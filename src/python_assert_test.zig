//! `assert` traps `R_ASSERT` at the source position of the checked expression.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const unit = "assert.my";

fn execute(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn expectTrap(text: []const u8, line: u64, column: u64) !void {
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const result = try native.run(&c);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_ASSERT", result.trap.code);
    try t.expectEqualStrings(unit, result.trap.path);
    try t.expectEqual(line, result.trap.line);
    try t.expectEqual(column, result.trap.column);
}

// spec: PY-ASSERT-1
test "a satisfied assert runs on and a failed one traps R_ASSERT" {
    try execute("def main() -> int:\n    assert 1 < 2\n    return 42\n", 42);
    try expectTrap("def main() -> int:\n    total = 1\n    assert total > 3\n    return 0\n", 3, 12);
}

// spec: PY-ASSERT-2
test "an assert carrying a message raises the same located R_ASSERT as a bare one" {
    try expectTrap("def main() -> int:\n    assert False, \"budget must remain positive\"\n    return 0\n", 2, 12);
}

// spec-case: PY-ASSERT-1
// spec-case: PY-ASSERT-2
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
    var c = try language.Compilation.init(t.allocator, unit, "def main() -> int:\n    assert 1\n    return 0\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
}
