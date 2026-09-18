//! Python collection forms preserve evaluation order and tracing roots.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

// spec: PY-COLLECTIONS-19
test "push is rejected with a migration diagnostic naming append" {
    var compilation = try language.Compilation.init(t.allocator, "push.my",
        \\def main() -> i64:
        \\    xs = [1]
        \\    xs.push(2)
        \\    return len(xs)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_REMOVED_SPELLING", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "append") != null);
}

// spec: PY-COLLECTIONS-20
test "absent list and dictionary values trap instead of returning a sentinel" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\def main() -> i64:
        \\    xs = [1, 2]
        \\    return xs.index(9)
        , .code = "R_LIST_VALUE" },
        .{ .source =
        \\def main() -> i64:
        \\    xs: list[i64] = []
        \\    return xs.pop()
        , .code = "R_LIST_BOUNDS" },
        .{ .source =
        \\def main() -> i64:
        \\    d = {"a": 1}
        \\    return d.pop("z")
        , .code = "R_MISSING_KEY" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "absent.my", case.source);
        defer compilation.deinit();
        const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
        try t.expect(result.trapped());
        try t.expectEqualStrings(case.code, result.trap.code);
    }
}

// spec: PY-COLLECTIONS-8
test "iteration detects alias growth including continue and final step" {
    for ([_][]const u8{
        "for x in items:\n        _ = x\n        alias.append(2)",
        "for x in items:\n        _ = x\n        alias.append(2)\n        continue",
    }) |loop| {
        const source = try std.fmt.allocPrint(t.allocator,
            \\def main() -> i64:
            \\    items = [1]
            \\    alias = items
            \\    {s}
            \\    return 0
        , .{loop});
        defer t.allocator.free(source);
        var compilation = try language.Compilation.init(t.allocator, "mutation.my", source);
        defer compilation.deinit();
        const result = try native.runWithOptions(&compilation, .{ .gc_stress = true });
        try t.expect(result.trapped());
        try t.expectEqualStrings("R_LIST_ITERATION_MUTATION", result.trap.code);
    }
    var compilation = try language.Compilation.init(t.allocator, "mutation.my",
        \\def main() -> i64:
        \\    items = [1]
        \\    for x in items:
        \\        _ = x
        \\        items.append(42)
        \\        break
        \\    return items[-1]
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&compilation)).value);
}
