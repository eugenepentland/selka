//! Split an `f"..."` literal into its alternating literal chunks and interpolation holes.
//! Only the byte ranges are computed here; the parser builds the text nodes and parses the
//! holes with the ordinary expression grammar, so an interpolation is an ordinary expression.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

/// Stable diagnostic code for a malformed interpolated string literal.
pub const code = "E_FORMAT_STRING";

/// One piece of a format string: literal source bytes, a doubled brace, or an expression.
pub const Piece = union(enum) {
    /// Source range of literal bytes, still carrying their ordinary escapes.
    literal: source.Span,
    /// Source range of a `{{` or `}}` pair standing for one brace character.
    brace: source.Span,
    /// Source range between the braces of one interpolation.
    hole: source.Span,
};

/// Split the content of an `f"..."` literal, rejecting unmatched and empty braces.
/// The span covers the whole literal including its `f` prefix and both quotes.
pub fn split(allocator: std.mem.Allocator, src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error![]const Piece {
    var pieces: std.ArrayList(Piece) = .empty;
    errdefer pieces.deinit(allocator);
    const bytes = src.bytes;
    const stop = span.end - 1;
    var at = span.start + 2;
    var start = at;
    while (at < stop) {
        const byte = bytes[at];
        if (byte == '\\') {
            at += 2;
            continue;
        }
        if (byte != '{' and byte != '}') {
            at += 1;
            continue;
        }
        if (at + 1 < stop and bytes[at + 1] == byte) {
            if (at > start) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = at } });
            try pieces.append(allocator, .{ .brace = .{ .start = at, .end = at + 2 } });
            at += 2;
            start = at;
            continue;
        }
        if (byte == '}') return sink.fail(code, .{ .start = at, .end = at + 1 }, "unmatched '}' in a format string; write '}}' for a literal brace");
        if (at > start) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = at } });
        const inner = try hole(bytes, at + 1, stop, sink);
        if (inner.end == inner.start) return sink.fail(code, inner, "a format string interpolation needs an expression");
        try pieces.append(allocator, .{ .hole = inner });
        at = inner.end + 1;
        start = at;
    }
    if (at > start or pieces.items.len == 0) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = stop } });
    return pieces.toOwnedSlice(allocator);
}

/// Locate the closing brace of one interpolation, skipping nested brackets and literals.
fn hole(bytes: []const u8, from: usize, stop: usize, sink: *diagnostic.Sink) diagnostic.Error!source.Span {
    var depth: usize = 0;
    var at = from;
    while (at < stop) : (at += 1) {
        switch (bytes[at]) {
            '\\' => at += 1,
            '"', '\'' => at = quoted(bytes, at, stop),
            '(', '[', '{' => depth += 1,
            ')', ']' => depth -|= 1,
            '}' => {
                if (depth == 0) return .{ .start = from, .end = at };
                depth -= 1;
            },
            ':' => if (depth == 0) return sink.fail(
                code,
                .{ .start = at, .end = at + 1 },
                "format specifications are not supported; convert the value before interpolating it",
            ),
            else => {},
        }
    }
    return sink.fail(code, .{ .start = from - 1, .end = stop }, "unterminated interpolation in a format string");
}

fn quoted(bytes: []const u8, from: usize, stop: usize) usize {
    var at = from + 1;
    while (at < stop and bytes[at] != bytes[from]) : (at += 1) {
        if (bytes[at] == '\\') at += 1;
    }
    return @min(at, stop - 1);
}
