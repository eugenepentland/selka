//! Native cross-worktree success receipts. Records are disposable, bounded and
//! published under a short process lock; checking and execution hold no store lock.
const std = @import("std");

/// A complete portable test execution identity.
pub const Digest = [32]u8;
/// Explicitly configured storage must be usable; damaged receipts remain misses.
pub const Error = error{ OutOfMemory, ReadFailed, WriteFailed };
const format = "selka-native-test-store-v1\n";
const maximum_record = 512;

/// A dedicated namespace beneath the caller's shared cache directory.
pub const Store = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    root: []const u8,

    /// Create or validate the versioned namespace without changing another cache format.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Store {
        if (directory.len == 0) return error.WriteFailed;
        const self: Store = .{ .arena = a, .io = io, .root = try std.fs.path.join(a, &.{ directory, "native-tests-v1" }) };
        std.Io.Dir.cwd().createDirPath(io, self.root) catch return error.WriteFailed;
        const guard = try self.lock(.exclusive);
        defer guard.close(io);
        if (try self.read(try self.path("format"))) |bytes| {
            if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
        } else {
            // A lost/corrupt format marker cannot silently adopt old receipts.
            var dir = std.Io.Dir.cwd().openDir(io, self.root, .{ .iterate = true }) catch return error.ReadFailed;
            defer dir.close(io);
            var entries = dir.iterate();
            while (entries.next(io) catch return error.ReadFailed) |entry| {
                if (std.mem.eql(u8, entry.name, ".lock") or std.mem.eql(u8, entry.name, "format.partial")) continue;
                return error.ReadFailed;
            }
            try self.publish(try self.path("format"), format);
        }
        return self;
    }

    /// Address a receipt directly; lookup never enumerates the shared store.
    pub fn artifactPath(self: Store, key: Digest) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "{s}/receipts/{s}.pass", .{ self.root, std.fmt.bytesToHex(key, .lower) });
    }

    /// Accept only an exact success envelope for this identity.
    pub fn hit(self: Store, key: Digest) Error!bool {
        const guard = try self.lock(.shared);
        defer guard.close(self.io);
        try self.validate();
        const found = try self.read(try self.artifactPath(key)) orelse return false;
        return std.mem.eql(u8, found, try self.success(key));
    }

    /// Atomically publish a completed success after the caller revalidates its inputs.
    pub fn save(self: Store, key: Digest) Error!void {
        const guard = try self.lock(.exclusive);
        defer guard.close(self.io);
        try self.validate();
        const destination = try self.artifactPath(key);
        const bytes = try self.success(key);
        if (try self.read(destination)) |previous| if (std.mem.eql(u8, previous, bytes)) return;
        std.Io.Dir.cwd().createDirPath(self.io, try self.path("receipts")) catch return error.WriteFailed;
        try self.publish(destination, bytes);
    }

    /// Discard an earlier success before an explicit forced execution begins.
    pub fn invalidate(self: Store, key: Digest) Error!void {
        const guard = try self.lock(.exclusive);
        defer guard.close(self.io);
        try self.validate();
        std.Io.Dir.cwd().deleteFile(self.io, try self.artifactPath(key)) catch |err| {
            if (err != error.FileNotFound) return error.WriteFailed;
        };
    }

    fn path(self: Store, leaf: []const u8) Error![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, leaf });
    }

    fn lock(self: Store, mode: std.Io.File.Lock) Error!std.Io.File {
        const name = try self.arena.dupeSentinel(u8, try self.path(".lock"), 0);
        const linux = std.os.linux;
        const descriptor = linux.open(name, .{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
        if (linux.errno(descriptor) != .SUCCESS) return error.WriteFailed;
        const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
        errdefer file.close(self.io);
        if ((file.stat(self.io) catch return error.WriteFailed).kind != .file) return error.WriteFailed;
        file.lock(self.io, mode) catch return error.WriteFailed;
        return file;
    }

    fn validate(self: Store) Error!void {
        const bytes = try self.read(try self.path("format")) orelse return error.ReadFailed;
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
    }

    fn read(self: Store, file_path: []const u8) Error!?[]const u8 {
        const name = try self.arena.dupeSentinel(u8, file_path, 0);
        const linux = std.os.linux;
        const descriptor = linux.open(name, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0);
        switch (linux.errno(descriptor)) {
            .SUCCESS => {},
            .NOENT, .LOOP => return null,
            else => return error.ReadFailed,
        }
        const file: std.Io.File = .{ .handle = @intCast(descriptor), .flags = .{ .nonblocking = true } };
        defer file.close(self.io);
        const info = file.stat(self.io) catch return error.ReadFailed;
        if (info.kind != .file or info.size > maximum_record) return null;
        var reader = file.reader(self.io, &.{});
        return reader.interface.allocRemaining(self.arena, .limited(maximum_record)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => null,
            else => error.ReadFailed,
        };
    }

    fn success(self: Store, key: Digest) Error![]const u8 {
        const payload = try std.fmt.allocPrint(self.arena, "selka-shared-test-v1\n{s}\npassed\n", .{std.fmt.bytesToHex(key, .lower)});
        var checksum: Digest = undefined;
        std.crypto.hash.Blake3.hash(payload, &checksum, .{});
        return std.fmt.allocPrint(self.arena, "{s}{s}\n", .{ payload, std.fmt.bytesToHex(checksum, .lower) });
    }

    // A permanent lock inode serializes writers. An interrupted writer's partial
    // is never a receipt and the next writer safely replaces it under that lock.
    fn publish(self: Store, destination: []const u8, bytes: []const u8) Error!void {
        const temporary = try std.fmt.allocPrint(self.arena, "{s}.partial", .{destination});
        std.Io.Dir.cwd().deleteFile(self.io, temporary) catch |err| {
            if (err != error.FileNotFound) return error.WriteFailed;
        };
        defer removePartial(self.io, temporary);
        {
            const file = std.Io.Dir.cwd().createFile(self.io, temporary, .{ .exclusive = true }) catch return error.WriteFailed;
            defer file.close(self.io);
            file.writeStreamingAll(self.io, bytes) catch return error.WriteFailed;
        }
        std.Io.Dir.cwd().rename(temporary, std.Io.Dir.cwd(), destination, self.io) catch return error.WriteFailed;
    }
};

fn removePartial(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shared test store checks exact identities rejects corrupt records and recovers interrupted publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store = try Store.open(a, std.testing.io, root);
    const key: Digest = @splat(7);
    try std.testing.expect(!try store.hit(key));
    try store.save(key);
    const other = try Store.open(a, std.testing.io, root);
    try std.testing.expect(try other.hit(key));
    try std.testing.expect(!try other.hit(@splat(8)));
    const path = try store.artifactPath(key);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expect(!try other.hit(key));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.partial", .{path}), .data = "interrupted" });
    try std.testing.expect(!try other.hit(key));
    try other.save(key);
    try std.testing.expect(try store.hit(key));
    try other.invalidate(key);
    try std.testing.expect(!try store.hit(key));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = &(@as([513]u8, @splat('x'))) });
    try std.testing.expect(!try store.hit(key));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.Io.Dir.cwd().symLink(std.testing.io, try store.path("format"), path, .{});
    try std.testing.expect(!try store.hit(key));
    try store.save(key);
    try std.testing.expect(try store.hit(key));
    try store.invalidate(key);
    try std.Io.Dir.cwd().symLink(std.testing.io, try store.path("format"), try std.fmt.allocPrint(a, "{s}.partial", .{path}), .{});
    try store.save(key);
    try std.testing.expectEqualStrings(format, (try store.read(try store.path("format"))).?);
    try std.testing.expect(try store.hit(key));
    try store.invalidate(key);
    const fifo = try a.dupeSentinel(u8, path, 0);
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.mknod(fifo, std.os.linux.S.IFIFO | 0o600, 0)));
    try std.testing.expect(!try store.hit(key));
    try store.save(key);
    try std.testing.expect(try store.hit(key));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shared test store preserves foreign formats and permanent lock ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store = try Store.open(a, std.testing.io, root);
    const lock_path = try store.path(".lock");
    const held = try store.lock(.exclusive);
    const contender = try std.Io.Dir.cwd().openFile(std.testing.io, lock_path, .{ .mode = .read_write });
    defer contender.close(std.testing.io);
    try std.testing.expect(!try contender.tryLock(std.testing.io, .shared));
    held.close(std.testing.io);
    try std.testing.expect(try contender.tryLock(std.testing.io, .shared));
    contender.unlock(std.testing.io);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try store.path("format"), .data = "foreign-format\n" });
    try std.testing.expectError(error.ReadFailed, Store.open(a, std.testing.io, root));
    try std.testing.expectError(error.ReadFailed, store.hit(@splat(1)));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try store.path("format"));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try store.path("foreign"), .data = "preserve" });
    try std.testing.expectError(error.ReadFailed, Store.open(a, std.testing.io, root));
    try std.testing.expectEqualStrings("preserve", (try store.read(try store.path("foreign"))).?);
}
