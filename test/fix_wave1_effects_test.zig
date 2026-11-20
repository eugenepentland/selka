//! CLI migration contract for effect-system retirement.
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

fn migrate(files: []const File, target: []const u8, expected: []const File) !void {
    var project = try Project.init(files);
    defer project.deinit();
    const preview = try project.run("fix", target, &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "E_EFFECTS_REMOVED") != null);
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
    const fixed = try project.run("fix", target, &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    for (expected) |file| {
        const actual = try project.read(file.path);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(file.data, actual);
    }
    const check = try project.run("check", if (std.mem.eql(u8, target, ".")) files[0].path else target, &.{});
    defer check.deinit();
    try testing.expectEqual(@as(u8, 0), check.status);
    const again = try project.run("fix", target, &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: EFFECTS-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 effects CLI removes clauses across imported modules and independent roots" {
    try migrate(&.{
        .{ .path = "main.selka", .data = "import helper\nfunc main() -> int noio:\n    return helper.value()\n" },
        .{ .path = "helper.selka", .data = "public func value() -> int effects(clock, clock, unknown):\n    return 7\n" },
        .{ .path = "other.selka", .data = "func main() -> int effects():\n    return 0\n" },
    }, ".", &.{
        .{ .path = "main.selka", .data = "import helper\nfunc main() -> int:\n    return helper.value()\n" },
        .{ .path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" },
        .{ .path = "other.selka", .data = "func main() -> int:\n    return 0\n" },
    });
}

// spec-case: EFFECTS-REMOVED-1
// spec-case: NOALLOC-ATTRIBUTE-1
test "wave1 effects CLI relocates multiline noalloc declaration and erases callback noalloc" {
    try migrate(&.{.{ .path = "main.selka", .data = "func use(cb: func(int) -> int noalloc) -> int:\n    mut values = [1]\n    return cb(values[0])\n\n" ++
        "func increment(\n    value: int\n) -> int noalloc:\n    return value + 1\n\n" ++
        "func main() -> int:\n    return use(increment)\n" }}, "main.selka", &.{.{ .path = "main.selka", .data = "func use(cb: func(int) -> int) -> int:\n    mut values = [1]\n    return cb(values[0])\n\n" ++
        "@noalloc\nfunc increment(\n    value: int\n) -> int:\n    return value + 1\n\n" ++
        "func main() -> int:\n    return use(increment)\n" }});
}

// spec-case: EFFECTS-REMOVED-1
test "wave1 effects CLI erases extern noalloc without attributing a bodyless declaration" {
    try migrate(&.{.{ .path = "main.selka", .data = "extern func stamp(host: Host) -> int noalloc\n\nfunc main(host: Host) -> int:\n    return stamp(host)\n" }}, "main.selka", &.{.{ .path = "main.selka", .data = "extern func stamp(host: Host) -> int\n\nfunc main(host: Host) -> int:\n    return stamp(host)\n" }});
}

/// Exercise compositional migrations without freezing the domain renaming policy.
fn converges(source: []const u8, expected: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const untouched = try project.read("main.selka");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(source, untouched);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    try testing.expect(std.mem.indexOf(u8, migrated, expected) != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "effects(") == null);
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: EFFECTS-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 effects CLI converges combined domain and operation clauses" {
    try converges(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 effect and domain before input
        \\domain D: int:
        \\    func make(value: int) -> D effects():
        \\        return wrap[D](value)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: copy + op(score(item: T) -> int effects())](item: T) -> int effects():
        \\    return T.score(item)
        \\func main() -> int effects():
        \\    return evaluate(D.make(7))
    , "domain_op_T_score: func(T) -> int");
}

// spec-case: EFFECTS-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 effects CLI resolves duplicate operation ceilings before domain migration" {
    try converges(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 duplicate effect clauses before input
        \\constraint A[P] = copy + op(score(item: P) -> int effects(output))
        \\constraint B[Q] = copy + op(score(item: Q) -> int effects(filesystem))
        \\domain D: int:
        \\    func make(value: int) -> D effects():
        \\        return wrap[D](value)
        \\    func score(item: D) -> int effects():
        \\        return unwrap(item)
        \\func evaluate[T: A + B](item: T) -> int effects(output, filesystem):
        \\    return T.score(item)
        \\func main() -> int:
        \\    return evaluate(D.make(1))
    , "record D:");
}

// spec-case: EFFECTS-REMOVED-1
// spec-case: FIX-MIGRATION-1
test "wave1 effects CLI retains parser diagnostic and fix across warm cache checks" {
    const source = "func main() -> int noio:\n    return 1\n";
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const first = try project.run("check", "main.selka", &.{});
    defer first.deinit();
    try testing.expectEqual(@as(u8, 1), first.status);
    const second = try project.run("check", "main.selka", &.{});
    defer second.deinit();
    try testing.expectEqual(@as(u8, 1), second.status);
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const original = try project.read("main.selka");
    defer testing.allocator.free(original);
    try testing.expectEqualStrings(source, original);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const clean = try project.run("check", "main.selka", &.{});
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}
