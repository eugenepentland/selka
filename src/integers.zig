//! Guest width bounds, independent of host optimization and physical storage width.
const typed = @import("typed.zig");
pub const Error = error{ Overflow, DivisionByZero, InternalError };

pub fn cast(ty: typed.Type, value: i128) Error!typed.Value {
    if (!ty.isInteger()) return error.InternalError;
    if (!ty.fits(value)) return error.Overflow;
    return typed.Value.number(ty, value);
}

pub fn binary(ty: typed.Type, op: typed.BinaryOp, left: i128, right: i128) Error!typed.Value {
    if (!ty.isInteger() or !ty.fits(left) or !ty.fits(right)) return error.InternalError;
    switch (op) {
        .eq => return .{ .bool = left == right },
        .ne => return .{ .bool = left != right },
        .lt => return .{ .bool = left < right },
        .le => return .{ .bool = left <= right },
        .gt => return .{ .bool = left > right },
        .ge => return .{ .bool = left >= right },
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
        .logical_and, .logical_or => return error.InternalError,
    }
}
