//! Change notes: one short plain-English paragraph per change, read from
//! `<changes>/unreleased/<slug>.md` and filed under a release by `release cut`.
const std = @import("std");
const decisions = @import("release_decisions.zig");

/// One change note: its title, its Summary paragraph and the prose after it.
pub const Note = struct { path: []const u8, title: []const u8, summary: []const u8, body: []const u8 };

/// A parsed note with every rule it breaks; a note with issues is still returned.
pub const Parsed = struct { note: Note, issues: []const decisions.Issue };

const invalid_code = "E_REVIEW_NOTE_INVALID";
const min_characters = 40;
const max_words = 120;
const summary_label = "Summary:";

/// One visible line: its 1-based number in the file and its text without comments.
const Line = struct { number: usize, text: []const u8 };

/// Parse one note from its bytes. Every failure is one located issue; all
/// allocations belong to `allocator`, normally a command arena.
pub fn parse(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!Parsed {
    const lines = try visibleLines(allocator, bytes);
    var issues: std.ArrayList(decisions.Issue) = .empty;
    var first: usize = 0;
    while (first < lines.len and lines[first].text.len == 0) first += 1;
    const title_line: usize = if (first < lines.len) lines[first].number else 1;
    var title: []const u8 = "";
    if (first < lines.len and std.mem.startsWith(u8, lines[first].text, "# ")) title = std.mem.trim(u8, lines[first].text[2..], " \t");
    if (title.len == 0 or placeholder(title)) try problem(allocator, &issues, path, title_line, "the first line must be a non-placeholder # Title");
    var summary_start: ?usize = null;
    for (lines, 0..) |line, index| {
        if (std.mem.startsWith(u8, line.text, summary_label)) {
            summary_start = index;
            break;
        }
    }
    const paragraph = try summaryParagraph(allocator, lines, summary_start);
    if (summary_start == null) {
        try problem(allocator, &issues, path, 1, "a change note needs a Summary: paragraph");
    } else {
        const line = lines[summary_start.?].number;
        const characters = nonWhitespace(paragraph.text);
        if (characters < min_characters) try problem(allocator, &issues, path, line, try std.fmt.allocPrint(allocator, "the summary has {d} non-whitespace characters; it needs at least {d}", .{ characters, min_characters }));
        const words = wordCount(paragraph.text);
        if (words > max_words) try problem(allocator, &issues, path, line, try std.fmt.allocPrint(allocator, "the summary has {d} words; keep it to {d}", .{ words, max_words }));
        if (placeholder(paragraph.text)) try problem(allocator, &issues, path, line, "the summary still holds a placeholder");
    }
    return .{
        .note = .{ .path = path, .title = title, .summary = paragraph.text, .body = try bodyAfter(allocator, lines, paragraph.end) },
        .issues = try issues.toOwnedSlice(allocator),
    };
}

/// Append one located `E_REVIEW_NOTE_INVALID` issue.
fn problem(allocator: std.mem.Allocator, issues: *std.ArrayList(decisions.Issue), path: []const u8, line: usize, message: []const u8) std.mem.Allocator.Error!void {
    try issues.append(allocator, .{ .code = invalid_code, .path = path, .line = line, .message = message });
}

/// The Summary paragraph text and the index of the first line after it.
const Paragraph = struct { text: []const u8, end: usize };

/// Join the Summary paragraph's lines, trimmed, with single spaces.
fn summaryParagraph(allocator: std.mem.Allocator, lines: []const Line, start: ?usize) std.mem.Allocator.Error!Paragraph {
    const first = start orelse return .{ .text = "", .end = lines.len };
    var text: std.ArrayList(u8) = .empty;
    var index = first;
    while (index < lines.len and lines[index].text.len != 0) : (index += 1) {
        const piece = if (index == first) std.mem.trim(u8, lines[index].text[summary_label.len..], " \t") else lines[index].text;
        if (piece.len == 0) continue;
        if (text.items.len != 0) try text.append(allocator, ' ');
        try text.appendSlice(allocator, piece);
    }
    return .{ .text = try text.toOwnedSlice(allocator), .end = index };
}

/// Every line after the summary paragraph, joined, with leading and trailing blank lines removed.
fn bodyAfter(allocator: std.mem.Allocator, lines: []const Line, end: usize) std.mem.Allocator.Error![]const u8 {
    var body: std.ArrayList(u8) = .empty;
    for (lines[end..], 0..) |line, index| {
        if (index != 0) try body.append(allocator, '\n');
        try body.appendSlice(allocator, line.text);
    }
    return std.mem.trim(u8, body.items, " \t\r\n");
}

/// The file's lines with every HTML comment removed. A line that holds only
/// comments disappears, so it neither ends a paragraph nor counts as blank.
fn visibleLines(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const Line {
    var result: std.ArrayList(Line) = .empty;
    var in_comment = false;
    var numbered = std.mem.splitScalar(u8, bytes, '\n');
    var number: usize = 0;
    while (numbered.next()) |raw| {
        number += 1;
        var text: std.ArrayList(u8) = .empty;
        var had_comment = false;
        var rest = raw;
        while (true) {
            if (in_comment) {
                had_comment = true;
                const close = std.mem.indexOf(u8, rest, "-->") orelse {
                    rest = "";
                    break;
                };
                rest = rest[close + 3 ..];
                in_comment = false;
            } else {
                const open = std.mem.indexOf(u8, rest, "<!--") orelse {
                    try text.appendSlice(allocator, rest);
                    break;
                };
                try text.appendSlice(allocator, rest[0..open]);
                had_comment = true;
                rest = rest[open + 4 ..];
                in_comment = true;
            }
        }
        const visible = std.mem.trim(u8, text.items, " \t\r");
        if (had_comment and visible.len == 0) continue;
        try result.append(allocator, .{ .number = number, .text = visible });
    }
    return result.items;
}

/// Whether text still holds TODO, TBD or FIXME as a whole word, or a `<summary>` marker, in any letter case.
fn placeholder(text: []const u8) bool {
    for ([_][]const u8{ "TODO", "TBD", "FIXME" }) |word| if (containsWord(text, word)) return true;
    return containsFold(text, "<summary>");
}

fn containsWord(text: []const u8, word: []const u8) bool {
    if (text.len < word.len) return false;
    for (0..text.len - word.len + 1) |offset| {
        if (!std.ascii.eqlIgnoreCase(text[offset..][0..word.len], word)) continue;
        const before_ok = offset == 0 or !std.ascii.isAlphanumeric(text[offset - 1]);
        const after = offset + word.len;
        const after_ok = after == text.len or !std.ascii.isAlphanumeric(text[after]);
        if (before_ok and after_ok) return true;
    }
    return false;
}

fn containsFold(text: []const u8, needle: []const u8) bool {
    if (text.len < needle.len) return false;
    for (0..text.len - needle.len + 1) |offset| {
        if (std.ascii.eqlIgnoreCase(text[offset..][0..needle.len], needle)) return true;
    }
    return false;
}

/// Count characters that are not whitespace; UTF-8 continuation bytes are not counted.
fn nonWhitespace(text: []const u8) usize {
    var count: usize = 0;
    for (text) |byte| {
        if (std.ascii.isWhitespace(byte) or byte & 0xC0 == 0x80) continue;
        count += 1;
    }
    return count;
}

fn wordCount(text: []const u8) usize {
    var words = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var count: usize = 0;
    while (words.next()) |_| count += 1;
    return count;
}
