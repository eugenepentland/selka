//! Closed integer and binary64 typed graph rules; source numeric decisions stay in Selka.
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");

/// Every language integer width, Boolean and Unit are admitted numeric leaves.
pub fn scalar(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}
/// Retained synthetic binary64 authority, distinct from every source-defined domain.
pub fn floating(catalog: value.Catalog, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= catalog.records.len) return false;
    return @import("numeric_surface.zig").isFloat(ty, catalog.records);
}
/// Full-width mathematical constants remain bounded by their declared integer type.
pub fn integer(ty: typed.Type, number: i128) bool {
    return ty.isInteger() and ty.fits(number);
}
/// Integer width conversion plus the established Boolean-to-int representation.
pub fn cast(target: typed.Type, input: typed.Type) bool {
    return (target.isInteger() and input.isInteger()) or (target == .i64 and input == .bool);
}
/// Exact input/output types of all native numeric unary opcodes.
pub fn unary(op: typed.UnaryOp, target: typed.Type, input: typed.Type) bool {
    return switch (op) {
        .neg => input.isInteger() and target == input,
        .not => input == .bool and target == .bool,
        .f64_from_i64 => input == .i64 and target == .u64,
        .f64_to_i64 => input == .u64 and target == .i64,
        .f64_to_i8 => input == .u64 and target == .i8,
        .f64_to_i16 => input == .u64 and target == .i16,
        .f64_to_i32 => input == .u64 and target == .i32,
        .f64_to_u8 => input == .u64 and target == .u8,
        .f64_to_u16 => input == .u64 and target == .u16,
        .f64_to_u32 => input == .u64 and target == .u32,
        else => input == .u64 and target == .u64,
    };
}
/// Integer operators retain width; binary64 operates on authenticated u64 bit payloads.
pub fn binary(op: typed.BinaryOp, target: typed.Type, input: typed.Type) bool {
    return switch (op) {
        .logical_and, .logical_or => input == .bool and target == .bool,
        .f64_eq, .f64_lt, .f64_le => input == .u64 and target == .bool,
        .f64_add, .f64_sub, .f64_mul, .f64_div => input == .u64 and target == .u64,
        .eq, .ne, .lt, .le, .gt, .ge => input.isInteger() and target == .bool,
        else => input.isInteger() and target == input,
    };
}
