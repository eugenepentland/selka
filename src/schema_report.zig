//! Checked schema plus the exact loaded source snapshot that produced it.
/// Failures returned by render; callers must handle these boundary errors.
pub const RenderError = @import("schema.zig").RenderError || error{ IncompleteProject, InternalError };

const std = @import("std");
const receipt = @import("source_receipt.zig");
/// Allocate a checked schema receipt with compiler identity and source dependency evidence.
pub fn render(allocator: std.mem.Allocator, compilation: *@import("project_compile.zig").Compilation, identity: receipt.Identity) RenderError![]u8 {
    try compilation.check();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const bytes = try @import("schema.zig").render(scratch, compilation);
    const schema = std.json.parseFromSlice(std.json.Value, scratch, bytes, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.InternalError;
    };
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
