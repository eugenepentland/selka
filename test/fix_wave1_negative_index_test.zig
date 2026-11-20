//! Language wave 1 migration of constant negative sequence indexes and bounds.
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

// spec-case: NEGATIVE-INDEX-FIX-1
// spec-case: FIX-MIGRATION-1
test "WAVE1 negative index CLI fix is complete and idempotent" {
    const original = @embedFile("fixtures/fix-migration/wave1-negative-index.selka");
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_NEGATIVE_INDEX_REMOVED"));
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(@embedFile("fixtures/fix-migration/wave1-negative-index.expected.selka"), after);
    try testing.expect(contains(after, "xs[len(xs) - 1]"));
    try testing.expect(contains(after, "xs[max(len(xs) - 2, 0):max(len(xs) - 1, 0)]"));
    try testing.expect(contains(after, "text[len(text) - 1]"));
    try testing.expect(contains(after, "data[max(len(data) - 2, 0):max(len(data) - 1, 0)]"));
    try testing.expect(contains(after, "fixed[len(fixed) - 1] = 4"));
    try testing.expect(contains(after, "replace(fixed, len(fixed) - 2, 5)"));
    try testing.expect(contains(after, "mapping[-1]"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: NEGATIVE-INDEX-FIX-2
test "WAVE1 imported max name withholds a generated clamp and preserves source" {
    const original = "import strings\nimport max\n\n\nfunc main() -> int:\n    const text = \"abc\"\n    return strings.char_rfind(text, \"\", 0, -1)\n";
    var project = try Project.init(&.{
        .{ .path = "main.selka", .data = original },
        .{ .path = "max.selka", .data = "public func value() -> int:\n    return 0\n" },
    });
    defer project.deinit();
    const result = try project.run("fix", "main.selka", &.{});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expect(contains(result.stderr, "E_NEGATIVE_INDEX_REMOVED"));
    const after = try project.read("main.selka");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(original, after);
}
