//! Generation-bound incremental Core planner exchange; canonical facts stay with Zig.
const std = @import("std");
const v1 = @import("cache_plan_protocol.zig");
/// Canonical producer, topology, or implementation fingerprint.
pub const Digest = v1.Digest;
/// Boundary allocation and validation failures.
pub const Error = v1.Error;
/// Maximum incremental request bytes, including an optional retained index.
pub const request_limit = 32 << 20;
/// Maximum incremental reply bytes, including newly published indexes.
pub const reply_limit = 64 << 20;
/// Maximum aggregate index, propagation and closure operations.
pub const max_work = 64_000_000;
/// Validated graph indexes tied to the exact current ordered identity mapping.
pub const Indexes = struct { topology: Digest, reverse: []const []const u32, groups: []const u32 };
/// One complete discovery revision and candidate summaries validated by the host.
pub const Incremental = struct {
    graph: v1.Graph,
    roots: []const []const u32,
    topology: Digest,
    prior: ?Indexes = null,
    changed: []const u32,
    candidates: []const bool,
};
/// Deterministic planning counts; algorithms may inspect different index work.
pub const Work = struct { index_nodes: u64 = 0, index_edges: u64 = 0, affected_nodes: u64 = 0, closure_nodes: u64 = 0, closure_edges: u64 = 0, reused_tests: u64 = 0, planned_tests: u64 = 0 };
/// Actual component transport costs, absent for explicit reference execution.
pub const Transport = v1.Transport;
/// Owned decisions and indexes; reused batches intentionally contain no closure.
pub const IncrementalResults = struct {
    arena: std.heap.ArenaAllocator,
    batches: []const []const u32,
    reused: []const bool,
    indexes: Indexes,
    work: Work,
    transport: Transport = .{},
    /// Release all result storage.
    pub fn deinit(self: *IncrementalResults) void {
        self.arena.deinit();
    }
};
/// Owned correlated request frame.
pub const Request = v1.Request;

/// Build the exact transpose, preserving repeated graph edges in source order.
pub fn transpose(a: std.mem.Allocator, graph: v1.Graph) Error![]const []const u32 {
    const sizes = try a.alloc(usize, graph.digests.len);
    defer a.free(sizes);
    @memset(sizes, 0);
    for (graph.callees) |row| for (row) |target| {
        if (target >= sizes.len) return error.ComponentProtocol;
        sizes[target] += 1;
    };
    const rows = try a.alloc([]u32, sizes.len);
    var filled: usize = 0;
    errdefer {
        for (rows[0..filled]) |row| a.free(row);
        a.free(rows);
    }
    for (rows, sizes) |*row, size| {
        row.* = try a.alloc(u32, size);
        filled += 1;
    }
    @memset(sizes, 0);
    for (graph.callees, 0..) |row, source| for (row) |target| {
        rows[target][sizes[target]] = @intCast(source);
        sizes[target] += 1;
    };
    return rows;
}

/// Reject malformed retained indexes before they can approve cached keys.
pub fn validateIndexes(a: std.mem.Allocator, graph: v1.Graph, indexes: Indexes, topology: Digest) Error!void {
    if (!std.mem.eql(u8, &indexes.topology, &topology) or indexes.groups.len != graph.digests.len or indexes.reverse.len != graph.digests.len) return error.ComponentProtocol;
    for (indexes.groups, 0..) |group, node| {
        if (group > node or group >= indexes.groups.len or indexes.groups[group] != group) return error.ComponentProtocol;
    }
    const expected = try transpose(a, graph);
    defer {
        for (expected) |row| a.free(row);
        a.free(expected);
    }
    for (expected, indexes.reverse) |left, right| if (!std.mem.eql(u32, left, right)) return error.ComponentProtocol;
}

/// Validate current tables and resource budgets independently of serialization.
pub fn validate(a: std.mem.Allocator, input: Incremental) Error!void {
    const graph = input.graph;
    if (graph.digests.len != graph.callees.len or graph.digests.len > 100000 or input.roots.len > 100000) return error.ComponentProtocol;
    if (input.candidates.len != input.roots.len or input.changed.len > graph.digests.len) return error.ComponentProtocol;
    var edges: usize = 0;
    var roots: usize = 0;
    for (graph.callees) |row| {
        if (row.len > 1000000 - edges) return error.ComponentProtocol;
        edges += row.len;
        for (row) |node| if (node >= graph.digests.len) return error.ComponentProtocol;
    }
    for (input.roots) |row| {
        if (row.len > 1000000 - roots) return error.ComponentProtocol;
        roots += row.len;
        for (row) |node| if (node >= graph.digests.len) return error.ComponentProtocol;
    }
    const seen = try a.alloc(bool, graph.digests.len);
    defer a.free(seen);
    @memset(seen, false);
    for (input.changed) |node| {
        if (node >= seen.len or seen[node]) return error.ComponentProtocol;
        seen[node] = true;
    }
    if (input.prior) |prior| try validateIndexes(a, graph, prior, input.topology);
    const size = 124 + graph.digests.len * 36 + edges * 4 + input.roots.len * 8 + roots * 4 + input.changed.len * 4 + if (input.prior != null) 32 + graph.digests.len * 8 + edges * 4 else @as(usize, 0);
    if (size > request_limit) return error.ComponentProtocol;
}

/// Serialize the complete current facts once for an incremental batch.
pub fn request(a: std.mem.Allocator, input: Incremental, id: u64) Error!Request {
    try validate(a, input);
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    try bytes.appendNTimes(a, 0, 64);
    for ([_]u32{ 0, 0, 0 }) |value| try append(&bytes, a, u32, value);
    try bytes.appendSlice(a, &input.topology);
    for ([_]u32{ @intCast(input.graph.digests.len), @intCast(input.roots.len), @intCast(input.changed.len), @intFromBool(input.prior != null) }) |value| try append(&bytes, a, u32, value);
    for (input.graph.digests, input.graph.callees) |digest, row| {
        try bytes.appendSlice(a, &digest);
        try rowBytes(&bytes, a, row);
    }
    for (input.roots, input.candidates) |row, candidate| {
        try append(&bytes, a, u32, @intFromBool(candidate));
        try rowBytes(&bytes, a, row);
    }
    for (input.changed) |node| try append(&bytes, a, u32, node);
    if (input.prior) |prior| {
        try bytes.appendSlice(a, &prior.topology);
        for (prior.groups) |group| try append(&bytes, a, u32, group);
        for (prior.reverse) |row| try rowBytes(&bytes, a, row);
    }
    var snapshot: Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes.items[64..], &snapshot, .{});
    const identity: v1.Identity = .{ .request_id = id, .snapshot = snapshot };
    header(bytes.items, 0, identity);
    return .{ .bytes = try bytes.toOwnedSlice(a), .identity = identity };
}

/// Write the version-two correlated envelope.
pub fn header(bytes: []u8, kind: u32, identity: v1.Identity) void {
    v1.header(bytes, kind, identity);
    @memcpy(bytes[0..8], "SLKCP002");
    std.mem.writeInt(u32, bytes[8..12], 2, .little);
    std.mem.writeInt(u32, bytes[12..16], 2, .little);
}

fn append(bytes: *std.ArrayList(u8), a: std.mem.Allocator, comptime T: type, value: T) Error!void {
    var encoded: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &encoded, value, .little);
    try bytes.appendSlice(a, &encoded);
}

fn rowBytes(bytes: *std.ArrayList(u8), a: std.mem.Allocator, row: []const u32) Error!void {
    try append(bytes, a, u32, @intCast(row.len));
    for (row) |node| try append(bytes, a, u32, node);
}

/// Encode a reference result for independent boundary qualification.
pub fn response(a: std.mem.Allocator, result: IncrementalResults, identity: v1.Identity) Error![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    try bytes.appendNTimes(a, 0, 64);
    inline for (@typeInfo(Work).@"struct".field_names) |field| try append(&bytes, a, u64, @field(result.work, field));
    try append(&bytes, a, u32, @intCast(result.indexes.groups.len));
    try append(&bytes, a, u32, @intCast(result.batches.len));
    for (result.indexes.groups) |group| try append(&bytes, a, u32, group);
    for (result.indexes.reverse) |row| try rowBytes(&bytes, a, row);
    for (result.batches, result.reused) |row, reuse| {
        try append(&bytes, a, u32, @intFromBool(reuse));
        try rowBytes(&bytes, a, row);
    }
    if (bytes.items.len > reply_limit) return error.ComponentProtocol;
    header(bytes.items, 1, identity);
    return bytes.toOwnedSlice(a);
}

const Reader = struct {
    bytes: []const u8,
    at: usize = 64,
    fn number(self: *Reader, comptime T: type) Error!T {
        if (self.bytes.len - self.at < @sizeOf(T)) return error.ComponentProtocol;
        const value = std.mem.readInt(T, self.bytes[self.at..][0..@sizeOf(T)], .little);
        self.at += @sizeOf(T);
        return value;
    }
    fn row(self: *Reader, a: std.mem.Allocator, maximum: usize) Error![]const u32 {
        const count = try self.number(u32);
        if (count > maximum or count > (self.bytes.len - self.at) / 4) return error.ComponentProtocol;
        const values = try a.alloc(u32, count);
        for (values) |*value| value.* = try self.number(u32);
        return values;
    }
};

/// Validate reply correlation, reusable candidates, current indexes and closures.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: v1.Identity, input: Incremental) Error!IncrementalResults {
    if (bytes.len < 128 or bytes.len > reply_limit or !std.mem.eql(u8, bytes[0..8], "SLKCP002")) return error.ComponentProtocol;
    for ([_]u32{ 2, 2, 1, @intCast(bytes.len - 64) }, 0..) |expected, index| if (std.mem.readInt(u32, bytes[8 + index * 4 ..][0..4], .little) != expected) return error.ComponentProtocol;
    if (std.mem.readInt(u64, bytes[24..32], .little) != identity.request_id or !std.mem.eql(u8, bytes[32..64], &identity.snapshot)) return error.ComponentProtocol;
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    try validate(scratch, input);
    var reader: Reader = .{ .bytes = bytes };
    var work: Work = .{};
    inline for (@typeInfo(Work).@"struct".field_names) |field| @field(work, field) = try reader.number(u64);
    for ([_]u64{ work.index_nodes, work.index_edges, work.closure_nodes, work.closure_edges }) |count| if (count > max_work) return error.ComponentProtocol;
    if (work.affected_nodes > input.graph.digests.len or work.reused_tests > input.roots.len) return error.ComponentProtocol;
    if (work.planned_tests != input.roots.len - work.reused_tests) return error.ComponentProtocol;
    if (work.index_nodes + work.index_edges + work.affected_nodes + work.closure_nodes + work.closure_edges > max_work) return error.ComponentProtocol;
    if (try reader.number(u32) != input.graph.digests.len or try reader.number(u32) != input.roots.len) return error.ComponentProtocol;
    const groups = try scratch.alloc(u32, input.graph.digests.len);
    for (groups) |*group| group.* = try reader.number(u32);
    const reverse = try scratch.alloc([]const u32, groups.len);
    var edges: usize = 0;
    for (reverse) |*row| {
        row.* = try reader.row(scratch, 1000000 - edges);
        edges += row.len;
    }
    const indexes: Indexes = .{ .topology = input.topology, .reverse = reverse, .groups = groups };
    try validateIndexes(scratch, input.graph, indexes, input.topology);
    const batches = try scratch.alloc([]const u32, input.roots.len);
    const reused = try scratch.alloc(bool, batches.len);
    const seen = try scratch.alloc(u32, groups.len);
    @memset(seen, 0);
    var reused_count: u64 = 0;
    for (batches, reused, input.roots, input.candidates, 1..) |*batch, *reuse, roots, candidate, epoch_value| {
        const epoch: u32 = @intCast(epoch_value);
        const flag = try reader.number(u32);
        if (flag > 1 or (flag == 1 and !candidate)) return error.ComponentProtocol;
        reuse.* = flag == 1;
        if (reuse.*) reused_count += 1;
        batch.* = try reader.row(scratch, groups.len);
        if (reuse.* and batch.len != 0) return error.ComponentProtocol;
        for (roots) |root| seen[root] = epoch;
        for (batch.*, 0..) |node, index| {
            if (node >= groups.len or seen[node] == epoch) return error.ComponentProtocol;
            if (index > 0 and !before(input.graph.digests, batch.*[index - 1], node)) return error.ComponentProtocol;
            seen[node] = epoch;
        }
    }
    if (reader.at != bytes.len or reused_count != work.reused_tests) return error.ComponentProtocol;
    return .{ .arena = arena, .batches = batches, .reused = reused, .indexes = indexes, .work = work };
}

fn before(digests: []const Digest, left: u32, right: u32) bool {
    return switch (std.mem.order(u8, &digests[left], &digests[right])) {
        .lt => true,
        .gt => false,
        .eq => left < right,
    };
}
