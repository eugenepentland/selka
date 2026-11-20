//! The one presence test for `Option[T]`: `value is None` and
//! `value is not None`, with the certain repairs of the removed `== None`,
//! `!= None`, `.is_none()` and `.is_some()` forms.
const std = @import("std");
const source = @import("source.zig");

/// Stable code for the removed `== None` / `!= None` comparison.
pub const comparison_code = "E_OPTION_COMPARISON_REMOVED";
/// Stable code for the removed `.is_none()` / `.is_some()` methods.
pub const method_code = "E_OPTION_METHOD_REMOVED";
/// The message for a removed presence comparison.
pub const comparison_message = "`== None` and `!= None` were removed; test presence with `value is None` or `value is not None`";
/// The message for a removed presence method.
pub const method_message = "`is_none()` and `is_some()` were removed; test presence with `value is None` or `value is not None`";

/// The replacement text for a removed presence test: `present` asks whether
/// the option carries a value.
pub fn testText(allocator: std.mem.Allocator, receiver: []const u8, present: bool) std.mem.Allocator.Error![]const u8 {
    return if (present)
        std.fmt.allocPrint(allocator, "{s} is not None", .{receiver})
    else
        std.fmt.allocPrint(allocator, "{s} is None", .{receiver});
}

/// The suffix a presence method leaves in place of its `.is_none()` or
/// `.is_some()`, for an edit that starts where the receiver ends.
pub fn testSuffix(present: bool) []const u8 {
    return if (present) " is not None" else " is None";
}

/// Whether a comparison operator touches either end of `span`. A presence test
/// written where a comparison already binds would parse as a chain after the
/// rewrite, so such a site is a hand migration rather than a certain edit.
pub fn adjacentComparison(src: source.Source, span: source.Span) bool {
    return comparisonBefore(src.bytes, span.start) or comparisonAfter(src.bytes, span.end);
}

/// Skip spaces, tabs and newlines backwards, answering the index before them.
fn spaceBefore(bytes: []const u8, from: usize) usize {
    var at = from;
    while (at > 0) : (at -= 1) {
        const byte = bytes[at - 1];
        if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') break;
    }
    return at;
}

/// Whether a comparison operator ends just before `start`.
fn comparisonBefore(bytes: []const u8, start: usize) bool {
    const at = spaceBefore(bytes, start);
    if (at == 0) return false;
    // `=` alone is an assignment; a doubled `=` is a comparison.
    if (bytes[at - 1] == '=') return at >= 2 and bytes[at - 2] == '=';
    if (bytes[at - 1] == '<' or bytes[at - 1] == '>') return true;
    if (bytes[at - 1] == '!') return at >= 2 and bytes[at - 2] == '=';
    // `not` before the test is unary and binds looser, so it stays certain.
    return wordAtEnd(bytes[0..at], "is") or wordAtEnd(bytes[0..at], "in");
}

/// Whether a comparison operator begins just after `end`.
fn comparisonAfter(bytes: []const u8, end: usize) bool {
    var at = end;
    while (at < bytes.len) : (at += 1) {
        const byte = bytes[at];
        if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') break;
    }
    if (at >= bytes.len) return false;
    const rest = bytes[at..];
    if (std.mem.startsWith(u8, rest, "==") or std.mem.startsWith(u8, rest, "!=")) return true;
    if (std.mem.startsWith(u8, rest, "<=") or std.mem.startsWith(u8, rest, ">=")) return true;
    if (rest[0] == '<' or rest[0] == '>') return true;
    return wordAtStart(rest, "is") or wordAtStart(rest, "in") or wordAtStart(rest, "not");
}

/// Whether `text` ends with `word` as a whole word.
fn wordAtEnd(text: []const u8, word: []const u8) bool {
    if (!std.mem.endsWith(u8, text, word)) return false;
    const at = text.len - word.len;
    if (at == 0) return true;
    return !isWordByte(text[at - 1]);
}

/// Whether `text` begins with `word` as a whole word.
fn wordAtStart(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    if (text.len == word.len) return true;
    return !isWordByte(text[word.len]);
}

/// Whether a byte continues an identifier.
fn isWordByte(byte: u8) bool {
    return byte == '_' or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9');
}
