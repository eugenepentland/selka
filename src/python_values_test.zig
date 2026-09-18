//! Integrated Python text/dictionary syntax and deterministic iteration behavior.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "trapped-values.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings(code, result.trap.code);
}
// spec-case: PY-DICT-1
test "Python values absent keys and structural iteration mutation trap" {
    try trapped("def main() -> int:\n    values = {1:10}\n    return values[2]\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    values = {1:10}\n    for key in values:\n        values[2] = key\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try trapped("def main() -> int:\n    return len(\"text\".split(\"\"))\n", "R_EMPTY_SEPARATOR");
}
