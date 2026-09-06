//! Strict JSON snapshot conversion; allocation belongs to the caller's request arena.
const std = @import("std");
const m = @import("model.zig");
const Json = std.json.Value;
pub const Error = error{ InvalidSnapshot, SnapshotCapacity, OutOfMemory };
/// Sanitized request metadata and borrowed bounded board slices.
pub const Request = struct { name: []const u8, board: m.Board, unavailable: bool };
/// Validate transport shape independently of the guest's logical input checks.
pub fn request(allocator: std.mem.Allocator, value: Json) Error!Request {
    try fields(value, &.{ "name", "input", "unavailable" });
    const unavailable = try get(value, "unavailable");
    if (unavailable != .bool) return error.InvalidSnapshot;
    const document = try get(value, "input");
    try fields(document, &.{ "version", "board" });
    if (try integer(u64, try get(document, "version")) != 1) return error.InvalidSnapshot;
    const board = try get(document, "board");
    try fields(board, &.{ "outline", "components", "nets", "regions", "features" });
    const regions_json = try array(try get(board, "regions"), 4);
    const regions = try allocator.alloc(m.Region, regions_json.len);
    for (regions, regions_json) |*out, item| out.* = try region(allocator, item);
    const features_json = try array(try get(board, "features"), 8);
    const features = try allocator.alloc(m.Feature, features_json.len);
    for (features, features_json) |*out, item| out.* = try feature(item);
    return .{ .name = try string(try get(value, "name")), .unavailable = unavailable.bool, .board = .{
        .outline = try rect(try get(board, "outline")),
        .components = try identities(m.ComponentId, allocator, try get(board, "components")),
        .nets = try identities(m.NetId, allocator, try get(board, "nets")),
        .regions = regions,
        .features = features,
    } };
}
fn fields(value: Json, names: []const []const u8) Error!void {
    if (value != .object or value.object.count() != names.len) return error.InvalidSnapshot;
    for (names) |name| if (!value.object.contains(name)) return error.InvalidSnapshot;
}
fn get(value: Json, name: []const u8) Error!Json {
    if (value != .object) return error.InvalidSnapshot;
    return value.object.get(name) orelse error.InvalidSnapshot;
}
fn string(value: Json) Error![]const u8 {
    return if (value == .string) value.string else error.InvalidSnapshot;
}
fn integer(comptime T: type, value: Json) Error!T {
    if (value != .number_string) return error.InvalidSnapshot;
    return std.fmt.parseInt(T, value.number_string, 10) catch error.InvalidSnapshot;
}
fn enumeration(comptime T: type, value: Json) Error!T {
    return std.meta.stringToEnum(T, try string(value)) orelse error.InvalidSnapshot;
}
fn array(value: Json, capacity: usize) Error![]const Json {
    if (value != .array) return error.InvalidSnapshot;
    if (value.array.items.len > capacity) return error.SnapshotCapacity;
    return value.array.items;
}
fn identities(comptime T: type, allocator: std.mem.Allocator, value: Json) Error![]const T {
    const values = try array(value, 4);
    const out = try allocator.alloc(T, values.len);
    for (out, values) |*id, item| id.* = @fromBackingInt(try integer(u64, item));
    return out;
}
fn rect(value: Json) Error!m.Rect {
    const values = try array(value, 4);
    if (values.len != 4) return error.InvalidSnapshot;
    return .{ .x = @fromBackingInt(try integer(i64, values[0])), .y = @fromBackingInt(try integer(i64, values[1])), .width = @fromBackingInt(try integer(i64, values[2])), .height = @fromBackingInt(try integer(i64, values[3])) };
}
fn region(allocator: std.mem.Allocator, value: Json) Error!m.Region {
    try fields(value, &.{ "rect", "face", "blocks", "allow_nets" });
    const blocks_value = try get(value, "blocks");
    if (blocks_value != .array) return error.InvalidSnapshot;
    var blocks: m.Blocks = .{};
    for (blocks_value.array.items) |item| {
        const tag = try enumeration(enum { component, track, via }, item);
        switch (tag) {
            inline else => |name| @field(blocks, @tagName(name)) = true,
        }
    }
    return .{ .rect = try rect(try get(value, "rect")), .face = try enumeration(m.RegionFace, try get(value, "face")), .blocks = blocks, .allow_nets = try identities(m.NetId, allocator, try get(value, "allow_nets")) };
}
fn feature(value: Json) Error!m.Feature {
    const kind = try enumeration(std.meta.Tag(m.Feature), try get(value, "kind"));
    switch (kind) {
        .component => try fields(value, &.{ "kind", "rect", "id", "face" }),
        .track => try fields(value, &.{ "kind", "rect", "net", "layer" }),
        .via => try fields(value, &.{ "kind", "rect", "net" }),
    }
    const bounds = try rect(try get(value, "rect"));
    return switch (kind) {
        .component => .{ .component = .{ .rect = bounds, .id = @fromBackingInt(try integer(u64, try get(value, "id"))), .face = try enumeration(m.Face, try get(value, "face")) } },
        .track => .{ .track = .{ .rect = bounds, .net = @fromBackingInt(try integer(u64, try get(value, "net"))), .layer = try enumeration(m.Layer, try get(value, "layer")) } },
        .via => .{ .via = .{ .rect = bounds, .net = @fromBackingInt(try integer(u64, try get(value, "net"))) } },
    };
}
