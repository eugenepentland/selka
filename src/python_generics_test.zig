//! Square-bracket type arguments on a generic function call in the Python surface.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "generic.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "generic.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-GENERIC-1
test "square type arguments select a generic function instance in Python syntax" {
    try execute(
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\def main() -> i64:
        \\    return identity[i64](42)
    , 42);
}

// spec-case: PY-GENERIC-1
test "explicit and inferred type arguments reach the same generic instance" {
    try execute(
        \\class Pair[T]:
        \\    first: T
        \\    second: T
        \\
        \\def pick[T](values: Pair[T]) -> T:
        \\    return values.first
        \\
        \\def main() -> i64:
        \\    boxed = Pair[i64](first=40, second=2)
        \\    return pick[i64](boxed) + pick(Pair[i64](first=2, second=0))
    , 42);
}

// spec: PY-GENERIC-2
test "square type arguments on a call keep record construction and reject wrong arity" {
    try reject(
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\def main() -> i64:
        \\    return identity[i64, bool](42)
    , "E_GENERIC_ARITY");
    try reject(
        \\def main() -> i64:
        \\    return missing[i64](42)
    , "E_UNKNOWN_TYPE");
}
