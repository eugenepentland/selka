//! The files a change touches beyond its interface: the generated sources, which the
//! review lists and does not diff, and the issue ids that comment lines add or remove.
//! Pure over the two sides' source files.
const std = @import("std");
const product = @import("product.zig");
const review_side = @import("review_side.zig");
const generated_marker = @import("generated_marker.zig");

/// Allocation is the only failure: the lists are built in memory.
pub const Error = std.mem.Allocator.Error;

/// A generated source the change adds, changes or removes. `first_line` is its first line
/// on the head, or on the base when the head no longer has it.
pub const Generated = struct { path: []const u8, first_line: []const u8, lines_before: usize, lines_after: usize };

/// One issue id a comment line names, with the file that holds the line.
pub const Citation = struct { id: []const u8, path: []const u8 };

/// The citations a change adds and removes, each de-duplicated by id and path.
pub const Citations = struct { added: []const Citation = &.{}, removed: []const Citation = &.{} };

/// The generated sources that differ between the sides, in path order. A generated file
/// is listed, never diffed: its declarations still count for the gate.
pub fn generatedChanges(a: std.mem.Allocator, base: []const review_side.File, head: []const review_side.File) Error![]const Generated {
    var out: std.ArrayList(Generated) = .empty;
    for (head) |file| {
        const before = findFile(base, file.path);
        if (before) |old| {
            if (std.mem.eql(u8, old.bytes, file.bytes)) continue;
        }
        const was_generated = if (before) |old| generated_marker.isGenerated(old.bytes) else false;
        if (!was_generated and !generated_marker.isGenerated(file.bytes)) continue;
        try out.append(a, .{
            .path = file.path,
            .first_line = firstLine(file.bytes),
            .lines_before = if (before) |old| std.mem.count(u8, old.bytes, "\n") else 0,
            .lines_after = std.mem.count(u8, file.bytes, "\n"),
        });
    }
    for (base) |file| {
        if (findFile(head, file.path) != null or !generated_marker.isGenerated(file.bytes)) continue;
        try out.append(a, .{ .path = file.path, .first_line = firstLine(file.bytes), .lines_before = std.mem.count(u8, file.bytes, "\n"), .lines_after = 0 });
    }
    std.mem.sort(Generated, out.items, {}, generatedLess);
    return out.items;
}

/// The citations that comment lines of the two sides add and remove. A comment line is one
/// whose first non-blank character is `#`. Generated files are not read.
pub fn citationChanges(a: std.mem.Allocator, base: []const review_side.File, head: []const review_side.File) Error!Citations {
    var added: std.ArrayList(Citation) = .empty;
    var removed: std.ArrayList(Citation) = .empty;
    var seen_added: std.StringHashMapUnmanaged(void) = .empty;
    var seen_removed: std.StringHashMapUnmanaged(void) = .empty;
    for (head) |file| {
        if (!isSource(file)) continue;
        const before = if (findFile(base, file.path)) |old| try commentSet(a, old.bytes) else std.StringHashMapUnmanaged(void).empty;
        try addCitations(a, &added, &seen_added, file, before);
    }
    for (base) |file| {
        if (!isSource(file)) continue;
        const after = if (findFile(head, file.path)) |new| try commentSet(a, new.bytes) else std.StringHashMapUnmanaged(void).empty;
        try addCitations(a, &removed, &seen_removed, file, after);
    }
    return .{ .added = added.items, .removed = removed.items };
}

/// Append the citations of the comment lines of `file` that `other` does not hold, once each by id and path.
fn addCitations(a: std.mem.Allocator, out: *std.ArrayList(Citation), seen: *std.StringHashMapUnmanaged(void), file: review_side.File, other: std.StringHashMapUnmanaged(void)) Error!void {
    var split = std.mem.splitScalar(u8, file.bytes, '\n');
    while (split.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!isComment(line) or other.contains(line)) continue;
        for (try citationIds(a, line)) |id| {
            const key = try std.fmt.allocPrint(a, "{s}\n{s}", .{ file.path, id });
            if ((try seen.getOrPut(a, key)).found_existing) continue;
            try out.append(a, .{ .id = id, .path = file.path });
        }
    }
}

/// The set of trimmed comment lines of a source text.
fn commentSet(a: std.mem.Allocator, bytes: []const u8) Error!std.StringHashMapUnmanaged(void) {
    var set: std.StringHashMapUnmanaged(void) = .empty;
    var split = std.mem.splitScalar(u8, bytes, '\n');
    while (split.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (isComment(line)) try set.put(a, line, {});
    }
    return set;
}

/// The issue ids of one line, in order. An id matches `[A-Z][A-Z0-9]*-[0-9]+`: an
/// uppercase letter, more uppercase letters or digits, a hyphen and one or more digits.
pub fn citationIds(a: std.mem.Allocator, line: []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    while (start < line.len) {
        if (citationEnd(line, start)) |end| {
            try out.append(a, line[start..end]);
            start = end;
        } else {
            start += 1;
        }
    }
    return out.items;
}

/// The end of the id that starts at `start`, or null when no id starts there.
fn citationEnd(line: []const u8, start: usize) ?usize {
    if (!isUpper(line[start])) return null;
    var index = start + 1;
    while (index < line.len and (isUpper(line[index]) or isDigit(line[index]))) index += 1;
    if (index >= line.len or line[index] != '-') return null;
    index += 1;
    const digits = index;
    while (index < line.len and isDigit(line[index])) index += 1;
    if (index == digits) return null;
    return index;
}

fn isUpper(byte: u8) bool {
    return byte >= 'A' and byte <= 'Z';
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn isComment(line: []const u8) bool {
    return line.len != 0 and line[0] == '#';
}

fn isSource(file: review_side.File) bool {
    return product.isSource(file.path) and !generated_marker.isGenerated(file.bytes);
}

fn findFile(files: []const review_side.File, path: []const u8) ?review_side.File {
    for (files) |file| {
        if (std.mem.eql(u8, file.path, path)) return file;
    }
    return null;
}

/// The first line of a file's bytes, without a trailing carriage return.
fn firstLine(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, '\n') orelse bytes.len;
    return std.mem.trimEnd(u8, bytes[0..end], "\r");
}

fn generatedLess(_: void, left: Generated, right: Generated) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

test "review files recognises a citation id and leaves other capitals alone" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const ids = try citationIds(scratch, "# FR-123: reason, see RFC-7231 and D9-2");
    try std.testing.expectEqual(@as(usize, 3), ids.len);
    try std.testing.expectEqualStrings("FR-123", ids[0]);
    try std.testing.expectEqualStrings("RFC-7231", ids[1]);
    try std.testing.expectEqualStrings("D9-2", ids[2]);
    try std.testing.expectEqual(@as(usize, 0), (try citationIds(scratch, "# fr-12 and FR- and A-x")).len);
}

test "review files takes the whole id when a longer capital run begins it" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ids = try citationIds(arena.allocator(), "# XFR-12");
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqualStrings("XFR-12", ids[0]);
}

test "review files lists a citation a comment line adds and a generated file that changes" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const base = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "public func answer() -> int:\n    return 42\n" },
        .{ .path = "ports.selka", .bytes = "# GENERATED by gen_ports.py\npublic func port() -> int:\n    return 1\n" },
    };
    const head = [_]review_side.File{
        .{ .path = "main.selka", .bytes = "# FR-123: reason\npublic func answer() -> int:\n    return 42\n" },
        .{ .path = "ports.selka", .bytes = "# GENERATED by gen_ports.py\npublic func port() -> int:\n    return 2\npublic func extra() -> int:\n    return 3\n" },
    };
    const citations = try citationChanges(scratch, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), citations.added.len);
    try std.testing.expectEqualStrings("FR-123", citations.added[0].id);
    try std.testing.expectEqualStrings("main.selka", citations.added[0].path);
    try std.testing.expectEqual(@as(usize, 0), citations.removed.len);
    const generated = try generatedChanges(scratch, &base, &head);
    try std.testing.expectEqual(@as(usize, 1), generated.len);
    try std.testing.expectEqualStrings("ports.selka", generated[0].path);
    try std.testing.expectEqualStrings("# GENERATED by gen_ports.py", generated[0].first_line);
    try std.testing.expectEqual(@as(usize, 3), generated[0].lines_before);
    try std.testing.expectEqual(@as(usize, 5), generated[0].lines_after);
}

test "review files de-duplicates a citation repeated in one file" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const head = [_]review_side.File{.{ .path = "main.selka", .bytes = "# FR-1: first\n# FR-1: again\n" }};
    const citations = try citationChanges(arena.allocator(), &.{}, &head);
    try std.testing.expectEqual(@as(usize, 1), citations.added.len);
}
