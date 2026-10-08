//! Compile-time scalar values and the type identities they carry.
const std = @import("std");
const identity = @import("type_identity.zig");
/// The checked program's type identities (`type_identity.zig`).
pub const Type = identity.Type;

/// A compile-time scalar value: what constant evaluation and folding produce.
pub const Value = union(enum) {
    unit,
    i64: i64,
    bool: bool,
    integer: struct { ty: Type, value: i128 },

    /// Return the scalar type carried by this value.
    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .unit => .unit,
            .i64 => .i64,
            .bool => .bool,
            .integer => |n| n.ty,
        };
    }

    /// Construct the representation of a previously range-checked integer.
    pub fn number(ty: Type, value: i128) Value {
        std.debug.assert(ty.isInteger());
        std.debug.assert(ty.fits(value));
        return if (ty == .i64) .{ .i64 = @intCast(value) } else .{ .integer = .{ .ty = ty, .value = value } };
    }
    /// Extract a mathematical integer, rejecting noninteger representations.
    pub fn asInteger(self: Value) error{InternalError}!i128 {
        return switch (self) {
            .i64 => |n| n,
            .integer => |n| n.value,
            else => error.InternalError,
        };
    }
};

/// Managed collection family and shape (`type_identity.zig`).
pub const ManagedKind = identity.ManagedKind;
/// Collection shape metadata of a managed record (`type_identity.zig`).
pub const CollectionShape = identity.CollectionShape;
