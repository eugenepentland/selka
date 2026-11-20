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

/// Make `name` a compiler-only local, so its store forwards the value's origins
/// instead of receiving its own copy.
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
    var unit = try language.Compilation.init(a, "selection-order.selka",
        \\func first(out: Stream) -> str:
        \\    print(out, 1)
        \\    return "z"
        \\func second(out: Stream) -> str:
        \\    print(out, 2)
        \\    return "a"
        \\func choose(out: Stream) -> str:
        \\    return copy(min(first(out), second(out)))
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
    var unit = try language.Compilation.init(arena.allocator(), "selection-effects.selka",
        \\@noalloc
        \\func extrema(a: str, b: str) -> bool:
        \\    return min(a, b) == a and max(a, b) == b
        \\@noalloc
        \\func fallback(value: int[]?, other: int[]) -> int:
        \\    return len(value.unwrap_or(other))
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
}

// spec-case: MUTATION-METADATA-1
// spec-case: VALUE-SEMANTICS-6
test "A04 optional selection preserves both writable source origins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A borrowed selection cannot be held (`E_SINGLE_OWNER_BORROW`), so the
    // store makes an explicit `copy`; the copy owns its slots, so the write
    // through it reaches neither source.
    var unit = try language.Compilation.init(a, "selection-origins.selka",
        \\func select(value: int[]?, fallback: int[]) -> int:
        \\    mut chosen = copy(value.unwrap_or(fallback))
        \\    append(mut chosen, 7)
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
    // An ordinary named home owns an independent value.
    try std.testing.expect(!try origins.check(a, program, request));
    try std.testing.expectEqualSlices(u16, &.{}, summaries[0].mutates);
    // A compiler-only receiver forwards the store instead of copying it again,
    // and the copy has already severed both roots, so nothing is published.
    try temporary(program.functions[0], "chosen");
    sink.items.clearRetainingCapacity();
    try std.testing.expect(!try origins.check(a, program, request));
    try std.testing.expectEqualSlices(u16, &.{}, summaries[0].mutates);
    try std.testing.expect(!summaries[0].external);
    // What the selection itself is remains a place, read once, whichever
    // operand it came from.
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
    var unit = try language.Compilation.init(a, "selection-duplicates.selka",
        \\func low(a: str, b: str) -> str:
        \\    return copy(min(a, b))
        \\func high(a: str, b: str) -> str:
        \\    return copy(max(a, b))
        \\func reverse(a: str, b: str) -> str:
        \\    return copy(min(b, a))
        \\func low_again(a: str, b: str) -> str:
        \\    return copy(min(a, b))
        \\func main() -> int:
        \\    return 0
    );
    try unit.check();
    var analysis = try language.duplicates.discover(a, unit.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try std.testing.expectEqual(@as(usize, 1), analysis.groups.len);
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ @fromBackingInt(0), @fromBackingInt(3) }, analysis.groups[0].members);
}
