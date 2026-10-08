//! Checked adapters between fixed guest byte arrays and borrowed host byte slices.
/// Failures returned by toOwnedBytes; callers must handle these boundary errors.
pub const ToOwnedBytesError = error{
    InternalError,
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

/// Copy an acquisition request without borrowing guest backing into a provider call.
pub fn acquisitionBytes(allocator: std.mem.Allocator, value: typed.Value, ty: typed.Type, records: []const typed.Record) ToOwnedBytesError![]u8 {
    if (!typed.acquisitionBytes(ty, records)) return error.InternalError;
    return toOwnedBytes(allocator, value, ty, records);
}
