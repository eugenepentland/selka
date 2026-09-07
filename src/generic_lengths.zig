//! Constant generic length arguments are bounded values, distinct from type identities.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Portable specialization-length bound independent of host pointer width.
pub const max_length: usize = 1048576;
/// Parse an unsuffixed decimal length within the specialization bound.
pub fn literal(src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!usize {
    const text = src.text(span);
    if (text.len == 0) return sink.fail(diagnostic.generic_length, span, "const length requires an unsuffixed decimal integer");
    for (text) |digit| if (!std.ascii.isDigit(digit)) return sink.fail(diagnostic.generic_length, span, "const length requires an unsuffixed decimal integer");
    const value = std.fmt.parseInt(u64, text, 10) catch return sink.fail(diagnostic.generic_length, span, "const length is outside the supported range");
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
