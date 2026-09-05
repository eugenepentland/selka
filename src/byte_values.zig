//! Checked adapters between fixed guest byte arrays and borrowed host byte slices.
const std = @import("std");
const typed = @import("typed.zig");
pub fn toOwnedBytes(allocator: std.mem.Allocator, value: typed.Value, ty: typed.Type, records: []const typed.Record) ![]u8 {
    if (!typed.byteRequest(ty, records) or value != .aggregate or value.typeOf() != ty) return error.InternalError;
    const length = records[ty.recordIndex()].array.?.length;
    if (value.aggregate.fields.len != length) return error.InternalError;
    const bytes = try allocator.alloc(u8, length);
    errdefer allocator.free(bytes);
    for (value.aggregate.fields, bytes) |element, *byte| {
        if (element.typeOf() != .u8) return error.InternalError;
        byte.* = std.math.cast(u8, try element.asInteger()) orelse return error.InternalError;
    }
    return bytes;
}
pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8, ty: typed.Type, records: []const typed.Record) !typed.Value {
    if (!typed.byteRequest(ty, records) or records[ty.recordIndex()].array.?.length != bytes.len) return error.InternalError;
    const fields = try allocator.alloc(typed.Value, bytes.len);
    defer allocator.free(fields);
    for (bytes, fields) |byte, *field| field.* = typed.Value.number(.u8, byte);
    return typed.Value.create(allocator, ty, fields);
}
