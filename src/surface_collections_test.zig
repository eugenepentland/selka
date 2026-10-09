//! collection syntax preserves managed aliasing and value record semantics.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "familiar-collections.my", bytes);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

// spec: SURFACE-COLLECTIONS-4
test "list syntax rejects invalid methods element types and indices" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values.append()
        \\    return 0
        , .code = "E_ARITY" },
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values.append(True)
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values[False] = 1
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values.remove(True)
        \\    return 0
        , .code = "E_TYPE" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "invalid-list.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
