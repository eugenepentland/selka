//! Bounded disk source provider shared by the CLI and interpreter applications.
const std = @import("std");
const project = @import("project.zig");
/// Imports resolve beneath this directory; the project loader supplies normalized paths.
pub const Files = struct {
    io: std.Io,
    root: []const u8,
    /// Borrow this provider only while the Files value remains at its current address.
    pub fn provider(self: *Files) project.Provider {
        return .{ .context = self, .read = read };
    }
    /// Return an owned source copy, preserving missing-file and byte-limit errors.
    pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const path = try std.fs.path.join(allocator, &.{ self.root, relative });
        defer allocator.free(path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(limit +| 1)) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.FileNotFound => error.NotFound,
            error.StreamTooLong => error.TooLarge,
            else => error.ReadFailed,
        };
        if (bytes.len > limit) {
            allocator.free(bytes);
            return error.TooLarge;
        }
        return bytes;
    }
};
