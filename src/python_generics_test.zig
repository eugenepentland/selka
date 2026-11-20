//! Square-bracket type arguments on a generic function call in the Python surface.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "generic.selka", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "generic.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-GENERIC-2
test "square type arguments on a call keep record construction and reject wrong arity" {
    try reject(
        \\func identity[T](value: T) -> T:
        \\    return value
        \\
        \\func main() -> i64:
        \\    return identity[i64, bool](42)
    , "E_GENERIC_ARITY");
    try reject(
        \\func main() -> i64:
        \\    return missing[i64](42)
    , "E_UNKNOWN_TYPE");
}
