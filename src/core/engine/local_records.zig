//! The records a build adopts and the packs of its work directory (round 14, D-L1r14-1).
//!
//! A record the build is served from the shared tier, or from a pack, and has to keep a local copy of (the tier's bytes, or the record rewritten with this
//! tree's stat tuples once its files were hashed) is held here in memory instead of being written at once. When the engine ends (or starts a new revision)
//! `flush` writes them as one pack: one file, one create and one rename, instead of a file for each of hundreds of records, which a busy journal stalls one
//! by one. A queue shorter than the policy's minimum is written as loose files, as the engine always did.
//!
//! The packs on disk are read once, lazily, at the first local miss: the newest `pack.max_loaded`, each only when one of its groups is a kind this engine has
//! registered at its identity. `find` looks a key up in each, newest first. Nothing here validates a record; the engine decodes and validates what it is
//! offered exactly as it does a loose file.
const std = @import("std");
const digest_rules = @import("digest.zig");
const pack_rules = @import("pack.zig");
const store_rules = @import("store.zig");
const Digest = digest_rules.Digest;
const Store = store_rules.Store;

/// A registered kind as `flush` needs it: its name and identity (a pack's groups) and the directory of its loose records.
pub const KindInfo = struct { name: []const u8, identity: Digest, directory: []const u8 };

/// A record waiting for the pack: the position of its kind in the registry and its encoded bytes.
const Pending = struct { kind: u32, bytes: []const u8 };

/// A pack read from disk: its file name, its bytes (the view borrows them), when it was last used and whether this process served from it.
const Loaded = struct {
    name: []const u8,
    bytes: []u8,
    view: pack_rules.View,
    modified: i64,
    used: std.atomic.Value(bool) = .init(false),
    /// Set when this process removed the file.
    gone: bool = false,
};

const flag_open: u8 = 1;
const flag_forgot: u8 = 2;

/// The queue of adopted records and the packs of one engine.
pub const Records = struct {
    mutex: std.Io.Mutex = .init,
    flags: std.atomic.Value(u8) = .init(0),
    /// The packs read, newest first. Set once by `open`; changed only by `flush`, when no query runs.
    packs: []Loaded = &.{},
    pending: std.AutoHashMapUnmanaged(Digest, Pending) = .empty,
    forgotten: std.AutoHashMapUnmanaged(Digest, void) = .empty,
    arena: ?std.heap.ArenaAllocator = null,

    /// Whether the packs were read.
    pub fn isOpen(self: *const Records) bool {
        return self.flags.load(.acquire) & flag_open != 0;
    }

    /// Read the packs of `store` that hold records of any of the `current` kinds at their identities. Idempotent; a pack that does not parse, or cannot be
    /// read, is not there.
    pub fn open(self: *Records, gpa: std.mem.Allocator, store: *const Store, current: []const pack_rules.Group) void {
        self.mutex.lockUncancelable(store.io);
        defer self.mutex.unlock(store.io);
        if (self.flags.load(.monotonic) & flag_open != 0) return;
        self.packs = loadPacks(gpa, store, current) catch &.{};
        _ = self.flags.fetchOr(flag_open, .release);
    }

    /// Whether there is nothing to flush: no record waiting, no key forgotten, no pack read.
    pub fn idle(self: *const Records) bool {
        return self.pending.count() == 0 and self.forgotten.count() == 0 and self.packs.len == 0;
    }

    /// How many packs were read.
    pub fn count(self: *const Records) usize {
        return self.packs.len;
    }

    /// The encoded record under `key` in the pack at position `at` (0 is the newest), or null: the pack holds none, or the process forgot the key.
    pub fn find(self: *Records, io: std.Io, at: usize, key: Digest) ?[]const u8 {
        if (self.flags.load(.acquire) & flag_forgot != 0 and self.isForgotten(io, key)) return null;
        return self.packs[at].view.find(key);
    }

    fn isForgotten(self: *Records, io: std.Io, key: Digest) bool {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.forgotten.contains(key);
    }

    /// Note that the pack at `at` served a record, so the flush stamps it as used.
    pub fn markUsed(self: *Records, at: usize) void {
        self.packs[at].used.store(true, .monotonic);
    }

    /// Hold `bytes`, the record under `key` of the kind at position `kind`, for the next pack. A later record under one key replaces the earlier.
    pub fn queue(self: *Records, gpa: std.mem.Allocator, io: std.Io, key: Digest, kind: u32, bytes: []const u8) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.arena == null) self.arena = .init(gpa);
        const owned = self.arena.?.allocator().dupe(u8, bytes) catch return;
        self.pending.put(gpa, key, .{ .kind = kind, .bytes = owned }) catch return;
    }

    /// The caller found the record under `key` wrong: drop it from the queue and never serve it from a pack again; `flush` rewrites the packs that hold it.
    pub fn forget(self: *Records, gpa: std.mem.Allocator, io: std.Io, key: Digest) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        _ = self.pending.remove(key);
        self.forgotten.put(gpa, key, {}) catch return;
        _ = self.flags.fetchOr(flag_forgot, .release);
    }

    /// Write what the build adopted: a pack when at least `minimum` records are queued, loose files otherwise; rewrite the packs that hold a forgotten
    /// key without it; stamp the packs this process served from. Every failure is dropped: nothing here is more than a hint. `now` names the new pack.
    pub fn flush(self: *Records, gpa: std.mem.Allocator, store: *Store, kinds: []const KindInfo, minimum: u32, now: i64) void {
        if (self.idle()) return;
        self.mutex.lockUncancelable(store.io);
        defer self.mutex.unlock(store.io);
        var scratch: std.heap.ArenaAllocator = .init(gpa);
        defer scratch.deinit();
        const a = scratch.allocator();
        var changed = false;
        if (self.pending.count() != 0) changed = self.writePending(a, store, kinds, minimum, now);
        if (self.forgotten.count() != 0) changed = self.rewriteForgotten(a, store, now) or changed;
        self.touchUsed(a, store, now);
        self.pending.clearRetainingCapacity();
        self.forgotten.clearRetainingCapacity();
        _ = self.flags.fetchAnd(~flag_forgot, .release);
        if (self.arena) |*arena| _ = arena.reset(.retain_capacity);
        if (changed) self.closePacks(gpa);
    }

    /// Free everything this holds. A queue that was not flushed is dropped.
    pub fn deinit(self: *Records, gpa: std.mem.Allocator) void {
        self.closePacks(gpa);
        self.pending.deinit(gpa);
        self.forgotten.deinit(gpa);
        if (self.arena) |*arena| arena.deinit();
    }

    fn closePacks(self: *Records, gpa: std.mem.Allocator) void {
        for (self.packs) |*loaded| {
            gpa.free(loaded.name);
            gpa.free(loaded.bytes);
        }
        if (self.packs.len != 0) gpa.free(self.packs);
        self.packs = &.{};
        _ = self.flags.fetchAnd(~flag_open, .release);
    }

    fn writePending(self: *Records, a: std.mem.Allocator, store: *Store, kinds: []const KindInfo, minimum: u32, now: i64) bool {
        if (self.pending.count() < minimum) {
            var entries = self.pending.iterator();
            while (entries.next()) |entry| {
                if (entry.value_ptr.kind >= kinds.len) continue;
                const path = store.recordPath(a, kinds[entry.value_ptr.kind].directory, entry.key_ptr.*) catch continue;
                _ = store.publish(a, path, entry.value_ptr.bytes) catch false;
            }
            return false;
        }
        const items = a.alloc(pack_rules.Item, self.pending.count()) catch return false;
        const present = a.alloc(bool, kinds.len) catch return false;
        @memset(present, false);
        var at: usize = 0;
        var entries = self.pending.iterator();
        while (entries.next()) |entry| {
            if (entry.value_ptr.kind >= kinds.len) continue;
            present[entry.value_ptr.kind] = true;
            items[at] = .{ .key = entry.key_ptr.*, .bytes = entry.value_ptr.bytes };
            at += 1;
        }
        var groups: std.ArrayList(pack_rules.Group) = .empty;
        for (kinds, present) |kind, held| {
            if (held) groups.append(a, .{ .kind = kind.name, .identity = kind.identity }) catch return false;
        }
        if (!publishPack(a, store, groups.items, items[0..at], now)) return false;
        self.dropCovered(a, store);
        return true;
    }

    /// Remove the packs read at the start of the process whose every record the pack just written carries too: a tree whose files moved refreshes the records of its
    /// pack, and the pack it writes for them replaces the one they came from, so the packs of a work directory do not pile up beside each other.
    fn dropCovered(self: *Records, a: std.mem.Allocator, store: *Store) void {
        for (self.packs) |*loaded| {
            if (!self.carries(loaded.view)) continue;
            const path = std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, loaded.name }) catch continue;
            store.remove(path);
            loaded.gone = true;
        }
    }

    fn carries(self: *const Records, view: pack_rules.View) bool {
        for (0..view.count) |slot| {
            if (!self.pending.contains(view.keyAt(slot))) return false;
        }
        return true;
    }

    fn rewriteForgotten(self: *Records, a: std.mem.Allocator, store: *Store, now: i64) bool {
        var changed = false;
        for (self.packs) |*loaded| {
            if (!self.holdsForgotten(loaded.view)) continue;
            var kept: std.ArrayList(pack_rules.Item) = .empty;
            for (0..loaded.view.count) |slot| {
                const key = loaded.view.keyAt(slot);
                if (self.forgotten.contains(key)) continue;
                kept.append(a, .{ .key = key, .bytes = loaded.view.recordAt(slot) }) catch return changed;
            }
            const groups = loaded.view.groupList(a) catch return changed;
            // The pack goes only after its survivors are somewhere: a write that fails leaves the old pack, which is as valid as it was. The survivors
            // keep the old pack's time, so they do not come before the records of a pack written since.
            if (kept.items.len != 0 and !publishPack(a, store, groups, kept.items, packTime(loaded.name) orelse now)) continue;
            const path = std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, loaded.name }) catch continue;
            store.remove(path);
            loaded.gone = true;
            changed = true;
        }
        return changed;
    }

    fn holdsForgotten(self: *const Records, view: pack_rules.View) bool {
        var keys = self.forgotten.keyIterator();
        while (keys.next()) |key| if (view.find(key.*) != null) return true;
        return false;
    }

    /// Stamp the packs this process served from as used now, unless they were stamped within `touch_interval_ns`. The system call is made directly: a pack
    /// another process retired meanwhile is a plain failure here, where the library's wrapper reports an unexpected error.
    fn touchUsed(self: *Records, a: std.mem.Allocator, store: *Store, now: i64) void {
        for (self.packs) |*loaded| {
            if (loaded.gone or !loaded.used.load(.monotonic)) continue;
            if (now >= loaded.modified and now - loaded.modified < store_rules.touch_interval_ns) continue;
            const path = std.fmt.allocPrintSentinel(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, loaded.name }, 0) catch continue;
            _ = std.os.linux.utimensat(std.os.linux.AT.FDCWD, path, null, 0);
        }
    }
};

/// Build a pack of `items` and publish it under `packs/`; whether it was written.
fn publishPack(a: std.mem.Allocator, store: *Store, groups: []const pack_rules.Group, items: []const pack_rules.Item, now: i64) bool {
    const built = (pack_rules.build(a, groups, items) catch return false) orelse return false;
    const name = pack_rules.fileName(a, now, built.digest) catch return false;
    const path = std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, name }) catch return false;
    return store.publish(a, path, built.bytes) catch false;
}

/// The time in the name of a pack file (`pack.fileName`), or null for a name that does not start with one.
fn packTime(name: []const u8) ?i64 {
    if (name.len < 20) return null;
    return std.fmt.parseInt(i64, name[0..20], 10) catch null;
}

fn newerName(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, right, left);
}

fn loadPacks(gpa: std.mem.Allocator, store: *const Store, current: []const pack_rules.Group) std.mem.Allocator.Error![]Loaded {
    const io = store.io;
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    const directory = try std.fmt.allocPrint(a, "{s}/{s}", .{ store.root, pack_rules.directory_leaf });
    var listing = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return &.{};
    defer listing.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = listing.iterate();
    while (entries.next(io) catch null) |entry| {
        if (entry.kind != .file or !pack_rules.isPackName(entry.name)) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, newerName);
    var loaded: std.ArrayList(Loaded) = .empty;
    for (names.items[0..@min(names.items.len, pack_rules.max_loaded)]) |name| {
        const path = try std.fmt.allocPrint(a, "{s}/{s}", .{ directory, name });
        const one = loadOne(gpa, io, path, name, current) orelse continue;
        loaded.append(gpa, one) catch {
            closeOne(gpa, one);
            closeAll(gpa, &loaded);
            return error.OutOfMemory;
        };
    }
    return loaded.toOwnedSlice(gpa) catch {
        closeAll(gpa, &loaded);
        return error.OutOfMemory;
    };
}

/// The pack at `path`, named `name`, when it holds a record of a current kind and parses.
fn loadOne(gpa: std.mem.Allocator, io: std.Io, path: []const u8, name: []const u8, current: []const pack_rules.Group) ?Loaded {
    const read = readLive(gpa, io, path, current) orelse return null;
    const view = pack_rules.View.parse(read.bytes) orelse {
        gpa.free(read.bytes);
        return null;
    };
    const owned = gpa.dupe(u8, name) catch {
        gpa.free(read.bytes);
        return null;
    };
    return .{ .name = owned, .bytes = read.bytes, .view = view, .modified = read.modified };
}

fn closeOne(gpa: std.mem.Allocator, one: Loaded) void {
    gpa.free(one.name);
    gpa.free(one.bytes);
}

fn closeAll(gpa: std.mem.Allocator, loaded: *std.ArrayList(Loaded)) void {
    for (loaded.items) |one| closeOne(gpa, one);
    loaded.deinit(gpa);
}

const Read = struct { bytes: []u8, modified: i64 };

/// The whole file at `path` when its first bytes say a record of one of the `current` kinds may be in it, else null. A file within the first read costs an
/// open, a read, a stat and a close; a larger one, one more read.
fn readLive(gpa: std.mem.Allocator, io: std.Io, path: []const u8, current: []const pack_rules.Group) ?Read {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return null;
    defer file.close(io);
    var first: [pack_rules.peek_bytes]u8 = undefined;
    const got = file.readPositional(io, &.{&first}, 0) catch return null;
    switch (pack_rules.liveness(first[0..got], got < first.len, current)) {
        .live => {},
        .dead, .damaged => return null,
    }
    const status = file.stat(io) catch return null;
    if (status.size > pack_rules.max_pack_bytes) return null;
    const bytes = gpa.alloc(u8, @intCast(status.size)) catch return null;
    const head = @min(got, bytes.len);
    @memcpy(bytes[0..head], first[0..head]);
    if (head < bytes.len) {
        const rest = file.readPositionalAll(io, bytes[head..], head) catch {
            gpa.free(bytes);
            return null;
        };
        if (head + rest != bytes.len) {
            gpa.free(bytes);
            return null;
        }
    }
    return .{ .bytes = bytes, .modified = @intCast(@min(status.mtime.nanoseconds, std.math.maxInt(i64))) };
}
