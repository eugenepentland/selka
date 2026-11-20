//! `selka fix`, `check` on library and test entries, and `test --diagnostics=json`,
//! driven through the compiler binary exactly as a user or an agent runs them.
const std = @import("std");
const testing = std.testing;

// spec: REPETITION-ORIGIN-1
test "wave1 repetition shares helper edits across independent roots" {
    const shared =
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings
        \\
        \\public func repeated(n: int) -> int[]:
        \\    return [1, 2] * n
        \\
        \\public func text_size(n: int) -> int:
        \\    match strings.repeat("ab", n):
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(_):
        \\            return 0
        \\
    ;
    const files = [_]File{
        .{ .path = "shared.selka", .data = shared },
        .{ .path = "padding.selka", .data = "public func number() -> int:\n    return 2\n" },
        .{ .path = "first.selka", .data = "import padding\nimport shared\nfunc main() -> int:\n    return len(shared.repeated(padding.number()))\n" },
        .{ .path = "second.selka", .data = "import shared\nfunc main() -> int:\n    return len(shared.repeated(2))\n" },
    };
    const first_edit = try fixedSharedModule(&files, "first.selka");
    defer testing.allocator.free(first_edit);
    const second_edit = try fixedSharedModule(&files, "second.selka");
    defer testing.allocator.free(second_edit);
    try testing.expectEqualStrings(first_edit, second_edit);
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
    try testing.expectEqual(@as(u8, 0), fixed.status);
    const first = try project.run("check", "first.selka", &.{});
    defer first.deinit();
    try testing.expectEqual(@as(u8, 0), first.status);
    const second = try project.run("check", "second.selka", &.{});
    defer second.deinit();
    try testing.expectEqual(@as(u8, 0), second.status);
    const again = try project.run("fix", ".", &.{"--check"});
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

fn fixedSharedModule(files: []const File, entry: []const u8) ![]const u8 {
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

fn migration(original: []const u8, expected: []const u8) !void {
    try migrationWith(original, expected, false);
}

/// `migration` for a source whose repairs include a warning's (the match flattened into `else Err(_)`): a file run applies those
/// only with `--warnings`.
fn migrationWarnings(original: []const u8, expected: []const u8) !void {
    try migrationWith(original, expected, true);
}

fn migrationWith(original: []const u8, expected: []const u8, warnings: bool) !void {
    var project = try Project.init(&.{.{ .path = "main.selka", .data = original }});
    defer project.deinit();
    const apply: []const []const u8 = if (warnings) &.{"--warnings"} else &.{};
    const list: []const []const u8 = if (warnings) &.{ "--check", "--warnings" } else &.{"--check"};
    const preview = try project.run("fix", "main.selka", list);
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    const unchanged = try project.read("main.selka");
    defer testing.allocator.free(unchanged);
    try testing.expectEqualStrings(original, unchanged);
    const fixed = try project.run("fix", "main.selka", apply);
    defer fixed.deinit();
    testing.expectEqual(@as(u8, 0), fixed.status) catch |failure| {
        std.debug.print("fix stdout: {s}\nfix stderr: {s}\n", .{ fixed.stdout, fixed.stderr });
        return failure;
    };
    // A retired module header can precede recognition of repetition.
    try testing.expect(contains(fixed.stdout, "E_REPETITION_REMOVED"));
    const migrated = try project.read("main.selka");
    defer testing.allocator.free(migrated);
    try testing.expectEqualStrings(expected, migrated);
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 0), checked.status);
    const again = try project.run("fix", "main.selka", list);
    defer again.deinit();
    try testing.expectEqual(@as(u8, 0), again.status);
}

// spec: REPETITION-1
test "wave1 repetition migrates text" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const value = "ab" * 3
        \\    return len(value)
        \\
    ,
        \\import strings
        \\func main() -> int:
        \\    const value = strings.repeat("ab", 3)
        \\    return len(value)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates list" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const values = [7] * (0 - 1)
        \\    return len(values)
        \\
    ,
        \\import lists
        \\func main() -> int:
        \\    const values = lists.filled((0 - 1), 7)
        \\    return len(values)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates bytes" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut data = b"ab"
        \\    data *= 3
        \\    return len(data)
        \\
    ,
        \\import byte_builder
        \\func main() -> int:
        \\    mut data = b"ab"
        \\    data = byte_builder.repeat(data, 3)
        \\    return len(data)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates old Result argument" {
    try migrationWarnings(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings
        \\
        \\func text(result: Result[str, strings.Error]) -> int:
        \\    match result:
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(_):
        \\            return 0
        \\
        \\func main() -> int:
        \\    return text(strings.repeat("ab", 3))
        \\
    ,
        \\import strings
        \\
        \\func text(result: Result[str, strings.Error]) -> int:
        \\    const value = result else Err(_):
        \\        return 0
        \\    return len(value)
        \\
        \\func main() -> int:
        \\    return text(Ok(strings.repeat("ab", 3)))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates old try" {
    try migrationWarnings(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings
        \\
        \\func text() -> Result[str, strings.Error]:
        \\    const value = try strings.repeat("ab", 3)
        \\    return Ok(value)
        \\
        \\func main() -> int:
        \\    match text():
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(_):
        \\            return 0
        \\
    ,
        \\import strings
        \\
        \\func text() -> str fails strings.Error:
        \\    const value = strings.repeat("ab", 3)
        \\    return value
        \\
        \\func main() -> int:
        \\    const value = text() else Err(_):
        \\        return 0
        \\    return len(value)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates old match with alias" {
    try migrationWarnings(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings as text
        \\
        \\func main() -> int:
        \\    match text.repeat("ab", 3):
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(_):
        \\            return 0
        \\
    ,
        \\import strings as text
        \\
        \\func main() -> int:
        \\    const repeated_result_48: Result[str, text.Error] = Ok(text.repeat("ab", 3))
        \\    const value = repeated_result_48 else Err(_):
        \\        return 0
        \\    return len(value)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition reuses module alias" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\import strings as text
        \\
        \\func main() -> int:
        \\    return len("a" * 2)
        \\
    ,
        \\import strings as text
        \\
        \\func main() -> int:
        \\    return len(text.repeat("a", 2))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition import follows retired module header" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\module main
        \\
        \\func main() -> int:
        \\    return len("a" * 2)
        \\
    ,
        \\import strings
        \\
        \\
        \\func main() -> int:
        \\    return len(strings.repeat("a", 2))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition import avoids top level function name" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func strings() -> int:
        \\    return 1
        \\
        \\func main() -> int:
        \\    return strings() + len("a" * 2)
        \\
    ,
        \\import strings as strings_wave1_0
        \\public func strings() -> int:
        \\    return 1
        \\
        \\func main() -> int:
        \\    return strings() + len(strings_wave1_0.repeat("a", 2))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates string assignment" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut text = "ab"
        \\    text *= 3
        \\    return len(text)
        \\
    ,
        \\import strings
        \\func main() -> int:
        \\    mut text = "ab"
        \\    text = strings.repeat(text, 3)
        \\    return len(text)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates list assignment with loops" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    values *= 3
        \\    return len(values)
        \\
    ,
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    const repeated_source_48 = copy(values)
        \\    mut repeated_count_48 = int(3)
        \\    if len(repeated_source_48) == 0:
        \\        repeated_count_48 = 0
        \\    values = []
        \\    for _ in range(repeated_count_48):
        \\        for repeated_element_48 in repeated_source_48:
        \\            append(mut values, copy(repeated_element_48))
        \\    return len(values)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates generic singleton without concrete type names" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func copies[T: copy + storable](value: T, count: int) -> T[]:
        \\    return [value] * count
        \\
        \\func main() -> int:
        \\    return len(copies(7, 3))
        \\
    ,
        \\import lists
        \\public func copies[T: copy + storable](value: T, count: int) -> T[]:
        \\    return lists.filled(count, value)
        \\
        \\func main() -> int:
        \\    return len(copies(7, 3))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition migrates generic list assignment" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\public func grow[T: copy + storable](mut values: T[], count: int):
        \\    values *= count
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    grow(mut values, 3)
        \\    return len(values)
        \\
    ,
        \\public func grow[T: copy + storable](mut values: T[], count: int):
        \\    const repeated_source_71 = copy(values)
        \\    mut repeated_count_71 = int(count)
        \\    if len(repeated_source_71) == 0:
        \\        repeated_count_71 = 0
        \\    values = []
        \\    for _ in range(repeated_count_71):
        \\        for repeated_element_71 in repeated_source_71:
        \\            append(mut values, copy(repeated_element_71))
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    grow(mut values, 3)
        \\    return len(values)
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition withholds arbitrary generic list expression" {
    var project = try Project.init(&.{.{
        .path = "main.selka",
        .data =
        // migrate-embedded: skip intentional removed-syntax diagnostic source
        \\public func copies[T: copy + storable, N: integer](values: T[], count: N) -> T[]:
        \\    return values * count
        \\
        \\func main() -> int:
        \\    return len(copies([1, 2], 3))
        \\
    }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "E_REPETITION_REMOVED"));
    const preview = try project.run("fix", "main.selka", &.{"--check"});
    defer preview.deinit();
    try testing.expectEqual(@as(u8, 1), preview.status);
    try testing.expectEqualStrings("fix: nothing to fix\n", preview.stdout);
}

fn migrationValue(original: []const u8, expected: []const u8, value: u8) !void {
    try migration(original, expected);
    var project = try Project.init(&.{.{ .path = "main.selka", .data = expected }});
    defer project.deinit();
    const executed = try project.run("run", "main.selka", &.{});
    defer executed.deinit();
    try testing.expectEqual(value, executed.status);
}

// spec-case: REPETITION-1
test "wave1 repetition migrates multi element list expression without hoisting" {
    try migrationValue(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const values = 2 * [1, 2]
        \\    return len(values)
        \\
    ,
        \\func main() -> int:
        \\    const values = repeat_sequence_39(2, [1, 2])
        \\    return len(values)
        \\
        \\
        \\func repeat_sequence_39[RepeatType_39: copy + storable](repeat_times_39: int, repeat_source_39: RepeatType_39[]) -> RepeatType_39[]:
        \\    mut repeat_output_39: RepeatType_39[] = []
        \\    if len(repeat_source_39) == 0:
        \\        return repeat_output_39
        \\    for _ in range(repeat_times_39):
        \\        for repeat_element_39 in repeat_source_39:
        \\            append(mut repeat_output_39, copy(repeat_element_39))
        \\    return repeat_output_39
        \\
    , 4);
}

// spec-case: REPETITION-1
test "wave1 repetition preserves two effectful operand calls in count first order" {
    try migrationValue(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func count(mut log: int[]) -> int:
        \\    log.append(1)
        \\    return 2
        \\
        \\func text(mut log: int[]) -> str:
        \\    log.append(2)
        \\    return "ab"
        \\
        \\func main() -> int:
        \\    mut log: int[] = []
        \\    const result = count(mut log) * text(mut log)
        \\    if result == "abab" and log == [1, 2]:
        \\        return 42
        \\    return 0
        \\
    ,
        \\import strings
        \\func count(mut log: int[]) -> int:
        \\    append(mut log, 1)
        \\    return 2
        \\
        \\func text(mut log: int[]) -> str:
        \\    append(mut log, 2)
        \\    return "ab"
        \\
        \\func main() -> int:
        \\    mut log: int[] = []
        \\    const result = repeat_sequence_199(count(mut log), text(mut log))
        \\    if result == "abab" and log == [1, 2]:
        \\        return 42
        \\    return 0
        \\
        \\
        \\func repeat_sequence_199(repeat_times_199: int, repeat_source_199: str) -> str:
        \\    return strings.repeat(repeat_source_199, repeat_times_199)
        \\
    , 42);
}

// spec-case: REPETITION-1
test "wave1 repetition widens narrow counts exactly" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func main() -> int:
        \\    const count: u8 = 3
        \\    return len("ab" * count)
        \\
    ,
        \\import strings
        \\func main() -> int:
        \\    const count: u8 = 3
        \\    return len(strings.repeat("ab", int(count)))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition ignores import text inside docstrings" {
    try migration(
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\"""Library documentation.
        \\import strings as wrong
        \\module phantom
        \\"""
        \\
        \\func main() -> int:
        \\    return len("a" * 2)
        \\
    ,
        \\import strings as strings_wave1_0
        \\"""Library documentation.
        \\import strings as wrong
        \\module phantom
        \\"""
        \\
        \\func main() -> int:
        \\    return len(strings_wave1_0.repeat("a", 2))
        \\
    );
}

// spec-case: REPETITION-1
test "wave1 repetition preserves unsigned maximum empty sequences and argument order" {
    try migrationValue(@embedFile("fixtures/fix-migration/wave1_unsigned_repetition/before.selka"), @embedFile("fixtures/fix-migration/wave1_unsigned_repetition/after.selka"), 42);
}

// spec-case: REPETITION-1
test "wave1 repetition and membership preserve locals behind import aliases" {
    try migrationValue(@embedFile("fixtures/fix-migration/wave1_import_collision/before.selka"), @embedFile("fixtures/fix-migration/wave1_import_collision/after.selka"), 42);
}

// spec-case: REPETITION-1
test "wave1 imported alias still rejects a shadowing local" {
    var project = try Project.init(&.{.{ .path = "main.selka", .data =
        \\import lists as sequence
        \\func main() -> int:
        \\    const sequence = 3
        \\    return sequence
        \\
    }});
    defer project.deinit();
    const checked = try project.run("check", "main.selka", &.{});
    defer checked.deinit();
    try testing.expectEqual(@as(u8, 1), checked.status);
    try testing.expect(contains(checked.stderr, "E_SHADOWING"));
}
