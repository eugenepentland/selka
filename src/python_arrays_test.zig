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

// spec: PY-ARRAY-1
test "a list literal builds a fixed array wherever the context declares one" {
    try execute(
        \\def total(values: [3]i64) -> i64:
        \\    return values[0] + values[1] + values[2]
        \\
        \\class Row:
        \\    cells: [2]i64
        \\
        \\def pair() -> [2]i64:
        \\    return [1, 2]
        \\
        \\def main() -> i64:
        \\    fixed: [3]i64 = [4, 7, 9]
        \\    row = Row(cells=[10, 11])
        \\    return total(fixed) + total([1, 2, 3]) + row.cells[1] + pair()[0] + 4
    , 42);
}

// spec-case: PY-ARRAY-1
test "a list literal without an array context still builds a managed list" {
    try execute(
        \\def main() -> i64:
        \\    values = [40, 2]
        \\    values.append(0)
        \\    return values[0] + values[1] + len(values) - 3
    , 42);
}

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

// spec: PY-TABLE-1
test "a dict literal builds an enum-indexed table from qualified case keys" {
    const text = try std.mem.concat(t.allocator, u8, &.{
        enumerated,
        \\def codes() -> [Status]i64:
        \\    return {Status.failed: 500, Status.ok: 200, Status.missing: 404}
        \\
        \\def main() -> i64:
        \\    table = codes()
        \\    return table[Status.ok] - table[Status.missing] + 246
    });
    defer t.allocator.free(text);
    try execute(text, 42);
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

// spec: PY-DIV-1
test "divtrunc and remtrunc round toward zero beside flooring // and %" {
    try execute(
        \\def main() -> i64:
        \\    a = -7
        \\    b = 2
        \\    return (a // b) * 1000 + divtrunc(a, b) * 100 + (a % b) * 10 + remtrunc(a, b)
    , -4291);
    try execute(
        \\def main() -> i64:
        \\    wide: u64 = 18446744073709551615
        \\    return i64(divtrunc(wide, 3u64) - remtrunc(wide, 3u64)) - 6148914691236517163
    , 42);
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
        \\class Source:
        \\    kept: i64
        \\    dropped: i64
        \\
        \\class Target:
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
        \\class Source:
        \\    kept: i64
        \\
        \\class Target:
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
