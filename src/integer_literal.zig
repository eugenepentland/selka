//! Shared integer spelling and signed-minimum validation for concrete and generic checks.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Parsed scalar type and nonnegative literal magnitude.
pub const Literal = struct { ty: typed.Type, value: i128 };
/// Validate the suffix/range, optionally allowing a directly negated minimum magnitude.
pub fn parse(src: source.Source, span: source.Span, allow_minimum: bool, sink: *diagnostic.Sink) diagnostic.Error!Literal {
    return parseExpected(src, span, allow_minimum, null, sink);
}

/// Unsuffixed constants adopt a representable expected integer type; explicit suffixes stay exact.
pub fn parseExpected(src: source.Source, span: source.Span, allow_minimum: bool, expected: ?typed.Type, sink: *diagnostic.Sink) diagnostic.Error!Literal {
    const text = src.text(span);
    var digits: usize = 0;
    while (digits < text.len and std.ascii.isDigit(text[digits])) digits += 1;
    const literal_type: typed.Type = if (digits == text.len) (if (expected != null and expected.?.isInteger()) expected.? else .i64) else typed.Type.fromName(text[digits..]) orelse
        return sink.fail("E_INTEGER_SUFFIX", span, "unknown integer suffix; use i8/i16/i32/i64 or u8/u16/u32/u64");
    if (!literal_type.isInteger()) return sink.fail("E_INTEGER_SUFFIX", span, "integer suffix must name an integer type");
    const magnitude = std.fmt.parseUnsigned(u128, text[0..digits], 10) catch
        return sink.fail("E_INTEGER_RANGE", span, "integer literal magnitude is too large");
    const maximum: u128 = @intCast(literal_type.max() + @as(i128, if (allow_minimum and literal_type.integer().?.signed) 1 else 0));
    if (magnitude > maximum) return sink.fail("E_INTEGER_RANGE", span, "integer literal does not fit its type; signed minimum magnitudes must be directly negated");
    return .{ .ty = literal_type, .value = @intCast(magnitude) };
}
