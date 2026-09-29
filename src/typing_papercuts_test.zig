//! Rejections and traps behind the typing papercuts: the discard name, `Option`
//! equality, float and method-carrying module constants, and float-to-integer
//! conversion. The accepted behaviour lives in `tests/lang`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Require `text` to fail checking with `code` as its first diagnostic.
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "papercut.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// Require `text` to check and `main` to return `expected`.
fn evaluates(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "papercut.my", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(expected, (try native.run(&compilation)).value);
}

// spec-case: DISCARD-NAME-1
test "a loop variable that is not the discard name still may not reuse an active name" {
    try reject(
        \\def main() -> int:
        \\    total = 0
        \\    for i in range(2):
        \\        for i in range(3):
        \\            total += 1
        \\    return total
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    total = 0
        \\    for total in range(2):
        \\        pass
        \\    return total
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    x = 1
        \\    ys = [x for x in [1, 2]]
        \\    return len(ys)
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    for a, a in enumerate([1]):
        \\        pass
        \\    return 0
    , "E_SHADOWING");
}

// spec-case: DISCARD-NAME-1
test "the discard name is not readable after its scope and a discarded assignment binds nothing" {
    try reject(
        \\def main() -> int:
        \\    for _ in range(2):
        \\        pass
        \\    return _
    , "E_UNKNOWN_NAME");
    try reject(
        \\def main() -> int:
        \\    _ = 5
        \\    return _
    , "E_UNKNOWN_NAME");
    try evaluates(
        \\def main() -> int:
        \\    _ = 5
        \\    for _ in range(2):
        \\        pass
        \\    return 3
    , 3);
}

// spec-case: OPTION-EQ-1
test "an equality with two operands that await a type, or a wrong payload, is still rejected" {
    try reject(
        \\def main() -> int:
        \\    if Some(1) == Some(1):
        \\        return 1
        \\    return 0
    , "E_OPTION_INFERENCE");
    try reject(
        \\def half(value: int) -> Option[int]:
        \\    return Some(value)
        \\
        \\
        \\def main() -> int:
        \\    if half(4) == Some("a"):
        \\        return 1
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def whole(value: int) -> int:
        \\    return value
        \\
        \\
        \\def main() -> int:
        \\    if whole(4) == Some(4):
        \\        return 1
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def main() -> int:
        \\    if Ok(1) == Ok(1):
        \\        return 1
        \\    return 0
    , "E_RESULT_INFERENCE");
}
