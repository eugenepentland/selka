//! Integrated Python text/dictionary syntax and deterministic iteration behavior.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "trapped-values.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expectEqualStrings(code, result.trap.code);
}
// spec-case: PY-DICT-1
test "Python values absent keys and structural iteration mutation trap" {
    try trapped("def main() -> int:\n    values = {1:10}\n    return values[2]\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    values = {1:10}\n    for key in values:\n        values[2] = key\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try trapped("def main() -> int:\n    return len(\"text\".split(\"\"))\n", "R_EMPTY_SEPARATOR");
}

// spec: GC-SCAN-PLAN-1
test "a dictionary reclaimed and replaced at its address is traced with the new entry layout" {
    // `d` and `x` are dead after their literals, so a stress collection
    // reclaims them and the string-keyed dictionary is allocated where `d`
    // was. A scan plan cached for `d`'s integer entries would then skip every
    // string key, the collector would reclaim the keys, and the pops would
    // miss.
    var c = try language.Compilation.init(t.allocator, "scan-plan.my",
        \\def main() -> int:
        \\    d: dict[int, int] = {1: 1}
        \\    x = [1, 2]
        \\    s: dict[str, int] = {}
        \\    for i in range(40):
        \\        s[str(i)] = i
        \\    for i in range(40):
        \\        _ = s.pop(str(i))
        \\    return len(s)
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 0), result.value);
}
