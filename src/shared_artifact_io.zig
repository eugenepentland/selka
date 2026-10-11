//! Bounded local artifact I/O; committed files are immutable and read by handle.
const std = @import("std");

/// Storage failures are explicit; damaged or absent artifacts are misses.
pub const Error = error{ OutOfMemory, ReadFailed, WriteFailed, DeterminismMismatch, InputChanged };
/// A content digest and exact length, independent of timestamps.
pub const Content = struct { size: usize, digest: [32]u8 };

/// Open a regular file without following its final symlink or blocking on a FIFO.
pub fn regular(a: std.mem.Allocator, io: std.Io, path: []const u8) Error!?std.Io.File {
    const name = try a.dupeSentinel(u8, path, 0);
    defer a.free(name);
    const linux = std.os.linux;
    const descriptor = linux.open(name, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0);
    switch (linux.errno(descriptor)) {
        .SUCCESS => {},
        .NOENT, .LOOP => return null,
        else => return error.ReadFailed,
    }
    const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
    errdefer file.close(io);
    if ((file.stat(io) catch return error.ReadFailed).kind != .file) {
        file.close(io);
        return null;
    }
    return file;
}

/// Hold a permanent regular lock inode until the returned handle closes.
pub fn lock(a: std.mem.Allocator, io: std.Io, path: []const u8) Error!std.Io.File {
    const name = try a.dupeSentinel(u8, path, 0);
    defer a.free(name);
    const linux = std.os.linux;
    const descriptor = linux.open(name, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
    if (linux.errno(descriptor) != .SUCCESS) return error.WriteFailed;
    const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
    errdefer file.close(io);
    if ((file.stat(io) catch return error.WriteFailed).kind != .file) return error.WriteFailed;
    file.lock(io, .exclusive) catch return error.WriteFailed;
    return file;
}

/// Read only a bounded regular record, returning caller-owned bytes.
pub fn bounded(a: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) Error!?[]u8 {
    const file = try regular(a, io, path) orelse return null;
    defer file.close(io);
    const size = (file.stat(io) catch return error.ReadFailed).size;
    if (size > limit) return null;
    const bytes = try a.alloc(u8, @intCast(size));
    errdefer a.free(bytes);
    const count = file.readPositionalAll(io, bytes, 0) catch return error.ReadFailed;
    if (count != size) {
        a.free(bytes);
        return null;
    }
    return bytes;
}

/// Hash exact bytes in bounded chunks, optionally copying them to a private file.
pub fn transfer(io: std.Io, input: std.Io.File, output: ?std.Io.File, offset: u64, size: usize) Error!Content {
    var buffer: [64 * 1024]u8 = undefined;
    var hash = std.crypto.hash.Blake3.init(.{});
    var done: usize = 0;
    while (done < size) {
        const take = @min(buffer.len, size - done);
        const count = input.readPositionalAll(io, buffer[0..take], offset + done) catch return error.ReadFailed;
        if (count != take) return error.InputChanged;
        hash.update(buffer[0..count]);
        if (output) |file| file.writeStreamingAll(io, buffer[0..count]) catch return error.WriteFailed;
        done += count;
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return .{ .size = size, .digest = digest };
}

/// Remove only a caller-owned incomplete file; cleanup never hides the primary error.
pub fn remove(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}
