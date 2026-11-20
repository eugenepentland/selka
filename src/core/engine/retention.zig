//! Retention of the engine's store (spec §7): the records of a kind are partitioned by code identity, and a kind keeps
//! its current identity's directory and the two most recently used others; objects no live record names (a record in a
//! pack included) and older than 14 days go; markers of dead processes go; of the records packs (`pack.zig`), the four
//! most recently used that hold a record of a current kind stay, with the two most recent others, and the partial files
//! of a writer that died go.
//!
//! It takes no lease: spec §8 says maintenance never blocks a reader, and the work directory's lease would make a command
//! that starts during a sweep wait for it. A reader that meets a vanished partition or object finds a miss and recomputes.
//! A partition is renamed aside before it is deleted, so a reader sees the whole directory or none of it.
const std = @import("std");
const language = @import("selka");
const retention = language.native_cache_retention;
const digest_rules = @import("digest.zig");
const record_rules = @import("record.zig");
const pack_rules = @import("pack.zig");
const store_rules = @import("store.zig");
const Digest = digest_rules.Digest;

/// Identity directories kept for a kind besides its current one: the most recently used.
pub const kept_identities = 2;

/// An object no live record names is collected once its file is older than this.
pub const object_age_ns: i64 = 14 * 24 * 3600 * std.time.ns_per_s;

/// What one retirement removed.
pub const Retired = struct {
    /// Identity directories removed.
    partitions: usize = 0,
    /// Unreferenced objects removed.
    objects: usize = 0,
    /// Markers of processes that are gone, removed.
    markers: usize = 0,
    /// Packs and partial pack files removed.
    packs: usize = 0,
};

/// A kind that is current, with its identity directory name.
pub const Current = struct { kind: []const u8, identity: Digest };

/// Why a retirement stopped. I/O failures are skipped, not errors: a collection that does not happen costs only disk.
pub const Error = std.mem.Allocator.Error;

/// Whether `name` names an identity directory: 64 lowercase hexadecimal digits.
pub fn isIdentityName(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |byte| {
        const digit = byte >= '0' and byte <= '9';
        const letter = byte >= 'a' and byte <= 'f';
        if (!digit and !letter) return false;
    }
    return true;
}

/// What a partition directory is called while it is being deleted.
const aside_prefix = ".retired-";

/// One identity directory considered for retirement.
const Partition = struct { name: []const u8, path: []const u8, used: i64 };

fn newerUse(_: void, left: Partition, right: Partition) bool {
    if (left.used != right.used) return left.used > right.used;
    return std.mem.lessThan(u8, left.name, right.name);
}

/// The file in the store's root holding the time of the last object scan, in decimal nanoseconds.
const scan_leaf = ".objects-scanned";

/// Objects are scanned for garbage at most this often.
const scan_interval_ns: i64 = 24 * 3600 * std.time.ns_per_s;

/// Whether the store under `work` holds more identity directories of some kind than a retirement keeps, or has not had
/// its objects scanned for a day, judged from directory listings and one small file.
pub fn due(a: std.mem.Allocator, io: std.Io, work: []const u8, now: i64) bool {
    const root = std.fmt.allocPrint(a, "{s}/{s}", .{ work, store_rules.root_leaf }) catch return false;
    defer a.free(root);
    if (packFiles(a, io, root) > pack_rules.max_kept + kept_identities) return true;
    const records = std.fmt.allocPrint(a, "{s}/records", .{root}) catch return false;
    defer a.free(records);
    var kinds = std.Io.Dir.cwd().openDir(io, records, .{ .iterate = true }) catch return false;
    defer kinds.close(io);
    var entries = kinds.iterate();
    while (entries.next(io) catch return false) |entry| {
        if (entry.kind != .directory) continue;
        if (identityCount(a, io, records, entry.name) > kept_identities + 1) return true;
    }
    const scanned = store_rules.Store.init(io, root).lastScan(a);
    return scanned == null or now - scanned.? >= scan_interval_ns;
}

/// How many packs the store under `root` holds.
fn packFiles(a: std.mem.Allocator, io: std.Io, root: []const u8) usize {
    const path = std.fmt.allocPrint(a, "{s}/{s}", .{ root, pack_rules.directory_leaf }) catch return 0;
    defer a.free(path);
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
    defer directory.close(io);
    var count: usize = 0;
    var entries = directory.iterate();
    while (entries.next(io) catch return count) |entry| {
        if (entry.kind == .file and pack_rules.isPackName(entry.name)) count += 1;
    }
    return count;
}

fn identityCount(a: std.mem.Allocator, io: std.Io, records: []const u8, kind: []const u8) usize {
    const path = std.fmt.allocPrint(a, "{s}/{s}", .{ records, kind }) catch return 0;
    defer a.free(path);
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
    defer directory.close(io);
    var count: usize = 0;
    var entries = directory.iterate();
    while (entries.next(io) catch return count) |entry| {
        if (entry.kind == .directory and isIdentityName(entry.name)) count += 1;
    }
    return count;
}

/// Retire what the store under `work` no longer needs, given the kinds that are current and the time `now`
/// (nanoseconds, the clock of the file timestamps). Two retirements at once are harmless: each removal is of a whole entry
/// and a removal that finds its entry gone is skipped.
pub fn retire(a: std.mem.Allocator, io: std.Io, work: []const u8, current: []const Current, now: i64) Error!Retired {
    var report: Retired = .{};
    const root = try std.fmt.allocPrint(a, "{s}/{s}", .{ work, store_rules.root_leaf });
    const store = store_rules.Store.init(io, root);
    report.partitions = try retirePartitions(a, store, current);
    report.markers = try clearMarkers(a, store);
    report.packs = try retirePacks(a, store, current, now);
    report.objects = try collectObjects(a, store, now);
    store.markScanned(a, now);
    return report;
}

fn retirePartitions(a: std.mem.Allocator, store: store_rules.Store, current: []const Current) Error!usize {
    const io = store.io;
    const records = try std.fmt.allocPrint(a, "{s}/records", .{store.root});
    var kinds = std.Io.Dir.cwd().openDir(io, records, .{ .iterate = true }) catch return 0;
    defer kinds.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = kinds.iterate();
    while (entries.next(io) catch return 0) |entry| {
        if (entry.kind == .directory and !std.mem.startsWith(u8, entry.name, ".")) try names.append(a, try a.dupe(u8, entry.name));
    }
    var removed: usize = 0;
    for (names.items) |kind| removed += try retireKind(a, store, kinds, kind, current);
    return removed;
}

fn retireKind(a: std.mem.Allocator, store: store_rules.Store, kinds: std.Io.Dir, kind: []const u8, current: []const Current) Error!usize {
    const io = store.io;
    var directory = kinds.openDir(io, kind, .{ .iterate = true }) catch return 0;
    defer directory.close(io);
    const own = ownIdentity(a, kind, current);
    var found: std.ArrayList(Partition) = .empty;
    var entries = directory.iterate();
    while (entries.next(io) catch return 0) |entry| {
        if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, aside_prefix)) {
            directory.deleteTree(io, try a.dupe(u8, entry.name)) catch continue;
            continue;
        }
        if (entry.kind != .directory or !isIdentityName(entry.name)) continue;
        if (own != null and std.mem.eql(u8, entry.name, own.?)) continue;
        const path = try std.fmt.allocPrint(a, "{s}/records/{s}/{s}", .{ store.root, kind, entry.name });
        try found.append(a, .{ .name = try a.dupe(u8, entry.name), .path = path, .used = store.lastUse(a, path) orelse 0 });
    }
    std.mem.sort(Partition, found.items, {}, newerUse);
    var removed: usize = 0;
    for (found.items, 0..) |partition, position| {
        if (position < kept_identities) continue;
        if (removeAside(a, directory, io, partition.name)) removed += 1;
    }
    return removed;
}

fn ownIdentity(a: std.mem.Allocator, kind: []const u8, current: []const Current) ?[]const u8 {
    for (current) |known| {
        if (!std.mem.eql(u8, known.kind, kind)) continue;
        return a.dupe(u8, &digest_rules.hex(known.identity)) catch return null;
    }
    return null;
}

/// Rename `name` in `directory` aside, then delete it: a reader sees the whole directory or none of it.
fn removeAside(a: std.mem.Allocator, directory: std.Io.Dir, io: std.Io, name: []const u8) bool {
    const aside = std.fmt.allocPrint(a, "{s}{s}", .{ aside_prefix, name }) catch return false;
    directory.rename(name, directory, aside, io) catch return false;
    directory.deleteTree(io, aside) catch return false;
    return true;
}

/// A partial pack file this old belongs to a writer that died: a live one renames its file within seconds.
const partial_age_ns: i64 = 3600 * std.time.ns_per_s;

/// A pack file considered for retirement.
const PackFile = struct { name: []const u8, used: i64 };

fn newerPack(_: void, left: PackFile, right: PackFile) bool {
    if (left.used != right.used) return left.used > right.used;
    return std.mem.lessThan(u8, right.name, left.name);
}

/// Remove the packs the rules keep no longer (`pack.max_kept` live ones, `kept_identities` of the others, the least recently used going first) and the partial
/// files a dead writer left. A pack is live when it holds records of a current kind at its current identity.
fn retirePacks(a: std.mem.Allocator, store: store_rules.Store, current: []const Current, now: i64) Error!usize {
    const io = store.io;
    const path = try std.fmt.allocPrint(a, "{s}/{s}", .{ store.root, pack_rules.directory_leaf });
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
    defer directory.close(io);
    const groups = try a.alloc(pack_rules.Group, current.len);
    for (current, groups) |known, *group| group.* = .{ .kind = known.kind, .identity = known.identity };
    var live: std.ArrayList(PackFile) = .empty;
    var dead: std.ArrayList(PackFile) = .empty;
    var partial: std.ArrayList([]const u8) = .empty;
    var entries = directory.iterate();
    while (entries.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const status = directory.statFile(io, entry.name, .{}) catch continue;
        const used: i64 = @intCast(@min(status.mtime.nanoseconds, std.math.maxInt(i64)));
        const name = try a.dupe(u8, entry.name);
        if (std.mem.endsWith(u8, name, ".partial")) {
            if (now - used >= partial_age_ns) try partial.append(a, name);
        } else if (pack_rules.isPackName(name)) {
            const one: PackFile = .{ .name = name, .used = used };
            if (packIsLive(io, path, name, groups)) try live.append(a, one) else try dead.append(a, one);
        }
    }
    var removed: usize = 0;
    for (partial.items) |name| removed += @intFromBool(removePack(directory, io, name));
    std.mem.sort(PackFile, live.items, {}, newerPack);
    std.mem.sort(PackFile, dead.items, {}, newerPack);
    for (live.items, 0..) |one, at| {
        if (at >= pack_rules.max_kept) removed += @intFromBool(removePack(directory, io, one.name));
    }
    for (dead.items, 0..) |one, at| {
        if (at >= kept_identities) removed += @intFromBool(removePack(directory, io, one.name));
    }
    return removed;
}

fn removePack(directory: std.Io.Dir, io: std.Io, name: []const u8) bool {
    directory.deleteFile(io, name) catch return false;
    return true;
}

/// Whether the first bytes of the pack `name` in `directory` say it holds a record of one of the `current` kinds at its identity.
fn packIsLive(io: std.Io, directory: []const u8, name: []const u8, current: []const pack_rules.Group) bool {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ directory, name }) catch return false;
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    defer file.close(io);
    var first: [pack_rules.peek_bytes]u8 = undefined;
    const got = file.readPositional(io, &.{&first}, 0) catch return false;
    return pack_rules.liveness(first[0..got], got < first.len, current) == .live;
}

fn clearMarkers(a: std.mem.Allocator, store: store_rules.Store) Error!usize {
    const io = store.io;
    const path = try std.fmt.allocPrint(a, "{s}/inflight", .{store.root});
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
    defer directory.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = directory.iterate();
    while (entries.next(io) catch return 0) |entry| {
        if (entry.kind == .file) try names.append(a, try a.dupe(u8, entry.name));
    }
    var removed: usize = 0;
    for (names.items) |name| {
        const file = try std.fmt.allocPrint(a, "{s}/{s}", .{ path, name });
        const bytes = (try store.load(a, file)) orelse continue;
        const marker = store_rules.Marker.parse(bytes);
        if (marker != null and marker.?.alive(a, io)) continue;
        store_rules.discard(io, file);
        removed += 1;
    }
    return removed;
}

/// An object file: its path and its name's digest.
const ObjectFile = struct { path: []const u8, digest: Digest };

fn collectObjects(a: std.mem.Allocator, store: store_rules.Store, now: i64) Error!usize {
    const old = try oldObjects(a, store, now);
    if (old.len == 0) return 0;
    var live: std.AutoHashMapUnmanaged(Digest, void) = .empty;
    try liveObjects(a, store, &live);
    var removed: usize = 0;
    for (old) |object| {
        if (live.contains(object.digest)) continue;
        store_rules.discard(store.io, object.path);
        removed += 1;
    }
    return removed;
}

fn oldObjects(a: std.mem.Allocator, store: store_rules.Store, now: i64) Error![]const ObjectFile {
    const io = store.io;
    const root = try std.fmt.allocPrint(a, "{s}/objects", .{store.root});
    var objects = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return &.{};
    defer objects.close(io);
    var old: std.ArrayList(ObjectFile) = .empty;
    var fans = objects.iterate();
    while (fans.next(io) catch return old.items) |fan| {
        if (fan.kind != .directory) continue;
        var inner = objects.openDir(io, fan.name, .{ .iterate = true }) catch continue;
        defer inner.close(io);
        var files = inner.iterate();
        while (files.next(io) catch break) |file| {
            if (file.kind != .file) continue;
            const digest = digest_rules.parseHex(file.name) orelse continue;
            const status = inner.statFile(io, file.name, .{}) catch continue;
            if (now - @as(i64, @intCast(@min(status.mtime.nanoseconds, std.math.maxInt(i64)))) < object_age_ns) continue;
            try old.append(a, .{ .path = try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ root, fan.name, file.name }), .digest = digest });
        }
    }
    return old.items;
}

/// Every object a record in the store names.
fn liveObjects(a: std.mem.Allocator, store: store_rules.Store, live: *std.AutoHashMapUnmanaged(Digest, void)) Error!void {
    const io = store.io;
    try livePackObjects(a, store, live);
    const records = try std.fmt.allocPrint(a, "{s}/records", .{store.root});
    var directory = std.Io.Dir.cwd().openDir(io, records, .{ .iterate = true }) catch return;
    defer directory.close(io);
    var walker = directory.walk(a) catch return;
    defer walker.deinit();
    while (walker.next(io) catch return) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".rec")) continue;
        const path = try std.fmt.allocPrint(a, "{s}/{s}", .{ records, entry.path });
        const bytes = (try store.load(a, path)) orelse continue;
        if (record_rules.objectOf(bytes)) |named| try live.put(a, named, {});
    }
}

/// Every object a record in a pack names: a record that is served from a pack needs its object as much as a file's.
fn livePackObjects(a: std.mem.Allocator, store: store_rules.Store, live: *std.AutoHashMapUnmanaged(Digest, void)) Error!void {
    const io = store.io;
    const path = try std.fmt.allocPrint(a, "{s}/{s}", .{ store.root, pack_rules.directory_leaf });
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer directory.close(io);
    var entries = directory.iterate();
    while (entries.next(io) catch return) |entry| {
        if (entry.kind != .file or !pack_rules.isPackName(entry.name)) continue;
        const file = try std.fmt.allocPrint(a, "{s}/{s}", .{ path, entry.name });
        const bytes = (try store.load(a, file)) orelse continue;
        const view = pack_rules.View.parse(bytes) orelse continue;
        for (0..view.count) |slot| {
            if (record_rules.objectOf(view.recordAt(slot))) |named| try live.put(a, named, {});
        }
    }
}

fn plant(io: std.Io, a: std.mem.Allocator, store: store_rules.Store, kind: []const u8, identity: Digest, used: i64) !void {
    const directory = try store.partition(a, kind, identity);
    try std.Io.Dir.cwd().createDirPath(io, directory);
    store.touch(a, directory, used);
    const file = try store.recordPath(a, directory, @splat(7));
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(file).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = "record" });
}

fn present(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

test "a kind keeps its current identity and the two most recently used others" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    try plant(io, a, store, "test-exec", @splat(1), 10);
    try plant(io, a, store, "test-exec", @splat(2), 50);
    try plant(io, a, store, "test-exec", @splat(3), 20);
    try plant(io, a, store, "test-exec", @splat(4), 40);
    try plant(io, a, store, "test-exec", @splat(5), 30);
    const current = [_]Current{.{ .kind = "test-exec", .identity = @splat(1) }};
    try std.testing.expect(due(a, io, work, 100));
    const report = try retire(a, io, work, &current, 100);
    try std.testing.expectEqual(@as(usize, 2), report.partitions);
    try std.testing.expect(present(io, try store.partition(a, "test-exec", @splat(1))));
    try std.testing.expect(present(io, try store.partition(a, "test-exec", @splat(2))));
    try std.testing.expect(present(io, try store.partition(a, "test-exec", @splat(4))));
    try std.testing.expect(!present(io, try store.partition(a, "test-exec", @splat(3))));
    try std.testing.expect(!present(io, try store.partition(a, "test-exec", @splat(5))));
    try std.testing.expect(!due(a, io, work, 101));
    try std.testing.expect(due(a, io, work, 101 + scan_interval_ns));
}

test "a kind that is no longer registered keeps only its two most recently used identities" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    try plant(io, a, store, "retired-kind", @splat(1), 10);
    try plant(io, a, store, "retired-kind", @splat(2), 30);
    try plant(io, a, store, "retired-kind", @splat(3), 20);
    const report = try retire(a, io, work, &.{}, 100);
    try std.testing.expectEqual(@as(usize, 1), report.partitions);
    try std.testing.expect(!present(io, try store.partition(a, "retired-kind", @splat(1))));
}

test "retirement runs while a command holds the work directory, because it takes no lease, and clears what an interrupted one left" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    try plant(io, a, store, "k", @splat(1), 10);
    try plant(io, a, store, "k", @splat(2), 20);
    try plant(io, a, store, "k", @splat(3), 30);
    try plant(io, a, store, "k", @splat(4), 40);
    const leftover = try std.fs.path.join(a, &.{ store.root, "records", "k", aside_prefix ++ "abandoned" });
    try std.Io.Dir.cwd().createDirPath(io, leftover);
    const held = try retention.Context.init(a, io, work, .compiler).lease();
    defer held.close(io);
    const report = try retire(a, io, work, &.{}, 100);
    try std.testing.expectEqual(@as(usize, 2), report.partitions);
    try std.testing.expect(!present(io, try store.partition(a, "k", @splat(1))));
    try std.testing.expect(present(io, try store.partition(a, "k", @splat(4))));
    try std.testing.expect(!present(io, leftover));
}

test "an object no record names is collected once it is old, and one a record names is kept" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    const kept_bytes = try a.alloc(u8, 5000);
    @memset(kept_bytes, 'o');
    const orphan_bytes = try a.dupe(u8, kept_bytes);
    orphan_bytes[0] = 'p';
    const kept = digest_rules.hash(kept_bytes);
    const orphan = digest_rules.hash(orphan_bytes);
    try std.testing.expect(try store.publishObject(a, kept, kept_bytes));
    try std.testing.expect(try store.publishObject(a, orphan, orphan_bytes));
    for ([_]Digest{ kept, orphan }) |name| {
        const path = try store.objectPath(a, name);
        try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 10 * std.time.ns_per_s } } });
    }
    const named: record_rules.Record = .{ .kind = "k", .identity = @splat(1), .key = @splat(9), .argument = "", .result = @splat(0), .payload = .{ .object = kept }, .reads = &.{} };
    const directory = try store.partition(a, "k", @splat(1));
    try std.testing.expect(try store.publish(a, try store.recordPath(a, directory, @splat(9)), try record_rules.encode(a, named)));
    const current = [_]Current{.{ .kind = "k", .identity = @splat(1) }};
    const soon = try retire(a, io, work, &current, 20 * std.time.ns_per_s);
    try std.testing.expectEqual(@as(usize, 0), soon.objects);
    const late = try retire(a, io, work, &current, object_age_ns + 20 * std.time.ns_per_s);
    try std.testing.expectEqual(@as(usize, 1), late.objects);
    try std.testing.expect(present(io, try store.objectPath(a, kept)));
    try std.testing.expect(!present(io, try store.objectPath(a, orphan)));
}

test "markers of dead processes are cleared and those of live ones are not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    const mine = try store_rules.Marker.mine(a, io);
    const dead: store_rules.Marker = .{ .pid = 4_000_000, .start = 1, .host = mine.host };
    try std.testing.expect(try store.publish(a, try store.inflightPath(a, @splat(1)), try mine.text(a)));
    try std.testing.expect(try store.publish(a, try store.inflightPath(a, @splat(2)), try dead.text(a)));
    const report = try retire(a, io, work, &.{}, 100);
    try std.testing.expectEqual(@as(usize, 1), report.markers);
    try std.testing.expect(present(io, try store.inflightPath(a, @splat(1))));
    try std.testing.expect(!present(io, try store.inflightPath(a, @splat(2))));
}

/// A pack to plant: one record of `kind` at `identity`, last used at `used` seconds, named by `tag`, naming `object` when it has one.
const PackPlan = struct { kind: []const u8, identity: Digest, tag: u8, used: i64, object: ?Digest = null };

fn plantPack(io: std.Io, a: std.mem.Allocator, store: *store_rules.Store, plan: PackPlan) ![]const u8 {
    const payload: record_rules.Payload = if (plan.object) |named| .{ .object = named } else .{ .inline_bytes = "x" };
    const record: record_rules.Record = .{ .kind = plan.kind, .identity = plan.identity, .key = @splat(plan.tag), .argument = "", .result = @splat(0), .payload = payload, .reads = &.{} };
    const bytes = try record_rules.encode(a, record);
    const built = (try pack_rules.build(a, &.{.{ .kind = plan.kind, .identity = plan.identity }}, &.{.{ .key = @splat(plan.tag), .bytes = bytes }})).?;
    const path = try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, try pack_rules.fileName(a, plan.tag, built.digest) });
    try std.testing.expect(try store.publish(a, path, built.bytes));
    try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = plan.used * std.time.ns_per_s } } });
    return path;
}

fn expectPresent(io: std.Io, paths: []const []const u8, wanted: bool) !void {
    for (paths) |path| try std.testing.expectEqual(wanted, present(io, path));
}

test "retirement keeps the four most recently used packs that hold a current kind and the two most recent others, and drops partial files left by a dead writer" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    const current = [_]Current{.{ .kind = "k", .identity = @splat(1) }};
    // Six live packs, the least recently used of which are the first two; four packs of another identity.
    const live_first = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 1, .used = 100 });
    const live_second = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 2, .used = 200 });
    const live_third = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 3, .used = 300 });
    const live_fourth = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 4, .used = 400 });
    const live_fifth = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 5, .used = 500 });
    const live_newest = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 6, .used = 600 });
    const dead_old = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(2), .tag = 7, .used = 150 });
    const dead_older = try plantPack(io, a, &store, .{ .kind = "gone", .identity = @splat(1), .tag = 8, .used = 120 });
    const dead_recent = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(3), .tag = 9, .used = 450 });
    const dead_newest = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(4), .tag = 10, .used = 650 });
    const stray = try std.fmt.allocPrint(a, "{s}/{s}/{s}.1.2.partial", .{ store.root, pack_rules.directory_leaf, "00000000000000000001-abababababababab.pack" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = stray, .data = "half a pack" });
    try std.Io.Dir.cwd().setTimestamps(io, stray, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 5 * std.time.ns_per_s } } });
    try std.testing.expect(due(a, io, work, 700 * std.time.ns_per_s));
    const report = try retire(a, io, work, &current, 700 * std.time.ns_per_s + partial_age_ns);
    try std.testing.expectEqual(@as(usize, 2 + 2 + 1), report.packs);
    try expectPresent(io, &.{ live_first, live_second, dead_old, dead_older, stray }, false);
    try expectPresent(io, &.{ live_third, live_fourth, live_fifth, live_newest, dead_recent, dead_newest }, true);
    try std.testing.expect(!due(a, io, work, 700 * std.time.ns_per_s));
}

test "an object that only a record in a pack names is kept, and one no record names is collected" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    var store = store_rules.Store.init(io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    const kept_bytes = try a.alloc(u8, 5000);
    @memset(kept_bytes, 'o');
    const orphan_bytes = try a.dupe(u8, kept_bytes);
    orphan_bytes[0] = 'p';
    const kept = digest_rules.hash(kept_bytes);
    const orphan = digest_rules.hash(orphan_bytes);
    try std.testing.expect(try store.publishObject(a, kept, kept_bytes));
    try std.testing.expect(try store.publishObject(a, orphan, orphan_bytes));
    for ([_]Digest{ kept, orphan }) |name| {
        try std.Io.Dir.cwd().setTimestamps(io, try store.objectPath(a, name), .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 10 * std.time.ns_per_s } } });
    }
    _ = try plantPack(io, a, &store, .{ .kind = "k", .identity = @splat(1), .tag = 1, .used = 100, .object = kept });
    const current = [_]Current{.{ .kind = "k", .identity = @splat(1) }};
    const late = try retire(a, io, work, &current, object_age_ns + 20 * std.time.ns_per_s);
    try std.testing.expectEqual(@as(usize, 1), late.objects);
    try std.testing.expect(present(io, try store.objectPath(a, kept)));
    try std.testing.expect(!present(io, try store.objectPath(a, orphan)));
}
