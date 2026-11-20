//! End-to-end migration of retired comprehensions and generator arguments.
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

// spec: COMPREHENSION-1
test "wave1 comprehensions and folds preserve iteration and empty input semantics" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const xs = [for i in range(5) yield i * 2]
        \\    const ys = [x + y for x in xs if x > 2 for y in [1, 2] if y > 1]
        \\    const zipped = [a + b for a, b in zip([1, 2], [3, 4])]
        \\    const indexed = [i + x for i, x in enumerate([4, 5])]
        \\    assert zipped == [4, 6]
        \\    assert indexed == [4, 6]
        \\    assert len(set(xs)) == 5
        \\    const total = sum(x for x in ys)
        \\    const low = min(x for x in ys)
        \\    const high = max(x for x in ys)
        \\    const d = {x: x + 1 for x in xs}
        \\    const s = {x for x in xs}
        \\    const z = sum(x for x in range(0))
        \\    const yes = any(x > 4 for x in xs)
        \\    const all_yes = all(x < 9 for x in xs)
        \\    if yes and all_yes:
        \\        return total + low + high + len(d) + len(s) + z
        \\    return 1
        \\
    ;
    try lifecycle(original, 50);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions fill helper preserves negative counts" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const value = 3
        \\    const empty = [for i in range(-1) yield 7]
        \\    const filled = [for i in range(4) yield value]
        \\    return len(empty) + sum(filled)
        \\
    ;
    try lifecycleWithText(original, 12, "lists.filled[int](-1, 7)");
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions module collisions keep explicit accumulator loops" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const lists = 3
        \\    const empty = [for i in range(-1) yield 7]
        \\    const filled = [for i in range(4) yield lists]
        \\    return len(empty) + sum(filled)
        \\
    ;
    try lifecycleWithText(original, 12, "mut gather_result_");
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions compose with contextual repetition and membership repairs" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const repeated: i16[] = [for i in range(2) yield 0] * 2
        \\    const flags = [x in [1, 2] for x in [1, 2, 3]]
        \\    const zeros: i16[] = [for i in range(3) yield 0]
        \\    const nested: i16[][] = [[0 for y in range(2)] for x in range(2)]
        \\    const small: dict[str, u8] = {copy(name): 0 for name in ["a", "b"]}
        \\    assert nested == [[0i16, 0i16], [0i16, 0i16]]
        \\    assert small["a"] == 0u8
        \\    assert flags == [True, True, False]
        \\    return len(repeated) + len(zeros)
        \\
    ;
    try lifecycle(original, 7);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions repair nested yields and sources in their repeated contexts" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func noted(mut calls: int[], value: int) -> int:
        \\    calls.append(value)
        \\    return value
        \\
        \\func main() -> int:
        \\    mut calls: int[] = []
        \\    const grid = [[noted(mut calls, x + y) for y in range(2)] for x in range(3)]
        \\    assert grid == [[0, 1], [1, 2], [2, 3]]
        \\    assert calls == [0, 1, 1, 2, 2, 3]
        \\    const flat = [x + 1 for x in [y * 2 for y in range(3)]]
        \\    assert flat == [1, 3, 5]
        \\    return len(calls)
        \\
    ;
    try lifecycle(original, 6);
}

// spec: COMPREHENSION-2
test "wave1 comprehensions generator any and all stop every nested loop before the next source" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func next(mut calls: int[]) -> int[]:
        \\    calls.append(1)
        \\    return [1, 2]
        \\
        \\func probe(mut calls: int[], value: bool) -> bool:
        \\    calls.append(1)
        \\    return value
        \\
        \\func main() -> int:
        \\    mut calls: int[] = []
        \\    const yes = any(probe(mut calls, True) for x in next(mut calls) for y in next(mut calls))
        \\    const no = all(probe(mut calls, False) for x in next(mut calls) for y in next(mut calls))
        \\    if yes and not no:
        \\        return len(calls)
        \\    return 1
        \\
    ;
    try lifecycle(original, 6);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions preserve source filter key value order and managed folds" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func input(mut trace: int[]) -> int[]:
        \\    trace.append(1)
        \\    return [1, 2]
        \\
        \\func filter(mut trace: int[], x: int) -> bool:
        \\    trace.append(10 + x)
        \\    return x == 2
        \\
        \\func stamp(mut trace: int[], x: int) -> int:
        \\    trace.append(x)
        \\    return x
        \\
        \\func main() -> int:
        \\    mut trace: int[] = []
        \\    const d = {stamp(mut trace, 20 + x): stamp(mut trace, 30 + x) for x in input(mut trace) if filter(mut trace, x)}
        \\    assert trace == [1, 11, 12, 22, 32]
        \\    const low = min(x for x in ["z", "alpha", "b"])
        \\    const high = max(x for x in ["z", "alpha", "b"])
        \\    assert low == "alpha"
        \\    assert high == "z"
        \\    assert not any(x > 0 for x in range(0))
        \\    assert all(x > 0 for x in range(0))
        \\    const zero = sum(x * 0.5 for x in range(0))
        \\    assert zero == 0.0
        \\    return d[22] + 10
        \\
    ;
    try lifecycle(original, 42);
}

// spec-case: COMPREHENSION-1
test "wave1 comprehensions retain min and max empty input traps" {
    for ([_][]const u8{ "min", "max" }) |name| {
        // migrate-embedded: skip original empty-generator fix lifecycle witness
        const original = try std.fmt.allocPrint(testing.allocator, "func main() -> int:\n    return {s}(x for x in range(0))\n", .{name});
        defer testing.allocator.free(original);
        var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
        defer project.deinit();
        const fixed = try project.run("fix", "main.selka", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 0), fixed.status);
        const checked = try project.run("check", "main.selka", &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        const executed = try project.run("run", "main.selka", &.{});
        defer executed.deinit();
        try testing.expect(contains(executed.stderr, "R_ASSERT"));
        try testing.expect(contains(executed.stderr, "arg is an empty sequence"));
        const again = try project.run("fix", "main.selka", &.{"--check"});
        defer again.deinit();
        try testing.expectEqual(@as(u8, 0), again.status);
    }
}

fn lifecycle(original: []const u8, answer: u8) !void {
    try lifecycleWithText(original, answer, "");
}

fn lifecycleWithText(original: []const u8, answer: u8, needle: []const u8) !void {
    try lifecycleExpected(original, answer, needle, .{});
}
const ExpectedRepair = struct { source: ?[]const u8 = null, code: ?[]const u8 = null };
fn lifecycleExpected(original: []const u8, answer: u8, needle: []const u8, expected: ExpectedRepair) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    if (expected.code) |diagnostic| try testing.expect(contains(preview.stdout, diagnostic));
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("{s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    const rewritten = try project.read("main.selka");
    defer testing.allocator.free(rewritten);
    try testing.expect(contains(rewritten, needle));
    if (expected.source) |source| try testing.expectEqualStrings(source, rewritten);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    const executed = try project.run("run", "main.selka", &.{"--verify-facts"});
    defer executed.deinit();
    try testing.expectEqualStrings("", executed.stderr);
    testing.expectEqual(answer, executed.status) catch |failure| {
        std.debug.print("{s}\n{s}\n", .{ executed.stdout, executed.stderr });
        return failure;
    };
}

// spec: COMPREHENSION-3
test "wave1 comprehensions generic repairs agree across imported independent roots" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func copied[T: copy + storable](values: T[]) -> T[]:
        \\    return [for value in values yield value]
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    return len(shared.copied([1, 2]))\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    return len(shared.copied[str](values=[\"a\", \"b\"]))\n" },
    };
    var project = try Project.init(&files);
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("shared.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(shared, unchanged);
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("{s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    const rewritten = try project.read("shared.selka");
    defer testing.allocator.free(rewritten);
    try testing.expect(contains(rewritten, ": T[] = []"));
    try testing.expect(contains(rewritten, ": T = copy(value)"));
    try testing.expect(contains(rewritten, ", own gather_value_"));
    for ([_][]const u8{ "first.selka", "second.selka" }) |root| {
        const checked = try project.run("check", root, &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        const ran = try project.run("run", root, &.{"--verify-facts"});
        defer ran.deinit();
        try testing.expectEqual(@as(u8, 2), ran.status);
    }
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: COMPREHENSION-3
test "wave1 comprehensions imported local nominal types survive independent roots" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public record PartSpec:
        \\    value: int
        \\
        \\public record Box[T]:
        \\    value: T
        \\
        \\public func parts() -> PartSpec[]:
        \\    return [PartSpec(value=i) for i in range(3)]
        \\
        \\public func filled() -> PartSpec[]:
        \\    const value = PartSpec(value=4)
        \\    return [for i in range(3) yield value]
        \\
        \\public func mapped() -> dict[str, PartSpec]:
        \\    return {"item": PartSpec(value=i) for i in range(2)}
        \\
        \\public func boxed[T: copy + storable](values: T[]) -> Box[T][]:
        \\    return [Box[T](value=value) for value in values]
        \\
    ;
    const files = [_]File{
        .{ .path = "shapes.selka", .data = shared },
        .{ .path = "padding.selka", .data = "public func number() -> int:\n    return 1\n" },
        .{ .path = "first.selka", .data = "import padding\nimport shapes\nfunc main() -> int:\n    return padding.number() + len(shapes.parts()) + len(shapes.boxed([1]))\n" },
        .{ .path = "second.selka", .data = "import shapes\nfunc main() -> int:\n    return len(shapes.boxed[shapes.PartSpec](values=shapes.parts()))\n" },
    };
    const first = try fixedLocalModule(&files, "first.selka");
    defer testing.allocator.free(first);
    const second = try fixedLocalModule(&files, "second.selka");
    defer testing.allocator.free(second);
    try testing.expectEqualStrings(first, second);
    try testing.expect(!contains(first, "shapes.PartSpec"));
    try testing.expect(contains(first, "lists.filled[PartSpec]"));
    try testing.expect(contains(first, ": Box[T][] = []"));
    var project = try Project.init(&files);
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("shapes.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(shared, unchanged);
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    for ([_][]const u8{ "first.selka", "second.selka" }) |root| {
        const checked = try project.run("check", root, &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
    }
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

fn fixedLocalModule(files: []const File, root: []const u8) ![]const u8 {
    var project = try Project.init(files);
    defer project.deinit();
    const fixed = try project.run("fix", root, &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("{s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    return project.read("shapes.selka");
}

// spec-case: COMPREHENSION-1
// spec-case: FIX-MIGRATION-1
test "wave1 comprehensions fill exact source contract" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const values = [for i in range(3) yield 7]
        \\    return len(values)
        \\
    ;
    const expected =
        \\import lists
        \\func main() -> int:
        \\    const values = lists.filled[int](3, 7)
        \\    return len(values)
        \\
    ;
    try lifecycleExpected(original, 3, "", .{ .source = expected, .code = "E_COMPREHENSION_REMOVED" });
}

// spec-case: COMPREHENSION-1
// spec-case: FIX-MIGRATION-1
test "wave1 comprehensions generator exact source contract" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    return sum(i for i in range(3))
        \\
    ;
    const expected =
        \\func main() -> int:
        \\    mut gather_result_35: int = 0
        \\    for i in range(0, 3):
        \\        const gather_value_35: int = i
        \\        gather_result_35 += gather_value_35
        \\    return gather_result_35
        \\
    ;
    try lifecycleExpected(original, 3, "", .{ .source = expected, .code = "E_GENERATOR_REMOVED" });
}
