//! Token ranges of retired expressions, excluding parenthesized wrappers.
const std = @import("std");
const lex = @import("lexer.zig");
const Span = @import("source.zig").Span;

/// Locate the expression keyword inside its possibly widened AST span.
pub fn keyword(tokens: []const lex.Token, span: Span, tag: lex.Tag) ?Span {
    for (tokens) |token| {
        if (token.span.start < span.start) continue;
        if (token.span.end > span.end) break;
        if (token.tag == tag) return token.span;
    }
    return null;
}

/// Locate the identifier spelling `word` inside its possibly widened AST span.
/// A contextual keyword is an identifier, so the token tag alone cannot find it.
pub fn word(tokens: []const lex.Token, bytes: []const u8, span: Span, spelling: []const u8) ?Span {
    for (tokens) |token| {
        if (token.span.start < span.start) continue;
        if (token.span.end > span.end) break;
        if (token.tag != .ident) continue;
        if (std.mem.eql(u8, bytes[token.span.start..token.span.end], spelling)) return token.span;
    }
    return null;
}

/// Find the argument opener after a possibly generic function/type anchor.
pub fn callOpen(tokens: []const lex.Token, anchor: usize) ?Span {
    var brackets: usize = 0;
    for (tokens) |token| {
        if (token.span.start < anchor) continue;
        switch (token.tag) {
            .lbracket => brackets += 1,
            .rbracket => brackets -|= 1,
            .lparen => if (brackets == 0) {
                return token.span;
            },
            else => {},
        }
    }
    return null;
}

/// Find the actual call close after a name/type anchor, preserving grouping.
pub fn callClose(tokens: []const lex.Token, anchor: usize) ?usize {
    const open = callOpen(tokens, anchor) orelse return null;
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.span.start < open.start) continue;
        if (token.tag == .lparen) depth += 1;
        if (token.tag == .rparen) {
            if (depth == 1) return token.span.start;
            depth -= 1;
        }
    }
    return null;
}
