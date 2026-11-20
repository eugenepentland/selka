//! The native test store: a per-user directory (`native-tests-v3`) that holds the engine's shared records. Records are
//! disposable, bounded, published under a short process lock and read without one; the store's lease, size policy and
//! retention (`selka cache gc --kind tests`) are the native cache's.
const std = @import("std");
const work = @import("selka").native_cache_work;
const retention = @import("selka").native_cache_retention;
/// A record's key.
pub const Digest = [32]u8;
/// Explicitly configured storage must be usable; damaged records remain misses.
pub const Error = error{ OutOfMemory, ReadFailed, WriteFailed };
/// What one `recordPublish` did. Only `stored` wrote a record.
pub const Saved = enum {
    /// The record was written.
    stored,
    /// The identical record was already present; its recency was refreshed.
    present,
    /// A collection holds the store, so nothing was written and nothing waited.
    skipped,
    /// A record under this key holds another result. It is kept, nothing is written, and the pair is appended to
    /// `mismatches.log`.
    mismatch,
};
const format = "selka-native-test-store-v3\n";
const maximum_record = 512;
/// The largest engine record the tier holds or reads.
const maximum_engine_record = 64 * 1024;

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

    /// Address an engine record directly: `engine/<key>.rec`, under the store's lease, policy and retention. Lookup never
    /// enumerates the store.
    pub fn recordPath(self: Store, key: Digest) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "{s}/engine/{s}.rec", .{ self.root, std.fmt.bytesToHex(key, .lower) });
    }

    /// The bytes of the engine record under `key`, or null when it is absent, not a regular file or too large. A hit
    /// refreshes the record's recency. The caller decodes and validates the record; this store only holds the bytes.
    pub fn recordRead(self: Store, key: Digest) Error!?[]const u8 {
        try self.validate();
        const record_file = try self.recordPath(key);
        const found = try self.readUpTo(record_file, maximum_engine_record) orelse return null;
        self.retentionContext().touchPath(record_file);
        return found;
    }

    /// Whether an engine record of `key` is there, by a stat that follows no link and changes no recency.
    pub fn recordPresent(self: Store, key: Digest) bool {
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const record_file = std.fmt.bufPrint(&buffer, "{s}/engine/{s}.rec", .{ self.root, std.fmt.bytesToHex(key, .lower) }) catch return false;
        const info = std.Io.Dir.cwd().statFile(self.io, record_file, .{ .follow_symlinks = false }) catch return false;
        return info.kind == .file;
    }

    /// Publish an engine record atomically under the short publication lock; a collection that holds the store makes it
    /// `.skipped`, and a record too large for the tier is `.skipped` as well. A record already under the key is replaced:
    /// the caller has compared results first (`recordMismatch`).
    pub fn recordPublish(self: Store, key: Digest, bytes: []const u8) Error!Saved {
        if (bytes.len > maximum_engine_record) return .skipped;
        const lease_guard = (self.retentionContext().tryLease() catch |err| return mapRetention(err)) orelse return .skipped;
        defer lease_guard.close(self.io);
        const guard = try self.lock(.exclusive);
        defer guard.close(self.io);
        try self.validate();
        std.Io.Dir.cwd().createDirPath(self.io, try self.path("engine")) catch return error.WriteFailed;
        try self.publish(try self.recordPath(key), bytes);
        return .stored;
    }

    /// Delete the engine record under `key`, under the store's lease and publication lock; best effort, a record that is not
    /// there or a store that is collected is left as it is.
    pub fn recordRemove(self: Store, key: Digest) void {
        const lease_guard = (self.retentionContext().tryLease() catch return) orelse return;
        defer lease_guard.close(self.io);
        const guard = self.lock(.exclusive) catch return;
        defer guard.close(self.io);
        const record_file = self.recordPath(key) catch return;
        std.Io.Dir.cwd().deleteFile(self.io, record_file) catch return;
    }

    /// Log that the engine record under `key` holds another result than the one being published: both digests, no
    /// timestamp, best effort. The record is kept and the publication dropped, a miss for both sides.
    pub fn recordMismatch(self: Store, key: Digest, existing: Digest, attempted: Digest) void {
        self.retentionContext().mismatch(.{ .kind = "engine", .key = key, .existing = existing, .attempted = attempted });
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
        return self.readUpTo(file_path, maximum_record);
    }

    fn readUpTo(self: Store, file_path: []const u8, limit: usize) Error!?[]const u8 {
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
        if (info.kind != .file or info.size > limit) return null;
        var reader = file.reader(self.io, &.{});
        return reader.interface.allocRemaining(self.arena, .limited(limit)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => null,
            else => error.ReadFailed,
        };
    }

    // A permanent lock inode serializes writers. An interrupted writer's partial
    // is never a record and the next writer safely replaces it under that lock.
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
test "the test store holds engine records, refuses oversized ones, reads only regular files and removes a record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store = try Store.open(a, std.testing.io, root);
    const key: Digest = @splat(3);
    try std.testing.expect((try store.recordRead(key)) == null);
    try std.testing.expect(!store.recordPresent(key));
    try std.testing.expectEqual(Saved.stored, try store.recordPublish(key, "a record"));
    try std.testing.expect(store.recordPresent(key));
    try std.testing.expectEqualStrings("a record", (try store.recordRead(key)).?);
    try std.testing.expectEqual(Saved.stored, try store.recordPublish(key, "another"));
    try std.testing.expectEqualStrings("another", (try store.recordRead(key)).?);
    const big = try a.alloc(u8, maximum_engine_record + 1);
    try std.testing.expectEqual(Saved.skipped, try store.recordPublish(@splat(4), big));
    try std.testing.expect(!store.recordPresent(@splat(4)));
    // A record the caller found wrong is removed; one that is not there is not an error.
    store.recordRemove(key);
    try std.testing.expect(!store.recordPresent(key));
    store.recordRemove(key);
    const record_file = try store.recordPath(key);
    try std.Io.Dir.cwd().symLink(std.testing.io, try store.path("format"), record_file, .{});
    try std.testing.expect((try store.recordRead(key)) == null);
    try std.testing.expect(!store.recordPresent(key));
    store.recordMismatch(key, @splat(1), @splat(2));
    const log = (try store.read(try store.path("mismatches.log"))).?;
    try std.testing.expect(std.mem.startsWith(u8, log, "mismatch engine "));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the test store preserves foreign formats and permanent lock ownership" {
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
    try std.testing.expectError(error.ReadFailed, store.recordRead(@splat(1)));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try store.path("format"));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try store.path("foreign"), .data = "preserve" });
    try std.testing.expectError(error.ReadFailed, Store.open(a, std.testing.io, root));
    try std.testing.expectEqualStrings("preserve", (try store.read(try store.path("foreign"))).?);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a record read refreshes retention and a stat does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(21);
    _ = try store.recordPublish(key, "record");
    const path_name = try store.recordPath(key);
    try std.Io.Dir.cwd().setTimestamps(io, path_name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    try std.testing.expect(store.recordPresent(key));
    try std.testing.expectEqual(@as(i96, 1), (try std.Io.Dir.cwd().statFile(io, path_name, .{})).mtime.nanoseconds);
    try std.testing.expect((try store.recordRead(key)) != null);
    try std.testing.expect((try std.Io.Dir.cwd().statFile(io, path_name, .{})).mtime.nanoseconds > 1);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a collection removes engine records, a miss refills, and publication lock inodes are protected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(22);
    _ = try store.recordPublish(key, "record");
    const context = store.retentionContext();
    var policy = retention.Policy.defaults(.tests);
    policy.max_entries = 0;
    const lease_guard = try context.lease();
    const publication = try store.lock(.exclusive);
    const lock_path = try store.path(".lock");
    const before = try std.Io.Dir.cwd().statFile(io, lock_path, .{});
    // A reader holds the namespace and the store's publication lock is held: the sweep runs beside them (F31), takes the engine
    // record, which needs no exclusive lease, and leaves the lock inode alone.
    const beside = try context.collect(policy, false);
    try std.testing.expect(beside.walk.leased and !beside.skipped_active);
    try std.testing.expectEqual(@as(usize, 1), beside.removed.entries);
    try std.testing.expectEqual(before.inode, (try std.Io.Dir.cwd().statFile(io, lock_path, .{})).inode);
    publication.close(io);
    lease_guard.close(io);
    try std.testing.expectEqual(@as(usize, 0), (try context.collect(policy, false)).removed.entries);
    try std.testing.expect((try store.recordRead(key)) == null);
    _ = try store.recordPublish(key, "record");
    try std.testing.expect((try store.recordRead(key)) != null);
}

// spec: SHARED-STORE-5
test "the test store opens and reads complete while a sweep holds it, and a publication is skipped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try Store.open(a, io, root);
    const key: Digest = @splat(42);
    try std.testing.expectEqual(Saved.stored, try store.recordPublish(key, "record"));
    const sweep = try std.Io.Dir.cwd().openFile(io, try store.path(".retention.lock"), .{ .mode = .read_write });
    defer sweep.close(io);
    try std.testing.expect(try sweep.tryLock(io, .exclusive));
    const second = try Store.open(a, io, root);
    try std.testing.expect((try second.recordRead(key)) != null);
    try std.testing.expectEqual(Saved.skipped, try second.recordPublish(@splat(43), "other"));
    sweep.unlock(io);
    try std.testing.expectEqual(Saved.stored, try second.recordPublish(@splat(43), "other"));
    try std.testing.expect((try store.recordRead(@splat(43))) != null);
}

const concurrent_publishers = 8;
const concurrent_keys = 16;

// One thread's open of a fresh store and its publication of every shared key.
const ConcurrentSaver = struct {
    root: []const u8,
    backing: std.mem.Allocator,
    start: *const std.atomic.Value(bool),
    failure: ?anyerror = null,
    stored: usize = 0,

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
            if (try store.recordPublish(concurrentKey(index), "record") == .stored) self.stored += 1;
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

const ConcurrentTotals = struct { failures: usize = 0, stored: usize = 0 };

fn concurrentTotals(savers: []const ConcurrentSaver) ConcurrentTotals {
    var totals: ConcurrentTotals = .{};
    for (savers) |saver| {
        if (saver.failure != null) totals.failures += 1;
        totals.stored += saver.stored;
    }
    return totals;
}

// spec-case: SHARED-STORE-6
test "concurrent first openers initialize one fresh store and publish every key without failure" {
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
    try std.testing.expect(totals.stored >= concurrent_keys);
    const store = try Store.open(a, std.testing.io, root);
    for (0..concurrent_keys) |index| try std.testing.expect(store.recordPresent(concurrentKey(index)));
    try std.testing.expectEqualStrings(format, (try store.read(try store.path("format"))).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try store.read(try store.path("mismatches.log")));
}

/// Put `count` small records in `dir`'s `engine` directory.
fn writeRecords(dir: std.Io.Dir, count: usize) !void {
    var name: [128]u8 = undefined;
    try dir.createDirPath(std.testing.io, "native-tests-v3/engine");
    for (0..count) |index| {
        const record = try std.fmt.bufPrint(&name, "native-tests-v3/engine/{x:0>64}.rec", .{index});
        try dir.writeFile(std.testing.io, .{ .sub_path = record, .data = "x" });
    }
}

/// Open the store at `root` `count` times in `a`, as a run opens it once per example.
fn openRepeatedly(a: std.mem.Allocator, root: []const u8, count: usize) !void {
    if (count == 0) return;
    _ = try Store.open(a, std.testing.io, root);
    try openRepeatedly(a, root, count - 1);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "opening the store again and again keeps nothing of its sweeps in the caller's arena" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store = try Store.open(a, std.testing.io, root);
    // A few hundred records and a policy that finds a sweep due at every open.
    try writeRecords(temporary.dir, 300);
    const context = retention.Context.init(a, std.testing.io, store.root, .tests);
    try std.testing.expect(try context.configure(.{ .max_bytes = 1 << 30, .max_entries = 1000, .interval_seconds = 0 }));
    var opened = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer opened.deinit();
    try openRepeatedly(opened.allocator(), root, 1);
    const settled = opened.queryCapacity();
    try openRepeatedly(opened.allocator(), root, 20);
    // A kept inventory costs more than a hundred bytes a record, 20 times over.
    try std.testing.expect(opened.queryCapacity() - settled < 64 * 1024);
}
