//! Source-preserving indentation lowering for the Python surface grammar.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const eIndentation = "E_INDENTATION";

fn lineStart(bytes: []const u8, offset: usize) usize {
    var at = offset;
    while (at > 0 and bytes[at - 1] != '\n') at -= 1;
    return at;
}

/// Insert virtual block delimiters without changing any original source offsets.
/// Continuation lines inside explicit delimiters do not participate in layout.
pub fn lower(comptime Token: type, allocator: std.mem.Allocator, bytes: []const u8, input: []const Token, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(allocator);
    var levels: [257]usize = @splat(0);
    var level: usize = 0;
    var delimiters: usize = 0;
    var previous_line: ?usize = null;
    var pending = false;
    for (input, 0..) |original, index| {
        var token = original;
        const line = lineStart(bytes, token.span.start);
        if (token.tag == .eof or (previous_line != line and delimiters == 0)) {
            var indent: usize = 0;
            if (token.tag != .eof) {
                for (bytes[line..token.span.start]) |ch| {
                    if (ch == '\t') return sink.fail(eIndentation, token.span, "indentation uses spaces; tabs are not permitted");
                    if (ch != ' ' and ch != '\r') break;
                    indent += 1;
                }
            }
            if (pending) {
                if (token.tag == .eof or indent <= levels[level]) return sink.fail(eIndentation, token.span, "expected an indented block after ':'");
                if (level + 1 == levels.len) return sink.fail("E_NESTING_LIMIT", token.span, "indentation exceeds 256 levels");
                level += 1;
                levels[level] = indent;
                pending = false;
            } else {
                while (indent < levels[level]) {
                    level -= 1;
                    try out.append(allocator, .{ .tag = .dedent, .span = .{ .start = token.span.start, .end = token.span.start } });
                }
                if (indent != levels[level]) return sink.fail(eIndentation, token.span, "unexpected indentation or dedent does not match an enclosing block");
            }
        }
        previous_line = line;
        const next_line = index + 1 < input.len and (input[index + 1].tag == .eof or lineStart(bytes, input[index + 1].span.start) != line);
        if (token.tag == .colon and delimiters == 0 and next_line) {
            token.tag = .indent;
            pending = true;
        } else switch (token.tag) {
            .lparen, .lbracket, .lbrace => delimiters += 1,
            .rparen, .rbracket, .rbrace => delimiters -|= 1,
            else => {},
        }
        try out.append(allocator, token);
    }
    return out.toOwnedSlice(allocator);
}
