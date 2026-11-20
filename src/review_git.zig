//! Git access for `selka review`: the repository top level, revision resolution,
//! merge bases, and a revision's project tree extracted once into the work cache.
//! Every git child runs without the repository variables a hook sets, so `-C`
//! names the repository it is meant to name. Nothing is written to the repository,
//! no worktree is created and no network is used.
const std = @import("std");
const product = @import("product.zig");

/// Failures of a review git call. `GitFailed` covers any git exit other than zero,
/// including a revision or path that does not exist at that revision.
pub const Error = error{ GitFailed, HostIo, OutOfMemory, TreeTooLarge };

/// The largest `git archive` output one review extracts; a larger project is refused.
const archive_limit = 512 << 20;
/// Repository variables that would point `git -C` at a different repository.
const hook_variables = [_][]const u8{ "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE" };
/// Where extracted revision trees live, relative to the repository top level.
pub const trees_directory = product.work_dir ++ "/review/trees";
/// Length of the abbreviated object name the terminal shows.
const short_length = 7;

/// A git runner. Its allocator is a command arena in practice: results are never freed.
pub const Git = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ.Map,

    /// Copy `source` without the repository variables, so every git child reads the repository it names.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, source: *const std.process.Environ.Map) Error!Git {
        var environ = try source.clone(allocator);
        for (hook_variables) |name| _ = environ.swapRemove(name);
        return .{ .allocator = allocator, .io = io, .environ = environ };
    }

    /// Release the copied environment. A `Git` on a command arena has nothing else to release.
    pub fn deinit(self: *Git) void {
        self.environ.deinit();
        self.* = undefined;
    }

    /// The absolute top level of the repository that holds `directory`.
    pub fn toplevel(self: *const Git, directory: []const u8) Error![]const u8 {
        return trimmed(try self.run(directory, &.{ "rev-parse", "--show-toplevel" }));
    }

    /// The full object name of `revision` peeled to a commit; GitFailed when it names none.
    pub fn commit(self: *const Git, root: []const u8, revision: []const u8) Error![]const u8 {
        const spelled = try std.fmt.allocPrint(self.allocator, "{s}^{{commit}}", .{revision});
        return trimmed(try self.run(root, &.{ "rev-parse", "--verify", "--quiet", spelled }));
    }

    /// The best common ancestor of two commits; GitFailed when they share none.
    pub fn mergeBase(self: *const Git, root: []const u8, left: []const u8, right: []const u8) Error![]const u8 {
        return trimmed(try self.run(root, &.{ "merge-base", left, right }));
    }

    /// The project directory of `project` at commit `sha`, extracted once into the
    /// work cache. Null when `project` has no `selka.json` in that commit, which makes
    /// it absent on that side. An empty `project` names the repository root. Nothing is
    /// written to the repository.
    pub fn materialize(self: *const Git, root: []const u8, sha: []const u8, project: []const u8) Error!?[]const u8 {
        if (!try self.hasConfig(root, sha, project)) return null;
        const tree = try treeDirectory(self.allocator, root, sha, project);
        if (!try exists(self.io, tree)) try self.extract(root, sha, project, tree);
        if (project.len == 0) return tree;
        const project_tree = try std.fs.path.join(self.allocator, &.{ tree, project });
        return project_tree;
    }

    /// Whether commit `sha` holds the project's `selka.json`.
    fn hasConfig(self: *const Git, root: []const u8, sha: []const u8, project: []const u8) Error!bool {
        const path = if (project.len == 0) product.project_file else try std.fs.path.join(self.allocator, &.{ project, product.project_file });
        const spec = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ sha, path });
        _ = self.run(root, &.{ "cat-file", "-e", spec }) catch |err| switch (err) {
            error.GitFailed => return false,
            else => return err,
        };
        return true;
    }

    /// Extract the archive of `project` at `sha` into `tree`. The archive is unpacked
    /// into a partial directory first and renamed into place, so a directory named
    /// `tree` is always complete.
    fn extract(self: *const Git, root: []const u8, sha: []const u8, project: []const u8, tree: []const u8) Error!void {
        const io = self.io;
        const cwd = std.Io.Dir.cwd();
        const trees = try std.fs.path.join(self.allocator, &.{ root, trees_directory });
        cwd.createDirPath(io, trees) catch return error.HostIo;
        const archive = if (project.len == 0)
            try self.run(root, &.{ "--literal-pathspecs", "archive", "--format=tar", sha })
        else
            try self.run(root, &.{ "--literal-pathspecs", "archive", "--format=tar", sha, "--", project });
        const partial = try std.fmt.allocPrint(self.allocator, "{s}.partial-{d}", .{ tree, std.os.linux.getpid() });
        cwd.deleteTree(io, partial) catch return error.HostIo;
        try unpack(io, cwd, partial, archive);
        cwd.rename(partial, cwd, tree, io) catch return finishRename(io, partial, tree);
    }

    /// Run `git -C DIRECTORY ARGS` and return its standard output. A non-zero exit is GitFailed.
    fn run(self: *const Git, directory: []const u8, args: []const []const u8) Error![]u8 {
        const argv = try self.allocator.alloc([]const u8, args.len + 3);
        argv[0] = "git";
        argv[1] = "-C";
        argv[2] = directory;
        @memcpy(argv[3..], args);
        const result = std.process.run(self.allocator, self.io, .{
            .argv = argv,
            .environ_map = &self.environ,
            .stdout_limit = .limited(archive_limit),
            .stderr_limit = .limited(1 << 16),
        }) catch |err| return runFailure(err);
        switch (result.term) {
            .exited => |code| if (code == 0) return result.stdout,
            else => {},
        }
        return error.GitFailed;
    }
};

/// The project's path relative to the repository top level, with forward slashes;
/// "" when the project is the top level itself. Null when `directory` is not inside `top`.
pub fn projectRelative(top: []const u8, directory: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, top, directory)) return "";
    if (directory.len <= top.len or !std.mem.startsWith(u8, directory, top)) return null;
    if (directory[top.len] != std.fs.path.sep) return null;
    return directory[top.len + 1 ..];
}

/// The abbreviated object name the review prints: at most seven characters.
pub fn shortName(sha: []const u8) []const u8 {
    return sha[0..@min(short_length, sha.len)];
}

/// The directory that holds `project` at `sha` under `root`: `trees/SHA-HASH`, where the
/// hash distinguishes project paths within one commit.
fn treeDirectory(allocator: std.mem.Allocator, root: []const u8, sha: []const u8, project: []const u8) Error![]const u8 {
    const name = try std.fmt.allocPrint(allocator, "{s}-{x:0>16}", .{ sha, std.hash.Wyhash.hash(0, project) });
    return std.fs.path.join(allocator, &.{ root, trees_directory, name });
}

/// Unpack `archive` into the new directory `partial`. A failed unpack removes the partial tree.
fn unpack(io: std.Io, cwd: std.Io.Dir, partial: []const u8, archive: []const u8) Error!void {
    var directory = cwd.createDirPathOpen(io, partial, .{}) catch return error.HostIo;
    defer directory.close(io);
    var reader = std.Io.Reader.fixed(archive);
    std.tar.extract(io, directory, &reader, .{}) catch |err| return abandon(io, cwd, partial, err);
}

/// Remove a partial tree whose unpacking failed, and name the failure.
fn abandon(io: std.Io, cwd: std.Io.Dir, partial: []const u8, err: anyerror) Error {
    cwd.deleteTree(io, partial) catch return error.HostIo;
    return if (err == error.OutOfMemory) error.OutOfMemory else error.HostIo;
}

/// Finish a failed rename of a partial tree. Another review may have moved its complete
/// copy into `tree` first, and that copy stands; otherwise the rename failed for the host.
fn finishRename(io: std.Io, partial: []const u8, tree: []const u8) Error!void {
    std.Io.Dir.cwd().deleteTree(io, partial) catch return error.HostIo;
    if (try exists(io, tree)) return;
    return error.HostIo;
}

/// The error a failed git child run becomes: an output over the limit, memory, or host I/O.
fn runFailure(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.TreeTooLarge,
        else => error.HostIo,
    };
}

/// Whether a path exists on disk, reporting host failures other than absence.
fn exists(io: std.Io, path: []const u8) Error!bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.HostIo,
    };
    return true;
}

/// Git output without its trailing newline.
fn trimmed(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t\r\n");
}

test "review git names a project relative to the repository top level" {
    try std.testing.expectEqualStrings("", projectRelative("/work/repo", "/work/repo").?);
    try std.testing.expectEqualStrings("ledger/repros", projectRelative("/work/repo", "/work/repo/ledger/repros").?);
    try std.testing.expect(projectRelative("/work/repo", "/work/repository") == null);
    try std.testing.expect(projectRelative("/work/repo", "/elsewhere") == null);
}

test "review git shortens object names to seven characters" {
    try std.testing.expectEqualStrings("c338c34", shortName("c338c3480a1b2c3d4e5f60718293a4b5c6d7e8f9"));
    try std.testing.expectEqualStrings("abc", shortName("abc"));
}

test "review git names the tree of a revision by its commit and project path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sha = "0123456789abcdef0123456789abcdef01234567";
    const first = try treeDirectory(a, "/repo", sha, "ledger");
    const second = try treeDirectory(a, "/repo", sha, "ledger/repros");
    const again = try treeDirectory(a, "/repo", sha, "ledger");
    try std.testing.expect(std.mem.startsWith(u8, first, "/repo/.selka-cache/review/trees/" ++ sha ++ "-"));
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expectEqualStrings(first, again);
}

test "review git names a git output over its limit as too large" {
    try std.testing.expectEqual(error.TreeTooLarge, runFailure(error.StreamTooLong));
    try std.testing.expectEqual(error.OutOfMemory, runFailure(error.OutOfMemory));
    try std.testing.expectEqual(error.HostIo, runFailure(error.FileNotFound));
}
