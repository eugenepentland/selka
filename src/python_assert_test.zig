//! `assert` traps with its message and the source text of the checked expression.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "assert.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

fn expectTrap(text: []const u8, message: []const u8, spelling: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "assert.my", text);
    defer c.deinit();
    const result = try c.execute(t.allocator);
    try t.expect(result == .trap);
    try t.expectEqualStrings("R_ASSERT", result.trap.code);
    try t.expectEqualStrings(message, result.trap.message);
    try t.expectEqualStrings(spelling, c.src.text(result.trap.span));
}

// spec: PY-ASSERT-1
test "a satisfied assert runs on and a failed one traps R_ASSERT" {
    try execute("def main() -> int:\n    assert 1 < 2\n    return 42\n", 42);
    try expectTrap(
        "def main() -> int:\n    total = 1\n    assert total > 3\n    return 0\n",
        "total > 3",
        "total > 3",
    );
}

// spec: PY-ASSERT-2
test "an assert message replaces the expression text in the trap report" {
    try expectTrap(
        "def main() -> int:\n    assert False, \"budget must remain positive\"\n    return 0\n",
        "budget must remain positive",
        "False",
    );
}

// spec-case: PY-ASSERT-1
test "assert checks a Boolean condition under any effect bound and inside loops" {
    try execute(
        \\def total(values: list[int]) -> int:
        \\    sum = 0
        \\    for value in values:
        \\        assert value >= 0, "counts are never negative"
        \\        sum = sum + value
        \\    return sum
        \\
        \\def main() -> int:
        \\    return total([40, 2])
    , 42);
    var c = try language.Compilation.init(t.allocator, "assert.my", "def main() -> int:\n    assert 1\n    return 0\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
}

// spec-case: PY-ASSERT-2
test "assert remains an ordinary identifier in legacy brace sources" {
    try execute("fn main() -> i64 { let assert = 42; return assert; }", 42);
}
