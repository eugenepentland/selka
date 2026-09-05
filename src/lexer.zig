//! ASCII tokenization; keyword classification does not depend on semantic scope.
const std = @import("std");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
pub const Tag = enum {
    eof,
    ident,
    integer,
    kw_fn,
    kw_enum,
    kw_union,
    kw_match,
    kw_domain,
    kw_private,
    kw_wrap,
    kw_unwrap,
    kw_struct,
    kw_conversion,
    kw_new,
    kw_update,
    kw_replace,
    kw_len,
    kw_return,
    kw_let,
    kw_mut,
    kw_true,
    kw_false,
    kw_i64,
    kw_i8,
    kw_i16,
    kw_i32,
    kw_u8,
    kw_u16,
    kw_u32,
    kw_u64,
    kw_cast,
    kw_bool,
    kw_if,
    kw_else,
    kw_while,
    kw_discard,
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    arrow,
    fat_arrow,
    semicolon,
    colon,
    comma,
    dot,
    plus,
    minus,
    star,
    slash,
    percent,
    and_and,
    or_or,
    plus_equal,
    minus_equal,
    equal,
    eq_eq,
    bang,
    bang_eq,
    lt,
    le,
    gt,
    ge,
};
pub const Token = struct { tag: Tag, span: Span };
fn keyword(word: []const u8) Tag {
    const words = .{ "fn", "return", "let", "mut", "true", "false", "i64", "bool", "if", "else", "while", "discard", "struct", "new", "update", "conversion", "i8", "i16", "i32", "u8", "u16", "u32", "u64", "cast", "replace", "len", "domain", "private", "wrap", "unwrap", "enum", "union", "match" };
    inline for (words) |w| {
        if (std.mem.eql(u8, word, w)) return @field(Tag, "kw_" ++ w);
    }
    return .ident;
}
pub fn lex(allocator: std.mem.Allocator, bytes: []const u8, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const ch = bytes[i];
        if (std.ascii.isWhitespace(ch)) {
            i += 1;
            continue;
        }
        if (ch == '/' and i + 1 < bytes.len and bytes[i + 1] == '/') {
            while (i < bytes.len and bytes[i] != '\n') i += 1;
            continue;
        }
        const tag: Tag = blk: {
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                i += 1;
                while (i < bytes.len and (std.ascii.isAlphanumeric(bytes[i]) or bytes[i] == '_')) i += 1;
                break :blk keyword(bytes[start..i]);
            }
            if (std.ascii.isDigit(ch)) {
                i += 1;
                while (i < bytes.len and std.ascii.isAlphanumeric(bytes[i])) i += 1;
                break :blk .integer;
            }
            i += 1;
            const next = if (i < bytes.len) bytes[i] else 0;
            const pair: ?Tag = switch (ch) {
                '-' => if (next == '>') .arrow else if (next == '=') .minus_equal else null,
                '+' => if (next == '=') .plus_equal else null,
                '&' => if (next == '&') .and_and else null,
                '|' => if (next == '|') .or_or else null,
                '=' => if (next == '=') .eq_eq else if (next == '>') .fat_arrow else null,
                '!' => if (next == '=') .bang_eq else null,
                '<' => if (next == '=') .le else null,
                '>' => if (next == '=') .ge else null,
                else => null,
            };
            if (pair) |p| {
                i += 1;
                break :blk p;
            }
            break :blk switch (ch) {
                '(' => .lparen,
                ')' => .rparen,
                '[' => .lbracket,
                ']' => .rbracket,
                '{' => .lbrace,
                '}' => .rbrace,
                ';' => .semicolon,
                ':' => .colon,
                ',' => .comma,
                '.' => .dot,
                '+' => .plus,
                '*' => .star,
                '/' => .slash,
                '%' => .percent,
                '-' => .minus,
                '=' => .equal,
                '!' => .bang,
                '<' => .lt,
                '>' => .gt,
                else => return sink.fail("E_TOKEN", .{ .start = start, .end = i }, "unexpected character in source"),
            };
        };
        try tokens.append(allocator, .{ .tag = tag, .span = .{ .start = start, .end = i } });
    }
    try tokens.append(allocator, .{ .tag = .eof, .span = .{ .start = i, .end = i } });
    return tokens.toOwnedSlice(allocator);
}
