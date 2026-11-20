//! Constant generic length arguments are bounded values, distinct from type identities.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const number_literal = @import("number_literal.zig");
/// Portable specialization-length bound independent of host pointer width.
pub const max_length: usize = 1048576;
/// Parse an unsuffixed integer length (`16`, `0x10`, `1_024`) within the specialization bound.
pub fn literal(src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!usize {
    const value = switch (number_literal.count(src.text(span))) {
        .ok => |value| value,
        .bad => |message| return sink.fail(diagnostic.generic_length, span, message),
    };
    if (value > max_length) return sink.fail(diagnostic.generic_length, span, "const length exceeds 1048576 elements");
    return @intCast(value);
}
/// Resolve a literal or a forwarded constant parameter from one concrete specialization.
pub fn resolve(src: source.Source, span: source.Span, parameters: []const ast.TypeParameter, values: []const ?usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    for (parameters, 0..) |parameter, i| {
        if (!std.mem.eql(u8, src.text(parameter.name), src.text(span))) continue;
        if (!parameter.constant_length or i >= values.len) return sink.fail(diagnostic.generic_length, span, "expected a constant length argument, not a type parameter");
        return values[i] orelse error.InternalError;
    }
    return literal(src, span, sink);
}
