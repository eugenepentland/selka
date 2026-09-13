//! Bounded copied metadata/listing streams behind an already validated directory grant.
const std = @import("std");
const CallError = @import("external_capabilities.zig").CallError;
const resources = @import("external_resources.zig");
/// Limits apply before publication; exceeding either denies the whole snapshot.
pub const Limits = struct { bytes: usize = 64 * 1024, entries: usize = 256 };
/// Owned immutable bytes and one private read cursor, released with the resource handle.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    position: usize = 0,
    /// Release copied contents and the snapshot object.
    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.bytes);
        self.allocator.destroy(self);
    }
    /// Copy only available bytes and report EOF without changing storage lifetime.
    pub fn read(self: *Snapshot, output: []u8) resources.Read {
        const length = @min(output.len, self.bytes.len - self.position);
        @memcpy(output[0..length], self.bytes[self.position..][0..length]);
        self.position += length;
        return .{ .length = length, .eof = self.position == self.bytes.len };
    }
};
/// Read metadata without following the final symlink; lists open directories without
/// following links; `k` creates one directory and `x` removes one file or empty directory.
pub fn create(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, mode: u8, limits: Limits) CallError!*Snapshot {
    const bytes = switch (mode) {
        'm' => try metadata(allocator, io, parent, name, limits),
        'l' => try listing(allocator, io, parent, name, limits),
        'k', 'x' => try change(allocator, io, parent, name, mode),
        else => return error.Denied,
    };
    errdefer allocator.free(bytes);
    const snapshot = try allocator.create(Snapshot);
    snapshot.* = .{ .allocator = allocator, .bytes = bytes };
    return snapshot;
}
/// Apply one directory change and report it as an empty acknowledged snapshot.
fn change(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, mode: u8) CallError![]u8 {
    if (name.len == 0) return error.Denied;
    if (mode == 'k') {
        parent.createDir(io, name, .default_dir) catch |err| return mapError(err);
    } else parent.deleteFile(io, name) catch |first| {
        if (first == error.IsDir) parent.deleteDir(io, name) catch |err| return mapError(err) else return mapError(first);
    };
    const bytes = try allocator.alloc(u8, 1);
    bytes[0] = 1;
    return bytes;
}
fn metadata(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, limits: Limits) CallError![]u8 {
    if (limits.bytes < 10) return error.Denied;
    const stat = if (name.len == 0) parent.stat(io) catch |err| return mapError(err) else parent.statFile(io, name, .{ .follow_symlinks = false }) catch |err| return mapError(err);
    const bytes = try allocator.alloc(u8, 10);
    bytes[0] = 1;
    bytes[1] = kind(stat.kind);
    std.mem.writeInt(u64, bytes[2..10], stat.size, .little);
    return bytes;
}
fn listing(allocator: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, limits: Limits) CallError![]u8 {
    if (limits.bytes == 0) return error.Denied;
    var directory = parent.openDir(io, if (name.len == 0) "." else name, .{ .iterate = true, .follow_symlinks = false }) catch |err| return mapError(err);
    defer directory.close(io);
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);
    try bytes.append(allocator, 1);
    var count: usize = 0;
    var iterator = directory.iterate();
    while (iterator.next(io) catch |err| return mapError(err)) |entry| {
        if (count >= limits.entries or entry.name.len > 4094 or entry.name.len == 0) return error.Denied;
        if (bytes.items.len > limits.bytes or entry.name.len + 3 > limits.bytes - bytes.items.len) return error.Denied;
        var header = [_]u8{ kind(entry.kind), 0, 0 };
        std.mem.writeInt(u16, header[1..3], @intCast(entry.name.len), .little);
        try bytes.appendSlice(allocator, &header);
        try bytes.appendSlice(allocator, entry.name);
        count += 1;
    }
    return bytes.toOwnedSlice(allocator);
}
fn kind(value: std.Io.File.Kind) u8 {
    return switch (value) {
        .file => 1,
        .directory => 2,
        .sym_link => 3,
        else => 0,
    };
}
fn mapError(err: anyerror) CallError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.AccessDenied, error.PermissionDenied, error.SymLinkLoop, error.NotDir => error.Denied,
        else => error.Failed,
    };
}
