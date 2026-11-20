//! The change-note titles filed under each release, for the project page. A release's
//! notes are the `.md` files of `<changes>/<release>/`, read in file-name order, so the
//! titles come out in the same order on every run. A missing directory has no notes.
const std = @import("std");
const store = @import("overview_store.zig");
const change_notes = @import("change_notes.zig");

/// Failure to read a release's notes: allocation, or a note or directory that cannot be read.
pub const Error = std.mem.Allocator.Error || error{HostIo};

/// Largest change note the page reads, as the release loader reads Markdown.
const max_note_bytes = 1 << 20;

/// One release and the titles of the change notes filed under it, in file-name order.
pub const Release = struct { name: []const u8, titles: []const []const u8 };

/// The titles of the change notes under each release of `history`, in the order of `history`.
/// `root` is the project directory and `changes` its configured change-note directory.
pub fn releaseNotes(a: std.mem.Allocator, io: std.Io, root: []const u8, changes: []const u8, history: []const store.Release) Error![]const Release {
    var out: std.ArrayList(Release) = .empty;
    for (history) |release| {
        const directory = try std.fs.path.join(a, &.{ root, changes, release.name });
        try out.append(a, .{ .name = release.name, .titles = try titlesIn(a, io, directory) });
    }
    return out.items;
}

/// The title of every `.md` change note in `directory`, in file-name order. A note with no
/// title is named by its file.
fn titlesIn(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error![]const []const u8 {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return error.HostIo,
    };
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = dir.iterate();
    while (iterator.next(io) catch return error.HostIo) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".md")) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    var titles: std.ArrayList([]const u8) = .empty;
    for (names.items) |name| {
        const path = try std.fs.path.join(a, &.{ directory, name });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(max_note_bytes)) catch return error.HostIo;
        const parsed = try change_notes.parse(a, name, bytes);
        try titles.append(a, if (parsed.note.title.len != 0) parsed.note.title else name);
    }
    return titles.items;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

test "overview notes lists each release's change-note titles in file-name order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "changes/0.1");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "changes/0.1/b-second.md", .data = "# Second change\n\nSummary: The second change does something useful for a reader.\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "changes/0.1/a-first.md", .data = "# First change\n\nSummary: The first change does something useful for a reader.\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const history = [_]store.Release{ .{ .name = "0.1", .decisions = 0, .notes = 2 }, .{ .name = "0.0", .decisions = 0 } };
    const releases = try releaseNotes(a, std.testing.io, root, "changes", &history);
    try std.testing.expectEqual(@as(usize, 2), releases.len);
    try std.testing.expectEqualStrings("0.1", releases[0].name);
    try std.testing.expectEqualStrings("First change", releases[0].titles[0]);
    try std.testing.expectEqualStrings("Second change", releases[0].titles[1]);
    try std.testing.expectEqual(@as(usize, 0), releases[1].titles.len);
}
