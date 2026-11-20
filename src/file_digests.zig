//! Stat-trusted module digests (G2p, lane 4 round 4): the project load hashes every module's bytes (`source_digest.of`) because the
//! digest names the module in every cache, and at 99k that is 6.5 MB of BLAKE3 per build for one edited file. A `Memo` remembers, per
//! project-relative path, the stat tuple a file had when its digest was taken and the digest. A later load whose read of the file ends
//! with the same tuple, taken the same before and after the read, takes the remembered digest and hashes nothing.
//!
//! This is the engine's own rule for a file it read (`core/engine/context.zig` `observe`, `validate.zig` `checkFile`): the tuple is
//! (inode, size, mtime, ctime); it is recorded only when the file's last change is older than the racy window, because a second write
//! within one tick of the kernel's clock keeps the tuple of the first (the racy-git case); and a tuple that moved during the read is not
//! trusted. The window is a parameter here so that this file stays free of the engine; the session passes the engine's own constant
//! (`world.Assumptions.racy_window_ns`, `core/frontend.zig` `digest_window_ns`), and a test holds the two together.
const std = @import("std");
const builtin = @import("builtin");
const source_digest = @import("source_digest.zig");
const retention_clock = @import("native_cache_retention.zig");

/// The tuple that tells one state of a file from another.
pub const Stat = struct {
    inode: u64,
    size: u64,
    mtime: i64,
    ctime: i64,

    /// The tuple of "none seen": never offered as steady, since a real file has no inode 0.
    pub const none: Stat = .{ .inode = 0, .size = 0, .mtime = 0, .ctime = 0 };

    /// Whether both tuples describe the same file state.
    pub fn eql(self: Stat, other: Stat) bool {
        return self.inode == other.inode and self.size == other.size and self.mtime == other.mtime and self.ctime == other.ctime;
    }

    /// The later of the two timestamps: the moment the file last changed, as far as its tuple can tell.
    pub fn changed(self: Stat) i64 {
        return @max(self.mtime, self.ctime);
    }
};

/// What a stored digest rests on: the tuple of the file when it was hashed, and its digest.
pub const Entry = struct { stat: Stat, digest: [32]u8 };

/// When the files are read, and how far a recorded tuple is trusted.
pub const Config = struct {
    io: std.Io,
    /// A file whose last change is this recent when it is observed is not trusted to its tuple (the engine's `Assumptions.racy_window_ns`).
    window_ns: i64,
    /// The clock to compare file times against, in nanoseconds since the epoch; null reads the retention clock the engine's world reads.
    now: ?i64 = null,
    /// Hash the bytes anyway and stop the process when the remembered digest is not theirs: a tuple that vouched for a file that had changed.
    /// A Debug compiler always does; a session that verifies (`SELKA_ENGINE_VERIFY`) asks for it.
    verify: bool = false,
};

/// The read in progress: the tuples the provider took of the open file before and after reading it, and the one the memo trusts.
const Step = struct {
    path: []const u8 = "",
    before: ?Stat = null,
    after: ?Stat = null,
    /// The tuple after the read when it equals the one before and the read returned that many bytes, else null.
    steady: ?Stat = null,
};

/// The remembered digests of one project's files.
pub const Memo = struct {
    arena: std.mem.Allocator,
    config: Config,
    table: std.StringHashMapUnmanaged(Entry) = .empty,
    /// The paths this load read, each with the steady tuple of the read (null when the file moved while it was read): for pruning the table
    /// when it is saved, and for a later reader of the same file to take instead of a stat of its own (`tupleOf`).
    seen: std.StringHashMapUnmanaged(?Stat) = .empty,
    step: Step = .{},
    /// Whether the table holds an entry the stored copy does not.
    dirty: bool = false,
    /// How many digests `vouch` gave, so a test and a report can see the memo work.
    vouched: usize = 0,

    /// An empty memo over `config`. Everything it keeps is allocated in `arena`.
    pub fn init(arena: std.mem.Allocator, config: Config) Memo {
        return .{ .arena = arena, .config = config };
    }

    /// The key of the stored table of the project at `root` (the cache's namespace already names the compiler).
    pub fn key(root: []const u8) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("file-digests-v1");
        hash.update(std.mem.asBytes(&root.len));
        hash.update(root);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// `file.stat` as the tuple, or null when the file cannot be statted.
    pub fn tupleOfFile(found: ?std.Io.File.Stat) ?Stat {
        const stat = found orelse return null;
        return .{ .inode = @intCast(stat.inode), .size = stat.size, .mtime = clamp(stat.mtime.nanoseconds), .ctime = clamp(stat.ctime.nanoseconds) };
    }

    /// The provider read project-relative `relative` through an open file whose tuple it took `before` the read and `after` it (the file
    /// descriptor's, so the memo costs no path lookup of its own). `vouch` and `learned` follow for the same file.
    pub fn observed(self: *Memo, relative: []const u8, before: ?Stat, after: ?Stat) void {
        self.step = .{ .path = relative, .before = before, .after = after };
    }

    /// The steady tuple this load took of `relative`'s file, when it read it and the file held still: a reader that needs the file's tuple
    /// in the same load can use it instead of statting the path again.
    pub fn tupleOf(self: *const Memo, relative: []const u8) ?Stat {
        return (self.seen.get(relative) orelse return null);
    }

    /// The digest of the `bytes` just read from `relative`, when the tuple the memo holds for it is the file's now and was the file's before
    /// the read, and the read returned exactly that many bytes; null when the bytes must be hashed.
    pub fn vouch(self: *Memo, relative: []const u8, bytes: []const u8) ?[32]u8 {
        self.step.steady = null;
        const before = self.step.before orelse Stat.none;
        const after = self.step.after orelse Stat.none;
        if (std.mem.eql(u8, self.step.path, relative) and self.step.before != null and self.step.after != null) {
            self.step.steady = steadyTuple(before, after, bytes.len);
        }
        self.noteSeen(relative, self.step.steady);
        const tuple = self.step.steady orelse return null;
        const entry = self.table.get(relative) orelse return null;
        if (!entry.stat.eql(tuple)) return null;
        if (builtin.mode == .debug or self.config.verify) {
            if (!std.mem.eql(u8, &digestOf(bytes), &entry.digest)) std.debug.panic("the file digest memo vouched for a stale digest of {s}", .{relative});
        }
        self.vouched += 1;
        return entry.digest;
    }

    /// Remember the `digest` the loader took of the bytes `vouch` would not vouch for, if their file held still during the read and its
    /// last change is older than the racy window.
    pub fn learned(self: *Memo, relative: []const u8, digest: [32]u8) void {
        const tuple = self.step.steady orelse return;
        if (!std.mem.eql(u8, self.step.path, relative)) return;
        if (racy(tuple, self.clock(), self.config.window_ns)) return;
        const owned = self.arena.dupe(u8, relative) catch return;
        const entry = self.table.getOrPut(self.arena, owned) catch return;
        entry.value_ptr.* = .{ .stat = tuple, .digest = digest };
        self.dirty = true;
    }

    fn noteSeen(self: *Memo, relative: []const u8, tuple: ?Stat) void {
        const owned = self.arena.dupe(u8, relative) catch return;
        self.seen.put(self.arena, owned, tuple) catch return;
    }

    fn clock(self: *const Memo) i64 {
        return self.config.now orelse clamp(retention_clock.retentionNanoseconds(self.config.io));
    }

    /// Drop the entries of files this load did not read once there are thousands more than it read, so a table does not outlive the files it describes.
    pub fn prune(self: *Memo) void {
        if (self.table.count() <= 4 * self.seen.count() + 4096) return;
        var doomed: std.ArrayList([]const u8) = .empty;
        var names = self.table.keyIterator();
        while (names.next()) |name| if (!self.seen.contains(name.*)) doomed.append(self.arena, name.*) catch return;
        for (doomed.items) |name| _ = self.table.remove(name);
        self.dirty = true;
    }

    /// The table as bytes: a magic, a count, then per entry the path, the tuple and the digest.
    pub fn encode(self: *const Memo, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try out.appendSlice(allocator, "FDG1");
        try appendInt(allocator, &out, u32, @intCast(self.table.count()));
        var items = self.table.iterator();
        while (items.next()) |item| {
            try appendInt(allocator, &out, u16, @intCast(item.key_ptr.len));
            try out.appendSlice(allocator, item.key_ptr.*);
            try appendInt(allocator, &out, u64, item.value_ptr.stat.inode);
            try appendInt(allocator, &out, u64, item.value_ptr.stat.size);
            try appendInt(allocator, &out, i64, item.value_ptr.stat.mtime);
            try appendInt(allocator, &out, i64, item.value_ptr.stat.ctime);
            try out.appendSlice(allocator, &item.value_ptr.digest);
        }
        return out.toOwnedSlice(allocator);
    }

    /// Fill the table from `bytes` made by `encode`. Anything that does not parse leaves the table empty: a miss, never a wrong digest.
    pub fn decode(self: *Memo, bytes: []const u8) void {
        self.decodeInto(bytes) catch {
            self.table.clearRetainingCapacity();
        };
    }

    fn decodeInto(self: *Memo, bytes: []const u8) error{ Malformed, OutOfMemory }!void {
        if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], "FDG1")) return error.Malformed;
        var at: usize = 4;
        const count = try takeInt(bytes, &at, u32);
        try self.table.ensureTotalCapacity(self.arena, count);
        for (0..count) |_| {
            const length = try takeInt(bytes, &at, u16);
            if (bytes.len - at < length) return error.Malformed;
            const path = try self.arena.dupe(u8, bytes[at..][0..length]);
            at += length;
            const stat: Stat = .{
                .inode = try takeInt(bytes, &at, u64),
                .size = try takeInt(bytes, &at, u64),
                .mtime = try takeInt(bytes, &at, i64),
                .ctime = try takeInt(bytes, &at, i64),
            };
            if (bytes.len - at < 32) return error.Malformed;
            self.table.putAssumeCapacity(path, .{ .stat = stat, .digest = bytes[at..][0..32].* });
            at += 32;
        }
        if (at != bytes.len) return error.Malformed;
    }
};

/// The tuple a read can be trusted to, when the file held still while it was read and the read returned the whole file.
pub fn steadyTuple(before: Stat, after: Stat, read_bytes: usize) ?Stat {
    if (!before.eql(after) or after.size != read_bytes) return null;
    return after;
}

/// Whether a file with this tuple changed too recently, at time `now`, to be told apart from a later write by its tuple alone.
pub fn racy(stat: Stat, now: i64, window_ns: i64) bool {
    return stat.changed() > now - window_ns;
}

fn clamp(value: i96) i64 {
    return std.math.cast(i64, value) orelse if (value < 0) std.math.minInt(i64) else std.math.maxInt(i64);
}

fn appendInt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime T: type, value: T) std.mem.Allocator.Error!void {
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn takeInt(bytes: []const u8, at: *usize, comptime T: type) error{Malformed}!T {
    if (bytes.len - at.* < @sizeOf(T)) return error.Malformed;
    const value = std.mem.readInt(T, bytes[at.*..][0..@sizeOf(T)], .little);
    at.* += @sizeOf(T);
    return value;
}

/// The digest of `bytes` a load would take.
fn digestOf(bytes: []const u8) [32]u8 {
    return source_digest.of(bytes);
}

const testing = std.testing;

/// What the provider does around a read of `name` in `dir`: the tuple of the open file before and after.
fn observeFile(memo: *Memo, dir: std.Io.Dir, name: []const u8) !void {
    var file = try dir.openFile(testing.io, name, .{});
    defer file.close(testing.io);
    const before = Memo.tupleOfFile(try file.stat(testing.io));
    const after = Memo.tupleOfFile(try file.stat(testing.io));
    memo.observed(name, before, after);
}

test "a file rewritten inside the racy window with the same size is hashed again" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // An hour's window: whatever the file's tuple says, a file written just now counts as changed within it.
    var memo = Memo.init(arena.allocator(), .{ .io = testing.io, .window_ns = 3_600 * std.time.ns_per_s });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "a.selka", .data = "aaaa" });
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqual(@as(?[32]u8, null), memo.vouch("a.selka", "aaaa"));
    memo.learned("a.selka", digestOf("aaaa"));
    // Changed within the window: nothing is recorded, so the next load hashes whatever the file holds.
    try testing.expectEqual(@as(usize, 0), memo.table.count());
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "a.selka", .data = "bbbb" });
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqual(@as(?[32]u8, null), memo.vouch("a.selka", "bbbb"));
}

test "a tuple recorded outside the window vouches for an unchanged file and not for a rewritten one" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "a.selka", .data = "aaaa" });
    // A zero window: the file counts as aged as soon as it is observed.
    var memo = Memo.init(arena.allocator(), .{ .io = testing.io, .window_ns = 0, .now = std.math.maxInt(i64) });
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqual(@as(?[32]u8, null), memo.vouch("a.selka", "aaaa"));
    memo.learned("a.selka", digestOf("aaaa"));
    try testing.expectEqual(@as(usize, 1), memo.table.count());
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqualSlices(u8, &digestOf("aaaa"), &memo.vouch("a.selka", "aaaa").?);
    // The same size, new bytes: the tuple moved, so the recorded digest is not offered. (A pause first, so the rewrite cannot share a tick
    // of the kernel's clock with the first write.)
    try std.Io.sleep(testing.io, .fromMilliseconds(20), .awake);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "a.selka", .data = "bbbb" });
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqual(@as(?[32]u8, null), memo.vouch("a.selka", "bbbb"));
    // A read that returned another length than the file has is not trusted either.
    try observeFile(&memo, temporary.dir, "a.selka");
    try testing.expectEqual(@as(?[32]u8, null), memo.vouch("a.selka", "bbbbb"));
}

test "a tuple that moved during the read is not trusted, and the racy rule is the engine's" {
    const first: Stat = .{ .inode = 7, .size = 4, .mtime = 100, .ctime = 100 };
    const moved: Stat = .{ .inode = 7, .size = 4, .mtime = 101, .ctime = 101 };
    try testing.expectEqual(@as(?Stat, null), steadyTuple(first, moved, 4));
    try testing.expectEqual(@as(?Stat, first), steadyTuple(first, first, 4));
    try testing.expectEqual(@as(?Stat, null), steadyTuple(first, first, 5));
    // Changed at 100, observed at 100 + window: not racy; one nanosecond sooner: racy.
    try testing.expect(!racy(first, 100 + 50, 50));
    try testing.expect(racy(first, 100 + 49, 50));
}

test "the table survives a round trip and a damaged copy is empty" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var memo = Memo.init(arena.allocator(), .{ .io = testing.io, .window_ns = 0 });
    try memo.table.put(arena.allocator(), "x/y.selka", .{ .stat = .{ .inode = 3, .size = 9, .mtime = 5, .ctime = 6 }, .digest = digestOf("y") });
    const bytes = try memo.encode(testing.allocator);
    defer testing.allocator.free(bytes);
    var copy = Memo.init(arena.allocator(), .{ .io = testing.io, .window_ns = 0 });
    copy.decode(bytes);
    try testing.expectEqual(@as(usize, 1), copy.table.count());
    try testing.expectEqualSlices(u8, &digestOf("y"), &copy.table.get("x/y.selka").?.digest);
    var broken = Memo.init(arena.allocator(), .{ .io = testing.io, .window_ns = 0 });
    broken.decode(bytes[0 .. bytes.len - 1]);
    try testing.expectEqual(@as(usize, 0), broken.table.count());
}
