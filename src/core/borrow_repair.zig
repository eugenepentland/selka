//! C6, the certain borrow repairs for an element read refused as a borrow.
//!
//! `mut x = xs[i]` is refused (`E_SINGLE_OWNER_BORROW`): the element is owned and
//! the list keeps it. Two rewrites are offered, each only when it is proven:
//!
//! - the binding is never written, so `const x = xs[i]` borrows the element (R1).
//!   The checker decides that by re-checking the function with `x` const
//!   (`single_owner.zig`, `probeConstBinding`); nothing here is needed.
//! - the binding is changed only through its scalar fields, and the block ends the
//!   change with the write-back `xs[i] = x`. Each use of `x` becomes the element
//!   place `xs[i]`, and the declaration and write-back lines go away. `proveWriteBack`
//!   checks the lines; the field types come from the checker.
//!
//! Anything else keeps the copy repair, so a repair never changes a result.
//! The caller keeps the original refusal and its rule (B7 for an element, R6
//! for a default selection); these proofs replace only its repair metadata.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const diagnostic = language.diagnostic;
const lexer = language.lexer;
const source = language.source;
const Span = source.Span;

/// The names one element-read binding involves, as the refusal sees them.
pub const Names = struct {
    /// The binding `x` of `mut x = xs[i]`.
    binding: []const u8,
    /// The list `xs` the element is read from.
    owner: []const u8,
    /// The index text: an identifier or an integer literal.
    index: []const u8,
    /// The name span of the binding; its line is the declaration.
    declaration: Span,
};

/// One line's layout-free tokens and its indentation in spaces.
const Line = struct { tokens: []lexer.Token, indent: usize };

/// The line index (zero-based) of the byte at `offset`.
fn lineIndex(src: source.Source, offset: usize) usize {
    return src.physicalLocation(offset).line - 1;
}

/// The tokens of one source line, without its newline and layout tokens. Null when
/// the line does not lex: the proof refuses such a line rather than skipping it.
fn lineOf(a: std.mem.Allocator, src: source.Source, index: usize) error{OutOfMemory}!?Line {
    const start = src.line_starts[index];
    const end = if (index + 1 < src.line_starts.len) src.line_starts[index + 1] - 1 else src.bytes.len;
    var indent: usize = 0;
    while (start + indent < end and src.bytes[start + indent] == ' ') indent += 1;
    var sink: diagnostic.Sink = .{ .allocator = a };
    defer sink.deinit();
    const raw = lexer.lexRange(a, src.bytes, .{ .start = start + indent, .end = end }, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var kept: usize = 0;
    for (raw) |token| switch (token.tag) {
        .semicolon, .eof, .indent, .dedent => {},
        else => {
            raw[kept] = token;
            kept += 1;
        },
    };
    return .{ .tokens = raw[0..kept], .indent = indent };
}

/// Words that the lexer reads as identifiers but that change a line's meaning:
/// `try` and `fail` leave the block, `mut` and `own` hand a name to a callee.
fn reservedWord(text: []const u8) bool {
    return std.mem.eql(u8, text, "try") or std.mem.eql(u8, text, "fail") or std.mem.eql(u8, text, "mut") or std.mem.eql(u8, text, "own");
}

/// Keywords that end a straight-line region: each leaves the block or hides a condition.
fn exiting(tag: lexer.Tag) bool {
    return switch (tag) {
        .kw_return, .kw_assert, .kw_break, .kw_continue, .kw_if, .kw_elif, .kw_else, .kw_while, .kw_for, .kw_match, .kw_case, .kw_with, .kw_const, .kw_pass => true,
        else => false,
    };
}

/// Tags that assign to the name before them.
fn assigns(tag: lexer.Tag) bool {
    return switch (tag) {
        .equal, .plus_equal, .minus_equal, .star_equal, .slash_equal, .slash_slash_equal, .percent_equal => true,
        else => false,
    };
}

/// Whether the token at `at` names a variable: an identifier that is not a field after a dot.
fn namesVariable(tokens: []const lexer.Token, at: usize, text: []const u8, src: source.Source) bool {
    if (tokens[at].tag != .ident) return false;
    if (at > 0 and tokens[at - 1].tag == .dot) return false;
    return std.mem.eql(u8, src.text(tokens[at].span), text);
}

/// The field of `fields` a `binding.field` access names, when it is a scalar.
fn scalarField(fields: []const typed.Field, name: []const u8) bool {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return !field.ty.isAggregate();
    }
    return false;
}

/// Whether one straight-line region line keeps the binding's uses to scalar field
/// accesses and never exits, reads or writes the owner, or changes the index.
/// `uses` collects each `binding` token, which the rewrite replaces.
fn regionLineOk(a: std.mem.Allocator, src: source.Source, names: Names, fields: []const typed.Field, tokens: []const lexer.Token, uses: *std.ArrayList(Span)) error{OutOfMemory}!bool {
    var depth: i64 = 0;
    for (tokens) |token| switch (token.tag) {
        .lparen, .lbracket, .lbrace => depth += 1,
        .rparen, .rbracket, .rbrace => {
            depth -= 1;
            if (depth < 0) return false;
        },
        else => {},
    };
    if (depth != 0) return false;
    for (tokens, 0..) |token, at| {
        if (exiting(token.tag)) return false;
        if (token.tag != .ident) continue;
        const text = src.text(token.span);
        if (reservedWord(text)) return false;
        if (at > 0 and tokens[at - 1].tag == .dot) continue;
        if (std.mem.eql(u8, text, names.owner)) return false;
        if (std.mem.eql(u8, text, names.index)) {
            // An index that is assigned or handed over mutably would move the element.
            if (at + 1 < tokens.len and assigns(tokens[at + 1].tag)) return false;
            if (at > 0 and tokens[at - 1].tag == .ident and reservedWord(src.text(tokens[at - 1].span))) return false;
            continue;
        }
        if (!std.mem.eql(u8, text, names.binding)) continue;
        // `binding.field` and nothing deeper: a scalar field, read or stored.
        if (at + 2 >= tokens.len or tokens[at + 1].tag != .dot or tokens[at + 2].tag != .ident) return false;
        if (!scalarField(fields, src.text(tokens[at + 2].span))) return false;
        if (at + 3 < tokens.len and (tokens[at + 3].tag == .dot or tokens[at + 3].tag == .lbracket or tokens[at + 3].tag == .lparen)) return false;
        try uses.append(a, token.span);
    }
    return true;
}

/// Whether a line is the write-back `owner[index] = binding`.
fn isWriteBack(src: source.Source, tokens: []const lexer.Token, names: Names) bool {
    if (tokens.len != 6) return false;
    if (!namesVariable(tokens, 0, names.owner, src) or tokens[1].tag != .lbracket) return false;
    if (!(namesVariable(tokens, 2, names.index, src) or (tokens[2].tag == .integer and std.mem.eql(u8, src.text(tokens[2].span), names.index)))) return false;
    if (tokens[3].tag != .rbracket or tokens[4].tag != .equal) return false;
    return namesVariable(tokens, 5, names.binding, src);
}

/// Whether a line is the declaration `mut binding = owner[index]` the refusal names.
fn isDeclaration(src: source.Source, tokens: []const lexer.Token, names: Names) bool {
    if (tokens.len != 7) return false;
    if (!namesVariable(tokens, 0, "mut", src) or !namesVariable(tokens, 1, names.binding, src)) return false;
    if (tokens[2].tag != .equal) return false;
    if (!namesVariable(tokens, 3, names.owner, src) or tokens[4].tag != .lbracket) return false;
    if (!(namesVariable(tokens, 5, names.index, src) or (tokens[5].tag == .integer and std.mem.eql(u8, src.text(tokens[5].span), names.index)))) return false;
    return tokens[6].tag == .rbracket;
}

/// Whether a line from `from` on, while the block continues at `indent`, names the
/// binding. A line that does not lex counts as naming it.
fn mentionedAfter(a: std.mem.Allocator, src: source.Source, from: usize, indent: usize, binding: []const u8) error{OutOfMemory}!bool {
    var index = from;
    while (index < src.line_starts.len) : (index += 1) {
        const line = (try lineOf(a, src, index)) orelse return true;
        if (line.tokens.len == 0) continue;
        if (line.indent < indent) return false;
        for (line.tokens, 0..) |token, at| {
            if (token.tag != .ident) continue;
            if (at > 0 and line.tokens[at - 1].tag == .dot) continue;
            if (std.mem.eql(u8, src.text(token.span), binding)) return true;
        }
    }
    return false;
}

/// The edits that rewrite `mut binding = owner[index]` and its write-back into the
/// element place, or null when the lines do not prove the rewrite. `fields` are the
/// element record's fields, which the checker reads from the typed program.
pub fn proveWriteBack(a: std.mem.Allocator, src: source.Source, names: Names, fields: []const typed.Field) error{OutOfMemory}!?[]const diagnostic.Edit {
    const declared = lineIndex(src, names.declaration.start);
    const head = (try lineOf(a, src, declared)) orelse return null;
    if (!isDeclaration(src, head.tokens, names)) return null;
    const indent = head.indent;
    var uses: std.ArrayList(Span) = .empty;
    var write_back_index: ?usize = null;
    var index = declared + 1;
    while (index < src.line_starts.len) : (index += 1) {
        const line = (try lineOf(a, src, index)) orelse return null;
        if (line.tokens.len == 0) continue;
        // A shallower line ends the block before the write-back; a deeper one is a nested block.
        if (line.indent != indent) return null;
        if (isWriteBack(src, line.tokens, names)) {
            write_back_index = index;
            break;
        }
        if (!try regionLineOk(a, src, names, fields, line.tokens, &uses)) return null;
    }
    const back = write_back_index orelse return null;
    // The binding is out of use after the write-back, while the block still continues.
    if (try mentionedAfter(a, src, back + 1, indent, names.binding)) return null;
    const place = Span{ .start = head.tokens[3].span.start, .end = head.tokens[6].span.end };
    const place_text = src.text(place);
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    try edits.append(a, .{ .span = .{ .start = src.line_starts[declared], .end = src.line_starts[declared + 1] }, .text = "" });
    try edits.append(a, .{ .span = .{ .start = src.line_starts[back], .end = if (back + 1 < src.line_starts.len) src.line_starts[back + 1] else src.bytes.len }, .text = "" });
    for (uses.items) |use| try edits.append(a, .{ .span = use, .text = place_text });
    return edits.items;
}
