//! Bounded, pointer-free test-index component frames.
const std = @import("std");
const typed = @import("typed.zig");
const index = @import("tests_index.zig");
/// Frame validation and allocation failures.
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Maximum request frame size, including its header.
pub const request_limit = 16 << 20;
/// Maximum reply frame size, including its header.
pub const reply_limit = 64 << 20;
/// Correlates the reply with one request and graph snapshot.
pub const Identity = struct { request_id: u64, snapshot: [32]u8 };
/// Allocator-owned serialized request and expected reply identity.
pub const Request = struct { bytes: []u8, identity: Identity };

/// Serialize a validated graph within the request budget.
pub fn request(a: std.mem.Allocator, graph: []const []const typed.FunctionId, tests: []const typed.FunctionId, id: u64) Error!Request {
    if (graph.len > 100000 or tests.len > 100000) return error.ComponentProtocol;
    var size: usize = 8 + tests.len * 4;
    var edges: usize = 0;
    for (graph) |list| {
        if (list.len > 1000000 - edges) return error.ComponentProtocol;
        edges += list.len;
        size += 4 + list.len * 4;
    }
    if (edges > 1000000 or size > request_limit - 64) return error.ComponentProtocol;
    const bytes = try a.alloc(u8, size + 64);
    errdefer a.free(bytes);
    var at: usize = 64;
    put(bytes, &at, @intCast(graph.len));
    put(bytes, &at, @intCast(tests.len));
    for (tests) |test_id| {
        const value = @backingInt(test_id);
        if (value >= graph.len) return error.ComponentProtocol;
        put(bytes, &at, @intCast(value));
    }
    for (graph) |list| {
        put(bytes, &at, @intCast(list.len));
        for (list) |target| {
            const value = @backingInt(target);
            if (value >= graph.len) return error.ComponentProtocol;
            put(bytes, &at, @intCast(value));
        }
    }
    var snapshot: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[64..], &snapshot, .{});
    const identity: Identity = .{ .request_id = id, .snapshot = snapshot };
    header(bytes, 0, identity);
    return .{ .bytes = bytes, .identity = identity };
}

/// Write a header into an already sized frame of at least 64 bytes.
pub fn header(bytes: []u8, kind: u32, identity: Identity) void {
    @memcpy(bytes[0..8], "SLKIDX01");
    var at: usize = 8;
    put(bytes, &at, 1);
    put(bytes, &at, 1);
    put(bytes, &at, kind);
    put(bytes, &at, @intCast(bytes.len - 64));
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
        if (self.at > self.bytes.len or self.bytes.len - self.at < 4) return error.ComponentProtocol;
        const n = std.mem.readInt(u32, self.bytes[self.at..][0..4], .little);
        self.at += 4;
        return n;
    }
    fn list(self: *Reader, a: std.mem.Allocator, names: []const []const u8, allowed: []const bool) Error![]const []const u8 {
        const n = try self.word();
        if (n > (self.bytes.len - self.at) / 4) return error.ComponentProtocol;
        const result = try a.alloc([]const u8, n);
        for (result) |*slot| {
            const id = try self.word();
            if (id >= names.len or !allowed[id]) return error.ComponentProtocol;
            slot.* = names[id];
        }
        return result;
    }
};

/// Validate a complete reply before publishing its arena-owned index.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: Identity, names: []const []const u8, tests: []const typed.FunctionId) Error!index.Index {
    if (bytes.len < 64 or bytes.len > reply_limit or !std.mem.eql(u8, bytes[0..8], "SLKIDX01")) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[8..12], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[12..16], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[16..20], .little) != 1) return error.ComponentProtocol;
    if (std.mem.readInt(u32, bytes[20..24], .little) != bytes.len - 64) return error.ComponentProtocol;
    if (std.mem.readInt(u64, bytes[24..32], .little) != identity.request_id) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[32..64], &identity.snapshot)) return error.ComponentProtocol;
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const allowed = try scratch.alloc(bool, names.len);
    @memset(allowed, false);
    for (tests) |id| {
        if (@backingInt(id) >= names.len) return error.ComponentProtocol;
        allowed[@backingInt(id)] = true;
    }
    var reader: Reader = .{ .bytes = bytes };
    if (try reader.word() != names.len) return error.ComponentProtocol;
    const direct = try scratch.alloc([]const []const u8, names.len);
    const reached = try scratch.alloc([]const []const u8, names.len);
    for (direct, reached) |*d, *r| {
        d.* = try reader.list(scratch, names, allowed);
        r.* = try reader.list(scratch, names, allowed);
    }
    if (reader.at != bytes.len) return error.ComponentProtocol;
    return .{ .arena = arena, .direct = direct, .reached = reached };
}
