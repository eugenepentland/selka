//! `Option[T]`'s one intrinsic method: its signature, the payload-typed
//! default, the generic-body acceptance, and the rejections that name the fix.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check a program that must be accepted with no diagnostic.
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

// `value.unwrap_or(default)` with an aggregate payload (float and f32 are records too) must not claim the two operands
// of its borrowed selection (K4F-PRELUDE-1; the prelude spelling `unwrap_or(value, default)` it was found on is refused
// since W13-S5, and the method is checked by the same `checkOptionMethod`).
test "unwrap_or checks scalar and aggregate payloads in place" {
    try accepted(
        \\func pick() -> float:
        \\    const present: float? = Some(1.5)
        \\    return present.unwrap_or(0.0)
        \\
        \\
        \\func main() -> int:
        \\    return int(pick())
    );
    try accepted(
        \\func pick() -> f32:
        \\    const present: f32? = Some(1.5)
        \\    return present.unwrap_or(0.25)
        \\
        \\
        \\func main() -> int:
        \\    return int(pick())
    );
    try accepted(
        \\func count() -> int:
        \\    const present: int[]? = Some([1, 2])
        \\    return len(present.unwrap_or([7]))
        \\
        \\
        \\func main() -> int:
        \\    return count()
    );
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
    , "E_COLLECTION_METHOD", "an Option receiver supports `unwrap_or(default)`; test presence with `value is None` or `value is not None`");
    try expectRejected(
        \\func main() -> int:
        \\    return parse_int("4").unwrap_or(1, 2)
    , "E_ARITY", "`unwrap_or` takes exactly one argument: `unwrap_or(default)`");
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
        \\@noalloc
        \\func bounded[T: copy + storable](value: T?, fallback: T) -> T:
        \\    if value is None:
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
        \\func report(value: int?, out: Stream) -> Unit:
        \\    print(out, value.unwrap_or(7))
        \\    print(out, value is None)
        \\    print(out, value is not None)
        \\
        \\
        \\func measured(value: int?) -> bool:
        \\    _ = value is None
        \\    _ = value is not None
        \\    _ = value.unwrap_or(4)
        \\    return value is not None and value.unwrap_or(5) == 5
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

// W13-Q1: options keep the method; the prelude spelling `unwrap_or(x, d)` is refused, with the method as its repair.
test "the bare unwrap_or(x, d) is refused with the method as its repair (W13-S5)" {
    var compilation = try language.Compilation.init(t.allocator, "option.selka",
        \\func main() -> int:
        \\    mut found: int? = Some(4)
        \\    return unwrap_or(found, 9)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const refusal = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", refusal.code);
    try t.expectEqualStrings("`unwrap_or(value, default)` is a second spelling and was removed; write `found.unwrap_or(9)`", refusal.message);
    try t.expectEqualStrings("found.unwrap_or(", refusal.provenance.fix.?.edit.text);
}
