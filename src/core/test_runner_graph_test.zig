//! Retained graph authority is checked against independent complete receipt keys.
const std = @import("std");
const graph = @import("test_runner_graph.zig");
const keys = @import("test_runner_identity.zig");
const stage = @import("stage_store.zig");
const engine_run = @import("test_runner_engine.zig");
const test_records = @import("test_records.zig");
const Ledger = test_records.Ledger;
const adapter = @import("selka").cache_plan_adapter;
const codec = @import("selka").persist_codec;
const Digest = stage.Digest;

const Fixture = struct { shared: keys.Shared, identities: []const ?Digest, tests: []const keys.Test };
const Trial = struct { prepared: graph.Prepared, stats: graph.Statistics, reused: []const bool, derived: []const Digest };
const Manifest = struct { nodes: []const Digest, tests: []const Digest, indexes: []const Digest, topology: Digest, node_count: u32, test_count: u32 };
const Index = struct { group: u32, reverse: []const u32 };
const Publication = struct { parent: std.mem.Allocator, prepared: graph.Prepared, indexes: adapter.incremental_protocol.Indexes };

fn fixture(a: std.mem.Allocator, shared: keys.Shared, identities: []const ?Digest, roots: []const []const u32) !Fixture {
    const tests = try a.alloc(keys.Test, roots.len);
    for (tests, roots, 0..) |*test_value, row, index| test_value.* = .{ .base = @splat(1), .name = if (index == 0) "left" else "right", .source_path = "graph.selka", .entry = @splat(2), .schema = null, .roots = row };
    return .{ .shared = shared, .identities = identities, .tests = tests };
}

fn ordinary(a: std.mem.Allocator) !Fixture {
    return fixture(
        a,
        .{ .digests = &.{ @splat(10), @splat(11), @splat(12), @splat(13) }, .callees = &.{ &.{ 1, 3 }, &.{}, &.{3}, &.{} } },
        &.{ @as(Digest, @splat(100)), @as(Digest, @splat(101)), @as(Digest, @splat(102)), @as(Digest, @splat(103)) },
        &.{ &.{0}, &.{2} },
    );
}

fn derive(a: std.mem.Allocator, ledger: Ledger, input: Fixture) !Trial {
    var stats: graph.Statistics = .{};
    const prepared = try graph.prepare(a, ledger, input.shared, input.identities, input.tests, &stats);
    const roots = try a.alloc([]const u32, input.tests.len);
    for (roots, input.tests) |*row, test_value| row.* = test_value.roots;
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const binding: adapter.Bound = .{ .identity = @splat(3), .mode = .reference, .io = std.testing.io, .environ = &environment, .directory = null, .artifact = null };
    var result = try binding.incremental(a, prepared.request(input.shared, roots));
    defer result.deinit();
    const derived = try a.alloc(Digest, input.tests.len);
    for (input.tests, derived, result.batches, result.reused, prepared.keys) |test_value, *key, batch, reused, cached| {
        key.* = if (reused) cached.? else try keys.plannedKey(input.shared, test_value, batch);
        try std.testing.expectEqual(try keys.key(input.shared, a, test_value), key.*);
    }
    for (prepared.keys, derived) |*cached, key| cached.* = key;
    try prepared.publish(a, ledger, result.indexes, &stats);
    return .{ .prepared = prepared, .stats = stats, .reused = try a.dupe(bool, result.reused), .derived = derived };
}

fn changedBody(a: std.mem.Allocator, original: Fixture, node: usize) !Fixture {
    const digests = try a.dupe(Digest, original.shared.digests);
    digests[node] = @splat(42);
    return .{ .shared = .{ .digests = digests, .callees = original.shared.callees }, .identities = original.identities, .tests = original.tests };
}

fn replaceIndexes(a: std.mem.Allocator, ledger: Ledger, slot: Digest, rows: []const Index) !void {
    var manifest = (try ledger.records.loadValue(a, a, .graph, &slot, Manifest)).?;
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    try writer.write([]const Index, rows);
    const shard = ledger.store.key("test-graph-indexes-v1", &.{writer.bytes.items});
    _ = ledger.records.save(.graph, &shard, writer.bytes.items, true);
    manifest.indexes = try a.dupe(Digest, &.{shard});
    try ledger.records.storeValue(a, .{ .which = .graph, .key = &slot, .replace = true }, Manifest, manifest);
}

fn publicationFailure(backing: std.mem.Allocator, input: Publication) !void {
    // Faulted reads may change a store's retained cache state. Each injection
    // must start with the same published records and its own store instance.
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var setup = std.heap.ArenaAllocator.init(input.parent);
    defer setup.deinit();
    const a = setup.allocator();
    var store = try stage.Store.init(input.parent, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(input.parent);
    defer bench.deinit();
    const records = engine_run.planningOf(bench.state);
    var seeded: graph.Statistics = .{};
    try input.prepared.publish(a, .{ .store = &store, .records = records }, input.indexes, &seeded);
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    var constrained = store;
    constrained.backing = backing;
    var stats: graph.Statistics = .{};
    try input.prepared.publish(arena.allocator(), .{ .store = &constrained, .records = records }, input.indexes, &stats);
}

// spec: NEW-CORE-TEST-GRAPH-1
test "graph metadata cold and noop derive complete keys and reuse immutable shards" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const warm = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, cold.reused);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, warm.reused);
    try std.testing.expectEqual(@as(usize, 4), cold.stats.changed_nodes);
    try std.testing.expectEqual(@as(usize, 3), cold.stats.shards_written);
    try std.testing.expectEqual(@as(usize, 4), warm.stats.nodes_read);
    try std.testing.expectEqual(@as(usize, 4), warm.stats.nodes_unchanged);
    try std.testing.expectEqual(@as(usize, 0), warm.stats.shards_written);
    try std.testing.expectEqual(@as(usize, 0), warm.prepared.changed.len);
    try std.testing.expect(warm.prepared.prior != null);
    try std.testing.expectEqualSlices(Digest, cold.derived, warm.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata private and shared edits invalidate precisely their reverse closures" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const private = try derive(a, ledger, try changedBody(a, input, 1));
    const reverted = try derive(a, ledger, input);
    const shared = try derive(a, ledger, try changedBody(a, input, 3));
    try std.testing.expectEqualSlices(bool, &.{ false, true }, private.reused);
    try std.testing.expectEqualSlices(u32, &.{1}, private.prepared.changed);
    try std.testing.expectEqual(@as(usize, 2), private.stats.candidate_tests);
    try std.testing.expectEqual(cold.derived[1], private.derived[1]);
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &private.derived[0]));
    try std.testing.expectEqualSlices(bool, &.{ false, true }, reverted.reused);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, shared.reused);
    try std.testing.expectEqualSlices(u32, &.{3}, shared.prepared.changed);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata preserves logical identities and keys across complete numeric ID remapping" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const cold = try derive(a, ledger, try ordinary(a));
    const remapped = try fixture(
        a,
        .{ .digests = &.{ @splat(13), @splat(12), @splat(11), @splat(10) }, .callees = &.{ &.{}, &.{0}, &.{}, &.{ 2, 0 } } },
        &.{ @as(Digest, @splat(103)), @as(Digest, @splat(102)), @as(Digest, @splat(101)), @as(Digest, @splat(100)) },
        &.{ &.{3}, &.{1} },
    );
    const warm = try derive(a, ledger, remapped);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, warm.reused);
    try std.testing.expectEqual(@as(usize, 4), warm.stats.nodes_unchanged);
    try std.testing.expectEqual(@as(usize, 0), warm.prepared.changed.len);
    try std.testing.expect(warm.prepared.prior == null);
    try std.testing.expectEqualSlices(Digest, cold.derived, warm.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata retains repeated ordered roots and equal digest multiplicity" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try fixture(
        a,
        .{ .digests = &.{ @splat(10), @splat(11), @splat(11) }, .callees = &.{ &.{ 1, 2 }, &.{}, &.{} } },
        &.{ @as(Digest, @splat(100)), @as(Digest, @splat(101)), @as(Digest, @splat(102)) },
        &.{ &.{ 0, 0 }, &.{0} },
    );
    const cold = try derive(a, ledger, input);
    const warm = try derive(a, ledger, input);
    const private = try derive(a, ledger, try changedBody(a, input, 2));
    try std.testing.expectEqualSlices(bool, &.{ true, true }, warm.reused);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, private.reused);
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &cold.derived[1]));
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &private.derived[0]));
    try std.testing.expectEqual(@as(usize, 2), private.stats.candidate_tests);
    var single_root = input.tests[0];
    single_root.roots = &.{0};
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &try keys.key(input.shared, a, single_root)));
    const one_equal_body: keys.Shared = .{ .digests = input.shared.digests, .callees = &.{ &.{1}, &.{}, &.{} } };
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &try keys.key(one_equal_body, a, input.tests[0])));
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata removed and replaced nodes invalidate their surviving callers" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const removed = try fixture(a, .{ .digests = &.{ @splat(10), @splat(12), @splat(13) }, .callees = &.{ &.{2}, &.{2}, &.{} } }, &.{ @as(Digest, @splat(100)), @as(Digest, @splat(102)), @as(Digest, @splat(103)) }, &.{ &.{0}, &.{1} });
    const shrunk = try derive(a, ledger, removed);
    _ = try derive(a, ledger, input);
    const replacement_ids = try a.dupe(?Digest, input.identities);
    replacement_ids[1] = @as(Digest, @splat(199));
    const replaced = try derive(a, ledger, .{ .shared = input.shared, .identities = replacement_ids, .tests = input.tests });
    try std.testing.expectEqualSlices(bool, &.{ false, true }, shrunk.reused);
    try std.testing.expectEqualSlices(u32, &.{0}, shrunk.prepared.changed);
    try std.testing.expect(!std.mem.eql(u8, &cold.derived[0], &shrunk.derived[0]));
    try std.testing.expectEqualSlices(bool, &.{ false, true }, replaced.reused);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, replaced.prepared.changed);
    try std.testing.expectEqualSlices(Digest, cold.derived, replaced.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata missing coherent snapshot shard discards all retained key candidates" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    var manifest = (try ledger.records.loadValue(a, a, .graph, &cold.prepared.slot, Manifest)).?;
    manifest.indexes = &.{@splat(255)};
    try ledger.records.storeValue(a, .{ .which = .graph, .key = &cold.prepared.slot, .replace = true }, Manifest, manifest);
    const recovered = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, recovered.reused);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqual(@as(usize, 4), recovered.stats.changed_nodes);
    try std.testing.expect(recovered.prepared.prior == null);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata loadChunks corrupted shard payload loses authority despite a valid storage envelope" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const manifest = (try ledger.records.loadValue(a, a, .graph, &cold.prepared.slot, Manifest)).?;
    try std.testing.expect(ledger.records.save(.graph, &manifest.tests[0], "invalid graph shard", true));
    const recovered = try derive(a, ledger, input);
    const repaired = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, recovered.reused);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqual(@as(usize, 4), recovered.stats.changed_nodes);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, repaired.reused);
    try std.testing.expectEqual(@as(usize, 0), repaired.stats.shards_written);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata loadChunks malformed canonical schema discards all prior authority" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    var manifest = (try ledger.records.loadValue(a, a, .graph, &cold.prepared.slot, Manifest)).?;
    const malformed = "\x01\x00";
    const shard = store.key("test-graph-tests-v1", &.{malformed});
    try std.testing.expect(ledger.records.save(.graph, &shard, malformed, true));
    manifest.tests = &.{shard};
    try ledger.records.storeValue(a, .{ .which = .graph, .key = &cold.prepared.slot, .replace = true }, Manifest, manifest);
    const recovered = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, recovered.reused);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata saveChunks frees every earlier publication collection on OutOfMemory" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    _ = try derive(a, ledger, input);
    const warm = try derive(a, ledger, input);
    var constrained = store;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    constrained.backing = failing.allocator();
    var stats: graph.Statistics = .{};
    try std.testing.expectError(error.OutOfMemory, warm.prepared.publish(a, .{ .store = &constrained, .records = ledger.records }, warm.prepared.prior.?, &stats));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    try checkPublicationFailures(std.testing.allocator, .{ .parent = std.testing.allocator, .prepared = warm.prepared, .indexes = warm.prepared.prior.? });
}

/// Fail each allocation of `publicationFailure` in turn, over `child`, and expect a clean OutOfMemory
/// every time. `checkAllAllocationFailures` needs every run to make the same allocations, so the
/// allocator it fails never lets an allocation grow in place: a growth then always allocates, copies
/// and frees, whatever `child` would have done. The testing allocator grows an allocation in place
/// only when it is the newest of its bucket and the bucket has room, and it never reuses a freed
/// slot, so each run starts at a different place in its bucket. One run then relocated a writer's
/// buffer where the run that counted the allocations had grown it in place, the counts differed,
/// and the check failed (`NondeterministicMemoryUsage`) at some lengths of the store's directory
/// path and not at others.
fn checkPublicationFailures(child: std.mem.Allocator, input: Publication) !void {
    var stable = std.testing.FailingAllocator.init(child, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(stable.allocator(), publicationFailure, .{input});
}

/// A backing allocator that refuses its first two growths and grants every later one, by
/// relocating the allocation itself, so the run that counts a scenario's allocations makes more of
/// them than a later run does. The testing allocator behaves so as the place in its current bucket
/// moves from run to run.
const LateGrowth = struct {
    child: std.mem.Allocator,
    attempts: usize = 0,

    fn allocator(self: *LateGrowth) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *LateGrowth = @ptrCast(@alignCast(ctx));
        return self.child.rawAlloc(len, alignment, ra);
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *LateGrowth = @ptrCast(@alignCast(ctx));
        self.attempts += 1;
        if (self.attempts <= 2) return null;
        const grown = self.child.rawAlloc(new_len, alignment, ra) orelse return null;
        const kept = @min(memory.len, new_len);
        @memcpy(grown[0..kept], memory[0..kept]);
        self.child.rawFree(memory, alignment, ra);
        return grown;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *LateGrowth = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ra);
    }
};

/// Check the failures of a warm publication, over `child`, in a store `name_len` characters below a
/// temporary directory; `gpa` holds the store and the setup.
fn checkPublicationFailuresBelow(gpa: std.mem.Allocator, child: std.mem.Allocator, name_len: usize) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const name = try a.alloc(u8, name_len);
    @memset(name, 'd');
    try directory.dir.createDirPath(std.testing.io, name);
    var nested = try directory.dir.openDir(std.testing.io, name, .{});
    defer nested.close(std.testing.io);
    var store = try stage.Store.init(gpa, std.testing.io, try nested.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(gpa);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    _ = try derive(a, ledger, input);
    const warm = try derive(a, ledger, input);
    try checkPublicationFailures(child, .{ .parent = gpa, .prepared = warm.prepared, .indexes = warm.prepared.prior.? });
}

/// Check the failures of a warm publication under directory names of 1, 1 + `step`, ... up to 250
/// characters, the longest a path component allows; return how many lengths ran.
fn checkPublicationFailuresAtEveryLength(gpa: std.mem.Allocator, step: usize) !usize {
    var ran: usize = 0;
    var length: usize = 1;
    while (length <= 250) : (length += step) {
        try checkPublicationFailuresBelow(gpa, gpa, length);
        ran += 1;
    }
    return ran;
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata publication failures are the same whatever the length of the store's directory path" {
    // Before the failed allocator stopped depending on heap layout, 114 of the lengths 1 to 250 failed in a 66-character worktree.
    try std.testing.expectEqual(@as(usize, 10), try checkPublicationFailuresAtEveryLength(std.testing.allocator, 25));
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata publication failures do not depend on whether the backing grows an allocation in place" {
    var late: LateGrowth = .{ .child = std.testing.allocator };
    try checkPublicationFailuresBelow(std.testing.allocator, late.allocator(), 1);
    // The checked allocator turned every growth into an allocation, so none reached the backing.
    try std.testing.expectEqual(@as(usize, 0), late.attempts);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata checksum valid incomplete reverse indexes discard the entire generation" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const invalid: []const Index = &.{ .{ .group = 0, .reverse = &.{} }, .{ .group = 1, .reverse = &.{0} }, .{ .group = 2, .reverse = &.{} }, .{ .group = 3, .reverse = &.{0} } };
    try replaceIndexes(a, ledger, cold.prepared.slot, invalid);
    const recovered = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, recovered.reused);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqual(@as(usize, 4), recovered.stats.changed_nodes);
    try std.testing.expect(recovered.prepared.prior == null);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata checksum valid noncanonical group labels discard the entire generation" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const cold = try derive(a, ledger, input);
    const invalid: []const Index = &.{ .{ .group = 3, .reverse = &.{} }, .{ .group = 1, .reverse = &.{0} }, .{ .group = 2, .reverse = &.{} }, .{ .group = 3, .reverse = &.{ 0, 2 } } };
    try replaceIndexes(a, ledger, cold.prepared.slot, invalid);
    const recovered = try derive(a, ledger, input);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, recovered.reused);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqual(@as(usize, 4), recovered.stats.changed_nodes);
    try std.testing.expect(recovered.prepared.prior == null);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata saveChunks keys and snapshot reuse survive alternate store compression" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const records = engine_run.planningOf(bench.state);
    var compressed = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    const input = try ordinary(a);
    const cold = try derive(a, .{ .store = &compressed, .records = records }, input);
    try std.testing.expect(try compressed.flush());
    compressed.deinit();
    var raw = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .compression = .none });
    defer raw.deinit();
    const warm = try derive(a, .{ .store = &raw, .records = records }, input);
    const private = try derive(a, .{ .store = &raw, .records = records }, try changedBody(a, input, 1));
    try std.testing.expectEqualSlices(bool, &.{ true, true }, warm.reused);
    try std.testing.expectEqualSlices(Digest, cold.derived, warm.derived);
    try std.testing.expectEqual(@as(usize, 0), warm.stats.shards_written);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, private.reused);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata recursive edge changes invalidate cycles while retaining unrelated tests" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const ordinary_input = try ordinary(a);
    const cycle: Fixture = .{ .shared = .{ .digests = ordinary_input.shared.digests, .callees = &.{ &.{1}, &.{0}, &.{3}, &.{} } }, .identities = ordinary_input.identities, .tests = ordinary_input.tests };
    const cold = try derive(a, ledger, cycle);
    const warm = try derive(a, ledger, cycle);
    const private = try derive(a, ledger, try changedBody(a, cycle, 1));
    _ = try derive(a, ledger, cycle);
    const split: Fixture = .{ .shared = .{ .digests = cycle.shared.digests, .callees = &.{ &.{1}, &.{}, &.{3}, &.{} } }, .identities = cycle.identities, .tests = cycle.tests };
    const changed_edge = try derive(a, ledger, split);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, warm.reused);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 2, 3 }, warm.prepared.prior.?.groups);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, private.reused);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, changed_edge.reused);
    try std.testing.expectEqualSlices(u32, &.{1}, changed_edge.prepared.changed);
    try std.testing.expect(changed_edge.prepared.prior == null);
    try std.testing.expectEqualSlices(Digest, cold.derived, changed_edge.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata validates every shard in a multi chunk snapshot before reusing keys" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const digests = try a.alloc(Digest, 259);
    const identities = try a.alloc(?Digest, digests.len);
    const callees = try a.alloc([]const u32, digests.len);
    for (digests, identities, callees, 0..) |*digest, *identity, *edges, index| {
        var distinct: Digest = @splat(20);
        std.mem.writeInt(u64, distinct[0..8], @intCast(index), .little);
        digest.* = @splat(10);
        identity.* = distinct;
        edges.* = &.{};
    }
    callees[0] = &.{257};
    callees[257] = &.{258};
    const input = try fixture(a, .{ .digests = digests, .callees = callees }, identities, &.{&.{0}});
    const cold = try derive(a, ledger, input);
    const warm = try derive(a, ledger, input);
    var manifest = (try ledger.records.loadValue(a, a, .graph, &cold.prepared.slot, Manifest)).?;
    const shards = try a.dupe(Digest, manifest.nodes);
    shards[1] = @splat(255);
    manifest.nodes = shards;
    try ledger.records.storeValue(a, .{ .which = .graph, .key = &cold.prepared.slot, .replace = true }, Manifest, manifest);
    const recovered = try derive(a, ledger, input);
    try std.testing.expectEqual(@as(usize, 5), cold.stats.shards_written);
    try std.testing.expectEqual(@as(usize, 5), warm.stats.shards_read);
    try std.testing.expectEqualSlices(bool, &.{true}, warm.reused);
    try std.testing.expectEqualSlices(bool, &.{false}, recovered.reused);
    try std.testing.expectEqual(@as(usize, 259), recovered.stats.changed_nodes);
    try std.testing.expectEqual(@as(usize, 0), recovered.stats.candidate_tests);
    try std.testing.expectEqualSlices(Digest, cold.derived, recovered.derived);
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata rejects ambiguous identities and incomplete current adjacency" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    var stats: graph.Statistics = .{};
    const duplicate_ids = try a.dupe(?Digest, input.identities);
    duplicate_ids[1] = duplicate_ids[0];
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, ledger, input.shared, duplicate_ids, input.tests, &stats));
    const missing_id = try a.dupe(?Digest, input.identities);
    missing_id[1] = null;
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, ledger, input.shared, missing_id, input.tests, &stats));
    const duplicate_edges: keys.Shared = .{ .digests = input.shared.digests, .callees = &.{ &.{ 1, 1 }, &.{}, &.{3}, &.{} } };
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, ledger, duplicate_edges, input.identities, input.tests, &stats));
    const absent_edge: keys.Shared = .{ .digests = input.shared.digests, .callees = &.{ &.{4}, &.{}, &.{3}, &.{} } };
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, ledger, absent_edge, input.identities, input.tests, &stats));
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata shares one head per entry: a base change reuses nodes and indexes and serves no key from another base" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const ledger: Ledger = .{ .store = &store, .records = engine_run.planningOf(bench.state) };
    const input = try ordinary(a);
    const first = try derive(a, ledger, input);
    const moved_tests = try a.alloc(keys.Test, input.tests.len);
    for (moved_tests, input.tests) |*test_value, original| {
        test_value.* = original;
        test_value.base = @splat(9);
    }
    var rebased = input;
    rebased.tests = moved_tests;
    const moved = try derive(a, ledger, rebased);
    try std.testing.expectEqualSlices(u8, &first.prepared.slot, &moved.prepared.slot);
    try std.testing.expectEqual(@as(usize, 0), moved.stats.candidate_tests);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, moved.reused);
    try std.testing.expectEqual(@as(usize, 4), moved.stats.nodes_unchanged);
    try std.testing.expectEqual(@as(usize, 0), moved.prepared.changed.len);
    try std.testing.expect(moved.prepared.prior != null);
    try std.testing.expect(!std.mem.eql(u8, &first.derived[0], &moved.derived[0]));
}

// spec-case: NEW-CORE-TEST-GRAPH-1
test "graph metadata reads the previous generation from a store opened after a whole-compiler identity change" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var first_store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer first_store.deinit();
    const input = try ordinary(a);
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const cold = try derive(a, .{ .store = &first_store, .records = engine_run.planningOf(bench.state) }, input);
    const scopes = @import("stage_scopes.zig");
    var changed = stage.defaultStageDigests();
    changed[@backingInt(scopes.Stage.whole)][0] ^= 0xff;
    var second_store = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .identities = changed });
    defer second_store.deinit();
    const warm = try derive(a, .{ .store = &second_store, .records = engine_run.planningOf(bench.state) }, input);
    try std.testing.expectEqual(@as(usize, 4), warm.stats.nodes_read);
    try std.testing.expectEqual(@as(usize, 4), warm.stats.nodes_unchanged);
    try std.testing.expectEqualSlices(Digest, cold.derived[0..], warm.derived[0..]);
}
