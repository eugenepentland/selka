//! Managed list generic contracts, recursive nominal layouts, and source formatting.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");

fn evaluate(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "managed-generic.my", bytes);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: GC-GENERIC-3
test "managed nominal indirection does not admit recursive by value records" {
    var compilation = try language.Compilation.init(t.allocator, "managed-invalid.my", "struct Bad<T:copy>{nested:Bad<T>}fn main()->i64{return 0;}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_RECURSIVE_RECORD", compilation.diagnostics.items[0].code);
}

// spec: GC-GENERIC-4
test "managed list formatting preserves contextual list case identifiers" {
    var compilation = try language.Compilation.init(t.allocator, "managed-format.my", "enum Kind{list,atom}fn main()->i64{let values:List<i64>=[];values.push(42);return values[0];}");
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "[]") != null);
    try evaluate(formatted);
}
