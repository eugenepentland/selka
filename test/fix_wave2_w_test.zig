//! Wave 2 batch W: the wave 3 fixes' leftovers (plan §3.W), each with its
//! certain `selka fix` repair (FIX-MIGRATION-1 protocol).
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
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

    /// Run `selka COMMAND TARGET ARGS...` from the project directory.
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

/// The FIX-MIGRATION-1 protocol: the preview rewrites nothing, the fix applies
/// every edit, the result is exactly the expected program, it checks, and a
/// second preview finds nothing left to repair.
fn migration(original: []const u8, expected: []const u8, code: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("fix stdout: {s}\nfix stderr: {s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    try testing.expect(contains(fixed.stdout, code));
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

/// Run one program and require its exit status and standard output, so a repair
/// is judged by the value it keeps, not by the shape it rewrites to.
fn runPrints(source: []const u8, stdout: []const u8) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    testing.expectEqual(@as(u8, 0), ran.status) catch |failure| {
        std.debug.print("run stderr: {s}\n", .{ran.stderr});
        return failure;
    };
    try testing.expectEqualStrings(stdout, ran.stdout);
}

// spec: NEGATIVE-INDEX-REMOVED-1
// spec-case: NEGATIVE-INDEX-REMOVED-1
test "wave2 W1 the scalar helper's negative-position repair keeps the value on non-ASCII text" {
    // `len` counts octets and the helper's window counts scalars, so the repair
    // must spell `strings.char_count`. Before the fix it wrote `max(len(t) - 1, 0)`
    // = 4, which starts the search past the match and answers -1.
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const t = "λλb"
        \\    print(out, strings.char_find(t, "b", -1))
        \\    return 0
        \\
    ,
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const t = "λλb"
        \\    print(out, strings.char_find(t, "b", max(strings.char_count(t) - 1, 0)))
        \\    return 0
        \\
    , "E_NEGATIVE_INDEX_REMOVED");
    // The repaired program answers the pre-change value.
    try runPrints(
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const t = "λλb"
        \\    print(out, strings.char_find(t, "b", max(strings.char_count(t) - 1, 0)))
        \\    return 0
        \\
    , "2\n");
}

// spec-case: NEGATIVE-INDEX-REMOVED-1
test "wave2 W1 an octet position still counts len" {
    // A surface slice is an octet position (wave 3's C2), so its repair counts
    // `len`; only a scalar helper's window counts scalars.
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    print(out, len(text[-2:]))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    print(out, len(text[max(len(text) - 2, 0):]))
        \\    return 0
        \\
    , "E_NEGATIVE_INDEX_REMOVED");
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    print(out, len(text[max(len(text) - 2, 0):]))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave2 W3 a stored bound text view takes the copy repair on its binding" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    mut parts: str[] = []
        \\    const v = text[0:2]
        \\    append(mut parts, v)
        \\    print(out, len(parts[0]))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    mut parts: str[] = []
        \\    const v = copy(text[0:2])
        \\    append(mut parts, own v)
        \\    print(out, len(parts[0]))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave2 W3 a stored bound list view takes the copy repair on its binding" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3]
        \\    mut parts: int[][] = []
        \\    const v = xs[0:2]
        \\    append(mut parts, v)
        \\    print(out, len(parts[0]))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3]
        \\    mut parts: int[][] = []
        \\    const v = copy(xs[0:2])
        \\    append(mut parts, own v)
        \\    print(out, len(parts[0]))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
    // The repaired program answers what the silently copying one did.
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3]
        \\    mut parts: int[][] = []
        \\    const v = copy(xs[0:2])
        \\    append(mut parts, own v)
        \\    print(out, len(parts[0]))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "perf B1 a bound list view stored in a record field takes the copy repair" {
    // The wave 3 fix left the bound form: `check` passed and the build failed
    // with an unlocated `E_CORE_INVALID_IR` view escape. The binding is the same
    // view as the inline slice, so the repair lands on the binding.
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\record Bag:
        \\    items: int[]
        \\
        \\
        \\func keep(xs: int[]) -> Bag:
        \\    const part = xs[1:3]
        \\    return Bag(items=part)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4]).items))
        \\    return 0
        \\
    ,
        \\record Bag:
        \\    items: int[]
        \\
        \\
        \\func keep(xs: int[]) -> Bag:
        \\    const part = copy(xs[1:3])
        \\    return Bag(items=own part)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4]).items))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
    try runPrints(
        \\record Bag:
        \\    items: int[]
        \\
        \\
        \\func keep(xs: int[]) -> Bag:
        \\    const part = copy(xs[1:3])
        \\    return Bag(items=own part)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4]).items))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "perf B1 a bound list view stored in a list element takes the copy repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut outer: int[][] = [[1]]
        \\    const part = xs[1:3]
        \\    outer[0] = part
        \\    print(out, len(outer[0]))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut outer: int[][] = [[1]]
        \\    const part = copy(xs[1:3])
        \\    outer[0] = own part
        \\    print(out, len(outer[0]))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut outer: int[][] = [[1]]
        \\    const part = copy(xs[1:3])
        \\    outer[0] = own part
        \\    print(out, len(outer[0]))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "perf B1 a bound list view stored in a dictionary value takes the copy repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut groups: dict[str, int[]] = {}
        \\    const part = xs[1:3]
        \\    groups["a"] = part
        \\    print(out, len(groups["a"]))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut groups: dict[str, int[]] = {}
        \\    const part = copy(xs[1:3])
        \\    groups["a"] = own part
        \\    print(out, len(groups["a"]))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut groups: dict[str, int[]] = {}
        \\    const part = copy(xs[1:3])
        \\    groups["a"] = own part
        \\    print(out, len(groups["a"]))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "perf B1 a returned bound list view takes the declaration repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func keep(xs: int[]) -> int[]:
        \\    const part = xs[1:3]
        \\    return part
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4])))
        \\    return 0
        \\
    ,
        \\func keep(xs: int[]) -> int[] from xs:
        \\    const part = xs[1:3]
        \\    return part
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4])))
        \\    return 0
        \\
    , "E_BORROW_UNDECLARED");
    try runPrints(
        \\func keep(xs: int[]) -> int[] from xs:
        \\    const part = xs[1:3]
        \\    return part
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, len(keep([1, 2, 3, 4])))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave2 W4 a list view of a mutable source is refused like a text view" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    mut xs = [1, 2, 3]
        \\    const v = xs[0:2]
        \\    append(mut xs, 4)
        \\    print(out, len(v))
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    mut xs = [1, 2, 3]
        \\    const v = copy(xs[0:2])
        \\    append(mut xs, 4)
        \\    print(out, len(v))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    mut xs = [1, 2, 3]
        \\    const v = copy(xs[0:2])
        \\    append(mut xs, 4)
        \\    print(out, len(v))
        \\    return 0
        \\
    , "2\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave2 W2 a deferred list binding of two slices builds and keeps its value" {
    // The merge used to check and then fail with an unlocated
    // `E_CORE_UNSUPPORTED`; a view phi now borrows from both parents.
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    const v: int[]
        \\    if len(xs) > 2:
        \\        v = xs[0:2]
        \\    else:
        \\        v = xs[1:3]
        \\    print(out, len(v), v[0])
        \\    return 0
        \\
    , "2 1\n");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave2 W3 a read-only bound slice stays accepted" {
    try runPrints(
        \\func main(out: Stream) -> int:
        \\    const text = "abcd"
        \\    const v = text[0:2]
        \\    const xs = [1, 2, 3]
        \\    const w = xs[1:3]
        \\    print(out, len(v), v, len(w))
        \\    return 0
        \\
    , "2 ab 2\n");
}
