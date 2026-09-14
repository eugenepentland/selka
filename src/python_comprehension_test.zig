//! List comprehensions build a fresh list through one checked loop.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "comprehension.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "comprehension.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-COMPREHENSION-1
test "a comprehension maps one generator, optionally filtered, into a fresh list" {
    try execute(
        \\def total(values: list[int]) -> int:
        \\    sum = 0
        \\    for value in values:
        \\        sum = sum + value
        \\    return sum
        \\
        \\def main() -> int:
        \\    source = [1, 2, 3, 4]
        \\    doubled = [value * 2 for value in source]
        \\    kept = [value for value in source if value > 2]
        \\    return total(doubled) + total(kept) * 3 + 1
    , 42);
}

// spec-case: PY-COMPREHENSION-1
test "comprehensions read strings and dictionaries and leave the source unchanged" {
    try execute(
        \\def main() -> int:
        \\    counts: dict[str, int] = {}
        \\    counts["a"] = 20
        \\    counts["b"] = 22
        \\    values = [counts[key] for key in counts]
        \\    letters = [piece for piece in "abc" if piece != "b"]
        \\    source = [1, 2]
        \\    _ = [value for value in source]
        \\    return values[0] + values[1] + len(letters) * 0 + len(source) * 0
    , 42);
}

// spec: PY-COMPREHENSION-2
test "comprehensions reject shadowing, non-Boolean filters and uniterable sources" {
    try reject(
        \\def main() -> int:
        \\    value = 1
        \\    _ = [value for value in [1, 2]]
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in [1, 2] if x]
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in 3]
        \\    return 0
    , "E_COLLECTION_METHOD");
}
