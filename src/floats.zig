//! Binary64 operations over explicit bit patterns, with strict rounding and canonical NaNs.
//! This is the compiler's constant evaluator. It folds a NaN to the canonical
//! pattern; the running program may produce other payloads, which no
//! observation point can tell apart (FLOAT-NAN-OBSERVED-1).
const std = @import("std");
const typed = @import("typed.zig");
pub const Error = error{ FloatConversion, InternalError };
/// Canonical quiet NaN: every observed NaN and every NaN the compiler folds.
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
/// Truncate a binary64 value toward zero into the integer type `ty`, failing with
/// `FloatConversion` for NaN, an infinity or a result outside that type's range. The
/// bounds are powers of two, so they are exact in binary64 and no integer conversion
/// runs before the range is known to hold.
pub fn toInteger(ty: typed.Type, input: u64) Error!i128 {
    @setFloatMode(.strict);
    const info = ty.integer() orelse return error.InternalError;
    const truncated = @trunc(@as(f64, @bitCast(input)));
    const exponent: i32 = info.bits - @intFromBool(info.signed);
    const upper = std.math.ldexp(@as(f64, 1.0), exponent);
    const lower = if (info.signed) -upper else 0.0;
    if (!std.math.isFinite(truncated) or truncated < lower or truncated >= upper) return error.FloatConversion;
    return @intFromFloat(truncated);
}
/// Execute a unary floating operation or a checked unsigned conversion.
pub fn unary(op: typed.UnaryOp, input: u64) Error!u64 {
    @setFloatMode(.strict);
    const value: f64 = @bitCast(input);
    const target: ?typed.Type = switch (op) {
        .f64_to_i8 => .i8,
        .f64_to_i16 => .i16,
        .f64_to_i32 => .i32,
        .f64_to_i64 => .i64,
        .f64_to_u8 => .u8,
        .f64_to_u16 => .u16,
        .f64_to_u32 => .u32,
        .f64_to_u64 => .u64,
        else => null,
    };
    if (target) |ty| {
        const converted = try toInteger(ty, input);
        return if (ty.integer().?.signed) @bitCast(@as(i64, @intCast(converted))) else @intCast(converted);
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
        .f64_sin => @sin(value),
        .f64_cos => @cos(value),
        else => return error.InternalError,
    };
    return bits(result);
}

/// Canonical quiet binary32 NaN: the narrow counterpart of `canonical_nan`.
pub const canonical_nan32: u32 = 0x7fc00000;

/// Round and canonicalize a binary32 result without exposing host NaN payload choices.
pub fn bits32(value: f32) u32 {
    return if (std.math.isNan(value)) canonical_nan32 else @bitCast(value);
}

/// Execute a binary32 operation; operands are the unsigned 32-bit representations.
pub fn binary32(op: typed.BinaryOp, left: u64, right: u64) Error!typed.Value {
    @setFloatMode(.strict);
    const a: f32 = @bitCast(@as(u32, @truncate(left)));
    const b: f32 = @bitCast(@as(u32, @truncate(right)));
    switch (op) {
        .f32_eq => return .{ .bool = a == b },
        .f32_lt => return .{ .bool = a < b },
        .f32_le => return .{ .bool = a <= b },
        else => {},
    }
    const result = switch (op) {
        .f32_add => a + b,
        .f32_sub => a - b,
        .f32_mul => a * b,
        .f32_div => a / b,
        else => return error.InternalError,
    };
    return typed.Value.number(.u32, bits32(result));
}

/// Execute a unary binary32 operation, a checked conversion to an integer, or a
/// conversion to or from binary64. The result is the unsigned pattern of its type:
/// a 32-bit pattern for `f32` results, a 64-bit one for `float`.
pub fn unary32(op: typed.UnaryOp, input: u64) Error!u64 {
    @setFloatMode(.strict);
    // Only the operations that read an f32 operand look at the low 32 bits; binary64 operands are converted below.
    const value: f32 = @bitCast(@as(u32, @truncate(input)));
    switch (op) {
        .f32_to_i8, .f32_to_i16, .f32_to_i32, .f32_to_i64, .f32_to_u8, .f32_to_u16, .f32_to_u32, .f32_to_u64 => {
            // Widening to binary64 is exact, so the checked range test runs on the same value.
            const wide: u64 = @bitCast(@as(f64, value));
            const target: typed.UnaryOp = switch (op) {
                .f32_to_i8 => .f64_to_i8,
                .f32_to_i16 => .f64_to_i16,
                .f32_to_i32 => .f64_to_i32,
                .f32_to_i64 => .f64_to_i64,
                .f32_to_u8 => .f64_to_u8,
                .f32_to_u16 => .f64_to_u16,
                .f32_to_u32 => .f64_to_u32,
                else => .f64_to_u64,
            };
            return unary(target, wide);
        },
        .f64_from_f32 => return bits(@as(f64, value)),
        .f32_from_f64 => return bits32(@floatCast(@as(f64, @bitCast(input)))),
        .f32_from_i64 => return bits32(@floatFromInt(@as(i64, @bitCast(input)))),
        .f32_from_u64 => return bits32(@floatFromInt(input)),
        .f32_sqrt => return bits32(@sqrt(value)),
        .f32_floor => return bits32(@floor(value)),
        .f32_ceil => return bits32(@ceil(value)),
        .f32_trunc => return bits32(@trunc(value)),
        .f32_abs => return bits32(@abs(value)),
        .f32_neg => return bits32(-value),
        else => return error.InternalError,
    }
}
