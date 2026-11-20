//! Why `selka fmt --check` says a file differs: the first place where the written text and the canonical text part,
//! said in one clause. The formatter compares whole texts, so the reason is read off the two texts at that place: a run of
//! blank lines of another length, trailing whitespace, another indent, a missing final newline, or else the two lines.
const std = @import("std");

/// The longest piece of a line the clause quotes before it ends it with `...`.
const quote_limit = 50;

/// The offset of the first byte at which `written` and `wanted` differ; the length of the shorter text when it is a
/// prefix of the other.
pub fn firstDifference(written: []const u8, wanted: []const u8) usize {
    var offset: usize = 0;
    while (offset < @min(written.len, wanted.len) and written[offset] == wanted[offset]) : (offset += 1) {}
    return offset;
}

/// The clause that says what the formatter wants at the first difference between `written` and `wanted`, which must differ.
/// The caller owns the result.
pub fn reason(allocator: std.mem.Allocator, written: []const u8, wanted: []const u8) std.mem.Allocator.Error![]u8 {
    const at = firstDifference(written, wanted);
    if (at == written.len and std.mem.eql(u8, wanted[at..], "\n")) return allocator.dupe(u8, "the file does not end with a newline");
    if (at == wanted.len and isBlank(written[at..])) return allocator.dupe(u8, "the file ends with blank lines the formatter drops");
    const start = lineStart(written, at);
    var run = start;
    while (run > 0 and isBlank(written[lineStart(written, run - 1) .. run - 1])) run = lineStart(written, run - 1);
    const line = lineNumber(written, start);
    const here = written[start..lineEnd(written, start)];
    const there = wanted[start..lineEnd(wanted, start)];
    if (run < start or isBlank(here) or isBlank(there)) {
        const before = blankRun(written, run);
        const after = blankRun(wanted, run);
        if (before != after) return blankLines(allocator, lineNumber(written, run) - 1, before, after, wanted[skipLines(wanted, run, after)..]);
    }
    if (std.mem.eql(u8, std.mem.trimEnd(u8, here, " \t\r"), there)) return std.fmt.allocPrint(allocator, "line {d} has trailing whitespace", .{line});
    const indent_here = here.len - std.mem.trimStart(u8, here, " \t").len;
    const indent_there = there.len - std.mem.trimStart(u8, there, " \t").len;
    if (std.mem.eql(u8, here[indent_here..], there[indent_there..])) {
        return std.fmt.allocPrint(allocator, "line {d} is indented {d} characters and the formatter wants {d}", .{ line, indent_here, indent_there });
    }
    return std.fmt.allocPrint(allocator, "line {d} reads `{s}{s}` and the formatter wants `{s}{s}`", .{
        line, quoted(here), ellipsis(here), quoted(there), ellipsis(there),
    });
}

/// The clause for a run of blank lines of another length: `after_line` is the line before the run (0 at the start of the
/// file), `before` the blank lines written, `after` the ones wanted and `next` the text the run is wanted to lead to.
fn blankLines(allocator: std.mem.Allocator, after_line: usize, before: usize, after: usize, next: []const u8) std.mem.Allocator.Error![]u8 {
    if (next.len == 0) return std.fmt.allocPrint(allocator, "line {d} is followed by blank lines at the end of the file, which the formatter drops", .{after_line});
    const top_level = after_line > 0 and next[0] != ' ' and next[0] != '\t';
    const place: []const u8 = if (top_level) " between top-level declarations" else "";
    if (after_line == 0) return std.fmt.allocPrint(allocator, "the file starts with {s} where the formatter wants {s}", .{ blankWords(before), blankWords(after) });
    return std.fmt.allocPrint(allocator, "line {d} is followed by {s}, and the formatter wants {s}{s}", .{ after_line, blankWords(before), blankWords(after), place });
}

/// A count of blank lines in words: `no blank line`, `one blank line`, `two blank lines`, up to four.
fn blankWords(count: usize) []const u8 {
    return switch (count) {
        0 => "no blank line",
        1 => "one blank line",
        2 => "two blank lines",
        3 => "three blank lines",
        4 => "four blank lines",
        else => "more blank lines",
    };
}

/// The piece of `line` the clause quotes: its first `quote_limit` bytes, cut before a partial character.
fn quoted(line: []const u8) []const u8 {
    if (line.len <= quote_limit) return line;
    var end: usize = quote_limit;
    while (end > 0 and line[end] & 0xC0 == 0x80) end -= 1;
    return line[0..end];
}

/// `...` when `quoted` cut the line, else nothing.
fn ellipsis(line: []const u8) []const u8 {
    return if (line.len > quote_limit) "..." else "";
}

/// Whether `text` holds only spaces, tabs, carriage returns and line breaks.
fn isBlank(text: []const u8) bool {
    return std.mem.trim(u8, text, " \t\r\n").len == 0;
}

/// The offset where the line holding `offset` begins.
fn lineStart(text: []const u8, offset: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, text[0..offset], '\n')) |newline| newline + 1 else 0;
}

/// The offset of the line break that ends the line starting at `start`, or the length of the text.
fn lineEnd(text: []const u8, start: usize) usize {
    return std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
}

/// The one-based number of the line starting at `start`.
fn lineNumber(text: []const u8, start: usize) usize {
    return std.mem.count(u8, text[0..start], "\n") + 1;
}

/// How many blank lines, each ended by a line break, follow one another from the line starting at `start`.
fn blankRun(text: []const u8, start: usize) usize {
    var count: usize = 0;
    var at = start;
    while (at < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse break;
        if (!isBlank(text[at..end])) break;
        count += 1;
        at = end + 1;
    }
    return count;
}

/// The offset after `count` blank lines from `start`.
fn skipLines(text: []const u8, start: usize, count: usize) usize {
    var at = start;
    var left = count;
    while (left > 0 and at < text.len) : (left -= 1) at = (std.mem.indexOfScalarPos(u8, text, at, '\n') orelse return text.len) + 1;
    return at;
}
