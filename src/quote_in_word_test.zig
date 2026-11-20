//! F-61: a quote inside a word that ends a text is named, with a note at it; a literal that never closes is named
//! for what it is (a text, a format string or a byte literal).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check `line` as the body of `main` and return the first diagnostic's code, message and note text (the note's
/// source text, or "" when there is none), joined by `|`.
fn refusal(line: []const u8) ![]u8 {
    const text = try std.mem.concat(t.allocator, u8, &.{ "func main(out: Stream) -> int:\n    ", line, "\n    return 0\n" });
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "quote.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    const noted = if (first.related) |related| compilation.src.text(.{ .start = related.span.start - 3, .end = related.span.end + 1 }) else "";
    return std.mem.concat(t.allocator, u8, &.{ first.code, "|", first.message, "|", noted });
}

fn expectRefusal(line: []const u8, expected: []const u8) !void {
    const got = try refusal(line);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

const apostrophe_tail = " (the note), so what followed was read as code; write that text in double quotes, or escape the apostrophe as \\'";

test "an apostrophe that ends a format string is named at the quote that never closes" {
    try expectRefusal("print(out, f'the page {1} carries the script's path')", "E_BYTE_LITERAL|this quote opens a text that never " ++
        "closes: the single-quoted text before it ended at the apostrophe in `script's`" ++ apostrophe_tail ++ "|ipt's");
}

test "an apostrophe that ends a plain text is named, and so is the first of two" {
    try expectRefusal("print(out, 'it's here')", "E_BYTE_LITERAL|this quote opens a text that never closes: the single-quoted " ++
        "text before it ended at the apostrophe in `it's`" ++ apostrophe_tail ++ "|'it's");
    try expectRefusal("print(out, 'the cat's toy', 'b')", "E_BYTE_LITERAL|this quote opens a text that never closes: the " ++
        "single-quoted text before it ended at the apostrophe in `cat's`" ++ apostrophe_tail ++ "|cat's");
}

test "two apostrophes that close each other name the first where the parser stops" {
    try expectRefusal("const x = 'the cat's toy and the dog's'", "E_SYNTAX|unexpected token; expected a newline: the single-quoted " ++
        "text before it ended at the apostrophe in `cat's`" ++ apostrophe_tail ++ "|cat's");
}

test "a double quote inside a word of a double-quoted text is named" {
    try expectRefusal("print(out, \"a\"b c\")", "E_BYTE_LITERAL|this quote opens a text that never closes: the double-quoted text " ++
        "before it ended at the quote in `a\"b` (the note), so what followed was read as code; write that text in single quotes, " ++
        "or escape the quote as \\\"| \"a\"b");
}

test "a literal that really never closes is named for what it is" {
    try expectRefusal("print(out, \"don't\" + 'abc)", "E_BYTE_LITERAL|unterminated text: a text closes on its line with the quote that " ++
        "opened it; escape newlines with \\n|");
    try expectRefusal("print(out, f'abc {1})", "E_BYTE_LITERAL|unterminated format string: it closes on its line with the quote " ++
        "that opened it; escape newlines with \\n|");
    try expectRefusal("print(out, b'abc)", "E_BYTE_LITERAL|unterminated byte literal; escape newlines with \\n|");
}

test "an escaped apostrophe and a literal before a keyword are not taken for an ended text" {
    var escaped = try language.Compilation.init(t.allocator, "escaped.selka", "func main(out: Stream) -> int:\n    print(out, 'it\\'s here')\n    return 0\n");
    defer escaped.deinit();
    try escaped.check();
    try expectRefusal("print(out, 'a'in 'abc)", "E_BYTE_LITERAL|unterminated text: a text closes on its line with the quote that " ++
        "opened it; escape newlines with \\n|");
}

fn meaningOf(code: []const u8) []const u8 {
    for (@import("diagnostic_codes.zig").entries) |entry| if (std.mem.eql(u8, entry.code, code)) return entry.meaning;
    return "";
}

test "the E_BYTE_LITERAL row says it covers texts and format strings, not only byte literals" {
    try t.expectEqualStrings("a quoted literal (a text, a format string or a byte literal) is malformed or unterminated", meaningOf("E_BYTE_LITERAL"));
}
