//! Pure tests for change-note parsing: the title, the Summary paragraph, its limits and placeholders.
const std = @import("std");
const t = std.testing;
const notes = @import("change_notes.zig");
const language = @import("compiler.zig");

const path = "changes/unreleased/x.md";
const summary = "`serve` now runs one event loop with a 1,024-slot connection table, back-pressure and an idle timeout.";

fn parseNote(arena: *std.heap.ArenaAllocator, bytes: []const u8) !notes.Parsed {
    return notes.parse(arena.allocator(), path, bytes);
}

/// A comptime run of `count` words, each followed by one space.
fn words(comptime count: usize) []const u8 {
    return comptime blk: {
        var text: []const u8 = "";
        for (0..count) |_| text = text ++ "word ";
        break :blk text;
    };
}

fn expectIssue(parsed: notes.Parsed, index: usize, line: usize, message: []const u8) !void {
    try t.expectEqualStrings("E_REVIEW_NOTE_INVALID", parsed.issues[index].code);
    try t.expectEqualStrings(path, parsed.issues[index].path);
    try t.expectEqual(line, parsed.issues[index].line);
    try t.expectEqualStrings(message, parsed.issues[index].message);
}

test "change note accepts a title, a summary and a body after it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try parseNote(&arena, "# Serve on the event loop\n\nSummary: " ++ summary ++ "\n\nDetails follow here.\n");
    try t.expectEqual(@as(usize, 0), parsed.issues.len);
    try t.expectEqualStrings(path, parsed.note.path);
    try t.expectEqualStrings("Serve on the event loop", parsed.note.title);
    try t.expectEqualStrings(summary, parsed.note.summary);
    try t.expectEqualStrings("Details follow here.", parsed.note.body);
}

test "change note ignores HTML comments and joins a multi-line summary" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const bytes =
        \\<!-- drafted by hand -->
        \\# Serve on the event loop
        \\<!-- a comment
        \\spanning two lines -->
        \\Summary: `serve` now runs one event loop
        \\<!-- inside a summary -->
        \\with a 1,024-slot connection table and
        \\back-pressure.
        \\
        \\<!-- trailing comment -->
        \\More prose.
        \\
    ;
    const parsed = try parseNote(&arena, bytes);
    try t.expectEqual(@as(usize, 0), parsed.issues.len);
    try t.expectEqualStrings("Serve on the event loop", parsed.note.title);
    try t.expectEqualStrings("`serve` now runs one event loop with a 1,024-slot connection table and back-pressure.", parsed.note.summary);
    try t.expectEqualStrings("More prose.", parsed.note.body);
}

test "change note needs a non-placeholder title on its first line" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const missing = try parseNote(&arena, "Summary: " ++ summary ++ "\n");
    try t.expectEqual(@as(usize, 1), missing.issues.len);
    try expectIssue(missing, 0, 1, "the first line must be a non-placeholder # Title");
    const placeholder_title = try parseNote(&arena, "# TODO: title of this change\n\nSummary: " ++ summary ++ "\n");
    try t.expectEqual(@as(usize, 1), placeholder_title.issues.len);
    try expectIssue(placeholder_title, 0, 1, "the first line must be a non-placeholder # Title");
    const no_space = try parseNote(&arena, "#Serve on the event loop\n\nSummary: " ++ summary ++ "\n");
    try t.expectEqual(@as(usize, 1), no_space.issues.len);
    try expectIssue(no_space, 0, 1, "the first line must be a non-placeholder # Title");
}

test "change note needs a Summary paragraph" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try parseNote(&arena, "# Serve on the event loop\n\nJust prose, with no summary paragraph at all.\n");
    try t.expectEqual(@as(usize, 1), parsed.issues.len);
    try expectIssue(parsed, 0, 1, "a change note needs a Summary: paragraph");
    try t.expectEqualStrings("", parsed.note.summary);
}

test "change note counts the summary's non-whitespace characters" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try parseNote(&arena, "# Serve on the event loop\n\nSummary: Too short.\n");
    try t.expectEqual(@as(usize, 1), parsed.issues.len);
    try expectIssue(parsed, 0, 3, "the summary has 9 non-whitespace characters; it needs at least 40");
    const exact = try parseNote(&arena, "# Serve on the event loop\n\nSummary: 0123456789012345678901234567890123456789\n");
    try t.expectEqual(@as(usize, 0), exact.issues.len);
}

test "change note keeps the summary to 120 words" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const long = try parseNote(&arena, "# Serve on the event loop\n\nSummary: " ++ comptime words(121) ++ "\n");
    try t.expectEqual(@as(usize, 1), long.issues.len);
    try expectIssue(long, 0, 3, "the summary has 121 words; keep it to 120");
    const limit = try parseNote(&arena, "# Serve on the event loop\n\nSummary: " ++ comptime words(120) ++ "\n");
    try t.expectEqual(@as(usize, 0), limit.issues.len);
}

test "change note refuses a placeholder in the summary" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const todo = try parseNote(&arena, "# Serve on the event loop\n\nSummary: This summary still says TODO in the middle of a sentence.\n");
    try t.expectEqual(@as(usize, 1), todo.issues.len);
    try expectIssue(todo, 0, 3, "the summary still holds a placeholder");
    const lower = try parseNote(&arena, "# Serve on the event loop\n\nSummary: The fix is tbd for the other ports, and this text is long enough.\n");
    try t.expectEqual(@as(usize, 1), lower.issues.len);
    try expectIssue(lower, 0, 3, "the summary still holds a placeholder");
    const marker = try parseNote(&arena, "# Serve on the event loop\n\nSummary: <Summary> stands where the real words belong in this long sentence.\n");
    try t.expectEqual(@as(usize, 1), marker.issues.len);
    try expectIssue(marker, 0, 3, "the summary still holds a placeholder");
    const word = try parseNote(&arena, "# Serve on the event loop\n\nSummary: Mastodon clients now read the event loop and the idle timeout for every connection.\n");
    try t.expectEqual(@as(usize, 0), word.issues.len);
}

test "change note parser is reachable through the compiler module" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try language.change_notes.parse(arena.allocator(), path, "# Serve on the event loop\n\nSummary: " ++ summary ++ "\n");
    try t.expectEqual(@as(usize, 0), parsed.issues.len);
    try t.expectEqualStrings("Serve on the event loop", parsed.note.title);
}
