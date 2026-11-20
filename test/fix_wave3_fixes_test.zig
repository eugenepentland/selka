//! Wave 3 fixes: the refusals the review's regressions add, each with its
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

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 fixes r4 a live view invalidated in a loop takes the copy repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    mut s = "abcdef"
        \\    const h = s[0:4]
        \\    for i in range(3):
        \\        s += "x"
        \\    print(out, h)
        \\    return 0
        \\
    ,
        \\func main(out: Stream) -> int:
        \\    mut s = "abcdef"
        \\    const h = copy(s[0:4])
        \\    for i in range(3):
        \\        s += "x"
        \\    print(out, h)
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 fixes r4 a live view invalidated in a loop is not a loop move" {
    const original =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main(out: Stream) -> int:
        \\    mut s = "abcdef"
        \\    const h = s[0:4]
        \\    for i in range(3):
        \\        s += "x"
        \\    print(out, h)
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "\"code\":\"E_SLICE_ESCAPES\""));
    try testing.expect(!contains(checked.stderr, "E_SINGLE_OWNER_LOOP"));
    // The refusal points at the view's definition, where the copy belongs.
    try testing.expect(contains(checked.stderr, "\"start\":{\"line\":3,\"column\":15}"));
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 fixes x1 a view result that outlives its source takes the copy repair" {
    // X1: the declared source keeps the result borrowed, so mutation while the
    // result is live is an R2 overlap, repaired by copying the call result.
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func head(t: str) -> str from t:
        \\    return t[0:4]
        \\func main(out: Stream) -> int:
        \\    mut s = "wxyz" + str(1)
        \\    const h = head(s)
        \\    for i in range(3):
        \\        s += "abcdefgh"
        \\    print(out, h)
        \\    return 0
        \\
    ,
        \\func head(t: str) -> str from t:
        \\    return t[0:4]
        \\func main(out: Stream) -> int:
        \\    mut s = "wxyz" + str(1)
        \\    const h = copy(head(s))
        \\    for i in range(3):
        \\        s += "abcdefgh"
        \\    print(out, h)
        \\    return 0
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: a failing command never exits with empty standard error" {
    const failing = [_][]const u8{
        // A slice stored in a list: the escape rule's copy repair.
        // migrate-embedded: skip intentional failing-command slice storage diagnostic input
        \\func main() -> int:
        \\    const s = "abc"
        \\    const held = [s[0:1]]
        \\    return len(held)
        ,
        // A view result invalidated by its source (X1).
        // migrate-embedded: skip intentional failing-command invalidated view diagnostic input
        \\func head(t: str) -> str from t:
        \\    return t[0:2]
        \\func main() -> int:
        \\    mut s = "abcd"
        \\    const h = head(s)
        \\    s += "x"
        \\    return len(h)
        ,
        // A type error.
        \\func main() -> int:
        \\    return "text"
        ,
        // A call to a function that does not exist.
        \\func main() -> int:
        \\    return missing(1)
        ,
    };
    for (failing) |source| {
        for ([_][]const u8{ "check", "build", "run" }) |command| {
            var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
            defer project.deinit();
            const args: []const []const u8 = if (std.mem.eql(u8, command, "build")) &.{ "-o", "out" } else &.{};
            const outcome = try project.run(command, "main.selka", args);
            defer outcome.deinit();
            try testing.expect(outcome.status != 0);
            try testing.expect(outcome.stderr.len != 0);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: the view-shape matrix is current" {
    // The generator is the source of truth: regenerate in memory and compare.
    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ "python3", "tests/view_shapes/matrix.py", "--check" },
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term) catch |failure| {
        std.debug.print("matrix check: {s}{s}\n", .{ result.stdout, result.stderr });
        return failure;
    };
    try testing.expect(contains(result.stdout, "view-shape matrix is current"));
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: every refused view-shape cell takes its certain fix" {
    const a = testing.allocator;
    const directory = "tests/view_shapes/refused";
    var opened = try std.Io.Dir.cwd().openDir(testing.io, directory, .{ .iterate = true });
    defer opened.close(testing.io);
    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| a.free(name);
        names.deinit(a);
    }
    var iterator = opened.iterate();
    while (try iterator.next(testing.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".selka")) continue;
        if (std.mem.endsWith(u8, entry.name, ".fixed.selka")) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    try testing.expect(names.items.len != 0);
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    for (names.items) |name| {
        const path = try std.fs.path.join(a, &.{ directory, name });
        defer a.free(path);
        const stem = name[0 .. name.len - ".selka".len];
        const fixed_name = try std.fmt.allocPrint(a, "{s}.fixed.selka", .{stem});
        defer a.free(fixed_name);
        const fixed_path = try std.fs.path.join(a, &.{ directory, fixed_name });
        defer a.free(fixed_path);
        const out_name = try std.fmt.allocPrint(a, "{s}.out", .{stem});
        defer a.free(out_name);
        const out_path = try std.fs.path.join(a, &.{ directory, out_name });
        defer a.free(out_path);
        const original = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, a, .limited(1 << 20));
        defer a.free(original);
        const expected = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixed_path, a, .limited(1 << 20));
        defer a.free(expected);
        const expected_out = try std.Io.Dir.cwd().readFileAlloc(testing.io, out_path, a, .limited(1 << 16));
        defer a.free(expected_out);
        // The refused cell is refused, and the diagnostic carries a fix.
        var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
        defer project.deinit();
        const checked = try project.run("check", "main.selka", &.{"--diagnostics=json"});
        defer checked.deinit();
        testing.expect(checked.status != 0) catch |failure| {
            std.debug.print("{s}: expected a refusal\n", .{name});
            return failure;
        };
        try testing.expect(contains(checked.stderr, "\"code\":\"E_"));
        try testing.expect(contains(checked.stderr, "fix.edits") or contains(checked.stderr, "\"edits\""));
        // The certain fix reproduces the committed fixed program exactly.
        const fixed = try project.run("fix", "main.selka", &.{});
        defer fixed.deinit();
        try testing.expectEqual(@as(u8, 0), fixed.status);
        const produced = try project.read("main.selka");
        defer a.free(produced);
        testing.expectEqualStrings(expected, produced) catch |failure| {
            std.debug.print("{s}: fix output differs from the committed cell\n", .{name});
            return failure;
        };
        // And the fixed program prints the pre-wave-3 value.
        const executed = try project.run("run", "main.selka", &.{});
        defer executed.deinit();
        try testing.expectEqual(@as(u8, 0), executed.status);
        try testing.expectEqualStrings(expected_out, executed.stdout);
    }
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 fixes b1 a stored list slice takes the copy repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\record Bag:
        \\    items: int[]
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    const bag = Bag(items=xs[1:3])
        \\    const outer = [xs[1:3]]
        \\    print(out, len(bag.items) + len(outer))
        \\    return 0
        \\
    ,
        \\record Bag:
        \\    items: int[]
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    const bag = Bag(items=copy(xs[1:3]))
        \\    const outer = [copy(xs[1:3])]
        \\    print(out, len(bag.items) + len(outer))
        \\    return 0
        \\
    , "E_SLICE_ESCAPES");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "wave3 fixes b1 a returned list slice takes the declaration repair" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func middle(xs: int[]) -> int[]:
        \\    return xs[1:3]
        \\func main(out: Stream) -> int:
        \\    print(out, len(middle([1, 2, 3, 4])))
        \\    return 0
        \\
    ,
        \\func middle(xs: int[]) -> int[] from xs:
        \\    return xs[1:3]
        \\func main(out: Stream) -> int:
        \\    print(out, len(middle([1, 2, 3, 4])))
        \\    return 0
        \\
    , "E_BORROW_UNDECLARED");
}

// spec-case: TEXT-INDEX-4
test "wave3 fixes c2 a str search answers in octet offsets and the helpers stay scalar" {
    const source =
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const s = "λbλb"
        \\    print(out, strings.find(s, "b") == Some(2), strings.rfind(s, "b") == Some(5), strings.text_index(s, "b"), strings.text_rindex(s, "b"))
        \\    print(out, strings.find(s, "b", 2).unwrap_or(-1), strings.count(s, "b"), strings.char_find(s, "b"), strings.char_count_of(s, "b"))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 0), ran.status);
    try testing.expectEqualStrings("True True 2 5\n2 2 1 2\n", ran.stdout);
}

// spec-case: TEXT-INDEX-4
// The method `s.find("b", 1)` this test was written with is refused since W13-S5; `strings.find` is a library body,
// so the trap's site is in `@stdlib/strings.selka`. Since FX18 the report's first line names the program's own call and the
// library frame follows it as context, with the program's callers after it.
test "wave3 fixes c2 a ranged endpoint inside a scalar traps at its call" {
    const source =
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const s = "λb"
        \\    print(out, strings.find(s, "b", 1).unwrap_or(-1))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const ran = try project.run("run", "main.selka", &.{});
    defer ran.deinit();
    try testing.expect(ran.status != 0);
    try testing.expect(std.mem.startsWith(u8, ran.stderr, "main.selka:5:16: error[R_TEXT_BOUNDARY]: "));
    try testing.expect(contains(ran.stderr, "\n  in strings::find at @stdlib/strings.selka:"));
    try testing.expect(contains(ran.stderr, "\n  in main::main at main.selka:5:16\n"));
}

// spec: MODULE-NOT-IMPORTED-1
test "wave3 fixes b2 a helper call without its import takes the import repair" {
    // The pre-change source names two module functions and imports neither.
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 missing import before input
        \\import lists
        \\public func widen(values: int[]) -> int[]:
        \\    return lists.stride(values, None, None, 2)
        \\public func size(text: str) -> int:
        \\    return strings.char_count(text)
        \\
    ,
        \\import lists
        \\import strings
        \\
        \\public func widen(values: int[]) -> int[]:
        \\    return lists.stride(values, None, None, 2)
        \\public func size(text: str) -> int:
        \\    return strings.char_count(text)
        \\
    , "E_MODULE_NOT_IMPORTED");
}

// spec: DIAG-ORACLE-1
// A nearest name is a guess (`strings.rfind` one edit from `strings.find` is another function), so the refusal names the candidate
// and carries no fix: `selka fix` leaves the file as it is.
test "wave3 fixes b2 a misspelt function of a module names the close one and selka fix leaves the file alone" {
    const source =
        \\import strings
        \\
        \\public func all_digits(text: str) -> bool:
        \\    return strings.isdigit(text)
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "module `strings` declares no `isdigit`; did you mean `is_digit`?"));
    try testing.expect(!contains(checked.stderr, "selka fix"));
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const fixed = try project.run("fix", "main.selka", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(source, unchanged);
}

// spec: MODULE-NOT-IMPORTED-1
test "wave3 fixes b2 a single-file program keeps the helper spellings" {
    // A program with no module header cannot write an `import`, so the prelude
    // spelling stands in for one; the rule binds where a module exists.
    const source =
        \\func main() -> int:
        \\    return strings.char_count("abc")
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = source }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec: TEXT-INDEX-4
test "wave3 fixes c2 leaves bytes and the unranged counts alone" {
    const clean =
        \\import bytes
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const b = b"abcd"
        \\    const s = "abc"
        \\    print(out, bytes.find(b, b"b"), bytes.rfind(b, b"c"), bytes.count(b, b"b", 1), bytes.starts_with(b, b"a", 0))
        \\    print(out, strings.count(s, "b"), strings.starts_with(s, "a"), strings.ends_with(s, "c"))
        \\    return 0
        \\
    ;
    var project = try Project.init(&.{.{ .path = "main.selka", .data = clean }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}
