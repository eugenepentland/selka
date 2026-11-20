//! The local records pack (round 14, D-L1r14-1): the records a tree adopts from the shared tier are written as one file when its engine ends, the next
//! process is served from it under this tree's stat tuples, and everything that goes wrong with a pack is a miss.
const std = @import("std");
const engine_rules = @import("engine.zig");
const explain_rules = @import("explain.zig");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const digest_rules = @import("digest.zig");
const local_rules = @import("local_records.zig");
const pack_rules = @import("pack.zig");
const shared_records = @import("shared_records.zig");
const shared_tier = @import("shared_tier.zig");
const store_rules = @import("store.zig");
const Fixture = fixture_rules.Fixture;

const second = std.time.ns_per_s;
const nodes = 20;
const many_nodes: [nodes]script.Node = blk: {
    var made: [nodes]script.Node = undefined;
    for (&made) |*node| node.* = fixture_rules.fileNode("/src/a.txt", .concat);
    break :blk made;
};
const many_files: script.Graph = .{ .nodes = &many_nodes };

/// A shared tier in a temporary directory, heap-allocated so the engines may point into it.
const Shared = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    records: shared_records.Records,

    fn create(gpa: std.mem.Allocator) !*Shared {
        const self = try gpa.create(Shared);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        const root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator());
        self.records = try shared_records.Records.open(self.arena.allocator(), std.testing.io, root);
        return self;
    }

    fn tier(self: *Shared) shared_tier.Tier {
        return self.records.tier();
    }

    fn destroy(self: *Shared) void {
        self.arena.deinit();
        self.temporary.cleanup();
        self.gpa.destroy(self);
    }
};

/// A tree: a fixture over the twenty-node graph whose file `/src/a.txt` holds `text`, aged past the racy window, with the shared tier on.
fn tree(gpa: std.mem.Allocator, shared: *Shared, text: []const u8, min: u32) !*Fixture {
    const fx = try Fixture.create(gpa, many_files);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", text);
    fx.files.advance(second);
    try fx.restart(.{ .shared = shared.tier(), .pack_min_records = min });
    return fx;
}

fn runAll(fx: *Fixture, expected: []const u8) !void {
    for (0..nodes) |number| try std.testing.expectEqualStrings(expected, try fx.run(@intCast(number)));
}

/// The pack files of `fx`'s work directory, oldest first, in `a`.
fn packNames(a: std.mem.Allocator, fx: *const Fixture) ![]const []const u8 {
    const directory = try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ fx.site.work, store_rules.root_leaf, pack_rules.directory_leaf });
    var listing = std.Io.Dir.cwd().openDir(std.testing.io, directory, .{ .iterate = true }) catch return &.{};
    defer listing.close(std.testing.io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = listing.iterate();
    while (try entries.next(std.testing.io)) |entry| {
        if (pack_rules.isPackName(entry.name)) try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn older(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.older);
    return names.items;
}

fn packPath(a: std.mem.Allocator, fx: *const Fixture, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}/{s}/{s}/{s}", .{ fx.site.work, store_rules.root_leaf, pack_rules.directory_leaf, name });
}

fn exists(path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(std.testing.io, path, .{}) catch return false;
    return true;
}

/// Whether every node's record is a file of its own in `fx`'s work directory, or none is.
fn recordFiles(a: std.mem.Allocator, fx: *Fixture, wanted: bool) !void {
    for (0..nodes) |number| try std.testing.expectEqual(wanted, exists(try fx.recordPath(a, @intCast(number))));
}

/// Put `bytes` where the pack was, start a process with no tier, and run every node: all are computed (the pack is not there), and the next process is
/// served the files that computing left.
fn damaged(a: std.mem.Allocator, fx: *Fixture, path: []const u8, bytes: []const u8) !void {
    try dropRecordFiles(a, fx);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try fx.restart(.{});
    try runAll(fx, "alpha");
    try std.testing.expectEqual(@as(u64, nodes), fx.numbers().count(.recomputed));
    try fx.restart(.{});
    try runAll(fx, "alpha");
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    try dropRecordFiles(a, fx);
}

fn dropRecordFiles(a: std.mem.Allocator, fx: *Fixture) !void {
    for (0..nodes) |number| store_rules.discard(std.testing.io, try fx.recordPath(a, @intCast(number)));
}

/// Engines over `fx`'s work directory and tier, each of which was asked for its share of the nodes.
fn startEngines(gpa: std.mem.Allocator, fx: *Fixture, shared: *Shared, engines: []*engine_rules.Engine) !void {
    for (engines, 0..) |*slot, at| {
        slot.* = try gpa.create(engine_rules.Engine);
        slot.*.* = try engine_rules.Engine.init(gpa, std.testing.io, fx.files.world(), .{ .work = fx.site.work, .shared = shared.tier(), .policy = .{ .pack_min_records = 1 } });
        try slot.*.register(&fx.kind);
        slot.*.share(&fx.kind, null);
        const share = nodes / engines.len;
        for (at * share..(at + 1) * share) |number| {
            var text: [8]u8 = undefined;
            const answer = try slot.*.query(&fx.kind, try std.fmt.bufPrint(&text, "{d}", .{number}));
            try std.testing.expectEqualStrings("alpha", try answer.payload());
        }
    }
}

/// End every engine on a thread of its own, together, and free them.
fn endTogether(gpa: std.mem.Allocator, engines: []*engine_rules.Engine) !void {
    defer for (engines) |engine| gpa.destroy(engine);
    var threads: [8]std.Thread = undefined;
    for (engines, 0..) |engine, at| threads[at] = try std.Thread.spawn(.{}, engine_rules.Engine.deinit, .{engine});
    for (threads[0..engines.len]) |thread| thread.join();
}

fn plant(a: std.mem.Allocator, store: *store_rules.Store, built: pack_rules.Built, now: i64) !void {
    const name = try pack_rules.fileName(a, now, built.digest);
    try std.testing.expect(try store.publish(a, try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ store.root, pack_rules.directory_leaf, name }), built.bytes));
}

/// Two trees with the same file; the first computed every node into the tier; the second is restarted with the tier and runs every node, its file
/// having been rewritten to another tuple so every adoption is refreshed. Its engine has not ended.
fn adopted(gpa: std.mem.Allocator, shared: *Shared, min: u32) !struct { first: *Fixture, fresh: *Fixture } {
    const first = try tree(gpa, shared, "alpha", min);
    errdefer first.destroy();
    const fresh = try tree(gpa, shared, "alpha", min);
    errdefer fresh.destroy();
    try runAll(first, "alpha");
    try fresh.files.write("/src/a.txt", "alpha");
    fresh.files.advance(second);
    try fresh.restart(.{ .shared = shared.tier(), .pack_min_records = min });
    try runAll(fresh, "alpha");
    try std.testing.expectEqual(@as(u64, nodes), fresh.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, nodes), fresh.numbers().count(.refreshed));
    return .{ .first = first, .fresh = fresh };
}

test "pack: the records a fresh tree adopts are written as one file, and the next process is served from it without hashing" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Nothing was written while the engine ran: the adopted records wait for its end.
    try std.testing.expectEqual(@as(usize, 0), (try packNames(a, trees.fresh)).len);
    try std.testing.expect(!exists(try trees.fresh.recordPath(a, 0)));
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 1), (try packNames(a, trees.fresh)).len);
    // Not one record is a file of its own, and the next process hashes nothing and asks no tier.
    try recordFiles(a, trees.fresh, false);
    trees.fresh.files.resetCounters();
    try runAll(trees.fresh, "alpha");
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.refreshed));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, nodes), trees.fresh.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.files.count("reads"));
    // A process that only served from the pack writes nothing.
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 1), (try packNames(a, trees.fresh)).len);
}

test "pack: fewer adopted records than the policy's minimum are files of their own" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes + 1);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 0), (try packNames(a, trees.fresh)).len);
    try recordFiles(a, trees.fresh, true);
    trees.fresh.files.resetCounters();
    try runAll(trees.fresh, "alpha");
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.files.count("reads"));
}

test "pack: a pack that does not parse is ignored whole, and a record in it that is damaged is a miss for that record only" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    const path = try packPath(a, trees.fresh, (try packNames(a, trees.fresh))[0]);
    const whole = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    // A byte of a record: the pack parses, and the record whose trailer disagrees is the only one that is not served.
    const hurt = try a.dupe(u8, whole);
    hurt[hurt.len - 1] ^= 0x55;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = hurt });
    try trees.fresh.restart(.{});
    try runAll(trees.fresh, "alpha");
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, nodes - 1), trees.fresh.numbers().count(.served));
    // A byte of the index, a cut file, and a file that is no pack at all: the pack is not there, and the next process is served what computing left.
    const flipped = try a.dupe(u8, whole);
    flipped[pack_rules.peek_bytes / 8] ^= 1;
    try damaged(a, trees.fresh, path, flipped);
    try damaged(a, trees.fresh, path, whole[0 .. whole.len / 2]);
    try damaged(a, trees.fresh, path, "not a pack");
    try damaged(a, trees.fresh, path, "");
}

test "pack: a record whose file changed is refused, one whose file only moved is hashed once and then trusted again" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    // The same bytes under a new inode: the tuple in the pack no longer holds, the hash does, and the refreshed record is the next pack's.
    try trees.fresh.files.replace("/src/a.txt", "alpha");
    trees.fresh.files.advance(second);
    trees.fresh.files.resetCounters();
    try trees.fresh.restart(.{ .pack_min_records = 1 });
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.numbers().count(.refreshed));
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.files.count("reads"));
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 2), (try packNames(a, trees.fresh)).len);
    trees.fresh.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.refreshed));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.files.count("reads"));
    // Other bytes: the record is stale, whichever pack it is in, and the query is computed.
    try trees.fresh.files.write("/src/a.txt", "beta!");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{});
    try std.testing.expectEqualStrings("beta!", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqualStrings("beta!", try trees.fresh.run(4));
    // The computed record is a file, and a file wins over a stale pack record: the next process serves it.
    try trees.fresh.restart(.{});
    try std.testing.expectEqualStrings("beta!", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.recomputed));
}

test "pack: a file of the key that no longer serves is removed when a pack serves the key, and the refreshed record goes to the next pack" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    // Other text: the query is computed, and its file is the only record of the key that serves.
    try trees.fresh.files.write("/src/a.txt", "beta!");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{});
    try std.testing.expectEqualStrings("beta!", try trees.fresh.run(3));
    try std.testing.expect(exists(try trees.fresh.recordPath(a, 3)));
    // The text is back: the file is stale, the pack's record holds, and the stale file is gone.
    try trees.fresh.files.write("/src/a.txt", "alpha");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{ .pack_min_records = 1 });
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.numbers().count(.recomputed));
    try std.testing.expect(!exists(try trees.fresh.recordPath(a, 3)));
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 2), (try packNames(a, trees.fresh)).len);
    trees.fresh.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(3));
    try std.testing.expectEqual(@as(u64, 0), trees.fresh.files.count("reads"));
}

test "pack: a pack whose every record a newer pack carries is removed, and one that only some are is kept" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    const first_pack = (try packNames(a, trees.fresh))[0];
    // The file moves and every record is refreshed: the new pack carries all of the old one.
    try trees.fresh.files.replace("/src/a.txt", "alpha");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{ .pack_min_records = nodes });
    try runAll(trees.fresh, "alpha");
    try std.testing.expectEqual(@as(u64, nodes), trees.fresh.numbers().count(.refreshed));
    try trees.fresh.restart(.{});
    const after = try packNames(a, trees.fresh);
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expect(!std.mem.eql(u8, first_pack, after[0]));
    // Only one record moves this time: its pack carries a part of the pack before it, which stays.
    try trees.fresh.files.replace("/src/a.txt", "alpha");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{ .pack_min_records = 1 });
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(0));
    try trees.fresh.restart(.{});
    try std.testing.expectEqual(@as(usize, 2), (try packNames(a, trees.fresh)).len);
}

test "pack: explain finds the record that only a pack holds" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    try recordFiles(a, trees.fresh, false);
    const verdict = try explain_rules.explain(&trees.fresh.runner, a, &trees.fresh.kind, "3");
    try std.testing.expect(verdict == .served);
    try trees.fresh.files.write("/src/a.txt", "beta!");
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{});
    const changed = try explain_rules.explain(&trees.fresh.runner, a, &trees.fresh.kind, "3");
    try std.testing.expect(changed == .changed);
}

test "pack: two engines ending at once in one work directory lose nothing of each other's records" {
    const gpa = std.testing.allocator;
    const shared = try Shared.create(gpa);
    defer shared.destroy();
    const first = try tree(gpa, shared, "alpha", 1);
    defer first.destroy();
    const fresh = try tree(gpa, shared, "alpha", 1);
    defer fresh.destroy();
    try runAll(first, "alpha");
    try fresh.files.write("/src/a.txt", "alpha");
    fresh.files.advance(second);
    var engines: [4]*engine_rules.Engine = undefined;
    try startEngines(gpa, fresh, shared, &engines);
    try endTogether(gpa, &engines);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 4), (try packNames(arena.allocator(), fresh)).len);
    fresh.files.resetCounters();
    try fresh.restart(.{});
    try runAll(fresh, "alpha");
    try std.testing.expectEqual(@as(u64, 0), fresh.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fresh.files.count("reads"));
}

test "pack: a record the process forgot is not served from a pack again, and the pack is rewritten without it" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const trees = try adopted(std.testing.allocator, shared, nodes);
    defer trees.first.destroy();
    defer trees.fresh.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try trees.fresh.restart(.{});
    const before = (try packNames(a, trees.fresh))[0];
    try trees.fresh.restart(.{});
    trees.fresh.runner.forget(&trees.fresh.kind, "7");
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(8));
    trees.fresh.files.advance(second);
    try trees.fresh.restart(.{});
    const after = try packNames(a, trees.fresh);
    try std.testing.expectEqual(@as(usize, 1), after.len);
    try std.testing.expect(!std.mem.eql(u8, before, after[0]));
    // The rewritten pack keeps the time of the one it replaces.
    try std.testing.expectEqualStrings(before[0..20], after[0][0..20]);
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(7));
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.numbers().count(.recomputed));
    try std.testing.expectEqualStrings("alpha", try trees.fresh.run(8));
    try std.testing.expectEqual(@as(u64, 1), trees.fresh.numbers().count(.recomputed));
}

test "pack: a pack of records of another identity is not read, and the newest pack is asked first" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = store_rules.Store.init(std.testing.io, try std.fs.path.join(a, &.{ work, store_rules.root_leaf }));
    const older = (try pack_rules.build(a, &.{.{ .kind = "k", .identity = @splat(1) }}, &.{.{ .key = @splat(5), .bytes = "old" }})).?;
    const newer = (try pack_rules.build(a, &.{.{ .kind = "k", .identity = @splat(1) }}, &.{.{ .key = @splat(5), .bytes = "new" }})).?;
    const foreign = (try pack_rules.build(a, &.{.{ .kind = "k", .identity = @splat(2) }}, &.{.{ .key = @splat(5), .bytes = "foreign" }})).?;
    try plant(a, &store, older, 10);
    try plant(a, &store, newer, 20);
    try plant(a, &store, foreign, 30);
    var records: local_rules.Records = .{};
    defer records.deinit(std.testing.allocator);
    records.open(std.testing.allocator, &store, &.{.{ .kind = "k", .identity = @splat(1) }});
    try std.testing.expect(records.isOpen());
    try std.testing.expectEqual(@as(usize, 2), records.count());
    try std.testing.expectEqualStrings("new", records.find(std.testing.io, 0, @splat(5)).?);
    try std.testing.expectEqualStrings("old", records.find(std.testing.io, 1, @splat(5)).?);
    try std.testing.expectEqual(@as(?[]const u8, null), records.find(std.testing.io, 0, @splat(6)));
    records.forget(std.testing.allocator, std.testing.io, @splat(5));
    try std.testing.expectEqual(@as(?[]const u8, null), records.find(std.testing.io, 0, @splat(5)));
}
