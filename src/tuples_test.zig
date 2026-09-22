//! Tuple diagnostics, identity and surface spelling.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
/// Source name every fixture in this file is checked under.
const unit_name = "tuples.my";

/// Check one unit and require it to be accepted.
fn accepts(source: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try compilation.check();
}

/// Check one unit and require its first diagnostic to carry `code`.
fn rejects(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// Check one unit and return an owned copy of its first diagnostic message.
fn message(source: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    return t.allocator.dupe(u8, compilation.diagnostics.items[0].message);
}

// spec: TUPLE-1
test "a tuple type is one interned record with positional fields and a source spelling" {
    // The same element list written twice is one type: both parameters accept
    // each other's value with no conversion at all.
    try accepts(
        \\def pair_left(p: tuple[int, str]) -> str:
        \\    return "x"
        \\
        \\
        \\def pair_right(p: tuple[int, str]) -> str:
        \\    return pair_left(p)
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    );
    // A mismatched element list is the ordinary expected/found message, in the
    // source spelling of both types.
    const found = try message(
        \\def pair(p: tuple[int, str]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return pair(7)
        \\
    );
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "expected tuple[int, str], found int") != null);
}

test "scratch probe" {
    try rejects(
        \\def g(p: tuple[int, str]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    , "E_UNKNOWN_TYPE");
}

// spec-case: TUPLE-1
test "a tuple spelling outside two to eight elements is E_TUPLE_ARITY at the spelling" {
    try rejects(
        \\def f(p: tuple[int]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    try rejects(
        \\def f(p: tuple[int, str, int, str, int, str, int, str, int]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    // Nested element types keep the source spelling too.
    const nested = try message(
        \\def f(p: tuple[list[int], str]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return f(1)
        \\
    );
    defer t.allocator.free(nested);
    try t.expect(std.mem.indexOf(u8, nested, "expected tuple[list[int], str], found int") != null);
}
