//! The fixed byte layout one trial invocation travels on, in both directions.
//! The guest's `wire`, `request` and `observe` modules decode and produce exactly
//! these positions; nothing here interprets a board, only its octets.
const std = @import("std");
const m = @import("model.zig");
/// A slot is one presence byte and eight little-endian octets.
const slot = 9;
/// A rectangle is four signed eight-octet fields.
const rectangle = 32;
/// A region adds a face, three block flags and four admitted-net slots.
const region_bytes = 73;
/// A feature adds a family byte and one face or layer byte.
const feature_bytes = 43;
/// Where each bounded collection starts inside one request.
const start = .{ .outline = 0, .components = 32, .nets = 68, .regions = 104, .features = 396 };
/// Every request is exactly this wide, so no field position is ever computed twice.
pub const request_bytes = 740;
/// One complete request, owned by the caller for as long as it needs it.
pub const Request = [request_bytes]u8;
/// An observation that is truncated, over-long or names an undeclared case.
pub const Error = error{InvalidObservation};

fn unsigned(out: []u8, value: u64) void {
    std.mem.writeInt(u64, out[0..8], value, .little);
}
fn signed(out: []u8, value: m.Micrometres) void {
    std.mem.writeInt(i64, out[0..8], @backingInt(value), .little);
}
fn rect(out: []u8, value: m.Rect) void {
    signed(out[0..8], value.x);
    signed(out[8..16], value.y);
    signed(out[16..24], value.width);
    signed(out[24..32], value.height);
}
fn identity(out: []u8, value: u64) void {
    out[0] = 1;
    unsigned(out[1..9], value);
}
fn admitted(out: []u8, nets: []const m.NetId) void {
    for (nets, 0..) |net, index| identity(out[index * slot ..][0..slot], @backingInt(net));
}
fn region(out: []u8, value: m.Region) void {
    out[0] = 1;
    rect(out[1..33], value.rect);
    out[33] = @backingInt(value.face);
    out[34] = @intFromBool(value.blocks.component);
    out[35] = @intFromBool(value.blocks.track);
    out[36] = @intFromBool(value.blocks.via);
    admitted(out[37..region_bytes], value.allow_nets);
}
fn feature(out: []u8, value: m.Feature) void {
    out[0] = 1;
    out[1] = @backingInt(std.meta.activeTag(value));
    rect(out[2..34], m.rectangle(value));
    switch (value) {
        .component => |item| {
            unsigned(out[34..42], @backingInt(item.id));
            out[42] = @backingInt(item.face);
        },
        .track => |item| {
            unsigned(out[34..42], @backingInt(item.net));
            out[42] = @backingInt(item.layer);
        },
        .via => |item| unsigned(out[34..42], @backingInt(item.net)),
    }
}
/// Lay one bounded board out at the positions the guest reads it from.
/// Absent slots stay zeroed, which is exactly how the guest reads "none".
pub fn encode(board: m.Board, out: *Request) void {
    @memset(out, 0);
    rect(out[start.outline..][0..rectangle], board.outline);
    for (board.components, 0..) |id, index| identity(out[start.components + index * slot ..][0..slot], @backingInt(id));
    for (board.nets, 0..) |id, index| identity(out[start.nets + index * slot ..][0..slot], @backingInt(id));
    for (board.regions, 0..) |value, index| region(out[start.regions + index * region_bytes ..][0..region_bytes], value);
    for (board.features, 0..) |value, index| feature(out[start.features + index * feature_bytes ..][0..feature_bytes], value);
}
fn count(bytes: []const u8) u64 {
    return std.mem.readInt(u64, bytes[0..8], .little);
}
fn declared(comptime T: type, code: u8) Error!T {
    if (code >= @typeInfo(T).@"enum".field_names.len) return error.InvalidObservation;
    return @fromBackingInt(@intCast(code));
}
fn violation(bytes: []const u8) Error!?m.Violation {
    if (bytes[0] == 0) return null;
    if (bytes[0] != 1 or bytes[10] > 1) return error.InvalidObservation;
    return .{
        .feature = count(bytes[1..9]),
        .kind = try declared(m.ViolationKind, bytes[9]),
        .region = if (bytes[10] == 1) count(bytes[11..19]) else null,
    };
}
/// Read back exactly what the guest published, or reject the whole observation.
/// A report is a count and an optional first violation; a failure is one ordinal.
pub fn decode(bytes: []const u8) Error!m.Outcome {
    if (bytes.len == 0) return error.InvalidObservation;
    if (bytes[0] == 0) {
        if (bytes.len != 28) return error.InvalidObservation;
        return .{ .ok = .{ .violations = count(bytes[1..9]), .first = try violation(bytes[9..28]) } };
    }
    if (bytes.len != 2) return error.InvalidObservation;
    if (bytes[0] == 1) return .{ .err = .{ .input = try declared(m.InputProblem, bytes[1]) } };
    if (bytes[0] == 2) return .{ .err = .{ .geometry = try declared(m.GeometryFailure, bytes[1]) } };
    return error.InvalidObservation;
}
