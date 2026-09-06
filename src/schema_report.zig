//! Checked schema plus the exact loaded source snapshot that produced it.
const std = @import("std");
const receipt = @import("source_receipt.zig");
pub fn render(allocator: std.mem.Allocator, compilation: *@import("project_compile.zig").Compilation, identity: receipt.Identity) ![]u8 {
    try compilation.check();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const bytes = try @import("schema.zig").render(scratch, compilation);
    const schema = try std.json.parseFromSlice(std.json.Value, scratch, bytes, .{});
    defer schema.deinit();
    const source = .{
        .version = "schema-source-v1",
        .entry = compilation.index.project.modules.items[0].name,
        .implementation = try receipt.implementation(scratch, identity),
        .sources = try receipt.inputs(scratch, compilation.index.project),
    };
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "schema-report-v1",
        .source_sha256 = try receipt.digest(scratch, source),
        .source = source,
        .schema_sha256 = try receipt.digest(scratch, schema.value),
        .schema = schema.value,
    }, .{});
}
