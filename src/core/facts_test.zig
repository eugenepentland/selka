//! Fact pass tests: what a release build proves, and what it must not.
const std = @import("std");
const support = @import("test_support.zig");

const filled_then_read =
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = len(args) + 100
    \\    values = [(j * 7) % 1009 for j in range(n)]
    \\    total = 0
    \\    for j in range(n):
    \\        total += values[j] // 3
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-1
test "a list filled by a counted loop and read under the same bound needs no bounds, overflow or floor checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), filled_then_read);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "floor_div.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "floor_rem.proven i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "mul.proven i64") != null);
    // `n + 100`, both counter steps and the sum; what stays exact is in branches the facts showed dead.
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, text, "add.proven i64"));
    // The negative-index normalization `j < 0` is decided and folds to a constant branch.
    try std.testing.expect(std.mem.indexOf(u8, text, "branch 0:bool") != null);
}

const unknown_sources =
    \\def total(values: list[int], n: int) -> int:
    \\    acc = 0
    \\    for j in range(n):
    \\        acc += values[j]
    \\    return acc
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print(total([1, 2, 3], len(args)))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-2
test "a list parameter or an unbounded sum keeps its checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), unknown_sources);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64 param0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "add.exact i64") != null);
    // The counter's own step is still proven: it stops below a bound that fits the type.
    try std.testing.expect(std.mem.indexOf(u8, text, "add.proven i64") != null);
}
