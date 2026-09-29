//! Bounded disk source provider shared by the CLI and interpreter applications.
const std = @import("std");
const project = @import("project.zig");
const embed = @import("embed.zig");
/// Imports resolve beneath this directory; the project loader supplies normalized paths.
/// Embedded files may sit anywhere beneath `embed_root`, which defaults to `root`.
pub const Files = struct {
    io: std.Io,
    root: []const u8,
    embed_root: ?[]const u8 = null,
    /// Borrow this provider only while the Files value remains at its current address.
    pub fn provider(self: *Files) project.Provider {
        return .{ .context = self, .read = read, .embed = readEmbed };
    }
    /// Read the file an `embed_bytes`/`embed_str` literal names, relative to the
    /// directory of module file `module_path` and confined to the embed root.
    pub fn readEmbed(context: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8) std.mem.Allocator.Error!embed.Read {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return embed.read(allocator, .{ .io = self.io, .import_root = self.root, .root = self.embed_root orelse self.root }, module_path, path);
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
