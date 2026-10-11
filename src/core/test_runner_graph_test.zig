//! Retained graph authority is checked against independent complete receipt keys.
const std = @import("std");
const graph = @import("test_runner_graph.zig");
const keys = @import("test_runner_identity.zig");
const stage = @import("stage_store.zig");
const adapter = @import("mylang").cache_plan_adapter;
const codec = @import("mylang").persist_codec;
const Digest = stage.Digest;

const Fixture = struct { shared: keys.Shared, identities: []const ?Digest, tests: []const keys.Test };
const Trial = struct { prepared: graph.Prepared, stats: graph.Statistics, reused: []const bool, derived: []const Digest };
const Manifest = struct { nodes: []const Digest, tests: []const Digest, indexes: []const Digest, topology: Digest, node_count: u32, test_count: u32 };
const Index = struct { group: u32, reverse: []const u32 };
const Publication = struct { parent: std.mem.Allocator, prepared: graph.Prepared, indexes: adapter.incremental_protocol.Indexes };

fn fixture(a: std.mem.Allocator, shared: keys.Shared, identities: []const ?Digest, roots: []const []const u32) !Fixture {
    const tests = try a.alloc(keys.Test, roots.len);
    for (tests, roots, 0..) |*test_value, row, index| test_value.* = .{ .base = @splat(1), .name = if (index == 0) "left" else "right", .source_path = "graph.my", .entry = @splat(2), .schema = null, .roots = row };
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

fn derive(a: std.mem.Allocator, store: *const stage.Store, input: Fixture) !Trial {
    var stats: graph.Statistics = .{};
    const prepared = try graph.prepare(a, store, input.shared, input.identities, input.tests, &stats);
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
    try prepared.publish(a, store, result.indexes, &stats);
    return .{ .prepared = prepared, .stats = stats, .reused = try a.dupe(bool, result.reused), .derived = derived };
}

fn changedBody(a: std.mem.Allocator, original: Fixture, node: usize) !Fixture {
    const digests = try a.dupe(Digest, original.shared.digests);
    digests[node] = @splat(42);
    return .{ .shared = .{ .digests = digests, .callees = original.shared.callees }, .identities = original.identities, .tests = original.tests };
}

fn replaceIndexes(a: std.mem.Allocator, store: *const stage.Store, slot: Digest, rows: []const Index) !void {
    var manifest = (try store.loadValue(a, slot, Manifest)).?;
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    try writer.write([]const Index, rows);
    const shard = store.key("test-graph-indexes-v1", &.{writer.bytes.items});
    _ = try store.save(shard, writer.bytes.items);
    manifest.indexes = try a.dupe(Digest, &.{shard});
    try store.storeValue(slot, Manifest, manifest);
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
    var seeded: graph.Statistics = .{};
    try input.prepared.publish(a, &store, input.indexes, &seeded);
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    var constrained = store;
    constrained.backing = backing;
    var stats: graph.Statistics = .{};
    try input.prepared.publish(arena.allocator(), &constrained, input.indexes, &stats);
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const warm = try derive(a, &store, input);
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const private = try derive(a, &store, try changedBody(a, input, 1));
    const reverted = try derive(a, &store, input);
    const shared = try derive(a, &store, try changedBody(a, input, 3));
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
    const cold = try derive(a, &store, try ordinary(a));
    const remapped = try fixture(
        a,
        .{ .digests = &.{ @splat(13), @splat(12), @splat(11), @splat(10) }, .callees = &.{ &.{}, &.{0}, &.{}, &.{ 2, 0 } } },
        &.{ @as(Digest, @splat(103)), @as(Digest, @splat(102)), @as(Digest, @splat(101)), @as(Digest, @splat(100)) },
        &.{ &.{3}, &.{1} },
    );
    const warm = try derive(a, &store, remapped);
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
    const input = try fixture(
        a,
        .{ .digests = &.{ @splat(10), @splat(11), @splat(11) }, .callees = &.{ &.{ 1, 2 }, &.{}, &.{} } },
        &.{ @as(Digest, @splat(100)), @as(Digest, @splat(101)), @as(Digest, @splat(102)) },
        &.{ &.{ 0, 0 }, &.{0} },
    );
    const cold = try derive(a, &store, input);
    const warm = try derive(a, &store, input);
    const private = try derive(a, &store, try changedBody(a, input, 2));
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const removed = try fixture(a, .{ .digests = &.{ @splat(10), @splat(12), @splat(13) }, .callees = &.{ &.{2}, &.{2}, &.{} } }, &.{ @as(Digest, @splat(100)), @as(Digest, @splat(102)), @as(Digest, @splat(103)) }, &.{ &.{0}, &.{1} });
    const shrunk = try derive(a, &store, removed);
    _ = try derive(a, &store, input);
    const replacement_ids = try a.dupe(?Digest, input.identities);
    replacement_ids[1] = @as(Digest, @splat(199));
    const replaced = try derive(a, &store, .{ .shared = input.shared, .identities = replacement_ids, .tests = input.tests });
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    var manifest = (try store.loadValue(a, cold.prepared.slot, Manifest)).?;
    manifest.indexes = &.{@splat(255)};
    try store.storeValue(cold.prepared.slot, Manifest, manifest);
    const recovered = try derive(a, &store, input);
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const manifest = (try store.loadValue(a, cold.prepared.slot, Manifest)).?;
    try std.testing.expect(try store.save(manifest.tests[0], "invalid graph shard"));
    const recovered = try derive(a, &store, input);
    const repaired = try derive(a, &store, input);
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    var manifest = (try store.loadValue(a, cold.prepared.slot, Manifest)).?;
    const malformed = "\x01\x00";
    const shard = store.key("test-graph-tests-v1", &.{malformed});
    try std.testing.expect(try store.save(shard, malformed));
    manifest.tests = &.{shard};
    try store.storeValue(cold.prepared.slot, Manifest, manifest);
    const recovered = try derive(a, &store, input);
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
    const input = try ordinary(a);
    _ = try derive(a, &store, input);
    const warm = try derive(a, &store, input);
    var constrained = store;
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    constrained.backing = failing.allocator();
    var stats: graph.Statistics = .{};
    try std.testing.expectError(error.OutOfMemory, warm.prepared.publish(a, &constrained, warm.prepared.prior.?, &stats));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publicationFailure, .{Publication{ .parent = std.testing.allocator, .prepared = warm.prepared, .indexes = warm.prepared.prior.? }});
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const invalid: []const Index = &.{ .{ .group = 0, .reverse = &.{} }, .{ .group = 1, .reverse = &.{0} }, .{ .group = 2, .reverse = &.{} }, .{ .group = 3, .reverse = &.{0} } };
    try replaceIndexes(a, &store, cold.prepared.slot, invalid);
    const recovered = try derive(a, &store, input);
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
    const input = try ordinary(a);
    const cold = try derive(a, &store, input);
    const invalid: []const Index = &.{ .{ .group = 3, .reverse = &.{} }, .{ .group = 1, .reverse = &.{0} }, .{ .group = 2, .reverse = &.{} }, .{ .group = 3, .reverse = &.{ 0, 2 } } };
    try replaceIndexes(a, &store, cold.prepared.slot, invalid);
    const recovered = try derive(a, &store, input);
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
    var compressed = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    const input = try ordinary(a);
    const cold = try derive(a, &compressed, input);
    try std.testing.expect(try compressed.flush());
    compressed.deinit();
    var raw = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .compression = .none });
    defer raw.deinit();
    const warm = try derive(a, &raw, input);
    const private = try derive(a, &raw, try changedBody(a, input, 1));
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
    const ordinary_input = try ordinary(a);
    const cycle: Fixture = .{ .shared = .{ .digests = ordinary_input.shared.digests, .callees = &.{ &.{1}, &.{0}, &.{3}, &.{} } }, .identities = ordinary_input.identities, .tests = ordinary_input.tests };
    const cold = try derive(a, &store, cycle);
    const warm = try derive(a, &store, cycle);
    const private = try derive(a, &store, try changedBody(a, cycle, 1));
    _ = try derive(a, &store, cycle);
    const split: Fixture = .{ .shared = .{ .digests = cycle.shared.digests, .callees = &.{ &.{1}, &.{}, &.{3}, &.{} } }, .identities = cycle.identities, .tests = cycle.tests };
    const changed_edge = try derive(a, &store, split);
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
    const cold = try derive(a, &store, input);
    const warm = try derive(a, &store, input);
    var manifest = (try store.loadValue(a, cold.prepared.slot, Manifest)).?;
    const shards = try a.dupe(Digest, manifest.nodes);
    shards[1] = @splat(255);
    manifest.nodes = shards;
    try store.storeValue(cold.prepared.slot, Manifest, manifest);
    const recovered = try derive(a, &store, input);
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
    const input = try ordinary(a);
    var stats: graph.Statistics = .{};
    const duplicate_ids = try a.dupe(?Digest, input.identities);
    duplicate_ids[1] = duplicate_ids[0];
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, &store, input.shared, duplicate_ids, input.tests, &stats));
    const missing_id = try a.dupe(?Digest, input.identities);
    missing_id[1] = null;
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, &store, input.shared, missing_id, input.tests, &stats));
    const duplicate_edges: keys.Shared = .{ .digests = input.shared.digests, .callees = &.{ &.{ 1, 1 }, &.{}, &.{3}, &.{} } };
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, &store, duplicate_edges, input.identities, input.tests, &stats));
    const absent_edge: keys.Shared = .{ .digests = input.shared.digests, .callees = &.{ &.{4}, &.{}, &.{3}, &.{} } };
    try std.testing.expectError(error.UnknownMetadata, graph.prepare(a, &store, absent_edge, input.identities, input.tests, &stats));
}
