//! A module's text as the check reads it, without what the check never reads (test-loop stage 6, D-TL6-1 of
//! `experiments/test-loop-20261109/DECISIONS.md`): the digest the `module-tokens` engine kind records for a source, so
//! that the report of a test entry stays valid across an edit that changes only comments, blank lines, trailing
//! whitespace and the line numbers that follow from them.
//!
//! The digest is over the lexer's tokens (`lexer.lex`, layout delimiters included) and, for each token that has bytes,
//! the bytes between it and the token before it when they are on the same line, or a line break and the bytes from the
//! start of its line when it is the first token of a line, then the token's own bytes. So it keeps every byte of every
//! token (a string or docstring whole, with its own lines), every column and the spacing inside a line, and which tokens
//! begin a line; it leaves out a comment (the lexer skips `#` to the end of the line), a blank line, the whitespace that
//! ends a line, and how many lines lie between two tokens. Every reader of a source between the file and a test's verdict
//! or its report reads only what the digest keeps (the readers are listed in D-TL6-4).
const std = @import("std");
const language = @import("selka");

/// The digest's domain: a change to what the digest covers is a new domain.
const domain = "core-test-module-tokens-v1";

/// The digest of `bytes` as the check reads them, or null when the lexer refuses them (the caller then keys the bytes).
pub fn digest(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?[32]u8 {
    return language.token_digest.digest(a, bytes, domain);
}

fn same(a: std.mem.Allocator, left: []const u8, right: []const u8) !bool {
    const one = try digest(a, left);
    const other = try digest(a, right);
    try std.testing.expect(one != null and other != null);
    return std.mem.eql(u8, &one.?, &other.?);
}

const module =
    \\# The module's own comment.
    \\import lib
    \\
    \\
    \\public func value(n: int) -> int:
    \\    """The value of `n`, plus one."""
    \\    return n + 1  # a trailing comment
    \\
    \\
    \\public func test_value() -> bool:
    \\    return value(1) == 2
    \\
;

// spec: TEST-LOOP-TOKEN-REPORTS-1
test "a module's token digest ignores comments, blank lines, trailing whitespace and line numbers, and nothing else" {
    const a = std.testing.allocator;
    // What the check never reads: a comment reworded, a comment line added, a blank line, trailing whitespace.
    try std.testing.expect(try sameEdit(a, try replace(a, "# The module's own comment.", "# Another comment, longer.")));
    try std.testing.expect(try sameEdit(a, try replace(a, "import lib\n", "import lib\n# one more line\n\n")));
    try std.testing.expect(try sameEdit(a, try replace(a, "# a trailing comment", "")));
    try std.testing.expect(try sameEdit(a, try replace(a, "return value(1) == 2\n", "return value(1) == 2   \n")));
    // What it reads: a string or a docstring, a token, the spacing inside a line, the indentation, a line break.
    try std.testing.expect(!try sameEdit(a, try replace(a, "plus one.", "plus two.")));
    try std.testing.expect(!try sameEdit(a, try replace(a, "n + 1", "n + 2")));
    try std.testing.expect(!try sameEdit(a, try replace(a, "n + 1", "n  + 1")));
    try std.testing.expect(!try sameEdit(a, try replace(a, "    return value(1) == 2", "        return value(1) == 2")));
    try std.testing.expect(!try sameEdit(a, try replace(a, "value(1) == 2", "value(\n        1) == 2")));
    // A file the lexer refuses has no digest: the caller reads its bytes instead.
    try std.testing.expect((try digest(a, "public func f() -> int:\n\treturn 1\n")) == null);
}

/// Whether `edited` has the module's digest; frees it.
fn sameEdit(a: std.mem.Allocator, edited: []const u8) !bool {
    defer a.free(edited);
    return same(a, module, edited);
}

fn replace(a: std.mem.Allocator, needle: []const u8, replacement: []const u8) ![]const u8 {
    try std.testing.expect(std.mem.indexOf(u8, module, needle) != null);
    return std.mem.replaceOwned(u8, a, module, needle, replacement);
}
