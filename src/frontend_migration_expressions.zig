//! Certain newline statement repairs; retired expressions use typed migrations.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const lex = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const Span = source.Span;

/// Remove explicit semicolons while preserving surrounding source text.
pub fn publish(src: source.Source, program: ast.Program, tokens: []const lex.Token, sink: *diagnostic.Sink) diagnostic.Error!bool {
    _ = program;
    var pass: Pass = .{ .src = src, .tokens = tokens, .sink = sink };
    try pass.semicolons();
    return pass.changed;
}

const Pass = struct {
    src: source.Source,
    tokens: []const lex.Token,
    sink: *diagnostic.Sink,
    changed: bool = false,

    fn repair(self: *Pass, span: Span, text: []const u8, message: []const u8) diagnostic.Error!void {
        try self.sink.appendFix(.{ .code = "E_FRONTEND_EXPRESSION", .span = span, .message = message }, .{ .span = span, .text = text });
        self.changed = true;
    }

    fn reject(self: *Pass, span: Span, message: []const u8) diagnostic.Error!void {
        try self.sink.items.append(self.sink.allocator, .{ .code = "E_FRONTEND_EXPRESSION", .span = span, .message = message });
        self.changed = true;
    }

    fn semicolons(self: *Pass) diagnostic.Error!void {
        var depth: usize = 0;
        for (self.tokens, 0..) |token, index| switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            .semicolon => {
                if (!std.mem.eql(u8, self.src.text(token.span), ";")) continue;
                if (depth != 0) {
                    try self.reject(token.span, "statements cannot be separated by semicolons inside expression delimiters");
                    continue;
                }
                const next = self.tokens[index + 1];
                const gap = self.src.bytes[token.span.end..next.span.start];
                if (next.tag == .dedent or next.tag == .eof or std.mem.indexOfScalar(u8, gap, '\n') != null or std.mem.indexOfScalar(u8, gap, '#') != null) {
                    try self.repair(token.span, "", "statements end at newlines; remove this semicolon");
                } else {
                    const indent = self.indentation(token.span.start);
                    const replacement = try std.fmt.allocPrint(self.sink.allocator, "\n{s}", .{indent});
                    try self.repair(.{ .start = token.span.start, .end = next.span.start }, replacement, "write each statement on its own line");
                }
            },
            else => {},
        };
    }

    fn indentation(self: *const Pass, point: usize) []const u8 {
        const line = if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..point], '\n')) |at| at + 1 else 0;
        var end = line;
        while (end < point and self.src.bytes[end] == ' ') end += 1;
        return self.src.bytes[line..end];
    }
};
