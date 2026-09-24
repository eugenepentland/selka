//! Source-preserving indentation lowering: a `:` that ends a line opens a suite and
//! the dedent that leaves it closes one, each with its own token, so a literal brace
//! is only ever a dictionary literal.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const eIndentation = "E_INDENTATION";

/// Line starts for a nondecreasing sequence of offsets. Each query scans only the
/// bytes since the previous one, so lowering a file costs one pass over its bytes
/// rather than a backward scan to the line start for every token.
const LineCursor = struct {
    bytes: []const u8,
    position: usize = 0,
    line: usize = 0,

    fn at(self: *LineCursor, offset: usize) usize {
        var index = offset;
        while (index > self.position) : (index -= 1) {
            if (self.bytes[index - 1] == '\n') {
                self.line = index;
                break;
            }
        }
        self.position = offset;
        return self.line;
    }
};

/// Insert virtual block delimiters without changing any original source offsets.
/// Continuation lines inside explicit delimiters do not participate in layout.
pub fn lower(comptime Token: type, allocator: std.mem.Allocator, bytes: []const u8, input: []const Token, sink: *diagnostic.Sink) diagnostic.Error![]Token {
    var out: std.ArrayList(Token) = .empty;
    errdefer out.deinit(allocator);
    // Layout adds one delimiter per opened or closed suite, a small fraction of
    // the tokens; reserving for them up front keeps the append path copy-free.
    try out.ensureTotalCapacity(allocator, input.len + input.len / 4 + 8);
    var lines: LineCursor = .{ .bytes = bytes };
    var levels: [257]usize = @splat(0);
    var level: usize = 0;
    var delimiters: usize = 0;
    var previous_line: ?usize = null;
    var pending = false;
    for (input, 0..) |original, index| {
        var token = original;
        const line = lines.at(token.span.start);
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
        // The next token starts a new line exactly when a newline lies between
        // this token's start and its own (a multi-line string token included).
        const next_line = index + 1 < input.len and (input[index + 1].tag == .eof or
            std.mem.indexOfScalar(u8, bytes[token.span.start..input[index + 1].span.start], '\n') != null);
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
