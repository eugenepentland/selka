//! Reproduce streaming SHA-256 performance with the same 64 KiB buffer as the coordinator.
const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedFile;
    const file = try std.Io.Dir.cwd().openFile(init.io, args[1], .{});
    defer file.close(init.io);
    var buffer: [65536]u8 = undefined;
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    while (true) {
        const n = file.readStreaming(init.io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        sha.update(buffer[0..n]);
    }
    var result: [32]u8 = undefined;
    sha.final(&result);
    var out: [256]u8 = undefined;
    const written = try std.fmt.bufPrint(&out, "{s} {s} {s}\n", .{
        std.fmt.bytesToHex(result, .lower), @tagName(builtin.zig_backend), @tagName(builtin.mode),
    });
    try std.Io.File.stdout().writeStreamingAll(init.io, written);
}
