//! `selka review index SITE_DIR`: the front page of a review site. It reads the project pages
//! and the review files the site refresh wrote, and writes `SITE_DIR/index.html`. Every
//! directory is read in name order, so two runs over the same site write the same bytes.
//! The site holds `projects/<name>/overview.json`, `changes/<branch>/<project>.review.json` for
//! open changes, `merged/<sha>/<project>.review.json` for landings, and two optional files:
//! `bypass.log` (tab-separated `utc old new reason` lines) and `gate-mode` (one word).
const std = @import("std");
const review_html = @import("review_html.zig");
const overview_collect = @import("overview_collect.zig");

/// Failure to build the index: allocation, or a site file or directory that cannot be read or written.
pub const Error = std.mem.Allocator.Error || error{HostIo};

/// The usage line for a wrong argument list.
const usage = "usage: selka review index SITE_DIR\n";
/// The page file the index writes in the site directory.
const index_file = "index.html";
/// The largest site file the index reads.
const max_file_bytes = 16 << 20;
/// The most landings each project lists.
const max_landed_per_project = 20;
/// The suffix of a review file, and of the overview file a project page keeps.
const review_suffix = ".review.json";
const overview_file = "overview.json";
/// The number of characters of a commit name the index shows.
const short_length = 12;

/// One project on the index: its directory name, its title, the first sentence of its summary and its page.
const Project = struct { name: []const u8, title: []const u8, summary: []const u8, link: []const u8 };

/// The verdict counts of one review: public declarations, those a decision explains, and refusals.
const Counts = struct { public: usize = 0, explained: usize = 0, refusals: usize = 0 };

/// One review row: its branch or landing name, its project, its verdict, its title, its counts,
/// its review page, and the reason of a bypass when the landing was bypassed.
const Row = struct { label: []const u8, project: []const u8, ok: bool, title: []const u8, counts: Counts, link: []const u8, bypass: ?[]const u8 };

/// The object the index page reads: the gate mode, the projects, the open changes and the landings.
const Data = struct { gate_mode: []const u8, projects: []const Project, changes: []const Row, landed: []const Row };

/// Run `review index SITE_DIR`: 0 when the index is written, 2 on a usage or host failure.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    if (args.len != 1 or args[0].len == 0 or args[0][0] == '-') {
        std.Io.File.stderr().writeStreamingAll(process.io, usage) catch return 2;
        return 2;
    }
    write(process, args[0]) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka review index: {s}\n", .{@errorName(err)}) catch "selka review index: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
    return 0;
}

/// Build the index of the site in `site` and write `site/index.html`.
fn write(process: std.process.Init, site: []const u8) !void {
    const a = process.arena.allocator();
    const io = process.io;
    var root = std.Io.Dir.cwd().openDir(io, site, .{}) catch return error.HostIo;
    defer root.close(io);
    const data = try build(a, io, root);
    const page = try review_html.siteIndex(a, try std.json.Stringify.valueAlloc(a, data, .{}));
    root.writeFile(io, .{ .sub_path = index_file, .data = page }) catch return error.HostIo;
}

/// Read every part of the site the index shows.
fn build(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) Error!Data {
    const log = (try readOptional(a, io, root, "bypass.log")) orelse "";
    const mode = std.mem.trim(u8, (try readOptional(a, io, root, "gate-mode")) orelse "", " \t\r\n");
    return .{
        .gate_mode = mode,
        .projects = try projects(a, io, root),
        .changes = try openChanges(a, io, root),
        .landed = try landedChanges(a, io, root, log),
    };
}

/// The project pages under `projects/`: one per directory that holds an overview, in name order.
fn projects(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) Error![]const Project {
    var out: std.ArrayList(Project) = .empty;
    var dir = (try openOptional(io, root, "projects")) orelse return &.{};
    defer dir.close(io);
    for (try namesIn(a, io, dir, .directory)) |name| {
        const bytes = (try readOptional(a, io, dir, try std.fs.path.join(a, &.{ name, overview_file }))) orelse continue;
        const value = try parseValue(a, bytes);
        const title = text(member(value, "title"));
        const summary = overview_collect.firstSentence(text(member(value, "summary")));
        try out.append(a, .{
            .name = name,
            .title = if (title.len != 0) title else name,
            .summary = summary,
            .link = try std.fmt.allocPrint(a, "projects/{s}/index.html", .{name}),
        });
    }
    return out.items;
}

/// The open changes: one row per `changes/<branch>/<project>.review.json`, by branch and then project.
fn openChanges(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) Error![]const Row {
    var out: std.ArrayList(Row) = .empty;
    var changes = (try openOptional(io, root, "changes")) orelse return &.{};
    defer changes.close(io);
    for (try namesIn(a, io, changes, .directory)) |branch| {
        var dir = (try openOptional(io, changes, branch)) orelse continue;
        defer dir.close(io);
        for (try reviewFiles(a, io, dir)) |file| {
            const project = file[0 .. file.len - review_suffix.len];
            const bytes = (try readOptional(a, io, dir, file)) orelse continue;
            const link = try std.fmt.allocPrint(a, "changes/{s}/{s}.html", .{ branch, project });
            try out.append(a, try rowOf(a, branch, project, link, bytes, null));
        }
    }
    return out.items;
}

/// The landed changes: one row per `merged/<sha>/<project>.review.json`, newest landing first (the
/// greatest sha name first), at most `max_landed_per_project` rows for each project.
fn landedChanges(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, log: []const u8) Error![]const Row {
    var out: std.ArrayList(Row) = .empty;
    var merged = (try openOptional(io, root, "merged")) orelse return &.{};
    defer merged.close(io);
    const landings = try namesIn(a, io, merged, .directory);
    var counted: std.StringHashMapUnmanaged(usize) = .empty;
    var index = landings.len;
    while (index > 0) {
        index -= 1;
        const sha = landings[index];
        var dir = (try openOptional(io, merged, sha)) orelse continue;
        defer dir.close(io);
        for (try reviewFiles(a, io, dir)) |file| {
            const project = file[0 .. file.len - review_suffix.len];
            const seen = try counted.getOrPut(a, project);
            if (!seen.found_existing) seen.value_ptr.* = 0;
            if (seen.value_ptr.* >= max_landed_per_project) continue;
            seen.value_ptr.* += 1;
            const bytes = (try readOptional(a, io, dir, file)) orelse continue;
            const link = try std.fmt.allocPrint(a, "merged/{s}/{s}.html", .{ sha, project });
            try out.append(a, try rowOf(a, sha, project, link, bytes, bypassFor(log, sha)));
        }
    }
    return out.items;
}

/// One review row from its `review-v1` bytes. A file that is not JSON is a row that says so.
fn rowOf(a: std.mem.Allocator, label: []const u8, project: []const u8, link: []const u8, bytes: []const u8, bypass: ?[]const u8) Error!Row {
    const value = (try parseValue(a, bytes)) orelse return .{
        .label = label,
        .project = project,
        .ok = false,
        .title = "this review file does not parse",
        .counts = .{},
        .link = link,
        .bypass = bypass,
    };
    const verdict = member(value, "verdict");
    const interface = items(member(value, "interface"));
    var explained: usize = 0;
    for (interface) |item| explained += @intFromBool(text(member(item, "decision")).len != 0);
    return .{
        .label = label,
        .project = project,
        .ok = flag(member(verdict, "ok")),
        .title = try titleOf(a, value),
        .counts = .{ .public = interface.len, .explained = explained, .refusals = items(member(verdict, "refusals")).len },
        .link = link,
        .bypass = bypass,
    };
}

/// The title a review shows: its first change note's title, else its first decision's, else its range.
fn titleOf(a: std.mem.Allocator, value: std.json.Value) Error![]const u8 {
    for (items(member(value, "notes"))) |note| {
        const title = text(member(note, "title"));
        if (title.len != 0) return title;
    }
    for (items(member(value, "decisions"))) |decision| {
        const title = text(member(decision, "title"));
        if (title.len != 0) return title;
    }
    const range = member(value, "range");
    return std.fmt.allocPrint(a, "{s}..{s}", .{ shortName(text(member(range, "base"))), shortName(text(member(range, "head"))) });
}

/// The reason of the last bypass line whose new tip starts with `sha`, or null when none did.
/// A bypass line is `utc`, `old`, `new` and the reason, separated by tabs.
fn bypassFor(log: []const u8, sha: []const u8) ?[]const u8 {
    var reason: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        _ = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const new = fields.next() orelse continue;
        if (sha.len != 0 and std.mem.startsWith(u8, new, sha)) reason = std.mem.trim(u8, fields.rest(), " \t\r");
    }
    return reason;
}

/// The name of a commit as the index shows it: its first characters.
fn shortName(name: []const u8) []const u8 {
    return if (name.len > short_length) name[0..short_length] else name;
}

/// The member `key` of a JSON object, or null when the value is not an object or lacks the key.
fn member(value: ?std.json.Value, key: []const u8) ?std.json.Value {
    const object = switch (value orelse return null) {
        .object => |found| found,
        else => return null,
    };
    return object.get(key);
}

/// The text of a JSON string, or the empty text when the value is missing or not a string.
fn text(value: ?std.json.Value) []const u8 {
    return switch (value orelse return "") {
        .string => |string| string,
        else => "",
    };
}

/// The truth of a JSON boolean, false when the value is missing or not a boolean.
fn flag(value: ?std.json.Value) bool {
    return switch (value orelse return false) {
        .bool => |found| found,
        else => false,
    };
}

/// The elements of a JSON array, or none when the value is missing or not an array.
fn items(value: ?std.json.Value) []const std.json.Value {
    return switch (value orelse return &.{}) {
        .array => |array| array.items,
        else => &.{},
    };
}

/// Parse one JSON document into values that live in `a`; null when the bytes are not JSON.
fn parseValue(a: std.mem.Allocator, bytes: []const u8) Error!?std.json.Value {
    const parsed = std.json.parseFromSlice(std.json.Value, a, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    return parsed.value;
}

/// The review files of `dir`, in name order.
fn reviewFiles(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (try namesIn(a, io, dir, .file)) |name| {
        if (std.mem.endsWith(u8, name, review_suffix)) try out.append(a, name);
    }
    return out.items;
}

/// The names of the entries of `dir` of `kind`, in name order.
fn namesIn(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, kind: std.Io.File.Kind) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = dir.iterate();
    while (iterator.next(io) catch return error.HostIo) |entry| {
        if (entry.kind != kind) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessText);
    return names.items;
}

/// Open the directory `name` of `parent`, or null when it does not exist.
fn openOptional(io: std.Io, parent: std.Io.Dir, name: []const u8) Error!?std.Io.Dir {
    return parent.openDir(io, name, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => null,
        else => error.HostIo,
    };
}

/// Read the file `path` of `dir`, or null when it does not exist.
fn readOptional(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) Error!?[]const u8 {
    return dir.readFileAlloc(io, path, a, .limited(max_file_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => error.HostIo,
    };
}

fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

test "review index names the bypass a landing carries, by its new tip" {
    const log = "2026-10-20T10:00:00Z\t1111111\t2222222\tfor a pin bump\n" ++
        "2026-10-21T09:00:00Z\t2222222\t3333333\tsecond reason\n";
    try std.testing.expectEqualStrings("for a pin bump", bypassFor(log, "2222222").?);
    try std.testing.expectEqualStrings("second reason", bypassFor(log, "3333333").?);
    try std.testing.expect(bypassFor(log, "1111111") == null);
    try std.testing.expect(bypassFor(log, "9999999") == null);
    try std.testing.expect(bypassFor(log, "") == null);
}

test "review index reads a review's verdict, counts and title" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const passing =
        "{\"version\":\"review-v1\",\"project\":\"p\",\"range\":{\"base\":\"0123456789abcdef\",\"head\":\"fedcba9876543210\",\"working_tree\":false}," ++
        "\"verdict\":{\"ok\":true,\"refusals\":[]},\"notes\":[{\"path\":\"changes/0.2/x.md\",\"title\":\"Serve on the event loop\",\"summary\":\"s\",\"valid\":true}]," ++
        "\"decisions\":[],\"interface\":[{\"name\":\"p::f\",\"decision\":\"Add f\"},{\"name\":\"p::g\"}]}";
    const row = try rowOf(a, "feature", "p", "changes/feature/p.html", passing, null);
    try std.testing.expect(row.ok);
    try std.testing.expectEqualStrings("Serve on the event loop", row.title);
    try std.testing.expectEqual(@as(usize, 2), row.counts.public);
    try std.testing.expectEqual(@as(usize, 1), row.counts.explained);
    try std.testing.expectEqual(@as(usize, 0), row.counts.refusals);
    const refused =
        "{\"verdict\":{\"ok\":false,\"refusals\":[{\"code\":\"E_REVIEW_DECISION_MISSING\",\"message\":\"m\"}]},\"notes\":[]," ++
        "\"decisions\":[{\"path\":\"decisions/unreleased/f.md\",\"title\":\"Add f\",\"changes\":[\"p::f\"],\"valid\":true}],\"interface\":[]}";
    const refused_row = try rowOf(a, "abc", "p", "merged/abc/p.html", refused, "for a pin bump");
    try std.testing.expect(!refused_row.ok);
    try std.testing.expectEqualStrings("Add f", refused_row.title);
    try std.testing.expectEqual(@as(usize, 1), refused_row.counts.refusals);
    try std.testing.expectEqualStrings("for a pin bump", refused_row.bypass.?);
    const bare = "{\"range\":{\"base\":\"0123456789abcdef\",\"head\":\"working tree\"},\"verdict\":{\"ok\":true,\"refusals\":[]},\"notes\":[],\"decisions\":[]}";
    const bare_row = try rowOf(a, "wip", "p", "changes/wip/p.html", bare, null);
    try std.testing.expectEqualStrings("0123456789ab..working tree", bare_row.title);
    const broken = try rowOf(a, "bad", "p", "changes/bad/p.html", "{not json", null);
    try std.testing.expect(!broken.ok);
    try std.testing.expectEqualStrings("this review file does not parse", broken.title);
}
