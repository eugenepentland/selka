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
/// Decode UTF-8 source bytes and explicit byte escapes into arena-owned storage.
pub fn decode(allocator: std.mem.Allocator, src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error![]const u8 {
    const raw = src.text(span);
    const text = if (raw[0] == 'b') raw[1..] else raw;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var i: usize = 1;
    while (i + 1 < text.len) : (i += 1) {
        var byte = text[i];
        if (byte == '\\') {
            i += 1;
            if (text[i] == 'u' or text[i] == 'U') {
                if (raw[0] == 'b') {
                    try output.append(allocator, '\\');
                    try output.append(allocator, text[i]);
                } else try unicodeEscape(allocator, text, &i, &output, span, sink);
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
                    if (i + 2 >= text.len - 1) return sink.fail(escape_code, span, "hex byte escape requires two digits");
                    for (text[i + 1 .. i + 3]) |digit| if (!std.ascii.isHex(digit)) return sink.fail(escape_code, span, "invalid hex byte escape");
                    const parsed = std.fmt.parseInt(u8, text[i + 1 .. i + 3], 16) catch return sink.fail(escape_code, span, "invalid hex byte escape");
                    i += 2;
                    break :hex parsed;
                },
                else => return sink.fail(escape_code, span, "unknown byte escape"),
            };
        }
        if (output.items.len == 65536) return sink.fail("E_BYTE_LITERAL_LIMIT", span, "byte literal exceeds 65536 decoded bytes; use input buffers for larger text");
        try output.append(allocator, byte);
    }
    return output.toOwnedSlice(allocator);
}

fn unicodeEscape(allocator: std.mem.Allocator, text: []const u8, index: *usize, output: *std.ArrayList(u8), span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!void {
    const digits: usize = if (text[index.*] == 'u') 4 else 8;
    if (index.* + digits >= text.len - 1) return sink.fail(escape_code, span, "Unicode escape has too few hexadecimal digits");
    const point = std.fmt.parseInt(u21, text[index.* + 1 .. index.* + digits + 1], 16) catch return sink.fail(escape_code, span, "invalid Unicode escape");
    var encoded: [4]u8 = undefined;
    const count = std.unicode.utf8Encode(point, &encoded) catch return sink.fail(escape_code, span, "Unicode escape is not a scalar value");
    if (output.items.len + count > 65536) return sink.fail("E_BYTE_LITERAL_LIMIT", span, "literal exceeds 65536 decoded bytes");
    try output.appendSlice(allocator, encoded[0..count]);
    index.* += digits;
}
