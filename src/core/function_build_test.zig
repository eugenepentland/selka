//! S2-F source lowering and target specialization contracts.
const std = @import("std");
const support = @import("test_support.zig");

const known =
    \\func inc(x: int) -> int:
    \\    return x + 1
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut f = inc
    \\    out.print(f(41))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-S2-IR-1
test "a known function value lowers to a direct call before release inlining" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), known);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 inc(41:i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call_indirect") == null);
}

const choice =
    \\func first(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\
    \\func second(x: int) -> int:
    \\    return x * 5 + 11
    \\
    \\
    \\func total(n: int, seed: int) -> int:
    \\    mut f = if (seed % 2 == 0) then (first) else (second)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += f(i)
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(total(4, 7))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-S2-IR-1
test "two constant callback targets become direct branches and unswitch the inner loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const before = try support.irText(arena.allocator(), choice);
    const after = try support.optimizedText(arena.allocator(), choice);
    try std.testing.expect(std.mem.indexOf(u8, before, "call_indirect") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call_indirect") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call i64 first") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "call i64 second") == null);
    try std.testing.expect(std.mem.indexOf(u8, after, "mul.proven i64") != null);
}

// spec-case: NEW-CORE-S2-IR-1
test "an escaped callback caller keeps unproved arithmetic as real source callees" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = try std.mem.replaceOwned(u8, a, choice, "total(4, 7)", "apply(total, 4, 7)");
    const source = try std.mem.concat(a, u8, &.{ entry, "\nfunc apply(f: func(int, int) -> int, n: int, seed: int) -> int:\n    return f(n, seed)\n" });
    const text = try support.optimizedText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 first") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 second") != null);
}

// spec-case: DEBUG-OPTIMIZE-1
test "loop optimization preserves early returns when the latch is unreachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source =
        \\func choose(xs: int[], flag: int) -> int:
        \\    for value in reversed(xs):
        \\        if flag > 0:
        \\            return value
        \\        return 0
        \\    return 7
        \\func main() -> int:
        \\    return choose([1, 2, 3], 1)
    ;
    const text = try support.optimizedText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, "ret") != null);
}
