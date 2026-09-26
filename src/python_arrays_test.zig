//! Contextual fixed-array and enum-indexed-table literals in the Python surface.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "array.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "array.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const enumerated =
    \\enum Status:
    \\    ok,
    \\    missing,
    \\    failed
    \\
;

// spec: PY-ARRAY-2
test "a fixed array literal checks its length and element types statically" {
    try reject(
        \\def main() -> i64:
        \\    fixed: [3]i64 = [4, 7]
        \\    return fixed[0]
    , "E_ARRAY_LENGTH");
    try reject(
        \\def main() -> i64:
        \\    fixed: [2]i64 = [4, True]
        \\    return fixed[0]
    , "E_TYPE");
}

// spec: PY-TABLE-2
test "an enum-indexed table literal requires every case exactly once from its own enum" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "{Status.ok: 1, Status.missing: 2}", .code = "E_INCOMPLETE_TABLE" },
        .{ .body = "{Status.ok: 1, Status.ok: 2, Status.failed: 3}", .code = "E_DUPLICATE_KEY" },
        .{ .body = "{1: 1, 2: 2, 3: 3}", .code = "E_TABLE_KEY" },
        .{ .body = "{Other.first: 1, Status.missing: 2, Status.failed: 3}", .code = "E_TABLE_KEY" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{
            enumerated,
            "enum Other:\n    first,\n    second\n\ndef codes() -> [Status]i64:\n    return ",
            case.body,
            "\n\ndef main() -> i64:\n    _ = codes()\n    return 0\n",
        });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

// spec-case: PY-DIV-1
test "truncating helpers check arity and defer to a binding of the same name" {
    try reject("def main() -> i64:\n    return divtrunc(1)\n", "E_ARITY");
    try reject("def main() -> i64:\n    return remtrunc(1, 2, 3)\n", "E_ARITY");
    try execute("def main() -> i64:\n    divtrunc = 2\n    return divtrunc * 21\n", 42);
    try execute("def divtrunc(a: i64, b: i64) -> i64:\n    return a + b\n\ndef main() -> i64:\n    return divtrunc(40, 2)\n", 42);
}

// spec: PY-CONVERSION-1
test "a conversion body accepts the Python record constructor" {
    try execute(
        \\record Source:
        \\    kept: i64
        \\    dropped: i64
        \\
        \\record Target:
        \\    kept: i64
        \\
        \\conversion def narrow(input: Source) -> Target:
        \\    _ = input.dropped
        \\    return Target(kept=input.kept)
        \\
        \\def main() -> i64:
        \\    return narrow(Source(kept=42, dropped=1)).kept
    , 42);
    try reject(
        \\record Source:
        \\    kept: i64
        \\
        \\record Target:
        \\    kept: i64
        \\
        \\def helper(value: i64) -> Target:
        \\    return Target(kept=value)
        \\
        \\conversion def narrow(input: Source) -> Target:
        \\    return helper(input.kept)
        \\
        \\def main() -> i64:
        \\    return narrow(Source(kept=42)).kept
    , "E_CONVERSION_BODY");
}
