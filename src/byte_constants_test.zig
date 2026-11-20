//! `ord("=")` and `b"="[0]` fold in a module constant and a literal match arm; anything else keeps its diagnostic.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// Check that `text` is refused with `code`, and return the first message the refusal carries.
fn refusal(arena: std.mem.Allocator, text: []const u8, code: []const u8) ![]const u8 {
    const report = try fixture.check(arena, text);
    const first = report.firstError() orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings(code, first.code);
    return first.message;
}

// spec-case: BYTE-CONSTANT-1
test "a constant folds ord of a one-byte literal and a literal indexed by an integer literal" {
    try fixture.run(t.allocator,
        \\const A: int = ord("a")
        \\const SECOND: int = b"xyz"[1]
        \\const SUM: int = A + SECOND
        \\
        \\
        \\func main() -> int:
        \\    return SUM - 218
        \\
    , 0 + 0);
}

// spec-case: BYTE-CONSTANT-2
test "a constant refuses a multi-byte literal, a computed argument and an index past the literal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const expression = "E_CONSTANT_EXPRESSION";
    _ = try refusal(a, "const A: int = ord(\"é\")\n\n\nfunc main() -> int:\n    return 0\n", expression);
    _ = try refusal(a, "const A: int = ord(\"ab\")\n\n\nfunc main() -> int:\n    return 0\n", expression);
    const indexed = try refusal(a, "const A: int = b\"ab\"[5]\n\n\nfunc main() -> int:\n    return 0\n", expression);
    try t.expect(std.mem.indexOf(u8, indexed, "select a byte of a literal") != null);
    _ = try refusal(a, "const N: int = 65\nconst A: int = ord(N)\n\n\nfunc main() -> int:\n    return 0\n", "E_UNKNOWN_SYMBOL");
}

// spec-case: BYTE-CONSTANT-3
test "a match arm takes ord of a one-byte literal, with alternatives and the matched integer type" {
    try fixture.run(t.allocator,
        \\func kind(ch: u8) -> int:
        \\    match ch:
        \\        case ord("+") | ord("-"):
        \\            return 1
        \\        case b"*"[0]:
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\
        \\func main() -> int:
        \\    return kind(43) * 20 + kind(45) * 10 + kind(42) + 10 + kind(1)
        \\
    , 42);
}

// spec-case: BYTE-CONSTANT-4
test "a match arm refuses a multi-byte literal, a repeated byte and a byte the matched type cannot hold" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const wide = try refusal(a, "func f(ch: int) -> int:\n    match ch:\n        case ord(\"é\"):\n            return 1\n        case _:\n            return 0\n\n\nfunc main() -> int:\n    return 0\n", "E_LITERAL_ARM");
    try t.expect(std.mem.indexOf(u8, wide, "one-byte literal") != null);
    _ = try refusal(a, "func f(ch: int) -> int:\n    match ch:\n        case ord(\"+\") | 43:\n            return 1\n        case _:\n            return 0\n\n\nfunc main() -> int:\n    return 0\n", "E_DUPLICATE_ARM");
    _ = try refusal(a, "func f(ch: i8) -> int:\n    match ch:\n        case b\"\\xff\"[0]:\n            return 1\n        case _:\n            return 0\n\n\nfunc main() -> int:\n    return 0\n", "E_LITERAL_ARM");
    _ = try refusal(a, "func f(ch: str) -> int:\n    match ch:\n        case ord(\"+\"):\n            return 1\n        case _:\n            return 0\n\n\nfunc main() -> int:\n    return 0\n", "E_LITERAL_ARM");
}
