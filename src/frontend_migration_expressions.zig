//! Certain source-first array comprehension and newline statement repairs.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const lex = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const Span = source.Span;

/// Publish canonical array comprehensions and remove explicit semicolons.
pub fn publish(src: source.Source, program: ast.Program, tokens: []const lex.Token, sink: *diagnostic.Sink) diagnostic.Error!bool {
    var pass: Pass = .{ .src = src, .program = program, .tokens = tokens, .sink = sink };
    for (program.nodes.items) |node| switch (node.data) {
        .comprehension => |value| if (!value.set and !pass.sourceFirst(node.span)) {
            const filters: []const ast.NodeId = if (value.filter) |filter| &.{filter} else &.{};
            const input: ?ast.NodeId = if (value.source == .iterable) value.source.iterable else null;
            try pass.comprehension(node.span, value.name, value.output, filters, input);
        },
        .gather => |value| if (value.shape == .list) {
            try pass.gather(node.span, value);
        },
        else => {},
    };
    try pass.semicolons();
    return pass.changed;
}

const Pass = struct {
    src: source.Source,
    program: ast.Program,
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

    fn sourceFirst(self: *const Pass, span: Span) bool {
        for (self.tokens, 0..) |token, index| {
            if (token.span.start == span.start) return token.tag == .lbracket and self.tokens[index + 1].tag == .kw_for;
        }
        return false;
    }

    fn gather(self: *Pass, span: Span, value: ast.Gather) diagnostic.Error!void {
        const outer = self.program.statements.items[@backingInt(value.loop)];
        const Header = struct { name: Span, body: ast.StatementId, input: ?ast.NodeId };
        const header: Header = switch (outer.data) {
            .for_each => |loop| blk: {
                if (loop.index_name != null) return self.reject(span, "rewrite destructuring comprehensions as an explicit loop with named locals");
                break :blk .{ .name = loop.name, .body = loop.body, .input = loop.iterable };
            },
            .for_range => |loop| .{ .name = loop.name, .body = loop.body, .input = null },
            else => return self.reject(span, "rewrite this comprehension as an explicit loop"),
        };
        var filters: std.ArrayList(ast.NodeId) = .empty;
        defer filters.deinit(self.sink.allocator);
        var body = header.body;
        while (true) {
            const statement = self.program.statements.items[@backingInt(body)];
            switch (statement.data) {
                .branch => |branch| {
                    if (branch.else_body != null) return self.reject(span, "rewrite this comprehension as an explicit loop");
                    try filters.append(self.sink.allocator, branch.condition);
                    body = branch.then_body;
                },
                .gather_step => |step| return self.comprehension(span, header.name, step.value, filters.items, header.input),
                else => return self.reject(span, "nested comprehension generators require explicit loops; use one source per `[for ... yield ...]` expression"),
            }
        }
    }

    fn comprehension(self: *Pass, span: Span, name: Span, output: ast.NodeId, filters: []const ast.NodeId, input_node: ?ast.NodeId) diagnostic.Error!void {
        if (self.hasComments(span)) return self.reject(span, "rewrite this comprehension in source-first order while preserving its comments");
        const input = if (input_node) |id| self.src.text(self.program.nodes.items[@backingInt(id)].span) else self.sourceText(span, name) orelse return self.reject(span, "rewrite the comprehension as `[for name in source yield value]`");
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.sink.allocator);
        try text.appendSlice(self.sink.allocator, "[for ");
        try text.appendSlice(self.sink.allocator, self.src.text(name));
        try text.appendSlice(self.sink.allocator, " in ");
        try text.appendSlice(self.sink.allocator, input);
        try self.filtersText(&text, filters);
        try text.appendSlice(self.sink.allocator, " yield ");
        try text.appendSlice(self.sink.allocator, self.src.text(self.program.nodes.items[@backingInt(output)].span));
        try text.appendSlice(self.sink.allocator, "]");
        const replacement = try self.sink.allocator.dupe(u8, text.items);
        try self.repair(span, replacement, "write array comprehensions in source-first order");
    }

    fn filtersText(self: *Pass, out: *std.ArrayList(u8), filters: []const ast.NodeId) diagnostic.Error!void {
        if (filters.len == 0) return;
        try out.appendSlice(self.sink.allocator, " if ");
        for (filters, 0..) |filter, index| {
            if (index != 0) try out.appendSlice(self.sink.allocator, " and ");
            if (filters.len > 1) try out.appendSlice(self.sink.allocator, "(");
            try out.appendSlice(self.sink.allocator, self.src.text(self.program.nodes.items[@backingInt(filter)].span));
            if (filters.len > 1) try out.appendSlice(self.sink.allocator, ")");
        }
    }

    fn sourceText(self: *const Pass, span: Span, name: Span) ?[]const u8 {
        var start: ?usize = null;
        var depth: usize = 0;
        for (self.tokens, 0..) |token, index| {
            if (token.span.start < name.end or token.span.start >= span.end) continue;
            if (start == null) {
                if (token.tag == .kw_in) start = self.tokens[index + 1].span.start;
                continue;
            }
            if (depth == 0 and (token.tag == .kw_if or token.tag == .kw_for or token.tag == .rbracket)) {
                return std.mem.trim(u8, self.src.bytes[start.?..token.span.start], " \t\r\n");
            }
            switch (token.tag) {
                .lparen, .lbracket, .lbrace => depth += 1,
                .rparen, .rbracket, .rbrace => depth -|= 1,
                else => {},
            }
        }
        return null;
    }

    fn hasComments(self: *const Pass, span: Span) bool {
        var cursor = span.start;
        for (self.tokens) |token| {
            if (token.span.start < span.start or token.span.end > span.end) continue;
            if (std.mem.indexOfScalar(u8, self.src.bytes[cursor..token.span.start], '#') != null) return true;
            cursor = token.span.end;
        }
        return false;
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
