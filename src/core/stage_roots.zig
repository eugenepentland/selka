//! The roots of the stage store: which records a build needed, kept per demand generation, and the ranks that order
//! the records compaction keeps (`stage_pack.State.compactLive`). A build writes its roots (`retain`) when it publishes
//! its generation: the 8-byte prefix of every key it loaded, checked or saved, in the order it first needed them. The
//! roots that stay are the current and last generation of every demand scope (`demand_generation.zig`), the generation
//! each replay record names (`replay_record.zig`) and the newest session manifests. A key no root names is dead, and
//! dropping it only costs a miss, so a record whose root was lost is recomputed, never misread.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const demand_generation = @import("demand_generation.zig");
const packs = @import("stage_pack.zig");
const replay_record = @import("replay_record.zig");
const stage = @import("stage_store.zig");

/// The rank of each live key prefix (`rankKey`): the first key a build needed has rank 0.
pub const Ranks = packs.Ranks;

const magic = "selka-stage-roots-v1\n";
/// The directory of manifests, inside the stage store's directory (the store lists only its packs and journals).
const directory_leaf = "roots";
const manifest_suffix = ".roots";
const partial_suffix = ".partial";
/// Manifests a read accepts: 8 million keys.
const maximum_manifest = 64 << 20;
/// Session manifests (generation 0, written by commands that publish no generation) that stay, newest first.
const sessions_kept = 4;

/// The 8-byte prefix a manifest stores and a rank is keyed by.
pub fn rankKey(key: stage.Digest) u64 {
    return std.mem.readInt(u64, key[0..8], .little);
}

/// The file name of `label`'s manifest at `generation`. Labels are file-name safe (demand scope names are hex).
pub fn manifestName(a: std.mem.Allocator, label: []const u8, generation: u64) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}-{d}{s}", .{ label, generation, manifest_suffix });
}

/// Record the keys `storage` touched as the roots of `label` at `generation` (generation 0 for a session). Best effort:
/// a manifest that cannot be written costs the next build its records' misses, nothing else. Manifests that no root names
/// are removed by `rank`, which knows what the replay records name; the work-directory check runs again once enough of them
/// accumulate (`work_retention.zig`).
pub fn retain(storage: *const stage.Store, a: std.mem.Allocator, io: std.Io, label: []const u8, generation: u64) void {
    const keys = storage.touchedKeys(a) catch return;
    const directory = std.fs.path.join(a, &.{ storage.storage.config.root, directory_leaf }) catch return;
    const name = manifestName(a, label, generation) catch return;
    writeManifest(io, a, directory, name, keys) catch return;
}

/// How many manifests `root` holds, named by any root or not: the work-directory check counts them to decide when to prune.
pub fn manifestCount(io: std.Io, a: std.mem.Allocator, root: []const u8) u64 {
    const directory = std.fs.path.join(a, &.{ root, directory_leaf }) catch return 0;
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    var count: u64 = 0;
    var entries = dir.iterate();
    while (entries.next(io) catch return count) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, manifest_suffix)) count += 1;
    }
    return count;
}

/// The ranks of the keys the roots name, given the work directory `work` (demand pointers and replay records) and the
/// stage store `root`. A key's rank is its place in the first manifest, in priority order, that names it: the current
/// generations come first, then the last ones, the replayed ones and the newest sessions. Manifests no root names are
/// removed. Allocation failures are explicit; a missing or damaged manifest names nothing.
pub fn rank(a: std.mem.Allocator, io: std.Io, work: []const u8, root: []const u8) std.mem.Allocator.Error!Ranks {
    const directory = try std.fs.path.join(a, &.{ root, directory_leaf });
    var names: std.ArrayList([]const u8) = .empty;
    const pointers = try demand_generation.listed(a, io, work);
    for (pointers) |listed| if (listed.pointer.current > 0) try names.append(a, try manifestName(a, listed.scope, listed.pointer.current));
    for (pointers) |listed| if (listed.pointer.high > listed.pointer.current) try names.append(a, try manifestName(a, listed.scope, listed.pointer.high));
    const replays = try replay_record.scan(a, io, try std.fs.path.join(a, &.{ work, "replay-v1" }));
    std.mem.sort(replay_record.Published, replays, {}, newerFirst);
    for (replays) |published| try names.append(a, try manifestName(a, published.scope, published.demand));
    for (try sessions(a, io, directory)) |name| try names.append(a, name);
    var kept: std.StringHashMapUnmanaged(void) = .empty;
    var ranks: Ranks = .empty;
    for (names.items) |name| {
        try kept.put(a, name, {});
        const keys = (try readManifest(io, a, directory, name)) orelse continue;
        for (keys) |key| {
            if (!ranks.contains(key)) try ranks.put(a, key, ranks.count());
        }
    }
    try removeUnkept(io, a, directory, &kept);
    return ranks;
}

/// Replay generations, newest first, so a generation a recent build names ranks before an older one.
fn newerFirst(_: void, lhs: replay_record.Published, rhs: replay_record.Published) bool {
    if (lhs.demand != rhs.demand) return lhs.demand > rhs.demand;
    return std.mem.lessThan(u8, lhs.scope, rhs.scope);
}

/// The newest `sessions_kept` generation-0 manifests of `directory`, by modification time.
fn sessions(a: std.mem.Allocator, io: std.Io, directory: []const u8) std.mem.Allocator.Error![]const []const u8 {
    const Named = struct { name: []const u8, written: i96 };
    var found: std.ArrayList(Named) = .empty;
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return &.{}) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, "-0" ++ manifest_suffix)) continue;
        const status = dir.statFile(io, entry.name, .{}) catch continue;
        try found.append(a, .{ .name = try a.dupe(u8, entry.name), .written = status.mtime.nanoseconds });
    }
    std.mem.sort(Named, found.items, {}, struct {
        fn newer(_: void, lhs: Named, rhs: Named) bool {
            return lhs.written > rhs.written;
        }
    }.newer);
    const count = @min(found.items.len, sessions_kept);
    const names = try a.alloc([]const u8, count);
    for (found.items[0..count], names) |item, *name| name.* = item.name;
    return names;
}

/// Write `keys` as the manifest `name` in `directory`: the magic, a count, 8-byte prefixes and a checksum, published
/// by rename so a reader sees the whole file or none of it.
fn writeManifest(io: std.Io, a: std.mem.Allocator, directory: []const u8, name: []const u8, keys: []const stage.Digest) !void {
    const bytes = try a.alloc(u8, magic.len + 8 + keys.len * 8 + 32);
    @memcpy(bytes[0..magic.len], magic);
    std.mem.writeInt(u64, bytes[magic.len..][0..8], keys.len, .little);
    for (keys, 0..) |key, index| @memcpy(bytes[magic.len + 8 + index * 8 ..][0..8], key[0..8]);
    const body = bytes.len - 32;
    fast_blake3.hash(bytes[0..body], bytes[body..][0..32]);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, directory);
    const final = try std.fs.path.join(a, &.{ directory, name });
    const partial = try std.fmt.allocPrint(a, "{s}{s}", .{ final, partial_suffix });
    try cwd.writeFile(io, .{ .sub_path = partial, .data = bytes });
    try cwd.rename(partial, cwd, final, io);
}

/// The keys of manifest `name`, or null when it is missing or damaged.
fn readManifest(io: std.Io, a: std.mem.Allocator, directory: []const u8, name: []const u8) std.mem.Allocator.Error!?[]const u64 {
    const path = try std.fs.path.join(a, &.{ directory, name });
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(maximum_manifest)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (bytes.len < magic.len + 8 + 32 or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
    const count = std.mem.readInt(u64, bytes[magic.len..][0..8], .little);
    const body = bytes.len - magic.len - 8 - 32;
    if (count > body / 8 or count * 8 != body) return null;
    const checksum_at = bytes.len - 32;
    var digest: [32]u8 = undefined;
    fast_blake3.hash(bytes[0..checksum_at], &digest);
    if (!std.mem.eql(u8, &digest, bytes[checksum_at..])) return null;
    const keys = try a.alloc(u64, @intCast(count));
    for (keys, 0..) |*key, index| key.* = std.mem.readInt(u64, bytes[magic.len + 8 + index * 8 ..][0..8], .little);
    return keys;
}

/// Remove every manifest of `directory` that `kept` does not name.
fn removeUnkept(io: std.Io, a: std.mem.Allocator, directory: []const u8, kept: *const std.StringHashMapUnmanaged(void)) std.mem.Allocator.Error!void {
    var names: std.ArrayList([]const u8) = .empty;
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, manifest_suffix)) continue;
        if (!kept.contains(entry.name)) try names.append(a, try a.dupe(u8, entry.name));
    }
    for (names.items) |name| dir.deleteFile(io, name) catch continue;
}

/// The key of record `name` in a store of the compiler that `storage` opens (`stage.Store.key`).
fn keyOf(storage: *const stage.Store, name: []const u8) stage.Digest {
    return storage.key("roots-test", &.{name});
}

/// Save records named `names` into a fresh store on `work`, and retain their keys as `label` at `generation`.
fn retainNamed(a: std.mem.Allocator, work: []const u8, label: []const u8, generation: u64, names: []const []const u8) !void {
    var writer = try stage.Store.init(a, std.testing.io, work);
    defer writer.deinit();
    for (names) |name| try std.testing.expect(try writer.save(keyOf(&writer, name), name));
    try std.testing.expect(try writer.flush());
    retain(&writer, a, std.testing.io, label, generation);
}

/// Write a replay record of `work` that names `generation` in the scope `label`, as `build_replay.remember` does.
fn writeReplay(a: std.mem.Allocator, work: []const u8, label: []const u8, generation: u64) !void {
    const payload = try std.json.Stringify.valueAlloc(a, .{ .published = replay_record.Published{ .demand = generation, .scope = label } }, .{});
    var digest: [32]u8 = undefined;
    fast_blake3.hash(payload, &digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    const record = try std.json.Stringify.valueAlloc(a, replay_record.Envelope{ .version = replay_record.version, .payload = payload, .checksum = &hex }, .{});
    const directory = try std.fs.path.join(a, &.{ work, "replay-v1" });
    try std.Io.Dir.cwd().createDirPath(std.testing.io, directory);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fs.path.join(a, &.{ directory, "record.1" }), .data = record });
}

test "a manifest keeps each key once, in the order the build first needed it, and a damaged one names none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var writer = try stage.Store.init(std.testing.allocator, std.testing.io, work);
    defer writer.deinit();
    const first = keyOf(&writer, "first");
    const second = keyOf(&writer, "second");
    try std.testing.expect(try writer.save(first, "one"));
    try std.testing.expect(try writer.save(second, "two"));
    try std.testing.expect(try writer.flush());
    try std.testing.expect((try writer.load(a, second)) != null);
    retain(&writer, a, std.testing.io, "label", 1);
    const directory = try std.fs.path.join(a, &.{ writer.storage.config.root, directory_leaf });
    const keys = (try readManifest(std.testing.io, a, directory, "label-1.roots")) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u64, &[_]u64{ rankKey(first), rankKey(second) }, keys);
    const path = try std.fs.path.join(a, &.{ directory, "label-1.roots" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expectEqual(@as(?[]const u64, null), try readManifest(std.testing.io, a, directory, "label-1.roots"));
}

test "ranks name the current generation first, then the last, replayed and session roots, and drop every other manifest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const scope = demand_generation.demandScope(work, "src/main.selka", "");
    const label = try demand_generation.scopeName(a, scope);
    try retainNamed(a, work, "stale-scope", 1, &.{"stale"});
    try retainNamed(a, work, label, 1, &.{"first"});
    try retainNamed(a, work, label, 2, &.{ "second", "third" });
    try retainNamed(a, work, label, 3, &.{"fourth"});
    try retainNamed(a, work, "session-run", 0, &.{"session"});
    try demand_generation.publish(a, std.testing.io, scope, .{ .read = 0, .write = 1, .last = 0 });
    try demand_generation.publish(a, std.testing.io, scope, .{ .read = 1, .write = 2, .last = 1 });
    try demand_generation.adopt(a, std.testing.io, scope, 1);
    try writeReplay(a, work, label, 3);
    const root = try std.fs.path.join(a, &.{ work, "stages-packed-v1" });
    const ranks = try rank(a, std.testing.io, work, root);
    var probe = try stage.Store.init(std.testing.allocator, std.testing.io, work);
    defer probe.deinit();
    try std.testing.expectEqual(@as(u64, 0), ranks.get(rankKey(keyOf(&probe, "first"))).?);
    try std.testing.expect(ranks.get(rankKey(keyOf(&probe, "second"))).? < 3);
    try std.testing.expect(ranks.get(rankKey(keyOf(&probe, "third"))).? < 3);
    try std.testing.expectEqual(@as(u64, 3), ranks.get(rankKey(keyOf(&probe, "fourth"))).?);
    try std.testing.expectEqual(@as(u64, 4), ranks.get(rankKey(keyOf(&probe, "session"))).?);
    try std.testing.expectEqual(@as(?u64, null), ranks.get(rankKey(keyOf(&probe, "stale"))));
    const directory = try std.fs.path.join(a, &.{ root, directory_leaf });
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, try std.fs.path.join(a, &.{ directory, "stale-scope-1.roots" }), .{}));
}
