//! `selka fix`, `check` on library and test entries, and `test --diagnostics=json`,
//! driven through the compiler binary exactly as a user or an agent runs them.
const std = @import("std");
const testing = std.testing;
/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// One source file of a temporary project.
const File = struct { path: []const u8, data: []const u8 };

/// A temporary project directory and the absolute paths a command needs.
const Project = struct {
    temp: testing.TmpDir,
    root: [:0]const u8,
    cache: []const u8,

    fn init(files: []const File) !Project {
        var temp = testing.tmpDir(.{});
        errdefer temp.cleanup();
        for (files) |file| {
            if (std.fs.path.dirname(file.path)) |directory| try temp.dir.createDirPath(testing.io, directory);
            try temp.dir.writeFile(testing.io, .{ .sub_path = file.path, .data = file.data });
        }
        const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/.cache", .{root});
        return .{ .temp = temp, .root = root, .cache = cache };
    }

    fn deinit(self: *Project) void {
        testing.allocator.free(self.cache);
        testing.allocator.free(self.root);
        self.temp.cleanup();
    }

    /// The absolute path of one file or directory inside the project.
    fn path(self: *const Project, relative: []const u8) ![]const u8 {
        return std.fs.path.join(testing.allocator, &.{ self.root, relative });
    }

    /// One file's current bytes.
    fn read(self: *const Project, relative: []const u8) ![]const u8 {
        return self.temp.dir.readFileAlloc(testing.io, relative, testing.allocator, .limited(1 << 20));
    }

    /// Run `selka COMMAND TARGET ARGS...` from the project directory with this
    /// project's cache, so the paths `fix` prints are project-relative.
    fn run(self: *const Project, command: []const u8, target: []const u8, args: []const []const u8) !Outcome {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
        defer testing.allocator.free(compiler);
        const absolute = try self.path(target);
        defer testing.allocator.free(absolute);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler, command, absolute });
        try argv.appendSlice(testing.allocator, args);
        if (!std.mem.eql(u8, command, "test")) try argv.append(testing.allocator, self.cache);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir } });
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .stdout = result.stdout, .stderr = result.stderr };
    }
};

/// A finished command: exit status and both streams, owned by the testing allocator.
const Outcome = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn migration(original: []const u8, expected: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_LIST_MEMBERSHIP_REMOVED"));
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("fix stdout: {s}\nfix stderr: {s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    try testing.expectEqualStrings(expected, migrated);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec: LIST-MEMBERSHIP-1
test "wave1 list membership migration retains positive and negative tests" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    if 2 in values and 4 not in values:
        \\        return 42
        \\    return 0
        \\
    ,
        \\import lists
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    if lists.contains(values, 2) and not lists.contains(values, 4):
        \\        return 42
        \\    return 0
        \\
    );
}

// spec-case: LIST-MEMBERSHIP-1
test "wave1 list membership migrates pure dictionary values" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import dicts
        \\func main() -> int:
        \\    const values = {1: 2}
        \\    if 2 in dicts.values(values):
        \\        return 42
        \\    return 0
        \\
    ,
        \\import lists
        \\import dicts
        \\func main() -> int:
        \\    const values = {1: 2}
        \\    if lists.contains(list(dicts.values(values)), 2):
        \\        return 42
        \\    return 0
        \\
    );
}

// spec-case: LIST-MEMBERSHIP-1
test "wave1 list membership migrates generic equality constraints" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func has[T: equality](values: T[], value: T) -> bool:
        \\    return value in values
        \\
        \\func main() -> int:
        \\    if has([1, 2], 2):
        \\        return 42
        \\    return 0
        \\
    ,
        \\import lists
        \\public func has[T: equality](values: T[], value: T) -> bool:
        \\    return lists.contains(values, value)
        \\
        \\func main() -> int:
        \\    if has([1, 2], 2):
        \\        return 42
        \\    return 0
        \\
    );
}

// spec-case: LIST-MEMBERSHIP-1
test "wave1 list membership withholds reordered calls" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional removed-syntax diagnostic source
        \\func needle() -> int:
        \\    return 2
        \\
        \\func values() -> int[]:
        \\    return [1, 2]
        \\
        \\func main() -> int:
        \\    if needle() in values():
        \\        return 42
        \\    return 0
        \\
    }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "E_LIST_MEMBERSHIP_REMOVED"));
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", preview.stdout);
}

// spec-case: LIST-MEMBERSHIP-1
test "wave1 list membership migrates pure literal list" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    if 2 in [1, 2]:
        \\        return 42
        \\    return 0
        \\
    ,
        \\import lists
        \\func main() -> int:
        \\    if lists.contains([1, 2], 2):
        \\        return 42
        \\    return 0
        \\
    );
}

// spec-case: LIST-MEMBERSHIP-1
test "wave1 list membership migrates pure float and list literal needles" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import dicts
        \\func main() -> int:
        \\    const mapping = {1: [7, 8]}
        \\    const zeros = [0.0]
        \\    if [7, 8] in dicts.values(mapping) and -0.0 in zeros and 0.0 in zeros:
        \\        return 42
        \\    return 0
        \\
    ,
        \\import lists
        \\import dicts
        \\func main() -> int:
        \\    const mapping = {1: [7, 8]}
        \\    const zeros = [0.0]
        \\    if lists.contains(list(dicts.values(mapping)), [7, 8]) and lists.contains(zeros, -0.0) and lists.contains(zeros, 0.0):
        \\        return 42
        \\    return 0
        \\
    );
}
