//! Public CLI regressions for `selka review`: the change-note skeleton, the change review
//! and its gate, and the change notes that `release cut` files.
const std = @import("std");
const testing = std.testing;

const Fixture = struct {
    a: std.mem.Allocator,
    dir: std.Io.Dir,
    fn write(self: Fixture, path: []const u8, bytes: []const u8) !void {
        if (std.fs.path.dirname(path)) |parent| try self.dir.createDirPath(testing.io, parent);
        try self.dir.writeFile(testing.io, .{ .sub_path = path, .data = bytes });
    }
    fn read(self: Fixture, path: []const u8) ![]const u8 {
        return self.dir.readFileAlloc(testing.io, path, self.a, .limited(1 << 20));
    }
    fn run(self: Fixture, args: []const []const u8, status: u8) !Result {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), self.a);
        const argv = try self.a.alloc([]const u8, args.len + 1);
        argv[0] = compiler;
        @memcpy(argv[1..], args);
        const result = try std.process.run(self.a, testing.io, .{ .argv = argv, .cwd = .{ .dir = self.dir } });
        if (!std.meta.eql(result.term, std.process.Child.Term{ .exited = status })) std.debug.print("review CLI expected {d}, got {any}\n{s}\n{s}\n", .{ status, result.term, result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        return .{ .stdout = result.stdout, .stderr = result.stderr };
    }
    fn project(self: Fixture) !void {
        try self.write("selka.json", "{\"version\":2}\n");
        try self.write("main.selka", documented);
        _ = try self.run(&.{ "fmt", "main.selka", "--write" }, 0);
    }
    /// Run git in the fixture with the hook variables removed, failing unless it exits zero.
    fn git(self: Fixture, args: []const []const u8) !void {
        var environment = try testing.environ.createMap(self.a);
        defer environment.deinit();
        _ = environment.swapRemove("GIT_DIR");
        _ = environment.swapRemove("GIT_WORK_TREE");
        _ = environment.swapRemove("GIT_INDEX_FILE");
        const prefix = [_][]const u8{ "git", "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false" };
        const argv = try self.a.alloc([]const u8, prefix.len + args.len);
        @memcpy(argv[0..prefix.len], &prefix);
        @memcpy(argv[prefix.len..], args);
        const result = try std.process.run(self.a, testing.io, .{ .argv = argv, .cwd = .{ .dir = self.dir }, .environ_map = &environment });
        const code: u8 = switch (result.term) {
            .exited => |status| status,
            else => 255,
        };
        if (code != 0) std.debug.print("git {s} failed\n{s}\n", .{ args[0], result.stderr });
        try testing.expectEqual(@as(u8, 0), code);
    }
    /// Make the fixture directory a repository on `main`, ignoring the review's cache.
    fn initialize(self: Fixture) !void {
        try self.write(".gitignore", ".selka-cache/\n");
        try self.git(&.{ "init", "-q" });
        try self.git(&.{ "symbolic-ref", "HEAD", "refs/heads/main" });
    }
    /// Commit every file of the fixture under `message`.
    fn commit(self: Fixture, message: []const u8) !void {
        try self.git(&.{ "add", "-A" });
        try self.git(&.{ "commit", "-q", "-m", message });
    }
    /// The documented project, committed on `main` as `base`.
    fn repository(self: Fixture) !void {
        try self.project();
        try self.initialize();
        try self.commit("base");
    }
};
const Result = struct { stdout: []const u8, stderr: []const u8 };
const documented =
    "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n" ++
    "    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    42\n    \"\"\"\n" ++
    "    return 42\n\n\n" ++
    "public func test_answer() -> bool:\n    return answer() == 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
const skeleton =
    "# TODO: title of this change\n\n" ++
    "Summary: TODO\n\n" ++
    "<!-- review: in two to four sentences, say what changed for someone who uses this project, and why. -->\n";
const note =
    "# Serve on the event loop\n\n" ++
    "Summary: `serve` now runs one event loop with a 1,024-slot connection table, back-pressure and an idle timeout.\n\n" ++
    "Details for the reviewer.\n";

/// `documented` with the body of `answer` changed and its interface kept.
const edited_body = "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    42\n    \"\"\"\n" ++
    "    return 40 + 2\n\n\n" ++
    "public func test_answer() -> bool:\n    return answer() == 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
/// `documented` with one new public function, `double`.
const double_source = documented ++ "\n\n" ++
    "public func double(x: int) -> int:\n" ++
    "    \"\"\"Twice the value. It multiplies by two.\n\n    >>> double(2)\n    4\n    \"\"\"\n" ++
    "    return x * 2\n";
/// A valid decision that names `double`.
const double_decision =
    "# Add double\n\n" ++
    "Changes: main::double\n" ++
    "Why: Callers need a doubled value without repeating the multiplication in every program that uses the library.\n";
/// A change note whose summary is still a placeholder.
const placeholder_note = "# Serve on the event loop\n\nSummary: TODO\n";

/// `documented` with the body of `test_answer` changed, its interface kept.
const changed_test = "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    42\n    \"\"\"\n" ++
    "    return 42\n\n\n" ++
    "public func test_answer() -> bool:\n    return answer() == 40 + 2\n\n\n" ++
    "func main() -> int:\n    return 0\n";
/// `documented` with `test_answer` removed and `test_new` added.
const swapped_tests = "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    42\n    \"\"\"\n" ++
    "    return 42\n\n\n" ++
    "public func test_new() -> bool:\n    return answer() == 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
/// `documented` with the example output of `answer` changed to 41, its source kept.
const changed_example = "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    41\n    \"\"\"\n" ++
    "    return 42\n\n\n" ++
    "public func test_answer() -> bool:\n    return answer() == 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
/// A project that imports `ports`, whose public function is new in the change.
const importing_main = "import ports\n\n\n\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer() -> int:\n    return 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
/// A generated source with one public function and its marker on the first line.
const generated_ports = "# GENERATED by tool\npublic func port_one() -> int:\n    return 1\n";

test "review behaviour lists a changed test body with its diff and attention says so" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", changed_test);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "! 1 existing test now expects something different\n  main::test_answer\n") != null);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"tests_changed\":[{\"module\":\"main\",\"name\":\"test_answer\",\"diff\":[\"-    return answer() == 42\",\"+    return answer() == 40 + 2\"]}]") != null);
    try testing.expect(std.mem.indexOf(u8, json, "{\"level\":\"info\",\"text\":\"1 existing test now expects something different\"") != null);
}

test "review behaviour lists added and removed tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", swapped_tests);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"tests_added\":[{\"module\":\"main\",\"name\":\"test_new\"}]") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"tests_removed\":[{\"module\":\"main\",\"name\":\"test_answer\"}]") != null);
    try testing.expect(std.mem.indexOf(u8, json, "{\"level\":\"warn\",\"text\":\"1 test was removed\"") != null);
}

test "review behaviour reports a docstring example whose output changed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", changed_example);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"examples_changed\":[{\"name\":\"main::answer\",\"source\":\"answer()\",\"old\":\"42\",\"new\":\"41\"}]") != null);
}

test "review behaviour lists a generated file and still asks for a decision on its new function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", importing_main);
    try f.write("ports.selka", generated_ports);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"generated\":[{\"path\":\"ports.selka\",\"first_line\":\"# GENERATED by tool\",\"lines_before\":0,\"lines_after\":3}]") != null);
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "error[E_REVIEW_DECISION_MISSING]: public declaration ports::port_one is added and no decision in this change names it;") != null);
}

test "review behaviour lists a citation that a new comment adds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", "# FR-123: reason\n" ++ documented);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"citations\":{\"added\":[{\"id\":\"FR-123\",\"path\":\"main.selka\"}],\"removed\":[]}") != null);
}

test "review attention lists a new public function that takes a capability" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", documented ++ "\n\npublic func read_file(fs: Filesystem) -> int:\n    return 1\n");
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "! New authority: these functions can now reach the outside world\n  main::read_file: needs `Filesystem`\n") != null);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"gained_authority\":[\"Filesystem\"]") != null);
    try testing.expect(std.mem.indexOf(u8, json, "{\"level\":\"info\",\"text\":\"New authority: these functions can now reach the outside world\",\"items\":[\"main::read_file: needs `Filesystem`\"]}") != null);
}

test "review behaviour runs the head's tests with --test and records their counts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    const shown = try f.run(&.{ "review", ".", "--test", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "tests at the head: ") != null);
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), try f.read("review.json"), .{});
    const run = parsed.value.object.get("tests_run").?.object;
    // test_answer and the docstring example each pass; a cached pass is still a pass.
    try testing.expectEqual(@as(i64, 2), run.get("passed").?.integer + run.get("cached").?.integer);
    try testing.expectEqual(@as(i64, 0), run.get("failed").?.integer);
    try testing.expect(run.get("found").?.bool);
}

test "review draft writes the change note skeleton and never overwrites a note" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    const written = try f.run(&.{ "review", "draft", ".", "--name", "serve-event-loop" }, 0);
    try testing.expectEqualStrings("review draft: wrote changes/unreleased/serve-event-loop.md; replace the title and Summary placeholders\n", written.stdout);
    try testing.expectEqualStrings(skeleton, try f.read("changes/unreleased/serve-event-loop.md"));
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const refused = try f.run(&.{ "review", "draft", ".", "--name", "serve-event-loop" }, 3);
    try testing.expectEqualStrings("selka review: change note already exists; draft never overwrites it\n", refused.stderr);
    try testing.expectEqualStrings(note, try f.read("changes/unreleased/serve-event-loop.md"));
}

test "review rejects other subcommands, a date and an unsafe name as usage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    const other = try f.run(&.{ "review", "check", "." }, 2);
    try testing.expect(std.mem.startsWith(u8, other.stderr, "usage: selka review draft PROJECT --name SLUG"));
    _ = try f.run(&.{ "review", "draft", "." }, 2);
    _ = try f.run(&.{ "review", "draft", ".", "--name", "bad/name" }, 2);
    _ = try f.run(&.{ "review", "draft", ".", "--name", "x", "--date", "2026-10-21" }, 2);
    try testing.expectError(error.FileNotFound, f.read("changes/unreleased/x.md"));
}

test "release cut files change notes under the release and records their count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const cut = try f.run(&.{ "release", "cut", ".", "--name", "0.1" }, 0);
    try testing.expect(std.mem.endsWith(u8, cut.stdout, "release cut: 0.1 (0 decisions, 1 change notes)\n"));
    try testing.expectEqualStrings(note, try f.read("changes/0.1/serve-event-loop.md"));
    try testing.expectError(error.FileNotFound, f.read("changes/unreleased/serve-event-loop.md"));
    try testing.expectEqual(std.Io.File.Kind.directory, (try f.dir.statFile(testing.io, "changes/unreleased", .{})).kind);
    try testing.expectEqualStrings("0.1\t0\t1\n", try f.read("release/history.txt"));
    const empty = try f.run(&.{ "release", "cut", ".", "--name", "0.2" }, 0);
    try testing.expect(std.mem.endsWith(u8, empty.stdout, "release cut: 0.2 (0 decisions)\n"));
    try testing.expectEqualStrings("0.1\t0\t1\n0.2\t0\t0\n", try f.read("release/history.txt"));
}

test "selka docs lists the change review guide and prints its note format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    const listed = try f.run(&.{"docs"}, 0);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "  change-review ") != null);
    const guide = try f.run(&.{ "docs", "change-review" }, 0);
    try testing.expect(std.mem.startsWith(u8, guide.stdout, "# Change review"));
    try testing.expect(std.mem.indexOf(u8, guide.stdout, "## Write a change note") != null);
}

test "review gate passes a body-only change with a valid note and records the body change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", edited_body);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const passed = try f.run(&.{ "review", ".", "--check", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "..working tree: OK\n") != null);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "review: passes;") != null);
    try testing.expect(std.mem.indexOf(u8, try f.read("review.json"), "\"body_changed\":[\"main::answer\"]") != null);
}

test "review gate refuses a source change that adds no change note" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", edited_body);
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "error[E_REVIEW_SUMMARY_MISSING]: the change touches the project's source and adds no change note; run `selka review draft . --name SLUG`\n") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "review: refused; 1 refusals;") != null);
    // Without --check the review is still written, and the command exits 0.
    _ = try f.run(&.{ "review", "." }, 0);
}

test "review gate refuses a new public function until a decision names it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "error[E_REVIEW_DECISION_MISSING]: public declaration main::double is added and no decision in this change names it; run `selka release draft . --name SLUG`\n") != null);
    // The refusal is counted in the attention list and printed once, as its error line.
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "! 1 refusal blocks the change; it is listed below\n") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, refused.stdout, "E_REVIEW_DECISION_MISSING"));
    try f.write("decisions/unreleased/double.md", double_decision);
    _ = try f.run(&.{ "review", ".", "--check" }, 0);
}

test "review gate ignores a decision that was already pending on the base" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("decisions/unreleased/double.md", double_decision);
    try f.initialize();
    try f.commit("base with an earlier decision");
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "error[E_REVIEW_DECISION_MISSING]") != null);
}

test "review gate accepts a decision added under a release directory in the same change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    try f.write("decisions/0.2/double.md", double_decision);
    _ = try f.run(&.{ "review", ".", "--check" }, 0);
}

test "review gate refuses a change note that still holds a placeholder" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", edited_body);
    try f.write("changes/unreleased/serve-event-loop.md", placeholder_note);
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "changes/unreleased/serve-event-loop.md:3: error[E_REVIEW_NOTE_INVALID]: the summary still holds a placeholder\n") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "E_REVIEW_SUMMARY_MISSING") == null);
}

test "review gate needs no note for a change limited to friction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("friction/case.selka", "func main() -> int:\n    return 0\n");
    try f.write("friction/log.jsonl", "{}\n");
    const passed = try f.run(&.{ "review", ".", "--check" }, 0);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "review: passes; 0 public changes, 0 change notes, 0 decisions\n") != null);
}

test "review gate reads an untracked note and decision in working-tree mode" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    try f.write("decisions/unreleased/double.md", double_decision);
    const passed = try f.run(&.{ "review", ".", "--check" }, 0);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "..working tree: OK\n") != null);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "  main::double: New function `double(x: int) -> int`. Twice the value.\n") != null);
}

test "review gate compares a committed range" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    try f.write("decisions/unreleased/double.md", double_decision);
    try f.commit("add double");
    const passed = try f.run(&.{ "review", ".", "--range", "HEAD~1..HEAD", "--check" }, 0);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "working tree") == null);
    try testing.expect(std.mem.indexOf(u8, passed.stdout, "review: passes;") != null);
}

test "review gate lets one valid decision explain a new project" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("README.md", "# Demo\n");
    try f.initialize();
    try f.commit("base without the project");
    try f.project();
    try f.write("decisions/unreleased/double.md", double_decision);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--check" }, 0);
}

test "review gate refuses a head whose declarations do not load" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", "public func broken(\n");
    const refused = try f.run(&.{ "review", ".", "--check" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "error[E_REVIEW_HEAD_UNREADABLE]: the working tree declarations do not load: ") != null);
    // The loader's located failure is copied, then released: the debug allocator reports no leak.
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "leaked") == null);
}

test "review json writes a review-v1 object whose first sentence reads as the change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    try f.write("decisions/unreleased/double.md", double_decision);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), try f.read("review.json"), .{});
    const object = parsed.value.object;
    try testing.expectEqualStrings("review-v1", object.get("version").?.string);
    try testing.expectEqualStrings("main::double", object.get("interface").?.array.items[0].object.get("name").?.string);
    const sentences = object.get("interface").?.array.items[0].object.get("sentences").?.array.items;
    try testing.expectEqualStrings("New function `double(x: int) -> int`. Twice the value.", sentences[0].string);
    try testing.expectEqualStrings("Add double", object.get("interface").?.array.items[0].object.get("decision").?.string);
    try testing.expect(object.get("verdict").?.object.get("ok").?.bool);
}

test "release check refuses an invalid pending change note and release cut keeps it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("changes/unreleased/serve-event-loop.md", placeholder_note);
    const checked = try f.run(&.{ "release", "check", "." }, 3);
    try testing.expect(std.mem.indexOf(u8, checked.stdout, "changes/unreleased/serve-event-loop.md:3:1: error[E_REVIEW_NOTE_INVALID]: the summary still holds a placeholder\n") != null);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "0.1" }, 3);
    try testing.expectEqualStrings(placeholder_note, try f.read("changes/unreleased/serve-event-loop.md"));
    try testing.expectError(error.FileNotFound, f.read("changes/0.1/serve-event-loop.md"));
}

/// The entry module of the inside tests: `main` calls nothing, and the functions under test live beside it.
const inside_main = "func main() -> int:\n    return 0\n";
/// A change note for the inside tests, so that a source change is not also refused for want of one.
const inside_note = "# Refine the functions under test\n\nSummary: The functions under test change in this review, for the inside tests.\n";

/// Commit a project whose `cli.selka` holds `cli` as the base, with `main.selka` as its entry.
fn insideBase(f: Fixture, cli: []const u8) !void {
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", inside_main);
    try f.write("cli.selka", cli);
    try f.initialize();
    try f.commit("base");
}

/// The `parse_serve` shape before a change: one `--port` branch that parses a number.
const serve_base = "func parse_serve(args: str[]) -> int:\n" ++
    "    mut index: int = 0\n    mut port: int = 0\n" ++
    "    while index < len(args):\n" ++
    "        if args[index] == \"--port\":\n" ++
    "            index += 1\n" ++
    "            if index >= len(args):\n                return 0 - 1\n" ++
    "            port = port * 10 + 1\n            port = port + 0\n" ++
    "        index += 1\n    return port\n";
/// `parse_serve` after the change: a `--blocking` branch, an `--idle-ms` branch that copies `--port`,
/// and an `--idle-ms=` branch written with the `strings.starts_with` function form.
const serve_head = "import strings\n\nfunc parse_serve(args: str[]) -> int:\n" ++
    "    mut index: int = 0\n    mut port: int = 0\n" ++
    "    while index < len(args):\n" ++
    "        if args[index] == \"--port\":\n" ++
    "            index += 1\n" ++
    "            if index >= len(args):\n                return 0 - 1\n" ++
    "            port = port * 10 + 1\n            port = port + 0\n" ++
    "        elif args[index] == \"--blocking\":\n            return 2\n" ++
    "        elif args[index] == \"--idle-ms\":\n" ++
    "            index += 1\n" ++
    "            if index >= len(args):\n                return 0 - 1\n" ++
    "            port = port * 10 + 1\n            port = port + 0\n" ++
    "        elif strings.starts_with(args[index], \"--idle-ms=\"):\n            return 3\n" ++
    "        index += 1\n    return port\n";

test "review inside lists a private helper whose body changed with its lines and decision points" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "public func answer() -> int:\n    return helper(1)\n\n\nfunc helper(x: int) -> int:\n    if x > 0:\n        return 1\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try f.initialize();
    try f.commit("base");
    try f.write("main.selka", "public func answer() -> int:\n    return helper(1)\n\n\nfunc helper(x: int) -> int:\n    if x > 0:\n        return 1\n    elif x < 0:\n        return 2\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try f.write("changes/unreleased/helper.md", inside_note);
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  main::helper: edited, lines 4 → 6, decision points 1 → 2\n") != null);
    try testing.expect(std.mem.indexOf(u8, try f.read("review.json"), "{\"name\":\"main::helper\",\"public\":false,\"state\":\"changed\",\"file\":\"main.selka\",\"line\":5,\"lines\":[4,6],\"decision_points\":[1,2],\"signals\":[],\"diff\":[\"+    elif x < 0:\",\"+        return 2\"]}") != null);
}

test "review inside names the special cases and the copied block of a parse_serve-shaped change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try insideBase(f, serve_base);
    try f.write("cli.selka", serve_head);
    try f.write("changes/unreleased/serve.md", inside_note);
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "! Possible patching instead of restructuring (heuristic)\n" ++
        "  cli::parse_serve: adds branches that compare `args[index]` against `\"--blocking\"`, `\"--idle-ms\"`, `\"--idle-ms=\"`\n" ++
        "  cli::parse_serve: the new block at line 15 repeats the block at line 7 with only names or literals changed\n") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  cli::parse_serve: edited, lines 12 → 22, decision points 3 → 7\n") != null);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "{\"kind\":\"special-case\",\"text\":\"adds branches that compare `args[index]` against `\\\"--blocking\\\"`, `\\\"--idle-ms\\\"`, `\\\"--idle-ms=\\\"`\"}") != null);
    try testing.expect(std.mem.indexOf(u8, json, "{\"kind\":\"copy\",\"text\":\"the new block at line 15 repeats the block at line 7 with only names or literals changed\"}") != null);
    try testing.expect(std.mem.indexOf(u8, json, "{\"level\":\"warn\",\"text\":\"Possible patching instead of restructuring (heuristic)\"") != null);
}

test "review inside takes a new bool parameter that a branch tests as a flag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try insideBase(f, "func announce(name: str) -> str:\n    return name\n");
    try f.write("cli.selka", "func announce(name: str, verbose: bool) -> str:\n    if verbose:\n        return \"loud\"\n    return name\n");
    try f.write("changes/unreleased/announce.md", inside_note);
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  cli::announce: takes a new bool parameter `verbose` and branches on it\n") != null);
    try testing.expect(std.mem.indexOf(u8, try f.read("review.json"), "{\"kind\":\"flag\",\"text\":\"takes a new bool parameter `verbose` and branches on it\"}") != null);
}

test "review inside gives no signal to an unrelated small edit and lists no module constant" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try insideBase(f, "func offset(x: int) -> int:\n    return x + 2\n");
    // The added public constant is explained by its own decision, so the review passes.
    try f.write("cli.selka", "public const LIMIT: int = 3\n\nfunc offset(x: int) -> int:\n    return x + 3\n");
    try f.write("changes/unreleased/offset.md", inside_note);
    try f.write("decisions/unreleased/limit.md", "# Add the limit\n\nChanges: cli::LIMIT\nWhy: Callers need the connection limit without reading the source of the server that enforces it.\n");
    const shown = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "Possible patching") == null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  cli::offset: edited, lines 2 → 2, decision points 0 → 0\n") != null);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  cli::LIMIT: added, lines") == null);
    const json = try f.read("review.json");
    try testing.expect(std.mem.indexOf(u8, json, "\"signals\":[],\"diff\":[\"-    return x + 2\",\"+    return x + 3\"]") != null);
    // An interface item names the constant too, but only an `inside` entry is followed by its visibility.
    try testing.expect(std.mem.indexOf(u8, json, "{\"name\":\"cli::LIMIT\",\"public\"") == null);
}

/// A `table` function whose body is 120 increments after its declaration of `total`.
fn longTable(a: std.mem.Allocator) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "func table() -> int:\n    mut total: int = 0\n");
    for (0..120) |_| try text.appendSlice(a, "    total += 1\n");
    try text.appendSlice(a, "    return total\n");
    return text.items;
}

test "review inside cuts a long edit at eighty diff lines and says how many lines it left out" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try insideBase(f, "func table() -> int:\n    return 0\n");
    try f.write("cli.selka", try longTable(f.a));
    try f.write("changes/unreleased/table.md", inside_note);
    _ = try f.run(&.{ "review", ".", "--json", "review.json" }, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, f.a, try f.read("review.json"), .{});
    const diff = parsed.value.object.get("inside").?.array.items[0].object.get("diff").?.array.items;
    // 123 diff lines in all: the removed `return 0`, the added declaration and 120 increments, and `return total`.
    try testing.expectEqual(@as(usize, 80), diff.len);
    try testing.expectEqualStrings("… 44 more lines", diff[79].string);
    try testing.expectEqualStrings("+    total += 1", diff[2].string);
}

test "review inside names the test helpers of a test module on one line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try insideBase(f, "func offset(x: int) -> int:\n    return x + 2\n");
    try f.write("cli_test.selka", "func serve_of(x: int) -> int:\n    return x\n");
    try f.commit("add a test module");
    try f.write("cli_test.selka", "func serve_of(x: int) -> int:\n    return x + 1\n");
    try f.write("changes/unreleased/helper.md", inside_note);
    const shown = try f.run(&.{ "review", "." }, 0);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "  test helpers changed: cli_test::serve_of\n") != null);
}

test "review html writes one self-contained page with the review's data, and two runs write the same bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--html", "review.html" }, 0);
    const first = try f.read("review.html");
    try testing.expect(std.mem.startsWith(u8, first, "<!doctype html>"));
    try testing.expect(std.mem.indexOf(u8, first, "New function `double(x: int) -> int`. Twice the value.") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"version\":\"review-v1\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "https://") == null);
    try testing.expect(std.mem.indexOf(u8, first, "http://") == null);
    _ = try f.run(&.{ "review", ".", "--html", "again.html" }, 0);
    try testing.expectEqualStrings(first, try f.read("again.html"));
}

test "review html is written when --check refuses the change, and the refusal still exits 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.repository();
    try f.write("main.selka", double_source);
    try f.write("changes/unreleased/serve-event-loop.md", note);
    _ = try f.run(&.{ "review", ".", "--check", "--html", "refused.html" }, 3);
    const page = try f.read("refused.html");
    try testing.expect(std.mem.startsWith(u8, page, "<!doctype html>"));
    try testing.expect(std.mem.indexOf(u8, page, "\"code\":\"E_REVIEW_DECISION_MISSING\"") != null);
}

/// An open change of project `p` on a branch: refused for a missing decision, with one note.
const open_review = "{\"version\":\"review-v1\",\"project\":\"p\",\"range\":{\"base\":\"0123456789abcdef0123\",\"head\":\"working tree\",\"working_tree\":true}," ++
    "\"verdict\":{\"ok\":false,\"refusals\":[{\"code\":\"E_REVIEW_DECISION_MISSING\",\"message\":\"m\"}]}," ++
    "\"notes\":[{\"path\":\"changes/unreleased/x.md\",\"title\":\"Serve on the event loop\",\"summary\":\"s\",\"valid\":true}]," ++
    "\"decisions\":[],\"interface\":[{\"name\":\"p::f\",\"module\":\"p\",\"kind\":\"function\",\"change\":\"added\",\"sentences\":[],\"signature\":\"s\"}],\"attention\":[]}\n";
/// A landing of project `p` that a bypass for a pin bump let through.
const landed_review = "{\"version\":\"review-v1\",\"project\":\"p\",\"range\":{\"base\":\"0123456789abcdef0123\",\"head\":\"abc123def456\",\"working_tree\":false}," ++
    "\"verdict\":{\"ok\":false,\"refusals\":[{\"code\":\"E_REVIEW_BASE_UNREADABLE\",\"message\":\"m\"}]},\"notes\":[]," ++
    "\"decisions\":[{\"path\":\"decisions/0.2/f.md\",\"title\":\"Add f\",\"changes\":[\"p::f\"],\"valid\":true}],\"interface\":[{\"name\":\"p::f\",\"decision\":\"Add f\"}],\"attention\":[]}\n";

test "review index writes the site's front page, with the banner, the open change and the bypassed landing, the same bytes twice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("site/projects/p/overview.json", "{\"version\":\"overview-v1\",\"title\":\"p\",\"summary\":\"Small library. It adds numbers.\"}\n");
    try f.write("site/changes/feature/p.review.json", open_review);
    try f.write("site/merged/abc123def456/p.review.json", landed_review);
    try f.write("site/bypass.log", "2026-10-21T05:00:00Z\t0000000000\tabc123def456\tpin bump to the new compiler\n");
    try f.write("site/gate-mode", "report-only\n");
    _ = try f.run(&.{ "review", "index", "site" }, 0);
    const first = try f.read("site/index.html");
    try testing.expect(std.mem.startsWith(u8, first, "<!doctype html>"));
    try testing.expect(std.mem.indexOf(u8, first, "\"gate_mode\":\"report-only\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "The gate is report-only") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"label\":\"feature\",\"project\":\"p\",\"ok\":false,\"title\":\"Serve on the event loop\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"link\":\"changes/feature/p.html\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"name\":\"p\",\"title\":\"p\",\"summary\":\"Small library.\",\"link\":\"projects/p/index.html\"") != null);
    try testing.expect(std.mem.indexOf(u8, first, "\"bypass\":\"pin bump to the new compiler\"") != null);
    _ = try f.run(&.{ "review", "index", "site" }, 0);
    try testing.expectEqualStrings(first, try f.read("site/index.html"));
}

test "review index takes one site directory, and a missing one is a host failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    const usage = try f.run(&.{ "review", "index" }, 2);
    try testing.expect(std.mem.startsWith(u8, usage.stderr, "usage: selka review index SITE_DIR"));
    _ = try f.run(&.{ "review", "index", "a", "b" }, 2);
    const missing = try f.run(&.{ "review", "index", "missing" }, 2);
    try testing.expect(std.mem.startsWith(u8, missing.stderr, "selka review index: "));
}
