//! Lexer pilot values: a bounded source snapshot and exact byte-spanned tokens.
const std = @import("std");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const kinds = [_]lexer.Tag{
    .eof,
    .ident,
    .integer,
    .bytes,
    .format,
    .kw_def,
    .kw_none,
    .kw_pass,
    .kw_assert,
    .kw_elif,
    .kw_case,
    .kw_arena,
    .kw_with,
    .kw_as,
    .kw_enum,
    .kw_union,
    .kw_match,
    .kw_domain,
    .kw_private,
    .kw_wrap,
    .kw_todo,
    .kw_codec_encode,
    .kw_codec_decode,
    .kw_unwrap,
    .kw_class,
    .kw_conversion,
    .kw_replace,
    .kw_len,
    .kw_return,
    .kw_true,
    .kw_false,
    .kw_i64,
    .kw_i8,
    .kw_i16,
    .kw_i32,
    .kw_u8,
    .kw_u16,
    .kw_u32,
    .kw_u64,
    .kw_filesystem_cap,
    .kw_network_cap,
    .kw_acquire_resource,
    .kw_complete_resource,
    .kw_environment_cap,
    .kw_environment_get,
    .kw_restrict_resource,
    .kw_read_resource,
    .kw_write_resource,
    .kw_clock_cap,
    .kw_random_cap,
    .kw_clock_now,
    .kw_random_u64,
    .kw_stand_in,
    .kw_clock_advance,
    .kw_bit_and,
    .kw_bit_or,
    .kw_bit_xor,
    .kw_shift_left,
    .kw_shift_right,
    .kw_wrapping_add,
    .kw_wrapping_sub,
    .kw_wrapping_mul,
    .kw_saturating_add,
    .kw_saturating_sub,
    .kw_saturating_mul,
    .kw_f64_add,
    .kw_f64_sub,
    .kw_f64_mul,
    .kw_f64_div,
    .kw_f64_eq,
    .kw_f64_lt,
    .kw_f64_le,
    .kw_f64_sqrt,
    .kw_f64_floor,
    .kw_f64_ceil,
    .kw_f64_trunc,
    .kw_f64_abs,
    .kw_f64_neg,
    .kw_f64_from_u64,
    .kw_f64_to_u64,
    .kw_f64_sin,
    .kw_f64_cos,
    .kw_bool,
    .kw_if,
    .kw_else,
    .kw_while,
    .kw_break,
    .kw_continue,
    .kw_const,
    .kw_for,
    .kw_in,
    .kw_is,
    .kw_type,
    .at,
    .lparen,
    .rparen,
    .lbracket,
    .rbracket,
    .lbrace,
    .rbrace,
    .indent,
    .dedent,
    .arrow,
    .fat_arrow,
    .semicolon,
    .colon,
    .comma,
    .dot,
    .plus,
    .minus,
    .star,
    .slash,
    .slash_slash,
    .percent,
    .ampersand,
    .pipe,
    .caret,
    .and_and,
    .or_or,
    .plus_equal,
    .minus_equal,
    .star_equal,
    .slash_equal,
    .slash_slash_equal,
    .percent_equal,
    .equal,
    .eq_eq,
    .bang,
    .bang_eq,
    .question,
    .lt,
    .le,
    .gt,
    .ge,
};
/// Maximum immutable source bytes accepted by the qualified pilot.
pub const source_limit = 262144;
/// Maximum complete binary reply size.
pub const reply_limit = 64 + 8 + 12 * 262401;
/// Located lexical failure without diagnostic prose or structured migration fixes.
pub const Failure = struct { code: []const u8, line: usize, column: usize, span: source.Span };
/// Allocator-owned token list or a lexical failure value.
pub const Outcome = union(enum) { tokens: []lexer.Token, failure: Failure };
/// Request bytes plus the echoed correlation and source digest identity.
pub const Request = struct { bytes: []u8, identity: [40]u8 };
/// Only failures produced by the pure lexical stage have wire codes.
pub const codes = [_][]const u8{ "E_TOKEN", "E_INDENTATION", "E_BYTE_LITERAL", "E_NESTING_LIMIT", "E_REMOVED_SPELLING" };
/// Encode one complete immutable source request and bind its source digest.
pub fn request(a: std.mem.Allocator, raw: []const u8, nonce: [8]u8) error{ OutOfMemory, ComponentProtocol }!Request {
    if (raw.len > source_limit) return error.ComponentProtocol;
    const bytes = try a.alloc(u8, raw.len + 64);
    @memcpy(bytes[0..8], "SLKLEX01");
    put(bytes, 8, 1);
    put(bytes, 12, 1);
    put(bytes, 16, 0);
    put(bytes, 20, @intCast(raw.len));
    @memcpy(bytes[24..32], &nonce);
    std.crypto.hash.sha2.Sha256.hash(raw, bytes[32..64], .{});
    @memcpy(bytes[64..], raw);
    return .{ .bytes = bytes, .identity = bytes[24..64].* };
}
fn get(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
fn put(bytes: []u8, at: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], value, .little);
}
/// Validate the entire reply, including kinds, ordering, EOF, locations and identity.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: [40]u8, src: source.Source) error{ OutOfMemory, ComponentProtocol }!Outcome {
    if (bytes.len < 72 or bytes.len > reply_limit) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[0..8], "SLKLEX01") or get(bytes, 8) != 1 or get(bytes, 12) != 1) return error.ComponentProtocol;
    if (get(bytes, 16) != 1 or get(bytes, 20) != bytes.len - 64) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[24..64], &identity)) return error.ComponentProtocol;
    const count = get(bytes, 68);
    if (get(bytes, 64) == 1) {
        if (bytes.len != 92 or count != 0 or get(bytes, 72) >= codes.len) return error.ComponentProtocol;
        const span: source.Span = .{ .start = get(bytes, 84), .end = get(bytes, 88) };
        if (span.start > span.end or span.end > src.bytes.len) return error.ComponentProtocol;
        const loc = src.physicalLocation(span.start);
        if (get(bytes, 76) != loc.line or get(bytes, 80) != loc.column) return error.ComponentProtocol;
        return .{ .failure = .{ .code = codes[get(bytes, 72)], .line = loc.line, .column = loc.column, .span = span } };
    }
    if (get(bytes, 64) != 0 or count == 0 or count > 262401 or bytes.len != 72 + @as(usize, count) * 12) return error.ComponentProtocol;
    const tokens = try a.alloc(lexer.Token, count);
    errdefer a.free(tokens);
    var previous: usize = 0;
    for (tokens, 0..) |*token, index| {
        const at = 72 + index * 12;
        const kind = get(bytes, at);
        if (kind >= kinds.len) return error.ComponentProtocol;
        const tag = kinds[kind];
        const span: source.Span = .{ .start = get(bytes, at + 4), .end = get(bytes, at + 8) };
        if (span.start < previous or span.start > span.end or span.end > src.bytes.len) return error.ComponentProtocol;
        if ((tag == .eof or tag == .dedent) and span.start != span.end) return error.ComponentProtocol;
        if (tag == .eof and index + 1 != tokens.len) return error.ComponentProtocol;
        if (tag != .eof and tag != .dedent and span.start == span.end) return error.ComponentProtocol;
        previous = span.end;
        token.* = .{ .tag = tag, .span = span };
    }
    const last = tokens[tokens.len - 1];
    if (last.tag != .eof or last.span.start != src.bytes.len) return error.ComponentProtocol;
    return .{ .tokens = tokens };
}
