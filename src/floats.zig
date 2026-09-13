//! Binary64 operations over explicit bit patterns, with strict rounding and canonical NaNs.
const std = @import("std");
const typed = @import("typed.zig");
pub const Error = error{ FloatConversion, InternalError };
/// Canonical quiet NaN used for every floating operation result.
pub const canonical_nan: u64 = 0x7ff8000000000000;
/// Round and canonicalize a binary64 result without exposing host NaN payload choices.
pub fn bits(value: f64) u64 {
    return if (std.math.isNan(value)) canonical_nan else @bitCast(value);
}
/// Execute a binary floating operation; operands are unsigned binary64 representations.
pub fn binary(op: typed.BinaryOp, left: u64, right: u64) Error!typed.Value {
    @setFloatMode(.strict);
    const a: f64 = @bitCast(left);
    const b: f64 = @bitCast(right);
    switch (op) {
        .f64_eq => return .{ .bool = a == b },
        .f64_lt => return .{ .bool = a < b },
        .f64_le => return .{ .bool = a <= b },
        else => {},
    }
    const result = switch (op) {
        .f64_add => a + b,
        .f64_sub => a - b,
        .f64_mul => a * b,
        .f64_div => a / b,
        else => return error.InternalError,
    };
    return typed.Value.number(.u64, bits(result));
}
/// Execute a unary floating operation or a checked unsigned conversion.
pub fn unary(op: typed.UnaryOp, input: u64) Error!u64 {
    @setFloatMode(.strict);
    const value: f64 = @bitCast(input);
    if (op == .f64_to_i64) {
        const truncated = @trunc(value);
        if (!std.math.isFinite(truncated) or truncated < -9223372036854775808.0 or truncated >= 9223372036854775808.0) return error.FloatConversion;
        return @bitCast(@as(i64, @intFromFloat(truncated)));
    }
    if (op == .f64_to_u64) {
        const truncated = @trunc(value);
        if (!std.math.isFinite(truncated) or truncated < 0 or truncated >= 18446744073709551616.0) return error.FloatConversion;
        return @intFromFloat(truncated);
    }
    const result: f64 = switch (op) {
        .f64_sqrt => @sqrt(value),
        .f64_floor => @floor(value),
        .f64_ceil => @ceil(value),
        .f64_trunc => @trunc(value),
        .f64_abs => @abs(value),
        .f64_neg => -value,
        .f64_from_u64 => @floatFromInt(input),
        .f64_from_i64 => @floatFromInt(@as(i64, @bitCast(input))),
        else => return error.InternalError,
    };
    return bits(result);
}
