//! `case a | b:` and `case text(value) | code(value):` over an enum, and the rest marker `case atom(..):`: what they
//! refuse and how.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

const header =
    \\enum Node:
    \\    text(value: str)
    \\    code(value: str)
    \\    number(value: int)
    \\    pair(left: int, right: int)
    \\    leaf
    \\    blank
    \\
    \\
;

/// The first refusal of `header` followed by a function `f` whose match has `arms`, as (code, message).
fn refused(arena: std.mem.Allocator, arms: []const u8) !struct { []const u8, []const u8 } {
    const text = try std.fmt.allocPrint(arena, "{s}func f(node: Node) -> int:\n    match node:\n{s}\n\n\nfunc main() -> int:\n    return 0\n", .{ header, arms });
    const report = try fixture.check(arena, text);
    const first = report.firstError() orelse return error.TestUnexpectedResult;
    return .{ first.code, first.message };
}

// spec-case: VARIANT-ALTERNATIVES-1
test "alternatives that bind different names, or the same name with different types, are refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names = try refused(a, "        case text(value) | pair(left=left, right=_):\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_ALTERNATIVE_BINDINGS", names[0]);
    try t.expect(std.mem.indexOf(u8, names[1], "binds the same names") != null);
    const types = try refused(a, "        case text(value) | number(value):\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_ALTERNATIVE_BINDINGS", types[0]);
    try t.expect(std.mem.indexOf(u8, types[1], "binds `value` as `int`, but the first binds it as `str`") != null);
    const payload = try refused(a, "        case leaf | text(value):\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_ALTERNATIVE_BINDINGS", payload[0]);
}

// spec-case: VARIANT-ALTERNATIVES-2
test "a repeated alternative is a duplicate arm and a list does not make a match exhaustive on its own" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const twice = try refused(a, "        case leaf | leaf:\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_DUPLICATE_ARM", twice[0]);
    const across = try refused(a, "        case text(value) | code(value):\n            return 1\n        case text(value):\n            return 2\n        case _:\n            return 0");
    try t.expectEqualStrings("E_DUPLICATE_ARM", across[0]);
    const missing = try refused(a, "        case text(value) | code(value):\n            return 1\n        case leaf | blank:\n            return 0");
    try t.expectEqualStrings("E_INCOMPLETE_MATCH", missing[0]);
}

// spec-case: VARIANT-ALTERNATIVES-3
test "under match mut the alternatives of an arm bind the same fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text =
        \\enum Counter:
        \\    up(n: int)
        \\    other(m: int, extra: int)
        \\    idle
        \\
        \\
        \\func bump(mut counter: Counter):
        \\    match mut counter:
        \\        case up(n) | other(extra=n, m=_):
        \\            n += 1
        \\        case idle:
        \\            pass
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const report = try fixture.check(arena.allocator(), text);
    const first = report.firstError() orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("E_ALTERNATIVE_BINDINGS", first.code);
    try t.expect(std.mem.indexOf(u8, first.message, "match mut") != null);
}

// spec-case: VARIANT-ALTERNATIVES-4
test "the rest marker ends a pattern and belongs to a case that has fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const last = try refused(a, "        case pair(.., left):\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_SYNTAX", last[0]);
    try t.expect(std.mem.indexOf(u8, last[1], "ends a pattern") != null);
    const none = try refused(a, "        case leaf(..):\n            return 1\n        case _:\n            return 0");
    try t.expectEqualStrings("E_PATTERN_PAYLOAD", none[0]);
    try t.expect(std.mem.indexOf(u8, none[1], "no fields for `..` to ignore") != null);
}

// spec-case: VARIANT-ALTERNATIVES-5
test "a list of constants in an integer match is still constants, and a list of cases runs" {
    try fixture.run(t.allocator,
        \\const LOW: int = 1
        \\const HIGH: int = 9
        \\
        \\
        \\enum Mode:
        \\    fast
        \\    slow
        \\    off
        \\
        \\
        \\func band(n: int) -> int:
        \\    match n:
        \\        case LOW | HIGH:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\
        \\func speed(mode: Mode) -> int:
        \\    match mode:
        \\        case fast | slow:
        \\            return 10
        \\        case off:
        \\            return 0
        \\
        \\
        \\func main() -> int:
        \\    return band(9) + band(5) + speed(Mode.slow) + speed(Mode.off) + 31
        \\
    , 42);
}
