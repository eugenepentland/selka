//! Opt-in immutable compiler artifacts. Indexes and materialized executables stay local.
const std = @import("std");
const storage = @import("shared_artifact_io.zig");
const retention = @import("native_cache_retention.zig");
const work = @import("native_cache_work.zig");
const policy = @import("shared_cache_policy.zig");

/// Explicit opt-in, independent of private caches and shared test-success receipts.
pub const environment_variable = "MYLANG_COMPILER_SHARED_CACHE";
/// Per-artifact bound; oversized entries use the ordinary private compilation path.
pub const maximum_payload = 128 * 1024 * 1024;
/// Storage failures; corruption is a miss and conflicting valid outputs are a
/// logged `Publication.mismatch`, never an error.
pub const Error = storage.Error;
/// What one publication did. Only `stored` wrote a record.
pub const Publication = enum {
    /// The bytes were staged and renamed into place.
    stored,
    /// A verified record already held exactly these bytes; nothing was written.
    present,
    /// Nothing was published: the payload is oversized or a collection holds the store.
    skipped,
    /// A verified record holds different bytes for this key. It is kept, nothing
    /// is published, and the pair of digests is appended to `mismatches.log`.
    mismatch,
};
/// Independent serializer domains under one versioned storage namespace.
pub const Kind = enum(u8) { syntax = 1, typed = 2, program = 3 };
/// Complete producer key supplied by the syntax, semantic or native layer.
pub const Key = [32]u8;
const format = "selka-compiler-artifact-store-v2\n";
const magic = "selka-compiler-blob-v1\x00";
const header_size = magic.len + 1 + 32 + 8 + 32;

/// Nonempty configured roots opt in; an empty value explicitly disables sharing.
pub fn selected(environment: *const std.process.Environ.Map) ?[]const u8 {
    const root = environment.get(environment_variable) orelse return null;
    return if (root.len == 0) null else root;
}

/// Open the store a command uses. An explicit setting opens it or fails; an unset
/// variable opens the per-user default only while `default_sharing` is on, and a
/// default store that cannot be opened prints one warning and yields null.
pub fn openSelected(a: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map) Error!?Store {
    return openSelectedWith(a, io, environment, policy.default_sharing);
}

fn openSelectedWith(a: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, sharing: bool) Error!?Store {
    const selection = try policy.resolveWith(a, environment, .compiler, null, sharing) orelse return null;
    defer if (selection.origin == .default) a.free(selection.path);
    const store = Store.open(a, io, selection.path) catch |err| {
        if (err == error.OutOfMemory or selection.origin == .explicit) return err;
        var buffer: [512]u8 = undefined;
        const warning = std.fmt.bufPrint(&buffer, "warning: shared compiler cache {s}: {s}; sharing disabled\n", .{ selection.path, @errorName(err) }) catch "warning: shared compiler cache unusable; sharing disabled\n";
        std.Io.File.stderr().writeStreamingAll(io, warning) catch return null;
        return null;
    };
    return store;
}

/// A bounded immutable store with independent exact-key work claims.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    serial: std.atomic.Value(u64) = .init(0),

    /// Create or validate a dedicated namespace. Release the owned path with deinit.
    /// An existing namespace is validated without any lock, and the throttled
    /// sweep that follows only tries its exclusive admission, so no open waits on
    /// another process's sweep.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Store {
        if (directory.len == 0) return error.WriteFailed;
        const self: Store = .{ .allocator = a, .io = io, .root = try std.fs.path.join(a, &.{ directory, "compiler-artifacts-v2" }) };
        errdefer a.free(self.root);
        try self.initialize();
        self.retentionContext().automatic();
        return self;
    }

    fn retentionContext(self: *const Store) retention.Context {
        return retention.Context.init(self.allocator, self.io, self.root, .compiler);
    }

    // Concurrent first openers race to create one namespace (SHARED-STORE-6).
    // Each attempt tolerates directories and a marker a peer already created; a
    // failed attempt is retried a bounded number of times, re-reading whatever
    // a peer published meanwhile, so only a store that stays unusable fails.
    fn initialize(self: *const Store) Error!void {
        try retention.retried(self, createNamespace);
        _ = try self.retentionContext().policy();
    }

    // A present marker is checked without any lock. Only first creation takes the
    // exclusive `.lock`, and it re-reads the marker under it. No sweep can run
    // before the marker exists, so creation needs no retention lease.
    fn createNamespace(self: *const Store) Error!void {
        std.Io.Dir.cwd().createDirPath(self.io, self.root) catch return error.WriteFailed;
        if (try self.marked()) return;
        const lock_path = try self.path(".lock");
        defer self.allocator.free(lock_path);
        const guard = try storage.lock(self.allocator, self.io, lock_path);
        defer guard.close(self.io);
        if (!try self.marked()) try self.writeMarker();
    }

    fn marked(self: *const Store) Error!bool {
        const marker = try self.path("format");
        defer self.allocator.free(marker);
        const bytes = try storage.bounded(self.allocator, self.io, marker, 128) orelse return false;
        defer self.allocator.free(bytes);
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
        return true;
    }

    fn writeMarker(self: *const Store) Error!void {
        const a = self.allocator;
        const io = self.io;
        const cwd = std.Io.Dir.cwd();
        var directory_handle = cwd.openDir(io, self.root, .{ .iterate = true }) catch return error.ReadFailed;
        defer directory_handle.close(io);
        var entries = directory_handle.iterate();
        while (entries.next(io) catch return error.ReadFailed) |entry| {
            if (std.mem.eql(u8, entry.name, ".retention.lock") or std.mem.eql(u8, entry.name, ".lock") or std.mem.eql(u8, entry.name, "format.partial")) continue;
            return error.ReadFailed;
        }
        const marker = try self.path("format");
        defer a.free(marker);
        const temporary = try self.path("format.partial");
        defer a.free(temporary);
        storage.remove(io, temporary);
        defer storage.remove(io, temporary);
        const file = cwd.createFile(io, temporary, .{ .exclusive = true }) catch return error.WriteFailed;
        defer file.close(io);
        file.writeStreamingAll(io, format) catch return error.WriteFailed;
        cwd.rename(temporary, cwd, marker, io) catch return error.WriteFailed;
    }

    /// Release the path; committed artifacts and permanent lock files remain.
    pub fn deinit(self: *Store) void {
        self.allocator.free(self.root);
    }

    /// Emit a useful storage diagnosis before a frontend maps the failure to its error set.
    pub fn reportFailure(self: *const Store, err: anyerror) void {
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "error: shared compiler cache: {s}\n", .{@errorName(err)}) catch return;
        std.Io.File.stderr().writeStreamingAll(self.io, text) catch return;
    }

    /// Load verified bytes into the caller's allocator; damaged records miss.
    /// Reads hold no lease: records are immutable inodes replaced only by rename,
    /// so an entry a sweep evicts is either read whole through its open handle or
    /// missed.
    pub fn load(self: *const Store, a: std.mem.Allocator, kind: Kind, key: Key) Error!?[]u8 {
        const entry = try self.record(kind, key) orelse return null;
        defer entry.file.close(self.io);
        const bytes = try a.alloc(u8, entry.content.size);
        errdefer a.free(bytes);
        const count = entry.file.readPositionalAll(self.io, bytes, header_size) catch return error.ReadFailed;
        if (count != bytes.len) {
            a.free(bytes);
            return null;
        }
        var digest: Key = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        if (!std.mem.eql(u8, &digest, &entry.content.digest)) {
            a.free(bytes);
            return null;
        }
        self.retentionContext().touch(entry.file);
        return bytes;
    }

    /// Retain exact serialized bytes; valid same-key disagreement is never overwritten.
    pub fn save(self: *Store, kind: Kind, key: Key, bytes: []const u8) Error!Publication {
        if (bytes.len > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .bytes = bytes }, bytes.len);
    }

    /// Stream a private artifact into shared storage without allocating its contents.
    pub fn publishFile(self: *Store, kind: Kind, key: Key, source: []const u8) Error!Publication {
        const file = try storage.regular(self.allocator, self.io, source) orelse return error.ReadFailed;
        defer file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .file = file }, @intCast(size));
    }

    /// Stream verified bytes to a new private staging file; a corrupt, truncated or
    /// vanished record is a miss and its partial copy is removed. Holds no lease.
    pub fn restore(self: *const Store, kind: Kind, key: Key, destination: []const u8) Error!bool {
        const entry = try self.record(kind, key) orelse return false;
        defer entry.file.close(self.io);
        const output = std.Io.Dir.cwd().createFile(self.io, destination, .{ .exclusive = true }) catch return error.WriteFailed;
        defer output.close(self.io);
        var keep = false;
        defer if (!keep) storage.remove(self.io, destination);
        const actual = storage.transfer(self.io, entry.file, output, header_size, entry.content.size) catch |err| {
            if (err == error.InputChanged) return false;
            return err;
        };
        if (!std.mem.eql(u8, &actual.digest, &entry.content.digest)) return false;
        output.setPermissions(self.io, .fromMode(if (kind == .program) 0o700 else 0o600)) catch return error.WriteFailed;
        keep = true;
        self.retentionContext().touch(entry.file);
        return true;
    }

    /// Coordinate expensive native work while retaining the namespace lease; null
    /// while a collection holds the store, so the caller works unclaimed.
    pub fn claim(self: *const Store, kind: Kind, key: Key) work.Error!?work.Claim {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(@tagName(kind));
        hash.update(&key);
        var work_key: Key = undefined;
        hash.final(&work_key);
        return work.Claim.attempt(self.allocator, self.io, self.root, work_key);
    }

    /// The immutable record path, useful for storage inspection and corruption tests.
    pub fn artifactPath(self: *const Store, kind: Kind, key: Key) Error![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}.blob", .{ self.root, @tagName(kind), std.fmt.bytesToHex(key, .lower) });
    }

    fn path(self: *const Store, leaf: []const u8) Error![]u8 {
        return std.fs.path.join(self.allocator, &.{ self.root, leaf });
    }

    fn validate(self: *const Store) Error!void {
        const path_name = try self.path("format");
        defer self.allocator.free(path_name);
        const bytes = try storage.bounded(self.allocator, self.io, path_name, 128) orelse return error.ReadFailed;
        defer self.allocator.free(bytes);
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
    }

    fn record(self: *const Store, kind: Kind, key: Key) Error!?Record {
        try self.validate();
        const path_name = try self.artifactPath(kind, key);
        defer self.allocator.free(path_name);
        const file = try storage.regular(self.allocator, self.io, path_name) orelse return null;
        var keep = false;
        defer if (!keep) file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size < header_size or size > header_size + maximum_payload) return null;
        var header: [header_size]u8 = undefined;
        if ((file.readPositionalAll(self.io, &header, 0) catch return error.ReadFailed) != header.len) return null;
        const content = decode(&header, kind, key) orelse return null;
        if (content.size != size - header_size) return null;
        keep = true;
        return .{ .file = file, .content = content };
    }

    // A record for the key whose payload matches its header; null when absent or damaged.
    fn verified(self: *const Store, kind: Kind, key: Key) Error!?Record {
        const entry = try self.record(kind, key) orelse return null;
        var keep = false;
        defer if (!keep) entry.file.close(self.io);
        const actual = storage.transfer(self.io, entry.file, null, header_size, entry.content.size) catch |err| {
            if (err == error.InputChanged) return null;
            return err;
        };
        if (!std.mem.eql(u8, &actual.digest, &entry.content.digest)) return null;
        keep = true;
        return entry;
    }

    // One per-key lock covers comparison, staging and replacement. An existing
    // verified record is compared by hashing the input in place, so a repeated
    // publication stages nothing and renames nothing; only an absent or damaged
    // record is staged. The lease is only tried: a running sweep skips publication.
    fn publish(self: *Store, kind: Kind, key: Key, input: Input, size: usize) Error!Publication {
        const lease = try self.retentionContext().tryLease() orelse return .skipped;
        defer lease.close(self.io);
        try self.validate();
        const a = self.allocator;
        const directory = try self.path(@tagName(kind));
        defer a.free(directory);
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(self.io, directory) catch return error.WriteFailed;
        const target = try self.artifactPath(kind, key);
        defer a.free(target);
        const lock_name = try std.fmt.allocPrint(a, "{s}.lock", .{target});
        defer a.free(lock_name);
        const guard = try storage.lock(a, self.io, lock_name);
        defer guard.close(self.io);
        if (try self.verified(kind, key)) |previous| {
            defer previous.file.close(self.io);
            const attempted = try measure(self.io, input, size);
            if (attempted.size == previous.content.size and std.mem.eql(u8, &attempted.digest, &previous.content.digest)) {
                self.retentionContext().touch(previous.file);
                return .present;
            }
            self.retentionContext().mismatch(.{ .kind = @tagName(kind), .key = key, .existing = previous.content.digest, .attempted = attempted.digest });
            return .mismatch;
        }
        const staged = try stage(self, directory);
        defer a.free(staged.path);
        defer storage.remove(self.io, staged.path);
        _ = try stageContents(self.io, staged.file, input, .{ .kind = kind, .key = key, .size = size });
        try self.validate();
        cwd.rename(staged.path, cwd, target, self.io) catch return error.WriteFailed;
        return .stored;
    }
};

const Record = struct { file: std.Io.File, content: storage.Content };
const Input = union(enum) { bytes: []const u8, file: std.Io.File };
const Address = struct { kind: Kind, key: Key, size: usize };
const Staged = struct { file: std.Io.File, path: []u8 };

fn stage(store: *Store, directory: []const u8) Error!Staged {
    const a = store.allocator;
    const io = store.io;
    for (0..1024) |_| {
        const path = try std.fmt.allocPrint(a, "{s}/.{d}-{x}-{d}.partial", .{ directory, std.os.linux.getpid(), @intFromPtr(store), store.serial.fetchAdd(1, .monotonic) });
        const file = std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true }) catch |err| {
            a.free(path);
            if (err == error.PathAlreadyExists) continue;
            return error.WriteFailed;
        };
        return .{ .file = file, .path = path };
    }
    return error.WriteFailed;
}

// The input's length and digest, read in place without writing a copy.
fn measure(io: std.Io, input: Input, size: usize) Error!storage.Content {
    switch (input) {
        .bytes => |bytes| {
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            return .{ .size = bytes.len, .digest = digest };
        },
        .file => |source| {
            const result = try storage.transfer(io, source, null, 0, size);
            if ((source.stat(io) catch return error.ReadFailed).size != size) return error.InputChanged;
            return result;
        },
    }
}

fn stageContents(io: std.Io, file: std.Io.File, input: Input, address: Address) Error!storage.Content {
    defer file.close(io);
    file.writeStreamingAll(io, &@as([header_size]u8, @splat(0))) catch return error.WriteFailed;
    const content: storage.Content = switch (input) {
        .bytes => |bytes| content: {
            file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            break :content .{ .size = bytes.len, .digest = digest };
        },
        .file => |source| content: {
            const result = try storage.transfer(io, source, file, 0, address.size);
            if ((source.stat(io) catch return error.ReadFailed).size != address.size) return error.InputChanged;
            break :content result;
        },
    };
    const header = encode(address.kind, address.key, content);
    file.writePositionalAll(io, &header, 0) catch return error.WriteFailed;
    return content;
}

fn encode(kind: Kind, key: Key, content: storage.Content) [header_size]u8 {
    var bytes: [header_size]u8 = undefined;
    @memcpy(bytes[0..magic.len], magic);
    bytes[magic.len] = @backingInt(kind);
    @memcpy(bytes[magic.len + 1 ..][0..32], &key);
    std.mem.writeInt(u64, bytes[magic.len + 33 ..][0..8], content.size, .little);
    @memcpy(bytes[magic.len + 41 ..][0..32], &content.digest);
    return bytes;
}

fn decode(bytes: *const [header_size]u8, kind: Kind, key: Key) ?storage.Content {
    if (!std.mem.eql(u8, bytes[0..magic.len], magic) or bytes[magic.len] != @backingInt(kind)) return null;
    if (!std.mem.eql(u8, bytes[magic.len + 1 ..][0..32], &key)) return null;
    const size = std.mem.readInt(u64, bytes[magic.len + 33 ..][0..8], .little);
    if (size > maximum_payload) return null;
    return .{ .size = @intCast(size), .digest = bytes[magic.len + 41 ..][0..32].* };
}

// spec-case: SHARED-STORE-4
test "openSelected fails an explicit unusable store and skips an unusable default one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = ".cache", .data = "a file where the cache directory belongs" });
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", root);
    try std.testing.expect((try openSelectedWith(a, io, &environment, false)) == null);
    try std.testing.expect((try openSelectedWith(a, io, &environment, true)) == null);
    try temporary.dir.deleteFile(io, ".cache");
    var default = (try openSelectedWith(a, io, &environment, true)).?;
    defer default.deinit();
    try std.testing.expect(std.mem.endsWith(u8, default.root, ".cache/mylang/compiler-artifacts/compiler-artifacts-v2"));
    try temporary.dir.writeFile(io, .{ .sub_path = "blocked", .data = "not a directory" });
    try environment.put(environment_variable, try std.fs.path.join(a, &.{ root, "blocked" }));
    try std.testing.expectError(error.WriteFailed, openSelectedWith(a, io, &environment, true));
    try std.testing.expectError(error.WriteFailed, openSelected(a, io, &environment));
    try environment.put(environment_variable, "");
    try std.testing.expect((try openSelected(a, io, &environment)) == null);
}

const concurrent_publishers = 8;
const concurrent_keys = 16;

// One thread's open of a fresh store and its publication of every shared key.
const ConcurrentPublisher = struct {
    root: []const u8,
    backing: std.mem.Allocator,
    start: *const std.atomic.Value(bool),
    failure: ?anyerror = null,
    stored: usize = 0,
    mismatches: usize = 0,

    fn run(self: *ConcurrentPublisher) void {
        self.publishAll() catch |err| {
            self.failure = err;
        };
    }

    fn publishAll(self: *ConcurrentPublisher) !void {
        while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
        var arena = std.heap.ArenaAllocator.init(self.backing);
        defer arena.deinit();
        var store = try Store.open(arena.allocator(), std.testing.io, self.root);
        defer store.deinit();
        for (0..concurrent_keys) |index| {
            const key = concurrentKey(index);
            switch (try store.save(.syntax, key, &key)) {
                .stored => self.stored += 1,
                .mismatch => self.mismatches += 1,
                .present, .skipped => {},
            }
        }
    }
};

fn concurrentKey(index: usize) Key {
    return @splat(@intCast(index + 1));
}

// Start every publisher at once against one store root and wait for all.
fn publishConcurrently(root: []const u8, backing: std.mem.Allocator, publishers: *[concurrent_publishers]ConcurrentPublisher) !void {
    var start: std.atomic.Value(bool) = .init(false);
    var threads: [concurrent_publishers]std.Thread = undefined;
    var started: usize = 0;
    defer for (threads[0..started]) |thread| thread.join();
    // Release the started publishers before joining, even when a spawn fails.
    defer start.store(true, .release);
    for (publishers, &threads) |*publisher, *thread| {
        publisher.* = .{ .root = root, .backing = backing, .start = &start };
        thread.* = try std.Thread.spawn(.{}, ConcurrentPublisher.run, .{publisher});
        started += 1;
    }
}

const ConcurrentTotals = struct { failures: usize = 0, stored: usize = 0, mismatches: usize = 0 };

fn concurrentTotals(publishers: []const ConcurrentPublisher) ConcurrentTotals {
    var totals: ConcurrentTotals = .{};
    for (publishers) |publisher| {
        if (publisher.failure != null) totals.failures += 1;
        totals.stored += publisher.stored;
        totals.mismatches += publisher.mismatches;
    }
    return totals;
}

// Every key holds exactly its bytes; a sequential republication finds them
// present (or stores one a sweep made every publisher skip), never a mismatch.
fn expectConcurrentRecords(store: *Store, a: std.mem.Allocator) !void {
    for (0..concurrent_keys) |index| {
        const key = concurrentKey(index);
        const again = try store.save(.syntax, key, &key);
        try std.testing.expect(again == .present or again == .stored);
        try std.testing.expectEqualSlices(u8, &key, (try store.load(a, .syntax, key)).?);
    }
}

// Staged partial files left in a tier directory; a finished publication leaves none.
fn leftoverPartials(io: std.Io, directory: []const u8) !usize {
    var tier = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer tier.close(io);
    var entries = tier.iterate();
    var partials: usize = 0;
    while (try entries.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".partial")) partials += 1;
    }
    return partials;
}

// spec: SHARED-STORE-6
test "concurrent first openers initialize one fresh compiler store and publish every key once without failure or mismatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try std.fs.path.join(a, &.{ try temporary.dir.realPathFileAlloc(io, ".", a), "fresh", "store" });
    var publishers: [concurrent_publishers]ConcurrentPublisher = undefined;
    try publishConcurrently(root, std.testing.allocator, &publishers);
    const totals = concurrentTotals(&publishers);
    try std.testing.expectEqual(@as(usize, 0), totals.failures);
    try std.testing.expectEqual(@as(usize, 0), totals.mismatches);
    try std.testing.expect(totals.stored <= concurrent_keys);
    var store = try Store.open(a, io, root);
    defer store.deinit();
    try expectConcurrentRecords(&store, a);
    try std.testing.expectEqualStrings(format, (try storage.bounded(a, io, try store.path("format"), 128)).?);
    try std.testing.expectEqual(@as(?[]u8, null), try storage.bounded(a, io, try store.path("mismatches.log"), 4096));
    try std.testing.expectEqual(@as(usize, 0), try leftoverPartials(io, try store.path("syntax")));
}
