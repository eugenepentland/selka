//! Native cross-worktree success receipts. Records are disposable, bounded and
//! published under a short process lock; execution holds no publication lock.
const std = @import("std");
const work = @import("mylang").native_cache_work;
const retention = @import("mylang").native_cache_retention;

/// A process-owned computation claim retaining the namespace until publication.
pub const Claim = work.Claim;

/// A complete portable test execution identity.
pub const Digest = [32]u8;
/// Explicitly configured storage must be usable; damaged receipts remain misses.
pub const Error = error{ OutOfMemory, ReadFailed, WriteFailed };
/// What one `save` did. Only `stored` wrote a receipt.
pub const Saved = enum {
    /// The success receipt was written.
    stored,
    /// The identical receipt was already present; its recency was refreshed.
    present,
    /// A collection holds the store, so nothing was written and nothing waited.
    skipped,
    /// A well-formed receipt for this identity holds different contents. It is
    /// kept, nothing is written, and the pair is appended to `mismatches.log`.
    mismatch,
};
const format = "selka-native-test-store-v3\n";
const maximum_record = 512;

/// A dedicated namespace beneath the caller's shared cache directory.
pub const Store = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    root: []const u8,

    /// Create or validate the versioned namespace without changing another cache format.
    /// A present marker is validated without any lock; the throttled sweep that
    /// follows only tries its exclusive admission, so no open waits on a sweep.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Store {
        if (directory.len == 0) return error.WriteFailed;
        const self: Store = .{ .arena = a, .io = io, .root = try std.fs.path.join(a, &.{ directory, "native-tests-v3" }) };
        try self.initialize();
        self.retentionContext().automatic();
        return self;
    }

    fn retentionContext(self: Store) retention.Context {
        return retention.Context.init(self.arena, self.io, self.root, .tests);
    }

    fn lease(self: Store) Error!std.Io.File {
        return self.retentionContext().lease() catch |err| return mapRetention(err);
    }

    // Concurrent first openers race to create one namespace (SHARED-STORE-6):
    // a failed attempt is retried a bounded number of times, re-reading the
    // marker a peer may have published, so only a store that stays unusable fails.
    fn initialize(self: Store) Error!void {
        try retention.retried(self, createNamespace);
        _ = self.retentionContext().policy() catch |err| return mapRetention(err);
    }

    // Only first creation takes the exclusive `.lock`, re-reading the marker
    // under it. No sweep runs before the marker exists.
    fn createNamespace(self: Store) Error!void {
        std.Io.Dir.cwd().createDirPath(self.io, self.root) catch return error.WriteFailed;
        if (try self.marked()) return;
        const guard = try self.lock(.exclusive);
        defer guard.close(self.io);
        if (!try self.marked()) try self.writeMarker();
    }

    fn marked(self: Store) Error!bool {
        const bytes = try self.read(try self.path("format")) orelse return false;
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
        return true;
    }

    // A lost/corrupt format marker cannot silently adopt old receipts.
    fn writeMarker(self: Store) Error!void {
        var dir = std.Io.Dir.cwd().openDir(self.io, self.root, .{ .iterate = true }) catch return error.ReadFailed;
        defer dir.close(self.io);
        var entries = dir.iterate();
        while (entries.next(self.io) catch return error.ReadFailed) |entry| {
            if (std.mem.eql(u8, entry.name, ".retention.lock") or std.mem.eql(u8, entry.name, ".lock") or std.mem.eql(u8, entry.name, "format.partial")) continue;
            return error.ReadFailed;
        }
        try self.publish(try self.path("format"), format);
    }

    /// Address a receipt directly; lookup never enumerates the shared store.
    pub fn artifactPath(self: Store, key: Digest) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "{s}/receipts/{s}.pass", .{ self.root, std.fmt.bytesToHex(key, .lower) });
    }

    /// Serialize one exact portable test computation without holding the publication
    /// lock; null while a collection holds the store, so the caller runs unclaimed.
    pub fn claim(self: Store, key: Digest) Error!?Claim {
        return work.Claim.attempt(self.arena, self.io, self.root, key) catch |err| return mapRetention(err);
    }

    /// Accept only an exact success envelope for this identity. A lookup takes no
    /// lock: receipts change only by atomic rename or unlink, so a vanished,
    /// truncated or different receipt is a miss.
    pub fn hit(self: Store, key: Digest) Error!bool {
        try self.validate();
        const found = try self.read(try self.artifactPath(key)) orelse return false;
        const verified = std.mem.eql(u8, found, try self.success(key));
        if (verified) self.retentionContext().touchPath(try self.artifactPath(key));
        return verified;
    }

    /// Atomically publish a completed success after the caller revalidates its inputs.
    /// A damaged receipt is replaced; a well-formed different one is a mismatch.
    pub fn save(self: Store, key: Digest) Error!Saved {
        const lease_guard = (self.retentionContext().tryLease() catch |err| return mapRetention(err)) orelse return .skipped;
        defer lease_guard.close(self.io);
        const guard = try self.lock(.exclusive);
        defer guard.close(self.io);
        try self.validate();
        const destination = try self.artifactPath(key);
        const bytes = try self.success(key);
        if (try self.read(destination)) |previous| {
            if (std.mem.eql(u8, previous, bytes)) {
                self.retentionContext().touchPath(destination);
                return .present;
            }
            if (sealed(previous, key)) {
                self.retentionContext().mismatch(.{ .kind = "receipt", .key = key, .existing = digestOf(previous), .attempted = digestOf(bytes) });
                return .mismatch;
            }
        }
        std.Io.Dir.cwd().createDirPath(self.io, try self.path("receipts")) catch return error.WriteFailed;
        try self.publish(destination, bytes);
        return .stored;
    }

    /// Discard an earlier success before an explicit forced execution begins.
    pub fn invalidate(self: Store, key: Digest) Error!void {
        const lease_guard = try self.lease();
        defer lease_guard.close(self.io);
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

// A well-formed envelope for `key`: the versioned header, this identity, and a
// checksum line that matches the payload before it. Damage fails the check.
fn sealed(record: []const u8, key: Digest) bool {
    const trailer = 64 + 1;
    if (record.len <= trailer or record[record.len - 1] != '\n') return false;
    const payload = record[0 .. record.len - trailer];
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &checksum, .{});
    if (!std.mem.eql(u8, record[record.len - trailer .. record.len - 1], &std.fmt.bytesToHex(checksum, .lower))) return false;
    const header = "selka-shared-test-v1\n";
    if (!std.mem.startsWith(u8, payload, header)) return false;
    const identity = payload[header.len..];
    return identity.len > 65 and std.mem.eql(u8, identity[0..64], &std.fmt.bytesToHex(key, .lower)) and identity[64] == '\n';
}

fn digestOf(bytes: []const u8) Digest {
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return digest;
}

fn mapRetention(err: retention.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => error.ReadFailed,
        else => error.WriteFailed,
    };
}

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
    _ = try store.save(key);
    const other = try Store.open(a, std.testing.io, root);
    try std.testing.expect(try other.hit(key));
    try std.testing.expect(!try other.hit(@splat(8)));
    const path = try store.artifactPath(key);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expect(!try other.hit(key));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.partial", .{path}), .data = "interrupted" });
    try std.testing.expect(!try other.hit(key));
    _ = try other.save(key);
    try std.testing.expect(try store.hit(key));
    try other.invalidate(key);
    try std.testing.expect(!try store.hit(key));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = &(@as([513]u8, @splat('x'))) });
    try std.testing.expect(!try store.hit(key));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.Io.Dir.cwd().symLink(std.testing.io, try store.path("format"), path, .{});
    try std.testing.expect(!try store.hit(key));
    _ = try store.save(key);
    try std.testing.expect(try store.hit(key));
    try store.invalidate(key);
    try std.Io.Dir.cwd().symLink(std.testing.io, try store.path("format"), try std.fmt.allocPrint(a, "{s}.partial", .{path}), .{});
    _ = try store.save(key);
    try std.testing.expectEqualStrings(format, (try store.read(try store.path("format"))).?);
    try std.testing.expect(try store.hit(key));
    try store.invalidate(key);
    const fifo = try a.dupeSentinel(u8, path, 0);
    try std.testing.expectEqual(std.os.linux.E.SUCCESS, std.os.linux.errno(std.os.linux.mknod(fifo, std.os.linux.S.IFIFO | 0o600, 0)));
    try std.testing.expect(!try store.hit(key));
    _ = try store.save(key);
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

// spec-case: NATIVE-CACHE-RETENTION-1
test "shared receipt verified hits refresh retention while corruption remains old" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(21);
    _ = try store.save(key);
    const path_name = try store.artifactPath(key);
    try std.Io.Dir.cwd().setTimestamps(io, path_name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    try std.testing.expect(try store.hit(key));
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, path_name, .{})).mtime.nanoseconds > 1);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path_name, .data = "corrupt" });
    try std.Io.Dir.cwd().setTimestamps(io, path_name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    try std.testing.expect(!try store.hit(key));
    try std.testing.expectEqual(@as(i96, 1), (try std.Io.Dir.cwd().statFile(io, path_name, .{})).mtime.nanoseconds);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "shared receipt collection misses refill and protects publication lock inodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(22);
    _ = try store.save(key);
    const context = store.retentionContext();
    var policy = retention.Policy.defaults(.tests);
    policy.max_entries = 0;
    const lease_guard = try context.lease();
    const publication = try store.lock(.exclusive);
    const lock_path = try store.path(".lock");
    const before = try std.Io.Dir.cwd().statFile(io, lock_path, .{});
    try std.testing.expect((try context.collect(policy, false)).skipped_active);
    try std.testing.expectEqual(before.inode, (try std.Io.Dir.cwd().statFile(io, lock_path, .{})).inode);
    publication.close(io);
    lease_guard.close(io);
    try std.testing.expectEqual(@as(usize, 1), (try context.collect(policy, false)).removed.entries);
    try std.testing.expect(!try store.hit(key));
    _ = try store.save(key);
    try std.testing.expect(try store.hit(key));
}

// spec: NATIVE-TEST-COALESCE-1
test "portable test claims retain storage and invalidate forced successes before followers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(31);
    _ = try store.save(key);
    var claim = (try store.claim(key)).?;
    const path_name = try std.fmt.allocPrint(a, "{s}/work/{s}.lock", .{ store.root, std.fmt.bytesToHex(key, .lower) });
    const contender = try std.Io.Dir.cwd().openFile(io, path_name, .{ .mode = .read_write });
    defer contender.close(io);
    try std.testing.expect(!try contender.tryLock(io, .exclusive));
    var independent = (try store.claim(@splat(32))).?;
    independent.deinit();
    var policy = retention.Policy.defaults(.tests);
    policy.max_entries = 0;
    try std.testing.expect((try store.retentionContext().collect(policy, false)).skipped_active);
    try store.invalidate(key);
    try std.testing.expect(!try store.hit(key));
    claim.deinit();
    try std.testing.expect(try contender.tryLock(io, .exclusive));
    contender.unlock(io);
    var retry = (try store.claim(key)).?;
    defer retry.deinit();
    try std.testing.expect(!try store.hit(key));
    _ = try store.save(key);
    try std.testing.expect(try store.hit(key));
}

// spec: SHARED-STORE-3
test "shared receipt mismatch is a logged miss that keeps the existing receipt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(41);
    const payload = try std.fmt.allocPrint(a, "selka-shared-test-v1\n{s}\nfailed\n", .{std.fmt.bytesToHex(key, .lower)});
    const foreign = try std.fmt.allocPrint(a, "{s}{s}\n", .{ payload, std.fmt.bytesToHex(digestOf(payload), .lower) });
    try std.Io.Dir.cwd().createDirPath(io, try store.path("receipts"));
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try store.artifactPath(key), .data = foreign });
    try std.testing.expect(!try store.hit(key));
    try std.testing.expectEqual(Saved.mismatch, try store.save(key));
    try std.testing.expectEqualStrings(foreign, (try store.read(try store.artifactPath(key))).?);
    try std.testing.expect(!try store.hit(key));
    const attempted = std.fmt.bytesToHex(digestOf(try store.success(key)), .lower);
    const expected = try std.fmt.allocPrint(a, "mismatch receipt {s} existing={s} attempted={s}\n", .{ std.fmt.bytesToHex(key, .lower), std.fmt.bytesToHex(digestOf(foreign), .lower), attempted });
    try std.testing.expectEqualStrings(expected, (try store.read(try store.path("mismatches.log"))).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try store.artifactPath(key), .data = foreign[0 .. foreign.len - 2] });
    try std.testing.expectEqual(Saved.stored, try store.save(key));
    try std.testing.expectEqual(Saved.present, try store.save(key));
    try std.testing.expect(try store.hit(key));
    try std.testing.expectEqualStrings(expected, (try store.read(try store.path("mismatches.log"))).?);
}

// spec: SHARED-STORE-5
test "shared receipt opens and lookups complete while a sweep holds the store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(42);
    try std.testing.expectEqual(Saved.stored, try store.save(key));
    const sweep = try std.Io.Dir.cwd().openFile(io, try store.path(".retention.lock"), .{ .mode = .read_write });
    defer sweep.close(io);
    try std.testing.expect(try sweep.tryLock(io, .exclusive));
    const second = try Store.open(a, io, root);
    try std.testing.expect(try second.hit(key));
    try std.testing.expectEqual(Saved.skipped, try second.save(@splat(43)));
    try std.testing.expect((try second.claim(key)) == null);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try second.artifactPath(key), .data = "selka-shared-test-v1\n" });
    try std.testing.expect(!try second.hit(key));
    try std.Io.Dir.cwd().deleteFile(io, try second.artifactPath(key));
    try std.testing.expect(!try second.hit(key));
    sweep.unlock(io);
    try std.testing.expectEqual(Saved.stored, try second.save(key));
    try std.testing.expect(try store.hit(key));
}

const concurrent_publishers = 8;
const concurrent_keys = 16;

// One thread's open of a fresh receipt store and its save of every shared key.
const ConcurrentSaver = struct {
    root: []const u8,
    backing: std.mem.Allocator,
    start: *const std.atomic.Value(bool),
    failure: ?anyerror = null,
    stored: usize = 0,
    mismatches: usize = 0,

    fn run(self: *ConcurrentSaver) void {
        self.saveAll() catch |err| {
            self.failure = err;
        };
    }

    fn saveAll(self: *ConcurrentSaver) !void {
        while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
        var arena = std.heap.ArenaAllocator.init(self.backing);
        defer arena.deinit();
        const store = try Store.open(arena.allocator(), std.testing.io, self.root);
        for (0..concurrent_keys) |index| {
            switch (try store.save(concurrentKey(index))) {
                .stored => self.stored += 1,
                .mismatch => self.mismatches += 1,
                .present, .skipped => {},
            }
        }
    }
};

fn concurrentKey(index: usize) Digest {
    return @splat(@intCast(index + 101));
}

// Start every saver at once against one store root and wait for all.
fn saveConcurrently(root: []const u8, backing: std.mem.Allocator, savers: *[concurrent_publishers]ConcurrentSaver) !void {
    var start: std.atomic.Value(bool) = .init(false);
    var threads: [concurrent_publishers]std.Thread = undefined;
    var started: usize = 0;
    defer for (threads[0..started]) |thread| thread.join();
    // Release the started savers before joining, even when a spawn fails.
    defer start.store(true, .release);
    for (savers, &threads) |*saver, *thread| {
        saver.* = .{ .root = root, .backing = backing, .start = &start };
        thread.* = try std.Thread.spawn(.{}, ConcurrentSaver.run, .{saver});
        started += 1;
    }
}

const ConcurrentTotals = struct { failures: usize = 0, stored: usize = 0, mismatches: usize = 0 };

fn concurrentTotals(savers: []const ConcurrentSaver) ConcurrentTotals {
    var totals: ConcurrentTotals = .{};
    for (savers) |saver| {
        if (saver.failure != null) totals.failures += 1;
        totals.stored += saver.stored;
        totals.mismatches += saver.mismatches;
    }
    return totals;
}

// Every key is a verified hit after a sequential save, which finds it present
// (or stores one a sweep made every saver skip), never a mismatch.
fn expectConcurrentReceipts(store: Store) !void {
    for (0..concurrent_keys) |index| {
        const again = try store.save(concurrentKey(index));
        try std.testing.expect(again == .present or again == .stored);
        try std.testing.expect(try store.hit(concurrentKey(index)));
    }
}

// spec-case: SHARED-STORE-6
test "concurrent first openers initialize one fresh receipt store and save every key once without failure or mismatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try std.fs.path.join(a, &.{ try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), "fresh", "store" });
    var savers: [concurrent_publishers]ConcurrentSaver = undefined;
    try saveConcurrently(root, std.testing.allocator, &savers);
    const totals = concurrentTotals(&savers);
    try std.testing.expectEqual(@as(usize, 0), totals.failures);
    try std.testing.expectEqual(@as(usize, 0), totals.mismatches);
    try std.testing.expect(totals.stored <= concurrent_keys);
    const store = try Store.open(a, std.testing.io, root);
    try expectConcurrentReceipts(store);
    try std.testing.expectEqualStrings(format, (try store.read(try store.path("format"))).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try store.read(try store.path("mismatches.log")));
}
