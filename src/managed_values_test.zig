//! Unicode text and ordered dictionary surface: literals, aliases, equality and membership.
const std = @import("std");
const values = @import("runtime_values.zig");
const t = std.testing;
const debug = std.debug.print;
const str_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));
const dict_type: values.Type = @fromBackingInt(@intCast(34));

fn runSource(source: []const u8, expected: i64) !void {
    const language = @import("compiler.zig");
    var compilation = try language.Compilation.init(t.allocator, "managed-values.selka", source);
    defer compilation.deinit();
    const result = @import("native_execute.zig").run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

test "user nominal str declaration preserves its declared fields" {
    try runSource(
        \\record str:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut value = str(n=42)
        \\    return value.n
    , 42);
}
