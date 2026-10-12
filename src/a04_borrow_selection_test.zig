//! Distinct-input selections retain effect order and both source origins.
const std = @import("std");
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const origins = @import("origins.zig");
const values = @import("value_semantics.zig");

fn callOrder(a: std.mem.Allocator, program: typed.Program, function: usize) ![]const typed.FunctionId {
    var walker = try walk.Walker.init(a, program, program.functions[function].scope.body);
    defer walker.deinit();
    var calls: std.ArrayList(typed.FunctionId) = .empty;
    while (try walker.next()) |item| if (item == .expression) {
        const node = program.nodes[@backingInt(item.expression)];
        if (node.data == .call) try calls.append(a, node.data.call.function);
    };
    return calls.items;
}

fn temporary(function: typed.Function, name: []const u8) !void {
    for (@constCast(function.scope.locals)) |*local| if (std.mem.eql(u8, local.name, name)) {
        local.usage.temporary = true;
        return;
    };
    return error.TestExpectedEqual;
}

fn selectionNodes(a: std.mem.Allocator, program: typed.Program) ![]const typed.NodeId {
    var result: std.ArrayList(typed.NodeId) = .empty;
    for (program.nodes, 0..) |node, index| if (node.data == .borrow_selection)
        try result.append(a, @fromBackingInt(index));
    return result.items;
}

// spec-case: PRELUDE-EXTREME-2
test "A04 borrowed selections visit evaluated operands once in source order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "selection-order.my",
        \\func first(out: Stream) -> str:
        \\    out.print(1)
        \\    return "z"
        \\func second(out: Stream) -> str:
        \\    out.print(2)
        \\    return "a"
        \\func choose(out: Stream) -> str:
        \\    return min(first(out), second(out))
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    const program = unit.program.?;
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ @fromBackingInt(0), @fromBackingInt(1) }, try callOrder(a, program, 2));
}

// spec-case: PRELUDE-EXTREME-1
// spec-case: OPTION-METHODS-1
test "A04 borrowed selection reads preserve noalloc contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "selection-effects.my",
        \\func extrema(a: str, b: str) -> bool noalloc:
        \\    return min(a, b) == a and max(a, b) == b
        \\func fallback(value: int[]?, other: int[]) -> int noalloc:
        \\    return len(value.unwrap_or(other))
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    try std.testing.expectEqual(@as(@TypeOf(unit.program.?.functions[0].policy.effects), 0), unit.program.?.functions[0].policy.effects);
    try std.testing.expectEqual(@as(@TypeOf(unit.program.?.functions[1].policy.effects), 0), unit.program.?.functions[1].policy.effects);
}

// spec-case: MUTATION-METADATA-1
// spec-case: VALUE-SEMANTICS-6
test "A04 optional selection preserves both writable source origins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "selection-origins.my",
        \\func select(value: int[]?, fallback: int[]) -> int:
        \\    mut chosen = value.unwrap_or(fallback)
        \\    chosen.append(7)
        \\    return len(chosen)
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    const program = unit.program.?;
    const summaries = try a.alloc(origins.Summary, program.functions.len);
    const exported = try a.alloc(bool, program.functions.len);
    @memset(exported, false);
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const request: origins.Request = .{ .exported = exported, .src = unit.src, .syntax = unit.syntax.?, .sink = &sink, .summaries = summaries };
    try std.testing.expect(!try origins.check(a, program, request));
    try std.testing.expectEqual(@as(origins.Mask, 0), summaries[0].mutates);
    // Ordinary named homes own independent values. A compiler-only receiver
    // instead forwards the selection: its mutation must retain both roots.
    try temporary(program.functions[0], "chosen");
    sink.items.clearRetainingCapacity();
    try std.testing.expect(try origins.check(a, program, request));
    try std.testing.expectEqual(@as(origins.Mask, 3), summaries[0].mutates);
    try std.testing.expect(summaries[0].external);
    const facts = try values.Facts.collect(a, program, program.functions[0]);
    const selections = try selectionNodes(a, program);
    for (selections) |id| try std.testing.expectEqual(values.Source.place, facts.classify(id, null));
    try std.testing.expectEqual(@as(usize, 1), selections.len);
}

// spec-case: TOOL-1
test "A04 selection duplicate fingerprints distinguish direction and operand order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "selection-duplicates.my",
        \\func low(a: str, b: str) -> str:
        \\    return min(a, b)
        \\func high(a: str, b: str) -> str:
        \\    return max(a, b)
        \\func reverse(a: str, b: str) -> str:
        \\    return min(b, a)
        \\func low_again(a: str, b: str) -> str:
        \\    return min(a, b)
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    var analysis = try language.duplicates.discover(a, unit.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try std.testing.expectEqual(@as(usize, 1), analysis.groups.len);
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ @fromBackingInt(0), @fromBackingInt(3) }, analysis.groups[0].members);
}
