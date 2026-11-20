//! Record replacements preserve projection provenance after tuple retirement.
const std = @import("std");
const language = @import("compiler.zig");
const origins = @import("origins.zig");
const values = @import("value_semantics.zig");
const typed = @import("typed.zig");

const source =
    \\record Pair:
    \\    items: int[]
    \\    count: int
    \\func touch(pair: Pair) -> int:
    \\    mut items = pair.items
    \\    append(mut items, 7)
    \\    return len(items)
    \\func main() -> int:
    \\    return 0
;

// spec-case: MUTATION-METADATA-1
test "A01 record temporaries preserve origin while named copies remain independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-origin.selka", source);
    try unit.check();
    const program = unit.program.?;
    const summaries = try a.alloc(origins.Summary, program.functions.len);
    const exported = try a.alloc(bool, program.functions.len);
    @memset(exported, false);
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const request: origins.Request = .{ .exported = exported, .src = unit.src, .syntax = unit.syntax.?, .sink = &sink, .summaries = summaries };
    try std.testing.expect(!try origins.check(a, program, request));
    try std.testing.expectEqualSlices(u16, &.{}, summaries[0].mutates);

    // Replace only the named independent home by a compiler temporary. This
    // controlled typed graph now forwards the borrowed field instead of copying
    // it, so its write must retain parameter zero's origin and be rejected.
    try makeTemporary(program.functions[0], "items");
    sink.items.clearRetainingCapacity();
    try std.testing.expect(try origins.check(a, program, request));
    try std.testing.expectEqualSlices(u16, &.{0}, summaries[0].mutates);
    try std.testing.expect(summaries[0].external);
}

// spec-case: VALUE-SEMANTICS-6
test "A01 record paths retain the whole RHS for source write diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-path.selka", source);
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
    for (program.nodes, 0..) |node, index| if (node.data == .field) return @fromBackingInt(index);
    return error.TestExpectedEqual;
}

// spec-case: TOOL-1
test "A01 record duplicate fingerprints distinguish ignored field positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "tuple-duplicates.selka",
        \\record Pair:
        \\    first: int
        \\    second: int
        \\func first(pair: Pair) -> int:
        \\    const value = pair.first
        \\    return value
        \\func second(pair: Pair) -> int:
        \\    const value = pair.second
        \\    return value
        \\func same_as_first(pair: Pair) -> int:
        \\    const value = pair.first
        \\    return value
        \\func main() -> int:
        \\    return first(Pair(first=1, second=2)) + second(Pair(first=1, second=2))
    );
    try unit.check();
    var analysis = try language.duplicates.discover(a, unit.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try std.testing.expectEqual(@as(usize, 1), analysis.groups.len);
    try std.testing.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ @fromBackingInt(0), @fromBackingInt(2) }, analysis.groups[0].members);
}
