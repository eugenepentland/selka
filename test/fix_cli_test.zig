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
    \\module main
    \\import util.helpers
    \\import util.unused
    \\
    \\
    \\def main() -> int:
    \\    xs: list[int] = []
    \\    helpers.grow(xs)
    \\    helpers.grow(xs)
    \\    return len(xs)
    \\
;
const fixable_helpers =
    \\module helpers
    \\
    \\
    \\public def grow(xs: mut list[int]) -> None:
    \\    xs.append(1)
    \\
;
const unused_module =
    \\module util.unused
    \\
    \\
    \\public def nothing() -> int:
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
    try testing.expect(contains(preview.stdout, "would fix util/helpers.my: 1 edit (E_MODULE_NAME)"));
    const untouched = try project.read("util/helpers.my");
    defer testing.allocator.free(untouched);
    try testing.expectEqualStrings(fixable_helpers, untouched);
    // A real run renames the module, marks both calls and drops the unused import.
    const fixed = try project.run("fix", "main.my", &.{});
    defer fixed.deinit();
    try testing.expectEqual(@as(u8, 0), fixed.status);
    try testing.expectEqualStrings("", fixed.stderr);
    try testing.expect(contains(fixed.stdout, "fixed main.my: 3 edits (E_MUTATION_MARKER, W_UNUSED_IMPORT)"));
    try testing.expect(contains(fixed.stdout, "fixed util/helpers.my: 1 edit (E_MODULE_NAME)"));
    try testing.expect(contains(fixed.stdout, "fix: 4 edits in 2 files over 3 rounds"));
    const main = try project.read("main.my");
    defer testing.allocator.free(main);
    try testing.expectEqualStrings(
        \\module main
        \\import util.helpers
        \\
        \\
        \\def main() -> int:
        \\    xs: list[int] = []
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

// spec-case: FIX-MIGRATION-1
test "CLI fix splits receiver overlap into a preceding call without repeating effects" {
    const original = @embedFile("fixtures/fix-migration/receiver-overlap.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_MUTATION_OVERLAP"));
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
        \\module lib
        \\
        \\
        \\public def grow(xs: mut list[int]) -> None:
        \\    xs.append(missing)
        \\
    ;
    const first_test =
        \\module first_test
        \\import lib
        \\
        \\
        \\public def test_one() -> bool:
        \\    xs: list[int] = []
        \\    lib.grow(xs)
        \\    return len(xs) == 1
        \\
    ;
    var project = try Project.init(&.{
        .{ .path = "lib.my", .data = library },
        .{ .path = "first_test.my", .data = first_test },
        .{ .path = "second_test.my", .data = "module second_test\nimport lib\n\n\npublic def test_two() -> bool:\n    xs: list[int] = []\n    lib.grow(mut xs)\n    return True\n" },
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
        .{ .path = "lib.my", .data = "module lib\n\n\npublic def one() -> int:\n    return 1\n" },
        .{ .path = "broken.my", .data = "module broken\n\n\npublic def one() -> int:\n    return missing\n" },
        .{ .path = "plain_test.my", .data = "def test_one() -> bool:\n    return True\n" },
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
    try testing.expect(contains(broken.stderr, "broken.my:5:12: error[E_UNKNOWN_NAME]"));
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
    // Before: the call-site marker rule rejects every file that reaches a call to a `mut` parameter.
    try testing.expectEqual(@as(usize, 7), try rejectedFiles(&project));
    const migrated = try project.run("fix", ".", &.{});
    defer migrated.deinit();
    try testing.expectEqual(@as(u8, 0), migrated.status);
    try testing.expectEqualStrings("", migrated.stderr);
    try testing.expect(contains(migrated.stdout, "fix: 91 edits in 6 files"));
    try testing.expect(contains(migrated.stdout, "fixed heap.my: 34 edits (E_MUTATION_MARKER)"));
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

const abi_append_producer = "module lib\n\npublic def change(items: mut list[int]):\n    items.append(9)\n\npublic def append_only(items: mut list[int]):\n    items.append(3)\n";
const abi_rebind_producer = "module lib\n\npublic def change(items: mut list[int]):\n    items = [7]\n    items.append(8)\n\npublic def append_only(items: mut list[int]):\n    items.append(3)\n";
const abi_consumer =
    \\module main
    \\
    \\import lib
    \\def main() -> int:
    \\    first = [1]
    \\    first_saved = first
    \\    lib.change(mut first)
    \\    action = lib.change
    \\    second = [1]
    \\    second_saved = second
    \\    action(mut second)
    \\    third = [1]
    \\    third_saved = third
    \\    append = lib.append_only
    \\    append(mut third)
    \\    lib.append_only(mut third)
    \\    return 1 if first == second and first != [1] and first_saved == [1] and second_saved == [1] and third == [1, 3, 3] and third_saved == [1] else 0
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

// spec-case: FIX-MIGRATION-1
// spec-case: D2-VIEW-STORAGE-1
test "D2 CLI fix materializes stored dictionary projections with contextual list snapshots" {
    const original = @embedFile("fixtures/fix-migration/dictionary-views.my");
    var project = try Project.init(&.{.{ .path = "main.my", .data = original }});
    defer project.deinit();
    const preview = try project.run("fix", "main.my", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expect(contains(preview.stdout, "E_VIEW_STORED"));
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
