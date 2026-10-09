//! Core IR builder tests: SSA shapes from checked source, the refusals of
//! unsupported constructs, and the copies `own.zig` puts in front of shared pushes.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");

const counted_loop =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
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
    \\func pick(a: int, b: int) -> bool:
    \\    return a > 0 and b > 0 or a == b
    \\
    \\
    \\func main(out: Stream) -> int:
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
    \\func parse(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func main(out: Stream) -> int:
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

const stored_view =
    \\func main(out: Stream) -> int:
    \\    mut table = {"a": 1}
    \\    mut holder = [table]
    \\    mut view = holder[0].values()
    \\    out.print(len(view))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-DICT-1
test "D2 rejects an interior stored dictionary view before core lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    const outcome = support.buildSource(arena.allocator(), stored_view, &refusal);
    try std.testing.expectError(error.SourceError, outcome);
    try std.testing.expectEqualStrings("", refusal.reason);
    try std.testing.expectEqual(@as(u32, 0), refusal.span);
}

const iterate_and_grow =
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    mut total = 0
    \\    for v in xs:
    \\        total += v
    \\        if total < 4:
    \\            xs.append(v)
    \\    out.print(total, len(xs))
    \\    return 0
    \\
;

const iterate_only =
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    mut total = 0
    \\    for v in xs:
    \\        total += v
    \\    out.print(total)
    \\    return 0
    \\
;

// spec: NEW-CORE-IR-3
// spec-case: NEW-CORE-ITERATION-1
test "a loop over a list place refreshes writes and guards changing length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const growing = try support.irText(arena.allocator(), iterate_and_grow);
    try std.testing.expect(std.mem.indexOf(u8, growing, "list_push") != null);
    try std.testing.expect(std.mem.indexOf(u8, growing, "unreachable") != null);
    const text = try support.irText(arena.allocator(), iterate_only);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_get.exact i64") != null);
}

const mutating_helper =
    \\func grow(mut xs: int[]) -> Unit:
    \\    xs.append(4)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    grow(mut xs)
    \\    out.print(len(xs))
    \\    return 0
    \\
;

// spec: NEW-CORE-MUT-1
test "a mut parameter is passed by value and returned: the caller writes the callee's final value back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(), mutating_helper);
    // `grow` returns the list it ends with, and `main` continues with that value.
    try std.testing.expect(std.mem.indexOf(u8, text, "fn grow(list[i64]) -> list[i64]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%9 = call list[i64] grow(%8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "%10 = list_len u64 %9") != null);
}

const aliased_pushes =
    \\func grow(xs: int[]) -> int:
    \\    mut copy = xs
    \\    copy.append(1)
    \\    return len(copy)
    \\
    \\
    \\func fill(n: int) -> int:
    \\    mut xs = [0]
    \\    for j in range(n):
    \\        xs.append(j)
    \\    return len(xs)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(grow([1, 2]) + fill(3))
    \\    return 0
    \\
;

// spec-case: NEW-CORE-OWN-1
test "a push onto a parameter's list copies it first; a push onto a list the function owns alone does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.ownedText(arena.allocator(), aliased_pushes);
    // Only `grow`'s push copies (its list is borrowed): `fill`'s list is fresh, and its loop
    // phi is dead after each push, so neither copies nor tests its count.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "list_copy list[i64] param0"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "list_copy"));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, text, "is_unique"));
}
