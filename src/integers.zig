//! Guest width bounds, independent of host optimization and physical storage width.
const typed = @import("typed.zig");
pub const Error = error{ Overflow, DivisionByZero, InvalidShift, FloatConversion, InternalError };

/// Construct an integer value only when the mathematical value fits the destination width.
pub fn cast(ty: typed.Type, value: i128) Error!typed.Value {
    if (!ty.isInteger()) return error.InternalError;
    if (!ty.fits(value)) return error.Overflow;
    return typed.Value.number(ty, value);
}

/// Evaluate checked integer arithmetic and report overflow or invalid division.
pub fn binary(ty: typed.Type, op: typed.BinaryOp, left: i128, right: i128) Error!typed.Value {
    if (!ty.isInteger()) return error.InternalError;
    if (!ty.fits(left) or !ty.fits(right)) return error.InternalError;
    switch (op) {
        .eq => return .{ .bool = left == right },
        .ne => return .{ .bool = left != right },
        .lt => return .{ .bool = left < right },
        .le => return .{ .bool = left <= right },
        .gt => return .{ .bool = left > right },
        .ge => return .{ .bool = left >= right },
        .floor_div, .floor_rem => {
            if (right == 0) return error.DivisionByZero;
            const quotient = @divFloor(left, right);
            return cast(ty, if (op == .floor_div) quotient else left - quotient * right);
        },
        .div, .rem => {
            if (right == 0) return error.DivisionByZero;
            // Guest integers are at most 64 bits; i128 division cannot overflow.
            return cast(ty, if (op == .div) @divTrunc(left, right) else @rem(left, right));
        },
        .add, .sub, .mul => {
            const result = switch (op) {
                .add => @addWithOverflow(left, right),
                .sub => @subWithOverflow(left, right),
                .mul => @mulWithOverflow(left, right),
                else => unreachable,
            };
            // u64 multiplication can overflow the signed i128 intermediate, but
            // any such product is necessarily outside the guest u64 range too.
            if (result[1] != 0) return error.Overflow;
            return cast(ty, result[0]);
        },
        .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .wrapping_add, .wrapping_sub, .wrapping_mul, .saturating_add, .saturating_sub, .saturating_mul => return extended(ty, op, left, right),
        .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => {
            if (ty != .u64) return error.InternalError;
            return @import("floats.zig").binary(op, @intCast(left), @intCast(right));
        },
        .logical_and, .logical_or => return error.InternalError,
    }
}

fn extended(ty: typed.Type, op: typed.BinaryOp, left: i128, right: i128) Error!typed.Value {
    const info = ty.integer().?;
    const modulus: i128 = @as(i128, 1) << info.bits;
    const mask: u128 = @intCast(modulus - 1);
    const a: u128 = @as(u128, @bitCast(left)) & mask;
    const b: u128 = @as(u128, @bitCast(right)) & mask;
    const result: i128 = switch (op) {
        .bit_and => @intCast(a & b),
        .bit_or => @intCast(a | b),
        .bit_xor => @intCast(a ^ b),
        .shift_left, .shift_right => blk: {
            if (right < 0 or right >= info.bits) return error.InvalidShift;
            const count: u7 = @intCast(right);
            break :blk if (op == .shift_left) @intCast((a << count) & mask) else left >> count;
        },
        .wrapping_add => left + right,
        .wrapping_sub => left - right,
        .wrapping_mul => @intCast((a * b) & mask),
        .saturating_add => return typed.Value.number(ty, @min(ty.max(), @max(ty.min(), left + right))),
        .saturating_sub => return typed.Value.number(ty, @min(ty.max(), @max(ty.min(), left - right))),
        .saturating_mul => {
            const product = @mulWithOverflow(left, right);
            if (product[1] != 0) return typed.Value.number(ty, ty.max());
            return typed.Value.number(ty, @min(ty.max(), @max(ty.min(), product[0])));
        },
        else => return error.InternalError,
    };
    const wrapped = @mod(result, modulus);
    return typed.Value.number(ty, if (info.signed and wrapped > ty.max()) wrapped - modulus else wrapped);
}
