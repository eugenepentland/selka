//! A multiple-of-divisor bias for the whole previously guarded signed range.
const std = @import("std");

/// Every admitted dividend has magnitude at most this bound; adding `addend`
/// maps its complete signed interval into u64 without wrapping mathematically.
pub const Plan = struct { bound: u64, divisor: u64, addend: u64 };

/// Evaluate the existing conservative coefficient * 2^(bits * degree) bound.
/// Optional proof refusal never changes the old guard's leaf bound.
pub fn magnitude(coefficient: u64, degree: u8, bits: u6) ?u64 {
    const shift = @as(u32, bits) * degree;
    if (shift >= 128) return null;
    const power = @as(u128, 1) << @intCast(shift);
    const product = std.math.mul(u128, coefficient, power) catch return null;
    if (product > std.math.maxInt(i64)) return null;
    return @intCast(product);
}

/// `B = ceil(M/d) * d`, with checked mathematical arithmetic throughout.
/// For -M <= x <= M, floor_mod(x,d) equals unsigned_rem(x+B,d).
pub fn plan(bound: u64, divisor: u64) ?Plan {
    if (bound > std.math.maxInt(i64) or divisor == 0 or divisor > std.math.maxInt(i64)) return null;
    const rounded = std.math.add(u128, bound, @as(u128, divisor) - 1) catch return null;
    const multiple = std.math.mul(u128, rounded / divisor, divisor) catch return null;
    const upper = std.math.add(u128, bound, multiple) catch return null;
    if (multiple > std.math.maxInt(u64) or upper > std.math.maxInt(u64)) return null;
    return .{ .bound = bound, .divisor = divisor, .addend = @intCast(multiple) };
}
