//! Core IR builder tests: SSA shapes from checked source.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");

const counted_loop =
    \\def total(n: int) -> int:
    \\    acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(total(4))
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-1
test "a counted loop becomes header, body, latch and exit blocks with phis for its carried locals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), counted_loop);
    try std.testing.expectEqualStrings(
        \\fn main(cap) -> i64
        \\b0:
        \\  %2 = call i64 total(4:i64)
        \\  print param0, %2
        \\  ret 0:i64
        \\fn total(i64) -> i64
        \\b0:
        \\  jump b1
        \\b1: ; preds b0 b3
        \\  %4 = phi i64 0:i64, %14
        \\  %8 = phi i64 0:i64, %11
        \\  %6 = cmp.lt bool %4, param0
        \\  branch %6, b2, b4
        \\b2: ; preds b1
        \\  %10 = mul.exact i64 %4, 2:i64
        \\  %11 = add.exact i64 %8, %10
        \\  jump b3
        \\b3: ; preds b2
        \\  %14 = add.exact i64 %4, 1:i64
        \\  jump b1
        \\b4: ; preds b1
        \\  ret %8
        \\
    , text);
}

const short_circuit =
    \\def pick(a: int, b: int) -> bool:
    \\    return a > 0 and b > 0 or a == b
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(pick(1, 2))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-IR-1
test "and/or evaluate their right operand in its own block and join with a phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), short_circuit);
    try std.testing.expect(std.mem.indexOf(u8, text, "phi bool") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "phi bool"));
    try std.testing.expect(std.mem.indexOf(u8, text, "cmp.eq bool param0, param1") != null);
}

const option_match =
    \\def parse(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(parse("12"))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-IR-1
test "a match on an option tests the tag and binds the payload in its arm" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), option_match);
    try std.testing.expect(std.mem.indexOf(u8, text, "str_parse_int option[i64] param0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "union_tag u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "union_payload i64 tag1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "call i64 parse(str0)") != null);
}

const unsupported =
    \\def main(out: Stream) -> int:
    \\    table = {"a": 1}
    \\    out.print(table["a"])
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-2
test "a construct the new core does not support stops the build with a reason and position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const outcome = support.buildSource(arena.allocator(), unsupported, &refusal);
    try std.testing.expectError(error.Unsupported, outcome);
    try std.testing.expect(refusal.reason.len != 0);
    try std.testing.expect(refusal.span > 0);
}
