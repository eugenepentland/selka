//! Signature admission for process-local comparison of noncapturing callables.
const callables = @import("callables.zig");
const std = @import("std");
const symbolic = @import("symbolic_types.zig");
const typed = @import("typed.zig");

/// The builtin spelling shared by concrete and symbolic checking.
pub const name = "same_function";
/// A comparison whose operands are not compatible callable values.
pub const code = "E_FUNCTION_IDENTITY";
/// Describe the callable-only boundary without exposing native addresses.
pub const message = "same_function requires two compatible function values";

/// Accept callbacks related by the existing directional signature contract.
pub fn compatible(left: typed.Type, right: typed.Type, records: []const typed.Record) bool {
    const a = callables.signature(left, records) orelse return false;
    const b = callables.signature(right, records) orelse return false;
    return callables.assignable(a, b) or callables.assignable(b, a);
}

/// Admit the same relation before a template's type parameters are instantiated.
pub fn symbolicCompatible(left: symbolic.Value, right: symbolic.Value, catalog: @import("records.zig").Catalog) bool {
    const a = symbolicMutates(left, catalog) orelse return false;
    const b = symbolicMutates(right, catalog) orelse return false;
    if (!std.mem.eql(u16, a, b)) return false;
    return symbolic.callbackAssignable(left, right, catalog) or symbolic.callbackAssignable(right, left, catalog);
}

fn symbolicMutates(value: symbolic.Value, catalog: @import("records.zig").Catalog) ?[]const u16 {
    return switch (value) {
        .callback => |callback| callback.mutates,
        .concrete => |ty| (callables.signature(ty, catalog.records) orelse return null).mutates,
        else => null,
    };
}
