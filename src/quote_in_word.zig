//! A quote inside a word that ends a text (F-61): `'the script's path'` is the text `'the script'`, then code, then a
//! quote that opens a text of its own. The scanner (`byte_literal.zig`) reports a literal that does not close on its
//! line as `E_BYTE_LITERAL` and the parser reports the code after the text as `E_SYNTAX`; this names what the literal
//! is (a text, a format string or a byte literal) and, when a text on the line ended at a quote inside a word, says so
//! with a note at that quote and the two ways to write it.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const byte_literal = @import("byte_literal.zig");
const Span = @import("source.zig").Span;

/// The message `byte_literal.end` gives an unterminated one-line literal; only a diagnostic with this text is rewritten.
const scanner_message = "unterminated byte literal; escape newlines with \\n";
const text_message = "unterminated text: a text closes on its line with the quote that opened it; escape newlines with \\n";
const format_message = "unterminated format string: it closes on its line with the quote that opened it; " ++
    "escape newlines with \\n";

/// Rewrite the failure `err` of scanning the literal whose quote is at `quote` (its prefix, `b` or `f`, just before it
/// when `prefixed`), given the lexer's tokens already read (a slice of `lexer.Token`, taken as `anytype` so this file
/// does not import the lexer that calls it). Returns `err` unchanged for anything but the scanner's
/// unterminated-literal diagnostic at that quote.
pub fn explainUnterminated(err: diagnostic.Error, bytes: []const u8, tokens: anytype, quote: usize, prefixed: bool, sink: *diagnostic.Sink) diagnostic.Error {
    if (err != error.SourceError or sink.items.items.len == 0) return err;
    const last = &sink.items.items[sink.items.items.len - 1];
    if (!std.mem.eql(u8, last.code, "E_BYTE_LITERAL") or last.span.start != quote) return err;
    if (!std.mem.eql(u8, last.message, scanner_message)) return err;
    const prefix: u8 = if (prefixed) bytes[quote - 1] else 0;
    if (prefix == 'f') last.message = format_message;
    if (prefix == 0) last.message = text_message;
    const ended = earliestOnLine(bytes, tokens, quote) orelse return err;
    last.message = try reason(sink.allocator, "this quote opens a text that never closes", bytes, ended);
    last.related = note(bytes, ended);
    return err;
}

/// The closing quote of the literal token `literal` when the next token, a name, starts right after it and the quote
/// stands after a letter or digit: the text ended inside a word. Null for any other literal, a triple-quoted one
/// included.
pub fn closingInsideWord(bytes: []const u8, literal: Span, next: Span) ?usize {
    const text = bytes[literal.start..literal.end];
    const prefix: usize = if (text.len > 0 and (text[0] == 'b' or text[0] == 'f')) 1 else 0;
    if (text.len < 3 or byte_literal.quoteDelimiters(text[prefix..]) != 1) return null;
    const closing = literal.end - 1;
    if (bytes[closing] != '\'' and bytes[closing] != '"') return null;
    if (!std.ascii.isAlphanumeric(bytes[closing - 1])) return null;
    if (next.start != literal.end or !std.ascii.isAlphabetic(bytes[next.start])) return null;
    return closing;
}

/// The message that says why: `lead`, then that the text before it ended at the quote `ended`, and how to write it.
pub fn reason(allocator: std.mem.Allocator, lead: []const u8, bytes: []const u8, ended: usize) error{OutOfMemory}![]const u8 {
    var left = ended;
    while (left > 0 and std.ascii.isAlphanumeric(bytes[left - 1])) left -= 1;
    var right = ended + 1;
    while (right < bytes.len and std.ascii.isAlphanumeric(bytes[right])) right += 1;
    const word = bytes[left..right];
    if (bytes[ended] == '\'') return std.fmt.allocPrint(allocator, "{s}: the single-quoted text before it ended at the " ++
        "apostrophe in `{s}` (the note), so what followed was read as code; write that text in double quotes, or " ++
        "escape the apostrophe as \\'", .{ lead, word });
    return std.fmt.allocPrint(allocator, "{s}: the double-quoted text before it ended at the quote in `{s}` (the note), " ++
        "so what followed was read as code; write that text in single quotes, or escape the quote as \\\"", .{ lead, word });
}

/// The note at the quote that ended the text.
pub fn note(bytes: []const u8, ended: usize) diagnostic.Related {
    const message = if (bytes[ended] == '\'') "the apostrophe that ended the text" else "the quote that ended the text";
    return .{ .span = .{ .start = ended, .end = ended + 1 }, .message = message };
}

/// The first literal on the line of `quote` that ended inside a word at the same quote character, or null.
fn earliestOnLine(bytes: []const u8, tokens: anytype, quote: usize) ?usize {
    const line_start = if (std.mem.lastIndexOfScalar(u8, bytes[0..quote], '\n')) |at| at + 1 else 0;
    var first = tokens.len;
    while (first > 0 and tokens[first - 1].span.start >= line_start) first -= 1;
    var index = first;
    while (index + 1 < tokens.len) : (index += 1) {
        const token = tokens[index];
        if (token.tag != .bytes and token.tag != .format) continue;
        if (tokens[index + 1].tag != .ident) continue;
        const closing = closingInsideWord(bytes, token.span, tokens[index + 1].span) orelse continue;
        if (bytes[closing] == bytes[quote]) return closing;
    }
    return null;
}
