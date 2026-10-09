//! `Option[T]`'s three intrinsic methods: their signatures, the payload-typed
//! default, the generic-body acceptance, and the rejections that name the fix.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check a program that must be accepted.
fn accepted(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "option.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

/// Check a program that must be rejected with `code` and exactly `message`.
fn expectRejected(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "option.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}

// spec: OPTION-METHODS-1
test "option methods check the default against the payload type" {
    try expectRejected(
        \\func main() -> int:
        \\    return parse_int("4").unwrap_or("x")
    , "E_TYPE", "`unwrap_or` default must be `int` (the Option's payload), found str");
    try accepted(
        \\func main() -> int:
        \\    return parse_int("4").unwrap_or(7)
    );
    try accepted(
        \\func main() -> int:
        \\    mut value: int? = None
        \\    return value.unwrap_or(7)
    );
}

// spec: OPTION-METHODS-2
test "option method rejections name the accepted spellings" {
    try expectRejected(
        \\func main() -> int:
        \\    return parse_int("4").missing()
    , "E_COLLECTION_METHOD", "an Option receiver supports `unwrap_or(default)`, `is_none()` and `is_some()`");
    try expectRejected(
        \\func main() -> int:
        \\    return parse_int("4").is_none(1)
    , "E_ARITY", "`is_none` takes no arguments");
    try expectRejected(
        \\func main() -> int:
        \\    return parse_int("4").unwrap_or()
    , "E_ARITY", "`unwrap_or` takes exactly one argument: `unwrap_or(default)`");
}

// spec-case: OPTION-METHODS-2
test "option methods are accepted in generic bodies under a noalloc ceiling" {
    try accepted(
        \\func head[T: copy + storable](values: T[]) -> T?:
        \\    if len(values) == 0:
        \\        return None
        \\    return Some(values[0])
        \\
        \\
        \\func bounded[T: copy + storable](value: T?, fallback: T) -> T noalloc:
        \\    if value.is_none():
        \\        return fallback
        \\    return value.unwrap_or(fallback)
        \\
        \\
        \\func main() -> int:
        \\    return bounded(head([1, 2]), 7)
    );
}

// spec-case: OPTION-METHODS-2
test "an Option method checks in place wherever its value is used" {
    try accepted(
        \\func report(value: int?, out: Stream) -> Unit effects(output):
        \\    out.print(value.unwrap_or(7))
        \\    out.print(value.is_none())
        \\    out.print(value.is_some())
        \\
        \\
        \\func measured(value: int?) -> bool:
        \\    _ = value.is_none()
        \\    _ = value.is_some()
        \\    _ = value.unwrap_or(4)
        \\    return value.is_some() and value.unwrap_or(5) == 5
        \\
        \\
        \\func main() -> int:
        \\    if measured(Some(1)):
        \\        return 0
        \\    return 1
    );
}

// spec-case: OPTION-METHODS-1
test "an integer-literal default adopts the payload type" {
    try accepted(
        \\func head[T: copy + storable](values: T[]) -> T?:
        \\    if len(values) == 0:
        \\        return None
        \\    return Some(values[0])
        \\
        \\
        \\func main() -> int:
        \\    mut narrow: u8[] = [u8(5)]
        \\    mut adopted: u8 = head(narrow).unwrap_or(7)
        \\    return int(adopted)
    );
}
