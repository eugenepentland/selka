//! Integrated Python text/dictionary syntax and deterministic iteration behavior.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "values.my", source);
    defer c.deinit();
    const result = c.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } }) catch |err| {
        for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    if (result == .trap) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.trap.message });
    try t.expectEqual(expected, result.value);
}
// spec-case: PY-TEXT-1
test "Python values Unicode literals chained methods indexing and membership" {
    try run(
        \\def main() -> int:
        \\    text = "hé🙂,x,"
        \\    parts = text.split(",")
        \\    if ",".join(parts) != text:
        \\        return 1
        \\    if "é🙂" not in text:
        \\        return 2
        \\    if parts[0][2] != "🙂":
        \\        return 3
        \\    return len(text)
    , 6);
}
// spec-case: PY-DICT-1
test "Python values dictionary literal growing aliases and arbitrary method receivers" {
    try run(
        \\class Box:
        \\    values: dict[str,int]
        \\def main() -> int:
        \\    box = Box{values: {"one": 1}}
        \\    alias = box.values
        \\    box.values["two"] = 40
        \\    if "two" not in alias:
        \\        return 1
        \\    if box.values.keys()[0] != "one":
        \\        return 2
        \\    return alias.get("two",0) + {"fallback": 2}.get("fallback",0)
    , 42);
}
// spec-case: PY-DICT-1
test "Python values dictionary and Unicode text iteration preserve order" {
    try run(
        \\def main() -> int:
        \\    values = {"a": 10,"b": 20}
        \\    total = 0
        \\    for key in values:
        \\        total += values[key]
        \\    for index, ch in enumerate("é🙂"):
        \\        total += index + len(ch)
        \\    return total
    , 33);
}

// spec-case: PY-TEXT-1
test "Python values Unicode slicing clamps endpoints and returns independent text" {
    try run(
        \\def main() -> int:
        \\    text = "aé🙂z"
        \\    middle = text[1:-1]
        \\    if middle != "é🙂":
        \\        return 1
        \\    if text[-99:99] != text:
        \\        return 2
        \\    if text[3:1] != "":
        \\        return 3
        \\    return len(text[:]) + len(middle)
    , 6);
}

// spec-case: PY-DICT-1
test "Python values generic dictionary preserves symbolic value types" {
    try run(
        \\def package[T:copy+storable](value: T) -> dict[str,T]:
        \\    values: dict[str,T] = {}
        \\    values["key"] = value
        \\    for key in values:
        \\        if key not in values:
        \\            return {}
        \\    return values
        \\def main() -> int:
        \\    return package(42)["key"]
    , 42);
}

// spec-case: PY-TEXT-1
test "Python values generic str conversion and Unicode escapes" {
    try run(
        \\def label[T:integer](number: T) -> str:
        \\    return "n=" + str(number)
        \\def main() -> int:
        \\    if label(42) != "n=42":
        \\        return 1
        \\    if "\u00e9\U0001f642" != "é🙂":
        \\        return 2
        \\    return 42
    , 42);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "trapped-values.my", source);
    defer c.deinit();
    const result = try c.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } });
    try t.expectEqualStrings(code, result.trap.code);
}
// spec-case: PY-DICT-1
test "Python values absent keys and structural iteration mutation trap" {
    try trapped("def main() -> int:\n    values = {1:10}\n    return values[2]\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    values = {1:10}\n    for key in values:\n        values[2] = key\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try trapped("def main() -> int:\n    return len(\"text\".split(\"\"))\n", "R_EMPTY_SEPARATOR");
}

// spec-case: PY-DICT-1
test "Python values collection float equality and membership preserve numeric semantics" {
    try run(
        \\def main() -> int:
        \\    zeros = [0.0]
        \\    negative = [-0.0]
        \\    if zeros != negative or -0.0 not in zeros:
        \\        return 1
        \\    nan = 0.0 / 0.0
        \\    nans = [nan]
        \\    if nans == nans or nan in nans:
        \\        return 2
        \\    if {"value": 0.0} != {"value": -0.0}:
        \\        return 3
        \\    if {"value": nan} == {"value": nan}:
        \\        return 4
        \\    if [[0.0]] != [[-0.0]]:
        \\        return 5
        \\    return 42
    , 42);
}
