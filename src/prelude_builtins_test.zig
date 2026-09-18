//! Prelude builtins reachable by their ordinary Python name without an import.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn run(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude.my", text);
    defer compilation.deinit();
    const result = native.runWithOptions(&compilation, .{ .gc_stress = true }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

fn trapped(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude-trap.my", text);
    defer compilation.deinit();
    const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude-invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

fn rejectMigration(text: []const u8, replacement: []const u8, token: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "removed.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", item.code);
    try t.expectEqualStrings(token, compilation.src.text(item.span));
    try t.expect(std.mem.indexOf(u8, item.message, replacement) != null);
}

fn rejectRemovedLexicalNames() !void {
    const cases = [_]struct { spelling: []const u8, replacement: []const u8 }{
        .{ .spelling = "filesystem_cap", .replacement = "Filesystem" },
        .{ .spelling = "network_cap", .replacement = "Network" },
        .{ .spelling = "clock_cap", .replacement = "Clock" },
        .{ .spelling = "random_cap", .replacement = "Entropy" },
        .{ .spelling = "environment_cap", .replacement = "Environment" },
        .{ .spelling = "codec_encode", .replacement = "codec" },
        .{ .spelling = "codec_decode", .replacement = "codec" },
        .{ .spelling = "f64_add", .replacement = "float" },
        .{ .spelling = "f64_sub", .replacement = "float" },
        .{ .spelling = "f64_mul", .replacement = "float" },
        .{ .spelling = "f64_div", .replacement = "float" },
        .{ .spelling = "f64_eq", .replacement = "float" },
        .{ .spelling = "f64_lt", .replacement = "float" },
        .{ .spelling = "f64_le", .replacement = "float" },
        .{ .spelling = "f64_sqrt", .replacement = "sqrt" },
        .{ .spelling = "f64_floor", .replacement = "floor" },
        .{ .spelling = "f64_ceil", .replacement = "ceil" },
        .{ .spelling = "f64_trunc", .replacement = "trunc" },
        .{ .spelling = "f64_abs", .replacement = "abs" },
        .{ .spelling = "f64_neg", .replacement = "float" },
        .{ .spelling = "f64_from_u64", .replacement = "float" },
        .{ .spelling = "f64_to_u64", .replacement = "int" },
    };
    for (cases) |case| try rejectMigration(case.spelling, case.replacement, case.spelling);
}

// spec: PRELUDE-FOLD-1
test "sum adds a list of ints or floats and rejects other element types" {
    try run("def main() -> int:\n    return sum([1, 2, 3])\n", 6);
    try run("def main() -> int:\n    return sum([])\n", 0);
    try run("def main() -> int:\n    xs: list[int] = []\n    return sum(xs)\n", 0);
    try run("def main() -> int:\n    return int(sum([0.5, 1.25]) * 2.0)\n", 3);
    try reject("def main() -> int:\n    return sum([True])\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-EXTREME-1
test "min and max accept a list or two scalars and trap on an empty list" {
    try run("def main() -> int:\n    return min([3, 1, 2])\n", 1);
    try run("def main() -> int:\n    return max([3, 1, 2])\n", 3);
    try run("def main() -> int:\n    return min(4, 2) + max(4, 2)\n", 6);
    try run("def main() -> int:\n    if min([1.5, 0.5]) == 0.5:\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    if min([\"pear\", \"apple\"]) == \"apple\":\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    if min(1.5, 0.5) == 0.5 and max(1.5, 0.5) == 1.5:\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    if max(\"pear\", \"apple\") == \"pear\":\n        return 1\n    return 0\n", 1);
    try trapped("def main() -> int:\n    xs: list[int] = []\n    return min(xs)\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    return min([])\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    return max([])\n", "R_LIST_BOUNDS");
    try reject("def main() -> int:\n    return min([1], [2])\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-SORT-1
test "sorted returns a new ascending list for int, float and str" {
    try run("def main() -> int:\n    ys = sorted([2, 1])\n    return ys[0]\n", 1);
    try run("def main() -> int:\n    xs = [3, 1, 2]\n    ys = sorted(xs)\n    return xs[0] * 10 + ys[0]\n", 31);
    try run("def main() -> int:\n    words = sorted([\"pear\", \"apple\"])\n    if words[0] == \"apple\" and words[1] == \"pear\":\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    ys = sorted([2.5, 0.5, 4.0])\n    return int(ys[0] * 2.0)\n", 1);
    try run("def main() -> int:\n    return len(sorted([]))\n", 0);
    try run("def main() -> int:\n    ys = sorted([9, 8, 7, 6, 5, 4, 3, 2, 1, 0])\n    if ys[0] == 0 and ys[9] == 9 and ys[4] == 4:\n        return 1\n    return 0\n", 1);
    try reject("def main() -> int:\n    return len(sorted([True, False]))\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-SORT-KEY-1
test "sorted key lambdas order records stably and diagnose invalid inputs" {
    try run(
        \\class Item:
        \\    key: int
        \\    position: int
        \\
        \\
        \\def main() -> int:
        \\    items = [Item(key=2, position=0), Item(key=1, position=1), Item(key=2, position=2)]
        \\    ordered = sorted(items, key=lambda item: item.key)
        \\    return ordered[0].position * 100 + ordered[1].position * 10 + ordered[2].position
    , 102);
    try reject("def main() -> int:\n    return len(sorted(1, key=lambda value: value))\n", "E_PRELUDE_TYPE");
    try reject("def main() -> int:\n    xs = [1]\n    return len(sorted(xs, key=lambda value: True))\n", "E_TYPE");
}

// spec: PRELUDE-ABS-1
test "abs is total for int and still a float operation for float" {
    try run("def main() -> int:\n    return abs(0 - 42)\n", 42);
    try run("def main() -> int:\n    return abs(7)\n", 7);
    try run("def main() -> int:\n    return int(abs(0.0 - 2.5) * 2.0)\n", 5);
    try trapped("def main() -> int:\n    return abs(0 - 9223372036854775807 - 1)\n", "R_OVERFLOW");
}

// spec: PRELUDE-ROUND-1
test "round returns the nearest integral float with halves away from zero" {
    try run("def main() -> int:\n    return int(round(1.6))\n", 2);
    try run("def main() -> int:\n    return int(round(2.5))\n", 3);
    try run("def main() -> int:\n    return int(round(0.0 - 2.5))\n", 0 - 3);
    try run("def main() -> int:\n    return int(round(0.4))\n", 0);
    try run("def main() -> int:\n    x = 1.0 / 0.0\n    if x > 0.0 and round(x) == x:\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    x = 0.0 / 0.0\n    if x != x and round(x) != round(x):\n        return 1\n    return 0\n", 1);
    try reject("def main() -> int:\n    return int(round(2))\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-FOLD-2
test "any and all fold a list of conditions" {
    try run("def main() -> int:\n    if any([False, True]) and all([True, True]):\n        return 42\n    return 0\n", 42);
    try run("def main() -> int:\n    if all([]):\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    if any([]):\n        return 1\n    return 0\n", 0);
    try reject("def main() -> int:\n    return int(any([1]))\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-ITERATION-1
test "reversed, list and zip iterate or materialise without a new runtime" {
    // The body must be able to read every name these forms bind; each binding is
    // marked initialized before the body even though locals are function-scoped.
    try run("def main() -> int:\n    ys = list(reversed([1, 2]))\n    return len(ys)\n", 2);
    try run("def main() -> int:\n    return list(reversed([4, 5, 6]))[0]\n", 6);
    try run("def main() -> int:\n    for value in reversed([1, 2, 3]):\n        return value\n    return 0\n", 3);
    try run("def main() -> int:\n    if list(reversed(\"abc\"))[0] == \"c\":\n        return 1\n    return 0\n", 1);
    try run("def main() -> int:\n    for value in reversed(\"abc\"):\n        if value == \"c\":\n            return 1\n        return 0\n    return 0\n", 1);
    try run("def main() -> int:\n    total = 0\n    for a, b in zip([1, 2], [3, 4]):\n        total = total + a + b\n    return total\n", 10);
    try run("def main() -> int:\n    total = 0\n    for a, b in zip([1, 2, 3], [4]):\n        total = total + a + b\n    return total\n", 5);
    try run("def main() -> int:\n    for a, b in zip([], []):\n        return a + b\n    return 7\n", 7);
    try run("def main() -> int:\n    return len(list(range(3)))\n", 3);
    try run("def main() -> int:\n    return list(range(2, 5))[2]\n", 4);
    try run("def main() -> int:\n    return len(list(range(0)))\n", 0);
    try run("def main() -> int:\n    xs = [1, 2]\n    return len(list(xs))\n", 2);
    try run("def main() -> int:\n    return len(list(range(0 - 1)))\n", 0);
    try run("def main() -> int:\n    total = 0\n    for a, b in zip(\"ab\", \"cd\"):\n        total = total + len(a) + len(b)\n    return total\n", 4);
    try run("def range(n: int) -> list[int]:\n    return [9, 9]\n\n\ndef main() -> int:\n    return list(range(3))[1]\n", 9);
    try reject("def main() -> int:\n    return len(zip([1], [2]))\n", "E_PRELUDE_TYPE");
}

// spec: PRELUDE-SHADOW-2
test "declared len and replace functions shadow their prelude operations" {
    try run("def len(value: int) -> int:\n    return value + 1\n\ndef main() -> int:\n    return len(41)\n", 42);
    try run("def replace(value: int) -> int:\n    return value + 2\n\ndef main() -> int:\n    return replace(40)\n", 42);
    try reject("def len(left: int, right: int) -> int:\n    return left + right\n\ndef main() -> int:\n    return len(1)\n", "E_ARITY");
    try reject("def replace() -> int:\n    return 0\n\ndef main() -> int:\n    return replace(1, 2, 3)\n", "E_ARITY");
}

// spec: CANONICAL-LEN-1
test "len returns int for every supported receiver and dot len is removed" {
    try run("def main() -> int:\n    fixed: [2]int = [20, 22]\n    return len(fixed)\n", 2);
    try run("def main() -> int:\n    values = [1, 2]\n    return len(values)\n", 2);
    try run("def main() -> int:\n    mapping = {\"a\": 1}\n    return len(mapping)\n", 1);
    try run("def main() -> int:\n    return len(\"xy\")\n", 2);
    try run("def main() -> int:\n    raw = b\"ab\"\n    return len(raw)\n", 2);
    try rejectMigration("def main() -> int:\n    values = [1]\n    return values.len()\n", "len(", "len");
}

// spec: REMOVED-SPELLING-1
test "removed names and punctuation report their canonical migration" {
    try rejectRemovedLexicalNames();
    try rejectMigration("def main() -> int:\n    values: List[int] = []\n    return len(values)\n", "list[", "List");
    try rejectMigration("def main() -> int:\n    values = [1]\n    values.push(2)\n    return 0\n", "append", "push");
    try rejectMigration("def main() -> int:\n    values = {\"a\": 1}\n    if values.contains(\"a\"):\n        return 1\n    return 0\n", "in", "contains");
    try rejectMigration("def main() -> int:\n    return 1 & 1\n", "no replacement", "&");
    try rejectMigration("def main() -> int:\n    return 1 => 1\n", "no replacement", "=>");
}

// spec: PRELUDE-TYPES-2
test "prelude types are registered from syntax instead of raw source text" {
    try run("def main() -> int:\n    n = 4 // 2; raw: bytes = \"hi\".encode()\n    return len(raw) + n\n", 4);
    try run("def main() -> int:\n    raw = \"hi\".encode()\n    return len(raw)\n", 2);
    try run("def main() -> int:\n    # bytes after a comment stays ordinary syntax\n    raw: bytes = \"hi\".encode()\n    return len(raw) + 40\n", 42);
    try run("class bytes:\n    value: int\n\nclass str:\n    value: int\n\ndef main() -> int:\n    raw: bytes = bytes(value=20)\n    text: str = str(value=22)\n    return raw.value + text.value\n", 42);
}
