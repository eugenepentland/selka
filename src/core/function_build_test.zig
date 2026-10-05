//! S2-F source lowering and target specialization contracts.
const std = @import("std");
const support = @import("test_support.zig");

const known =
    \\def inc(x: int) -> int:
    \\    return x + 1
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    f = inc
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
    \\def first(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\
    \\def second(x: int) -> int:
    \\    return x * 5 + 11
    \\
    \\
    \\def total(n: int, seed: int) -> int:
    \\    f = first if seed % 2 == 0 else second
    \\    acc = 0
    \\    for i in range(n):
    \\        acc += f(i)
    \\    return acc
    \\
    \\
    \\def main(out: Stream) -> int:
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
}
