//! Bounded local artifact I/O; committed files are immutable and read by handle.
const std = @import("std");

/// Storage failures are explicit; damaged or absent artifacts are misses.
pub const Error = error{ OutOfMemory, ReadFailed, WriteFailed, InputChanged };
/// A content digest and exact length, independent of timestamps.
pub const Content = struct { size: usize, digest: [32]u8 };

/// A regular file opened by `regularStat` and the status it was found with.
pub const Opened = struct { file: std.Io.File, stat: std.Io.File.Stat };

/// Open a regular file without following its final symlink or blocking on a FIFO.
pub fn regular(a: std.mem.Allocator, io: std.Io, path: []const u8) Error!?std.Io.File {
    const opened = try regularStat(a, io, path) orelse return null;
    return opened.file;
}

/// `regular`, handing back the status the open was checked with, for a caller that needs the size or the times and would otherwise ask again.
pub fn regularStat(a: std.mem.Allocator, io: std.Io, path: []const u8) Error!?Opened {
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
    const found = file.stat(io) catch return error.ReadFailed;
    if (found.kind != .file) {
        file.close(io);
        return null;
    }
    return .{ .file = file, .stat = found };
}

/// Open a permanent regular lock inode without locking it, so the caller can try the lock. Null when `create` is false and there is no such
/// file.
pub fn openLock(a: std.mem.Allocator, io: std.Io, path: []const u8, create: bool) Error!?std.Io.File {
    const name = try a.dupeSentinel(u8, path, 0);
    defer a.free(name);
    const linux = std.os.linux;
    const descriptor = linux.open(name, .{ .ACCMODE = .RDWR, .CREAT = create, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
    switch (linux.errno(descriptor)) {
        .SUCCESS => {},
        .NOENT => if (!create) return null else return error.WriteFailed,
        else => return error.WriteFailed,
    }
    const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
    errdefer file.close(io);
    if ((file.stat(io) catch return error.WriteFailed).kind != .file) return error.WriteFailed;
    return file;
}

/// Hold a regular lock inode until the returned handle closes. A name removed while this waited (a collector sweeping idle claim
/// files unlinks the ones it can lock) leaves the waiter holding an orphan inode that the next caller would not find, so the name is
/// checked after the lock is taken and, if it no longer names the held file, opened and locked again.
pub fn lock(a: std.mem.Allocator, io: std.Io, path: []const u8) Error!std.Io.File {
    const name = try a.dupeSentinel(u8, path, 0);
    defer a.free(name);
    const linux = std.os.linux;
    var attempt: usize = 0;
    while (attempt < lock_attempts) : (attempt += 1) {
        const descriptor = linux.open(name, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
        if (linux.errno(descriptor) != .SUCCESS) return error.WriteFailed;
        const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
        const held = file.stat(io) catch {
            file.close(io);
            return error.WriteFailed;
        };
        if (held.kind != .file) {
            file.close(io);
            return error.WriteFailed;
        }
        file.lock(io, .exclusive) catch {
            file.close(io);
            return error.WriteFailed;
        };
        const named = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch {
            file.close(io);
            continue;
        };
        if (named.inode == held.inode) return file;
        file.close(io);
    }
    return error.WriteFailed;
}

/// How many times `lock` opens a name that was removed under it before it gives up: each retry means another process removed
/// the name in the moments between two of this one's attempts.
const lock_attempts = 64;

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

/// Copy exact bytes in bounded chunks without hashing them, for a caller that already has the digest.
pub fn copy(io: std.Io, input: std.Io.File, output: std.Io.File, offset: u64, size: usize) Error!void {
    var buffer: [64 * 1024]u8 = undefined;
    var done: usize = 0;
    while (done < size) {
        const take = @min(buffer.len, size - done);
        const count = input.readPositionalAll(io, buffer[0..take], offset + done) catch return error.ReadFailed;
        if (count != take) return error.InputChanged;
        output.writeStreamingAll(io, buffer[0..count]) catch return error.WriteFailed;
        done += count;
    }
}

/// Remove only a caller-owned incomplete file; cleanup never hides the primary error.
pub fn remove(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}
