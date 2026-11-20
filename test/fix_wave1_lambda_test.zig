//! CLI regressions for typed lambda retirement.
const std = @import("std");
const testing = std.testing;

// spec: LAMBDA-MIGRATION-1
test "wave1 lambda preview fix check and idempotence across independent roots" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func answer() -> int:
        \\    mut values = sorted([3, 1, 2], key=lambda value: value)
        \\    return values[0]
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "padding.selka", .data = "public func zero() -> int:\n    return 0\n" },
        .{ .path = "first.selka", .data = "import padding\nimport shared\nfunc main() -> int:\n    return padding.zero() + shared.answer()\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    return shared.answer()\n" },
    };
    const first_repair = try fixedShared(&files, "first.selka");
    defer testing.allocator.free(first_repair);
    const second_repair = try fixedShared(&files, "second.selka");
    defer testing.allocator.free(second_repair);
    try testing.expectEqualStrings(first_repair, second_repair);
    var project = try Project.init(&files);
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_LAMBDA_REMOVED"));
    const unchanged = try project.read("shared.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(shared, unchanged);
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const changed = try project.read("shared.selka");
    defer testing.allocator.free(changed);
    try testing.expectEqualStrings(
        \\func lambda_fn_68(value: int) -> int:
        \\    return value
        \\
        \\public func answer() -> int:
        \\    mut values = sorted([3, 1, 2], key=lambda_fn_68)
        \\    return values[0]
        \\
    , changed);
    for ([_][]const u8{ "first.selka", "second.selka" }) |entry| {
        const checked = try project.run("check", entry, &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
    }
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: LAMBDA-MIGRATION-1
test "wave1 lambda generic callback callers retain distinct int and str contracts" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func apply[T](value: T, callback: func(T) -> T effects()) -> T:
        \\    return callback(value)
        \\func main() -> int:
        \\    mut a: int = apply(2, lambda value: value + 1)
        \\    mut b = apply[str](value="ok", callback=lambda value: value)
        \\    return a + len(b)
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const changed = try project.read("main.selka");
    defer testing.allocator.free(changed);
    try testing.expect(contains(changed, "value: int) -> int:"));
    try testing.expect(contains(changed, "value: str) -> str:"));
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec-case: LAMBDA-MIGRATION-1
test "wave1 lambda migration preserves managed callback mutation at runtime" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func apply(callback: func(mut values: int[]) -> Unit effects(mutation), mut values: int[]) -> Unit effects(mutation):
        \\    callback(mut values)
        \\
        \\public func test_mutation() -> bool:
        \\    mut values = [1, 2, 3]
        \\    apply(lambda values: values.clear(), mut values)
        \\    return len(values) == 0
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const executed = try project.run("test", "main.selka", &.{});
    defer executed.deinit();
    if (executed.status != 0) std.debug.print("lambda runtime stdout={s} stderr={s}\n", .{ executed.stdout, executed.stderr });
    try testing.expectEqual(@as(u8, 0), executed.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

fn fixedShared(files: []const File, entry: []const u8) ![]const u8 {
    var project = try Project.init(files);
    defer project.deinit();
    const fixed = try project.run("fix", entry, &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    return project.read("shared.selka");
}

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
