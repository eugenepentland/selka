//! Canonical source text for a parser-validated program.
//!
//! The formatter reprints the validated token stream under one fixed layout:
//! four-space suites; a single space around binary and assignment operators and
//! after commas and annotation colons; no padding inside ordinary delimiters; no
//! trailing whitespace; one final newline for a nonempty program; two blank lines
//! between top-level declarations and one after the module header directive group.
//! Comments and literal text are read back from the source gaps between tokens, so
//! their bytes survive; declaration, directive and evaluation order never change.
//! The parser has already accepted the input, so this formatter never type-checks,
//! resolves names, lowers or executes. A syntactically valid draft formats even
//! when its names and types are unresolved.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");

const Tag = lex.Tag;

/// Return canonical text for an already-parsed program; callers own the copy.
pub fn format(allocator: std.mem.Allocator, bytes: []const u8, input_tokens: []const lex.Token, types: ast.TypeDeclarations) std.mem.Allocator.Error![]u8 {
    _ = types;
    const count = input_tokens.len;
    if (count == 0) return allocator.alloc(u8, 0);

    const prev_real = try allocator.alloc(?usize, count);
    defer allocator.free(prev_real);
    const next_real = try allocator.alloc(?usize, count);
    defer allocator.free(next_real);
    const levels = try allocator.alloc(usize, count);
    defer allocator.free(levels);

    {
        var last: ?usize = null;
        for (0..count) |i| {
            prev_real[i] = last;
            if (isReal(input_tokens[i].tag)) last = i;
        }
    }
    {
        var next: ?usize = null;
        var i = count;
        while (i > 0) {
            i -= 1;
            if (isReal(input_tokens[i].tag)) next = i;
            next_real[i] = next;
        }
    }
    {
        var level: usize = 0;
        for (0..count) |i| {
            switch (input_tokens[i].tag) {
                .dedent => level -|= 1,
                .indent => {
                    levels[i] = level;
                    level += 1;
                    continue;
                },
                else => {},
            }
            levels[i] = level;
        }
    }

    const comments = try collectComments(allocator, bytes, input_tokens);
    defer allocator.free(comments);
    const top_starts = try collectTopStarts(allocator, bytes, input_tokens);
    defer allocator.free(top_starts);

    var writer: Writer = .{
        .allocator = allocator,
        .bytes = bytes,
        .tokens = input_tokens,
        .prev_real = prev_real,
        .next_real = next_real,
        .levels = levels,
        .top_starts = top_starts,
    };
    defer writer.delims.deinit(allocator);
    errdefer writer.out.deinit(allocator);
    try writer.run(comments);
    return writer.finish();
}

const Role = enum { header, declaration };
const TopStart = struct { token: usize, role: Role };
const Delim = enum { paren, dict, subscript, type_params, other };

const Comment = struct {
    /// Index of the token immediately after the gap that contains this comment.
    before_token: usize,
    /// Byte offset of the `#`.
    start: usize,
    /// Trimmed comment bytes, including the leading `#`.
    text: []const u8,
    /// The previous token shares this comment's source line.
    trailing: bool,
};

const Writer = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    tokens: []const lex.Token,
    prev_real: []const ?usize,
    next_real: []const ?usize,
    levels: []const usize,
    top_starts: []const TopStart,
    out: std.ArrayList(u8) = .empty,
    delims: std.ArrayList(Delim) = .empty,

    level: usize = 0,
    line_open: bool = false,
    at_line_start: bool = true,
    force_space_after_colon: bool = false,
    tight_after: bool = false,
    prev_tag: ?Tag = null,
    prev_prev_tag: ?Tag = null,
    prev_minus_unary: bool = false,
    prev_real_end: usize = 0,
    prev_role: ?Role = null,
    next_top: usize = 0,
    blank_applied: bool = false,

    fn run(self: *Writer, comments: []const Comment) !void {
        var comment_index: usize = 0;
        var index: usize = 0;
        while (index < self.tokens.len) : (index += 1) {
            while (comment_index < comments.len and comments[comment_index].before_token == index) : (comment_index += 1) {
                try self.emitComment(comments[comment_index]);
            }
            try self.emitToken(index);
        }
    }

    fn emitToken(self: *Writer, index: usize) !void {
        const token = self.tokens[index];
        switch (token.tag) {
            .dedent => self.level -|= 1,
            .indent => try self.emitSuiteColon(token),
            .eof => if (self.line_open) try self.endLine(),
            .semicolon => if (self.line_open) try self.endLine(),
            else => try self.emitReal(index),
        }
    }

    fn emitSuiteColon(self: *Writer, token: lex.Token) !void {
        if (!self.line_open) try self.startLine(self.level);
        self.force_space_after_colon = false;
        self.at_line_start = false;
        try self.out.append(self.allocator, ':');
        self.prev_tag = null;
        self.prev_prev_tag = null;
        self.prev_minus_unary = false;
        self.tight_after = false;
        self.prev_real_end = token.span.end;
        self.level += 1;
    }

    fn emitReal(self: *Writer, index: usize) !void {
        const token = self.tokens[index];
        const tag = token.tag;
        const unary_minus = tag == .minus and !(self.prev_tag != null and isOperandEnd(self.prev_tag.?));
        const named_equal = tag == .equal and self.isNamedArgumentEqual();

        if (tag == .comma and self.commaIsRedundant(index)) return;

        if (self.line_open and self.delims.items.len == 0 and hasNewline(self.bytes, self.prev_real_end, token.span.start)) {
            try self.endLine();
        }
        if (!self.line_open) {
            if (self.level == 0 and self.delims.items.len == 0) try self.applyTopBlanks();
            const indent = if (self.delims.items.len > 0) self.level + 1 else self.level;
            try self.startLine(indent);
            self.noteTopStart(index);
        }

        if (self.at_line_start) {
            self.force_space_after_colon = false;
            self.tight_after = false;
        } else if (self.tight_after) {
            self.tight_after = false;
        } else if (self.force_space_after_colon) {
            if (!isCloser(tag)) try self.space();
            self.force_space_after_colon = false;
        } else if (!named_equal) {
            const separate_word = self.isMutationClause(token) or self.followsApplication(index) or self.followsPrefix(index);
            if (self.needSpaceBefore(tag) or separate_word) try self.space();
        }

        if (named_equal) {
            try self.out.append(self.allocator, '=');
            self.tight_after = true;
        } else if (tag == .colon) {
            const slice = self.delims.items.len > 0 and self.delims.items[self.delims.items.len - 1] == .subscript;
            try self.out.append(self.allocator, ':');
            self.force_space_after_colon = !slice;
        } else {
            try self.out.appendSlice(self.allocator, self.bytes[token.span.start..token.span.end]);
        }
        self.at_line_start = false;

        switch (tag) {
            .lparen => try self.delims.append(self.allocator, .paren),
            .lbracket => try self.delims.append(self.allocator, self.bracketRole(index)),
            .lbrace => try self.delims.append(self.allocator, .dict),
            .rparen, .rbracket, .rbrace => {
                if (self.delims.items.len > 0) _ = self.delims.pop();
            },
            else => {},
        }

        self.prev_prev_tag = self.prev_tag;
        self.prev_tag = tag;
        self.prev_minus_unary = unary_minus;
        self.prev_real_end = token.span.end;
    }

    /// `effects(mutation) mutates(...)`: the clause is a word after `)`, not a call.
    fn isMutationClause(self: *const Writer, token: lex.Token) bool {
        if (token.tag != .ident or self.prev_tag != .rparen) return false;
        return std.mem.eql(u8, self.bytes[token.span.start..token.span.end], "mutates");
    }

    /// Contextual expression words stay separated from a parenthesized value
    /// or array literal, including `try (load())` and `then [value]`.
    fn followsPrefix(self: *const Writer, index: usize) bool {
        const previous = self.prev_real[index] orelse return false;
        const token = self.tokens[previous];
        if (token.tag != .ident) return false;
        const word = self.bytes[token.span.start..token.span.end];
        return std.mem.eql(u8, word, "try") or std.mem.eql(u8, word, "fail") or
            std.mem.eql(u8, word, "yield") or std.mem.eql(u8, word, "then");
    }

    /// FMT-CLAUSE-SPACE-1: an identifier right after a `]` that closes a type
    /// application or subscript — `-> Option[int] effects()`, `-> list[T] noalloc`
    /// — is a separate word. Only the `]` of an array length prefix (`[2]u.Value`)
    /// binds the identifier after it, and that bracket's role is not `subscript`.
    fn followsApplication(self: *const Writer, index: usize) bool {
        if (self.tokens[index].tag != .ident or self.prev_tag != .rbracket) return false;
        var cursor = self.prev_real[index] orelse return false;
        var depth: usize = 0;
        while (true) {
            switch (self.tokens[cursor].tag) {
                .rbracket => depth += 1,
                .lbracket => {
                    depth -= 1;
                    if (depth == 0) return self.bracketRole(cursor) == .subscript;
                },
                else => {},
            }
            cursor = self.prev_real[cursor] orelse return false;
        }
    }

    fn isNamedArgumentEqual(self: *const Writer) bool {
        const previous = self.prev_tag orelse return false;
        switch (previous) {
            .ident, .kw_len, .kw_replace => {},
            else => return false,
        }
        const before = self.prev_prev_tag orelse return false;
        if (before != .lparen and before != .comma) return false;
        if (self.delims.items.len == 0) return false;
        return self.delims.items[self.delims.items.len - 1] == .paren;
    }

    fn emitComment(self: *Writer, comment: Comment) !void {
        if (comment.trailing and self.line_open) {
            try self.space();
            try self.out.appendSlice(self.allocator, comment.text);
            try self.endLine();
            return;
        }
        if (self.line_open) try self.endLine();
        const comment_level = self.commentLevel(comment);
        if (comment_level == 0 and self.delims.items.len == 0) try self.applyTopBlanks();
        try self.startLine(comment_level);
        try self.out.appendSlice(self.allocator, comment.text);
        try self.endLine();
    }

    fn commentLevel(self: *const Writer, comment: Comment) usize {
        const previous = self.prev_real[comment.before_token];
        const next = self.next_real[comment.before_token];
        if (previous == null and next == null) return 0;
        if (previous == null) return self.levels[next.?];
        if (next == null) return self.levels[previous.?];
        const p = previous.?;
        const n = next.?;
        const previous_indent = self.lineIndentAt(self.tokens[p].span.start);
        const next_indent = self.lineIndentAt(self.tokens[n].span.start);
        const column = self.columnAt(comment.start);
        if (column == previous_indent) return self.levels[p];
        if (column == next_indent) return self.levels[n];
        const previous_distance = if (column > previous_indent) column - previous_indent else previous_indent - column;
        const next_distance = if (column > next_indent) column - next_indent else next_indent - column;
        if (previous_distance < next_distance) return self.levels[p];
        if (next_distance < previous_distance) return self.levels[n];
        return @min(self.levels[p], self.levels[n]);
    }

    fn lineIndentAt(self: *const Writer, position: usize) usize {
        var start = position;
        while (start > 0 and self.bytes[start - 1] != '\n') start -= 1;
        var count: usize = 0;
        var at = start;
        while (at < position and self.bytes[at] == ' ') : (at += 1) count += 1;
        return count;
    }

    fn columnAt(self: *const Writer, position: usize) usize {
        var start = position;
        while (start > 0 and self.bytes[start - 1] != '\n') start -= 1;
        return position - start;
    }

    /// Whether this comma is the redundant one before a closing delimiter, as in
    /// `(a, b,)` or `f(x,)`. Canonical text drops it, so a trailing comma in a
    /// tuple, argument list or field list is removed consistently rather than
    /// preserved; no one-element tuple is spellable, so dropping it never changes
    /// what a program means.
    fn commaIsRedundant(self: *const Writer, index: usize) bool {
        if (index + 1 >= self.tokens.len) return false;
        const next = self.next_real[index + 1] orelse return false;
        return switch (self.tokens[next].tag) {
            .rparen, .rbracket, .rbrace => true,
            else => false,
        };
    }

    fn bracketRole(self: *const Writer, index: usize) Delim {
        if (index == 0) return .other;
        const previous = self.prev_real[index] orelse return .other;
        if (self.tokens[previous].tag == .ident) {
            if (self.prev_real[previous]) |before| {
                switch (self.tokens[before].tag) {
                    .kw_def, .kw_class, .kw_enum, .kw_union, .kw_domain, .kw_type, .kw_conversion => return .type_params,
                    .ident => {
                        const text = self.bytes[self.tokens[before].span.start..self.tokens[before].span.end];
                        if (std.mem.eql(u8, text, "record") or std.mem.eql(u8, text, "result") or std.mem.eql(u8, text, "constraint") or std.mem.eql(u8, text, "resource")) return .type_params;
                    },
                    else => {},
                }
            }
        }
        if (isOperandEnd(self.tokens[previous].tag)) return .subscript;
        return .other;
    }

    fn applyTopBlanks(self: *Writer) !void {
        if (self.prev_role == null or self.blank_applied) return;
        if (self.line_open) try self.endLine();
        const count = if (self.next_top < self.top_starts.len)
            blankBetween(self.prev_role.?, self.top_starts[self.next_top].role)
        else
            0;
        var i: usize = 0;
        while (i < count) : (i += 1) try self.out.append(self.allocator, '\n');
        self.blank_applied = true;
    }

    fn noteTopStart(self: *Writer, index: usize) void {
        if (self.next_top >= self.top_starts.len) return;
        if (self.top_starts[self.next_top].token != index) return;
        self.prev_role = self.top_starts[self.next_top].role;
        self.next_top += 1;
        self.blank_applied = false;
    }

    fn startLine(self: *Writer, indent: usize) !void {
        if (self.line_open) return;
        var i: usize = 0;
        while (i < indent * 4) : (i += 1) try self.out.append(self.allocator, ' ');
        self.line_open = true;
        self.at_line_start = true;
        self.force_space_after_colon = false;
        self.tight_after = false;
    }

    fn endLine(self: *Writer) !void {
        if (!self.line_open) return;
        self.trimTrailing();
        try self.out.append(self.allocator, '\n');
        self.line_open = false;
        self.at_line_start = true;
        self.force_space_after_colon = false;
        self.tight_after = false;
    }

    fn trimTrailing(self: *Writer) void {
        while (self.out.items.len > 0) {
            const last = self.out.items[self.out.items.len - 1];
            if (last != ' ' and last != '\t' and last != '\r') break;
            self.out.shrinkRetainingCapacity(self.out.items.len - 1);
        }
    }

    fn space(self: *Writer) !void {
        if (self.out.items.len == 0) return;
        const last = self.out.items[self.out.items.len - 1];
        if (last == ' ' or last == '\n') return;
        try self.out.append(self.allocator, ' ');
    }

    fn needSpaceBefore(self: *const Writer, current: Tag) bool {
        const previous = self.prev_tag orelse return false;
        const prev = previous;
        switch (current) {
            .rparen, .rbracket, .rbrace, .comma, .dot, .semicolon => return false,
            else => {},
        }
        switch (prev) {
            .lparen, .lbracket, .lbrace, .dot, .colon => return false,
            else => {},
        }
        if (current == .question) return false;
        if (prev == .comma) return true;
        if (prev == .minus and self.prev_minus_unary) return false;
        if (isAssign(prev) or isBinary(prev) or isArrow(prev)) return true;
        if (current == .lparen or current == .lbracket) {
            if (isAssign(prev) or isBinary(prev) or isArrow(prev)) return true;
            return isPrefixKeyword(prev);
        }
        if (isAssign(current) or isArrow(current)) return true;
        if (current == .minus) {
            if (!isOperandEnd(prev)) return isWordLike(prev) or isPrefixKeyword(prev);
            return true;
        }
        if (isBinary(current)) return true;
        if (isPrefixKeyword(prev)) return true;
        if (isWordLike(prev) and isWordLike(current)) return true;
        if ((prev == .rparen or prev == .rbrace or prev == .question) and isWordLike(current)) return true;
        // An operand followed by a keyword, e.g. `with arena() as scratch` or
        // `key in table`. An identifier after `]` stays tight because it is the
        // element type of an array spelling such as `[2]u.Value`.
        if (isOperandEnd(prev) and isKeywordTag(current)) return true;
        return false;
    }

    fn finish(self: *Writer) ![]u8 {
        if (self.line_open) try self.endLine();
        if (self.out.items.len > 0 and self.out.items[self.out.items.len - 1] != '\n') {
            try self.out.append(self.allocator, '\n');
        }
        return self.out.toOwnedSlice(self.allocator);
    }
};

fn collectComments(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token) ![]Comment {
    var list: std.ArrayList(Comment) = .empty;
    errdefer list.deinit(allocator);
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const gap_start = if (i == 0) 0 else tokens[i - 1].span.end;
        const gap_end = tokens[i].span.start;
        if (gap_start > gap_end) continue;
        var line_start = gap_start;
        while (line_start < gap_end) {
            const relative_newline = std.mem.indexOfScalar(u8, bytes[line_start..gap_end], '\n');
            const line_end = if (relative_newline) |offset| line_start + offset else gap_end;
            if (std.mem.indexOfScalar(u8, bytes[line_start..line_end], '#')) |hash_offset| {
                const start = line_start + hash_offset;
                const text_end = if (std.mem.indexOfScalar(u8, bytes[start..], '\n')) |offset| start + offset else bytes.len;
                try list.append(allocator, .{
                    .before_token = i,
                    .start = start,
                    .text = std.mem.trimEnd(u8, bytes[start..text_end], " \t\r\x0b\x0c"),
                    .trailing = line_start == gap_start and i > 0,
                });
            }
            if (relative_newline == null) break;
            line_start = line_end + 1;
        }
    }
    return list.toOwnedSlice(allocator);
}

fn collectTopStarts(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token) ![]TopStart {
    var list: std.ArrayList(TopStart) = .empty;
    errdefer list.deinit(allocator);
    var level: usize = 0;
    var depth: usize = 0;
    var previous_end: ?usize = null;
    var after_semicolon = false;
    var skip_until: usize = 0;
    for (0..tokens.len) |i| {
        if (i < skip_until) continue;
        const tag = tokens[i].tag;
        if (tag == .dedent) {
            level -|= 1;
            continue;
        }
        if (tag == .indent) {
            level += 1;
            continue;
        }
        if (tag == .eof) break;
        // An attribute clause is part of the declaration below it; skip the whole
        // clause so it neither opens a blank-line group nor is mistaken for one.
        if (tag == .at) {
            skip_until = lex.declarationEnd(bytes, tokens, i, false);
            if (skip_until <= i) skip_until = i + 1;
            continue;
        }
        if (tag == .semicolon) {
            after_semicolon = true;
            continue;
        }
        const new_line = previous_end == null or after_semicolon or hasNewline(bytes, previous_end.?, tokens[i].span.start);
        if (level == 0 and depth == 0 and new_line) {
            try list.append(allocator, .{ .token = i, .role = classifyRole(bytes, tokens[i]) });
        }
        after_semicolon = false;
        previous_end = tokens[i].span.end;
        switch (tag) {
            .lparen, .lbracket, .lbrace => depth += 1,
            .rparen, .rbracket, .rbrace => depth -|= 1,
            else => {},
        }
    }
    return list.toOwnedSlice(allocator);
}

fn classifyRole(bytes: []const u8, token: lex.Token) Role {
    if (token.tag == .ident) {
        const text = bytes[token.span.start..token.span.end];
        if (std.mem.eql(u8, text, "module") or std.mem.eql(u8, text, "import") or std.mem.eql(u8, text, "export")) return .header;
    }
    return .declaration;
}

fn blankBetween(previous: Role, next: Role) usize {
    return switch (previous) {
        .header => if (next == .header) 0 else 1,
        .declaration => if (next == .declaration) 2 else 1,
    };
}

fn hasNewline(bytes: []const u8, from: usize, to: usize) bool {
    if (from >= to) return false;
    return std.mem.indexOfScalar(u8, bytes[from..to], '\n') != null;
}

fn isReal(tag: Tag) bool {
    return tag != .indent and tag != .dedent and tag != .eof;
}

fn isKeywordTag(tag: Tag) bool {
    return @backingInt(tag) >= @backingInt(Tag.kw_def) and @backingInt(tag) <= @backingInt(Tag.kw_type);
}

fn isWordLike(tag: Tag) bool {
    return switch (tag) {
        .ident, .integer, .bytes, .format, .bang => true,
        else => isKeywordTag(tag),
    };
}

fn isOperandEnd(tag: Tag) bool {
    return switch (tag) {
        .ident, .integer, .bytes, .format, .rparen, .rbracket, .rbrace, .question, .kw_true, .kw_false, .kw_none => true,
        else => false,
    };
}

fn isPrefixKeyword(tag: Tag) bool {
    return switch (tag) {
        .kw_return, .kw_if, .kw_else, .kw_elif, .kw_while, .kw_assert, .kw_in, .kw_match, .kw_case, .kw_with, .kw_as, .kw_for, .bang => true,
        else => false,
    };
}

fn isBinary(tag: Tag) bool {
    return switch (tag) {
        .plus, .minus, .star, .slash, .slash_slash, .percent, .eq_eq, .bang_eq, .lt, .le, .gt, .ge, .and_and, .or_or => true,
        .pipe, .caret, .ampersand => true,
        else => false,
    };
}

fn isAssign(tag: Tag) bool {
    return switch (tag) {
        .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .slash_slash_equal, .percent_equal => true,
        else => false,
    };
}

fn isArrow(tag: Tag) bool {
    return tag == .arrow or tag == .fat_arrow;
}

fn isCloser(tag: Tag) bool {
    return tag == .rparen or tag == .rbracket or tag == .rbrace;
}
