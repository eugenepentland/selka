//! Tuple retirement preview/fix/project-wide migration contract.
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

fn migrate(files: []const File, needles: []const []const u8) !void {
    try migrateExpected(files, needles, null);
}
fn migrateExpected(files: []const File, needles: []const []const u8, expected: ?[]const u8) !void {
    var project = try Project.init(files);
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |err| {
        std.debug.print("tuple fix: {s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return err;
    };
    // Earlier retirements can hide tuples in the first preview; the completed
    // migration must still report that it applied the tuple repair.
    try testing.expect(contains(fixed.stdout, "E_TUPLE_REMOVED"));
    const result = try project.read(files[0].path);
    defer testing.allocator.free(result);
    for (needles) |needle| try testing.expect(contains(result, needle));
    if (expected) |source| try testing.expectEqualStrings(source, result);
    for (files) |file| {
        const checked = try project.run("check", file.path, &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
    }
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}
// spec: TUPLE-REMOVED-1
// spec-case: TUPLE-3
test "wave1 tuple swap stages every operand before writes" {
    try migrateExpected(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut a = 1
        \\    mut b = 2
        \\    a, b = b, a
        \\    return a * 10 + b
        \\
    }}, &.{ "tuple_value_0_", "tuple_value_1_" },
        \\func main() -> int:
        \\    mut a = 1
        \\    mut b = 2
        \\    const tuple_value_0_52 = b
        \\    const tuple_value_1_52 = a
        \\    a = tuple_value_0_52
        \\    b = tuple_value_1_52
        \\    return a * 10 + b
        \\
    );
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple return names fields and expands every call site" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func split(n: int) -> tuple[int, int]:
        \\    const head = n
        \\    const rest = n + 1
        \\    return head, rest
        \\
        \\func main() -> int:
        \\    const left, right = split(4)
        \\    return left * 10 + right
        \\
    }}, &.{ "public record Split:", "head: int", "rest: int", "return Split(head=head, rest=rest)", ".head", ".rest" });
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple return inferred names collision and named generic calls" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\record Pair:
        \\    used: int
        \\
        \\func pair[T](value: T) -> tuple[T, T]:
        \\    const head = value
        \\    const rest = value
        \\    return head, rest
        \\
        \\func main() -> int:
        \\    const first, second = pair(value=4)
        \\    const text_a, text_b = pair[str](value="x")
        \\    return first + second + len(text_a) + len(text_b)
        \\
    }}, &.{ "public record Pair_1[T]:", "head=copy(head), rest=copy(rest)", " = own tuple_field_" });
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple shared signature survives an unrelated independent root error" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func split(n: int) -> tuple[int, int]:
        \\    const head = n
        \\    const rest = n + 1
        \\    return head, rest
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.split(1)\n    return a + b\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.split(2)\n    return missing + a + b\n" },
    };
    var project = try Project.init(&files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const unchanged = try project.read("shared.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(shared, unchanged);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.split(2)\n    return a + b\n" });
    const repaired = try project.run("fix", ".", &.{});
    defer repaired.deinit();
    testing.expectEqual(@as(u8, 0), repaired.status) catch |err| {
        std.debug.print("tuple project fix: {s}\n{s}\n", .{ repaired.stdout, repaired.stderr });
        return err;
    };
}
// spec: TUPLE-6
test "wave1 tuple stored and printed tuples remain manual diagnostics" {
    const source_text =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const pair = (1, 2)
        \\    print(pair)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source_text }});
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stderr, "E_TUPLE_REMOVED"));
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(source_text, unchanged);
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple shared signature waits for unsupported independent consumer" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func split(n: int) -> tuple[int, int]:
        \\    const head = n
        \\    const rest = n + 1
        \\    return head, rest
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.split(1)\n    return a + b\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const stored = shared.split(2)\n    print(stored)\n    return 0\n" },
    };
    var project = try Project.init(&files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple sort key returns become record keys" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func key(value: int) -> tuple[int, int]:
        \\    return -value, value
        \\func main() -> int:
        \\    const values = sorted([1, 3, 2], key=key)
        \\    return values[0]
        \\
    }}, &.{ "public record Key:", "return Key(field_1=-value, field_2=value)" });
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple waits for earlier scalar domain migration without deadlock" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\domain Count: int:
        \\    pass
        \\func split(n: int) -> tuple[int, int]:
        \\    const head = n
        \\    const rest = n + 1
        \\    return head, rest
        \\func main() -> int:
        \\    const first, second = split(4)
        \\    return first + second
        \\
    }}, &.{ "record Count:", "public record Split:" });
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple shared literal-return fields ignore consumer names and import closures" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func pair() -> tuple[int, int]:
        \\    return 1, 2
        \\
    ;
    try migrate(&.{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "other.selka", .data = "public func pair() -> int:\n    return 0\n" },
        .{ .path = "first.selka", .data = "import shared\nimport other\nfunc main() -> int:\n    const x, y = shared.pair()\n    return x + y + other.pair()\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.pair()\n    return a + b\n" },
    }, &.{ "public record Pair:", "field_1: int", "field_2: int", "return Pair(field_1=1, field_2=2)" });
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple literal return and generic signature retain two concrete providers" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func duplicate[T](value: T) -> tuple[T, T]:
        \\    return value, value
        \\func main() -> int:
        \\    const x, y = duplicate(value=4)
        \\    const a, b = duplicate[str](value="x")
        \\    return x + y + len(a) + len(b)
        \\
    }}, &.{ "public record Duplicate[T]:", "field_1: T", "field_2: T" });
}
// spec-case: TUPLE-REMOVED-1
// spec-case: PY-DESTRUCTURE-PLACE-1
test "wave1 tuple place targets run after every RHS operand in original order" {
    const source_text =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func mark(events: mut int[], value: int) -> int:
        \\    events.append(value)
        \\    return value
        \\func index(events: mut int[], value: int) -> int:
        \\    events.append(value)
        \\    return value - 3
        \\func main() -> int:
        \\    mut events: int[] = []
        \\    mut values = [0, 0]
        \\    values[index(events, 3)], values[index(events, 4)] = mark(events, 1), mark(events, 2)
        \\    assert events == [1, 2, 3, 4]
        \\    assert values == [1, 2]
        \\    return 0
        \\
    ;
    try migrate(&.{.{ .path = "main.selka", .data = source_text }}, &.{ "tuple_value_0_", "tuple_value_1_" });
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source_text }});
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    testing.expectEqual(@as(u8, 0), ran.status) catch |err| {
        std.debug.print("tuple place run: {s}\n{s}\n", .{ ran.stdout, ran.stderr });
        return err;
    };
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple shared signature waits for a parser failure before tuple recognition" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func pair() -> tuple[int, int]:
        \\    return 1, 2
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const x, y = shared.pair()\n    return x + y\n" },
        .{ .path = "broken.selka", .data = "func main() -> int:\n    return ]\n" },
    };
    var project = try Project.init(&files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stderr, "withheld E_TUPLE_REMOVED repairs: incomplete import or declaration graph"));
    try testing.expect(!contains(fixed.stdout, "fix: nothing to fix"));
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
}

const independent_sort = @embedFile("fixtures/fix-tuple-directory/sort-key.selka");

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple C1 independent sort repair proceeds beside unrelated errors and tuple refusals" {
    for ([_][]const u8{
        "import strings\nfunc main() -> int:\n    assert strings.starts_with(\"x\", \"x\")\n    return missing\n",
        // migrate-embedded: skip intentional independent unsupported tuple storage.
        "func main(out: Stream) -> int:\n    const stored = (1, 2)\n    print(out, stored)\n    return 0\n",
    }) |negative| {
        var project = try Project.init(&.{
            .{ .path = "sort_key.selka", .data = independent_sort },
            .{ .path = "negative.selka", .data = negative },
        });
        defer project.deinit();
        const preview = try project.run("fix", ".", &.{"--check"});
        defer preview.deinit();
        try testing.expectEqual(@as(u8, 1), preview.status);
        try testing.expect(contains(preview.stdout, "would fix sort_key.selka:"));
        try testing.expect(contains(preview.stdout, "E_TUPLE_REMOVED"));
        const before = try project.read("sort_key.selka");
        defer testing.allocator.free(before);
        try testing.expectEqualStrings(independent_sort, before);
        const fixed = try project.run("fix", ".", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 1), fixed.status);
        try testing.expect(contains(fixed.stdout, "fixed sort_key.selka:"));
        const after = try project.read("sort_key.selka");
        defer testing.allocator.free(after);
        try testing.expect(contains(after, "public record Key:"));
        try testing.expect(contains(after, "copy(value.text)"));
        const unchanged = try project.read("negative.selka");
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(negative, unchanged);
        const checked = try project.run("check", "sort_key.selka", &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
        const ran = try project.run("run", "sort_key.selka", &.{});
        defer ran.deinit();
        try testing.expectEqual(@as(u8, 0), ran.status);
        try testing.expectEqualStrings("a\n", ran.stdout);
        const again = try project.run("fix", ".", &.{"--check"});
        defer again.deinit();
        try testing.expectEqual(@as(u8, 1), again.status);
        try testing.expect(!contains(again.stdout, "would fix"));
        const stable = try project.read("sort_key.selka");
        defer testing.allocator.free(stable);
        try testing.expectEqualStrings(after, stable);
    }
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple C1 shared scopes defer transitively and name the withheld repairs" {
    const files = [_]File{
        .{ .path = "shared.selka", .data = "public func pair() -> tuple[int, int]:\n    return 1, 2\n" },
        .{ .path = "extra.selka", .data = "public func value() -> int:\n    return 0\n" },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const x, y = shared.pair()\n    return x + y\n" },
        .{ .path = "bridge.selka", .data = "import shared\nimport extra\nfunc main() -> int:\n    const x, y = shared.pair()\n    return x + y + extra.value()\n" },
        .{ .path = "negative.selka", .data = "import extra\nfunc main() -> int:\n    return extra.value() + missing\n" },
    };
    var project = try Project.init(&files);
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stderr, "withheld E_TUPLE_REMOVED repairs: a shared import or declaration group has unresolved diagnostics"));
    try testing.expect(contains(fixed.stdout, "fix: tuple repairs withheld; diagnostics remain"));
    for (files) |file| {
        const unchanged = try project.read(file.path);
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(file.data, unchanged);
    }
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple C1 tupleScope and syntaxComplete retain directory wide deferral for incomplete graphs" {
    for ([_][]const u8{
        "import absent\nfunc main() -> int:\n    return absent.value()\n",
        "func main() -> int:\n    return ]\n",
    }) |broken| {
        const files = [_]File{
            .{ .path = "sort_key.selka", .data = independent_sort },
            .{ .path = "negative.selka", .data = broken },
        };
        var project = try Project.init(&files);
        defer project.deinit();
        const preview = try project.run("fix", ".", &.{"--check"});
        defer preview.deinit();
        try testing.expectEqual(@as(u8, 1), preview.status);
        try testing.expect(contains(preview.stderr, "withheld E_TUPLE_REMOVED repairs: incomplete import or declaration graph"));
        try testing.expect(!contains(preview.stdout, "fix: nothing to fix"));
        const fixed = try project.run("fix", ".", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 1), fixed.status);
        for (files) |file| {
            const unchanged = try project.read(file.path);
            defer testing.allocator.free(unchanged);
            try testing.expectEqualStrings(file.data, unchanged);
        }
    }
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple C1 connected callers migrate beside a disjoint semantic refusal" {
    const negative = "func main() -> int:\n    return missing\n";
    var project = try Project.init(&.{
        .{ .path = "shared.selka", .data = "public func pair() -> tuple[int, int]:\n    return 1, 2\n" },
        .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const x, y = shared.pair()\n    assert x + y == 3\n    return 0\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    const a, b = shared.pair()\n    assert a + b == 3\n    return 0\n" },
        .{ .path = "negative.selka", .data = negative },
    });
    defer project.deinit();
    const preview = try project.run("fix", ".", &.{"--check"});
    defer preview.deinit();
    for ([_][]const u8{ "shared.selka", "first.selka", "second.selka" }) |path| {
        const line = try std.fmt.allocPrint(testing.allocator, "would fix {s}:", .{path});
        defer testing.allocator.free(line);
        try testing.expect(contains(preview.stdout, line));
    }
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const shared = try project.read("shared.selka");
    defer testing.allocator.free(shared);
    try testing.expect(contains(shared, "public record Pair:"));
    for ([_][]const u8{ "first.selka", "second.selka" }) |path| {
        const checked = try project.run("check", path, &.{});
        defer checked.deinit();
        try testing.expectEqual(@as(u8, 0), checked.status);
    }
    const unchanged = try project.read("negative.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(negative, unchanged);
    const ran = try project.run("run", "first.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 1), again.status);
    try testing.expect(!contains(again.stdout, "would fix"));
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple C1 tupleScope retains shared consumer protection through source aliases" {
    for ([_]bool{ false, true }) |hard_link| {
        const files = [_]File{
            .{ .path = "shared.selka", .data = "public func pair() -> tuple[int, int]:\n    return 1, 2\n" },
            .{ .path = "first.selka", .data = "import shared\nfunc main() -> int:\n    const x, y = shared.pair()\n    return x + y\n" },
            .{ .path = "second.selka", .data = "import alias\nfunc main() -> int:\n    const x, y = alias.pair()\n    return x + y + missing\n" },
        };
        var project = try Project.init(&files);
        defer project.deinit();
        if (hard_link) {
            try project.temp.dir.hardLink("shared.selka", project.temp.dir, "alias.selka", testing.io, .{});
        } else try project.temp.dir.symLink(testing.io, "shared.selka", "alias.selka", .{});
        const fixed = try project.run("fix", ".", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 1), fixed.status);
        try testing.expect(contains(fixed.stderr, "withheld E_TUPLE_REMOVED repairs: incomplete import or declaration graph"));
        for (files) |file| {
            const unchanged = try project.read(file.path);
            defer testing.allocator.free(unchanged);
            try testing.expectEqualStrings(file.data, unchanged);
        }
    }
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple swap snapshots a managed local before a later operand writes it" {
    const source_text =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func change(values: mut int[]) -> int[]:
        \\    values.append(9)
        \\    return copy(values)
        \\func main() -> int:
        \\    mut left = [1]
        \\    mut right = [2]
        \\    left, right = right, change(right)
        \\    assert left == [2]
        \\    assert right == [2, 9]
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source_text }});
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |err| {
        std.debug.print("managed tuple fix: {s}\n{s}\n", .{ fixed.stdout, fixed.stderr });
        return err;
    };
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    const snapshot = std.mem.indexOf(u8, migrated, "= copy(right)") orelse return error.TestUnexpectedResult;
    const mutation = std.mem.indexOf(u8, migrated, "= change(mut right)") orelse return error.TestUnexpectedResult;
    try testing.expect(snapshot < mutation);
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    testing.expectEqual(@as(u8, 0), ran.status) catch |err| {
        std.debug.print("managed tuple run: {s}\n{s}\n", .{ ran.stdout, ran.stderr });
        return err;
    };
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple Result-return records remain manual without partial consumer writes" {
    const source_text =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func pair() -> tuple[Result[int, str], int]:
        \\    const result: Result[int, str] = Ok(1)
        \\    const number = 2
        \\    return result, number
        \\func main() -> int:
        \\    const _, count = pair()
        \\    return count
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source_text }});
    defer project.deinit();
    const fixed = try project.run("fix", ".", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(source_text, unchanged);
    try testing.expect(contains(fixed.stderr, "E_TUPLE_REMOVED"));
}
// spec-case: TUPLE-REMOVED-1
test "wave1 tuple ignored Result operands are explicitly discarded after staging" {
    try migrateExpected(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const result: Result[int, str] = Ok(1)
        \\    const _, number = result, 2
        \\    return number
        \\
    }}, &.{ "_ = tuple_value_0_", "const number = tuple_value_1_" },
        \\func main() -> int:
        \\    const result: Result[int, str] = Ok(1)
        \\    const tuple_value_0_67 = own result
        \\    const tuple_value_1_67 = 2
        \\    _ = tuple_value_0_67
        \\    const number = tuple_value_1_67
        \\    return number
        \\
    );
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple scalar Results stage without an own marker" {
    try migrateExpected(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const result: Result[int, int] = Ok(1)
        \\    const _, number = result, 2
        \\    return number
        \\
    }}, &.{"_ = tuple_value_0_"},
        \\func main() -> int:
        \\    const result: Result[int, int] = Ok(1)
        \\    const tuple_value_0_67 = result
        \\    const tuple_value_1_67 = 2
        \\    _ = tuple_value_0_67
        \\    const number = tuple_value_1_67
        \\    return number
        \\
    );
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple owned Result parameters transfer into staging" {
    try migrate(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func use(own result: Result[int, str]) -> int:
        \\    const _, number = result, 2
        \\    return number
        \\func main() -> int:
        \\    return use(Ok(1))
        \\
    }}, &.{ "= own result", "_ = tuple_value_0_", "const number = tuple_value_1_" });
}

// spec-case: TUPLE-REMOVED-1
test "wave1 tuple borrowed Result operands remain deferred without partial staging" {
    const cases = [_][]const u8{
        // migrate-embedded: skip intentional FIX-MIGRATION-1 unsupported borrowed operand
        \\func use(result: Result[int, str]) -> int:
        \\    const _, number = result, 2
        \\    return number
        \\func main() -> int:
        \\    return use(Ok(1))
        \\
        ,
        // migrate-embedded: skip intentional FIX-MIGRATION-1 unsupported from operand
        \\func head(source: str) -> str from source fails int:
        \\    return source[0:1]
        \\func main() -> int:
        \\    const source = "source-" + str(1)
        \\    const result = head(source)
        \\    const _, number = result, 2
        \\    return number
        \\
        ,
    };
    for (cases) |source_text| {
        var project = try Project.init(&.{.{ .path = "main.selka", .data = source_text }});
        defer project.deinit();
        const fixed = try project.run("fix", ".", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 1), fixed.status);
        try testing.expect(contains(fixed.stderr, "E_TUPLE_REMOVED"));
        const unchanged = try project.read("main.selka");
        defer testing.allocator.free(unchanged);
        try testing.expectEqualStrings(source_text, unchanged);
    }
}
