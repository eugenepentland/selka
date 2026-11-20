//! The declaration target used by wave-one statement migrations works through the CLI.
const std = @import("std");
const testing = std.testing;
/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// Skips the calling test while release builds are off (`-Dtest-release=true` runs them).
fn requireRelease() error{SkipZigTest}!void {
    if (!@import("test_release_options").enabled) return error.SkipZigTest;
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
        var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
        defer environment.deinit();
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = self.temp.dir }, .environ_map = &environment });
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

// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 declaration migration target checks runs and remains fix-idempotent" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\func main() -> int:
        \\    mut result: int
        \\    if True:
        \\        result = 42
        \\    else:
        \\        result = 0
        \\    return result
    }});
    defer project.deinit();
    const formatted = try project.run("fmt", "main.selka", &.{});
    defer formatted.deinit();
    try testing.expectEqual(@as(u8, 0), formatted.status);
    try testing.expect(std.mem.indexOf(u8, formatted.stdout, "mut result: int\n") != null);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = formatted.stdout });
    const check = try project.run("check", "main.selka", &.{});
    defer check.deinit();
    try testing.expectEqual(@as(u8, 0), check.status);
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 0), preview.status);
    const result = try project.run("run", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 42), result.status);
}
// spec-case: DECL-DEFINITE-ASSIGNMENT-1
test "wave1 native declarations clean up managed branches early returns and failing propagation" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\record Box:
        \\    values: int[]
        \\
        \\enum Error:
        \\    failed
        \\
        \\func choose(flag: bool) -> int[]:
        \\    const result: int[]
        \\    if flag:
        \\        result = [1, 2]
        \\    else:
        \\        result = [3]
        \\    return result
        \\
        \\func choose_box(flag: bool) -> Box:
        \\    const result: Box
        \\    if flag:
        \\        result = Box(values=[4])
        \\    else:
        \\        result = Box(values=[5, 6])
        \\    return result
        \\
        \\func early_box(flag: bool) -> Box:
        \\    const result: Box
        \\    if flag:
        \\        return Box(values=[7])
        \\    result = Box(values=[8])
        \\    return result
        \\
        \\func input(fail_now: bool) -> int fails Error:
        \\    if fail_now:
        \\        fail Error.failed
        \\    return 5
        \\
        \\func propagated(fail_now: bool) -> int[] fails Error:
        \\    const result: int[]
        \\    const value = try input(fail_now)
        \\    result = [value]
        \\    return result
        \\
        \\func main() -> int:
        \\    assert len(choose(True)) == 2
        \\    assert len(choose(False)) == 1
        \\    assert choose_box(True).values[0] == 4
        \\    assert len(choose_box(False).values) == 2
        \\    assert early_box(True).values[0] == 7
        \\    assert early_box(False).values[0] == 8
        \\    match propagated(True):
        \\        case Ok(_):
        \\            return 1
        \\        case Err(_):
        \\            pass
        \\    match propagated(False):
        \\        case Ok(values):
        \\            assert values[0] == 5
        \\        case Err(_):
        \\            return 2
        \\    return 42
    }});
    defer project.deinit();
    const debug = try project.run("run", "main.selka", &.{"--verify-facts"});
    defer debug.deinit();
    try testing.expectEqualStrings("", debug.stderr);
    try testing.expectEqual(@as(u8, 42), debug.status);
    try testing.expect(std.mem.indexOf(u8, debug.stderr, "myl-core leakcheck:") == null);
    try requireRelease();
    const release = try project.run("run", "main.selka", &.{ "--release", "--verify-facts" });
    defer release.deinit();
    try testing.expectEqual(@as(u8, 42), release.status);
    try testing.expect(std.mem.indexOf(u8, release.stderr, "myl-core leakcheck:") == null);
}
