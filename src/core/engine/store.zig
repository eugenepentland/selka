//! The engine's store on disk (spec §7 and §8): one file per record, published by write-then-rename, objects named by
//! their digest, and in-flight markers. There is no journal or per-record lock: a reader opens the one file its key
//! names, and a record is either the old file or the new one. The records a build adopts from the shared tier are the
//! exception: they are one file written when the build ends (`pack.zig`).
//!
//! ```
//! engine-v1/
//!   records/<kind>/<code identity, 64 hex>/<key[0..2] hex>/<key hex>.rec
//!   packs/<ns, 20 digits>-<16 hex>.pack
//!   objects/<digest[0..2] hex>/<digest hex>
//!   inflight/<key hex>
//! ```
//!
//! Every failure to read is a miss and every failure to write is dropped: the store is a cache, and a query that
//! cannot be stored is still answered. Retention is `retention.zig`'s; this file only stamps a partition's last use.
const std = @import("std");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// The directory under a work directory that holds the engine's store.
pub const root_leaf = "engine-v1";
/// The payload size above which a result is an object shared by every kind (spec §7).
pub const object_threshold = 4096;
/// The largest record or object a lookup reads.
pub const read_limit = 1 << 30;
/// The file in a partition holding the time of its last use, in decimal nanoseconds (as the ownership pack store's partitions did).
pub const used_leaf = ".last-use";
/// The file in the store's root holding the time of the last scan for unreferenced objects.
pub const scanned_leaf = ".objects-scanned";
/// A partition's last-use stamp is rewritten only when older than this.
pub const touch_interval_ns: i64 = 60 * std.time.ns_per_s;
/// The file in a partition holding when the shared tier was last asked about the partition's served records, and which tier it was.
pub const swept_leaf = ".swept";
/// A file this size or smaller is read by one `pread` into a buffer on the stack: a record is a few KiB and an object tens of them, and sizing
/// the buffer first costs a system call of its own.
const small_read = 32 * 1024;

/// The store under one work directory.
pub const Store = struct {
    io: std.Io,
    /// `<work>/engine-v1`.
    root: []const u8,
    /// Numbers the partial files of this process.
    sequence: std.atomic.Value(u32) = .init(0),

    /// A store under `root`, which is the engine's directory (`<work>/engine-v1`). Nothing is created until a write.
    pub fn init(io: std.Io, root: []const u8) Store {
        return .{ .io = io, .root = root };
    }

    /// Delete the file at `path`. A file that is not there is already gone; any other failure leaves the file, which is as
    /// valid as it was.
    pub fn remove(self: *const Store, path: []const u8) void {
        std.Io.Dir.cwd().deleteFile(self.io, path) catch return;
    }

    /// The directory of the records of `kind` under code identity `identity`.
    pub fn partition(self: *const Store, a: std.mem.Allocator, kind: []const u8, identity: Digest) std.mem.Allocator.Error![]const u8 {
        return std.fmt.allocPrint(a, "{s}/records/{s}/{s}", .{ self.root, kind, digest_rules.hex(identity) });
    }

    /// The file of the record with `key` in the partition directory `directory`.
    pub fn recordPath(self: *const Store, a: std.mem.Allocator, directory: []const u8, key: Digest) std.mem.Allocator.Error![]const u8 {
        _ = self;
        const text = digest_rules.hex(key);
        return std.fmt.allocPrint(a, "{s}/{s}/{s}.rec", .{ directory, text[0..2], text });
    }

    /// The file of the object with `digest`.
    pub fn objectPath(self: *const Store, a: std.mem.Allocator, digest: Digest) std.mem.Allocator.Error![]const u8 {
        const text = digest_rules.hex(digest);
        return std.fmt.allocPrint(a, "{s}/objects/{s}/{s}", .{ self.root, text[0..2], text });
    }

    /// The marker file of the in-flight computation of `key`.
    pub fn inflightPath(self: *const Store, a: std.mem.Allocator, key: Digest) std.mem.Allocator.Error![]const u8 {
        return std.fmt.allocPrint(a, "{s}/inflight/{s}", .{ self.root, digest_rules.hex(key) });
    }

    /// The bytes of the file at `path` in `a`, or null when it is absent, unreadable or too large. A file within `small_read` costs an open, one
    /// read and a close. A read that returns less than the buffer holds is taken for the whole file (a regular file reads short only at its
    /// end); were it cut short, a record's trailer or an object's name would refuse it, as they refuse a torn file.
    pub fn load(self: *const Store, a: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!?[]u8 {
        const file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return null;
        defer file.close(self.io);
        var first: [small_read]u8 = undefined;
        const got = file.readPositional(self.io, &.{&first}, 0) catch return null;
        if (got < first.len) {
            const copy = try a.dupe(u8, first[0..got]);
            return copy;
        }
        const size = (file.stat(self.io) catch return null).size;
        if (size > read_limit) return null;
        const length: usize = @max(@as(usize, @intCast(size)), got);
        const whole = try a.alloc(u8, length);
        @memcpy(whole[0..got], first[0..got]);
        const rest = file.readPositionalAll(self.io, whole[got..], got) catch {
            a.free(whole);
            return null;
        };
        if (got + rest == length) return whole;
        a.free(whole);
        return null;
    }

    /// Publish `bytes` as the file at `path`: write a partial file beside it, then rename it into place. A reader sees
    /// the old file or the new one. Returns false when the write failed (nothing is left behind).
    pub fn publish(self: *Store, a: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!bool {
        const partial = try std.fmt.allocPrint(a, "{s}.{d}.{d}.partial", .{ path, std.os.linux.getpid(), self.sequence.fetchAdd(1, .monotonic) });
        defer a.free(partial);
        const cwd = std.Io.Dir.cwd();
        cwd.writeFile(self.io, .{ .sub_path = partial, .data = bytes }) catch |err| {
            if (err != error.FileNotFound) return false;
            cwd.createDirPath(self.io, std.fs.path.dirname(path).?) catch return false;
            cwd.writeFile(self.io, .{ .sub_path = partial, .data = bytes }) catch return false;
        };
        cwd.rename(partial, cwd, path, self.io) catch {
            discard(self.io, partial);
            return false;
        };
        return true;
    }

    /// Publish the object `bytes` under `digest` unless an object of that size is already there.
    pub fn publishObject(self: *Store, a: std.mem.Allocator, digest: Digest, bytes: []const u8) std.mem.Allocator.Error!bool {
        const path = try self.objectPath(a, digest);
        defer a.free(path);
        if (std.Io.Dir.cwd().statFile(self.io, path, .{})) |present| {
            if (present.size == bytes.len) return true;
        } else |_| {}
        return self.publish(a, path, bytes);
    }

    /// The object with `digest`, or null when it is absent or its bytes do not hash to its name. A damaged object is
    /// deleted, so the recomputed one is written whole instead of being taken for the present object of the same size.
    pub fn loadObject(self: *const Store, a: std.mem.Allocator, digest: Digest) std.mem.Allocator.Error!?[]u8 {
        const path = try self.objectPath(a, digest);
        defer a.free(path);
        const bytes = (try self.load(a, path)) orelse return null;
        if (std.mem.eql(u8, &digest_rules.hash(bytes), &digest)) return bytes;
        a.free(bytes);
        self.remove(path);
        return null;
    }

    /// Stamp the partition directory `directory` as used at `now`, unless it was stamped less than
    /// `touch_interval_ns` ago. Failures are ignored: a missing stamp only makes the partition look old.
    pub fn touch(self: *const Store, a: std.mem.Allocator, directory: []const u8, now: i64) void {
        const stamp = std.fmt.allocPrint(a, "{s}/{s}", .{ directory, used_leaf }) catch return;
        defer a.free(stamp);
        if (self.lastUse(a, directory)) |last| if (now >= last and now - last < touch_interval_ns) return;
        std.Io.Dir.cwd().createDirPath(self.io, directory) catch return;
        const text = std.fmt.allocPrint(a, "{d}\n", .{now}) catch return;
        defer a.free(text);
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = stamp, .data = text }) catch return;
    }

    /// When the shared tier named `tier` was last asked about the records served from `directory`, or null when it never was, or was another tier.
    pub fn sweptAt(self: *const Store, a: std.mem.Allocator, directory: []const u8, tier: Digest) ?i64 {
        const path = std.fmt.allocPrint(a, "{s}/{s}", .{ directory, swept_leaf }) catch return null;
        defer a.free(path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, a, .limited(256)) catch return null;
        defer a.free(bytes);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        const when = std.fmt.parseInt(i64, lines.next() orelse return null, 10) catch return null;
        const named = lines.next() orelse return null;
        if (!std.mem.eql(u8, named, &digest_rules.hex(tier))) return null;
        return when;
    }

    /// Record that the shared tier named `tier` was asked about the records served from `directory` at `now`. A failure is ignored: a missing
    /// stamp only makes the next process ask again.
    pub fn markSwept(self: *const Store, a: std.mem.Allocator, directory: []const u8, now: i64, tier: Digest) void {
        const path = std.fmt.allocPrint(a, "{s}/{s}", .{ directory, swept_leaf }) catch return;
        defer a.free(path);
        const text = std.fmt.allocPrint(a, "{d}\n{s}\n", .{ now, digest_rules.hex(tier) }) catch return;
        defer a.free(text);
        std.Io.Dir.cwd().createDirPath(self.io, directory) catch return;
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = text }) catch return;
    }

    /// Record that the objects were scanned for garbage at `now`.
    pub fn markScanned(self: *const Store, a: std.mem.Allocator, now: i64) void {
        const path = std.fmt.allocPrint(a, "{s}/{s}", .{ self.root, scanned_leaf }) catch return;
        defer a.free(path);
        const text = std.fmt.allocPrint(a, "{d}\n", .{now}) catch return;
        defer a.free(text);
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = text }) catch return;
    }

    /// The time the objects were last scanned for garbage, or null when they never were.
    pub fn lastScan(self: *const Store, a: std.mem.Allocator) ?i64 {
        const path = std.fmt.allocPrint(a, "{s}/{s}", .{ self.root, scanned_leaf }) catch return null;
        defer a.free(path);
        return self.stampAt(a, path);
    }

    /// The time `directory` was last stamped, or null when it never was.
    pub fn lastUse(self: *const Store, a: std.mem.Allocator, directory: []const u8) ?i64 {
        const stamp = std.fmt.allocPrint(a, "{s}/{s}", .{ directory, used_leaf }) catch return null;
        defer a.free(stamp);
        return self.stampAt(a, stamp);
    }

    fn stampAt(self: *const Store, a: std.mem.Allocator, path: []const u8) ?i64 {
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, a, .limited(64)) catch return null;
        defer a.free(bytes);
        return std.fmt.parseInt(i64, std.mem.trim(u8, bytes, " \n"), 10) catch null;
    }
};

/// Who computes a key: the process that wrote its marker.
pub const Marker = struct {
    pid: u32,
    /// The process's start time in clock ticks since boot (field 22 of `/proc/<pid>/stat`), which tells a reused pid.
    start: u64,
    host: []const u8,

    /// The marker of the running process, its host name in `a`.
    pub fn mine(a: std.mem.Allocator, io: std.Io) std.mem.Allocator.Error!Marker {
        const pid: u32 = @intCast(std.os.linux.getpid());
        return .{ .pid = pid, .start = processStart(a, io, pid) orelse 0, .host = try hostName(a, io) };
    }

    /// The marker as the file's text.
    pub fn text(self: Marker, a: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return std.fmt.allocPrint(a, "{d}\n{d}\n{s}\n", .{ self.pid, self.start, self.host });
    }

    /// The marker a file's text holds, its host borrowed from `bytes`; null for anything else.
    pub fn parse(bytes: []const u8) ?Marker {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        const pid = std.fmt.parseInt(u32, lines.next() orelse return null, 10) catch return null;
        const start = std.fmt.parseInt(u64, lines.next() orelse return null, 10) catch return null;
        return .{ .pid = pid, .start = start, .host = lines.next() orelse return null };
    }

    /// Whether the process this marker names is still running on this host, as the same process.
    pub fn alive(self: Marker, a: std.mem.Allocator, io: std.Io) bool {
        const here = hostName(a, io) catch return true;
        defer a.free(here);
        if (!std.mem.eql(u8, here, self.host)) return true;
        const started = processStart(a, io, self.pid) orelse return false;
        return started == self.start;
    }
};

/// The whole text of a file the kernel generates, whose size reads as zero, or null.
fn readGenerated(a: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) ?[]u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    var reader = file.readerStreaming(io, &.{});
    return reader.interface.allocRemaining(a, .limited(limit)) catch null;
}

fn hostName(a: std.mem.Allocator, io: std.Io) std.mem.Allocator.Error![]u8 {
    const bytes = readGenerated(a, io, "/proc/sys/kernel/hostname", 256) orelse return a.dupe(u8, "unknown");
    defer a.free(bytes);
    return a.dupe(u8, std.mem.trim(u8, bytes, " \n"));
}

fn processStart(a: std.mem.Allocator, io: std.Io, pid: u32) ?u64 {
    const path = std.fmt.allocPrint(a, "/proc/{d}/stat", .{pid}) catch return null;
    defer a.free(path);
    const bytes = readGenerated(a, io, path, 4096) orelse return null;
    defer a.free(bytes);
    // The command name in parentheses may hold spaces: the fields count from the last ')'.
    const close = std.mem.lastIndexOfScalar(u8, bytes, ')') orelse return null;
    var fields = std.mem.tokenizeScalar(u8, bytes[close + 1 ..], ' ');
    // After the name: state is field 3, so the start time (field 22) is the 20th token.
    for (0..19) |_| _ = fields.next() orelse return null;
    return std.fmt.parseInt(u64, std.mem.trim(u8, fields.next() orelse return null, "\n"), 10) catch null;
}

/// The outcome of `claim`.
pub const Claim = enum {
    /// The marker was written: this process computes the key and releases the marker.
    claimed,
    /// A live process holds the marker: wait for its record.
    held,
    /// No marker could be written: compute without one.
    unavailable,
};

/// Try to claim the computation of `key`: write the marker file exclusively. A marker whose process is gone is
/// replaced.
pub fn claim(store: *const Store, a: std.mem.Allocator, key: Digest) std.mem.Allocator.Error!Claim {
    const path = try store.inflightPath(a, key);
    defer a.free(path);
    const mine = try Marker.mine(a, store.io);
    defer a.free(mine.host);
    const text = try mine.text(a);
    defer a.free(text);
    const cwd = std.Io.Dir.cwd();
    for (0..3) |_| {
        cwd.writeFile(store.io, .{ .sub_path = path, .data = text, .flags = .{ .exclusive = true } }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                if (try holder(store, a, path)) return .held;
                discard(store.io, path);
                continue;
            },
            error.FileNotFound => {
                cwd.createDirPath(store.io, std.fs.path.dirname(path).?) catch return .unavailable;
                continue;
            },
            else => return .unavailable,
        };
        return .claimed;
    }
    return .unavailable;
}

/// Whether the marker file at `path` names a live process.
fn holder(store: *const Store, a: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!bool {
    const bytes = (try store.load(a, path)) orelse return false;
    defer a.free(bytes);
    const marker = Marker.parse(bytes) orelse return false;
    return marker.alive(a, store.io);
}

/// Whether a live process holds the marker of `key`.
pub fn claimed(store: *const Store, a: std.mem.Allocator, key: Digest) std.mem.Allocator.Error!bool {
    const path = try store.inflightPath(a, key);
    defer a.free(path);
    return holder(store, a, path);
}

/// Remove the marker of `key`. Allocates nothing, so a computation that finished can always release its marker.
pub fn release(store: *const Store, key: Digest) void {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buffer, "{s}/inflight/{s}", .{ store.root, digest_rules.hex(key) }) catch return;
    discard(store.io, path);
}

/// Delete the file at `path`, ignoring a failure: what is left behind is a miss or a stale marker, both harmless.
pub fn discard(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn scratch(temporary: *std.testing.TmpDir, a: std.mem.Allocator) ![]const u8 {
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    return std.fs.path.join(a, &.{ base, root_leaf });
}

test "a published file is read back whole and replaces the one before it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const directory = try store.partition(a, "test-exec", @splat(0xab));
    const path = try store.recordPath(a, directory, @splat(0xcd));
    try std.testing.expect(std.mem.endsWith(u8, path, try std.fmt.allocPrint(a, "/cd/{s}.rec", .{digest_rules.hex(@splat(0xcd))})));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, path));
    try std.testing.expect(try store.publish(a, path, "first"));
    try std.testing.expectEqualStrings("first", (try store.load(a, path)).?);
    try std.testing.expect(try store.publish(a, path, "second"));
    try std.testing.expectEqualStrings("second", (try store.load(a, path)).?);
}

test "an object is served only while its bytes hash to its name" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const payload = try a.alloc(u8, 5000);
    @memset(payload, 'x');
    const digest = digest_rules.hash(payload);
    try std.testing.expect(try store.publishObject(a, digest, payload));
    try std.testing.expect(try store.publishObject(a, digest, payload));
    try std.testing.expectEqualStrings(payload, (try store.loadObject(a, digest)).?);
    try std.testing.expect(try store.publish(a, try store.objectPath(a, digest), payload[1..]));
    try std.testing.expectEqual(@as(?[]u8, null), try store.loadObject(a, digest));
}

test "a damaged object of the right size is deleted when found, so republishing writes it whole" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const payload = try a.alloc(u8, 5000);
    @memset(payload, 'x');
    const digest = digest_rules.hash(payload);
    try std.testing.expect(try store.publishObject(a, digest, payload));
    const damaged = try a.dupe(u8, payload);
    damaged[2500] ^= 1;
    try std.testing.expect(try store.publish(a, try store.objectPath(a, digest), damaged));
    // Same size as the object: publishing alone would take it for the object and leave it damaged.
    try std.testing.expectEqual(@as(?[]u8, null), try store.loadObject(a, digest));
    try std.testing.expect(try store.publishObject(a, digest, payload));
    try std.testing.expectEqualStrings(payload, (try store.loadObject(a, digest)).?);
}

test "a partition's use is stamped once per interval" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const directory = try store.partition(a, "test-plan", @splat(1));
    try std.testing.expectEqual(@as(?i64, null), store.lastUse(a, directory));
    store.touch(a, directory, 1_000);
    try std.testing.expectEqual(@as(?i64, 1_000), store.lastUse(a, directory));
    store.touch(a, directory, 1_000 + touch_interval_ns - 1);
    try std.testing.expectEqual(@as(?i64, 1_000), store.lastUse(a, directory));
    store.touch(a, directory, 1_000 + touch_interval_ns);
    try std.testing.expectEqual(@as(?i64, 1_000 + touch_interval_ns), store.lastUse(a, directory));
}

test "a marker is held by a live process, and one whose process is gone is replaced" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const key: Digest = @splat(5);
    try std.testing.expect(!try claimed(&store, a, key));
    try std.testing.expectEqual(Claim.claimed, try claim(&store, a, key));
    try std.testing.expect(try claimed(&store, a, key));
    try std.testing.expectEqual(Claim.held, try claim(&store, a, key));
    release(&store, key);
    try std.testing.expect(!try claimed(&store, a, key));
    // A marker naming a pid that is not running on this host.
    const mine = try Marker.mine(a, std.testing.io);
    const dead: Marker = .{ .pid = 4_000_000, .start = 1, .host = mine.host };
    try std.testing.expect(try store.publish(a, try store.inflightPath(a, key), try dead.text(a)));
    try std.testing.expect(!try claimed(&store, a, key));
    try std.testing.expectEqual(Claim.claimed, try claim(&store, a, key));
    try std.testing.expect(try claimed(&store, a, key));
}

test "a marker's text parses back, and a pid with another start time is not the process" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mine = try Marker.mine(a, std.testing.io);
    try std.testing.expect(mine.start != 0);
    const parsed = Marker.parse(try mine.text(a)).?;
    try std.testing.expectEqual(mine.pid, parsed.pid);
    try std.testing.expect(parsed.alive(a, std.testing.io));
    const reused: Marker = .{ .pid = mine.pid, .start = mine.start + 1, .host = mine.host };
    try std.testing.expect(!reused.alive(a, std.testing.io));
    try std.testing.expectEqual(@as(?Marker, null), Marker.parse("not a marker"));
}

fn patterned(a: std.mem.Allocator, length: usize) ![]u8 {
    const bytes = try a.alloc(u8, length);
    for (bytes, 0..) |*byte, at| byte.* = @intCast(at % 251);
    return bytes;
}

test "a file is read whole at every size around the buffer of a single read, and an absent one is null" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const directory = try store.partition(a, "k", @splat(1));
    const path = try store.recordPath(a, directory, @splat(2));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, path));
    const bytes = try patterned(a, 3 * small_read);
    for ([_]usize{ 0, 1, small_read - 1, small_read, small_read + 1, 2 * small_read, 3 * small_read }) |length| {
        try std.testing.expect(try store.publish(a, path, bytes[0..length]));
        try std.testing.expectEqualSlices(u8, bytes[0..length], (try store.load(a, path)).?);
    }
}

test "a sweep stamp names the time and the tier, and any other file is no stamp" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = Store.init(std.testing.io, try scratch(&temporary, a));
    const directory = try store.partition(a, "test-plan", @splat(1));
    const tier: Digest = @splat(7);
    try std.testing.expectEqual(@as(?i64, null), store.sweptAt(a, directory, tier));
    store.markSwept(a, directory, 5_000, tier);
    try std.testing.expectEqual(@as(?i64, 5_000), store.sweptAt(a, directory, tier));
    try std.testing.expectEqual(@as(?i64, null), store.sweptAt(a, directory, @splat(8)));
    store.markSwept(a, directory, 9_000, tier);
    try std.testing.expectEqual(@as(?i64, 9_000), store.sweptAt(a, directory, tier));
    const stamp = try std.fmt.allocPrint(a, "{s}/{s}", .{ directory, swept_leaf });
    for ([_][]const u8{ "", "9000", "9000\n", "later\nnot a digest\n", "9000\nshort\n" }) |text| {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = stamp, .data = text });
        try std.testing.expectEqual(@as(?i64, null), store.sweptAt(a, directory, tier));
    }
}
