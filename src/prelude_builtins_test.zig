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

// spec: PRELUDE-SHADOW-1
test "a declared function or binding keeps its own prelude name" {
    try run("def sum(xs: list[int]) -> int:\n    return 7\n\n\ndef main() -> int:\n    return sum([1, 2, 3])\n", 7);
    try run("def main() -> int:\n    max = 5\n    return max + 1\n", 6);
    try run("def main() -> int:\n    sorted = 4\n    return sorted + 1\n", 5);
    try run("def list() -> int:\n    return 9\n\n\ndef main() -> int:\n    return list()\n", 9);
}
