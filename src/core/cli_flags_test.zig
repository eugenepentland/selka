//! The S5-B2 command-line flags through the built compiler: `test --affected --against`,
//! `--no-cache`, `--report` and `--timings` (NEW-CORE-S5-AFFECTED-1, -NO-CACHE-1,
//! -REPORT-1, -TIMINGS-1), and the flags retired instead of ported.
const std = @import("std");
const tools = @import("core_test_options");
const support = @import("test_support.zig");

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
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.corePath(), self.arena);
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{executable}, args });
        return self.spawn(argv);
    }

    /// Run `git` in the project directory and require it to succeed.
    fn git(self: Context, args: []const []const u8) !void {
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{ "git", "-c", "user.email=test@example.com", "-c", "user.name=test" }, args });
        const result = try self.spawn(argv);
        try std.testing.expectEqual(@as(u8, 0), result.status);
    }

    // The flag tests count this project's own replays and receipts: no shared store.
    fn spawn(self: Context, argv: []const []const u8) !Outcome {
        var environment = try tools.privateEnvironment(self.arena);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = argv, .cwd = .{ .path = self.root }, .environ_map = &environment });
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

test "C5 trim demand default native builds preserve cold warm and dirty behavior" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const before =
        \\import bytes
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    assert strings.lstrip_chars("000120", "0") == "120"
        \\    assert bytes.rstrip_chars(b"abc000", b"0") == b"abc"
        \\    print(out, strings.lstrip_chars("000120", "0"))
        \\    return 0
    ;
    const after = try std.mem.replaceOwned(u8, context.arena, before, "120", "240");
    for ([_]struct { text: []const u8, stdout: []const u8 }{
        .{ .text = before, .stdout = "120\n" },
        .{ .text = before, .stdout = "120\n" },
        .{ .text = after, .stdout = "240\n" },
        .{ .text = after, .stdout = "240\n" },
        .{ .text = before, .stdout = "120\n" },
    }) |round| {
        try context.write("main.selka", round.text);
        const built = try context.compiler(&.{ "build", "main.selka", "-o", "program", "--cache-dir", "cache" });
        try std.testing.expectEqual(@as(u8, 0), built.status);
        try std.testing.expectEqualStrings("", built.stdout);
        try std.testing.expectEqualStrings("", built.stderr);
        const executed = try context.spawn(&.{try context.path("program")});
        try std.testing.expectEqual(@as(u8, 0), executed.status);
        try std.testing.expectEqualStrings(round.stdout, executed.stdout);
        try std.testing.expectEqualStrings("", executed.stderr);
    }
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shared test cache flag rejects missing empty and repeated values and stays test specific" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const invalid = [_][]const []const u8{
        &.{ "test", "missing.selka", "--shared-cache-dir" },
        &.{ "test", "missing.selka", "--shared-cache-dir", "" },
        &.{ "test", "missing.selka", "--shared-cache-dir=" },
        &.{ "test", "missing.selka", "--shared-cache-dir", "--force" },
        &.{ "test", "missing.selka", "--shared-cache-dir", "one", "--shared-cache-dir=two" },
    };
    for (invalid) |arguments| {
        const result = try context.compiler(arguments);
        try std.testing.expectEqual(@as(u8, 2), result.status);
        try std.testing.expect(contains(result.stderr, "usage: selka test"));
        try std.testing.expect(contains(result.stderr, "--shared-cache-dir"));
    }
    const build = try context.compiler(&.{ "build", "missing.selka", "-o", "out", "--shared-cache-dir", "one" });
    try std.testing.expectEqual(@as(u8, 2), build.status);
    try std.testing.expect(contains(build.stderr, "usage: selka build"));
}

// spec: CLI-LOCAL-STDLIB-1
test "local standard sources are preferred only with --local-stdlib" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", "import csv\n\nfunc main() -> int:\n    return csv.marker()\n");
    try context.write("csv.selka", "public func marker() -> int:\n    return 42\n");
    try context.write("local_test.selka", "import csv\n\npublic func test_marker() -> bool:\n    return csv.marker() == 42\n");
    const local = try context.compiler(&.{ "run", "main.selka", "--local-stdlib", "--print-result", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 42), local.status);
    try std.testing.expect(contains(local.stdout, "42"));
    const embedded = try context.compiler(&.{ "run", "main.selka", "--print-result", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 1), embedded.status);
    try std.testing.expect(contains(embedded.stderr, "E_UNKNOWN_SYMBOL"));
    try std.testing.expect(contains(embedded.stderr, "local standard module"));
    const checked = try context.compiler(&.{ "check", "main.selka", "--local-stdlib", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), checked.status);
    const library = try context.compiler(&.{ "check", "csv.selka", "--local-stdlib", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), library.status);
    const tested = try context.compiler(&.{ "test", "local_test.selka", "--local-stdlib", "--filter=test_marker", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), tested.status);
    try std.testing.expect(contains(tested.stdout, "1 passed"));
    // Receipts bind the replacement mode: a passing local run cannot replay when
    // the same entry resolves the embedded module instead.
    const cached_local = try context.compiler(&.{ "test", "local_test.selka", "--local-stdlib", "--filter=test_marker", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 0), cached_local.status);
    try std.testing.expect(contains(cached_local.stdout, "1 passed"));
    const cached_embedded = try context.compiler(&.{ "test", "local_test.selka", "--filter=test_marker", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 1), cached_embedded.status);
    try std.testing.expect(contains(cached_embedded.stderr, "E_UNKNOWN_SYMBOL"));
    try std.testing.expect(!contains(cached_embedded.stdout, "cached"));
    // A standard-named file named as the check entry is checked from its path,
    // not from the embedded module it shadows.
    try context.write("csv.selka", "public func marker() -> int:\n    return \"not an int\"\n");
    const bare = try context.compiler(&.{ "check", "csv.selka", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 1), bare.status);
    try std.testing.expect(contains(bare.stderr, "E_TYPE"));
    try std.testing.expect(contains(bare.stderr, "csv.selka:2:5"));
    try std.testing.expect(!contains(bare.stderr, "@stdlib/csv.selka"));
}

// spec: MSG-B-3
test "a local file that a standard module hides is named by check, build, run and test, and in the refusal of a name the module lacks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    const warning = "selka: local standard module 'strings.selka' is ignored; pass --local-stdlib to prefer it";
    try context.write("main.selka", "import strings\n\nfunc main() -> int:\n    return len(strings.upper(\"ab\"))\n");
    try context.write("strings.selka", "public func shadow() -> int:\n    return 1\n");
    try context.write("shadow_test.selka", "import strings\n\npublic func test_upper() -> bool:\n    return strings.upper(\"a\") == \"A\"\n");
    const checked = try context.compiler(&.{ "check", "main.selka", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), checked.status);
    try std.testing.expect(contains(checked.stderr, warning));
    const built = try context.compiler(&.{ "build", "main.selka", "-o", "prog", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), built.status);
    try std.testing.expect(contains(built.stderr, warning));
    const ran = try context.compiler(&.{ "run", "main.selka", "--print-result", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 2), ran.status);
    try std.testing.expect(contains(ran.stderr, warning));
    const tested = try context.compiler(&.{ "test", "shadow_test.selka", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), tested.status);
    try std.testing.expect(contains(tested.stderr, warning));
    // With the switch the file is the module, and nothing is ignored.
    const local = try context.compiler(&.{ "check", "main.selka", "--local-stdlib", "--no-cache" });
    try std.testing.expect(!contains(local.stderr, "is ignored"));
    // A name only the local file declares: the refusal says whose `strings` it is, in every command that reads the project.
    try context.write("use.selka", "import strings\n\nfunc main() -> int:\n    return strings.shadow()\n");
    const refusal = "module `strings` declares no `shadow`; `strings` here is the standard module, so your `strings.selka` is not used: rename it";
    for ([_][]const []const u8{ &.{ "check", "use.selka", "--no-cache" }, &.{ "run", "use.selka", "--no-cache" }, &.{ "build", "use.selka", "-o", "prog", "--no-cache" } }) |arguments| {
        const refused = try context.compiler(arguments);
        try std.testing.expectEqual(@as(u8, 1), refused.status);
        try std.testing.expect(contains(refused.stderr, refusal));
    }
}

// spec: CHECK-LIBRARY-3
test "checkLibraryModule checks a mainless imported entry as a library" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("helper.selka", "public func value() -> int:\n    return 7\n");
    try context.write("test_lib.selka", "import helper\n\npublic func test_value() -> bool:\n    return helper.value() == 7\n");
    const plain = try context.compiler(&.{ "check", "test_lib.selka", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), plain.status);
    const local = try context.compiler(&.{ "check", "test_lib.selka", "--local-stdlib", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), local.status);
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
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\func test_unrelated() -> bool:
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
    try context.write("app.selka", affected_before);
    try context.git(&.{ "init", "-q" });
    try context.git(&.{ "add", "app.selka" });
    try context.git(&.{ "commit", "-q", "-m", "init" });
    const affected = [_][]const u8{ "test", "app.selka", "--affected", "--against=HEAD", "--cache-dir", "cache" };
    // An untracked module changes on every line, but this program does not load it.
    try context.write("other.selka", "\n\nconst OTHER: int = 1\n\n\nfunc test_other() -> bool:\n    return OTHER == 1\n");
    // An unchanged program selects nothing and exits 3, as a filter matching nothing does.
    const unchanged = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 3), unchanged.status);
    try std.testing.expect(contains(unchanged.stderr, "affected: 0 selected, 2 skipped against HEAD"));
    try std.testing.expect(contains(unchanged.stderr, "skipped app::test_helper: no changed declaration is reachable"));
    // A body edit selects only the test that reaches it, and a selected test reruns.
    try context.write("app.selka", try std.mem.replaceOwned(u8, context.arena, affected_before, "value + 1", "value + 2"));
    const edited = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 1), edited.status);
    try std.testing.expect(contains(edited.stderr, "affected: 1 selected, 1 skipped against HEAD"));
    try std.testing.expect(contains(edited.stderr, "skipped app::test_unrelated"));
    try std.testing.expect(contains(edited.stdout, "failed app::test_helper"));
    try std.testing.expect(!contains(edited.stdout, "test_unrelated"));
    // A filter applies first.
    const filtered = try context.compiler(&.{ "test", "app.selka", "--affected", "--against", "HEAD", "--filter", "unrelated", "--cache-dir", "cache" });
    try std.testing.expectEqual(@as(u8, 3), filtered.status);
    try std.testing.expect(contains(filtered.stderr, "affected: 0 selected, 1 skipped against HEAD"));
    // A changed constant is folded into its readers, so it selects every test.
    try context.write("app.selka", try std.mem.replaceOwned(u8, context.arena, affected_before, "LIMIT: int = 3", "LIMIT: int = 4"));
    const constant = try context.compiler(&affected);
    try std.testing.expectEqual(@as(u8, 1), constant.status);
    try std.testing.expect(contains(constant.stderr, "affected: 2 selected, 0 skipped against HEAD"));
    // The switches only mean something together; a bad revision is a host failure.
    try std.testing.expectEqual(@as(u8, 2), (try context.compiler(&.{ "test", "app.selka", "--against=HEAD" })).status);
    try std.testing.expectEqual(@as(u8, 2), (try context.compiler(&.{ "test", "app.selka", "--affected" })).status);
    const unresolvable = try context.compiler(&.{ "test", "app.selka", "--affected", "--against=no-such-revision", "--cache-dir", "cache" });
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
    try context.write("main.selka", answer);
    try context.write("check.selka", "func test_answer() -> bool:\n    return 6 * 7 == 42\n");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("cache"));
    const cached = try context.compiler(&.{ "run", "main.selka", "--print-result", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), cached.status);
    try std.testing.expect(try context.entries("cache") != 0);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("empty"));
    // An uncached run links its program afresh and leaves nothing behind.
    const uncached = try context.compiler(&.{ "run", "main.selka", "--print-result", "--cache-dir", "empty", "--no-cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), uncached.status);
    try std.testing.expectEqualStrings("42\n", uncached.stdout);
    try std.testing.expect(contains(uncached.stderr, "\"program\":\"linked\""));
    try std.testing.expectEqual(@as(usize, 0), try context.entries("empty"));
    const again = try context.compiler(&.{ "run", "main.selka", "--cache-dir", "cache", "--no-cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), again.status);
    try std.testing.expect(!contains(again.stderr, "replayed"));
    const tested = try context.compiler(&.{ "test", "check.selka", "--cache-dir", "empty", "--no-cache" });
    try std.testing.expectEqual(@as(u8, 0), tested.status);
    try std.testing.expect(contains(tested.stdout, "passed check::test_answer"));
    try std.testing.expectEqual(@as(usize, 0), try context.entries("empty"));
}

// spec: NEW-CORE-S5-REPORT-1
// spec-case: NEW-CORE-STAGE-PACK-1
test "report prints the cache report as one JSON line and says when a build replayed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", answer);
    const first = try context.compiler(&.{ "run", "main.selka", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), first.status);
    const line = std.mem.trimEnd(u8, first.stderr, "\n");
    const record = try std.json.parseFromSliceLeaky(std.json.Value, context.arena, line, .{});
    try std.testing.expectEqualStrings("cache-report-v1", record.object.get("version").?.string);
    try std.testing.expectEqualStrings("linked", record.object.get("program").?.string);
    try std.testing.expect(record.object.get("units").?.integer > 0);
    try std.testing.expect(record.object.get("processes").?.integer > 0);
    const storage = record.object.get("storage").?.object;
    try std.testing.expect(storage.get("flush_succeeded").?.bool);
    try std.testing.expect(storage.get("flush_nanoseconds").?.integer >= 0);
    try std.testing.expect(storage.get("reads").?.object.get("decoded_bytes").?.integer >= 0);
    const stages = record.object.get("stages").?.object;
    try std.testing.expectEqualStrings("stage-report-v3", stages.get("version").?.string);
    try std.testing.expect(stages.get("lowering").?.object.get("materialized").?.integer > 0);
    const restores = stages.get("optimizer").?.object.get("restores").?.object;
    try std.testing.expect(restores.get("final").?.integer >= 0);
    try std.testing.expect(restores.get("checkpoints").?.integer >= 0);
    const misses = stages.get("frontend_misses").?.object;
    try std.testing.expect(misses.contains("lookup") and misses.contains("retention"));
    try std.testing.expect(stages.get("nanoseconds").?.object.get("native").?.integer > 0);
    const frontend_phases = stages.get("nanoseconds").?.object.get("frontend_phases").?.array.items;
    try std.testing.expect(frontend_phases.len > 0);
    for (frontend_phases) |phase| {
        try std.testing.expect(phase.object.get("name").?.string.len > 0);
        try std.testing.expect(phase.object.get("nanoseconds").?.integer >= 0);
        _ = phase.object.get("inclusive").?.bool;
    }
    const second = try context.compiler(&.{ "run", "main.selka", "--cache-dir", "cache", "--report" });
    try std.testing.expectEqual(@as(u8, 42), second.status);
    try std.testing.expect(contains(second.stderr, "{\"version\":\"cache-report-v1\",\"program\":\"replayed\",\"units\":0,"));
    const text = try context.compiler(&.{ "run", "main.selka", "--cache-dir", "cache", "--cache-report" });
    try std.testing.expectEqualStrings("selka-core: cache: replayed the last identical build\n", text.stderr);
    const quiet = try context.compiler(&.{ "run", "main.selka", "--cache-dir", "cache" });
    try std.testing.expectEqualStrings("", quiet.stderr);
}

// spec: NEW-CORE-S5-TIMINGS-1
test "timings print the program's run time without changing its status, output or trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", answer);
    try context.write("trap.selka", "func main() -> int:\n    return divtrunc(1, 0)\n");
    const timed = try context.compiler(&.{ "run", "main.selka", "--print-result", "--cache-dir", "cache", "--timings" });
    try std.testing.expectEqual(@as(u8, 42), timed.status);
    try std.testing.expectEqualStrings("42\n", timed.stdout);
    const prefix = "timings: native_ns=";
    try std.testing.expect(std.mem.startsWith(u8, timed.stderr, prefix));
    _ = try std.fmt.parseInt(u64, std.mem.trimEnd(u8, timed.stderr[prefix.len..], "\n"), 10);
    const trapped = try context.compiler(&.{ "run", "trap.selka", "--cache-dir", "cache", "--timings" });
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "error[R_DIVISION_BY_ZERO]"));
    try std.testing.expect(contains(trapped.stderr, prefix));
    const twice = try context.compiler(&.{ "run", "main.selka", "--timings", "--timings" });
    try std.testing.expectEqual(@as(u8, 2), twice.status);
    try std.testing.expect(contains(twice.stderr, "usage: selka run"));
    const profile = try context.compiler(&.{ "run", "main.selka", "--timings=json" });
    try std.testing.expectEqual(@as(u8, 2), profile.status);
    try std.testing.expect(contains(profile.stderr, "retired"));
}

// spec-case: NEW-CORE-S5-RETIRED-1
test "explain-invalidation is refused on run as retired" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", answer);
    const explained = try context.compiler(&.{ "run", "main.selka", "--explain-invalidation" });
    try std.testing.expectEqual(@as(u8, 2), explained.status);
    try std.testing.expect(contains(explained.stderr, "--report"));
}

// spec: NEW-CORE-S5-TEST-USAGE-1
test "test names a bad flag value or unknown option before printing its own usage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", answer);
    const zero_jobs = try context.compiler(&.{ "test", "main.selka", "--jobs", "0" });
    try std.testing.expectEqual(@as(u8, 2), zero_jobs.status);
    try std.testing.expect(contains(zero_jobs.stderr, "selka test: invalid value '0' for --jobs\nusage: selka test <entry.selka|directory>"));
    try std.testing.expect(contains(zero_jobs.stderr, "--property-runs N"));
    const joined = try context.compiler(&.{ "test", "main.selka", "--jobs=x" });
    try std.testing.expectEqual(@as(u8, 2), joined.status);
    try std.testing.expect(contains(joined.stderr, "invalid value 'x' for --jobs"));
    const runs = try context.compiler(&.{ "test", "main.selka", "--property-runs", "0" });
    try std.testing.expectEqual(@as(u8, 2), runs.status);
    try std.testing.expect(contains(runs.stderr, "invalid value '0' for --property-runs"));
    const unknown = try context.compiler(&.{ "test", "main.selka", "--bogus" });
    try std.testing.expectEqual(@as(u8, 2), unknown.status);
    try std.testing.expect(contains(unknown.stderr, "unknown option '--bogus'"));
    const missing = try context.compiler(&.{ "test", "main.selka", "--filter" });
    try std.testing.expectEqual(@as(u8, 2), missing.status);
    try std.testing.expect(contains(missing.stderr, "missing value for '--filter'"));
    try std.testing.expect(!contains(missing.stderr, "selka-core"));
}

const debug_line = "func main(out: Stream) -> int:\n    debug(\"debugging\", 41)\n    print(out, 42)\n    return 0\n";

/// A `debug` line whose argument writes `counter`: the standard output shows the write in every build mode.
const debug_effect = "func bump(mut n: int) -> int:\n    n += 1\n    return n\n\nfunc main(out: Stream) -> int:\n" ++
    "    mut counter = 0\n    debug(\"debugging\", bump(mut counter))\n    print(out, counter)\n    return 0\n";

/// A `debug` line whose only reader of `xs[len(args) + 4]` is out of range, so every build mode traps.
const debug_trap = "func main(args: str[]) -> int:\n    const xs = [1, 2, 3]\n    debug(xs[len(args) + 4])\n    return 0\n";

// spec-case: DEBUG-OPTIMIZE-1
test "default optimized debug aliases reuse caches while unoptimized and release stay distinct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", debug_line);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, try context.path("suite"));
    try context.write("suite/check.selka", "func test_answer() -> bool:\n    return 6 * 7 == 42\n");
    // `replay`: the build finds the default build's program; `cached`: the test run finds the default run's results. `build` and
    // `run` default to the lean build, `test` to -O0, so `--debug-lean` repeats the first and `--debug-o0` the second.
    const ModeCase = struct { flags: []const []const u8, replay: bool = false, cached: bool = false, release: bool = false };
    for ([_]ModeCase{
        .{ .flags = &.{} },
        .{ .flags = &.{"--optimize-debug"} },
        .{ .flags = &.{ "--mode", "Debug" }, .replay = true, .cached = true },
        .{ .flags = &.{"--debug-lean"}, .replay = true },
        .{ .flags = &.{"--debug-o0"}, .cached = true },
        .{ .flags = &.{"--unoptimized"} },
        .{ .flags = &.{"--release"}, .release = true },
    }) |mode| {
        try support.requireReleaseArgs(mode.flags);
        const build_args = try std.mem.concat(context.arena, []const u8, &.{ &.{ "build", "main.selka", "-o", "program", "--cache-dir", "cache", "--report" }, mode.flags });
        const first = try context.compiler(build_args);
        try std.testing.expectEqual(@as(u8, 0), first.status);
        try std.testing.expect(contains(first.stderr, if (mode.replay) "\"program\":\"replayed\"" else "\"program\":\"linked\""));
        const again = try context.compiler(build_args);
        try std.testing.expectEqual(@as(u8, 0), again.status);
        try std.testing.expect(contains(again.stderr, "\"program\":\"replayed\""));
        const ran = try context.spawn(&.{try context.path("program")});
        try std.testing.expectEqualStrings("42\n", ran.stdout);
        try std.testing.expectEqualStrings(if (mode.release) "" else "debugging 41\n", ran.stderr);
        const test_args = try std.mem.concat(context.arena, []const u8, &.{ &.{ "test", "suite", "--cache-dir", "cache" }, mode.flags });
        const tested = try context.compiler(test_args);
        try std.testing.expectEqual(@as(u8, 0), tested.status);
        try std.testing.expect(contains(tested.stdout, if (mode.cached) "0 passed, 1 cached" else "1 passed, 0 cached"));
        const cached = try context.compiler(test_args);
        try std.testing.expectEqual(@as(u8, 0), cached.status);
        try std.testing.expect(contains(cached.stdout, "0 passed, 1 cached"));
    }
}

// spec-case: DEBUG-OPTIMIZE-1
test "default and unoptimized run commands retain debug output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", debug_line);
    for ([_][]const []const u8{
        &.{ "run", "main.selka", "--verify-facts" },
        &.{ "run-project", "main.selka", "--verify-facts" },
        &.{ "build", "main.selka", "--run" },
        &.{ "run", "main.selka", "--unoptimized" },
        &.{ "run-project", "main.selka", "--unoptimized" },
        &.{ "build", "main.selka", "--run", "--unoptimized" },
    }) |args| {
        const ran = try context.compiler(args);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("42\n", ran.stdout);
        try std.testing.expect(contains(ran.stderr, "debugging 41\n"));
    }
}

// spec-case: DEBUG-OPTIMIZE-1
test "explicit modes conflict for tests and developer builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    for ([_][]const []const u8{
        &.{ "--release", "--optimize-debug" },
        &.{ "--optimize-debug", "--release" },
        &.{ "--release", "--unoptimized" },
        &.{ "--unoptimized", "--release" },
        &.{ "--optimize-debug", "--unoptimized" },
        &.{ "--unoptimized", "--optimize-debug" },
        &.{ "--debug-lean", "--debug-o0" },
        &.{ "--debug-o0", "--release" },
        &.{ "--unoptimized", "--debug-lean" },
    }) |flags| {
        const tested = try context.compiler(try std.mem.concat(context.arena, []const u8, &.{ &.{ "test", "check.selka" }, flags }));
        try std.testing.expectEqual(@as(u8, 2), tested.status);
        try std.testing.expect(contains(tested.stderr, "mutually exclusive"));
        const developer = try context.compiler(try std.mem.concat(context.arena, []const u8, &.{ &.{ "build", "main.selka", "-o", "out", "--generic-vectors" }, flags }));
        try std.testing.expectEqual(@as(u8, 2), developer.status);
    }
}

// spec: NEW-CORE-S5-DEBUG-RELEASE-1
test "a build --release executable evaluates the arguments of debug lines and writes nothing, a debug build and a run write them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("main.selka", debug_effect);
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "main.selka", "-o", "debugged" })).status);
    const debugged = try context.spawn(&.{try context.path("debugged")});
    try std.testing.expectEqualStrings("1\n", debugged.stdout);
    try std.testing.expectEqualStrings("debugging 1\n", debugged.stderr);
    try context.write("trap.selka", debug_trap);
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "trap.selka", "-o", "debug_trapped" })).status);
    const debug_trapped = try context.spawn(&.{try context.path("debug_trapped")});
    try std.testing.expectEqual(@as(u8, 1), debug_trapped.status);
    try std.testing.expect(contains(debug_trapped.stderr, "R_LIST_BOUNDS"));
    try support.requireRelease();
    // The release binary calls `bump` and writes `counter` as the debug binary does, so the same line prints on standard
    // output; it formats nothing and writes nothing to standard error. A bad index in the arguments traps there too.
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "main.selka", "-o", "released", "--release" })).status);
    const released = try context.spawn(&.{try context.path("released")});
    try std.testing.expectEqualStrings("1\n", released.stdout);
    try std.testing.expectEqualStrings("", released.stderr);
    const ran = try context.compiler(&.{ "run", "main.selka", "--release" });
    try std.testing.expectEqualStrings("1\n", ran.stdout);
    try std.testing.expect(contains(ran.stderr, "debugging 1\n"));
    try std.testing.expectEqual(@as(u8, 0), (try context.compiler(&.{ "build", "trap.selka", "-o", "trapped", "--release" })).status);
    const trapped = try context.spawn(&.{try context.path("trapped")});
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "R_LIST_BOUNDS"));
}

// spec: FRONTEND-DEVELOPER-PROJECT-1
test "developer views and coverageCommand check configured project identity and policy before output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try temporary.dir.createDirPath(std.testing.io, "src");
    try context.write("src/main.selka", "import src.helper as helper\nfunc main() -> int:\n    return helper.value()\n");
    try context.write("src/helper.selka", "public func value() -> int:\n    return 7\n");
    try context.write("selka.json", "{\"version\":1}");
    const commands = [_][]const u8{ "dump-ir", "dump-typed", "coverage", "check" };
    try checkDeveloperViews(context, &commands);
    try context.write("selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try context.write("policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    try denyDeveloperViews(context, &commands);
    try context.write("selka.json", "{");
    for (commands[0..2]) |command| {
        const invalid = try context.compiler(&.{ command, "src/main.selka" });
        try std.testing.expectEqual(@as(u8, 2), invalid.status);
        try std.testing.expectEqualStrings("", invalid.stdout);
        try std.testing.expect(contains(invalid.stderr, "E_PROJECT_CONFIG"));
    }
    try context.write("selka.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":8}}");
    const bounded = try context.compiler(&.{ "dump-typed", "src/main.selka" });
    try std.testing.expectEqual(@as(u8, 1), bounded.status);
    try std.testing.expectEqualStrings("", bounded.stdout);
    try std.testing.expect(contains(bounded.stderr, "E_PROJECT"));
}

test "the per-file budget bounds the project's files, not the embedded standard library" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    // math.selka alone is over 95,000 bytes; the per-file budget admits only the project's few lines.
    try context.write("main.selka", "import math\nfunc main() -> int:\n    return 3\n");
    try context.write("selka.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":64}}");
    const checked = try context.compiler(&.{ "check", "main.selka" });
    try std.testing.expectEqual(@as(u8, 0), checked.status);
    try std.testing.expect(!contains(checked.stderr, "E_PROJECT_BYTES"));
    try context.write("main.selka", "import math\nfunc main() -> int:\n    return 3\n# a comment that pushes the project's own file past the 64-byte budget\n");
    const refused = try context.compiler(&.{ "check", "main.selka" });
    try std.testing.expectEqual(@as(u8, 1), refused.status);
    try std.testing.expect(contains(refused.stderr, "E_PROJECT_BYTES"));
}

fn checkDeveloperViews(context: Context, commands: []const []const u8) !void {
    for (commands) |command| {
        const result = try context.compiler(&.{ command, "src/main.selka" });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        // A clean `check` writes its one status line; the developer views write nothing.
        if (std.mem.eql(u8, command, "check")) {
            try std.testing.expect(std.mem.startsWith(u8, result.stderr, "check: ok (2 modules, "));
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "\n"));
        } else try std.testing.expectEqualStrings("", result.stderr);
        if (!std.mem.eql(u8, command, "check")) {
            try std.testing.expect(result.stdout.len > 0);
            try std.testing.expect(!contains(result.stdout, "frontend "));
        }
    }
}

fn denyDeveloperViews(context: Context, commands: []const []const u8) !void {
    for (commands) |command| {
        const denied = try context.compiler(&.{ command, "src/main.selka" });
        if (std.mem.eql(u8, command, "coverage")) {
            try std.testing.expect(contains(denied.stdout, "frontend "));
            try std.testing.expect(!contains(denied.stdout, "ok "));
        } else {
            try std.testing.expectEqual(@as(u8, 3), denied.status);
            try std.testing.expectEqualStrings("", denied.stdout);
            try std.testing.expect(denied.stderr.len > 0);
        }
    }
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "CLI rejects invalid stage compression with a configuration diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.corePath(), a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("SELKA_STAGE_CACHE_COMPRESSION", "invalid");
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = "func main() -> int:\n    return 0\n" });
    const source = try temporary.dir.realPathFileAlloc(std.testing.io, "app.selka", a);
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ executable, "build", source, "-o", "unused-compression-test" },
        .environ_map = &environment,
    });
    try std.testing.expect(result.term == .exited);
    try std.testing.expect(result.term.exited != 0);
    try std.testing.expect(contains(result.stderr, "SELKA_STAGE_CACHE_COMPRESSION must be 'zlib' or 'none'"));
}

/// The `storage.compression` that one `run --report` in `cache` reports, with `environment`.
fn reportedCompression(a: std.mem.Allocator, executable: []const u8, source: []const u8, cache: []const u8, environment: *const std.process.Environ.Map) ![]const u8 {
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ executable, "run", source, "--cache-dir", cache, "--report" },
        .environ_map = environment,
    });
    try std.testing.expect(result.term == .exited);
    try std.testing.expectEqual(@as(u8, 0), result.term.exited);
    const record = try std.json.parseFromSliceLeaky(std.json.Value, a, std.mem.trimEnd(u8, result.stderr, "\n"), .{});
    return record.object.get("storage").?.object.get("compression").?.string;
}

// spec-case: NEW-CORE-STAGE-PACK-1
test "report names the stage store compression: uncompressed by default and zlib on request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.corePath(), a);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = "func main() -> int:\n    return 0\n" });
    const source = try std.fs.path.join(a, &.{ root, "app.selka" });
    var environment = try tools.privateEnvironment(a);
    defer environment.deinit();
    _ = environment.swapRemove("SELKA_STAGE_CACHE_COMPRESSION");
    const uncompressed = try reportedCompression(a, executable, source, try std.fs.path.join(a, &.{ root, "default-cache" }), &environment);
    try std.testing.expectEqualStrings("none", uncompressed);
    try environment.put("SELKA_STAGE_CACHE_COMPRESSION", "zlib");
    const compressed = try reportedCompression(a, executable, source, try std.fs.path.join(a, &.{ root, "zlib-cache" }), &environment);
    try std.testing.expectEqualStrings("zlib", compressed);
}

// spec-case: DEBUG-OPTIMIZE-1
test "unsigned negation traps in default unoptimized release and verified builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("negate.selka", "func main() -> int:\n    _ = -1u8\n    return 0\n");
    for ([_][]const []const u8{ &.{}, &.{"--unoptimized"}, &.{"--verify-facts"}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |flags| {
        try support.requireReleaseArgs(flags);
        const args = try std.mem.concat(context.arena, []const u8, &.{ &.{ "build", "negate.selka", "--run" }, flags });
        const result = try context.compiler(args);
        try std.testing.expectEqual(@as(u8, 1), result.status);
        try std.testing.expect(contains(result.stderr, "R_OVERFLOW"));
    }
}
