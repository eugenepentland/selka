//! The S5-B2 command-line flags through the built compiler: `test --affected --against`,
//! `--no-cache`, `--report` and `--timings` (NEW-CORE-S5-AFFECTED-1, -NO-CACHE-1,
//! -REPORT-1, -TIMINGS-1), and the flags retired instead of ported.
const std = @import("std");
const tools = @import("core_test_options");

const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8 };

/// A temporary project directory and the commands run in it.
const Context = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn write(self: Context, name: []const u8, bytes: []const u8) !void {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try self.path(name), .data = bytes });
    }

    fn path(self: Context, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, name });
    }

    /// Run the compiler with `args`, in the project directory.
    fn compiler(self: Context, args: []const []const u8) !Outcome {
        // The build names the compiler relative to the test's own working directory.
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.core_path, self.arena);
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{executable}, args });
        return self.spawn(argv);
    }

    /// Run `git` in the project directory and require it to succeed.
    fn git(self: Context, args: []const []const u8) !void {
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{ "git", "-c", "user.email=test@example.com", "-c", "user.name=test" }, args });
        const result = try self.spawn(argv);
        try std.testing.expectEqual(@as(u8, 0), result.status);
    }

    fn spawn(self: Context, argv: []const []const u8) !Outcome {
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = argv, .cwd = .{ .path = self.root } });
        const status: u8 = switch (result.term) {
            .exited => |code| code,
            else => 255,
        };
        return .{ .status = status, .stdout = result.stdout, .stderr = result.stderr };
    }

    /// How many entries the directory `name` holds.
    fn entries(self: Context, name: []const u8) !usize {
        var directory = try std.Io.Dir.cwd().openDir(std.testing.io, try self.path(name), .{ .iterate = true });
        defer directory.close(std.testing.io);
        var iterator = directory.iterate();
        var count: usize = 0;
        while (try iterator.next(std.testing.io)) |_| count += 1;
        return count;
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

const affected_before =
    \\
    \\
    \\const LIMIT: int = 3
    \\
    \\
    \\func helper(value: int) -> int:
    \\    return value + 1
    \\
    \\
    \\func test_helper() -> bool effects():
    \\    return helper(1) == 2
    \\
    \\
    \\func test_unrelated() -> bool effects():
    \\    return LIMIT == 3
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

// spec: NEW-CORE-S5-AFFECTED-1
test "test --affected runs only the tests that reach a declaration changed since a git revision" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("app.my", affected_before);
    try context.git(&.{ "init", "-q" });
    try context.git(&.{ "add", "app.my" });
    try context.git(&.{ "commit", "-q", "-m", "init" });
    const affected = [_][]const u8{ "test", "app.my", "--affected", "--against=HEAD", "--cache-dir", "cache" };
    // An untracked module changes on every line, but this program does not load it.
    try context.write("other.my", "\n\nconst OTHER: int = 1\n\n\nfunc test_other() -> bool:\n    return OTHER == 1\n");
    // An unchanged program selects nothing and exits 3, as a filter matching nothing does.
    const unchanged = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 3), unchanged.status);
    try std.testing.expect(contains(unchanged.stderr, "affected: 0 selected, 2 skipped against HEAD"));
    try std.testing.expect(contains(unchanged.stderr, "skipped app::test_helper: no changed declaration is reachable"));
    // A body edit selects only the test that reaches it, and a selected test reruns.
    try context.write("app.my", try std.mem.replaceOwned(u8, context.arena, affected_before, "value + 1", "value + 2"));
    const edited = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 1), edited.status);
    try std.testing.expect(contains(edited.stderr, "affected: 1 selected, 1 skipped against HEAD"));
    try std.testing.expect(contains(edited.stderr, "skipped app::test_unrelated"));
    try std.testing.expect(contains(edited.stdout, "failed app::test_helper"));
    try std.testing.expect(!contains(edited.stdout, "test_unrelated"));
    // A filter applies first.
    const filtered = try context.compiler(&.{ "test", "app.my", "--affected", "--against", "HEAD", "--filter", "unrelated", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 3), filtered.status);
    try std.testing.expect(contains(filtered.stderr, "affected: 0 selected, 1 skipped against HEAD"));
    // A changed constant is folded into its readers, so it selects every test.
    try context.write("app.my", try std.mem.replaceOwned(u8, context.arena, affected_before, "LIMIT: int = 3", "LIMIT: int = 4"));
    const constant = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 1), constant.status);
    try std.testing.expect(contains(constant.stderr, "affected: 2 selected, 0 skipped against HEAD"));
    // The switches only mean something together; a bad revision is a host failure.
    try std.testing.expectEqual(@as(u8, 2), (try context.compiler(&.{ "test", "app.my", "--against=HEAD" })).status);
    try std.testing.expectEqual(@as(u8, 2), (try context.compiler(&.{ "test", "app.my", "--affected" })).status);
    const unresolvable = try context.compiler(&.{ "test", "app.my", "--affected", "--against=no-such-revision", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 2), unresolvable.status);
    try std.testing.expect(contains(unresolvable.stderr, "git cannot resolve"));
}

const answer = "func main() -> int:\n    return 42\n";

// spec: NEW-CORE-S5-NO-CACHE-1
test "no-cache builds runs and tests through a private cache it removes and publishes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", answer);
    try context.write("check.my", "func test_answer() -> bool:\n    return 6 * 7 == 42\n");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("cache"));
    const cached = try context.compiler(&.{ "run", "main.my", "--print-result", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), cached.status);
    try std.testing.expect(try context.entries("cache") != 0);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("empty"));
    // An uncached run links its program afresh and leaves nothing behind.
    const uncached = try context.compiler(&.{ "run", "main.my", "--print-result", "--cache-dir", "empty", "--no-cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), uncached.status);
    try std.testing.expectEqualStrings("42\n", uncached.stdout);
    try std.testing.expect(contains(uncached.stderr, "\"program\":\"linked\""));
    try std.testing.expectEqual(@as(usize, 0), try context.entries("empty"));
    const again = try context.compiler(&.{ "run", "main.my", "--cache-dir", "cache", "--no-cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), again.status);
    try std.testing.expect(!contains(again.stderr, "replayed"));
    const tested = try context.compiler(&.{ "test", "check.my", "--cache-dir", "empty", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), tested.status);
    try std.testing.expect(contains(tested.stdout, "passed check::test_answer"));
    try std.testing.expectEqual(@as(usize, 0), try context.entries("empty"));
}

// spec: NEW-CORE-S5-REPORT-1
test "report prints the cache report as one JSON line and says when a build replayed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", answer);
    const first = try context.compiler(&.{ "run", "main.my", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), first.status);
    const line = std.mem.trimEnd(u8, first.stderr, "\n");
    const record = try std.json.parseFromSliceLeaky(std.json.Value, context.arena, line, .{});
    try std.testing.expectEqualStrings("cache-report-v1", record.object.get("version").?.string);
    try std.testing.expectEqualStrings("linked", record.object.get("program").?.string);
    try std.testing.expect(record.object.get("units").?.integer > 0);
    try std.testing.expect(record.object.get("processes").?.integer > 0);
    const second = try context.compiler(&.{ "run", "main.my", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), second.status);
    try std.testing.expect(contains(second.stderr, "{\"version\":\"cache-report-v1\",\"program\":\"replayed\",\"units\":0,"));
    const text = try context.compiler(&.{ "run", "main.my", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expectEqualStrings("mylang-core: cache: replayed the last identical build\n", text.stderr);
    const quiet = try context.compiler(&.{ "run", "main.my", "--cache-dir", "cache" });
    try std.testing.expectEqualStrings("", quiet.stderr);
}

// spec: NEW-CORE-S5-TIMINGS-1
test "timings print the program's run time without changing its status, output or trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", answer);
    try context.write("trap.my", "func main() -> int:\n    return divtrunc(1, 0)\n");
    const timed = try context.compiler(&.{ "run", "main.my", "--print-result", "--cache-dir", "cache", "--timings" });
    try std.testing.expectEqual(@as(u8, 42), timed.status);
    try std.testing.expectEqualStrings("42\n", timed.stdout);
    const prefix = "timings: native_ns=";
    try std.testing.expect(std.mem.startsWith(u8, timed.stderr, prefix));
    _ = try std.fmt.parseInt(u64, std.mem.trimEnd(u8, timed.stderr[prefix.len..], "\n"), 10);
    const trapped = try context.compiler(&.{ "run", "trap.my", "--cache-dir", "cache", "--timings" });
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "error[R_DIVISION_BY_ZERO]"));
    try std.testing.expect(contains(trapped.stderr, prefix));
    const twice = try context.compiler(&.{ "run", "main.my", "--timings", "--timings" });
    try std.testing.expectEqual(@as(u8, 2), twice.status);
    try std.testing.expect(contains(twice.stderr, "usage: mylang run"));
    const profile = try context.compiler(&.{ "run", "main.my", "--timings=json" });
    try std.testing.expectEqual(@as(u8, 2), profile.status);
    try std.testing.expect(contains(profile.stderr, "retired"));
}

// spec-case: NEW-CORE-S5-RETIRED-1
test "explain-invalidation and friction-log are refused on run as retired" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", answer);
    const explained = try context.compiler(&.{ "run", "main.my", "--explain-invalidation" });
    try std.testing.expectEqual(@as(u8, 2), explained.status);
    try std.testing.expect(contains(explained.stderr, "--report"));
    const logged = try context.compiler(&.{ "run", "main.my", "--friction-log=log.jsonl" });
    try std.testing.expectEqual(@as(u8, 2), logged.status);
    try std.testing.expect(contains(logged.stderr, "mylang check"));
}

// spec: NEW-CORE-S5-TEST-USAGE-1
test "test names a bad flag value or unknown option before printing its own usage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", answer);
    const zero_jobs = try context.compiler(&.{ "test", "main.my", "--jobs", "0" });
    try std.testing.expectEqual(@as(u8, 2), zero_jobs.status);
    try std.testing.expect(contains(zero_jobs.stderr, "mylang test: invalid value '0' for --jobs\nusage: mylang test <entry.my|directory>"));
    try std.testing.expect(contains(zero_jobs.stderr, "--property-runs N"));
    const joined = try context.compiler(&.{ "test", "main.my", "--jobs=x" });
    try std.testing.expectEqual(@as(u8, 2), joined.status);
    try std.testing.expect(contains(joined.stderr, "invalid value 'x' for --jobs"));
    const runs = try context.compiler(&.{ "test", "main.my", "--property-runs", "0" });
    try std.testing.expectEqual(@as(u8, 2), runs.status);
    try std.testing.expect(contains(runs.stderr, "invalid value '0' for --property-runs"));
    const unknown = try context.compiler(&.{ "test", "main.my", "--bogus" });
    try std.testing.expectEqual(@as(u8, 2), unknown.status);
    try std.testing.expect(contains(unknown.stderr, "unknown option '--bogus'"));
    const missing = try context.compiler(&.{ "test", "main.my", "--filter" });
    try std.testing.expectEqual(@as(u8, 2), missing.status);
    try std.testing.expect(contains(missing.stderr, "missing value for '--filter'"));
    try std.testing.expect(!contains(missing.stderr, "mylang-core"));
}

const debug_line = "func main(out: Stream) -> int:\n    debug(\"debugging\", 41)\n    out.print(42)\n    return 0\n";

// spec-case: DEBUG-OPTIMIZE-1
test "optimize-debug separates cached builds and test receipts and keeps debug output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", debug_line);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("suite"));
    try context.write("suite/check.my", "func test_answer() -> bool:\n    return 6 * 7 == 42\n");
    for ([_][]const []const u8{ &.{}, &.{"--optimize-debug"}, &.{"--release"} }) |mode| {
        const build_args = try std.mem.concat(context.arena, []const u8, &.{ &.{ "build", "main.my", "-o", "program", "--cache-dir", "cache", "--report" }, mode });
        const first = try context.compiler(build_args);
        try std.testing.expectEqual(@as(u8, 0), first.status);
        try std.testing.expect(contains(first.stderr, "\"program\":\"linked\""));
        const again = try context.compiler(build_args);
        try std.testing.expectEqual(@as(u8, 0), again.status);
        try std.testing.expect(contains(again.stderr, "\"program\":\"replayed\""));
        const ran = try context.spawn(&.{try context.path("program")});
        try std.testing.expectEqualStrings("42\n", ran.stdout);
        const release = mode.len != 0 and std.mem.eql(u8, mode[0], "--release");
        try std.testing.expectEqualStrings(if (release) "" else "debugging 41\n", ran.stderr);
        const test_args = try std.mem.concat(context.arena, []const u8, &.{ &.{ "test", "suite", "--cache-dir", "cache" }, mode });
        const tested = try context.compiler(test_args);
        try std.testing.expectEqual(@as(u8, 0), tested.status);
        try std.testing.expect(contains(tested.stdout, "1 passed, 0 cached"));
        const cached = try context.compiler(test_args);
        try std.testing.expectEqual(@as(u8, 0), cached.status);
        try std.testing.expect(contains(cached.stdout, "0 passed, 1 cached"));
    }
}

// spec-case: DEBUG-OPTIMIZE-1
test "optimize-debug run commands retain debug output and test rejects conflicting modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", debug_line);
    for ([_][]const u8{ "run", "run-project" }) |command| {
        const ran = try context.compiler(&.{ command, "main.my", "--optimize-debug", "--verify-facts" });
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("42\n", ran.stdout);
        try std.testing.expect(contains(ran.stderr, "debugging 41\n"));
    }
    const through = try context.compiler(&.{ "build", "main.my", "--run", "--optimize-debug" });
    try std.testing.expectEqual(@as(u8, 0), through.status);
    try std.testing.expectEqualStrings("42\n", through.stdout);
    try std.testing.expect(contains(through.stderr, "debugging 41\n"));
    const conflict = try context.compiler(&.{ "test", "check.my", "--release", "--optimize-debug" });
    try std.testing.expectEqual(@as(u8, 2), conflict.status);
    try std.testing.expect(contains(conflict.stderr, "mutually exclusive"));
}

// spec: NEW-CORE-S5-DEBUG-RELEASE-1
test "a build --release executable drops debug lines, a debug build and a run keep them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.my", debug_line);
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "main.my", "-o", "released", "--release" })).status);
    const released = try context.spawn(&.{try context.path("released")});
    try std.testing.expectEqualStrings("42\n", released.stdout);
    try std.testing.expectEqualStrings("", released.stderr);
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "main.my", "-o", "debugged" })).status);
    const debugged = try context.spawn(&.{try context.path("debugged")});
    try std.testing.expectEqualStrings("42\n", debugged.stdout);
    try std.testing.expectEqualStrings("debugging 41\n", debugged.stderr);
    const ran = try context.compiler(&.{ "run", "main.my", "--release" });
    try std.testing.expectEqualStrings("42\n", ran.stdout);
    try std.testing.expect(contains(ran.stderr, "debugging 41\n"));
}
