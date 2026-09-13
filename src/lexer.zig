//! ASCII tokenization; keyword classification does not depend on semantic scope.
const std = @import("std");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
/// Lexical token categories, including keywords, punctuation, literals, and end of input.
pub const Tag = enum {
    eof,
    ident,
    integer,
    bytes,
    kw_fn,
    kw_none,
    kw_pass,
    kw_elif,
    kw_case,
    kw_reset_arena,
    kw_arena,
    kw_with,
    kw_borrow,
    kw_as,
    kw_read_field,
    kw_take_field,
    kw_read_ref,
    kw_read_slice,
    kw_write_slice,
    kw_len_slice,
    kw_write_ref,
    kw_acknowledge,
    kw_try,
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
    kw_allocator,
    kw_filesystem_cap,
    kw_network_cap,
    kw_acquire_resource,
    kw_complete_resource,
    kw_environment_cap,
    kw_environment_get,
    kw_restrict_resource,
    kw_read_resource_slice,
    kw_write_resource_slice,
    kw_read_resource,
    kw_write_resource,
    kw_clock_cap,
    kw_random_cap,
    kw_clock_now,
    kw_random_u64,
    kw_len_buffer,
    kw_capacity_buffer,
    kw_read_buffer,
    kw_write_buffer,
    kw_append_buffer,
    kw_resize_buffer,
    kw_reserve_buffer,
    kw_take_buffer,
    kw_truncate_buffer,
    kw_len_pool,
    kw_capacity_pool,
    kw_insert_pool,
    kw_read_pool,
    kw_replace_pool,
    kw_remove_pool,
    kw_clear_pool,
    kw_acquire_pool,
    kw_acquire_buffer,
    kw_new_list,
    kw_len_list,
    kw_read_list,
    kw_append_list,
    kw_write_list,

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
    kw_cast,
    kw_bool,
    kw_if,
    kw_else,
    kw_while,
    kw_break,
    kw_continue,
    kw_const,
    kw_for,
    kw_in,
    kw_type,
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
    dot_dot,
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

/// Index just past one top-level declaration's terminating `;` or `}`, without parsing it.
/// `braced` selects the expected terminator; null accepts whichever appears first.
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
            .lbrace, .lparen, .lbracket => depth += 1,
            .rbrace, .rparen, .rbracket => {
                depth -|= 1;
                if (tag == .rbrace and depth == 0 and (braced orelse true)) return at;
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

        "fn",
        "return",
        "let",
        "mut",
        "true",
        "false",
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
        "type",
        "discard",
        "struct",
        "new",
        "update",
        "conversion",
        "i8",
        "i16",
        "i32",
        "u8",
        "u16",
        "u32",
        "u64",
        "allocator",
        "filesystem_cap",
        "network_cap",
        "acquire_resource",
        "complete_resource",
        "environment_cap",
        "environment_get",
        "restrict_resource",
        "read_resource_slice",
        "write_resource_slice",
        "read_resource",
        "write_resource",
        "clock_cap",
        "random_cap",
        "clock_now",
        "random_u64",
        "len_buffer",
        "capacity_buffer",
        "read_buffer",
        "write_buffer",
        "append_buffer",
        "resize_buffer",
        "reserve_buffer",
        "take_buffer",
        "truncate_buffer",
        "len_pool",
        "capacity_pool",
        "insert_pool",
        "read_pool",
        "replace_pool",
        "remove_pool",
        "clear_pool",
        "acquire_pool",
        "acquire_buffer",
        "new_list",
        "len_list",
        "read_list",
        "append_list",
        "write_list",

        "cast",
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
        "reset_arena",
        "arena",
        "borrow",
        "as",
        "read_field",
        "take_field",
        "read_ref",
        "write_ref",
        "read_slice",
        "write_slice",
        "len_slice",
        "acknowledge",
        "try",
    };
    inline for (words) |w| {
        if (std.mem.eql(u8, word, w)) return @field(Tag, "kw_" ++ w);
    }
    return .ident;
}
fn pythonKeyword(word: []const u8) Tag {
    const aliases = .{
        .{ "def", Tag.kw_fn },
        .{ "class", Tag.kw_struct },
        .{ "True", Tag.kw_true },
        .{ "False", Tag.kw_false },
        .{ "None", Tag.kw_none },
        .{ "pass", Tag.kw_pass },
        .{ "elif", Tag.kw_elif },
        .{ "case", Tag.kw_case },
        .{ "and", Tag.and_and },
        .{ "or", Tag.or_or },
        .{ "not", Tag.bang },
        .{ "with", Tag.kw_with },
    };
    inline for (aliases) |alias| if (std.mem.eql(u8, word, alias[0])) return alias[1];
    return keyword(word);
}
fn dialectKeyword(word: []const u8, python: bool) Tag {
    return if (python) pythonKeyword(word) else keyword(word);
}
/// Check the identifier spelling rules without accepting reserved keywords.
pub fn isIdentifier(word: []const u8) bool {
    if (word.len == 0 or !(std.ascii.isAlphabetic(word[0]) or word[0] == '_')) return false;
    for (word[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    return keyword(word) == .ident;
}
/// Recognize Python declaration heads without mistaking comments or strings for code.
pub fn isPythonSource(bytes: []const u8) bool {
    var at: usize = 0;
    while (at < bytes.len) {
        const ch = bytes[at];
        if (ch == '#' or (ch == '/' and at + 1 < bytes.len and bytes[at + 1] == '/')) {
            while (at < bytes.len and bytes[at] != '\n') at += 1;
        } else if (ch == '"' or ch == '\'') {
            const quote = ch;
            at += 1;
            while (at < bytes.len and bytes[at] != quote) {
                if (bytes[at] == '\\' and at + 1 < bytes.len) at += 1;
                at += 1;
            }
            if (at < bytes.len) at += 1;
        } else if (std.ascii.isAlphabetic(ch) or ch == '_') {
            const start = at;
            at += 1;
            while (at < bytes.len and (std.ascii.isAlphanumeric(bytes[at]) or bytes[at] == '_')) at += 1;
            if (std.mem.eql(u8, bytes[start..at], "def") or std.mem.eql(u8, bytes[start..at], "class")) {
                var next = at;
                while (next < bytes.len and (bytes[next] == ' ' or bytes[next] == '\t')) next += 1;
                if (next > at and next < bytes.len and (std.ascii.isAlphabetic(bytes[next]) or bytes[next] == '_')) return true;
            }
        } else at += 1;
    }
    return false;
}
/// Allocate source-spanned tokens and report invalid input through the supplied diagnostic sink.
pub fn lex(allocator: std.mem.Allocator, bytes: []const u8, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    const python = isPythonSource(bytes);
    var i: usize = 0;
    while (i < bytes.len) {
        const start = i;
        const ch = bytes[i];
        if (std.ascii.isWhitespace(ch)) {
            i += 1;
            continue;
        }
        const legacy_comment = !python and ch == '/' and i + 1 < bytes.len and bytes[i + 1] == '/';
        if (ch == '#' or legacy_comment) {
            while (i < bytes.len and bytes[i] != '\n') i += 1;
            continue;
        }
        const tag: Tag = blk: {
            const bytes_prefix = ch == 'b' and i + 1 < bytes.len and (bytes[i + 1] == '"' or bytes[i + 1] == '\'');
            if (ch == '"' or ch == '\'' or bytes_prefix) {
                i = try @import("byte_literal.zig").end(bytes, start + @as(usize, @intFromBool(ch == 'b')), sink);
                break :blk .bytes;
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                i += 1;
                while (i < bytes.len and (std.ascii.isAlphanumeric(bytes[i]) or bytes[i] == '_')) i += 1;
                break :blk dialectKeyword(bytes[start..i], python);
            }
            if (std.ascii.isDigit(ch)) {
                i = @import("float_syntax.zig").end(bytes, start);
                break :blk .integer;
            }
            i += 1;
            const next = if (i < bytes.len) bytes[i] else 0;
            const pair: ?Tag = switch (ch) {
                '/' => if (python and next == '/') .slash_slash else null,
                '.' => if (next == '.') .dot_dot else null,
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
                '&' => .ampersand,
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
                '?' => .question,
                '<' => .lt,
                '>' => .gt,
                else => return sink.fail("E_TOKEN", .{ .start = start, .end = i }, "unexpected character in source"),
            };
        };
        try tokens.append(allocator, .{ .tag = tag, .span = .{ .start = start, .end = i } });
    }
    try tokens.append(allocator, .{ .tag = .eof, .span = .{ .start = i, .end = i } });
    if (isPythonSource(bytes)) {
        const raw = try tokens.toOwnedSlice(allocator);
        defer allocator.free(raw);
        return @import("python_layout.zig").lower(Token, allocator, bytes, raw, sink);
    }
    return tokens.toOwnedSlice(allocator);
}

/// Recognize omitted semicolons at a line break, closing block, or end of source.
pub fn implicitTerminator(bytes: []const u8, tokens: []const Token, position: usize) bool {
    if (position == 0) return false;
    const current = tokens[position];
    if (current.tag == .rbrace or current.tag == .eof) return true;
    return std.mem.indexOfScalar(u8, bytes[tokens[position - 1].span.end..current.span.start], '\n') != null;
}
fn declarationHead(bytes: []const u8, token: Token) bool {
    return switch (token.tag) {
        .kw_fn, .kw_struct, .kw_enum, .kw_union, .kw_domain, .kw_type, .kw_const, .kw_private, .kw_conversion => true,
        .ident => value: {
            const text = bytes[token.span.start..token.span.end];
            inline for (.{ "export", "buffer", "list", "pool", "resource", "result", "host" }) |word| if (std.mem.eql(u8, text, word)) break :value true;
            break :value false;
        },
        else => false,
    };
}

/// Normalize a simple name or one direct-import qualification, preserving source spelling.
pub fn qualifiedName(text: []const u8, tokens: []const Token) ?struct { alias: ?[]const u8, name: []const u8 } {
    if (tokens.len < 2 or tokens[0].tag != .ident) return null;
    const first = text[tokens[0].span.start..tokens[0].span.end];
    if (tokens.len == 2 and tokens[1].tag == .eof) return .{ .alias = null, .name = first };
    const last: usize = if (tokens.len == 4 and tokens[1].tag == .dot) 2 else qualified: {
        if (tokens.len != 5) return null;
        if (tokens[1].tag != .colon or tokens[2].tag != .colon) return null;
        break :qualified 3;
    };
    if (tokens[last].tag != .ident or tokens[last + 1].tag != .eof) return null;
    return .{ .alias = first, .name = text[tokens[last].span.start..tokens[last].span.end] };
}
