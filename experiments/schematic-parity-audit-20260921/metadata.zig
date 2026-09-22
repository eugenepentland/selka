// Audit-only access to the production metadata generator; no compiler rebuild.
const std = @import("std");
const outputs = @import("outputs");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .unlimited);
    const manifest = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, try outputs.metadata(allocator, manifest.value));
}
