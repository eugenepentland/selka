//! Checked adapters between fixed guest byte arrays and borrowed host byte slices.
/// Failures returned by toOwnedBytes; callers must handle these boundary errors.
pub const ToOwnedBytesError = error{
    InternalError,
    OutOfMemory,
};
/// Failures returned by fromBytes; callers must handle these boundary errors.
pub const FromBytesError = error{
    InternalError,
    InvalidAggregateType,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
/// Validate a typed byte aggregate and allocate its contiguous host byte representation.
pub fn toOwnedBytes(allocator: std.mem.Allocator, value: typed.Value, ty: typed.Type, records: []const typed.Record) ToOwnedBytesError![]u8 {
    if (!typed.byteRequest(ty, records) or value != .aggregate or value.typeOf() != ty) return error.InternalError;
    const length = records[ty.recordIndex()].shape.array.?.length;
    if (value.aggregate.fields.len != length) return error.InternalError;
    const bytes = try allocator.alloc(u8, length);
    errdefer allocator.free(bytes);
    for (value.aggregate.fields, bytes) |element, *byte| {
        if (element.typeOf() != .u8) return error.InternalError;
        byte.* = std.math.cast(u8, try element.asInteger()) orelse return error.InternalError;
    }
    return bytes;
}
/// Allocate a typed byte aggregate from host bytes using the supplied nominal schema.
pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8, ty: typed.Type, records: []const typed.Record) FromBytesError!typed.Value {
    if (!typed.byteRequest(ty, records) or records[ty.recordIndex()].shape.array.?.length != bytes.len) return error.InternalError;
    const fields = try allocator.alloc(typed.Value, bytes.len);
    defer allocator.free(fields);
    for (bytes, fields) |byte, *field| field.* = typed.Value.number(.u8, byte);
    return typed.Value.create(allocator, ty, fields);
}

/// Copy an acquisition request without borrowing guest backing into a provider call.
pub fn acquisitionBytes(allocator: std.mem.Allocator, value: typed.Value, ty: typed.Type, records: []const typed.Record) ToOwnedBytesError![]u8 {
    if (typed.byteRequest(ty, records)) return toOwnedBytes(allocator, value, ty, records);
    if (!typed.acquisitionBytes(ty, records)) return error.InternalError;
    if (!value.isOwned(.resource) or value.typeOf() != ty) return error.InternalError;
    const resource = value.owned.resource;
    const info = resource.store.bufferInfo(resource.owner) catch return error.InternalError;
    if (info.element_type != .u8) return error.InternalError;
    const bytes = try allocator.alloc(u8, info.length);
    errdefer allocator.free(bytes);
    for (bytes, 0..) |*byte, i| {
        const item = resource.store.readOwner(resource.owner, i) catch return error.InternalError;
        defer item.release(allocator);
        if (item.typeOf() != .u8) return error.InternalError;
        byte.* = std.math.cast(u8, try item.asInteger()) orelse return error.InternalError;
    }
    return bytes;
}
