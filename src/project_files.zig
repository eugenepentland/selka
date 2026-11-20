//! Bounded disk source provider shared by the CLI and interpreter applications.
const std = @import("std");
const project = @import("project.zig");
const embed = @import("embed.zig");
const module_records = @import("module_records.zig");
const file_digests = @import("file_digests.zig");
/// Imports resolve beneath this directory; the project loader supplies normalized paths.
/// Embedded files may sit anywhere beneath `embed_root`, which defaults to `root`.
pub const Files = struct {
    io: std.Io,
    root: []const u8,
    embed_root: ?[]const u8 = null,
    /// The entry file's cache key name (`core/entry_name.zig`), set by the build in its own arena; empty for any other check.
    entry_key: []const u8 = "",
    /// Header records the loader may read and keep; null keeps none.
    records: ?module_records.Records = null,
    /// The digests a stat tuple vouches for (`file_digests.zig`); null hashes every module as it is loaded. A reader that sets it hands the
    /// loader `vouch` and `learned` hooks that call it (the plain `provider` below does not).
    digests: ?*file_digests.Memo = null,
    /// Borrow this provider only while the Files value remains at its current address.
    pub fn provider(self: *Files) project.Provider {
        return .{
            .context = self,
            .read = read,
            .embed = readEmbed,
            .records = self.records,
            .vouch = if (self.digests != null) vouch else null,
            .learned = if (self.digests != null) learned else null,
        };
    }
    /// The digest the memo holds for a file this provider just read; the provider reads only from disk, so the file's tuple describes the bytes.
    fn vouch(context: ?*anyopaque, relative: []const u8, bytes: []const u8) ?[32]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return (self.digests orelse return null).vouch(relative, bytes);
    }
    /// Tell the memo the digest the loader took of a file this provider read.
    fn learned(context: ?*anyopaque, relative: []const u8, digest: [32]u8) void {
        const self: *Files = @ptrCast(@alignCast(context.?));
        (self.digests orelse return).learned(relative, digest);
    }
    /// Read the file an `embed_bytes`/`embed_str` literal names, relative to the
    /// directory of module file `module_path` and confined to the embed root.
    pub fn readEmbed(context: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!embed.Read {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return embed.readLimited(allocator, .{ .io = self.io, .import_root = self.root, .root = self.embed_root orelse self.root }, module_path, path, limit);
    }
    /// Return an owned source copy, preserving missing-file and byte-limit errors.
    pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const path = try std.fs.path.join(allocator, &.{ self.root, relative });
        defer allocator.free(path);
        if (self.digests) |memo| return readObserved(self, memo, path, relative, allocator, limit);
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

    /// `read`, through an open file whose tuple is taken before and after the read and handed to the digest memo: the descriptor's tuple
    /// costs no path lookup, where a stat of the path would cost one before and one after.
    fn readObserved(self: *Files, memo: *file_digests.Memo, path: []const u8, relative: []const u8, allocator: std.mem.Allocator, limit: usize) project.ReadError![]u8 {
        var file = std.Io.Dir.cwd().openFile(self.io, path, .{ .allow_directory = true }) catch |err| return switch (err) {
            error.FileNotFound => error.NotFound,
            else => error.ReadFailed,
        };
        defer file.close(self.io);
        const before = file_digests.Memo.tupleOfFile(file.stat(self.io) catch null);
        var reader = file.reader(self.io, &.{});
        const bytes = reader.interface.allocRemaining(allocator, .limited(limit +| 1)) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => error.TooLarge,
            error.ReadFailed => error.ReadFailed,
        };
        if (bytes.len > limit) {
            allocator.free(bytes);
            return error.TooLarge;
        }
        memo.observed(relative, before, file_digests.Memo.tupleOfFile(file.stat(self.io) catch null));
        return bytes;
    }
};
