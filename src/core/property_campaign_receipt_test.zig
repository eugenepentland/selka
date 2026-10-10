//! Completed-prefix integrity, interruption, concurrent publication and allocation cleanup.
const std = @import("std");
const receipt = @import("property_campaign_receipt.zig");
const contract = @import("property_campaign_contract.zig");

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    temporary: std.testing.TmpDir,
    store: receipt.Store,

    fn init(backing: std.mem.Allocator) !Fixture {
        return initWithAllocator(backing);
    }

    fn initWithAllocator(backing: std.mem.Allocator) !Fixture {
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
        return .{ .arena = arena, .temporary = temporary, .store = .{ .arena = backing, .io = std.testing.io, .root = root } };
    }

    fn deinit(self: *Fixture) void {
        self.temporary.cleanup();
        self.arena.deinit();
    }
};
const campaign: receipt.Digest = @splat(41);
const clause_message = "positive";
const first: contract.Progress = .{ .next_ordinal = 3, .passed = 2, .discarded = 1, .clauses = &.{.{ .message = clause_message, .count = 1 }} };
const second: contract.Progress = .{ .next_ordinal = 6, .passed = 4, .discarded = 2, .clauses = &.{.{ .message = clause_message, .count = 2 }} };

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix resumes interrupted chunks and larger budgets with exact tallies" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const store = fixture.store;
    try std.testing.expect(try store.load(campaign, 2) == null);
    try std.testing.expect(try store.commit(campaign, null, first));
    const path = try store.artifactPath(fixture.arena.allocator(), campaign);
    const partial = try std.fmt.allocPrint(fixture.arena.allocator(), "{s}.partial", .{path});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = partial, .data = "unanswered interrupted chunk" });
    const loaded = (try store.load(campaign, 4)).?;
    defer receipt.deinitProgress(store.arena, loaded);
    try std.testing.expectEqual(@as(u64, 3), loaded.next_ordinal);
    try std.testing.expectEqual(@as(u64, 2), loaded.passed);
    try std.testing.expectEqualStrings(clause_message, loaded.clauses[0].message);
    try std.testing.expectEqual(@as(u64, 1), loaded.clauses[0].count);
    try std.testing.expect(try store.load(campaign, 1) == null);
    try std.testing.expect(try store.commit(campaign, loaded, second));
    const extended = (try store.load(campaign, 4)).?;
    defer receipt.deinitProgress(store.arena, extended);
    try std.testing.expectEqual(@as(u64, 6), extended.next_ordinal);
    try std.testing.expectEqual(@as(u64, 4), extended.passed);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix stale concurrent writer cannot overwrite or regress progress" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const writer = fixture.store;
    const concurrent = fixture.store;
    try std.testing.expect(try writer.commit(campaign, null, first));
    const observed = (try concurrent.load(campaign, 4)).?;
    defer receipt.deinitProgress(concurrent.arena, observed);
    try std.testing.expect(try writer.commit(campaign, first, second));
    const conflicting: contract.Progress = .{ .next_ordinal = 7, .passed = 5, .discarded = 2, .clauses = second.clauses };
    try std.testing.expect(!try concurrent.commit(campaign, observed, conflicting));
    try std.testing.expect(!try concurrent.commit(campaign, null, first));
    try std.testing.expect(!try writer.commit(campaign, second, first));
    const intact = (try writer.load(campaign, 8)).?;
    defer receipt.deinitProgress(writer.arena, intact);
    try std.testing.expectEqual(second.next_ordinal, intact.next_ordinal);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix refuses gaps incoherent clauses and changed historical ordering" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const store = fixture.store;
    var gap = first;
    gap.next_ordinal += 1;
    try std.testing.expect(!try store.commit(campaign, null, gap));
    var incorrect = first;
    incorrect.clauses = &.{.{ .message = clause_message, .count = 2 }};
    try std.testing.expect(!try store.commit(campaign, null, incorrect));
    var duplicate = second;
    duplicate.clauses = &.{ .{ .message = clause_message, .count = 1 }, .{ .message = clause_message, .count = 1 } };
    try std.testing.expect(!try store.commit(campaign, null, duplicate));
    try std.testing.expect(try store.commit(campaign, null, first));
    var reordered = second;
    reordered.clauses = &.{ .{ .message = "new", .count = 1 }, .{ .message = clause_message, .count = 1 } };
    try std.testing.expect(!try store.commit(campaign, first, reordered));
    try std.testing.expect(!try store.commit(campaign, first, first));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix corruption missing foreign and truncated records miss" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const store = fixture.store;
    try std.testing.expect(try store.commit(campaign, null, first));
    const path = try store.artifactPath(a, campaign);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
    const foreign: receipt.Digest = @splat(42);
    const foreign_path = try store.artifactPath(a, foreign);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = foreign_path, .data = bytes });
    try std.testing.expect(try store.load(foreign, 4) == null);
    bytes[bytes.len - 1] ^= 1;
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = bytes });
    try std.testing.expect(try store.load(campaign, 4) == null);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "truncated" });
    try std.testing.expect(try store.load(campaign, 4) == null);
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    try std.testing.expect(try store.load(campaign, 4) == null);
}

fn rewriteField(io: std.Io, path: []const u8, a: std.mem.Allocator, field_offset: usize, value: u64) !void {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .unlimited);
    const header = "core-property-prefix-v1\n".len;
    const payload = bytes[header + 32 ..];
    std.mem.writeInt(u64, payload[field_offset..][0..8], value, .little);
    var hash: receipt.Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &hash, .{});
    @memcpy(bytes[header..][0..32], &hash);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix checksummed malformed counter and oversized ordinal arithmetic miss" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const store = fixture.store;
    try std.testing.expect(try store.commit(campaign, null, first));
    const path = try store.artifactPath(fixture.arena.allocator(), campaign);
    try rewriteField(store.io, path, fixture.arena.allocator(), 32, 99);
    try std.testing.expect(try store.load(campaign, 4) == null);
    try std.testing.expect(try store.commit(campaign, null, first));
    try rewriteField(store.io, path, fixture.arena.allocator(), 40, std.math.maxInt(u64));
    try std.testing.expect(try store.load(campaign, std.math.maxInt(u64)) == null);
}

fn loadAllocationFailure(a: std.mem.Allocator, store: receipt.Store) !void {
    var failing = store;
    failing.arena = a;
    const progress = (try failing.load(campaign, 4)).?;
    defer receipt.deinitProgress(a, progress);
    try std.testing.expectEqual(first.next_ordinal, progress.next_ordinal);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix clone and load allocation failures clean up owned clauses" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.testing.expect(try fixture.store.commit(campaign, null, first));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, loadAllocationFailure, .{fixture.store});
}

fn commitAllocationFailure(a: std.mem.Allocator, store: receipt.Store, path: []const u8, baseline: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(store.io, .{ .sub_path = path, .data = baseline });
    var failing = store;
    failing.arena = a;
    const published = failing.commit(campaign, first, second) catch |err| {
        const preserved = (try store.load(campaign, 4)).?;
        defer receipt.deinitProgress(store.arena, preserved);
        try std.testing.expectEqual(first.next_ordinal, preserved.next_ordinal);
        return err;
    };
    try std.testing.expect(published);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix commit allocation failures preserve prior completed publication" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const store = fixture.store;
    try std.testing.expect(try store.commit(campaign, null, first));
    const path = try store.artifactPath(fixture.arena.allocator(), campaign);
    const baseline = try std.Io.Dir.cwd().readFileAlloc(store.io, path, fixture.arena.allocator(), .unlimited);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, commitAllocationFailure, .{ store, path, baseline });
    const loaded = (try store.load(campaign, 4)).?;
    defer receipt.deinitProgress(store.arena, loaded);
    try std.testing.expectEqual(first.next_ordinal, loaded.next_ordinal);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix smaller budgets cannot reuse past their discard exhaustion limit" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const store = fixture.store;
    const discarded: contract.Progress = .{
        .next_ordinal = 27,
        .passed = 2,
        .discarded = 25,
        .clauses = &.{.{ .message = "rare", .count = 25 }},
    };
    try std.testing.expect(try store.commit(campaign, null, discarded));
    try std.testing.expect(try store.load(campaign, 2) == null);
    const loaded = (try store.load(campaign, 3)).?;
    defer receipt.deinitProgress(store.arena, loaded);
    try std.testing.expectEqual(@as(u64, 25), loaded.discarded);
    const huge: contract.Progress = .{ .next_ordinal = contract.maximum_ordinal + 1, .passed = contract.maximum_ordinal + 1 };
    try std.testing.expect(!try store.commit(campaign, null, huge));
    const overlong: [4097]u8 = @splat('x');
    var oversized = first;
    oversized.clauses = &.{.{ .message = &overlong, .count = 1 }};
    try std.testing.expect(!try store.commit(campaign, null, oversized));
}

const Gate = struct {
    ready: std.atomic.Value(u32) = .init(0),
    begin: std.atomic.Value(bool) = .init(false),
};
const Publisher = struct {
    store: receipt.Store,
    progress: contract.Progress,
    gate: *Gate,
    published: bool = false,
    failure: ?anyerror = null,

    fn run(self: *Publisher) void {
        _ = self.gate.ready.fetchAdd(1, .release);
        while (!self.gate.begin.load(.acquire)) yieldThread();
        self.published = self.store.commit(campaign, null, self.progress) catch |err| {
            self.failure = err;
            return;
        };
    }
};

fn concurrentPublication(store: receipt.Store) !void {
    var gate: Gate = .{};
    var left: Publisher = .{ .store = store, .progress = first, .gate = &gate };
    var right: Publisher = .{ .store = store, .progress = second, .gate = &gate };
    const left_thread = try std.Thread.spawn(.{}, Publisher.run, .{&left});
    var left_joined = false;
    errdefer {
        if (!left_joined) {
            gate.begin.store(true, .release);
            left_thread.join();
        }
    }
    const right_thread = try std.Thread.spawn(.{}, Publisher.run, .{&right});
    while (gate.ready.load(.acquire) != 2) yieldThread();
    gate.begin.store(true, .release);
    left_thread.join();
    right_thread.join();
    left_joined = true;
    if (left.failure) |err| return err;
    if (right.failure) |err| return err;
    try std.testing.expect(left.published != right.published);
    const loaded = (try store.load(campaign, 4)).?;
    defer receipt.deinitProgress(store.arena, loaded);
    const winner = if (left.published) first else second;
    try std.testing.expectEqual(winner.next_ordinal, loaded.next_ordinal);
    try std.testing.expectEqual(winner.passed, loaded.passed);
    try std.testing.expectEqual(winner.discarded, loaded.discarded);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign prefix concurrentPublication threads serialize independent file descriptor commits" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try concurrentPublication(fixture.store);
    try std.testing.expect(try fixture.store.load(@splat(99), 4) == null);
}

fn fixtureInitAllocationFailure(a: std.mem.Allocator) !void {
    var fixture = try Fixture.initWithAllocator(a);
    defer fixture.deinit();
    try std.testing.expect(fixture.store.root.len != 0);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property campaign Fixture initWithAllocator allocation failures clean up scratch directory and path" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fixtureInitAllocationFailure, .{});
    var baseline = try Fixture.init(std.testing.allocator);
    defer baseline.deinit();
    try std.testing.expect(baseline.store.root.len != 0);
}

fn yieldThread() void {
    std.Thread.yield() catch return;
}
