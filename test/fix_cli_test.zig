//! `mylang fix`, `check` on library and test entries, and `test --diagnostics=json`,
//! driven through the compiler binary exactly as a user or an agent runs them.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;

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

    /// Run `mylang COMMAND TARGET ARGS...` from the project directory with this
    /// project's cache, so the paths `fix` prints are project-relative.
    fn run(self: *const Project, command: []const u8, target: []const u8, args: []const []const u8) !Outcome {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
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

const fixable_main =
    \\import util.helpers
    \\import util.unused
    \\
    \\
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    helpers.grow(xs)
    \\    helpers.grow(xs)
    \\    return len(xs)
    \\
;
const fixable_helpers =
    \\module helpers
    \\
    \\public func grow(mut xs: int[]) -> Unit:
    \\    xs.append(1)
    \\
;
const unused_module =
    \\
    \\
    \\public func nothing() -> int:
    \\    return 0
    \\
;

// spec: FIX-MIGRATION-1
test "CLI fix applies every structured fix across modules to a fixed point" {
    var project = try Project.init(&.{
        .{ .path = "main.my", .data = fixable_main },
        .{ .path = "util/helpers.my", .data = fixable_helpers },
        .{ .path = "util/unused.my", .data = unused_module },
    });
    defer project.deinit();
    // `--check` reports what would change and writes nothing.
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "would fix util/helpers.my: 1 edit (E_MODULE_HEADER)"));
    const untouched = try project.read("util/helpers.my");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(fixable_helpers, untouched);
    // A real run removes the legacy module header, marks both calls and drops the unused import.
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fixed main.my: 3 edits (E_MUTATION_MARKER, W_UNUSED_IMPORT)"));
    try testing.expect(contains(fixed.stdout, "fixed util/helpers.my: 1 edit (E_MODULE_HEADER)"));
    try testing.expect(contains(fixed.stdout, "fix: 4 edits in 2 files over 3 rounds"));
    const main = try project.read("main.my");
    defer testing.allocator.free(main);
    try testing.expectEqualStrings(
        \\import util.helpers
        \\
        \\
        \\func main() -> int:
        \\    mut xs: int[] = []
        \\    helpers.grow(mut xs)
        \\    helpers.grow(mut xs)
        \\    return len(xs)
        \\
    , main);
    // Nothing is left, and the project checks.
    const again = try project.run("fix", "main.my", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", again.stdout);
    const checked = try project.run("check", "main.my", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
}

// spec-case: FRONTEND-MIGRATION-1
test "CLI fix migrates frontend syntax to a clean check and then reaches a fixed point" {
    const original = @embedFile("fixtures/fix-migration/frontend.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const before = try project.read("main.my");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.my");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "func shift(mut points: Point[], named delta: int) -> Unit:"));
    try testing.expect(contains(after, "mut answer = (if (True) then (points[0].x) else (0))"));
    const checked = try project.run("check", "main.my", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.my", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix splits receiver overlap into a preceding call without repeating effects" {
    const original = @embedFile("fixtures/fix-migration/receiver-overlap.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_FRONTEND_SYNTAX"));
    const before = try project.read("main.my");
    defer testing.allocator.free(before);
    try testing.expectEqualStrings(original, before);
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.my");
    defer testing.allocator.free(after);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, after, "selected(mut items)"));
    try testing.expect(contains(after, " = selected(mut items)\n    items[mutation_result_"));
    const checked = try project.run("check", "main.my", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.my", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec-case: FIX-MIGRATION-1
test "CLI fix reports what it cannot fix once and exits 1" {
    const library =
        \\
        \\
        \\public func grow(mut xs: int[]) -> Unit:
        \\    xs.append(missing)
        \\
    ;
    const first_test =
        \\import lib
        \\
        \\
        \\public func test_one() -> bool:
        \\    mut xs: int[] = []
        \\    lib.grow(xs)
        \\    return len(xs) == 1
        \\
    ;
    var project = try Project.init(&.{
        .{ .path = "lib.my", .data = library },
        .{ .path = "first_test.my", .data = first_test },
        .{ .path = "second_test.my", .data = "import lib\n\n\npublic func test_two() -> bool:\n    mut xs: int[] = []\n    lib.grow(mut xs)\n    return True\n" },
    });
    defer project.deinit();
    const outcome = try project.run("fix", ".", &.{});
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    // The unknown name in the shared module is reported once, not per test file.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "error[E_UNKNOWN_NAME]"));
    try testing.expect(contains(outcome.stdout, "fixed first_test.my: 1 edit (E_MUTATION_MARKER)"));
    const fixed = try project.read("first_test.my");
    defer testing.allocator.free(fixed);
    try testing.expect(contains(fixed, "lib.grow(mut xs)"));
    const json = try project.run("fix", ".", &.{"--diagnostics=json"});
    defer json.deinit();
    try testing.expect(contains(json.stderr, "\"version\":\"diagnostic-v1\""));
    const usage = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fix" } });
    defer testing.allocator.free(usage.stdout);
    defer testing.allocator.free(usage.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, usage.term);
    try testing.expect(contains(usage.stderr, "usage: mylang fix"));
}

// spec-case: CHECK-LIBRARY-2
test "CLI check checks a library module or a test file without main" {
    var project = try Project.init(&.{
        .{ .path = "lib.my", .data = "\n\npublic func one() -> int:\n    return 1\n" },
        .{ .path = "broken.my", .data = "\n\npublic func one() -> int:\n    return missing\n" },
        .{ .path = "plain_test.my", .data = "func test_one() -> bool:\n    return True\n" },
    });
    defer project.deinit();
    const library = try project.run("check", "lib.my", &.{});
    defer library.deinit();
    try testing.expectEqual(@as(u8, 0), library.status);
    try testing.expectEqualStrings("", library.stderr);
    // A library's own error keeps its line, and the stub never shows up.
    const broken = try project.run("check", "broken.my", &.{});
    defer broken.deinit();
    try testing.expectEqual(@as(u8, 1), broken.status);
    try testing.expect(contains(broken.stderr, "broken.my:4:12: error[E_UNKNOWN_NAME]"));
    try testing.expect(!contains(broken.stderr, "E_MAIN"));
    const headerless_test = try project.run("check", "plain_test.my", &.{});
    defer headerless_test.deinit();
    try testing.expectEqual(@as(u8, 0), headerless_test.status);
}

/// The pinned migration corpus: nine modules and tests of the value-semantics
/// Lox port (the copy the RC performance harness pins, 2026-09-29) with every
/// call-site `mut` marker stripped, as a program written before the markers
/// were required would read.
const lox_corpus = [_]File{
    .{ .path = "value.my", .data = @embedFile("fixtures/fix-migration/lox/value.my") },
    .{ .path = "table.my", .data = @embedFile("fixtures/fix-migration/lox/table.my") },
    .{ .path = "chunk.my", .data = @embedFile("fixtures/fix-migration/lox/chunk.my") },
    .{ .path = "object.my", .data = @embedFile("fixtures/fix-migration/lox/object.my") },
    .{ .path = "heap.my", .data = @embedFile("fixtures/fix-migration/lox/heap.my") },
    .{ .path = "lox_strings.my", .data = @embedFile("fixtures/fix-migration/lox/lox_strings.my") },
    .{ .path = "table_test.my", .data = @embedFile("fixtures/fix-migration/lox/table_test.my") },
    .{ .path = "heap_test.my", .data = @embedFile("fixtures/fix-migration/lox/heap_test.my") },
    .{ .path = "lox_strings_test.my", .data = @embedFile("fixtures/fix-migration/lox/lox_strings_test.my") },
};

/// How many of the corpus files `check` rejects.
fn rejectedFiles(project: *const Project) !usize {
    var rejected: usize = 0;
    for (lox_corpus) |file| {
        const outcome = try project.run("check", file.path, &.{});
        defer outcome.deinit();
        rejected += @intFromBool(outcome.status != 0);
    }
    return rejected;
}

// spec: FIX-MIGRATION-2
test "CLI fix migrates the pinned pre-marker Lox corpus with no hand edits" {
    var project = try Project.init(&lox_corpus);
    defer project.deinit();
    // Before: every file uses retired source syntax; writable calls also lack markers.
    try testing.expectEqual(@as(usize, 9), try rejectedFiles(&project));
    const migrated = try project.run("fix", ".", &.{});
    defer migrated.deinit();
    try testing.expectEqual(@as(u8, 0), migrated.status);
    try testing.expectEqualStrings("", migrated.stderr);
    try testing.expect(contains(migrated.stdout, "fix: 412 edits in 9 files over 30 rounds"));
    try testing.expect(contains(migrated.stdout, "fixed heap.my: 147 edits (E_MODULE_HEADER, E_BINDING_DECLARATION, E_MUTATION_MARKER, E_NAMED_PATTERN, E_NAMED_FIELDS)"));
    // After: every entry checks, and a second pass finds nothing to do.
    try testing.expectEqual(@as(usize, 0), try rejectedFiles(&project));
    const settled = try project.run("fix", ".", &.{"--check"});
    defer settled.deinit();
    try testing.expectEqual(@as(u8, 0), settled.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", settled.stdout);
    const heap = try project.read("heap.my");
    defer testing.allocator.free(heap);
    try testing.expect(contains(heap, "    mark_table(mut marker, rt.globals)\n"));
}

const abi_append_producer = "\npublic func change(mut items: int[]):\n    items.append(9)\n\npublic func append_only(mut items: int[]):\n    items.append(3)\n";
const abi_rebind_producer = "\npublic func change(mut items: int[]):\n    items = [7]\n    items.append(8)\n\npublic func append_only(mut items: int[]):\n    items.append(3)\n";
const abi_consumer =
    \\
    \\import lib
    \\func main() -> int:
    \\    mut first = [1]
    \\    mut first_saved = first
    \\    lib.change(mut first)
    \\    mut action = lib.change
    \\    mut second = [1]
    \\    mut second_saved = second
    \\    action(mut second)
    \\    mut third = [1]
    \\    mut third_saved = third
    \\    mut append = lib.append_only
    \\    append(mut third)
    \\    lib.append_only(mut third)
    \\    return if (first == second and first != [1] and first_saved == [1] and second_saved == [1] and third == [1, 3, 3] and third_saved == [1]) then (1) else (0)
;

fn abiRun(project: *const Project) !void {
    const result = try project.run("run", "main.my", &.{"--print-result"});
    defer result.deinit();
    try testing.expectEqual(@as(u8, 1), result.status);
    try testing.expectEqualStrings("1\n", result.stdout);
}

// spec-case: MUT-REBIND-CALLER-1
test "CLI warm imported direct and callback ABIs follow producer rebinding changes" {
    var project = try Project.init(&.{ .{ .path = "main.my", .data = abi_consumer }, .{ .path = "lib.my", .data = abi_append_producer } });
    defer project.deinit();
    try abiRun(&project);
    try abiRun(&project);
    try project.temp.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = abi_rebind_producer });
    try abiRun(&project);
    try abiRun(&project);
    const consumer = try project.read("main.my");
    defer testing.allocator.free(consumer);
    try testing.expectEqualStrings(abi_consumer, consumer);
}

// spec: NEW-CORE-S5-ARENA-3
// spec-case: FIX-MIGRATION-1
test "CLI fix removes retired arena blocks, dedents their bodies and unwraps escapes" {
    const original = @embedFile("fixtures/fix-migration/arenas.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_ARENA_REMOVED"));
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    const after = try project.read("main.my");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(arenas_migrated, after);
    const checked = try project.run("check", "main.my", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    try testing.expectEqualStrings("", checked.stderr);
    const again = try project.run("fix", "main.my", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

/// `fixtures/fix-migration/arenas.my` after `mylang fix`.
const arenas_migrated =
    \\# Pre-S5 arena code: `mylang fix` deletes every `with arena():` line, dedents
    \\# the block's body and rewrites each `name.escape(value)` to `value`.
    \\record Reading:
    \\    sensor: int
    \\    samples: int[]
    \\
    \\
    \\func collect(sensors: int) -> Reading[]:
    \\    mut readings: Reading[] = []
    \\    for sensor in range(sensors):
    \\        # one region per sensor
    \\        mut samples: int[] = []
    \\        for index in range(3):
    \\            samples.append(sensor * 3 + index)
    \\
    \\        # kept: a copy survives the region
    \\        readings.append(Reading(sensor=sensor, samples=samples))
    \\    return readings
    \\
    \\
    \\func loudest(readings: Reading[]) -> int:
    \\    mut best = 0
    \\# a comment at the left margin stays where it is
    \\    for reading in readings:
    \\        mut total = 0
    \\        for sample in reading.samples:
    \\            total = total + sample
    \\        if total > best:
    \\            best = total
    \\    return best
    \\
    \\
    \\func nested() -> int:
    \\    mut kept = "z"
    \\    mut joined = "-".join(["a", str(2)])
    \\    kept = (joined + "!")
    \\    mut size = len(joined)
    \\    # after the inner block
    \\    return len(kept) + size
    \\
    \\
    \\func main() -> int:
    \\    mut readings = collect(4)
    \\    return len(readings) + loudest(readings) + nested()
    \\
;

// spec-case: FIX-MIGRATION-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 CLI fix materializes stored dictionary projections with contextual list snapshots" {
    const original = @embedFile("fixtures/fix-migration/dictionary-views.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_MODULE_HEADER"));
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const after = try project.read("main.my");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "keys = list(mapping.keys())"));
    try testing.expect(contains(after, "values = list(mapping.values())"));
    try testing.expect(contains(after, "items = list(mapping.items())"));
    try testing.expect(contains(after, "nested = [list(mapping.values())]"));
    try testing.expect(contains(after, "interior = list(rows[0].values())"));
    const checked = try project.run("check", "main.my", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.my", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

fn storedViewCorpus(path: []const u8, text: []const u8) !void {
    var project = try Project.init(&.{.{ .path = path, .data = text }});
    defer project.deinit();
    const checked = try project.run("check", path, &.{"--diagnostics=json"});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "E_VIEW_STORED"));
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects the former held receiver snapshot history and aggregate view corpora" {
    try storedViewCorpus("rc_dictionary_views.my", @embedFile("fixtures/view-storage/rc_dictionary_views.my"));
    try storedViewCorpus("rc_view_receivers.my", @embedFile("fixtures/view-storage/rc_view_receivers.my"));
    try storedViewCorpus("live_view_snapshots.my", @embedFile("fixtures/view-storage/live_view_snapshots.my"));
    try storedViewCorpus("rc_semantic_history.my", @embedFile("fixtures/view-storage/rc_semantic_history.my"));
}

/// The shapes from the EDA and Lox port migrations (2026-10-09) that `mylang
/// fix` once broke: parse wrappers named for the builtin parser, and an
/// imported module whose union payloads, nested comprehensions, nested
/// conditionals and byte-literal conditionals carry overlapping repairs.
const port_defects = [_]File{
    .{ .path = "mylang.json", .data = @embedFile("fixtures/fix-migration/port-defects/mylang.json") },
    .{ .path = "main.my", .data = @embedFile("fixtures/fix-migration/port-defects/main.my") },
    .{ .path = "parsing.my", .data = @embedFile("fixtures/fix-migration/port-defects/parsing.my") },
    .{ .path = "shapes.my", .data = @embedFile("fixtures/fix-migration/port-defects/shapes.my") },
};

// spec: FIX-MIGRATION-OVERLAP-1
// spec-case: FRONTEND-NUMERIC-MIGRATION-3
// spec-case: FRONTEND-BYTES-PARENS-1
test "CLI fix migrates the port defect shapes without capture, overlapping edits or mangling" {
    var project = try Project.init(&port_defects);
    defer project.deinit();
    const migrated = try project.run("fix", ".", &.{});
    defer migrated.deinit();
    try testing.expectEqual(@as(u8, 0), migrated.status);
    try testing.expectEqualStrings("", migrated.stderr);
    const parsing = try project.read("parsing.my");
    defer testing.allocator.free(parsing);
    try testing.expect(contains(parsing, "public func parse_int(s: str) -> int?:\n    if len(s) == 0:\n        return None\n    return s.parse_int()\n"));
    try testing.expect(contains(parsing, "    return s.strip().parse_float()\n"));
    try testing.expect(contains(parsing, "    return (sign + digits).parse_int()\n"));
    const shapes = try project.read("shapes.my");
    defer testing.allocator.free(shapes);
    try testing.expect(contains(shapes, "public enum Tag:\n    items(value: Item[])\n    atom(value: bytes)\n    count(value: int)\n"));
    try testing.expect(contains(shapes, "    board\n    polygon(value: FixedArray[float, 2][])\n"));
    try testing.expect(contains(shapes, "    return [for part in parts yield PartSpec(title=part.name, pads=[for p in part.pins yield p + 1])]\n"));
    try testing.expect(contains(shapes, "    return (if (c) then (1) else ((if (d) then (2) else (3))))\n"));
    try testing.expect(contains(shapes, "    return [for x in xs yield (if (x > 0) then (x) else (-x))]\n"));
    try testing.expect(contains(shapes, "(if (desc is None) then (b\"\") else (desc))"));
    // The migrated program computes what the original did: no wrapper calls itself.
    const ran = try project.run("run", "main.my", &.{});
    defer ran.deinit();
    try testing.expectEqual(@as(u8, 71), ran.status);
    const settled = try project.run("fix", ".", &.{"--check"});
    defer settled.deinit();
    try testing.expectEqual(@as(u8, 0), settled.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", settled.stdout);
}

// spec-case: FIX-MIGRATION-CAPTURE-1
test "CLI fix leaves a float rename that would call the user's own wrapper for a hand edit" {
    const original = @embedFile("fixtures/fix-migration/capture.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 1), fixed.status);
    try testing.expect(contains(fixed.stdout, "fixed main.my: 1 edit (E_REMOVED_SPELLING)"));
    try testing.expect(contains(fixed.stderr, "this file declares or binds `abs`, so rename the call by hand"));
    const after = try project.read("main.my");
    defer testing.allocator.free(after);
    try testing.expect(contains(after, "    return sqrt(x)\n"));
    try testing.expect(contains(after, "    return f64_abs(x)\n"));
    try testing.expect(!contains(after, "return abs(x)"));
}
