//! Diagnostics and traps of gathered comprehensions, generator arguments and
//! the operators sets share with integers. Their accepted behaviour is tested
//! in the language, in `tests/lang/sets.my`, `tests/lang/dict_comprehensions.my`
//! and `tests/lang/generator_arguments.my`; the rest of the set diagnostics are
//! in `sets_test.zig`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const debug = std.debug;

/// Check `source` and require a rejection carrying `code` whose message or
/// alternative note holds `needle`.
fn rejected(source: []const u8, code: []const u8, needle: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "collections-reject.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    for (c.diagnostics.items) |d| {
        if (!std.mem.eql(u8, d.code, code)) continue;
        if (std.mem.indexOf(u8, d.message, needle) != null) return;
        if (d.related) |related| if (std.mem.indexOf(u8, related.message, needle) != null) return;
    }
    for (c.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
    return t.expect(false);
}

/// Run `source` natively and require a trap carrying `code` whose report holds `needle`.
fn trapped(source: []const u8, code: []const u8, needle: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "collections-trap.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expect(result.trapped());
    try t.expectEqualStrings(code, result.trap.code);
    try t.expect(std.mem.indexOf(u8, result.stderr, needle) != null);
}

// spec-case: PY-GENERATOR-1
test "a generator outside a consuming call names the list comprehension" {
    try rejected("func main() -> int:\n    mut g = (x for x in [1, 2])\n    return 0\n", "E_GENERATOR", "accepted only as the argument");
    try rejected("func total(xs: int[]) -> int:\n    return len(xs)\n\nfunc main() -> int:\n    return total(x for x in [1, 2])\n", "E_GENERATOR", "[x * x for x in xs]");
    try rejected("func main() -> int:\n    return min((x for x in [1, 2]), 5)\n", "E_GENERATOR", "accepted only as the argument");
    try rejected("func main() -> int:\n    return sum(x > 1 for x in [1, 2])\n", "E_PRELUDE_TYPE", "sum(1 for x in xs if p)");
    try rejected("func main() -> int:\n    if any(x for x in [1, 2]):\n        return 1\n    return 0\n", "E_PRELUDE_TYPE", "any requires bool values");
}

// spec: PY-GENERATOR-2
test "a generator has no length and needs its own parentheses beside another argument" {
    try rejected("def main() -> int:\n    return len(x for x in [1, 2])\n", "E_GENERATOR", "sum(1 for x in xs if p)");
    try rejected("def main() -> int:\n    xs = sorted(x for x in [2, 1], reverse=True)\n    return xs[0]\n", "E_SYNTAX", "sorted((x for x in xs), reverse=True)");
}

// spec-case: PY-GENERATOR-1
test "min and max of a generator with no values trap with CPython's message" {
    try trapped("func main() -> int:\n    return min(x for x in [1, 2] if x > 5)\n", "R_ASSERT", "min() arg is an empty sequence");
    try trapped("func main() -> int:\n    return max(x for x in range(0))\n", "R_ASSERT", "max() arg is an empty sequence");
}

// spec-case: PY-SET-OPS-1
test "an ampersand where an argument begins stays the removed marker" {
    try rejected("def touch(values: mut list[int]) -> None:\n    values[0] = 1\n\ndef main() -> int:\n    values = [1]\n    touch(&values)\n    return 0\n", "E_REMOVED_SPELLING", "mut value");
}

// spec-case: PY-GATHER-1
test "a dict comprehension rejects an unhashable key and a binding that shadows a local" {
    try rejected("func main() -> int:\n    mut d = {x * 0.5: x for x in [1, 2]}\n    return len(d)\n", "E_DICT_KEY", "a float is not hashable");
    try rejected("func main() -> int:\n    mut x = 1\n    mut d = {x: x for x in [1, 2]}\n    return len(d)\n", "E_SHADOWING", "");
    try rejected("func main() -> int:\n    mut grid = [[1]]\n    mut flat = [for row in grid if len(row) yield row]\n    return len(flat)\n", "E_TYPE", "");
}
