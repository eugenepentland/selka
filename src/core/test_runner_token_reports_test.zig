//! Stage 6 of the test-loop plan (`experiments/test-loop-20261109/DECISIONS.md`, D-TL6-1 and D-TL6-2): an entry's stored
//! report reads its module sources through `module-tokens`, so a comment edit, a line shift or trailing whitespace replays
//! it, byte for byte, and any edit the check reads (a string, a docstring, the indentation, a token) misses it as before.
//! A module a printed diagnostic names is read by its bytes (`test_runner_engine.reportReads`, tested there). `SELKA_TEST_TOKEN_REPORTS=0` reads every source by its
//! bytes, the oracle.
const std = @import("std");
const options = @import("core_test_options");
const v = @import("property_value.zig");

const library =
    \\# The library's comment.
    \\public func value(n: int) -> int:
    \\    """The value of `n`, plus one."""
    \\    return n + 1
    \\
    \\
    \\public func label() -> str:
    \\    return "one"
    \\
    \\
    \\public func other() -> str:
    \\    return "two"
    \\
;
const warned =
    \\# A module the check warns about.
    \\public func noisy() -> int:
    \\    const unused = 5
    \\    return 2
    \\
;
const root =
    \\import lib
    \\import noise
    \\
    \\
    \\public func test_value() -> bool:
    \\    return lib.value(1) == 2 and lib.label() == "one" and noise.noisy() == 2
    \\
;

/// One run's stdout and how many of its tests the stored report served.
const Run = struct { stdout: []const u8, replayed: usize, tests: usize };

/// A temporary project and the runs over it, all in one cache.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn write(self: Project, name: []const u8, data: []const u8) !void {
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", name });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = data });
    }

    fn edit(self: Project, name: []const u8, before: []const u8, needle: []const u8, replacement: []const u8) !void {
        try std.testing.expect(std.mem.indexOf(u8, before, needle) != null);
        try self.write(name, try std.mem.replaceOwned(u8, self.arena, before, needle, replacement));
    }

    /// `selka test app.selka --json`, with the token reads on or (`bytes`) off.
    fn run(self: Project, bytes: bool) !Run {
        var environment = try options.privateEnvironment(self.arena);
        if (bytes) try environment.put("SELKA_TEST_TOKEN_REPORTS", "0");
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", "app.selka" });
        const directory = try std.fs.path.join(self.arena, &.{ self.root, "cache" });
        const argv = [_][]const u8{ options.corePath(), "test", path, "--json", "--cache-dir", directory, "--jobs", "1" };
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        const report = try std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{});
        var found: Run = .{ .stdout = result.stdout, .replayed = 0, .tests = 0 };
        for (v.array(v.get(report, "tests"))) |item| {
            found.tests += 1;
            const cache = v.get(item, "cache");
            if (cache == .object and std.mem.eql(u8, v.text(v.get(cache, "reason")), "engine-report-hit")) found.replayed += 1;
        }
        return found;
    }
};

fn start(a: std.mem.Allocator, directory: *std.testing.TmpDir) !Project {
    const project: Project = .{ .arena = a, .root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try std.fs.path.join(a, &.{ project.root, "project" }));
    try project.write("lib.selka", library);
    try project.write("noise.selka", warned);
    try project.write("app.selka", root);
    try project.write("selka.json", "{\"version\":2}");
    return project;
}

// spec: TEST-LOOP-TOKEN-REPORTS-1
test "a stored report is replayed byte for byte after a comment edit, a line shift and trailing whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const project = try start(a, &directory);
    const cold = try project.run(false);
    try std.testing.expectEqual(@as(usize, 0), cold.replayed);
    const replay = try project.run(false);
    try std.testing.expectEqual(replay.tests, replay.replayed);
    // A comment reworded, a comment line added above everything (every later line moves), trailing whitespace.
    try project.edit("lib.selka", library, "# The library's comment.", "# The library's comment, reworded at length.");
    try std.testing.expectEqualStrings(replay.stdout, (try project.run(false)).stdout);
    try project.edit("lib.selka", library, "# The library's comment.\n", "# The library's comment.\n# One more line.\n\n");
    try std.testing.expectEqualStrings(replay.stdout, (try project.run(false)).stdout);
    try project.edit("lib.selka", library, "return n + 1\n", "return n + 1   \n");
    try std.testing.expectEqualStrings(replay.stdout, (try project.run(false)).stdout);
    // The oracle reads the bytes: the same comment edit is a miss there, and its first run records its own report.
    try project.edit("lib.selka", library, "# The library's comment.", "# Yet another comment.");
    try std.testing.expectEqual(@as(usize, 0), (try project.run(true)).replayed);
    const oracle = try project.run(true);
    try std.testing.expectEqual(oracle.tests, oracle.replayed);
}

/// Apply one edit to the state the last run recorded and expect it to miss the stored report; then let it record its own.
fn expectMiss(project: Project, file: []const u8, before: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    const settled = try project.run(false);
    try std.testing.expectEqual(settled.tests, settled.replayed);
    try project.edit(file, before, needle, replacement);
    try std.testing.expectEqual(@as(usize, 0), (try project.run(false)).replayed);
    return std.mem.replaceOwned(u8, project.arena, before, needle, replacement);
}

// spec-case: TEST-LOOP-TOKEN-REPORTS-1
test "an edit the check reads misses the stored report: a string, a docstring, the indentation, a token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const project = try start(a, &directory);
    _ = try project.run(false);
    const string = try expectMiss(project, "lib.selka", library, "\"two\"", "\"three\"");
    const docstring = try expectMiss(project, "lib.selka", string, "plus one.", "plus one, always.");
    const indented = try expectMiss(project, "lib.selka", docstring, "    return \"one\"", "        return \"one\"");
    _ = try expectMiss(project, "lib.selka", indented, "n + 1", "1 + n");
}

const documented =
    \\# A module with a docstring example.
    \\public func double(n: int) -> int:
    \\    """Twice `n`.
    \\
    \\    >>> double(2)
    \\    4
    \\    """
    \\    return n * 2
    \\
    \\
    \\public func test_double() -> bool:
    \\    return double(3) == 6
    \\
;

// spec-case: TEST-LOOP-TOKEN-REPORTS-1
test "a module with a docstring example is read by its bytes: a line shift there misses the stored report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const project = try start(a, &directory);
    try project.write("app.selka", documented);
    _ = try project.run(false);
    const replay = try project.run(false);
    try std.testing.expectEqual(replay.tests, replay.replayed);
    try std.testing.expect(replay.tests >= 2);
    // An example's key holds the docstring lines its program maps back to, so a comment line above it moves the key.
    try project.edit("app.selka", documented, "# A module with a docstring example.\n", "# A module with a docstring example.\n# One more line.\n");
    try std.testing.expectEqual(@as(usize, 0), (try project.run(false)).replayed);
}
