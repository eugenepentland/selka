//! Loop duplication must not invent edges from outside a cloned region.
const std = @import("std");
const support = @import("test_support.zig");

const early_return =
    \\record Payload:
    \\    number: int
    \\    items: int[]
    \\
    \\
    \\enum Item:
    \\    payload(value: Payload)
    \\    empty
    \\
    \\
    \\func contents(items: Item[], index: int) -> int[]:
    \\    match items[index].copy():
    \\        case Item.payload(value=old):
    \\            return old.items.copy()
    \\        case Item.empty:
    \\            return []
    \\
    \\
    \\func iterator_alias(mut items: Item[], index: int) -> int:
    \\    for before in items.copy():
    \\        match items[index].copy():
    \\            case Item.payload(value=old):
    \\                mut fields = old.items.copy()
    \\                fields.append(2)
    \\                mut seen = 0
    \\                match before:
    \\                    case Item.payload(value=saved):
    \\                        seen = len(saved.items)
    \\                    case Item.empty:
    \\                        pass
    \\                items[index] = Item.payload(value=Payload(number=0, items=fields))
    \\                return seen
    \\            case Item.empty:
    \\                pass
    \\    return -1
    \\
    \\
    \\public func test_iteration_binding_stays_independent() -> bool:
    \\    mut items = [Item.payload(value=Payload(number=0, items=[1]))]
    \\    return iterator_alias(mut items, 0) == 1 and contents(items, 0) == [1, 2]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(test_iteration_binding_stays_independent())
    \\    mut empty: Item[] = []
    \\    out.print(iterator_alias(mut empty, 0))
    \\    return 0
;

// spec-case: NEW-CORE-UNSWITCH-1
// spec-case: NEW-CORE-VERSION-1
test "loop duplication preserves an inlined early return join with an outside predecessor" {
    inline for (.{ @import("passes.zig").Mode.trusted, @import("passes.zig").Mode.verify }) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var refusal: @import("build.zig").Refusal = .{};
        var module = try support.buildSource(a, early_return, &refusal);
        const result = try support.runPasses(a, &module, mode);
        const ran = try support.runOwned(a, &module, .{ .release = true, .verify = mode == .verify, .own = false, .analysis = support.analysis(&result) });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("True\n-1\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

const single_entry =
    \\func sum(mut xs: int[], n: int, kind: int) -> int:
    \\    xs.append(2)
    \\    mut total = 0
    \\    for i in range(n):
    \\        if kind == 0:
    \\            total += xs[i]
    \\        else:
    \\            total += xs[i] + 1
    \\    return total
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    out.print(sum(mut xs, 3, 1))
    \\    return 0
;

// spec-case: NEW-CORE-UNSWITCH-1
test "loop duplication still optimizes a single entry invariant branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, single_entry, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    try std.testing.expect(result.counts.unswitched > 0);
    const ran = try support.runOwned(a, &module, .{ .release = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("9\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}
