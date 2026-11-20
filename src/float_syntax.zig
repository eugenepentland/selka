//! Decimal floating syntax without changing scalar wire identities.
const std = @import("std");
const number_literal = @import("number_literal.zig");

/// Decimal points or exponent markers distinguish floating tokens from integer suffixes;
/// a `0x`, `0o` or `0b` spelling is always an integer, whatever letters it holds.
pub fn isLiteral(text: []const u8) bool {
    return number_literal.isFloat(text);
}

/// Whether a floating token is a binary32 literal: a float spelling ending in the `f32` suffix.
pub fn isF32Literal(text: []const u8) bool {
    return isLiteral(text) and std.mem.endsWith(u8, text, number_literal.f32_suffix);
}
