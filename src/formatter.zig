//! Canonical whitespace over parser-validated tokens, preserving token spellings
//! and all line comments in their original token gaps.
const std = @import("std");
const lex = @import("lexer.zig");
const Tag = lex.Tag;
const Output = struct {
    writer: *std.Io.Writer,
    line_start: bool = true,
    indent: usize = 0,
    fn newline(self: *Output) !void {
        if (!self.line_start) self.writer.writeByte('\n') catch return error.OutOfMemory;
        self.line_start = true;
    }
    fn text(self: *Output, bytes: []const u8) !void {
        if (self.line_start) {
            for (0..self.indent) |_| self.writer.writeAll("    ") catch return error.OutOfMemory;
            self.line_start = false;
        }
        self.writer.writeAll(bytes) catch return error.OutOfMemory;
    }
    fn space(self: *Output) !void {
        if (!self.line_start) self.writer.writeByte(' ') catch return error.OutOfMemory;
    }
    fn comments(self: *Output, gap: []const u8) !void {
        var offset: usize = 0;
        while (std.mem.indexOfPos(u8, gap, offset, "//")) |start| {
            if (std.mem.indexOfScalar(u8, gap[offset..start], '\n') != null) try self.newline() else try self.space();
            const end = std.mem.indexOfScalarPos(u8, gap, start, '\n') orelse gap.len;
            try self.text(std.mem.trimEnd(u8, gap[start..end], "\r"));
            try self.newline();
            offset = @min(end + 1, gap.len);
        }
    }
};
fn genericHead(tag: Tag) bool {
    return switch (tag) {
        .kw_reset_arena, .kw_cast, .kw_wrap, .kw_insert_pool, .kw_read_pool, .kw_replace_pool, .kw_remove_pool, .kw_acquire_pool, .kw_acquire_buffer, .kw_acquire_resource, .kw_complete_resource, .kw_clock_now, .kw_random_u64, .kw_environment_get, .kw_restrict_resource, .kw_read_resource, .kw_write_resource, .kw_read_resource_slice, .kw_write_resource_slice, .kw_write_buffer, .kw_append_buffer, .kw_resize_buffer, .kw_reserve_buffer => true,
        else => false,
    };
}
fn closes(tag: Tag) bool {
    return switch (tag) {
        .rparen, .rbracket, .rbrace, .gt => true,
        else => false,
    };
}
fn joinsClose(tag: Tag) bool {
    return switch (tag) {
        .comma, .semicolon, .rparen, .rbracket, .dot, .kw_else => true,
        else => false,
    };
}
fn spaceBetween(previous: Tag, current: Tag, generic_open: bool, previous_generic: bool) bool {
    if (generic_open or previous_generic) return false;
    if (current == .rparen or current == .rbracket or current == .comma or current == .semicolon or current == .colon or current == .dot or current == .dot_dot) return false;
    if (previous == .lparen or previous == .lbracket or previous == .dot or previous == .dot_dot or previous == .bang or previous == .ampersand) return false;
    if (current == .lparen) return previous == .kw_if or previous == .kw_while or previous == .kw_return;
    if (current == .lbracket) return previous == .kw_new or previous == .kw_mut or previous == .colon or previous == .arrow or previous == .equal or previous == .comma;
    if (previous == .rbracket) return switch (current) {
        .ident, .kw_i8, .kw_i16, .kw_i32, .kw_i64, .kw_u8, .kw_u16, .kw_u32, .kw_u64, .kw_bool => false,
        else => true,
    };
    return true;
}
pub fn format(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var out: Output = .{ .writer = &output.writer };
    var delimiters: std.ArrayList(Tag) = .empty;
    defer delimiters.deinit(allocator);
    var previous: Tag = .eof;
    var previous_generic = false;
    var end: usize = 0;
    for (tokens, 0..) |token, index| {
        try out.comments(bytes[end..token.span.start]);
        if (token.tag == .eof) break;
        const top: Tag = if (delimiters.items.len == 0) .eof else delimiters.items[delimiters.items.len - 1];
        const generic_open = token.tag == .lt and genericHead(previous);
        const generic_close = token.tag == .gt and top == .lt;
        // Two colon tokens qualify a module name. Preserve comments between them
        // while avoiding the ordinary annotation space after the second colon.
        const after_qualifier = previous == .colon and index >= 2 and tokens[index - 2].tag == .colon;
        if (token.tag == .rbrace) out.indent -= 1;
        const break_before = (token.tag == .rbrace and previous != .lbrace) or previous == .semicolon or
            (previous == .lbrace and token.tag != .rbrace) or (previous == .comma and top == .lbrace) or
            (previous == .rbrace and !joinsClose(token.tag));
        if (break_before) try out.newline() else if (previous != .eof and !(previous == .lbrace and token.tag == .rbrace) and !generic_close and !after_qualifier and spaceBetween(previous, token.tag, generic_open, previous_generic)) try out.space();
        try out.text(bytes[token.span.start..token.span.end]);
        if (token.tag == .lbrace or token.tag == .lparen or token.tag == .lbracket or generic_open) try delimiters.append(allocator, token.tag) else if (closes(token.tag) and (token.tag != .gt or generic_close)) _ = delimiters.pop();
        if (token.tag == .lbrace) out.indent += 1;
        previous_generic = generic_open or generic_close;
        previous = token.tag;
        end = token.span.end;
    }
    try out.newline();
    return output.toOwnedSlice();
}
