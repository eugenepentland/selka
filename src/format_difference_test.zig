//! What `fmt --check` says about the first place a file differs from its canonical layout.
const std = @import("std");
const t = std.testing;
const format_difference = @import("format_difference.zig");

/// The clause for `written` against `wanted`, freed by the caller.
fn clause(written: []const u8, wanted: []const u8) ![]u8 {
    return format_difference.reason(t.allocator, written, wanted);
}

// W5-F-9: one blank line between module-level constants where the formatter wants two was "formatting differs" and nothing else.
test "a blank line short of the two between top-level declarations says so" {
    const found = try clause("const A: int = 1\n\nconst B: int = 2\n", "const A: int = 1\n\n\nconst B: int = 2\n");
    defer t.allocator.free(found);
    try t.expectEqualStrings("line 1 is followed by one blank line, and the formatter wants two blank lines between top-level declarations", found);
    try t.expectEqual(@as(usize, 18), format_difference.firstDifference("const A: int = 1\n\nconst B: int = 2\n", "const A: int = 1\n\n\nconst B: int = 2\n"));
}

test "blank lines the formatter drops are counted where they stand" {
    const inside = try clause("func f() -> int:\n    x = 1\n\n    return x\n", "func f() -> int:\n    x = 1\n    return x\n");
    defer t.allocator.free(inside);
    try t.expectEqualStrings("line 2 is followed by one blank line, and the formatter wants no blank line", inside);
    const start = try clause("\nfunc f() -> int:\n", "func f() -> int:\n");
    defer t.allocator.free(start);
    try t.expectEqualStrings("the file starts with one blank line where the formatter wants no blank line", start);
    const end = try clause("func f() -> int:\n    return 1\n\n\n", "func f() -> int:\n    return 1\n");
    defer t.allocator.free(end);
    try t.expectEqualStrings("the file ends with blank lines the formatter drops", end);
    const four = try clause("a\n\n\n\n\nb\n", "a\n\n\nb\n");
    defer t.allocator.free(four);
    try t.expectEqualStrings("line 1 is followed by four blank lines, and the formatter wants two blank lines between top-level declarations", four);
    const many = try clause("a\n\n\n\n\n\n\nb\n", "a\n\n\nb\n");
    defer t.allocator.free(many);
    try t.expectEqualStrings("line 1 is followed by more blank lines, and the formatter wants two blank lines between top-level declarations", many);
}

test "a missing final newline, trailing whitespace and another indent are named" {
    const newline = try clause("func f() -> int:\n    return 1", "func f() -> int:\n    return 1\n");
    defer t.allocator.free(newline);
    try t.expectEqualStrings("the file does not end with a newline", newline);
    const trailing = try clause("x = 1  \ny = 2\n", "x = 1\ny = 2\n");
    defer t.allocator.free(trailing);
    try t.expectEqualStrings("line 1 has trailing whitespace", trailing);
    const indent = try clause("func f() -> int:\n        return 1\n", "func f() -> int:\n    return 1\n");
    defer t.allocator.free(indent);
    try t.expectEqualStrings("line 2 is indented 8 characters and the formatter wants 4", indent);
}

test "any other difference quotes the line as written and as wanted, cut at fifty bytes" {
    const spaced = try clause("func  main( ) -> int:\n", "func main() -> int:\n");
    defer t.allocator.free(spaced);
    try t.expectEqualStrings("line 1 reads `func  main( ) -> int:` and the formatter wants `func main() -> int:`", spaced);
    const written = "const NAME: str = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"\n";
    const wanted = "const NAME: str = \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"\n";
    const wide = try clause(written, wanted);
    defer t.allocator.free(wide);
    try t.expectEqualStrings("line 1 reads `const NAME: str = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...` and the formatter wants `const NAME: str = \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...`", wide);
}
