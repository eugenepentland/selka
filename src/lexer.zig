//! ASCII tokenization; keyword classification does not depend on semantic scope.
const std = @import("std");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const removed_names = @import("removed_names.zig");
const byte_literal = @import("byte_literal.zig");
/// Lexical token categories, including keywords, punctuation, literals, and end of input.
pub const Tag = enum {
    eof,
    ident,
    integer,
    bytes,
    format,
    kw_def,
    kw_none,
    kw_pass,
    kw_assert,
    kw_elif,
    kw_case,
    kw_arena,
    kw_with,
    kw_as,
    kw_enum,
    kw_union,
    kw_match,
    kw_domain,
    kw_private,
    kw_wrap,
    kw_todo,
    kw_codec_encode,
    kw_codec_decode,
    kw_unwrap,
    kw_class,
    kw_conversion,
    kw_replace,
    kw_len,
    kw_return,
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
    kw_filesystem_cap,
    kw_network_cap,
    kw_acquire_resource,
    kw_complete_resource,
    kw_environment_cap,
    kw_environment_get,
    kw_restrict_resource,
    kw_read_resource,
    kw_write_resource,
    kw_clock_cap,
    kw_random_cap,
    kw_clock_now,
    kw_random_u64,

    kw_bit_and,
    kw_bit_or,
    kw_bit_xor,
    kw_shift_left,
    kw_shift_right,
    kw_wrapping_add,
    kw_wrapping_sub,
    kw_wrapping_mul,
    kw_saturating_add,
    kw_saturating_sub,
    kw_saturating_mul,
    kw_f64_add,
    kw_f64_sub,
    kw_f64_mul,
    kw_f64_div,
    kw_f64_eq,
    kw_f64_lt,
    kw_f64_le,
    kw_f64_sqrt,
    kw_f64_floor,
    kw_f64_ceil,
    kw_f64_trunc,
    kw_f64_abs,
    kw_f64_neg,
    kw_f64_from_u64,
    kw_f64_to_u64,
    kw_bool,
    kw_if,
    kw_else,
    kw_while,
    kw_break,
    kw_continue,
    kw_const,
    kw_for,
    kw_in,
    kw_is,
    kw_type,
    at,
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    indent,
    dedent,
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
    slash_slash,
    percent,
    ampersand,
    and_and,
    or_or,
    plus_equal,
    minus_equal,
    star_equal,
    slash_equal,
    slash_slash_equal,
    percent_equal,
    equal,
    eq_eq,
    bang,
    bang_eq,
    question,
    lt,
    le,
    gt,
    ge,
};
/// Token category paired with its byte span in the original source.
pub const Token = struct { tag: Tag, span: Span };

/// Index just past one top-level declaration's terminating newline or dedent, without
/// parsing it. `braced` selects which one; null accepts whichever appears first.
/// Unterminated input returns the end-of-file index, so callers can reject it.
pub fn declarationEnd(bytes: []const u8, tokens: []const Token, start: usize, braced: ?bool) usize {
    var depth: usize = 0;
    var at = start;
    while (tokens[at].tag != .eof) {
        const tag = tokens[at].tag;
        const newline_candidate = at > start and depth == 0 and !(braced orelse true);
        if (newline_candidate) {
            if (declarationHead(bytes, tokens[at]) and implicitTerminator(bytes, tokens, at)) return at;
        }
        at += 1;
        switch (tag) {
            .indent, .lbrace, .lparen, .lbracket => depth += 1,
            .dedent, .rbrace, .rparen, .rbracket => {
                depth -|= 1;
                if (tag == .dedent and depth == 0 and (braced orelse true)) return at;
            },
            .semicolon => if (depth == 0 and !(braced orelse false)) return at,
            else => {},
        }
    }
    return at;
}
fn keyword(word: []const u8) Tag {
    const words = .{
        "f64_add",
        "f64_sub",
        "f64_mul",
        "f64_div",
        "f64_eq",
        "f64_lt",
        "f64_le",
        "f64_sqrt",
        "f64_floor",
        "f64_ceil",
        "f64_trunc",
        "f64_abs",
        "f64_neg",
        "f64_from_u64",
        "f64_to_u64",

        "bit_and",
        "bit_or",
        "bit_xor",
        "shift_left",
        "shift_right",
        "wrapping_add",
        "wrapping_sub",
        "wrapping_mul",
        "saturating_add",
        "saturating_sub",
        "saturating_mul",

        "return",
        "i64",
        "bool",
        "if",
        "else",
        "while",
        "break",
        "continue",
        "const",
        "for",
        "in",
        "is",
        "type",
        "conversion",
        "i8",
        "i16",
        "i32",
        "u8",
        "u16",
        "u32",
        "u64",
        "filesystem_cap",
        "network_cap",
        "acquire_resource",
        "complete_resource",
        "environment_cap",
        "environment_get",
        "restrict_resource",
        "read_resource",
        "write_resource",
        "clock_cap",
        "random_cap",
        "clock_now",
        "random_u64",

        "replace",
        "len",
        "domain",
        "private",
        "wrap",
        "todo",
        "codec_encode",
        "codec_decode",
        "unwrap",
        "enum",
        "union",
        "match",
        "arena",
        "as",
        "pass",
        "elif",
        "case",
        "with",
        "assert",
    };
    inline for (words) |w| {
        if (std.mem.eql(u8, word, w)) return @field(Tag, "kw_" ++ w);
    }
    const aliases = .{
        .{ "def", Tag.kw_def },
        .{ "class", Tag.kw_class },
        .{ "True", Tag.kw_true },
        .{ "False", Tag.kw_false },
        .{ "None", Tag.kw_none },
        .{ "and", Tag.and_and },
        .{ "or", Tag.or_or },
        .{ "not", Tag.bang },
        // Internal binary64 square root for `src/stdlib/math.my`: the module
        // declares `sqrt`, which shadows the prelude helper, so it reaches the
        // intrinsic under a spelling ordinary programs are not taught.
        .{ "__float_sqrt", Tag.kw_f64_sqrt },
    };
    inline for (aliases) |alias| if (std.mem.eql(u8, word, alias[0])) return alias[1];
    return .ident;
}
fn rejectRemovedWord(sink: *diagnostic.Sink, bytes: []const u8, start: usize, end: usize) diagnostic.Error!void {
    _ = try removed_names.rejectLexical(sink, .{ .start = start, .end = end }, bytes[start..end]);
}
fn rejectRemovedPunctuation(sink: *diagnostic.Sink, ch: u8, next: u8, start: usize, end: usize) diagnostic.Error!void {
    if (ch == '&') _ = try removed_names.reject(sink, .{ .start = start, .end = end }, "&");
    if (ch == '=' and next == '>') _ = try removed_names.reject(sink, .{ .start = start, .end = end + 1 }, "=>");
}
/// How a token is written in source, for diagnostics that name what was expected.
/// Keywords and punctuation answer their own spelling; the open categories name
/// themselves, because no single spelling stands for all of them.
pub fn spelling(comptime tag: Tag) []const u8 {
    return switch (tag) {
        .eof => "end of file",
        .ident => "a name",
        .integer => "a number",
        .bytes => "a string",
        .format => "a formatted string",
        .kw_def => "def",
        .kw_class => "class",
        .kw_none => "None",
        .kw_true => "True",
        .kw_false => "False",
        .at => "@",
        .lparen => "(",
        .rparen => ")",
        .lbracket => "[",
        .rbracket => "]",
        .lbrace => "{",
        .rbrace => "}",
        .indent => "an indented block",
        .dedent => "a dedent",
        .arrow => "->",
        .fat_arrow => "=>",
        .semicolon => "a newline",
        .colon => ":",
        .comma => ",",
        .dot => ".",
        .plus => "+",
        .minus => "-",
        .star => "*",
        .slash => "/",
        .slash_slash => "//",
        .percent => "%",
        .ampersand => "&",
        .and_and => "and",
        .or_or => "or",
        .plus_equal => "+=",
        .minus_equal => "-=",
        .star_equal => "*=",
        .slash_equal => "/=",
        .slash_slash_equal => "//=",
        .percent_equal => "%=",
        .equal => "=",
        .eq_eq => "==",
        .bang => "not",
        .bang_eq => "!=",
        .question => "?",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        else => @tagName(tag)[3..],
    };
}

/// Check the identifier spelling rules without accepting reserved keywords.
pub fn isIdentifier(word: []const u8) bool {
    if (word.len == 0 or !(std.ascii.isAlphabetic(word[0]) or word[0] == '_')) return false;
    for (word[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    return keyword(word) == .ident;
}
/// Allocate source-spanned tokens and report invalid input through the supplied diagnostic sink.
pub fn lex(allocator: std.mem.Allocator, bytes: []const u8, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    const raw = try tokenize(allocator, bytes, .{ .start = 0, .end = bytes.len }, sink);
    defer allocator.free(raw);
    return @import("python_layout.zig").lower(Token, allocator, bytes, raw, sink);
}

/// Tokenize one byte range with absolute source spans and no indentation lowering.
/// Format-string interpolations reuse the ordinary grammar through this entry point.
pub fn lexRange(allocator: std.mem.Allocator, bytes: []const u8, span: Span, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    return tokenize(allocator, bytes, span, sink);
}

/// Scan one quoted literal at `start` and return the index past its closing
/// quotes. A triple-quoted spelling is one token; `byte_prefix` marks `b"..."`,
/// whose quote sits one byte after the prefix.
fn quotedEnd(bytes: []const u8, start: usize, limit: usize, byte_prefix: bool, sink: *diagnostic.Sink) diagnostic.Error!usize {
    if (byte_literal.tripleStart(bytes, start, limit)) return byte_literal.tripleEnd(bytes, start, sink);
    return byte_literal.end(bytes, start + @as(usize, @intFromBool(byte_prefix)), sink);
}

fn tokenize(allocator: std.mem.Allocator, bytes: []const u8, span: Span, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    const limit = span.end;
    var i: usize = span.start;
    while (i < limit) {
        const start = i;
        const ch = bytes[i];
        if (std.ascii.isWhitespace(ch)) {
            i += 1;
            continue;
        }
        if (ch == '#') {
            while (i < limit and bytes[i] != '\n') i += 1;
            continue;
        }
        const tag: Tag = blk: {
            const quotes = i + 1 < limit and (bytes[i + 1] == '"' or bytes[i + 1] == '\'');
            const bytes_prefix = ch == 'b' and quotes;
            const format_prefix = ch == 'f' and quotes;
            if (format_prefix) {
                i = try byte_literal.end(bytes, start + 1, sink);
                break :blk .format;
            }
            // A triple-quoted literal is one token so a docstring may span lines;
            // it stays an ordinary `.bytes` token for every later stage.
            if (ch == '"' or ch == '\'' or bytes_prefix) {
                i = try quotedEnd(bytes, start, limit, ch == 'b', sink);
                break :blk .bytes;
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                i += 1;
                while (i < limit and (std.ascii.isAlphanumeric(bytes[i]) or bytes[i] == '_')) i += 1;
                try rejectRemovedWord(sink, bytes, start, i);
                break :blk keyword(bytes[start..i]);
            }
            if (std.ascii.isDigit(ch)) {
                i = @import("float_syntax.zig").end(bytes, start);
                break :blk .integer;
            }
            i += 1;
            const next = if (i < limit) bytes[i] else 0;
            try rejectRemovedPunctuation(sink, ch, next, start, i);
            // `//=` is the one three-byte operator; every other augmented form is a pair.
            if (ch == '/' and next == '/' and i + 1 < limit and bytes[i + 1] == '=') {
                i += 2;
                break :blk .slash_slash_equal;
            }
            const pair: ?Tag = switch (ch) {
                '/' => if (next == '/') .slash_slash else if (next == '=') .slash_equal else null,
                '-' => if (next == '>') .arrow else if (next == '=') .minus_equal else null,
                '+' => if (next == '=') .plus_equal else null,
                '*' => if (next == '=') .star_equal else null,
                '%' => if (next == '=') .percent_equal else null,
                '=' => if (next == '=') .eq_eq else null,
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
                '@' => .at,
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
                '&' => .ampersand,
                '=' => .equal,
                '?' => .question,
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

/// Recognize omitted semicolons at a line break, closing block, or end of source.
pub fn implicitTerminator(bytes: []const u8, tokens: []const Token, position: usize) bool {
    if (position == 0) return false;
    const current = tokens[position];
    if (current.tag == .dedent or current.tag == .eof) return true;
    return std.mem.indexOfScalar(u8, bytes[tokens[position - 1].span.end..current.span.start], '\n') != null;
}
fn declarationHead(bytes: []const u8, token: Token) bool {
    return switch (token.tag) {
        .kw_def, .kw_class, .kw_enum, .kw_union, .kw_domain, .kw_type, .kw_const, .kw_private, .kw_conversion, .at => true,
        .ident => value: {
            const text = bytes[token.span.start..token.span.end];
            inline for (.{ "export", "public", "resource", "result", "host", "extern", "record", "constraint" }) |word| if (std.mem.eql(u8, text, word)) break :value true;
            break :value false;
        },
        else => false,
    };
}

/// Normalize a simple name or one direct-import qualification, preserving source
/// spelling. A dotted module path splits at the last dot, so `shared.units.area`
/// normalizes to alias `shared.units` and name `area`.
pub fn qualifiedName(text: []const u8, tokens: []const Token) ?struct { alias: ?[]const u8, name: []const u8 } {
    if (tokens.len < 2 or tokens[0].tag != .ident) return null;
    const first = text[tokens[0].span.start..tokens[0].span.end];
    if (tokens.len == 2 and tokens[1].tag == .eof) return .{ .alias = null, .name = first };
    if (tokens.len == 5 and tokens[1].tag == .colon and tokens[2].tag == .colon) {
        if (tokens[3].tag != .ident or tokens[4].tag != .eof) return null;
        return .{ .alias = first, .name = text[tokens[3].span.start..tokens[3].span.end] };
    }
    var cursor: usize = 1;
    var last_dot: ?usize = null;
    while (cursor + 1 < tokens.len and tokens[cursor].tag == .dot and tokens[cursor + 1].tag == .ident) {
        last_dot = cursor;
        cursor += 2;
    }
    const dot = last_dot orelse return null;
    if (cursor + 1 != tokens.len or tokens[cursor].tag != .eof) return null;
    const alias_end = tokens[dot - 1].span.end;
    const name_token = tokens[dot + 1];
    return .{ .alias = text[tokens[0].span.start..alias_end], .name = text[name_token.span.start..name_token.span.end] };
}
