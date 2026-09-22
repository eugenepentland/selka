//! `Option[T]`'s three intrinsic methods: their signatures, the payload-typed
//! default, the generic-body acceptance, and the rejections that name the fix.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "option.my", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code`, and return the first
/// diagnostic's message.
fn rejectedMessage(text: []const u8, code: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "option.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    return compilation.diagnostics.items[0].message;
}

// spec: OPTION-METHODS-1
test "option methods check the default against the payload type" {
    const message = try rejectedMessage(
        \\def main() -> int:
        \\    return int("4").unwrap_or("x")
    , "E_TYPE");
    try t.expectEqualStrings("`unwrap_or` default must be `int` (the Option's payload), found str", message);
    try accepted(
        \\def main() -> int:
        \\    return int("4").unwrap_or(7)
    );
    try accepted(
        \\def main() -> int:
        \\    value: Option[int] = None
        \\    return value.unwrap_or(7)
    );
}

// spec: OPTION-METHODS-2
test "option method rejections name the accepted spellings" {
    const unknown = try rejectedMessage(
        \\def main() -> int:
        \\    return int("4").missing()
    , "E_COLLECTION_METHOD");
    try t.expectEqualStrings("an Option receiver supports `unwrap_or(default)`, `is_none()` and `is_some()`", unknown);
    const extra = try rejectedMessage(
        \\def main() -> int:
        \\    return int("4").is_none(1)
    , "E_ARITY");
    try t.expectEqualStrings("`is_none` takes no arguments", extra);
    const missing = try rejectedMessage(
        \\def main() -> int:
        \\    return int("4").unwrap_or()
    , "E_ARITY");
    try t.expectEqualStrings("`unwrap_or` takes exactly one argument: `unwrap_or(default)`", missing);
}

// spec-case: OPTION-METHODS-2
test "option methods are accepted in generic bodies under a noalloc ceiling" {
    try accepted(
        \\def head[T: copy + storable](values: list[T]) -> Option[T]:
        \\    if len(values) == 0:
        \\        return None
        \\    return Some(values[0])
        \\
        \\
        \\def bounded[T: copy + storable](value: Option[T], fallback: T) -> T noalloc:
        \\    if value.is_none():
        \\        return fallback
        \\    return value.unwrap_or(fallback)
        \\
        \\
        \\def main() -> int:
        \\    return bounded(head([1, 2]), 7)
    );
}

// spec-case: OPTION-METHODS-2
test "an Option carrying a checked result still requires match" {
    const message = try rejectedMessage(
        \\def maybe() -> Option[Result[int, str]]:
        \\    return Some(Ok(1))
        \\
        \\
        \\def main() -> int:
        \\    if maybe().is_none():
        \\        return 0
        \\    return 1
    , "E_OPTION_TEST");
    try t.expectEqualStrings("use match for an Option carrying an owned value or checked Result", message);
}

// spec-case: OPTION-METHODS-2
test "an Option method checks in place wherever its value is used" {
    try accepted(
        \\def report(value: Option[int], out: Stream) -> None effects(output):
        \\    out.print(value.unwrap_or(7))
        \\    out.print(value.is_none())
        \\    out.print(value.is_some())
        \\
        \\
        \\def measured(value: Option[int]) -> int:
        \\    value.is_none()
        \\    value.is_some()
        \\    value.unwrap_or(4)
        \\    return value.unwrap_or(5) + int(value.is_some())
        \\
        \\
        \\def main() -> int:
        \\    return measured(Some(1))
    );
}

// spec-case: OPTION-METHODS-1
test "an integer-literal default adopts the payload type" {
    try accepted(
        \\def head[T: copy + storable](values: list[T]) -> Option[T]:
        \\    if len(values) == 0:
        \\        return None
        \\    return Some(values[0])
        \\
        \\
        \\def main() -> int:
        \\    narrow: list[u8] = [u8(5)]
        \\    return head(narrow).unwrap_or(7)
    );
}
