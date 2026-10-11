//! Existing bounded named-field codec reused by body request and reply schemas.
const std = @import("std");
const logical = @import("parser_value.zig");
/// Malformed logical values or allocation failure.
pub const Error = logical.Error;
/// Logical payload and outer frame share the existing sixty-four MiB ceiling.
pub const wire_limit = logical.value_wire_limit;
/// Encode complete logical values without native semantic preprocessing.
pub fn encode(a: std.mem.Allocator, comptime T: type, item: T, magic: []const u8) Error![]u8 {
    return logical.encodeTreeProfile(a, T, item, magic, .body);
}
/// Return independent arena-owned logical values before domain validation.
pub fn decode(a: std.mem.Allocator, comptime T: type, bytes: []const u8, magic: []const u8) Error!logical.Owned(T) {
    return logical.decodeTreeProfile(T, a, bytes, magic, .body);
}
