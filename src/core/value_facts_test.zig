//! S1 lane V facts: field intervals through records, list element hulls through writes, list
//! lengths through push and pop, and the verify-mode assertions that check each at run time.
const std = @import("std");
const support = @import("test_support.zig");

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

const record_fields =
    \\record P:
    \\    x: int
    \\    y: int
    \\    z: int
    \\
    \\
    \\def fields(n: int) -> int:
    \\    p = P(x=n % 5, y=7, z=n % 3)
    \\    p.y = p.y + 2
    \\    return p.x * 1000000000000 + p.z * 1000000000000 + p.y * 1000000000000
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(fields(7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-6
test "a record's field intervals flow through record_make, record_set and record_get, so field arithmetic is proven" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), record_fields);
    const body = text[std.mem.indexOf(u8, text, "fn fields").?..];
    // x < 5, z < 3 and y = 9 make every product and sum fit; only the remainders of the parameter keep their checks.
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "mul.proven"));
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "add.proven"));
    try std.testing.expect(!contains(body, "mul.exact"));
}

const list_facts =
    \\def literal() -> int:
    \\    xs = [10, 20, 30]
    \\    return xs[2] + xs[0] + len(xs)
    \\
    \\
    \\def hull() -> int:
    \\    xs = [1, 2, 3]
    \\    xs[1] = 100
    \\    xs[0] = 5
    \\    return xs[0] * 900000000000000000 + xs[1]
    \\
    \\
    \\def pops() -> int:
    \\    xs = [1, 2]
    \\    a = xs.pop()
    \\    b = xs.pop()
    \\    return a + b
    \\
    \\
    \\def parameter(xs: list[int], i: int) -> int:
    \\    ys = xs
    \\    return ys.pop() + ys[i]
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(literal(), hull(), pops(), parameter([1, 2, 3], 0))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-7
test "a list's length through new, push and pop and its element hull through element writes prove reads, writes and pops" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), list_facts);
    const literal = text[std.mem.indexOf(u8, text, "fn literal").?..std.mem.indexOf(u8, text, "fn hull").?];
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, literal, "list_get.proven"));
    const hull = text[std.mem.indexOf(u8, text, "fn hull").?..std.mem.indexOf(u8, text, "fn pops").?];
    // Two writes at known indices, hull [1, 100] after the first and [1, 100] with 5 after the second:
    // the product 5 * 9e17 overflows i64 only if the first element could exceed 10.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, hull, "list_set.proven"));
    const pops = text[std.mem.indexOf(u8, text, "fn pops").?..std.mem.indexOf(u8, text, "fn parameter").?];
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, pops, "list_pop.proven"));
    // A list parameter's length is unknown: its pop and its read keep their checks.
    const parameter = text[std.mem.indexOf(u8, text, "fn parameter").?..];
    try std.testing.expect(contains(parameter, "list_pop.exact"));
    try std.testing.expect(contains(parameter, "list_get.exact"));
}

// spec: NEW-CORE-VERIFY-3
test "a verify build asserts every list length interval and record field interval it relies on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lists = try support.verifyLlvmText(arena.allocator(), list_facts);
    try std.testing.expect(contains(lists, "list length [2, 2]"));
    try std.testing.expect(contains(lists, "list length [3, 3]"));
    const records = try support.verifyLlvmText(arena.allocator(), record_fields);
    // `y` is 7 + 2 = 9 in the record `record_set` built.
    try std.testing.expect(contains(records, "record field 1 range [9, 9]"));
    try std.testing.expect(contains(records, "record field 0 range [0, 4]"));
}
