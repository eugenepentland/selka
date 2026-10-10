//! Generation-bound test keys and logical graph facts. Missing metadata only loses reuse.
const std = @import("std");
const stage = @import("stage_store.zig");
const keys = @import("test_runner_identity.zig");
const wire = @import("mylang").cache_plan_adapter.incremental_protocol;
const codec = @import("mylang").persist_codec;
const Digest = keys.Digest;
const Error = keys.Error;
const chunk_size = 256;
const node_limit = 100000;
const edge_limit = 1000000;

const Node = struct { identity: ?Digest, body: Digest, edges: []const Digest };
const Test = struct { envelope: Digest, key: ?Digest = null };
const Index = struct { group: u32, reverse: []const u32 };
const Manifest = struct { nodes: []const Digest, tests: []const Digest, indexes: []const Digest, topology: Digest, node_count: u32, test_count: u32 };
const Snapshot = struct { nodes: []const Node, tests: []Test, topology: Digest };
const Previous = struct { snapshot: Snapshot, indexes: wire.Indexes };

/// Metadata work, including full revision validation before admitting any old key.
pub const Statistics = @import("test_runner_work.zig").Graph;
/// Current facts and old key candidates; only the bound planner may authorize reuse.
pub const Prepared = struct {
    snapshot: Snapshot,
    prior: ?wire.Indexes,
    changed: []const u32,
    candidates: []const bool,
    keys: []?Digest,
    slot: Digest,

    /// Bind the complete current graph and ordered roots to the incremental request.
    pub fn request(self: Prepared, shared: keys.Shared, roots: []const []const u32) wire.Incremental {
        return .{ .graph = .{ .digests = shared.digests, .callees = shared.callees }, .roots = roots, .topology = self.snapshot.topology, .prior = self.prior, .changed = self.changed, .candidates = self.candidates };
    }

    /// Publish immutable chunks first and the complete generation manifest last.
    /// The stored keys describe derivation only; they never certify a passing test.
    pub fn publish(self: Prepared, a: std.mem.Allocator, store: *const stage.Store, indexes: wire.Indexes, stats: *Statistics) Error!void {
        if (!std.mem.eql(u8, &indexes.topology, &self.snapshot.topology)) return error.UnknownMetadata;
        if (indexes.groups.len != self.snapshot.nodes.len or indexes.reverse.len != self.snapshot.nodes.len) return error.UnknownMetadata;
        for (self.snapshot.tests, self.keys) |*test_value, key| test_value.key = key;
        const rows = try a.alloc(Index, indexes.groups.len);
        for (rows, indexes.groups, indexes.reverse) |*row, group, reverse| row.* = .{ .group = group, .reverse = reverse };
        const node_chunks = try saveChunks(Node, store, self.snapshot.nodes, stats);
        defer store.backing.free(node_chunks);
        const test_chunks = try saveChunks(Test, store, self.snapshot.tests, stats);
        defer store.backing.free(test_chunks);
        const index_chunks = try saveChunks(Index, store, rows, stats);
        defer store.backing.free(index_chunks);
        const manifest: Manifest = .{
            .nodes = node_chunks,
            .tests = test_chunks,
            .indexes = index_chunks,
            .topology = self.snapshot.topology,
            .node_count = @intCast(self.snapshot.nodes.len),
            .test_count = @intCast(self.snapshot.tests.len),
        };
        try store.storeValue(self.slot, Manifest, manifest);
    }
};

/// Compare logical identities and complete outgoing sets, preserving keys across ID remapping.
/// Any incomplete previous generation discards all of its authority together.
pub fn prepare(a: std.mem.Allocator, store: *const stage.Store, shared: keys.Shared, identities: []const ?Digest, tests: []const keys.Test, stats: *Statistics) Error!Prepared {
    if (tests.len == 0 or tests.len > node_limit) return error.UnknownMetadata;
    const current_nodes = try nodes(a, shared, identities);
    const current_tests = try a.alloc(Test, tests.len);
    for (tests, current_tests) |test_value, *saved| saved.* = .{ .envelope = try envelope(shared, identities, test_value) };
    const topology = topologyDigest(current_nodes);
    const slot = store.key("test-graph-head-v1", &.{ tests[0].source_path, &tests[0].base });
    const previous = try load(a, store, slot, stats);
    var old_nodes: std.AutoHashMapUnmanaged(Digest, usize) = .empty;
    var old_tests: std.AutoHashMapUnmanaged(Digest, Digest) = .empty;
    if (previous) |old| {
        for (old.snapshot.nodes, 0..) |node, index| if (node.identity) |identity| try old_nodes.put(a, identity, index);
        for (old.snapshot.tests) |test_value| if (test_value.key) |key| try old_tests.put(a, test_value.envelope, key);
    }
    var changed: std.ArrayList(u32) = .empty;
    for (current_nodes, 0..) |node, index| {
        const unchanged = if (node.identity) |identity| if (old_nodes.get(identity)) |old_index| same(node, previous.?.snapshot.nodes[old_index]) else false else false;
        if (unchanged) stats.nodes_unchanged += 1 else try changed.append(a, @intCast(index));
    }
    stats.changed_nodes = changed.items.len;
    const candidates = try a.alloc(bool, tests.len);
    const cached = try a.alloc(?Digest, tests.len);
    for (current_tests, candidates, cached) |test_value, *candidate, *key| {
        key.* = old_tests.get(test_value.envelope);
        candidate.* = key.* != null;
        stats.candidate_tests += @intFromBool(candidate.*);
    }
    const prior = if (previous) |old| if (std.mem.eql(u8, &old.snapshot.topology, &topology)) old.indexes else null else null;
    return .{ .snapshot = .{ .nodes = current_nodes, .tests = current_tests, .topology = topology }, .prior = prior, .changed = changed.items, .candidates = candidates, .keys = cached, .slot = slot };
}

fn same(left: Node, right: Node) bool {
    return std.mem.eql(u8, &left.body, &right.body) and std.mem.eql(u8, std.mem.sliceAsBytes(left.edges), std.mem.sliceAsBytes(right.edges));
}

fn nodes(a: std.mem.Allocator, shared: keys.Shared, identities: []const ?Digest) Error![]const Node {
    if (shared.digests.len > node_limit or shared.digests.len != shared.callees.len or shared.digests.len != identities.len) return error.UnknownMetadata;
    var seen: std.AutoHashMapUnmanaged(Digest, void) = .empty;
    const result = try a.alloc(Node, identities.len);
    var edge_count: usize = 0;
    for (identities, shared.digests, shared.callees, result) |identity, body, targets, *node| {
        if (identity) |id| {
            if ((try seen.getOrPut(a, id)).found_existing) return error.UnknownMetadata;
        } else if (targets.len != 0) return error.UnknownMetadata;
        if (targets.len > edge_limit - edge_count) return error.UnknownMetadata;
        edge_count += targets.len;
        const edges = try a.alloc(Digest, targets.len);
        for (targets, edges) |target, *edge| {
            if (target >= identities.len) return error.UnknownMetadata;
            edge.* = identities[target] orelse return error.UnknownMetadata;
        }
        std.mem.sort(Digest, edges, {}, digestBefore);
        for (edges, 0..) |edge, index| if (index != 0 and std.mem.eql(u8, &edge, &edges[index - 1])) return error.UnknownMetadata;
        node.* = .{ .identity = identity, .body = body, .edges = edges };
    }
    return result;
}

fn envelope(shared: keys.Shared, identities: []const ?Digest, test_value: keys.Test) Error!Digest {
    // This is only an index: the actual legacy key retains its flat closure encoding.
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("test-key-envelope-v1");
    hash.update(&try keys.plannedKey(shared, test_value, &.{}));
    integer(&hash, test_value.roots.len);
    for (test_value.roots) |root| {
        if (root >= identities.len) return error.UnknownMetadata;
        hash.update(&(identities[root] orelse return error.UnknownMetadata));
    }
    return finish(&hash);
}

fn topologyDigest(values: []const Node) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("test-ordered-topology-v1");
    integer(&hash, values.len);
    for (values) |node| {
        hash.update(&.{@intFromBool(node.identity != null)});
        if (node.identity) |identity| hash.update(&identity);
        integer(&hash, node.edges.len);
        for (node.edges) |edge| hash.update(&edge);
    }
    return finish(&hash);
}

fn load(a: std.mem.Allocator, store: *const stage.Store, slot: Digest, stats: *Statistics) Error!?Previous {
    const manifest = try store.loadValue(a, slot, Manifest) orelse return null;
    if (manifest.node_count > node_limit or manifest.test_count > node_limit) return null;
    const old_nodes = try loadChunks(Node, a, store, manifest.nodes, manifest.node_count, stats) orelse return null;
    const old_tests = try loadChunks(Test, a, store, manifest.tests, manifest.test_count, stats) orelse return null;
    const old_indexes = try loadChunks(Index, a, store, manifest.indexes, manifest.node_count, stats) orelse return null;
    if (!try validNodes(a, old_nodes)) return null;
    if (!std.mem.eql(u8, &topologyDigest(old_nodes), &manifest.topology)) return null;
    const groups = try a.alloc(u32, old_indexes.len);
    const reverse = try a.alloc([]const u32, old_indexes.len);
    var edges: usize = 0;
    for (old_indexes, groups, reverse, 0..) |index, *group, *targets, node| {
        if (index.group > node or index.reverse.len > edge_limit - edges) return null;
        edges += index.reverse.len;
        for (index.reverse) |target| if (target >= old_nodes.len) return null;
        group.* = index.group;
        targets.* = index.reverse;
    }
    for (groups) |group| if (groups[group] != group) return null;
    if (!try validReverse(a, old_nodes, reverse)) return null;
    stats.nodes_read += old_nodes.len;
    return .{ .snapshot = .{ .nodes = old_nodes, .tests = old_tests, .topology = manifest.topology }, .indexes = .{ .topology = manifest.topology, .groups = groups, .reverse = reverse } };
}

fn validReverse(a: std.mem.Allocator, values: []const Node, reverse: []const []const u32) Error!bool {
    var ids: std.AutoHashMapUnmanaged(Digest, u32) = .empty;
    for (values, 0..) |node, index| if (node.identity) |identity| try ids.put(a, identity, @intCast(index));
    const used = try a.alloc(usize, values.len);
    @memset(used, 0);
    for (values, 0..) |node, caller| for (node.edges) |edge| {
        const target = ids.get(edge) orelse return false;
        if (used[target] >= reverse[target].len or reverse[target][used[target]] != caller) return false;
        used[target] += 1;
    };
    for (used, reverse) |count, row| if (count != row.len) return false;
    return true;
}

fn validNodes(a: std.mem.Allocator, values: []const Node) Error!bool {
    var ids: std.AutoHashMapUnmanaged(Digest, void) = .empty;
    for (values) |node| if (node.identity) |identity| {
        if ((try ids.getOrPut(a, identity)).found_existing) return false;
    } else if (node.edges.len != 0) return false;
    var edge_count: usize = 0;
    for (values) |node| {
        if (node.edges.len > edge_limit - edge_count) return false;
        edge_count += node.edges.len;
        for (node.edges, 0..) |edge, index| {
            if (!ids.contains(edge)) return false;
            if (index != 0 and !digestBefore({}, node.edges[index - 1], edge)) return false;
        }
    }
    return true;
}

fn chunkScope(comptime T: type) []const u8 {
    return if (T == Node) "test-graph-nodes-v1" else if (T == Test) "test-graph-tests-v1" else "test-graph-indexes-v1";
}

fn saveChunks(comptime T: type, store: *const stage.Store, values: []const T, stats: *Statistics) Error![]Digest {
    const chunks = try store.backing.alloc(Digest, chunkCount(values.len));
    errdefer store.backing.free(chunks);
    for (chunks, 0..) |*chunk, index| {
        var writer = codec.Writer.init(store.backing);
        defer writer.deinit();
        try writer.write([]const T, values[index * chunk_size .. @min(values.len, (index + 1) * chunk_size)]);
        chunk.* = store.key(chunkScope(T), &.{writer.bytes.items});
        // Immutable chunks can be shared by successive graph generations.
        const present = try store.load(store.backing, chunk.*);
        defer if (present) |bytes| store.backing.free(bytes);
        const valid = if (present) |bytes| std.mem.eql(u8, &store.key(chunkScope(T), &.{bytes}), chunk) else false;
        if (!valid) {
            if (try store.save(chunk.*, writer.bytes.items)) stats.shards_written += 1;
        }
    }
    return chunks;
}

fn loadChunks(comptime T: type, a: std.mem.Allocator, store: *const stage.Store, chunks: []const Digest, count: usize, stats: *Statistics) Error!?[]T {
    if (chunks.len != chunkCount(count)) return null;
    const values = try a.alloc(T, count);
    for (chunks, 0..) |chunk, index| {
        const bytes = try store.load(store.backing, chunk) orelse return null;
        defer store.backing.free(bytes);
        if (!std.mem.eql(u8, &store.key(chunkScope(T), &.{bytes}), &chunk)) return null;
        var reader = codec.Reader.init(a, bytes);
        const decoded = reader.read([]const T) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        const size = @min(chunk_size, count - index * chunk_size);
        if (!reader.done() or decoded.len != size) return null;
        @memcpy(values[index * chunk_size ..][0..size], decoded);
        stats.shards_read += 1;
    }
    return values;
}

fn integer(hash: *std.crypto.hash.Blake3, value: usize) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, @intCast(value), .little);
    hash.update(&bytes);
}

fn chunkCount(count: usize) usize {
    return count / chunk_size + @intFromBool(count % chunk_size != 0);
}
fn finish(hash: *std.crypto.hash.Blake3) Digest {
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}
fn digestBefore(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}
