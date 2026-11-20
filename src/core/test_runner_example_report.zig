//! Exact stdout transcript comparison for one generated docstring test.
const std = @import("std");
const source = @import("selka").docstring_example_source;
const report = @import("test_runner_report.zig");

/// Compare each prompt's complete output; markers delimit even empty statements. An example that returned leaves
/// the ending out of its output (`docs/functions.md`, "Runnable examples"): the prompt it returned in is then compared on
/// the output it had written, and a prompt after it, which never ran, fails as not reached.
pub fn grade(a: std.mem.Allocator, name: []const u8, transcript: source.Transcript, output: []const u8) std.mem.Allocator.Error!report.Verdict {
    var offset: usize = 0;
    const finished = std.mem.endsWith(u8, output, transcript.ending);
    for (transcript.sections, 0..) |section, index| {
        if (!std.mem.startsWith(u8, output[offset..], section.marker)) return failure(a, name, transcript.path, section, output[offset..]);
        offset += section.marker.len;
        const next = if (index + 1 < transcript.sections.len) transcript.sections[index + 1].marker else transcript.ending;
        const end = std.mem.indexOfPos(u8, output, offset, next) orelse {
            if (finished or !std.mem.eql(u8, section.text, output[offset..])) return failure(a, name, transcript.path, section, output[offset..]);
            if (index + 1 == transcript.sections.len) return .{ .name = name, .status = .passed };
            return notReached(a, name, transcript.path, section, transcript.sections[index + 1]);
        };
        if (!std.mem.eql(u8, section.text, output[offset..end])) return failure(a, name, transcript.path, section, output[offset..end]);
        offset = end;
    }
    if (!std.mem.eql(u8, output[offset..], transcript.ending)) return failure(a, name, transcript.path, transcript.sections[transcript.sections.len - 1], output[offset..]);
    return .{ .name = name, .status = .passed };
}

/// The verdict of an example that returned `False`: its output matched, but a `return False` fails the case, at the
/// last prompt that ran.
pub fn returnedFalse(a: std.mem.Allocator, name: []const u8, transcript: source.Transcript, output: []const u8) std.mem.Allocator.Error!report.Verdict {
    var line = transcript.sections[0].line;
    for (transcript.sections) |section| {
        if (std.mem.indexOf(u8, output, section.marker) == null) break;
        line = section.line;
    }
    return .{
        .name = name,
        .status = .failed,
        .at = try std.fmt.allocPrint(a, "{s}:{d}", .{ transcript.path, line }),
        .reason = try std.fmt.allocPrint(a, "{s}:{d}: the example returned False: a `return` ends it there, and `return False` fails the case", .{ transcript.path, line }),
    };
}

/// Report a trapped trial at its last reached prompt without exposing delimiters.
pub fn interrupted(a: std.mem.Allocator, name: []const u8, transcript: source.Transcript, diagnostics: []const u8, output: []const u8) std.mem.Allocator.Error!report.Verdict {
    var visible: std.ArrayList(u8) = .empty;
    var offset: usize = 0;
    var line = transcript.sections[0].line;
    for (transcript.sections) |section| {
        const start = std.mem.indexOfPos(u8, output, offset, section.marker) orelse break;
        try visible.appendSlice(a, output[offset..start]);
        offset = start + section.marker.len;
        line = section.line;
    }
    const end = std.mem.indexOfPos(u8, output, offset, transcript.ending) orelse output.len;
    try visible.appendSlice(a, output[offset..end]);
    return .{
        .name = name,
        .status = .failed,
        .at = try std.fmt.allocPrint(a, "{s}:{d}", .{ transcript.path, line }),
        .reason = if (visible.items.len == 0) diagnostics else try std.fmt.allocPrint(a, "{s}\n{s}", .{ diagnostics, visible.items }),
    };
}

fn notReached(a: std.mem.Allocator, name: []const u8, path: []const u8, returned: source.Expected, skipped: source.Expected) std.mem.Allocator.Error!report.Verdict {
    return .{
        .name = name,
        .status = .failed,
        .at = try std.fmt.allocPrint(a, "{s}:{d}", .{ path, skipped.line }),
        .reason = try std.fmt.allocPrint(a, "{s}:{d}: this prompt did not run: the example returned in the prompt at line {d}", .{ path, skipped.line, returned.line }),
    };
}

fn failure(a: std.mem.Allocator, name: []const u8, path: []const u8, section: source.Expected, actual: []const u8) std.mem.Allocator.Error!report.Verdict {
    return .{
        .name = name,
        .status = .failed,
        .at = try std.fmt.allocPrint(a, "{s}:{d}", .{ path, section.line }),
        .reason = try std.fmt.allocPrint(a, "{s}:{d}: expected {s}, got {s}", .{ path, section.line, try std.json.Stringify.valueAlloc(a, section.text, .{}), try std.json.Stringify.valueAlloc(a, actual, .{}) }),
    };
}

test "docstring example output comparison keeps stdout values whitespace and statement boundaries exact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const transcript: source.Transcript = .{ .path = "library.selka", .sections = &.{ .{ .marker = "<a>", .text = "hello\n'world'\n\n", .line = 7 }, .{ .marker = "<b>", .text = "", .line = 12 } }, .ending = "<end>" };
    const passed = try grade(a, "library::greet.example", transcript, "<a>hello\n'world'\n\n<b><end>");
    try std.testing.expectEqual(report.Status.passed, passed.status);
    const wrong = try grade(a, passed.name, transcript, "<a>hello\nworld\n\n<b><end>");
    try std.testing.expectEqual(report.Status.failed, wrong.status);
    try std.testing.expectEqualStrings("library.selka:7", wrong.at);
    const moved = try grade(a, passed.name, transcript, "<a>hello\n'world'\n<b>\n<end>");
    try std.testing.expectEqual(report.Status.failed, moved.status);
    // An output that stops after the last prompt's marker is an example that returned there (below).
    const cut = try grade(a, passed.name, transcript, "<a>hello\n'world'\n\n<b>");
    try std.testing.expectEqual(report.Status.passed, cut.status);
    const lost = try grade(a, passed.name, transcript, "<a>hello\n'world'\n\n");
    try std.testing.expectEqual(report.Status.failed, lost.status);
}

test "docstring example interrupted trial hides boundaries and identifies the reached prompt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const transcript: source.Transcript = .{ .path = "library.selka", .sections = &.{ .{ .marker = "<a>", .text = "hello\n", .line = 7 }, .{ .marker = "<b>", .text = "", .line = 12 } }, .ending = "<end>" };
    const trapped = try interrupted(a, "library::greet.example", transcript, "R_LIST_BOUNDS", "<a>hello\n<b>");
    try std.testing.expectEqualStrings("library.selka:12", trapped.at);
    try std.testing.expectEqualStrings("R_LIST_BOUNDS\nhello\n", trapped.reason);
    const early = try interrupted(a, trapped.name, transcript, "R_STEP_LIMIT", "");
    try std.testing.expectEqualStrings("library.selka:7", early.at);
    try std.testing.expectEqualStrings("R_STEP_LIMIT", early.reason);
}

test "docstring example output comparison takes the output so far of an example that returned and fails a prompt it never reached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const transcript: source.Transcript = .{ .path = "library.selka", .sections = &.{ .{ .marker = "<a>", .text = "oops\n", .line = 7 }, .{ .marker = "<b>", .text = "", .line = 12 } }, .ending = "<end>" };
    const last = source.Transcript{ .path = "library.selka", .sections = transcript.sections[0..1], .ending = "<end>" };
    const returned = try grade(a, "library::g.example", last, "<a>oops\n");
    try std.testing.expectEqual(report.Status.passed, returned.status);
    const different = try grade(a, returned.name, last, "<a>other\n");
    try std.testing.expectEqual(report.Status.failed, different.status);
    try std.testing.expectEqualStrings("library.selka:7: expected \"oops\\n\", got \"other\\n\"", different.reason);
    const before = try grade(a, returned.name, transcript, "<a>oops\n");
    try std.testing.expectEqual(report.Status.failed, before.status);
    try std.testing.expectEqualStrings("library.selka:12", before.at);
    try std.testing.expectEqualStrings("library.selka:12: this prompt did not run: the example returned in the prompt at line 7", before.reason);
    const silent = try returnedFalse(a, returned.name, transcript, "<a>oops\n");
    try std.testing.expectEqualStrings("library.selka:7", silent.at);
    const second = try returnedFalse(a, returned.name, transcript, "<a>oops\n<b>");
    try std.testing.expectEqualStrings("library.selka:12", second.at);
}
