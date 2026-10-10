//! Bounded Core reachability exchange; IR canonicalization stays with the host.
const std = @import("std");
/// Canonical function or implementation fingerprint.
pub const Digest = [32]u8;
/// Immutable complete Core graph, including calls and function references.
pub const Graph = struct { digests: []const Digest, callees: []const []const u32 };
/// Boundary allocation and validation failures.
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Maximum serialized input bytes.
pub const request_limit = 16 << 20;
/// Maximum serialized output bytes.
pub const reply_limit = 64 << 20;
/// Maximum aggregate popped nodes and inspected edges.
pub const max_work = 16_000_000;
/// Request nonce and complete input snapshot.
pub const Identity = struct { request_id: u64, snapshot: Digest };
/// Owned request frame and expected reply correlation.
pub const Request = struct { bytes: []u8, identity: Identity };
/// Actual batch transport costs, absent for explicit reference execution.
pub const Transport = struct { request_bytes: u64 = 0, reply_bytes: u64 = 0, startups: u64 = 0 };
/// Arena-owned, canonically sorted nonroot node IDs for each requested batch.
pub const Results = struct {
    arena: std.heap.ArenaAllocator,
    batches: []const []const u32,
    transport: Transport = .{},
    /// Release all result storage.
    pub fn deinit(self: *Results) void {
        self.arena.deinit();
    }
};
/// Reject incomplete graphs and resource budgets before traversal or serialization.
pub fn validate(graph: Graph, roots: []const []const u32) Error!void {
    if (graph.digests.len != graph.callees.len or graph.digests.len > 100000 or roots.len > 100000) return error.ComponentProtocol;
    var edges: usize = 0;
    var root_count: usize = 0;
    for (graph.callees) |list| {
        if (list.len > 1000000 - edges) return error.ComponentProtocol;
        edges += list.len;
        for (list) |id| if (id >= graph.digests.len) return error.ComponentProtocol;
    }
    for (roots) |list| {
        if (list.len > 1000000 - root_count) return error.ComponentProtocol;
        root_count += list.len;
        for (list) |id| if (id >= graph.digests.len) return error.ComponentProtocol;
    }
    if (84 + graph.digests.len * 36 + edges * 4 + roots.len * 4 + root_count * 4 > request_limit) return error.ComponentProtocol;
}
/// Serialize the current pure, disposable, successful-result policy and graph.
pub fn request(a: std.mem.Allocator, graph: Graph, roots: []const []const u32, id: u64) Error!Request {
    try validate(graph, roots);
    var size: usize = 84 + graph.digests.len * 36 + roots.len * 4;
    for (graph.callees) |list| size += list.len * 4;
    for (roots) |list| size += list.len * 4;
    const bytes = try a.alloc(u8, size);
    var at: usize = 64;
    for ([_]u32{ 0, 0, 0, @intCast(graph.digests.len), @intCast(roots.len) }) |value| put(bytes, &at, value);
    for (graph.digests, graph.callees) |digest, list| {
        @memcpy(bytes[at..][0..32], &digest);
        at += 32;
        put(bytes, &at, @intCast(list.len));
        for (list) |target| put(bytes, &at, target);
    }
    for (roots) |list| {
        put(bytes, &at, @intCast(list.len));
        for (list) |root| put(bytes, &at, root);
    }
    var snapshot: Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[64..], &snapshot, .{});
    const identity: Identity = .{ .request_id = id, .snapshot = snapshot };
    header(bytes, 0, identity);
    return .{ .bytes = bytes, .identity = identity };
}
/// Write the versioned 64-byte envelope.
pub fn header(bytes: []u8, kind: u32, identity: Identity) void {
    @memcpy(bytes[0..8], "SLKCP001");
    var at: usize = 8;
    for ([_]u32{ 1, 1, kind, @intCast(bytes.len - 64) }) |value| put(bytes, &at, value);
    std.mem.writeInt(u64, bytes[24..32], identity.request_id, .little);
    @memcpy(bytes[32..64], &identity.snapshot);
}
fn put(bytes: []u8, at: *usize, value: u32) void {
    std.mem.writeInt(u32, bytes[at.*..][0..4], value, .little);
    at.* += 4;
}
const Reader = struct {
    bytes: []const u8,
    at: usize = 64,
    fn word(self: *Reader) Error!u32 {
        if (self.bytes.len - self.at < 4) return error.ComponentProtocol;
        const value = std.mem.readInt(u32, self.bytes[self.at..][0..4], .little);
        self.at += 4;
        return value;
    }
};
/// Strictly validate correlation, IDs, multiplicity, root exclusion and ordering.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: Identity, graph: Graph, roots: []const []const u32) Error!Results {
    try validate(graph, roots);
    if (bytes.len < 68 or bytes.len > reply_limit or !std.mem.eql(u8, bytes[0..8], "SLKCP001")) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[8..12], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[12..16], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[16..20], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[20..24], .little) != bytes.len - 64) return error.ComponentProtocol;
    if (std.mem.readInt(u64, bytes[24..32], .little) != identity.request_id) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[32..64], &identity.snapshot)) return error.ComponentProtocol;
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    var reader: Reader = .{ .bytes = bytes };
    if (try reader.word() != roots.len) return error.ComponentProtocol;
    const batches = try scratch.alloc([]const u32, roots.len);
    const seen = try scratch.alloc(u32, graph.digests.len);
    @memset(seen, 0);
    for (batches, roots, 1..) |*batch, list, epoch_value| {
        const epoch: u32 = @intCast(epoch_value);
        for (list) |root| seen[root] = epoch;
        const count = try reader.word();
        if (count > graph.digests.len or count > (bytes.len - reader.at) / 4) return error.ComponentProtocol;
        const ids = try scratch.alloc(u32, count);
        for (ids, 0..) |*slot, index| {
            const id = try reader.word();
            if (id >= seen.len or seen[id] == epoch) return error.ComponentProtocol;
            if (index > 0 and !before(graph.digests, ids[index - 1], id)) return error.ComponentProtocol;
            seen[id] = epoch;
            slot.* = id;
        }
        batch.* = ids;
    }
    if (reader.at != bytes.len) return error.ComponentProtocol;
    return .{ .arena = arena, .batches = batches };
}
fn before(digests: []const Digest, left: u32, right: u32) bool {
    return switch (std.mem.order(u8, &digests[left], &digests[right])) {
        .lt => true,
        .gt => false,
        .eq => left < right,
    };
}
/// Pure host oracle preserving ordered roots and duplicate equal nonroot digests.
pub fn reference(a: std.mem.Allocator, graph: Graph, roots: []const []const u32) Error!Results {
    try validate(graph, roots);
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const batches = try scratch.alloc([]const u32, roots.len);
    const seen = try scratch.alloc(u32, graph.digests.len);
    @memset(seen, 0);
    var work: usize = 0;
    var output_size: usize = 68 + roots.len * 4;
    for (batches, roots, 1..) |*batch, list, epoch_value| {
        const epoch: u32 = @intCast(epoch_value);
        var queue: std.ArrayList(u32) = .empty;
        for (list) |root| {
            if (seen[root] == epoch) continue;
            seen[root] = epoch;
            try queue.append(scratch, root);
        }
        var reached: std.ArrayList(u32) = .empty;
        var next: usize = 0;
        while (next < queue.items.len) : (next += 1) {
            work += 1;
            if (work > max_work) return error.ComponentProtocol;
            for (graph.callees[queue.items[next]]) |target| {
                work += 1;
                if (work > max_work) return error.ComponentProtocol;
                if (seen[target] == epoch) continue;
                seen[target] = epoch;
                try queue.append(scratch, target);
                try reached.append(scratch, target);
            }
        }
        output_size += reached.items.len * 4;
        if (output_size > reply_limit) return error.ComponentProtocol;
        std.mem.sort(u32, reached.items, graph.digests, before);
        batch.* = reached.items;
    }
    return .{ .arena = arena, .batches = batches };
}
