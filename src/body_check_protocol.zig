//! Authenticated request correlation for one scalar body-check batch.
const std = @import("std");
const value = @import("body_check_value.zig");
const wire = @import("body_check_wire_io.zig");
const validate = @import("body_check_validate.zig");
const digest = @import("component_digest.zig");
/// Complete raw body inputs.
pub const Input = value.Input;
/// Maximum complete framed exchange size.
pub const reply_limit = wire.wire_limit;
/// Transport and domain validation failures are host errors.
pub const Error = wire.Error;
/// Owned framed request and its exact correlation identity.
pub const Request = struct { bytes: []u8, identity: [40]u8 };
/// Validate and encode one raw batch without checking its bodies natively.
pub fn request(a: std.mem.Allocator, input: Input, nonce: [8]u8) Error!Request {
    try validate.input(a, input);
    const payload = try wire.encode(a, Input, input, "SLKBKI01");
    defer a.free(payload);
    const bytes = try frame(a, payload, 0, @splat(0));
    @memcpy(bytes[24..32], &nonce);
    const hash = digest.hash(payload);
    @memcpy(bytes[32..64], &hash);
    return .{ .bytes = bytes, .identity = bytes[24..64].* };
}
/// Decode independent reply storage and validate every structural association.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: [40]u8, input: Input) Error!value.Decoded {
    if (bytes.len < 80 or bytes.len > reply_limit) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[0..8], "SLKBCK01")) return error.ComponentProtocol;
    if (get(bytes, 8) != 1 or get(bytes, 12) != 6 or get(bytes, 16) != 1) return error.ComponentProtocol;
    if (get(bytes, 20) != bytes.len - 64 or !std.mem.eql(u8, bytes[24..64], &identity)) return error.ComponentProtocol;
    var decoded = try wire.decode(a, value.Outcome, bytes[64..], "SLKBKR01");
    errdefer decoded.arena.deinit();
    try validate.input(a, input);
    try validate.outcome(a, input, decoded.value);
    return .{ .arena = decoded.arena, .outcome = decoded.value };
}
/// Encode an oracle or test reply using the same logical schema as the producer.
pub fn response(a: std.mem.Allocator, outcome: value.Outcome, identity: [40]u8) Error![]u8 {
    const payload = try wire.encode(a, value.Outcome, outcome, "SLKBKR01");
    defer a.free(payload);
    return frame(a, payload, 1, identity);
}
fn frame(a: std.mem.Allocator, payload: []const u8, direction: u32, identity: [40]u8) Error![]u8 {
    if (payload.len > reply_limit - 64) return error.ComponentProtocol;
    const bytes = try a.alloc(u8, payload.len + 64);
    @memset(bytes[0..64], 0);
    @memcpy(bytes[0..8], "SLKBCK01");
    put(bytes, 8, 1);
    put(bytes, 12, 6);
    put(bytes, 16, direction);
    put(bytes, 20, @intCast(payload.len));
    @memcpy(bytes[24..64], &identity);
    @memcpy(bytes[64..], payload);
    return bytes;
}
fn put(bytes: []u8, at: usize, number: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], number, .little);
}
fn get(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
