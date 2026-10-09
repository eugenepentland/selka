//! Distinguish optional absence from Unit while preserving transparent grouping.
const std = @import("std");
const source = @import("source.zig");
/// Parentheses around None keep its absence meaning; () remains a Unit value.
pub fn isNone(src: source.Source, span: source.Span) bool {
    var text = std.mem.trim(u8, src.text(span), " \t\r\n");
    while (text.len >= 2 and text[0] == '(' and text[text.len - 1] == ')') {
        text = std.mem.trim(u8, text[1 .. text.len - 1], " \t\r\n");
    }
    return std.mem.eql(u8, text, "None");
}
