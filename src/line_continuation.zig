//! A statement ends at its newline, so an expression continues onto the next line only inside brackets. A line that ends in a
//! binary operator, or in a backslash, is how Python says "continued"; each is refused here with the way this language says it,
//! parentheses, and with the repair that writes them where the statement's expression is certain (R3-CONTINUE).
//!
//! `tokens` below is every token of one file in order, the last one `eof`, as the lexer's tokenizer makes them (not the layout
//! pass's output).
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

const how = "an expression continues on the next line only inside parentheses";

/// Where a statement lies: its first token, its last, and how many brackets are open at the token asked about.
const Extent = struct { first: usize, last: usize, depth: usize };
/// The tokens of the expression of a statement, `first` through `last`.
const Range = struct { first: usize, last: usize };

/// Whether the backslash at `at` is the last character of its line: only spaces, tabs and a carriage return follow it.
pub fn endsLine(bytes: []const u8, at: usize) bool {
    var index = at + 1;
    while (index < bytes.len and (bytes[index] == ' ' or bytes[index] == '\t' or bytes[index] == '\r')) index += 1;
    return index == bytes.len or bytes[index] == '\n';
}

/// Whether a line that ends in this token is meant to go on: the binary operators, `and`, `or` and `in`.
fn isBinary(comptime Token: type, tag: @FieldType(Token, "tag")) bool {
    return switch (tag) {
        .plus, .minus, .star, .slash, .slash_slash, .percent, .ampersand, .pipe, .caret => true,
        .and_and, .or_or, .eq_eq, .bang_eq, .lt, .le, .gt, .ge, .kw_in => true,
        else => false,
    };
}

/// Whether a token is an assignment operator, which a statement's expression does not hold outside brackets.
fn isAssignment(comptime Token: type, tag: @FieldType(Token, "tag")) bool {
    return switch (tag) {
        .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .slash_slash_equal, .percent_equal => true,
        else => false,
    };
}

/// Whether a line break lies before `tokens[index]`.
fn startsLine(comptime Token: type, bytes: []const u8, tokens: []const Token, index: usize) bool {
    if (index == 0) return true;
    const before = tokens[index - 1].span.end;
    const start = tokens[index].span.start;
    return before < start and std.mem.indexOfScalar(u8, bytes[before..start], '\n') != null;
}

/// Where a backslash that ends a line lies between `tokens[index - 1]` and `tokens[index]`, outside a comment.
fn backslashBefore(comptime Token: type, bytes: []const u8, tokens: []const Token, index: usize) ?usize {
    var at = tokens[index - 1].span.end;
    const end = tokens[index].span.start;
    while (at < end) : (at += 1) {
        if (bytes[at] == '#') {
            while (at < end and bytes[at] != '\n') at += 1;
        } else if (bytes[at] == '\\' and endsLine(bytes, at)) {
            return at;
        }
    }
    return null;
}

/// Whether the line break before `tokens[index]` is one the writer meant to continue: the line before ends in a binary
/// operator, or in a backslash.
fn joins(comptime Token: type, bytes: []const u8, tokens: []const Token, index: usize) bool {
    return isBinary(Token, tokens[index - 1].tag) or backslashBefore(Token, bytes, tokens, index) != null;
}

/// The statement that holds `tokens[at]`: it begins at the last line start at or before `at` that no operator or backslash
/// joins to the line before, and ends where the next such line start, outside brackets, begins.
fn extent(comptime Token: type, bytes: []const u8, tokens: []const Token, at: usize) Extent {
    var found: Extent = .{ .first = 0, .last = at, .depth = 0 };
    var depth: usize = 0;
    for (tokens, 0..) |token, index| {
        const breaks = index > 0 and depth == 0 and startsLine(Token, bytes, tokens, index) and !joins(Token, bytes, tokens, index);
        if (index > at and (breaks or token.tag == .eof)) {
            found.last = index - 1;
            return found;
        }
        if (index <= at and breaks) found.first = index;
        if (index == at) found.depth = depth;
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            else => {},
        }
    }
    return found;
}

/// The index of the token after the first assignment operator outside brackets in `first` through `last`.
fn afterAssignment(comptime Token: type, tokens: []const Token, first: usize, last: usize) ?usize {
    var depth: usize = 0;
    for (tokens[first .. last + 1], first..) |token, index| {
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            else => if (depth == 0 and isAssignment(Token, token.tag)) return index + 1,
        }
    }
    return null;
}

/// Whether `tokens[open..close + 1]` is brackets in balance with no comma, colon or assignment outside them.
fn plain(comptime Token: type, tokens: []const Token, open: usize, close: usize) bool {
    var depth: usize = 0;
    for (tokens[open .. close + 1]) |token| {
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => {
                if (depth == 0) return false;
                depth -= 1;
            },
            .comma, .colon => if (depth == 0) return false,
            else => if (depth == 0 and isAssignment(Token, token.tag)) return false,
        }
    }
    return depth == 0;
}

/// The expression of the statement `first` through `last`: what follows `return`, the first `=` outside brackets or an
/// augmented one, and for `if`, `elif` and `while` what lies between the keyword and the closing colon. Null where the
/// statement is of another shape, or where the span is not `plain`, or ends in an operator.
fn expression(comptime Token: type, tokens: []const Token, first: usize, last: usize) ?Range {
    var open = first + 1;
    var close = last;
    switch (tokens[first].tag) {
        .kw_return => {},
        .kw_if, .kw_elif, .kw_while => {
            if (last <= first or tokens[last].tag != .colon) return null;
            close = last - 1;
        },
        else => open = afterAssignment(Token, tokens, first, last) orelse return null,
    }
    if (open > close or isBinary(Token, tokens[close].tag) or !plain(Token, tokens, open, close)) return null;
    return .{ .first = open, .last = close };
}

/// How many spaces begin the line that `tokens[index]` is on.
fn indentOf(comptime Token: type, bytes: []const u8, tokens: []const Token, index: usize) usize {
    var line = tokens[index].span.start;
    while (line > 0 and bytes[line - 1] != '\n') line -= 1;
    var width: usize = 0;
    while (line + width < bytes.len and bytes[line + width] == ' ') width += 1;
    return width;
}

/// The edit that removes the backslash at `slash` before `tokens[index]`, with the spaces in front of it.
fn deletion(comptime Token: type, bytes: []const u8, tokens: []const Token, index: usize, slash: usize) diagnostic.Edit {
    var start = slash;
    const floor = tokens[index - 1].span.end;
    while (start > floor and (bytes[start - 1] == ' ' or bytes[start - 1] == '\t')) start -= 1;
    return .{ .span = .{ .start = start, .end = slash + 1 }, .text = "" };
}

/// Whether a statement that starts with `tokens[first]` and ends with `tokens[last]` leaves no deeper line after it that the
/// repair would strand: an `if`, `elif` or `while` is followed by its body, so only the others are asked.
fn standsAlone(comptime Token: type, bytes: []const u8, tokens: []const Token, first: usize, last: usize) bool {
    switch (tokens[first].tag) {
        .kw_if, .kw_elif, .kw_while => return true,
        else => {},
    }
    if (last + 1 >= tokens.len or tokens[last + 1].tag == .eof) return true;
    return indentOf(Token, bytes, tokens, last + 1) <= indentOf(Token, bytes, tokens, first);
}

/// The repair that puts the expression of the statement around `tokens[at]` in parentheses and removes the backslashes that
/// continue it, or null where the statement is not one whose expression is certain. `before` is how many tokens of the
/// expression must lie before `tokens[at]`, the first token after the line break: two where an operand and its operator do.
fn wrap(comptime Token: type, allocator: std.mem.Allocator, bytes: []const u8, tokens: []const Token, at: usize, before: usize) std.mem.Allocator.Error!?diagnostic.Fix {
    const found = extent(Token, bytes, tokens, at);
    const expr = expression(Token, tokens, found.first, found.last) orelse return null;
    if (expr.first + before > at or at > expr.last or startsLine(Token, bytes, tokens, expr.first)) return null;
    if (!standsAlone(Token, bytes, tokens, found.first, found.last)) return null;
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    errdefer edits.deinit(allocator);
    const open = tokens[expr.first].span.start;
    try edits.append(allocator, .{ .span = .{ .start = open, .end = open }, .text = "(" });
    for (expr.first + 1..expr.last + 1) |index| {
        if (!startsLine(Token, bytes, tokens, index)) continue;
        if (backslashBefore(Token, bytes, tokens, index)) |slash| try edits.append(allocator, deletion(Token, bytes, tokens, index, slash));
    }
    const close = tokens[expr.last].span.end;
    try edits.append(allocator, .{ .span = .{ .start = close, .end = close }, .text = ")" });
    const owned = try edits.toOwnedSlice(allocator);
    return .{ .edit = owned[0], .more = owned[1..] };
}

/// Refuse the indented line `tokens[at]` when the line before it ends in a binary operator (`E_INDENTATION`, at the operator):
/// say that an expression continues only inside parentheses, with the repair where it is certain. Returns without a
/// diagnostic when the line before does not end in one, for the caller's own message.
pub fn refuseOperator(comptime Token: type, bytes: []const u8, tokens: []const Token, at: usize, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (at == 0 or at >= tokens.len or !isBinary(Token, tokens[at - 1].tag)) return;
    const operator = tokens[at - 1].span;
    const spelled = bytes[operator.start..operator.end];
    const message = try std.fmt.allocPrint(sink.allocator, "{s}, so a line ending in `{s}` ends there: write `(a {s}` ... `b)`", .{ how, spelled, spelled });
    return sink.failRepaired("E_INDENTATION", operator, message, try wrap(Token, sink.allocator, bytes, tokens, at, 2));
}

/// Refuse the backslash at `slash` that ends a line (`E_TOKEN`, as before, with the advice): a backslash does not continue a
/// line. Inside brackets the repair removes it; outside, it writes the parentheses and removes every backslash of the
/// statement, where the statement is one whose expression is certain. `tokens` may be empty, for a file that does not read.
pub fn refuseBackslash(comptime Token: type, bytes: []const u8, tokens: []const Token, slash: usize, sink: *diagnostic.Sink) diagnostic.Error {
    const span: source.Span = .{ .start = slash, .end = slash + 1 };
    var at: usize = 0;
    while (at < tokens.len and tokens[at].span.start <= slash) at += 1;
    const known = at > 0 and at < tokens.len and tokens[at].tag != .eof and backslashBefore(Token, bytes, tokens, at) == slash;
    if (known and extent(Token, bytes, tokens, at).depth > 0) {
        const message = "a backslash does not continue a line, and inside brackets the line goes on without one: delete it";
        return sink.failRepaired("E_TOKEN", span, message, .{ .edit = deletion(Token, bytes, tokens, at, slash) });
    }
    const message = try std.fmt.allocPrint(sink.allocator, "a backslash does not continue a line: {s}, so write `(a +` ... `b)` and no backslash", .{how});
    return sink.failRepaired("E_TOKEN", span, message, if (known) try wrap(Token, sink.allocator, bytes, tokens, at, 1) else null);
}
