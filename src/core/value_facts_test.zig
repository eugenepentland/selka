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

const rewritten_list =
    \\def churn(size: int, rounds: int, seed: int) -> int:
    \\    if size < 2 or rounds < 1 or seed < 1 or seed > 1000000:
    \\        return -1
    \\    values = [(seed + j * 13) % 1009 for j in range(size)]
    \\    checksum = 0
    \\    for batch in range(rounds):
    \\        index = (seed + batch * 17) % size
    \\        values[index] = (values[index] + batch + 1) % 1000003
    \\        checksum = (checksum + values[index]) % 1000000007
    \\    return checksum
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(churn(64, 100, 7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-8
test "a list rewritten in a loop has the hull of its entry and its writes, and an index remainder of the list's length is in bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), rewritten_list);
    const body = text[std.mem.indexOf(u8, text, "fn churn").?..];
    // `if size < 2 or ...: return` says `size >= 2` afterwards, so `% size` is an unsigned remainder, below `size = len(values)`.
    try std.testing.expect(contains(body, "list_get.proven i64"));
    try std.testing.expect(contains(body, "list_set.proven list[i64]"));
    // The elements stay in [0, 1000002]: both remainders by constants are unsigned, and the checksum sum cannot overflow.
    try std.testing.expect(!contains(body, "floor_rem.exact"));
    try std.testing.expect(!contains(body, "list_get.exact"));
}

const either_or =
    \\def guarded(size: int, n: int) -> int:
    \\    if size < 2 or n < 1:
    \\        return 0
    \\    return 100 % size + n // size
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(guarded(5, 7))
    \\    return 0
    \\
;

// spec: NEW-CORE-FACTS-9
test "an or of comparisons is control flow, so what each failed test says about its operands holds after the if" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.factsText(arena.allocator(), either_or);
    const body = text[std.mem.indexOf(u8, text, "fn guarded").?..];
    try std.testing.expect(contains(body, "floor_rem.proven"));
    try std.testing.expect(contains(body, "floor_div.proven"));
    // No boolean phi joins the two comparisons.
    try std.testing.expect(!contains(body, "phi bool"));
}
