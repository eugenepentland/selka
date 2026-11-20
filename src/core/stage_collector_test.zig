//! The shared stage collector: which records a collection keeps (live roots, recent packs), what the size cap forces, the lease
//! scan and the collection interval. Each test runs on its own shared namespace under a temporary directory.
const std = @import("std");
const stage = @import("stage_store.zig");
const collector = @import("stage_collector.zig");
const leases = @import("stage_leases.zig");

const io = std.testing.io;
const scope = "lowering-receipt-v7";
const day_ns: i96 = 24 * 60 * 60 * 1_000_000_000;

/// Set `path`'s modification time to `nanoseconds`.
fn ageFile(path: []const u8, nanoseconds: i96) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    try file.setTimestamps(io, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = nanoseconds } } });
}

/// Set every pack of the namespace `shared` to `nanoseconds`.
fn agePacks(a: std.mem.Allocator, shared: []const u8, nanoseconds: i96) !void {
    var directory = try std.Io.Dir.cwd().openDir(io, shared, .{ .iterate = true });
    defer directory.close(io);
    var entries = directory.iterate();
    while (try entries.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".pack")) continue;
        try ageFile(try std.fs.path.join(a, &.{ shared, entry.name }), nanoseconds);
    }
}

/// The packs in namespace directory `shared`.
fn countPacks(shared: []const u8) !u32 {
    var directory = try std.Io.Dir.cwd().openDir(io, shared, .{ .iterate = true });
    defer directory.close(io);
    var found: u32 = 0;
    var entries = directory.iterate();
    while (try entries.next(io)) |entry| found += @intFromBool(entry.kind == .file and std.mem.endsWith(u8, entry.name, ".pack"));
    return found;
}

/// A temporary directory with work directories `one` and `two` and the shared root `shared`, and the namespace under it.
const Fixture = struct {
    gpa: std.mem.Allocator,
    directory: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init(gpa: std.mem.Allocator) Fixture {
        return .{ .gpa = gpa, .directory = std.testing.tmpDir(.{}), .arena = std.heap.ArenaAllocator.init(gpa) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.directory.cleanup();
    }

    fn path(self: *Fixture, name: []const u8) ![]const u8 {
        const root = try self.directory.dir.realPathFileAlloc(io, ".", self.arena.allocator());
        return std.fs.path.join(self.arena.allocator(), &.{ root, name });
    }

    /// The shared namespace directory (`stage-artifacts-v1` under `shared`).
    fn namespace(self: *Fixture) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ try self.path("shared"), stage.shared_leaf });
    }

    fn open(self: *Fixture, work: []const u8, publish: bool) !stage.Store {
        const cache = try self.path(work);
        try std.Io.Dir.cwd().createDirPath(io, cache);
        return stage.Store.initWithOptions(self.gpa, io, cache, .{ .shared = try self.path("shared"), .publish = publish });
    }
};

test "a collection keeps what a live root names and what is recent, and drops the rest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    const live = one.key(scope, &.{"live"});
    const dead = one.key(scope, &.{"dead"});
    const missing = one.key(scope, &.{"missing"});
    const stale = one.key(scope, &.{"stale"});
    try std.testing.expect(try one.save(live, "L"));
    try std.testing.expect(try one.save(dead, "D"));
    try std.testing.expect(try one.save(missing, "M"));
    try std.testing.expect(try one.save(stale, "S"));
    try std.testing.expect(try one.flush());
    const now = (try collector.clockNow(a, io, try fixture.namespace())).?;
    try agePacks(a, try fixture.namespace(), now - 20 * day_ns);
    const recent = one.key(scope, &.{"recent"});
    try std.testing.expect(try one.save(recent, "R"));
    try std.testing.expect(try one.flush());
    try std.Io.Dir.cwd().createDirPath(io, try fixture.path("stale-work"));
    collector.writeRoot(a, io, try fixture.namespace(), try fixture.path("one"), &.{live});
    collector.writeRoot(a, io, try fixture.namespace(), try fixture.path("gone"), &.{missing});
    collector.writeRoot(a, io, try fixture.namespace(), try fixture.path("stale-work"), &.{stale});
    const stale_root = try std.fs.path.join(a, &.{ try fixture.namespace(), collector.roots_leaf, try collector.rootFileName(a, try fixture.path("stale-work")) });
    try ageFile(stale_root, now - 20 * day_ns);
    const report = (try collector.collect(a, io, try fixture.namespace(), one.shared.?.state, collector.default_cap, now)).?;
    try std.testing.expect(report.prefixes >= 1);
    var two = try fixture.open("two", false);
    defer two.deinit();
    try expectLoads(std.testing.allocator, &two, "live", "L");
    try expectLoads(std.testing.allocator, &two, "recent", "R");
    try expectMissing(std.testing.allocator, &two, "dead");
    try expectMissing(std.testing.allocator, &two, "missing");
    try expectMissing(std.testing.allocator, &two, "stale");
}

/// The record named `name` in `store` (its key computed here, as a build computes it) loads with `payload`.
fn expectLoads(gpa: std.mem.Allocator, store: *stage.Store, name: []const u8, payload: []const u8) !void {
    const digest = store.key(scope, &.{name});
    const found = (try store.load(gpa, digest)).?;
    defer gpa.free(found);
    try std.testing.expectEqualStrings(payload, found);
}

/// No record named `name` loads from `store`.
fn expectMissing(gpa: std.mem.Allocator, store: *stage.Store, name: []const u8) !void {
    const digest = store.key(scope, &.{name});
    try std.testing.expect((try store.load(gpa, digest)) == null);
}

test "over the cap with only live and recent packs, a collection evicts nothing and reports the budget unmet" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    const kept = one.key(scope, &.{"kept"});
    try std.testing.expect(try one.save(kept, "K"));
    try std.testing.expect(try one.flush());
    const now = (try collector.clockNow(a, io, try fixture.namespace())).?;
    try agePacks(a, try fixture.namespace(), now - 20 * day_ns);
    collector.writeRoot(a, io, try fixture.namespace(), try fixture.path("one"), &.{kept});
    const report = (try collector.collect(a, io, try fixture.namespace(), one.shared.?.state, 1, now)).?;
    try std.testing.expect(report.unmet);
    try std.testing.expectEqual(@as(u64, 0), report.evicted);
    var two = try fixture.open("two", false);
    defer two.deinit();
    try expectLoads(std.testing.allocator, &two, "kept", "K");
}

test "F54 the namespace's cap is its policy file's, the default without one, and the default for a damaged one" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    const root = try fixture.namespace();
    try std.testing.expectEqual(collector.default_cap, collector.loadPolicy(a, io, root).max_bytes);
    try collector.savePolicy(a, io, root, .{ .max_bytes = 12345 });
    try std.testing.expectEqual(@as(u64, 12345), collector.loadPolicy(a, io, root).max_bytes);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ root, collector.policy_leaf }), .data = "max_bytes=lots\n" });
    try std.testing.expectEqual(collector.default_cap, collector.loadPolicy(a, io, root).max_bytes);
    try std.testing.expect(collector.default_cap <= 4 << 30);
}

test "F54 a preview names the packs a collection would evict and changes nothing, and gc --apply evicts them" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    const old = one.key(scope, &.{"old"});
    try std.testing.expect(try one.save(old, "O"));
    try std.testing.expect(try one.flush());
    const now = (try collector.clockNow(a, io, try fixture.namespace())).?;
    try agePacks(a, try fixture.namespace(), now - 20 * day_ns);
    const preview = (try collector.collectWith(a, io, try fixture.namespace(), one.shared.?.state, .{ .cap = 1, .now = now, .dry_run = true })).?;
    try std.testing.expect(preview.dry_run);
    try std.testing.expectEqual(@as(u64, 1), preview.evicted);
    try std.testing.expect(preview.bytes_after < preview.bytes_before);
    // The preview changed nothing: the pack is still there, and still as old as it was made.
    try std.testing.expectEqual(@as(u32, 1), try countPacks(try fixture.namespace()));
    // The command: a policy of one byte, then gc --apply through the store's maintenance entry.
    const configured = (try stage.Store.maintain(std.testing.allocator, io, try fixture.path("shared"), .{ .max_bytes = 1, .configure = true })).?;
    try std.testing.expectEqual(@as(u64, 1), configured.policy.max_bytes);
    const previewed = (try stage.Store.maintain(std.testing.allocator, io, try fixture.path("shared"), .{})).?;
    try std.testing.expect(previewed.report.?.dry_run);
    try std.testing.expectEqual(@as(u64, 1), previewed.policy.max_bytes);
    const applied = (try stage.Store.maintain(std.testing.allocator, io, try fixture.path("shared"), .{ .apply = true })).?;
    try std.testing.expect(!applied.report.?.dry_run);
    // The pack is older than every lease and names no live record: the collection compacts it away (or evicts it).
    try std.testing.expect(applied.report.?.bytes_after < applied.report.?.bytes_before);
    try std.testing.expectEqual(@as(u32, 0), try countPacks(try fixture.namespace()));
    try std.testing.expect((try stage.Store.maintain(std.testing.allocator, io, try fixture.path("no-such-root"), .{})) == null);
}

test "a stale lease is removed and a live one counts toward the epoch" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    try std.Io.Dir.cwd().createDirPath(io, try std.fs.path.join(a, &.{ try fixture.namespace(), leases.directory_leaf }));
    const stale_lease = try std.fs.path.join(a, &.{ try fixture.namespace(), leases.directory_leaf, "stale" });
    (try std.Io.Dir.cwd().createFile(io, stale_lease, .{})).close(io);
    const found = try leases.scan(io, try fixture.namespace(), a);
    try std.testing.expectEqual(@as(u64, 1), found.removed);
    try std.testing.expectEqual(@as(u64, 1), found.live);
    try std.testing.expect(found.oldest != null);
}

test "a collection runs at most once per interval" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var one = try fixture.open("one", true);
    defer one.deinit();
    const first = try collector.collectIfDue(a, io, try fixture.namespace(), one.shared.?.state, collector.default_cap);
    try std.testing.expect(first != null);
    const second = try collector.collectIfDue(a, io, try fixture.namespace(), one.shared.?.state, collector.default_cap);
    try std.testing.expect(second == null);
}

test "a lease registers under a usable namespace, and an allocation failure while registering is an out-of-memory error" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.Io.Dir.cwd().createDirPath(io, try fixture.namespace());
    const registered = (try leases.register(std.testing.allocator, io, try fixture.namespace())).?;
    defer registered.release(io, std.testing.allocator);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, leases.register(failing.allocator(), io, try fixture.namespace()));
}
