//! Working-tree-versus-revision line diff for the commit-time lint rules.
//!
//! `change-without-test` and `test --affected` both need to know which current
//! declarations changed since a reference. Recompiling the reference revision
//! would duplicate the whole frontend, so the diff reads the changed line
//! ranges from `git diff --unified=0 <reference>` run in the entry file's own
//! repository and maps them onto the current declarations' source spans.
const std = @import("std");

/// Failures a diff helper reports: a git invocation that failed, or allocation.
pub const Error = error{ GitFailed, OutOfMemory };

/// One one-based, half-open range of changed lines in the working tree.
pub const LineRange = struct { start: usize, len: usize };

/// Plain diff output, whatever the user's colour configuration says.
const no_color = "--no-color";

/// Run one git subcommand in `repo_root` and return its stdout. Any non-zero
/// exit or spawn failure is `GitFailed`.
fn runGit(allocator: std.mem.Allocator, io: std.Io, repo_root: []const u8, args: []const []const u8) Error![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "-C", repo_root });
    try argv.appendSlice(allocator, args);
    const result = std.process.run(allocator, io, .{ .argv = argv.items }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GitFailed,
    };
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return error.GitFailed;
        },
        else => {
            allocator.free(result.stdout);
            return error.GitFailed;
        },
    }
    return result.stdout;
}

/// Working-tree byte paths that differ from `reference`, as git prints them
/// (repository-relative, forward slashes).
pub fn changedFiles(allocator: std.mem.Allocator, io: std.Io, repo_root: []const u8, reference: []const u8) Error![]const []const u8 {
    const bytes = try runGit(allocator, io, repo_root, &.{ "diff", "--name-only", no_color, reference });
    defer allocator.free(bytes);
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const path = std.mem.trim(u8, line, " \t\r");
        if (path.len == 0) continue;
        try paths.append(allocator, try allocator.dupe(u8, path));
    }
    return paths.toOwnedSlice(allocator);
}

/// Changed working-tree line ranges in one path, read from the `+` side of each
/// `--unified=0` hunk header. A pure deletion (length zero) contributes nothing.
pub fn changedLines(allocator: std.mem.Allocator, io: std.Io, repo_root: []const u8, reference: []const u8, path: []const u8) Error![]LineRange {
    const bytes = try runGit(allocator, io, repo_root, &.{ "diff", "--unified=0", no_color, reference, "--", path });
    defer allocator.free(bytes);
    return parseHunks(allocator, bytes);
}

/// One changed working-tree file and the line ranges its edits touch.
pub const FileLines = struct { path: []const u8, ranges: []const LineRange };

/// Every working-tree `.my` file under `repo_root` that differs from
/// `reference`, with the lines each edit touches, from one `git diff` run.
/// Paths are relative to `repo_root`. A pure deletion touches the lines on
/// both sides of the gap, so removing a line from a body still marks it; a
/// deleted file is left out, and a file `git` does not track yet is changed on
/// every line.
pub fn changedModules(allocator: std.mem.Allocator, io: std.Io, repo_root: []const u8, reference: []const u8) Error![]FileLines {
    const bytes = try runGit(allocator, io, repo_root, &.{ "diff", "--unified=0", no_color, "--no-prefix", "--no-renames", "--relative", reference, "--", "*.my" });
    defer allocator.free(bytes);
    var files: std.ArrayList(FileLines) = .empty;
    var ranges: std.ArrayList(LineRange) = .empty;
    var current: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "+++ ")) {
            if (current) |path| try files.append(allocator, .{ .path = path, .ranges = try ranges.toOwnedSlice(allocator) });
            const target = line["+++ ".len..];
            current = if (std.mem.eql(u8, target, "/dev/null")) null else try allocator.dupe(u8, target);
            ranges.clearRetainingCapacity();
            continue;
        }
        if (current == null or !std.mem.startsWith(u8, line, "@@ ")) continue;
        if (hunkRange(line, true)) |range| try ranges.append(allocator, range);
    }
    if (current) |path| try files.append(allocator, .{ .path = path, .ranges = try ranges.toOwnedSlice(allocator) });
    const untracked = try runGit(allocator, io, repo_root, &.{ "ls-files", "--others", "--exclude-standard", "--", "*.my" });
    defer allocator.free(untracked);
    var names = std.mem.splitScalar(u8, untracked, '\n');
    while (names.next()) |name| {
        const path = std.mem.trim(u8, name, " \t\r");
        if (path.len == 0) continue;
        const whole = try allocator.alloc(LineRange, 1);
        whole[0] = .{ .start = 1, .len = std.math.maxInt(u32) };
        try files.append(allocator, .{ .path = try allocator.dupe(u8, path), .ranges = whole });
    }
    return files.toOwnedSlice(allocator);
}

/// The working-tree side of one `@@ -a,b +c,d @@` header. A zero-length side
/// is a pure deletion after line `c`; `deletions` keeps it as the two lines
/// around the gap instead of dropping it.
fn hunkRange(line: []const u8, deletions: bool) ?LineRange {
    const plus = std.mem.indexOf(u8, line, " +") orelse return null;
    const rest = line[plus + 2 ..];
    const comma = std.mem.indexOfAny(u8, rest, " ,") orelse rest.len;
    const start = std.fmt.parseUnsigned(usize, rest[0..comma], 10) catch return null;
    var length: usize = 1;
    if (comma < rest.len and rest[comma] == ',') {
        const after = rest[comma + 1 ..];
        const stop = std.mem.indexOfScalar(u8, after, ' ') orelse after.len;
        length = std.fmt.parseUnsigned(usize, after[0..stop], 10) catch 1;
    }
    if (length != 0) return .{ .start = start, .len = length };
    if (!deletions) return null;
    return .{ .start = @max(start, 1), .len = 2 };
}

/// Parse the `@@ -a,b +c,d @@` headers of one unified diff.
fn parseHunks(allocator: std.mem.Allocator, bytes: []const u8) Error![]LineRange {
    var ranges: std.ArrayList(LineRange) = .empty;
    errdefer ranges.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "@@ ")) continue;
        if (hunkRange(line, false)) |range| try ranges.append(allocator, range);
    }
    return ranges.toOwnedSlice(allocator);
}

/// Whether one zero-based declaration line range intersects any changed range.
/// Changed ranges are one-based; the declaration range is zero-based.
pub fn intersects(ranges: []const LineRange, first_line: usize, last_line: usize) bool {
    for (ranges) |range| {
        const first_changed = range.start - 1;
        if (first_changed > last_line) continue;
        if (first_changed + range.len > first_line) return true;
    }
    return false;
}

fn runGitTest(allocator: std.mem.Allocator, io: std.Io, root: []const u8, args: []const []const u8) !void {
    const bytes = try runGit(allocator, io, root, args);
    allocator.free(bytes);
}

// spec: REF-DIFF-1
test "ref_diff reads changed line ranges and files from a git revision" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "file.my", .data = "one\ntwo\nthree\n" });
    try runGitTest(std.testing.allocator, std.testing.io, root, &.{ "init", "-q" });
    try runGitTest(std.testing.allocator, std.testing.io, root, &.{ "add", "file.my" });
    try runGitTest(std.testing.allocator, std.testing.io, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "file.my", .data = "one\nchanged\nthree\n" });
    const ranges = try changedLines(std.testing.allocator, std.testing.io, root, "HEAD", "file.my");
    defer std.testing.allocator.free(ranges);
    try std.testing.expectEqual(@as(usize, 1), ranges.len);
    try std.testing.expectEqual(@as(usize, 2), ranges[0].start);
    try std.testing.expectEqual(@as(usize, 1), ranges[0].len);
    try std.testing.expect(intersects(ranges, 1, 1));
    try std.testing.expect(!intersects(ranges, 2, 2));
    const files = try changedFiles(std.testing.allocator, std.testing.io, root, "HEAD");
    defer {
        for (files) |path| std.testing.allocator.free(path);
        std.testing.allocator.free(files);
    }
    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqualStrings("file.my", files[0]);
    try std.testing.expectError(error.GitFailed, changedLines(std.testing.allocator, std.testing.io, root, "no-such-revision", "file.my"));
}

// spec-case: REF-DIFF-1
test "ref_diff parseHunks reads the plus side and skips pure deletions" {
    const diff =
        \\@@ -1 +1 @@
        \\-old
        \\+new
        \\@@ -5,2 +5,0 @@
        \\-gone
        \\@@ -8,0 +9,3 @@
        \\+a
        \\+b
        \\+c
    ;
    const ranges = try parseHunks(std.testing.allocator, diff);
    defer std.testing.allocator.free(ranges);
    try std.testing.expectEqual(@as(usize, 2), ranges.len);
    try std.testing.expectEqual(@as(usize, 1), ranges[0].start);
    try std.testing.expectEqual(@as(usize, 1), ranges[0].len);
    try std.testing.expectEqual(@as(usize, 9), ranges[1].start);
    try std.testing.expectEqual(@as(usize, 3), ranges[1].len);
}
