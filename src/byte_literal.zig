//! Quoted byte literals decode to fixed u8 arrays, without implicit terminators.
const std = @import("std");
const source = @import("source.zig");
const escape_code = "E_BYTE_ESCAPE";
const diagnostic = @import("diagnostic.zig");
/// Find the closing quote while preserving escaped quotes and located failures.
pub fn end(bytes: []const u8, start: usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    var i = start + 1;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == bytes[start]) return i + 1;
        if (bytes[i] == '\n' or bytes[i] == '\r') break;
        if (bytes[i] == '\\') {
            i += 1;
            if (i == bytes.len or bytes[i] == '\n' or bytes[i] == '\r') break;
        }
    }
    return sink.fail("E_BYTE_LITERAL", .{ .start = start, .end = @min(i, bytes.len) }, "unterminated byte literal; escape newlines with \\n");
}
/// The offset just past the closing three quotes of the triple-quoted literal that opens at `start`, or null when it never
/// closes: the first three quotes in a row that no backslash escapes.
fn tripleClose(bytes: []const u8, start: usize) ?usize {
    const quote = bytes[start];
    var i = start + 3;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == '\\') {
            i += 1;
            continue;
        }
        if (bytes[i] != quote) continue;
        if (i + 2 < bytes.len and bytes[i + 1] == quote and bytes[i + 2] == quote) return i + 3;
    }
    return null;
}
/// Find the closing triple quote while preserving escaped quotes, allowing the
/// newlines a docstring may span, and reporting an unterminated literal.
pub fn tripleEnd(bytes: []const u8, start: usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    return tripleClose(bytes, start) orelse
        sink.fail("E_BYTE_LITERAL", .{ .start = start, .end = bytes.len }, "unterminated triple-quoted literal; close it with three matching quotes");
}
/// `tripleEnd` for a triple-quoted format string (F-19), whose quotes open at `start`. Its refusal names the line the literal
/// opened on, because the literal then runs to the end of the file.
pub fn tripleFormatEnd(bytes: []const u8, start: usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    if (tripleClose(bytes, start)) |close| return close;
    const line = std.mem.count(u8, bytes[0..start], "\n") + 1;
    const message = try std.fmt.allocPrint(sink.allocator, "unterminated triple-quoted format string: it opened on line {d} " ++
        "and has no closing three quotes of the same kind", .{line});
    return sink.fail("E_BYTE_LITERAL", .{ .start = start, .end = bytes.len }, message);
}
/// Whether `start` opens a triple-quoted literal (`"""` or `'''`) before `limit`.
pub fn tripleStart(bytes: []const u8, start: usize, limit: usize) bool {
    const quote = bytes[start];
    if (quote != '"' and quote != '\'') return false;
    if (start + 2 >= limit) return false;
    return bytes[start + 1] == quote and bytes[start + 2] == quote;
}
/// How many quote characters delimit this literal: three for a triple-quoted
/// spelling, one otherwise. Used to strip the delimiters when decoding.
pub fn quoteDelimiters(text: []const u8) usize {
    if (text.len < 6) return 1;
    const quote = text[0];
    if (quote != '"' and quote != '\'') return 1;
    if (text[1] != quote or text[2] != quote) return 1;
    return 3;
}
/// What a `str` literal over the limit says: the limit, and the two ways to hold a larger text (`docs/bytes.md`).
const text_over = "text literal exceeds 65536 decoded bytes; join shorter text literals with + in a constant (const BIG: str = " ++
    "\"...\" + \"...\"; the join may hold up to 1 MiB), or put the text in a file and read it with embed_str(\"file\"), which has no limit";
/// What a `bytes` literal over the limit says: the limit, and the two ways to hold a larger value.
const bytes_over = "byte literal exceeds 65536 decoded bytes; join shorter byte literals with + in a constant (const BIG: bytes = " ++
    "b\"...\" + b\"...\"; the join may hold up to 1 MiB), or put the data in a file and read it with embed_bytes(\"file\"), which has no limit";
/// Decode UTF-8 source bytes and explicit byte escapes into arena-owned storage.
pub fn decode(allocator: std.mem.Allocator, src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
    const raw = src.text(span);
    return decodeDelimited(allocator, src, span, .{ .delimiters = quoteDelimiters(if (raw[0] == 'b') raw[1..] else raw) }, sink);
}
/// Decode one literal piece of a format string. The parser lends the piece the byte before and the byte after it as its
/// delimiters (a quote, or a brace beside a hole), so the delimiter count is one whatever those bytes are: reading it
/// from them would take `"` followed by two more quotes of the text for a triple-quoted opening. A bad escape is reported
/// at its own backslash, because a piece of a triple-quoted format string can start many lines above it.
pub fn decodePiece(allocator: std.mem.Allocator, src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
    return decodeDelimited(allocator, src, span, .{ .delimiters = 1, .at_escape = true }, sink);
}
/// How `decodeDelimited` reads its literal: the quote bytes at each end, and whether a bad escape is reported at the escape.
const Shape = struct { delimiters: usize, at_escape: bool = false };
/// `decode` for a literal whose delimiters are already known.
fn decodeDelimited(allocator: std.mem.Allocator, src: source.Source, span: source.Span, shape: Shape, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
    const delimiters = shape.delimiters;
    const raw = src.text(span);
    const text = if (raw[0] == 'b') raw[1..] else raw;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var i: usize = delimiters;
    while (i + delimiters < text.len) : (i += 1) {
        var byte = text[i];
        if (byte == '\\') {
            i += 1;
            const fault: source.Span = if (shape.at_escape) .{ .start = span.start + i - 1, .end = span.start + i + 1 } else span;
            if (text[i] == 'u' or text[i] == 'U') {
                if (raw[0] == 'b') {
                    try output.append(allocator, '\\');
                    try output.append(allocator, text[i]);
                } else try unicodeEscape(allocator, text[0 .. text.len - delimiters], &i, &output, .{ .fault = fault, .start = span.start }, sink);
                continue;
            }
            byte = switch (text[i]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '0' => 0,
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                'x' => hex: {
                    if (i + 2 >= text.len - delimiters) return sink.fail(escape_code, fault, "hex byte escape requires two digits");
                    for (text[i + 1 .. i + 3]) |digit| if (!std.ascii.isHex(digit)) return sink.fail(escape_code, fault, "invalid hex byte escape");
                    const parsed = std.fmt.parseInt(u8, text[i + 1 .. i + 3], 16) catch return sink.fail(escape_code, fault, "invalid hex byte escape");
                    i += 2;
                    break :hex parsed;
                },
                else => return sink.fail(escape_code, fault, "unknown byte escape"),
            };
        }
        if (output.items.len == 65536) return sink.fail("E_BYTE_LITERAL_LIMIT", span, if (raw[0] == 'b') bytes_over else text_over);
        try output.append(allocator, byte);
    }
    return output.toOwnedSlice(allocator);
}

/// Where a `\u` or `\U` escape stands: the span a refusal is reported at (the literal, or just the escape), and the offset in the
/// file of the literal's first byte, which the text of the escape is counted from.
const Site = struct { fault: source.Span, start: usize };
/// The accepted spelling of a Unicode escape, said wherever one is refused: the lexer takes no braces (`\u{fffd}`).
const unicode_form = "write `\\u` and exactly four hexadecimal digits, as in `\\u00e9`, or `\\U` and exactly eight, as in `\\U0001f600`, for a character above U+FFFF";
const unicode_few = "Unicode escape has too few hexadecimal digits: " ++ unicode_form;
const unicode_invalid = "invalid Unicode escape: " ++ unicode_form;
const unicode_braced = "a Unicode escape has no braces: " ++ unicode_form;

/// Decode the `\u` or `\U` escape at `text[index]`, where `text` ends before the closing delimiters.
fn unicodeEscape(allocator: std.mem.Allocator, text: []const u8, index: *usize, output: *std.ArrayList(u8), site: Site, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (index.* + 1 < text.len and text[index.* + 1] == '{') return bracedEscape(allocator, text, index.*, site, sink);
    const digits: usize = if (text[index.*] == 'u') 4 else 8;
    if (index.* + digits >= text.len) return sink.fail(escape_code, site.fault, unicode_few);
    const point = std.fmt.parseInt(u21, text[index.* + 1 .. index.* + digits + 1], 16) catch return sink.fail(escape_code, site.fault, unicode_invalid);
    var encoded: [4]u8 = undefined;
    const count = std.unicode.utf8Encode(point, &encoded) catch return sink.fail(escape_code, site.fault, "Unicode escape is not a scalar value");
    if (output.items.len + count > 65536) return sink.fail("E_BYTE_LITERAL_LIMIT", site.fault, text_over);
    try output.appendSlice(allocator, encoded[0..count]);
    index.* += digits;
}

/// The refusal of `\u{...}` at `text[at]`, the Rust spelling. The message gives the accepted one; when the braces hold one to four
/// hexadecimal digits of a scalar value after a `\u`, the diagnostic carries the repair, the same digits as `\u` and four.
fn bracedEscape(allocator: std.mem.Allocator, text: []const u8, at: usize, site: Site, sink: *diagnostic.Sink) diagnostic.Error {
    const close = std.mem.indexOfScalarPos(u8, text, at + 2, '}') orelse return sink.fail(escape_code, site.fault, unicode_braced);
    const digits = text[at + 2 .. close];
    if (text[at] != 'u' or digits.len == 0 or digits.len > 4) return sink.fail(escape_code, site.fault, unicode_braced);
    for (digits) |digit| if (!std.ascii.isHex(digit)) return sink.fail(escape_code, site.fault, unicode_braced);
    const point = std.fmt.parseInt(u16, digits, 16) catch return sink.fail(escape_code, site.fault, unicode_braced);
    if (point >= 0xd800 and point <= 0xdfff) return sink.fail(escape_code, site.fault, unicode_braced);
    const spelled = try allocator.alloc(u8, 6);
    @memcpy(spelled[0..2], "\\u");
    @memset(spelled[2..], '0');
    @memcpy(spelled[6 - digits.len ..], digits);
    return sink.failFix(escape_code, site.fault, unicode_braced, .{ .span = .{ .start = site.start + at - 1, .end = site.start + close + 1 }, .text = spelled });
}
