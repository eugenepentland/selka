//! Diagnostics and traps of the Python expression idioms: comparison chains,
//! text ordering, stepped ranges, repetition, format specifications and
//! `round(x, n)`. Their accepted behaviour is tested in the language, in
//! `tests/lang/python_expressions.my` and `tests/lang/format_specs.my`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;

/// Check `source` and require a rejection carrying `code` whose message holds `needle`.
fn rejected(source: []const u8, code: []const u8, needle: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "expression-reject.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    for (c.diagnostics.items) |d| {
        if (std.mem.eql(u8, d.code, code) and std.mem.indexOf(u8, d.message, needle) != null) return;
    }
    for (c.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
    return t.expect(false);
}

/// Run `source` natively and require a trap carrying `code` whose report holds `needle`.
fn trapped(source: []const u8, code: []const u8, needle: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "expression-trap.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
    try t.expect(std.mem.indexOf(u8, result.stderr, needle) != null);
}

// spec-case: PY-RANGE-STEP-1
test "a literal zero range step is rejected with CPython's message in every range position" {
    try rejected("def main() -> int:\n    t = 0\n    for i in range(0, 10, 0):\n        t += i\n    return t\n", "E_RANGE_STEP", "range() arg 3 must not be zero");
    try rejected("def main() -> int:\n    return len([i for i in range(5, 0, 0)])\n", "E_RANGE_STEP", "must not be zero");
    try rejected("def main() -> int:\n    return len(list(range(1, 2, 0)))\n", "E_RANGE_STEP", "must not be zero");
    try rejected("def main() -> int:\n    t = 0\n    for i in range(0, 10, 1, 2):\n        t += i\n    return t\n", "E_ARITY", "start, end, step");
}

// spec-case: PY-RANGE-STEP-1
test "a zero runtime range step traps before the first iteration" {
    try trapped("def step() -> int:\n    return 0\n\ndef main() -> int:\n    t = 0\n    for i in range(0, 10, step()):\n        t += 1\n    return t\n", "R_ASSERT", "range() arg 3 must not be zero");
}

// spec-case: PY-REPEAT-1
test "a repetition needs one sequence and one integer count" {
    try rejected("def main() -> int:\n    return len(\"ab\" * 1.5)\n", "E_TYPE", "");
    try rejected("def main() -> int:\n    return len(\"ab\" * \"c\")\n", "E_TEXT_OPERATOR", "");
    try rejected("def main() -> int:\n    s = \"ab\"\n    s *= \"c\"\n    return len(s)\n", "E_TYPE", "");
}

// spec: PY-FSTRING-SPEC-2
test "a format specification its value cannot take is rejected when the program is checked" {
    try rejected("def main() -> int:\n    s = \"ab\"\n    return len(f\"{s:+}\")\n", "E_FORMAT_STRING", "Sign not allowed in string format specifier");
    try rejected("def main() -> int:\n    n = 3\n    return len(f\"{n:.2d}\")\n", "E_FORMAT_STRING", "Precision not allowed in integer format specifier");
    try rejected("def main() -> int:\n    x = 1.5\n    return len(f\"{x:d}\")\n", "E_FORMAT_STRING", "Unknown format code");
    try rejected("def main() -> int:\n    x = 1.5\n    return len(f\"{x:.f}\")\n", "E_FORMAT_STRING", "missing precision");
    try rejected("def main() -> int:\n    x = 1.5\n    w = 8\n    return len(f\"{x:{w}}\")\n", "E_FORMAT_STRING", "nested");
    try rejected("def main() -> int:\n    b = True\n    return len(f\"{b:>5}\")\n", "E_FORMAT_STRING", "convert this value first");
    try rejected("def main() -> int:\n    xs = [1]\n    return len(f\"{xs:>5}\")\n", "E_FORMAT_STRING", "convert this value first");
    try rejected("def main() -> int:\n    n = 3\n    return len(f\"{n:9999}\")\n", "E_FORMAT_STRING", "at most 4095");
}

// spec-case: PRELUDE-ROUND-2
test "round with a digit count requires a float and an integer count" {
    try rejected("def main() -> int:\n    return int(round(5, 2))\n", "E_PRELUDE_TYPE", "float argument");
    try rejected("def main() -> int:\n    return int(round(5.0, 2.0))\n", "E_PRELUDE_TYPE", "integer");
    try rejected("def main() -> int:\n    return int(round(5.0, 2, 1))\n", "E_ARITY", "round(value: float, ndigits: int)");
}
