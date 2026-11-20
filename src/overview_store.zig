//! Root-relative release metadata shared by overview and release commands.
const std = @import("std");
const loader = @import("release_project_load.zig");
const baseline = @import("api_diff_baseline.zig");
const decisions = @import("release_decisions.zig");

/// Host and metadata decoding failures; no body checking is performed.
pub const Error = baseline.Error || error{ HostIo, InvalidHistory };
/// One chronological release/history.txt entry; `notes` is 0 when the row has no third column.
pub const Release = struct { name: []const u8, decisions: usize, notes: usize = 0 };
/// Borrowed-or-arena-owned release inputs; release the caller's arena after use.
pub const Store = struct {
    previous: ?[]const baseline.Entry = null,
    decisions: []const decisions.Decision = &.{},
    issues: []const decisions.Issue = &.{},
    history: []const Release = &.{},
};
/// Conventional history path, independent of the configurable baseline filename.
pub const history_path = "release/history.txt";

/// Read the public baseline, sorted decision files and chronological history.
/// A missing baseline is represented by null; malformed existing bytes fail.
pub fn load(a: std.mem.Allocator, io: std.Io, model: *const loader.Model) Error!Store {
    var result: Store = .{};
    if (try readOptional(a, io, model.root, model.options.baseline)) |bytes| result.previous = try baseline.parseReleaseBaseline(a, bytes);
    if (try readOptional(a, io, model.root, history_path)) |bytes| result.history = try parseHistory(a, bytes);
    var parsed: std.ArrayList(decisions.Decision) = .empty;
    var issues: std.ArrayList(decisions.Issue) = .empty;
    const files = try decisionPaths(a, io, model.root, model.options.decisions);
    const pending = try std.fs.path.join(a, &.{ model.options.decisions, "unreleased" });
    for (files) |path| {
        const bytes = (try readOptional(a, io, model.root, path)) orelse return error.HostIo;
        const is_pending = path.len > pending.len and std.mem.startsWith(u8, path, pending) and path[pending.len] == std.fs.path.sep;
        const item = try decisions.parse(a, path, bytes, is_pending);
        try parsed.append(a, item.decision);
        try issues.appendSlice(a, item.issues);
    }
    result.decisions = parsed.items;
    result.issues = issues.items;
    return result;
}

/// Read one optional root-relative text file, retaining bytes in the caller arena.
pub fn readOptional(a: std.mem.Allocator, io: std.Io, root: []const u8, path: []const u8) Error!?[]const u8 {
    const absolute = try std.fs.path.join(a, &.{ root, path });
    return std.Io.Dir.cwd().readFileAlloc(io, absolute, a, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        error.OutOfMemory => error.OutOfMemory,
        else => error.HostIo,
    };
}

fn decisionPaths(a: std.mem.Allocator, io: std.Io, root: []const u8, path: []const u8) Error![]const []const u8 {
    const absolute = try std.fs.path.join(a, &.{ root, path });
    var dir = std.Io.Dir.cwd().openDir(io, absolute, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return error.HostIo,
    };
    defer dir.close(io);
    var walker = try dir.walk(a);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (walker.next(io) catch return error.HostIo) |item| {
        if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".md")) continue;
        try paths.append(a, try std.fs.path.join(a, &.{ path, item.path }));
    }
    std.mem.sort([]const u8, paths.items, {}, less);
    return paths.items;
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Parse NAME<TAB>COUNT or NAME<TAB>COUNT<TAB>NOTES rows, preserving file order and rejecting duplicates.
pub fn parseHistory(a: std.mem.Allocator, bytes: []const u8) Error![]const Release {
    var result: std.ArrayList(Release) = .empty;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var words = std.mem.tokenizeAny(u8, line, " \t");
        const name = words.next() orelse return error.InvalidHistory;
        const count = words.next() orelse return error.InvalidHistory;
        const notes = words.next();
        if (words.next() != null or !validName(name)) return error.InvalidHistory;
        for (result.items) |prior| if (std.mem.eql(u8, prior.name, name)) return error.InvalidHistory;
        const decisions_count = std.fmt.parseInt(usize, count, 10) catch return error.InvalidHistory;
        const notes_count = if (notes) |text| (std.fmt.parseInt(usize, text, 10) catch return error.InvalidHistory) else 0;
        try result.append(a, .{ .name = try a.dupe(u8, name), .decisions = decisions_count, .notes = notes_count });
    }
    return result.items;
}

fn validName(name: []const u8) bool {
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) continue;
        if (c != '.' and c != '-' and c != '_') return false;
    }
    return name.len != 0;
}
