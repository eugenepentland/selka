//! Shared integer spelling and signed-minimum validation for concrete and generic checks.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const number_literal = @import("number_literal.zig");
/// Parsed scalar type and nonnegative literal magnitude.
pub const Literal = struct { ty: typed.Type, value: i128 };
/// Validate the suffix/range, optionally allowing a directly negated minimum magnitude.
pub fn parse(src: source.Source, span: source.Span, allow_minimum: bool, sink: *diagnostic.Sink) diagnostic.Error!Literal {
    return parseExpected(src, span, allow_minimum, null, sink);
}

/// Unsuffixed constants adopt a representable expected integer type; explicit suffixes stay exact.
/// The spelling may be decimal, `0x`, `0o` or `0b`, with underscores between digits.
pub fn parseExpected(src: source.Source, span: source.Span, allow_minimum: bool, expected: ?typed.Type, sink: *diagnostic.Sink) diagnostic.Error!Literal {
    const parts = switch (number_literal.integer(src.text(span))) {
        .ok => |parts| parts,
        .bad => |problem| return sink.fail(problem.code, span, problem.message),
    };
    const literal_type: typed.Type = if (parts.suffix.len == 0) (if (expected != null and expected.?.isInteger()) expected.? else .i64) else typed.Type.fromName(parts.suffix) orelse
        return sink.fail(number_literal.suffix_code, span, suffixMessage(parts));
    if (!literal_type.isInteger()) return sink.fail(number_literal.suffix_code, span, "integer suffix must name an integer type");
    const magnitude = number_literal.magnitude(parts) orelse
        return sink.fail(number_literal.range_code, span, "integer literal magnitude is too large");
    const maximum: u128 = @intCast(literal_type.max() + @as(i128, if (allow_minimum and literal_type.integer().?.signed) 1 else 0));
    if (magnitude > maximum) return sink.fail(number_literal.range_code, span, "integer literal does not fit its type; signed minimum magnitudes must be directly negated");
    return .{ .ty = literal_type, .value = @intCast(magnitude) };
}

fn suffixMessage(parts: number_literal.Integer) []const u8 {
    if (parts.base == 10 and (std.mem.eql(u8, parts.suffix, "j") or std.mem.eql(u8, parts.suffix, "J"))) return number_literal.imaginary_message;
    return "unknown integer suffix; use i8/i16/i32/i64 or u8/u16/u32/u64";
}

/// Whether an integer token carries no width suffix, so its type comes from context.
/// A float spelling is never such a literal.
pub fn unsuffixed(text: []const u8) bool {
    if (number_literal.isFloat(text)) return false;
    return switch (number_literal.integer(text)) {
        .ok => |parts| parts.suffix.len == 0,
        .bad => false,
    };
}
