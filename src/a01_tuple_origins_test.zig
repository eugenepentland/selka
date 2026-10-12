//! Complete tuple staging preserves the prior projection's source provenance.
const std = @import("std");
const language = @import("compiler.zig");
const origins = @import("origins.zig");
const values = @import("value_semantics.zig");
const typed = @import("typed.zig");

const source =
    \\func touch(pair: tuple[int[], int]) -> int:
    \\    mut items, _ = pair
    \\    items.append(7)
    \\    return len(items)
    \\func main() -> int:
    \\    return 0
;

// spec-case: MUTATION-METADATA-1
test "A01 tuple staged temporaries preserve origin while named copies remain independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-origin.my", source);
    try unit.check();
    const program = unit.program.?;
    const summaries = try a.alloc(origins.Summary, program.functions.len);
    const exported = try a.alloc(bool, program.functions.len);
    @memset(exported, false);
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const request: origins.Request = .{ .exported = exported, .src = unit.src, .syntax = unit.syntax.?, .sink = &sink, .summaries = summaries };
    try std.testing.expect(!try origins.check(a, program, request));
    try std.testing.expectEqual(@as(origins.Mask, 0), summaries[0].mutates);

    // Replace only the named independent home by a compiler temporary. This
    // controlled typed graph now forwards the borrowed field instead of copying
    // it, so its write must retain parameter zero's origin and be rejected.
    try makeTemporary(program.functions[0], "items");
    sink.items.clearRetainingCapacity();
    try std.testing.expect(try origins.check(a, program, request));
    try std.testing.expectEqual(@as(origins.Mask, 1), summaries[0].mutates);
    try std.testing.expect(summaries[0].external);
}

// spec-case: VALUE-SEMANTICS-6
test "A01 tuple staged paths retain the whole RHS for source write diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-path.my", source);
    try unit.check();
    const program = unit.program.?;
    const facts = try values.Facts.collect(a, program, program.functions[0]);
    try std.testing.expect(facts.rootedAt(try stagedRead(program), @fromBackingInt(0)));
}

fn makeTemporary(function: typed.Function, name: []const u8) !void {
    for (@constCast(function.scope.locals)) |*local| if (std.mem.eql(u8, local.name, name)) {
        local.usage.temporary = true;
        return;
    };
    return error.TestExpectedEqual;
}

fn stagedRead(program: typed.Program) !typed.NodeId {
    var staged: ?typed.LocalId = null;
    for (program.statements) |statement| if (statement.data == .initialize) {
        if (statement.data.initialize.unpack) |fields| staged = fields[0];
    };
    const slot = staged orelse return error.TestExpectedEqual;
    for (program.nodes, 0..) |node, index| if (node.data == .local and node.data.local == slot) return @fromBackingInt(index);
    return error.TestExpectedEqual;
}

// spec-case: TOOL-1
test "A01 tuple staged duplicate fingerprints distinguish ignored field positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-duplicates.my",
        \\func first(pair: tuple[int, int]) -> int:
        \\    const value, _ = pair
        \\    return value
        \\func second(pair: tuple[int, int]) -> int:
        \\    const _, value = pair
        \\    return value
        \\func same_as_first(pair: tuple[int, int]) -> int:
        \\    const value, _ = pair
        \\    return value
        \\func main() -> int:
        \\    return first((1, 2)) + second((1, 2))
    );
    try unit.check();
    var analysis = try language.duplicates.discover(a, unit.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try std.testing.expectEqual(@as(usize, 1), analysis.groups.len);
    try std.testing.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ @fromBackingInt(0), @fromBackingInt(2) }, analysis.groups[0].members);
}
