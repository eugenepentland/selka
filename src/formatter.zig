//! Canonical source text for a parser-validated program.
//!
//! The formatter reprints the validated token stream under one fixed layout:
//! four-space suites; a single space around binary and assignment operators and
//! after commas and annotation colons; no padding inside ordinary delimiters; no
//! trailing whitespace; one final newline for a nonempty program; two blank lines
//! between top-level declarations and one after the module header directive group.
//! Consecutive one-line top-level `const` declarations with no blank line between them
//! in the source stay together, so a table of constants is not spread over three lines each.
//! A call, constructor, collection literal or parameter list whose content spans
//! source lines keeps one item per line with a trailing comma, so a diff that adds
//! an item touches one line; a single-line delimiter stays single-line.
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
pub fn format(allocator: std.mem.Allocator, bytes: []const u8, input_tokens: []const lex.Token, program: ast.Program) std.mem.Allocator.Error![]u8 {
    const borrowed = try @import("formatter_borrowing.zig").canonical(allocator, bytes, input_tokens, program.functions);
    defer if (borrowed) |owned| owned.deinit(allocator);
    return formatTokens(allocator, if (borrowed) |owned| owned.bytes else bytes, if (borrowed) |owned| owned.tokens else input_tokens);
}

fn formatTokens(allocator: std.mem.Allocator, bytes: []const u8, input_tokens: []const lex.Token) std.mem.Allocator.Error![]u8 {
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

    const breaks = try multilineDelimiters(allocator, bytes, input_tokens);
    defer allocator.free(breaks);
    const specials = try delimiterSpecials(allocator, bytes, input_tokens);
    defer allocator.free(specials);
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
        .breaks = breaks,
        .specials = specials,
    };
    defer writer.delims.deinit(allocator);
    errdefer writer.out.deinit(allocator);
    try writer.run(comments);
    const rendered = try writer.finish();
    defer allocator.free(rendered);
    return sortImports(allocator, rendered);
}

/// Sort each contiguous run of `import` lines by module path, so a project's
/// imports read alphabetically and a diff that adds one touches one line. A blank
/// line or a comment line ends a run, so a comment stays with the group it
/// annotates, and an alias or a trailing comment travels with its own line.
pub fn sortImports(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var run: std.ArrayList([]const u8) = .empty;
    defer run.deinit(allocator);
    var start: usize = 0;
    while (start < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const newline = end < text.len;
        const line = text[start..end];
        if (importKey(line) == null) {
            try flushImports(allocator, &out, run.items);
            run.clearRetainingCapacity();
            try out.appendSlice(allocator, line);
            if (newline) try out.append(allocator, '\n');
        } else {
            try run.append(allocator, line);
        }
        start = if (newline) end + 1 else end;
    }
    try flushImports(allocator, &out, run.items);
    return out.toOwnedSlice(allocator);
}

/// The module path an `import` line names: everything between the keyword and
/// the alias, the trailing comment or the end of the line. Null when the line is
/// not an import.
fn importKey(line: []const u8) ?[]const u8 {
    const keyword = "import ";
    if (!std.mem.startsWith(u8, line, keyword)) return null;
    const rest = line[keyword.len..];
    const path_end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    if (path_end == 0) return null;
    return rest[0..path_end];
}

/// Write one run of import lines sorted by module path, breaking a tie on the
/// whole line so the order is total and a second format changes nothing.
fn flushImports(allocator: std.mem.Allocator, out: *std.ArrayList(u8), run: [][]const u8) std.mem.Allocator.Error!void {
    std.mem.sort([]const u8, run, {}, importLessThan);
    for (run) |line| {
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
}

fn importLessThan(_: void, left: []const u8, right: []const u8) bool {
    const a = importKey(left).?;
    const b = importKey(right).?;
    if (!std.mem.eql(u8, a, b)) return std.mem.lessThan(u8, a, b);
    return std.mem.lessThan(u8, left, right);
}

/// Canonical quoting for one string token: double quotes, unless the text holds a
/// double quote and no single one. A docstring literal (triple-quoted) keeps its
/// delimiters and its body byte for byte, because its content is a text block
/// rather than a quoted word. An escape of a quote the chosen delimiter no longer
/// needs is dropped, and the new delimiter's own quote is escaped, so the value
/// the literal denotes never changes.
pub fn canonicalLiteral(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    var prefix: usize = 0;
    while (prefix < text.len and std.ascii.isAlphabetic(text[prefix])) prefix += 1;
    if (prefix >= text.len) return allocator.dupe(u8, text);
    const quote = text[prefix];
    if (quote != '\'' and quote != '"') return allocator.dupe(u8, text);
    const width: usize = if (text.len >= prefix + 3 and text[prefix + 1] == quote and text[prefix + 2] == quote) 3 else 1;
    const body_start = prefix + width;
    if (width == 3 or text.len < body_start + width) return allocator.dupe(u8, text);
    const body = text[body_start .. text.len - width];
    const target: u8 = if (holdsQuote(body, '"') and !holdsQuote(body, '\'')) '\'' else '"';
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, text[0..prefix]);
    try out.append(allocator, target);
    try appendBody(&out, allocator, body, target);
    try out.append(allocator, target);
    return out.toOwnedSlice(allocator);
}

/// Whether the raw literal body spells `scalar`, counting its escaped form.
fn holdsQuote(body: []const u8, scalar: u8) bool {
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (body[i] == '\\') {
            if (i + 1 < body.len and body[i + 1] == scalar) return true;
            i += 1;
            continue;
        }
        if (body[i] == scalar) return true;
    }
    return false;
}

/// Append one literal body with its quotes escaped for `target`, leaving every
/// other escape sequence untouched.
fn appendBody(out: *std.ArrayList(u8), allocator: std.mem.Allocator, body: []const u8, target: u8) std.mem.Allocator.Error!void {
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        const ch = body[i];
        if (ch == '\\' and i + 1 < body.len) {
            const next = body[i + 1];
            i += 1;
            if ((next == '\'' or next == '"') and next != target) {
                try out.append(allocator, next);
            } else if (next == '\'' or next == '"') {
                try out.append(allocator, '\\');
                try out.append(allocator, next);
            } else {
                try out.append(allocator, '\\');
                try out.append(allocator, next);
            }
            continue;
        }
        if (ch == target) try out.append(allocator, '\\');
        try out.append(allocator, ch);
    }
}

const Role = enum { header, declaration };
/// A line that starts a top-level declaration or directive: its first token, its role and whether it is a one-line
/// `const` that directly follows another one with no blank line between them (`markConstBlocks`).
const TopStart = struct { token: usize, role: Role, joins_previous: bool = false };
const Delim = enum { paren, dict, subscript, type_params, other, group, bare };

/// One open delimiter. `multiline` says the writer lays its items one per line
/// (FMT-1), which a subscript and a type-parameter list never do: their content is
/// an index, a slice or a type argument, not an item list with a trailing comma.
/// A `group` is a parenthesized expression, `return (a and b)`: it lays its one
/// expression on a line of its own, but takes no trailing comma, because `(a and b,)`
/// is a one-element tuple, which is not a value (F-S1a-10). A `bare` list puts its
/// items on lines of their own and ends its last without a comma (`Special`).
const Open = struct {
    kind: Delim,
    multiline: bool,
    /// The indentation level of the line the opening token stands on.
    indent: usize,
    /// Token index of the opening delimiter.
    opener: usize,
};

/// Mark every opening delimiter whose content spans source lines and holds at
/// least one real token, so an empty `(\n)` still collapses to `()`.
pub fn multilineDelimiters(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token) std.mem.Allocator.Error![]bool {
    const breaks = try allocator.alloc(bool, tokens.len);
    errdefer allocator.free(breaks);
    @memset(breaks, false);
    const stack = try allocator.alloc(usize, tokens.len);
    defer allocator.free(stack);
    var depth: usize = 0;
    var content: usize = 0;
    for (tokens, 0..) |token, index| {
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => {
                stack[depth] = index;
                depth += 1;
            },
            .rparen, .rbracket, .rbrace => {
                if (depth == 0) continue;
                depth -= 1;
                const opener = stack[depth];
                breaks[opener] = content > opener + 1 and hasNewline(bytes, tokens[opener].span.end, token.span.start);
            },
            else => {},
        }
        if (isReal(token.tag)) content = index;
    }
    return breaks;
}

/// How a delimiter whose content spans lines differs from an ordinary item list, which takes a comma after its last item.
pub const Special = enum {
    /// An item list: a call, a constructor, a parameter list, a tuple, a list or a dictionary literal.
    none,
    /// A parenthesized expression, `return (a and b)`: no comma stands at its own level, and `(a and b,)` is a one-element
    /// tuple, which is not a value (F-S1a-10). Its content goes on one line of its own, with no trailing comma. A comprehension
    /// or generator, which holds a `for` and may hold commas in its targets, is laid out the same way.
    group,
    /// Items separated by commas whose last item takes none: an attribute's arguments, `@ensures(result >= 0, "message")`, and a
    /// pattern that ends with the rest marker, `case atom(text, ..)`.
    bare,
};

/// Classify every opening delimiter of the token stream (`Special`).
pub fn delimiterSpecials(allocator: std.mem.Allocator, bytes: []const u8, tokens: []const lex.Token) std.mem.Allocator.Error![]Special {
    const specials = try allocator.alloc(Special, tokens.len);
    errdefer allocator.free(specials);
    @memset(specials, .none);
    const Level = struct { opener: usize, comma: bool = false, loop: bool = false, expression: bool, attribute: bool };
    var stack: std.ArrayList(Level) = .empty;
    defer stack.deinit(allocator);
    var previous: ?usize = null;
    var before_previous: ?usize = null;
    for (tokens, 0..) |token, index| {
        switch (token.tag) {
            .lparen, .lbracket, .lbrace => {
                const is_paren = token.tag == .lparen;
                const expression = is_paren and (if (previous) |before| startsOperand(bytes, tokens[before]) else true);
                const attribute = is_paren and previous != null and tokens[previous.?].tag == .ident and before_previous != null and tokens[before_previous.?].tag == .at;
                try stack.append(allocator, .{ .opener = index, .expression = expression, .attribute = attribute });
            },
            .rparen, .rbracket, .rbrace => if (stack.pop()) |level| {
                const rest_marker = previous != null and tokens[previous.?].tag == .dot and level.opener + 1 != index;
                specials[level.opener] = if (level.loop) .group else if (level.attribute or rest_marker) .bare else if (level.expression and !level.comma) .group else .none;
            },
            .comma => if (stack.items.len > 0) {
                stack.items[stack.items.len - 1].comma = true;
            },
            .kw_for => if (stack.items.len > 0) {
                stack.items[stack.items.len - 1].loop = true;
            },
            else => {},
        }
        if (isReal(token.tag)) {
            before_previous = previous;
            previous = index;
        }
    }
    return specials;
}

/// Whether the comma of a delimiter of this kind ends an item, so that the next item starts a line of a one-item-per-line layout.
fn separatesItems(kind: Delim) bool {
    return switch (kind) {
        .paren, .dict, .other, .bare => true,
        .subscript, .type_params, .group => false,
    };
}

/// Whether a `(` right after this token opens a parenthesized expression: the token is an operator, a separator, an opening
/// delimiter or a keyword that is followed by an expression, and not the end of an operand a call or a type list follows.
fn startsOperand(bytes: []const u8, token: lex.Token) bool {
    const tag = token.tag;
    if (isAssign(tag) or isBinary(tag) or isArrow(tag) or isPrefixKeyword(tag)) return true;
    switch (tag) {
        .lparen, .lbracket, .lbrace, .comma, .colon, .semicolon, .kw_is => return true,
        .ident => {
            const word = bytes[token.span.start..token.span.end];
            return std.mem.eql(u8, word, "try") or std.mem.eql(u8, word, "fail") or std.mem.eql(u8, word, "yield") or std.mem.eql(u8, word, "then");
        },
        else => return false,
    }
}

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
    delims: std.ArrayList(Open) = .empty,
    breaks: []const bool,
    /// Per token, how an opening delimiter differs from an ordinary item list (`delimiterSpecials`).
    specials: []const Special,

    level: usize = 0,
    /// The indentation level of the line being written.
    line_indent: usize = 0,
    /// A comma inside a one-item-per-line delimiter already ended its item; the
    /// line break waits so a trailing comment stays on that item's line.
    break_after_comma: bool = false,
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
                try self.emitComment(comments[comment_index], index);
            }
            try self.emitToken(index);
        }
    }

    fn emitToken(self: *Writer, index: usize) !void {
        if (self.break_after_comma) {
            self.break_after_comma = false;
            try self.endLine();
        }
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

        const closing = tag == .rparen or tag == .rbracket or tag == .rbrace;
        if (closing) if (self.openMultiline()) |open| try self.breakBeforeCloser(index, open);

        if (self.line_open and self.delims.items.len == 0 and hasNewline(self.bytes, self.prev_real_end, token.span.start)) {
            try self.endLine();
        }
        if (!self.line_open) {
            if (self.level == 0 and self.delims.items.len == 0) try self.applyTopBlanks();
            const indent = if (self.multilineIndent()) |base| base + 1 else if (self.delims.items.len > 0) self.level + 1 else self.level;
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
            // The colon of `on fail:` stays beside `fail`, which elsewhere is a prefix word.
            const separate_word = !self.isOnFailColon(index) and (self.isMutationClause(token) or self.followsApplication(index) or self.followsPrefix(index));
            if (self.needSpaceBefore(tag) or separate_word) try self.space();
        }

        if (named_equal) {
            try self.out.append(self.allocator, '=');
            self.tight_after = true;
        } else if (tag == .colon) {
            const slice = self.delims.items.len > 0 and self.delims.items[self.delims.items.len - 1].kind == .subscript;
            try self.out.append(self.allocator, ':');
            self.force_space_after_colon = !slice;
        } else if (tag == .bytes or tag == .format) {
            const literal = try canonicalLiteral(self.allocator, self.bytes[token.span.start..token.span.end]);
            defer self.allocator.free(literal);
            try self.out.appendSlice(self.allocator, literal);
        } else {
            try self.out.appendSlice(self.allocator, self.bytes[token.span.start..token.span.end]);
        }
        self.at_line_start = false;

        switch (tag) {
            .lparen, .lbracket, .lbrace => {
                const special = self.specials[index];
                const kind: Delim = switch (special) {
                    .group => .group,
                    .bare => .bare,
                    .none => switch (tag) {
                        .lparen => .paren,
                        .lbracket => self.bracketRole(index),
                        else => .dict,
                    },
                };
                const item_list = kind == .paren or kind == .dict or kind == .other or kind == .group or kind == .bare;
                const multiline = self.breaks[index] and item_list;
                try self.delims.append(self.allocator, .{ .kind = kind, .multiline = multiline, .indent = self.line_indent, .opener = index });
                if (multiline) try self.endLine();
            },
            .rparen, .rbracket, .rbrace => {
                if (self.delims.items.len > 0) _ = self.delims.pop();
            },
            else => {},
        }
        if (tag == .comma) if (self.openMultiline()) |open| if (self.breaks[open.opener] and separatesItems(open.kind)) {
            self.break_after_comma = true;
        };

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
    /// Whether token `index` is the colon of `on fail:`.
    fn isOnFailColon(self: *const Writer, index: usize) bool {
        if (self.tokens[index].tag != .colon) return false;
        const fail_at = self.prev_real[index] orelse return false;
        const on_at = self.prev_real[fail_at] orelse return false;
        return self.wordIs(fail_at, "fail") and self.wordIs(on_at, "on");
    }

    fn wordIs(self: *const Writer, index: usize, text: []const u8) bool {
        const token = self.tokens[index];
        return token.tag == .ident and std.mem.eql(u8, self.bytes[token.span.start..token.span.end], text);
    }

    fn followsPrefix(self: *const Writer, index: usize) bool {
        const previous = self.prev_real[index] orelse return false;
        const token = self.tokens[previous];
        if (token.tag != .ident) return false;
        const word = self.bytes[token.span.start..token.span.end];
        return std.mem.eql(u8, word, "try") or std.mem.eql(u8, word, "fail") or
            std.mem.eql(u8, word, "yield") or std.mem.eql(u8, word, "then");
    }

    /// FMT-1: an identifier right after a `]` that closes a type
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
        const kind = self.delims.items[self.delims.items.len - 1].kind;
        return kind == .paren or kind == .bare;
    }

    fn emitComment(self: *Writer, comment: Comment, next_token: usize) !void {
        self.break_after_comma = false;
        if (comment.trailing and self.line_open) {
            // A comment on the last item of a one-item-per-line list still sees the
            // synthesized trailing comma, so the comma precedes the comment.
            if (self.prev_tag != .comma) try self.appendTrailingComma(comment.before_token);
            try self.space();
            try self.out.appendSlice(self.allocator, comment.text);
            try self.endLine();
            return;
        }
        if (self.line_open) try self.endLine();
        const comment_level = if (self.multilineIndent()) |base| base + 1 else self.commentLevel(comment);
        if (comment_level == 0 and self.delims.items.len == 0) try self.applyTopBlanks();
        try self.startLine(comment_level);
        try self.out.appendSlice(self.allocator, comment.text);
        try self.endLine();
        _ = next_token;
    }

    /// Write the comma a one-item-per-line list gives its last item, when the
    /// source left it out and the line is still open.
    fn appendTrailingComma(self: *Writer, before_token: usize) !void {
        const open = self.openMultiline() orelse return;
        if (open.kind == .subscript or open.kind == .type_params or open.kind == .group or open.kind == .bare) return;
        const next = self.next_real[before_token] orelse return;
        switch (self.tokens[next].tag) {
            .rparen, .rbracket, .rbrace => try self.out.append(self.allocator, ','),
            else => {},
        }
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
        if (self.followsPrefix(index)) return .other;
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
        // The type arguments of a keyword intrinsic, `accept_resource[network.Accepted](listener)`, are no list literal.
        const intrinsic = self.tokens[previous].tag == .kw_accept_resource or (isKeywordTag(self.tokens[previous].tag) and !isPrefixKeyword(self.tokens[previous].tag));
        if (intrinsic) return .subscript;
        return .other;
    }

    fn applyTopBlanks(self: *Writer) !void {
        if (self.prev_role == null or self.blank_applied) return;
        if (self.line_open) try self.endLine();
        const count = if (self.next_top >= self.top_starts.len or self.top_starts[self.next_top].joins_previous)
            0
        else
            blankBetween(self.prev_role.?, self.top_starts[self.next_top].role);
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

    /// The innermost open delimiter when the writer lays it out one item per line.
    fn openMultiline(self: *const Writer) ?Open {
        if (self.delims.items.len == 0) return null;
        const open = self.delims.items[self.delims.items.len - 1];
        if (!open.multiline) return null;
        return open;
    }

    /// The indentation level of the nearest enclosing item list laid out one item
    /// per line, which is what a fresh line inside it aligns to.
    fn multilineIndent(self: *const Writer) ?usize {
        var depth = self.delims.items.len;
        while (depth > 0) {
            depth -= 1;
            const open = self.delims.items[depth];
            if (open.multiline) return open.indent;
        }
        return null;
    }

    /// Close a one-item-per-line delimiter: the last item takes a trailing comma
    /// and the closer starts the indentation of the line that opened it.
    fn breakBeforeCloser(self: *Writer, index: usize, open: Open) !void {
        const empty = if (self.prev_real[index]) |previous| previous == open.opener else true;
        if (self.line_open) {
            if (!empty and open.kind != .group and open.kind != .bare) try self.out.append(self.allocator, ',');
            try self.endLine();
        }
        try self.startLine(open.indent);
        self.tight_after = true;
        self.force_space_after_colon = false;
    }

    fn startLine(self: *Writer, indent: usize) !void {
        if (self.line_open) return;
        self.line_indent = indent;
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
        // The rest marker of a pattern, `case atom(text, ..)`, keeps the space its comma leaves.
        if (current == .dot and prev == .comma) return true;
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
        // `not` (the `.bang` token) is always a word of its own, so `xs[i] not in d` keeps its space after a `]`,
        // the one operand end that binds a following word (an array length prefix, `[2]u.Value`).
        if (prev == .rbracket and current == .bang) return true;
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
    markConstBlocks(bytes, tokens, list.items);
    return list.toOwnedSlice(allocator);
}

/// Set `joins_previous` on each one-line top-level `const` whose predecessor is also a one-line `const` and whose
/// gap holds no blank line, so a block of constants (and a comment between two of them) keeps its layout.
fn markConstBlocks(bytes: []const u8, tokens: []const lex.Token, starts: []TopStart) void {
    var previous_end: ?usize = null;
    for (starts, 0..) |*start, n| {
        const limit = if (n + 1 < starts.len) starts[n + 1].token else tokens.len;
        var last = limit;
        while (last > start.token + 1 and !isReal(tokens[last - 1].tag)) last -= 1;
        const end = tokens[last - 1].span.end;
        const one_line = startsConst(bytes, tokens, start.token) and !hasNewline(bytes, tokens[start.token].span.start, end);
        if (!one_line) {
            previous_end = null;
            continue;
        }
        if (previous_end) |before| start.joins_previous = !hasBlankLine(bytes, before, tokens[start.token].span.start);
        previous_end = end;
    }
}

/// Whether the declaration that begins at this token is a `const`, with or without `public` or `private` before it.
fn startsConst(bytes: []const u8, tokens: []const lex.Token, index: usize) bool {
    const token = tokens[index];
    if (token.tag == .kw_const) return true;
    const modifier = token.tag == .kw_private or (token.tag == .ident and std.mem.eql(u8, bytes[token.span.start..token.span.end], "public"));
    return modifier and index + 1 < tokens.len and tokens[index + 1].tag == .kw_const;
}

/// Whether a source line that ends inside `bytes[from..to]` holds only whitespace; the text before the first
/// newline is the rest of the previous declaration's line and the text after the last one is the next one's indent.
fn hasBlankLine(bytes: []const u8, from: usize, to: usize) bool {
    if (from >= to) return false;
    var line = (std.mem.indexOfScalar(u8, bytes[from..to], '\n') orelse return false) + from + 1;
    while (std.mem.indexOfScalarPos(u8, bytes[0..to], line, '\n')) |newline| {
        if (std.mem.trim(u8, bytes[line..newline], " \t\r").len == 0) return true;
        line = newline + 1;
    }
    return false;
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
