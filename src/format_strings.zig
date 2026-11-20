//! Split an `f"..."` literal into its alternating literal chunks and interpolation holes.
//! Only the byte ranges are computed here; the parser builds the text nodes and parses the
//! holes with the ordinary expression grammar, so an interpolation is an ordinary expression.
//! A hole's `:spec` suffix (`PY-FSTRING-SPEC-1`) is its own piece right after the hole.
//! A triple-quoted literal (`f"""..."""`, `f'''...'''`, F-19) splits the same way; a hole and its specification close on the line
//! they open, because the one-line form has no line end to span (D-F19-1).
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const ast = @import("ast.zig");

/// Stable diagnostic code for a malformed interpolated string literal.
pub const code = "E_FORMAT_STRING";

/// One piece of a format string: literal source bytes, a doubled brace, or an expression.
pub const Piece = union(enum) {
    /// Source range of literal bytes, still carrying their ordinary escapes.
    literal: source.Span,
    /// Source range of a `{{` or `}}` pair standing for one brace character.
    brace: source.Span,
    /// Source range between the braces of one interpolation.
    hole: source.Span,
    /// Source range of the format specification after the preceding hole's
    /// top-level `:`, up to its closing brace; it may be empty.
    spec: source.Span,
};

/// How many quote bytes open (and close) the format-string literal at `span`: three for `f"""..."""` and `f'''...'''`, one
/// otherwise. A one-line literal ends at its second quote, so a third quote right after two means a triple-quoted one.
pub fn quoteWidth(bytes: []const u8, span: source.Span) usize {
    return if (byte_literal.tripleStart(bytes, span.start + 1, span.end)) 3 else 1;
}

/// Split the content of an `f"..."` literal, rejecting unmatched and empty braces.
/// The span covers the whole literal including its `f` prefix and both quotes (three each when triple-quoted).
pub fn split(allocator: std.mem.Allocator, src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error![]const Piece {
    var pieces: std.ArrayList(Piece) = .empty;
    errdefer pieces.deinit(allocator);
    const bytes = src.bytes;
    const width = quoteWidth(bytes, span);
    const stop = span.end - width;
    var at = span.start + 1 + width;
    var start = at;
    while (at < stop) {
        const byte = bytes[at];
        if (byte == '\\') {
            at += 2;
            continue;
        }
        if (byte != '{' and byte != '}') {
            at += 1;
            continue;
        }
        if (at + 1 < stop and bytes[at + 1] == byte) {
            if (at > start) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = at } });
            try pieces.append(allocator, .{ .brace = .{ .start = at, .end = at + 2 } });
            at += 2;
            start = at;
            continue;
        }
        if (byte == '}') return sink.fail(code, .{ .start = at, .end = at + 1 }, "unmatched '}' in a format string; write '}}' for a literal brace");
        if (at > start) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = at } });
        const inner = try hole(bytes, at + 1, stop, sink);
        if (inner.end == inner.start) return sink.fail(code, inner, "a format string interpolation needs an expression");
        try pieces.append(allocator, .{ .hole = inner });
        at = inner.end + 1;
        if (bytes[inner.end] == ':') {
            const format = try specification(bytes, inner.start - 1, at, stop, sink);
            try pieces.append(allocator, .{ .spec = format });
            at = format.end + 1;
        }
        start = at;
    }
    if (at > start or pieces.items.len == 0) try pieces.append(allocator, .{ .literal = .{ .start = start, .end = stop } });
    return pieces.toOwnedSlice(allocator);
}

/// How many bytes of a hole's opening the advice about a literal brace quotes.
const advice_bytes = 24;

/// The sentence a hole gets that was probably meant as text, as CSS, JSON or a template is (FR21): a literal brace is written
/// `{{` and `}}`, and the hole's own opening follows as it stands and doubled. `open` is the `{` that opens the hole and `end`
/// the end of the part to quote (through its `:` or to its closing brace); the quote stops at a line end and at 24 bytes.
pub fn literalBraceAdvice(allocator: std.mem.Allocator, bytes: []const u8, open: usize, end: usize) error{OutOfMemory}![]const u8 {
    var stop = @min(end, open + advice_bytes);
    if (std.mem.indexOfAny(u8, bytes[open..stop], "\r\n")) |line| stop = open + line;
    const opening = bytes[open..stop];
    const more: []const u8 = if (stop < end) "..." else "";
    var text: std.Io.Writer.Allocating = .init(allocator);
    const out = &text.writer;
    out.print("A literal brace in a format string is written `{{{{` and `}}}}`: if `{s}{s}` was meant as text, write `{{{s}{s}`", .{ opening, more, opening, more }) catch return error.OutOfMemory;
    return text.toOwnedSlice();
}

/// The most bytes of a hole's expression the advice about a `!` conversion quotes.
const conversion_bytes = 40;

/// The message of a `!` in a hole, the conversion of CPython's format strings (`f"{text!r}"`): a hole holds an expression and a
/// format after `:`, so the conversion is the function called in the hole. `expression` is the hole's text before the `!`; the
/// advice quotes it when it is one short line of plain text, and says `value` otherwise.
pub fn conversionAdvice(allocator: std.mem.Allocator, expression: []const u8) error{OutOfMemory}![]const u8 {
    const trimmed = std.mem.trim(u8, expression, " \t");
    const plain = trimmed.len != 0 and trimmed.len <= conversion_bytes and std.mem.indexOfAny(u8, trimmed, "`\r\n{}") == null;
    const name = if (plain) trimmed else "value";
    return std.fmt.allocPrint(
        allocator,
        "unexpected character in source: a format string hole holds an expression, then an optional format after `:`, as in `{{count:>8}}`; " ++
            "it has no `!` conversion, so call the function in the hole: `{{repr({s})}}` for `!r`, `{{str({s})}}` for `!s`",
        .{ name, name },
    );
}

/// The quote that the backslash at `at` escapes inside a hole that ends at `stop` (`\"` or `\'`), or null when `at` is no such backslash.
pub fn escapedQuote(bytes: []const u8, at: usize, stop: usize) ?u8 {
    if (at + 1 >= stop or bytes[at] != '\\') return null;
    return if (bytes[at + 1] == '"' or bytes[at + 1] == '\'') bytes[at + 1] else null;
}

/// The message of a backslash before a quote in a hole (`f"{d[\"k\"]}"`, as another language's format strings allow): a hole holds an
/// expression, not escaped text, so a quote inside it is the other kind of quote, or the value goes in a local first. `quote` is the
/// quote that follows the backslash, the kind that closes the literal.
pub fn escapedQuoteAdvice(allocator: std.mem.Allocator, quote: u8) error{OutOfMemory}![]const u8 {
    const other: u8 = if (quote == '"') '\'' else '"';
    return std.fmt.allocPrint(
        allocator,
        "unexpected character in source: a format string hole holds an expression, not escaped text, so a quote inside it is written as the " ++
            "other kind, `f{[c]c}{{d[{[o]c}k{[o]c}]}}{[c]c}`, or the value goes in a local first: `const k = d[{[c]c}k{[c]c}]`, then `f{[c]c}{{k}}{[c]c}`",
        .{ .c = quote, .o = other },
    );
}

/// Whether a format specification reads as text rather than a specification: a word after a word, or a `;` that is not a fill
/// character, neither of which a specification has (`color: red; margin: 0`), so the refusal may say a literal brace is
/// written `{{`.
pub fn looksLikeText(spec: []const u8) bool {
    for (spec, 0..) |byte, at| {
        if (byte == ';' and !(at + 1 < spec.len and std.mem.indexOfScalar(u8, "<>^=", spec[at + 1]) != null)) return true;
        if (!std.ascii.isAlphanumeric(byte)) continue;
        var next = at + 1;
        while (next < spec.len and spec[next] == ' ') next += 1;
        if (next > at + 1 and next < spec.len and std.ascii.isAlphanumeric(spec[next])) return true;
    }
    return false;
}

/// The edits that write a `!r` or `!s` conversion as the call it stands for, when the hole is exactly `expression!r` or
/// `expression!s` (`{text!r}` becomes `{repr(text)}`, `{n + 1!s:>8}` becomes `{str(n + 1):>8}`). `hole` is the hole's range
/// (up to its closing brace or its `:`) and `bang` the offset of its `!`. The first edit opens the call before the expression
/// and the second closes it in place of the conversion, so the white space around the expression stays where it was. Null when
/// the conversion is not `r` or `s` alone at the end of the hole (`!a`, `!r2`, a second `!`) or no expression stands before it;
/// the caller checks that the expression parses.
pub fn conversionEdits(bytes: []const u8, hole_span: source.Span, bang: usize) ?[2]diagnostic.Edit {
    if (bang + 2 != hole_span.end or bang < hole_span.start) return null;
    const call: []const u8 = switch (bytes[bang + 1]) {
        'r' => "repr(",
        's' => "str(",
        else => return null,
    };
    const expression = std.mem.trim(u8, bytes[hole_span.start..bang], " \t");
    if (expression.len == 0) return null;
    const start = @intFromPtr(expression.ptr) - @intFromPtr(bytes.ptr);
    return .{
        .{ .span = .{ .start = start, .end = start }, .text = call },
        .{ .span = .{ .start = start + expression.len, .end = bang + 2 }, .text = ")" },
    };
}

/// Add the advice for an unknown name that a format string's hole reports (FR21, FR24) to `failure`: when the name stands in a
/// hole that reads as the literal's own braces (`f"body { margin: 0 }"`, `f"a { color }"`), the sentence saying a literal brace
/// is written `{{`. `parts` are the literal's pieces in `nodes` (literal text is skipped), `bytes` the source. A failure of
/// another code, or a name in an ordinary hole, is left alone. The concrete checker and the generic-body checker both ask it, so a
/// hint reads the same in a generic function.
pub fn adviseUnknownName(allocator: std.mem.Allocator, bytes: []const u8, nodes: []const ast.Node, parts: []const ast.NodeId, failure: *diagnostic.Diagnostic) error{OutOfMemory}!void {
    if (!std.mem.eql(u8, failure.code, "E_UNKNOWN_NAME")) return;
    for (parts) |part| {
        const syntax = nodes[@backingInt(part)];
        if (syntax.data == .text or syntax.span.start == 0) continue;
        const spec: ?source.Span = if (syntax.data == .format_field) syntax.data.format_field.spec else null;
        // A field's span starts after its `{`; a hole that is one expression spans the expression alone, so its `{` and its
        // closing brace lie past the white space around it.
        var open = syntax.span.start - 1;
        var end = if (spec) |found| found.start - 1 else syntax.span.end;
        if (spec == null) {
            while (end < bytes.len and std.ascii.isWhitespace(bytes[end])) end += 1;
            open = syntax.span.start;
            while (open > 0 and std.ascii.isWhitespace(bytes[open - 1])) open -= 1;
            if (open == 0) continue;
            open -= 1;
        }
        if (bytes[open] != '{' or failure.span.start < open or failure.span.start > end or end > bytes.len) continue;
        const spec_text: ?[]const u8 = if (spec) |found| bytes[found.start..found.end] else null;
        if (!holeLooksLikeText(bytes[open + 1 .. end], spec_text)) return;
        const advice = try literalBraceAdvice(allocator, bytes, open, if (spec) |found| found.start else end);
        failure.message = try std.fmt.allocPrint(allocator, "{s}. {s}", .{ failure.message, advice });
        return;
    }
}

/// Whether a hole reads as the literal's own braces rather than a value to format (FR24): its text starts or ends with white space
/// (`{ margin`, `color }`), a quoted text stands before its colon (the key of a JSON object, `{"a": 1}`), or a space follows
/// its colon (`{margin: 0}`). `inner` is the text between the `{` and the colon or closing brace and `spec` the text after the
/// colon, if there is one. A hint only: the caller asks after a hole was refused, and no accepted hole is judged by it.
pub fn holeLooksLikeText(inner: []const u8, spec: ?[]const u8) bool {
    if (inner.len == 0) return false;
    if (std.ascii.isWhitespace(inner[0]) or std.ascii.isWhitespace(inner[inner.len - 1])) return true;
    const after = spec orelse return false;
    return inner[0] == '"' or inner[0] == '\'' or (after.len != 0 and after[0] == ' ');
}

/// What a hole or format specification that reaches a line end says: a hole closes on the line it opens (D-F19-1).
const line_end_message = "a `{` in a triple-quoted format string closes on the line it opens: write the hole on one line, " ++
    "or `{{` for a literal brace";

/// Whether `byte` ends a line.
fn lineEnd(byte: u8) bool {
    return byte == '\n' or byte == '\r';
}

/// The failure of a hole opened at `open` that meets the line end at `at`: the `{` through the end of its line.
fn unclosedOnLine(open: usize, at: usize, sink: *diagnostic.Sink) diagnostic.Error {
    return sink.fail(code, .{ .start = open, .end = at }, line_end_message);
}

/// Locate the closing brace of one interpolation, skipping nested brackets and literals.
fn hole(bytes: []const u8, from: usize, stop: usize, sink: *diagnostic.Sink) diagnostic.Error!source.Span {
    var depth: usize = 0;
    var at = from;
    while (at < stop) : (at += 1) {
        if (lineEnd(bytes[at])) return unclosedOnLine(from - 1, at, sink);
        switch (bytes[at]) {
            '\\' => {
                at += 1;
                if (at < stop and lineEnd(bytes[at])) return unclosedOnLine(from - 1, at, sink);
            },
            '"', '\'' => at = quoted(bytes, at, stop),
            '(', '[', '{' => depth += 1,
            ')', ']' => depth -|= 1,
            '}' => {
                if (depth == 0) return .{ .start = from, .end = at };
                depth -= 1;
            },
            ':' => if (depth == 0) return .{ .start = from, .end = at },
            else => {},
        }
    }
    return unterminated(bytes, from - 1, .{ .start = from - 1, .end = stop }, "unterminated interpolation in a format string", sink);
}

/// The failure of a hole opened at `open` that the literal never closes, reported over `span`: a `{` that was probably meant as
/// text says how a literal brace is written (FR21).
fn unterminated(bytes: []const u8, open: usize, span: source.Span, message: []const u8, sink: *diagnostic.Sink) diagnostic.Error {
    if (quoteEndedHole(bytes, span.end)) {
        const blank = std.mem.trim(u8, bytes[open + 1 .. span.end], " \t").len == 0;
        const advice = try quoteInHoleAdvice(sink.allocator, bytes[span.end], blank);
        return sink.fail(code, span, try std.fmt.allocPrint(sink.allocator, "{s}. {s}", .{ message, advice }));
    }
    const advice = try literalBraceAdvice(sink.allocator, bytes, open, span.end);
    return sink.fail(code, span, try std.fmt.allocPrint(sink.allocator, "{s}. {s}", .{ message, advice }));
}

/// Whether the one-quote literal whose closing quote is at `stop` ended inside a hole that the rest of its line closes: a `}` follows
/// the quote (`f"{d["k"]}"`), so the quote was part of the hole's text and the brace is no stray one (FR21 would say `{{`). A doubled
/// quote after it is a triple-quoted literal's end or an empty text, and is left to the brace advice.
fn quoteEndedHole(bytes: []const u8, stop: usize) bool {
    if (stop + 1 >= bytes.len or (bytes[stop] != '"' and bytes[stop] != '\'') or bytes[stop + 1] == bytes[stop]) return false;
    const line_end = std.mem.indexOfAnyPos(u8, bytes, stop + 1, "\r\n") orelse bytes.len;
    return std.mem.indexOfScalar(u8, bytes[stop + 1 .. line_end], '}') != null;
}

/// What a quote inside a hole says: a quote of the literal's own kind (`quote`) ends the literal there, so the hole is left open.
/// The ways out are the other kind of quote in the hole or for the literal, or a local that holds the value first. A `blank` hole
/// (`f"{"k": 1}"`, a brace of JSON) also says how its brace is written beside the other kind of quote.
fn quoteInHoleAdvice(allocator: std.mem.Allocator, quote: u8, blank: bool) error{OutOfMemory}![]const u8 {
    const other: u8 = if (quote == '"') '\'' else '"';
    const advice = try std.fmt.allocPrint(
        allocator,
        "A `{[c]c}` inside a hole ends the literal there, so this hole was left open: write the " ++
            "quote inside the hole as the other kind, `f{[c]c}{{d[{[o]c}k{[o]c}]}}{[c]c}`, or the literal as the other kind, " ++
            "`f{[o]c}{{d[{[c]c}k{[c]c}]}}{[o]c}`, or bind the value to a name first: `const k = d[{[c]c}k{[c]c}]`, then `f{[c]c}{{k}}{[c]c}`",
        .{ .c = quote, .o = other },
    );
    if (!blank) return advice;
    return std.fmt.allocPrint(allocator, "{[a]s}. A `{{` of the text itself is written `{{{{`: `f{[o]c}{{{{{[c]c}k{[c]c}: 1}}}}{[o]c}`", .{ .a = advice, .o = other, .c = quote });
}

/// What a `{` inside a format specification says first: a specification is literal text.
const nested_message = "a nested `{...}` inside a format specification is not supported; a specification is literal text such as `{value:>8.2f}`";

/// Locate the closing brace of one format specification, which starts at `from` in the hole opened by the `{` at `open`.
/// A nested `{...}` (a computed width or precision) is rejected: a specification is literal.
fn specification(bytes: []const u8, open: usize, from: usize, stop: usize, sink: *diagnostic.Sink) diagnostic.Error!source.Span {
    var at = from;
    while (at < stop) : (at += 1) {
        if (bytes[at] == '}') return .{ .start = from, .end = at };
        if (lineEnd(bytes[at])) return unclosedOnLine(open, at, sink);
        if (bytes[at] == '{') {
            const advice = try literalBraceAdvice(sink.allocator, bytes, open, from);
            const message = try std.fmt.allocPrint(sink.allocator, "{s}. {s}", .{ nested_message, advice });
            return sink.fail(code, .{ .start = at, .end = at + 1 }, message);
        }
    }
    return unterminated(bytes, open, .{ .start = from - 1, .end = stop }, "unterminated format specification in a format string", sink);
}

/// The index of the quote that closes the text opened at `from`; or the byte before the line end that meets it, so that the
/// caller reports the hole (a text in a hole stays on the hole's line); or `stop - 1`.
fn quoted(bytes: []const u8, from: usize, stop: usize) usize {
    var at = from + 1;
    while (at < stop and bytes[at] != bytes[from]) : (at += 1) {
        if (lineEnd(bytes[at])) return at - 1;
        if (bytes[at] == '\\') {
            at += 1;
            if (at < stop and lineEnd(bytes[at])) return at - 1;
        }
    }
    return @min(at, stop - 1);
}
