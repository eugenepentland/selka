//! Interpolated `f"..."` literals lower to str conversion and concatenation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-FSTRING-1
test "format strings interpolate expressions and convert every scalar" {
    try execute(
        \\def label(count: int, items: list[int]) -> str:
        \\    return f"total {count} of {len(items)} items"
        \\
        \\def main() -> int:
        \\    score = 0
        \\    if label(7, [1, 2, 3]) == "total 7 of 3 items":
        \\        score = score + 1
        \\    if f"{1 + 1}" == "2":
        \\        score = score + 2
        \\    if f"{True} {None} {1.5}" == "True None 1.5":
        \\        score = score + 4
        \\    name = "x"
        \\    if f"a\t{name}b" == "a\tx" + "b":
        \\        score = score + 8
        \\    if f"{f'{name}'}" == "x":
        \\        score = score + 16
        \\    return score
    , 31);
}

// spec: PY-FSTRING-2
test "doubled braces are literal and an empty format string is empty text" {
    try execute(
        \\def main() -> int:
        \\    score = 0
        \\    if f"{{literal}}" == "{literal}":
        \\        score = score + 1
        \\    if f"" == "":
        \\        score = score + 2
        \\    if f"no holes" == "no holes":
        \\        score = score + 4
        \\    return score
    , 7);
}

// spec-case: PY-FSTRING-2
test "malformed format strings and unconvertible values are rejected" {
    const header = "def main() -> int:\n    x = 1\n    _ = ";
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "f\"{}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x:.2f}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"a}b\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{1 2}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{[1, 2]}\"", .code = "E_TEXT_CONVERSION" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, case.body, "\n    return 0\n" });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

// spec-case: PY-FSTRING-1
test "an f prefix stays an ordinary identifier in legacy brace sources" {
    try execute(
        \\def main() -> i64:
        \\    f = 42
        \\    return f
    , 42);
}
