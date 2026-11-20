//! Public CLI regressions for checked project documentation and release commands.
const std = @import("std");
const testing = std.testing;

/// Skips the calling test while release builds are off (`-Dtest-release=true` runs them).
fn requireRelease() error{SkipZigTest}!void {
    if (!@import("test_release_options").enabled) return error.SkipZigTest;
}

test "CLI docs prints the checked release guide outside the source tree" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const release_docs = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "docs", "release-docs" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(release_docs.stdout);
    defer testing.allocator.free(release_docs.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release_docs.term);
    try testing.expectEqualStrings("", release_docs.stderr);
    try testing.expect(std.mem.startsWith(u8, release_docs.stdout, "# Checked project documentation"));
    try testing.expect(std.mem.indexOf(u8, release_docs.stdout, "release check . --step decisions,overview") != null);
    const listed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "docs" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(listed.stdout);
    defer testing.allocator.free(listed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listed.term);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "  release-docs ") != null);
}

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
        var environment = try @import("test_paths").privateEnvironment(self.a);
        const result = try std.process.run(self.a, testing.io, .{ .argv = argv, .cwd = .{ .dir = self.dir }, .environ_map = &environment });
        if (!std.meta.eql(result.term, std.process.Child.Term{ .exited = status })) std.debug.print("release CLI expected {d}, got {any}\n{s}\n{s}\n", .{ status, result.term, result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        return .{ .stdout = result.stdout, .stderr = result.stderr };
    }
    fn project(self: Fixture) !void {
        try self.write("selka.json", "{\"version\":2}\n");
        try self.write("main.selka", documented);
        _ = try self.run(&.{ "fmt", "main.selka", "--write" }, 0);
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
const changed =
    "\"\"\"Small arithmetic library with executable calling examples.\"\"\"\n\n\n" ++
    "public func answer(value: int = 42) -> int:\n" ++
    "    \"\"\"The stable answer used by the command.\n\n    >>> answer()\n    42\n    \"\"\"\n" ++
    "    return value\n\n\n" ++
    "public func test_answer() -> bool:\n    return answer() == 42\n\n\n" ++
    "func main() -> int:\n    return 0\n";
const explanation = "# Configurable answer\n\nChanges: main::answer\nWhy: Callers need to choose a number while existing callers retain the familiar default.\n";

test "release CLI init draft check cut records a reviewed interface change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    const missing = try f.run(&.{ "release", "check", ".", "--step", "decisions", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "E_RELEASE_NO_BASELINE") != null);
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const first = try f.read("release/baseline.txt");
    _ = try f.run(&.{ "release", "init", "." }, 3);
    try testing.expectEqualStrings(first, try f.read("release/baseline.txt"));
    const green = try f.run(&.{ "release", "check", "." }, 0);
    try testing.expect(std.mem.indexOf(u8, green.stdout, "1 tests, 1 examples") != null);
    try f.write("main.selka", changed);
    _ = try f.run(&.{ "release", "draft", ".", "--name", "answer", "--date", "2026-10-19" }, 0);
    const drafted = try f.read("decisions/unreleased/answer.md");
    try testing.expect(std.mem.indexOf(u8, drafted, "Changes: main::answer") != null);
    try testing.expect(std.mem.indexOf(u8, drafted, "Date: 2026-10-19") != null);
    _ = try f.run(&.{ "release", "draft", ".", "--name", "answer" }, 3);
    const refused = try f.run(&.{ "release", "check", ".", "--step", "decisions,overview" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "E_RELEASE_DECISION_INVALID") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "E_RELEASE_OVERVIEW_STALE") != null);
    try f.write("decisions/unreleased/answer.md", explanation);
    _ = try f.run(&.{ "overview", ".", "--write" }, 0);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "0.1" }, 0);
    try testing.expectEqualStrings("0.1\t1\n", try f.read("release/history.txt"));
    try testing.expectEqualStrings(explanation, try f.read("decisions/0.1/answer.md"));
    _ = try f.run(&.{ "overview", ".", "--check" }, 0);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "0.1" }, 3);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "unreleased" }, 3);
}

test "release CLI source errors refuse and dependent steps explain their skips" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("main.selka", "func main() -> int:\n    return 'wrong'\n");
    const result = try f.run(&.{ "release", "check", ".", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "release-check-v1") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "diagnostic-v1") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "check failed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\":\"skipped\"") != null);
    try f.write("main.selka", "func main( broken\n");
    const syntax = try f.run(&.{ "release", "check", ".", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, syntax.stdout, "project declarations could not be loaded") != null);
}

test "release CLI rejects usage and validates every nested pending decision" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    _ = try f.run(&.{ "release", "check", ".", "--step", "unknown" }, 2);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "ok", "--step", "decisions" }, 2);
    _ = try f.run(&.{ "release", "draft", ".", "--name", "../escape" }, 2);
    _ = try f.run(&.{ "release", "draft", ".", "--name", "bad", "--date", "2026-02-29" }, 2);
    try f.write("decisions/unreleased/nested/invalid.md", "# TODO\nChanges: main::answer\nWhy: TODO\n");
    try f.write("decisions/old/archive.md", "# Historic removed symbol\nChanges: gone::name\nWhy: TODO\n`gone::name`\n");
    const result = try f.run(&.{ "release", "check", ".", "--step", "decisions,docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "nested/invalid.md") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "archive.md") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "release: docs ok") != null);
}

test "release CLI references use whole spans skip fences and resolve unloaded standard modules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("README.md", "# Reference\n`main::answer` and `math::clamp` resolve.\n`bad::name + 1` is not a reference.\n``text::missing``\n```text\n`fenced::missing`\n```\n");
    const bad = try f.run(&.{ "release", "check", ".", "--step", "docs", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, bad.stdout, "text::missing") != null);
    try testing.expect(std.mem.indexOf(u8, bad.stdout, "fenced::missing") == null);
    try testing.expect(std.mem.indexOf(u8, bad.stdout, "\"line\":4,\"column\":3") != null);
    try f.write("README.md", "# Reference\n`main::answer` and `math::clamp` resolve.\n");
    _ = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 0);
    _ = try f.run(&.{ "doctest", "." }, 1);
}

test "release CLI skips are explicit refusals and exact filters do not duplicate prefix cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("extra_test.selka", "public func test_a() -> bool:\n    return 1 == 1\n\n\npublic func test_ab() -> bool:\n    return 2 == 2\n");
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const once = try f.run(&.{ "release", "check", ".", "--step", "tests" }, 0);
    try testing.expect(std.mem.indexOf(u8, once.stdout, "3 tests, 1 examples") != null);
    try f.write("main.cases.json", "{\"main::answer.example\":{\"skip\":\"ordinary test opt-out\"}}");
    _ = try f.run(&.{ "test", "main.selka" }, 0);
    const refused = try f.run(&.{ "release", "check", ".", "--step", "tests" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "main::answer.example skipped") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "release requires every test and example to pass") != null);
}

// spec: DOCS-RELEASE-CHECK-2
test "FR-423 the tests step runs each root through selka test and a warm run reuses every receipt" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const cold = try f.run(&.{ "release", "check", ".", "--step", "tests" }, 0);
    try testing.expect(std.mem.indexOf(u8, cold.stdout, "release: tests ok (1 tests, 1 examples") != null);
    // The second run is unchanged, so both cases answer from their receipts the
    // way an ordinary `selka test` rerun does.
    const warm = try f.run(&.{ "release", "check", ".", "--step", "tests" }, 0);
    try testing.expect(std.mem.indexOf(u8, warm.stdout, "release: tests ok (1 tests, 1 examples") != null);
    try testing.expect(std.mem.indexOf(u8, warm.stdout, "2 cached") != null);
}

test "release CLI adopts multiline comments once while preserving directives constants and interface" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "# A documented arithmetic module.\n# Uses `math::clamp` for a bounded answer.\nimport math\n\n" ++
        "# A constant keeps its ordinary comment.\npublic const LIMIT: int = 42\n\n" ++
        "# Return the clamped answer.\n#\n# >>> answer()\n# 42\n# lint: allow missing-example reason=\"kept directive\"\n" ++
        "public func answer() -> int: # A trailing header comment.\n    # This body comment stays in its body.\n    return math.clamp(LIMIT, 0, 42)\n\n" ++
        "func main() -> int:\n    return 0\n");
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    _ = try f.run(&.{ "release", "init", ".", "--adopt-comments" }, 0);
    const migrated = try f.read("main.selka");
    try testing.expect(std.mem.indexOf(u8, migrated, "import math\n\"\"\"A documented") != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "    >>> answer()\n    42") != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "# lint: allow missing-example") != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "# A constant keeps its ordinary comment.") != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "    # This body comment stays in its body.") != null);
    try testing.expect(std.mem.indexOf(u8, migrated, "# A trailing header comment.\n    \"\"\"Return the clamped answer.") != null);
    const diff = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, diff.stdout, "\"breaking\":[]") != null);
    _ = try f.run(&.{ "release", "check", ".", "--step", "docs,tests" }, 0);
    _ = try f.run(&.{ "release", "init", ".", "--adopt-comments" }, 3);
    try testing.expectEqualStrings(migrated, try f.read("main.selka"));
}

test "O3 api-diff classifies declared source changes independently of bodies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "public func part(s: str) -> str from s:\n    return s[1:3]\nfunc main() -> int:\n    return 0\n");
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    // A fresh implementation satisfies the unchanged declared upper bound.
    try f.write("main.selka", "public func part(s: str) -> str from s:\n    return copy(s[1:3])\nfunc main() -> int:\n    return 0\n");
    const body = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, body.stdout, "\"compatible\":[\"main::part\"]") != null);
    try testing.expect(std.mem.indexOf(u8, body.stdout, "\"breaking\":[]") != null);
    // Removing the final source changes borrowed-result ABI and breaks declared borrowers.
    try f.write("main.selka", "public func part(s: str) -> str:\n    return copy(s[1:3])\nfunc main() -> int:\n    return 0\n");
    const narrowed = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, narrowed.stdout, "\"breaking\":[\"main::part\"]") != null);
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    try f.write("main.selka", "public func part(s: str) -> str from s:\n    return s[1:3]\nfunc main() -> int:\n    return 0\n");
    const broadened = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, broadened.stdout, "\"breaking\":[\"main::part\"]") != null);
}

test "CLI O3 api-diff source preflight reports normal Core R4 diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    const invalid = [_][]const u8{
        "public func part(a: str) -> str from missing:",
        "public func part(own a: str) -> str from a:",
        "public func part(a: int) -> str from a:",
    };
    for (invalid) |header| {
        try f.write("main.selka", try std.mem.concat(f.a, u8, &.{
            header, "\n    return missing_body()\nfunc main() -> int:\n    return 0\n",
        }));
        const refused = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt", "--diagnostics=json" }, 1);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "\"code\":\"E_BORROW_SOURCE\"") != null);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "\"rule\":\"R4\"") != null);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "E_UNKNOWN_SYMBOL") == null);
        try testing.expect(std.mem.indexOf(u8, refused.stdout, "cannot read or classify") == null);
    }
}

test "CLI O3 declaration tools share Core source preflight despite invalid bodies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "public func part(a: str) -> str from missing:\n    return missing_body()\nfunc main() -> int:\n    return 0\n");
    const commands = [_][]const []const u8{
        &.{ "list-interfaces", "main.selka", "--diagnostics=json" },
        &.{ "list-interfaces", "main.selka", "--contracts", "--diagnostics=json" },
        &.{ "api", "main.selka", "--check", "--diagnostics=json" },
        &.{ "index-project", "main.selka", "--full", "--diagnostics=json" },
        &.{ "context", "main.selka", "--symbol=main::part", "--diagnostics=json" },
        &.{ "tests-for", "main.selka", "main::part", "--diagnostics=json" },
    };
    for (commands) |args| {
        const refused = try f.run(args, 1);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "\"code\":\"E_BORROW_SOURCE\"") != null);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "\"rule\":\"R4\"") != null);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, "E_UNKNOWN_SYMBOL") == null);
    }
    const release = try f.run(&.{ "release", "check", ".", "--step", "check", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, release.stdout, "\"code\":\"E_BORROW_SOURCE\"") != null);
    try testing.expect(std.mem.indexOf(u8, release.stdout, "\"rule\":\"R4\"") != null);
    const overview = try f.run(&.{ "overview", ".", "--check" }, 1);
    try testing.expect(std.mem.indexOf(u8, overview.stderr, "E_BORROW_SOURCE") != null);
    try testing.expect(std.mem.indexOf(u8, overview.stderr, "ownership rule R4") != null);
}

test "release CLI body changes need no decision but removals need baseline names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("main.selka", try std.mem.replaceOwned(u8, f.a, documented, "return 42", "return 40 + 2"));
    _ = try f.run(&.{ "release", "check", ".", "--step", "decisions" }, 0);
    try f.write("main.selka", try std.mem.replaceOwned(u8, f.a, documented, "public func answer", "func answer"));
    const missing = try f.run(&.{ "release", "check", ".", "--step", "decisions" }, 3);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "main::answer") != null);
    try f.write("decisions/unreleased/private.md", explanation);
    _ = try f.run(&.{ "release", "check", ".", "--step", "decisions" }, 0);
    try f.write("main.selka", "\"\"\"The command after removing the public answer.\"\"\"\n\nfunc main() -> int:\n    return 0\n");
    try f.write("README.md", "The removed API was `main::answer`.\n");
    const prose = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, prose.stdout, "E_RELEASE_REFERENCE_UNKNOWN") != null);
}

test "release CLI uses configured paths nested archives and selected test roots" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("selka.json", "{\"version\":2,\"release\":{\"entries\":[\"main.selka\"],\"exclude\":[\"excluded\"],\"baseline\":\"abi/public.txt\",\"decisions\":\"notes/choices\",\"overview\":\"notes/PROJECT.md\"}}\n");
    try f.write("unselected.selka", "func main() -> int:\n    return 'not selected'\n");
    try f.write("excluded/bad_test.selka", "not syntax\n");
    try f.write("build/bad_test.selka", "not syntax\n");
    try f.write(".hidden/bad_test.selka", "not syntax\n");
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const selected = try f.run(&.{ "release", "check", ".", "--step", "check,tests" }, 0);
    try testing.expect(std.mem.indexOf(u8, selected.stdout, "1 tests, 1 examples") != null);
    try f.write("notes/choices/unreleased/group/initial.md", explanation);
    _ = try f.run(&.{ "overview", ".", "--write" }, 0);
    _ = try f.run(&.{ "fmt", "unselected.selka", "--write" }, 0);
    _ = try f.run(&.{ "release", "cut", ".", "--name", "v1" }, 0);
    try testing.expectEqualStrings(explanation, try f.read("notes/choices/v1/group/initial.md"));
    try testing.expectEqualStrings("v1\t1\n", try f.read("release/history.txt"));
    try testing.expect(std.mem.startsWith(u8, try f.read("abi/public.txt"), "# api-diff-baseline-v2"));
    _ = try f.run(&.{ "overview", ".", "--check" }, 0);
}

test "release CLI overview requires current existing interface files and cut writes nothing when refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    _ = try f.run(&.{ "api", "main.selka", "--write" }, 0);
    try f.write("main.api", "# generated by selka api; do not edit\nmodule main\n");
    const stale = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 3);
    try testing.expect(std.mem.indexOf(u8, stale.stdout, "E_INTERFACE_FILE_STALE") != null);
    const before = try f.read("release/baseline.txt");
    _ = try f.run(&.{ "release", "cut", ".", "--name", "blocked" }, 3);
    try testing.expectEqualStrings(before, try f.read("release/baseline.txt"));
    try testing.expectEqualStrings("", try f.read("release/history.txt"));
    _ = try f.run(&.{ "api", "main.selka", "--write" }, 0);
    _ = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 0);
}

test "release CLI Markdown fences run standalone and skipped examples refuse release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    try f.write("docs/example.md", "```selka\n# doc: check\nfunc answer() -> int:\n    return 42\n```\n");
    _ = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 0);
    try f.write("docs/example.md", "```selka\n# doc: check\nimport main\n```\n");
    const standalone = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, standalone.stdout, "Markdown examples refused") != null);
    try f.write("docs/example.md", "```selka\n# doc: skip needs a service\nfunc main() -> int:\n    return 0\n```\n");
    const skipped = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, skipped.stdout, "E_RELEASE_STEP_FAILED") != null);
}

test "release CLI malformed metadata is a located usage failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const baseline = try f.read("release/baseline.txt");
    try f.write("release/baseline.txt", "bad baseline\n");
    const bad_baseline = try f.run(&.{ "release", "check", ".", "--step", "decisions" }, 2);
    try testing.expect(std.mem.indexOf(u8, bad_baseline.stderr, "malformed release/baseline.txt") != null);
    try f.write("release/baseline.txt", baseline);
    try f.write("release/history.txt", "name\tnot-a-count\n");
    const bad_history = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 2);
    try testing.expect(std.mem.indexOf(u8, bad_history.stderr, "malformed release/history.txt") != null);
}

test "release CLI doc reference diagnostics locate literal first and indented lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "\"\"\"A `missing::first` module reference.\"\"\"\n\npublic func answer() -> int:\n    \"\"\"An answer with a reference.\n    `missing::second`\n    \"\"\"\n    return 42\n");
    const result = try f.run(&.{ "release", "check", ".", "--step", "docs", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"line\":1,\"column\":7") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"line\":5,\"column\":6") != null);
}

test "release CLI docs rules block every profile without duplicating lint findings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2,\"lint\":{\"profile\":\"agent\"}}\n");
    try f.write("main.selka", "public func answer() -> int:\n    return 42\n\n\nfunc main() -> int:\n    return answer()\n");
    const agent = try f.run(&.{ "release", "check", ".", "--step", "lint,docs", "--json" }, 3);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, agent.stdout, "\"code\":\"L_UNDOCUMENTED_EXPORT\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, agent.stdout, "\"code\":\"L_MISSING_EXAMPLE\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, agent.stdout, "\"code\":\"L_UNDOCUMENTED_MODULE\""));
    try f.write("selka.json", "{\"version\":2,\"lint\":{\"profile\":\"strict\"}}\n");
    const strict = try f.run(&.{ "release", "check", ".", "--step", "lint,docs", "--json" }, 3);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, strict.stdout, "\"code\":\"L_UNDOCUMENTED_EXPORT\""));
    try f.write("selka.json", "{\"version\":2,\"lint\":{\"profile\":\"safety\"}}\n");
    const safety = try f.run(&.{ "release", "check", ".", "--step", "docs", "--json" }, 3);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, safety.stdout, "\"code\":\"L_MISSING_EXAMPLE\""));
}

test "release CLI example-only orphan api hints repair that module and hidden pending files validate" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("solo.selka", "\"\"\"An independent example library outside the entry closure.\"\"\"\n\npublic func value() -> int:\n    \"\"\"Return an example value.\n\n    >>> value()\n    7\n    \"\"\"\n    return 7\n");
    _ = try f.run(&.{ "release", "init", "." }, 0);
    _ = try f.run(&.{ "api", "main.selka", "--write" }, 0);
    const stale = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 3);
    try testing.expect(std.mem.indexOf(u8, stale.stdout, "selka api solo.selka --write") != null);
    _ = try f.run(&.{ "api", "solo.selka", "--write" }, 0);
    _ = try f.run(&.{ "release", "check", ".", "--step", "overview,tests" }, 0);
    try f.write("decisions/unreleased/.nested/invalid.md", "# TODO\nChanges: solo::value\nWhy: TODO\n");
    const pending = try f.run(&.{ "release", "check", ".", "--step", "decisions" }, 3);
    try testing.expect(std.mem.indexOf(u8, pending.stdout, ".nested/invalid.md") != null);
}

test "release CLI adoption leaves extern declarations and existing docstrings in place" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "# An extern has no body for a docstring.\npublic extern func foreign(host: Host) -> int\n\n# Keep the already documented declaration comment.\npublic func existing() -> int:\n    \"\"\"Existing docstring stays as written.\"\"\"\n    return 1\n\n# The record retains field behavior.\npublic record Box:\n    value: int = 7\n\n# The enumeration retains case behavior.\npublic enum Shade:\n    light\n    dark\n\nfunc main() -> int:\n    return 0\n");
    _ = try f.run(&.{ "release", "init", ".", "--adopt-comments" }, 0);
    const source = try f.read("main.selka");
    try testing.expect(std.mem.indexOf(u8, source, "# An extern has no body for a docstring.\npublic extern func foreign") != null);
    try testing.expect(std.mem.indexOf(u8, source, "# Keep the already documented declaration comment.") != null);
    try testing.expect(std.mem.indexOf(u8, source, "    \"\"\"The record retains field behavior.\"\"\"") != null);
    try testing.expect(std.mem.indexOf(u8, source, "    \"\"\"The enumeration retains case behavior.\"\"\"") != null);
}

test "release CLI check refuses holes and direct source errors stay findings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "func main() -> int:\n    return todo[int]()\n");
    const result = try f.run(&.{ "release", "check", ".", "--step", "check" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "release: check FAILED") != null);
}

test "release CLI InvalidReleasePaths rejects overlapping metadata paths before writing files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("selka.json", "{\"version\":2,\"release\":{\"overview\":\"release/baseline.txt\"}}\n");
    _ = try f.run(&.{ "release", "init", "." }, 2);
    try testing.expectError(error.FileNotFound, f.dir.statFile(testing.io, "release/baseline.txt", .{}));
    try f.write("selka.json", "{\"version\":2,\"release\":{\"baseline\":\"decisions/unreleased/baseline.txt\"}}\n");
    _ = try f.run(&.{ "release", "init", "." }, 2);
    try testing.expectError(error.FileNotFound, f.dir.statFile(testing.io, "decisions/unreleased/baseline.txt", .{}));
    try f.write("selka.json", "{\"version\":2,\"release\":{\"overview\":\"main.selka\"}}\n");
    const before = try f.read("main.selka");
    _ = try f.run(&.{ "release", "init", "." }, 2);
    try testing.expectEqualStrings(before, try f.read("main.selka"));
}

test "release CLI CommentDelimiterCollision restores earlier adopted sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "import a\nimport b\n\nfunc main() -> int:\n    return a.value() + b.value()\n");
    const before = "# A comment that will be adopted first.\npublic func value() -> int:\n    return 1\n";
    try f.write("a.selka", before);
    try f.write("b.selka", "# Both delimiters: \"\"\" and '''.\npublic func value() -> int:\n    return 2\n");
    const result = try f.run(&.{ "release", "init", ".", "--adopt-comments" }, 2);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "CommentDelimiterCollision") != null);
    try testing.expectEqualStrings(before, try f.read("a.selka"));
    try testing.expectError(error.FileNotFound, f.dir.statFile(testing.io, "release/baseline.txt", .{}));
}

test "release CLI private boolean tests aliases and marked cases share ordinary discovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("private_test.selka", "type Truth = bool\n\nfunc test_private() -> Truth:\n    return 1 == 1\n\n@test\nfunc marked() -> bool:\n    return 2 == 2\n");
    const ordinary = try f.run(&.{ "test", "private_test.selka", "--json" }, 0);
    const inventory = try std.json.parseFromSlice(std.json.Value, f.a, ordinary.stdout, .{});
    const cases = inventory.value.object.get("tests").?.array.items;
    try testing.expectEqual(@as(usize, 2), cases.len);
    try testing.expectEqualStrings("private_test::marked", cases[0].object.get("name").?.string);
    try testing.expectEqualStrings("private_test::test_private", cases[1].object.get("name").?.string);
    const result = try f.run(&.{ "release", "check", ".", "--step", "tests" }, 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "3 tests, 1 examples") != null);
    try f.write("private_test.selka", "func test_invalid() -> Absent:\n    return True\n");
    const invalid = try f.run(&.{ "release", "check", ".", "--step", "tests", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, invalid.stdout, "E_RELEASE_STEP_FAILED") != null);
}

test "release CLI references honor odd and even opening backslash escapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("README.md", "An escaped \\`missing::odd` span.\nAn active \\\\`missing::even` span.\n");
    const result = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "missing::odd") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "missing::even") != null);
}

test "release CLI configured docs metadata keeps archived references and examples historical" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("selka.json", "{\"version\":2,\"release\":{\"decisions\":\"docs/choices\",\"overview\":\"docs/SUMMARY.md\"}}\n");
    try f.write("docs/choices/old/removed.md", "# Historical choice\nChanges: removed::declaration\nWhy: Historical text can retain `removed::declaration`.\n\n```selka\n# doc: check\nfunc bad() -> int:\n    return False\n```\n");
    _ = try f.run(&.{ "release", "init", "." }, 0);
    _ = try f.run(&.{ "release", "check", ".", "--step", "docs,decisions,overview" }, 0);
    try f.write("docs/choices/unreleased/current.md", explanation ++ "\nCurrent prose `unknown::current`.\n");
    const pending = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, pending.stdout, "unknown::current") != null);
    try f.write("docs/choices/unreleased/current.md", explanation);
    try f.write("docs/handwritten.md", "Current prose `unknown::handwritten`.\n");
    const handwritten = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, handwritten.stdout, "unknown::handwritten") != null);
}

test "release CLI transcript code and literal expected output are not prose references" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    const source = "\"\"\"Library illustrating literal example output.\"\"\"\n\npublic func value() -> int:\n    \"\"\"Return a useful example value.\n\n    >>> \"`unknown::literal`\"\n    '`unknown::literal`'\n\n    {s}\n    \"\"\"\n    return 1\n";
    try f.write("main.selka", try std.fmt.allocPrint(f.a, source, .{"Later prose references `main::value`."}));
    _ = try f.run(&.{ "release", "check", ".", "--step", "tests,docs" }, 0);
    try f.write("main.selka", try std.fmt.allocPrint(f.a, source, .{"Later prose references `unknown::prose`."}));
    const result = try f.run(&.{ "release", "check", ".", "--step", "docs" }, 3);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "unknown::prose") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "unknown::literal") == null);
}

test "FR-413 release check and init name the file and position of a source error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("repro_helper.selka", "def old_syntax(:\nfunc test_old() -> bool:\n    return True\n");
    const check = try f.run(&.{ "release", "check", "." }, 3);
    // The compiler's own code, file and position replace `declaration loading failed:
    // SourceError`; the check step is still the one that failed.
    try testing.expect(std.mem.indexOf(u8, check.stdout, "repro_helper.selka:1:") != null);
    try testing.expect(std.mem.indexOf(u8, check.stdout, "error[E_SYNTAX]") != null);
    try testing.expect(std.mem.indexOf(u8, check.stdout, "declaration loading failed: SourceError") == null);
    try testing.expect(std.mem.indexOf(u8, check.stdout, "release: check FAILED") != null);
    const init = try f.run(&.{ "release", "init", "." }, 3);
    try testing.expect(std.mem.indexOf(u8, init.stdout, "repro_helper.selka:1:") != null);
    const json = try f.run(&.{ "release", "check", ".", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, json.stdout, "\"code\":\"E_SYNTAX\"") != null);
    try testing.expect(std.mem.indexOf(u8, json.stdout, "\"path\":\"repro_helper.selka\"") != null);
}

test "release CLI adoption needs adjacency skips banners prints every adoption and previews dry runs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "# =============================================================================\n" ++
        "# Arithmetic helpers\n" ++
        "# =============================================================================\n" ++
        "public func banner() -> int:\n" ++
        "    return 1\n\n\n" ++
        "# A separate comment.\n\n" ++
        "# Adjacent documentation.\n" ++
        "public func adjacent() -> int:\n" ++
        "    return 2\n\n\n" ++
        "# Another adjacent block.\n" ++
        "public record Box:\n" ++
        "    value: int = 7\n\n\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
    const before = try f.read("main.selka");
    const dry = try f.run(&.{ "release", "init", ".", "--adopt-comments", "--dry-run" }, 0);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, dry.stdout, "adopt-comments: "));
    try testing.expect(std.mem.indexOf(u8, dry.stdout, "main::adjacent") != null);
    try testing.expect(std.mem.indexOf(u8, dry.stdout, "main::Box") != null);
    try testing.expect(std.mem.indexOf(u8, dry.stdout, "main::banner") == null);
    try testing.expectEqualStrings(before, try f.read("main.selka"));
    try testing.expectError(error.FileNotFound, f.dir.statFile(testing.io, "release/baseline.txt", .{}));
    const applied = try f.run(&.{ "release", "init", ".", "--adopt-comments" }, 0);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, applied.stdout, "adopt-comments: "));
    const adopted = try f.read("main.selka");
    try testing.expect(std.mem.indexOf(u8, adopted, "    \"\"\"Adjacent documentation.\"\"\"") != null);
    try testing.expect(std.mem.indexOf(u8, adopted, "    \"\"\"Another adjacent block.\"\"\"") != null);
    try testing.expect(std.mem.indexOf(u8, adopted, "# A separate comment.") != null);
    try testing.expect(std.mem.indexOf(u8, adopted, "# =============================================================================") != null);
    try testing.expect(std.mem.indexOf(u8, adopted, "\"\"\"Arithmetic helpers") == null);
}

test "release CLI format failure names release.exclude and an exclusion skips an intentional repro" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    try f.write("repros/crash.selka", "func main() -> int:\n    return 1+2\n");
    const refused = try f.run(&.{ "release", "check", ".", "--step", "format" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "repros/crash.selka") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "release.exclude") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "selka fmt repros/crash.selka --write") != null);
    try f.write("selka.json", "{\"version\":2,\"release\":{\"exclude\":[\"repros/\"]}}\n");
    const excluded = try f.run(&.{ "release", "check", ".", "--step", "format" }, 0);
    try testing.expect(std.mem.indexOf(u8, excluded.stdout, "release: format ok") != null);
}

test "release CLI file-level waivers cover several declarations in the lint and docs steps" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "\"\"\"A fixture module with reasoned file-level waivers.\"\"\"\n\n\n" ++
        "func first() -> int:\n    return 1\n\n\n" ++
        "func second() -> int:\n    return 2\n\n\n" ++
        "public func answer() -> int:\n    \"\"\"Return the fixture answer.\"\"\"\n    return 42\n\n\n" ++
        "func main() -> int:\n    return 0\n");
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const refused = try f.run(&.{ "release", "check", ".", "--step", "lint,docs", "--json" }, 3);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "\"code\":\"L_DEAD_PRIVATE\"") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, "\"code\":\"L_MISSING_EXAMPLE\"") != null);
    try f.write("main.selka", "\"\"\"A fixture module with reasoned file-level waivers.\"\"\"\n\n\n" ++
        "# lint: allow-file dead-private reason=\"the fixture handlers are exercised end to end\"\n" ++
        "func first() -> int:\n    return 1\n\n\n" ++
        "func second() -> int:\n    return 2\n\n\n" ++
        "# lint: allow-file missing-example reason=\"covered by the fixture's end-to-end run\"\n" ++
        "public func answer() -> int:\n    \"\"\"Return the fixture answer.\"\"\"\n    return 42\n\n\n" ++
        "func main() -> int:\n    return 0\n");
    _ = try f.run(&.{ "overview", ".", "--write" }, 0);
    const covered = try f.run(&.{ "release", "check", ".", "--step", "lint,docs" }, 0);
    try testing.expect(std.mem.indexOf(u8, covered.stdout, "L_DEAD_PRIVATE") == null);
    try testing.expect(std.mem.indexOf(u8, covered.stdout, "L_MISSING_EXAMPLE") == null);
}

test "release CLI long-example is a warning that never refuses a release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    const line = try arena.allocator().alloc(u8, 130);
    @memset(line, 'x');
    try f.write("main.selka", try std.fmt.allocPrint(arena.allocator(), "\"\"\"A module with one long example.\"\"\"\n\n\n" ++
        "public func dump() -> str:\n" ++
        "    \"\"\"Return a long value.\n\n    >>> dump()\n    {s}\n    \"\"\"\n" ++
        "    return \"short\"\n\n\n" ++
        "public func test_dump() -> bool:\n    return dump() == \"short\"\n\n\n" ++
        "func main() -> int:\n    return 0\n", .{line}));
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const result = try f.run(&.{ "release", "check", ".", "--step", "lint", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"code\":\"L_LONG_EXAMPLE\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"severity\":\"warning\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\":\"releasable\"") != null);
}

test "release CLI overview step reports a reference-only edit as stale" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.project();
    _ = try f.run(&.{ "release", "init", "." }, 0);
    const edited = try std.mem.replaceOwned(u8, f.a, documented, "    42\n    \"\"\"\n    return 42", "    42\n\n    The stable answer stays the same.\n    \"\"\"\n    return 42");
    try f.write("main.selka", edited);
    const stale = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 3);
    try testing.expect(std.mem.indexOf(u8, stale.stdout, "E_RELEASE_OVERVIEW_STALE") != null);
    try testing.expect(std.mem.indexOf(u8, stale.stdout, "reference/main.md") != null);
    _ = try f.run(&.{ "overview", ".", "--write" }, 0);
    const green = try f.run(&.{ "release", "check", ".", "--step", "overview" }, 0);
    try testing.expect(std.mem.indexOf(u8, green.stdout, "release: overview ok") != null);
    try testing.expect(std.mem.indexOf(u8, try f.read("reference/main.md"), "The stable answer stays the same.") != null);
}

test "a release build fails a @vectorize loop LLVM cannot vectorize, and accepts one it vectorizes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    // The blocked loop appends to a list, a call LLVM cannot vectorize; the vectorized loop
    // reads a list in order, which LLVM vectorizes as a reduction.
    const blocked_source =
        \\func grow(n: int) -> int:
        \\    mut xs: int[] = []
        \\    @vectorize
        \\    for i in range(n):
        \\        append(mut xs, i * 3 % 7)
        \\    return len(xs)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, grow(100000))
        \\    return 0
    ;
    const vectorized_source =
        \\func total(n: int) -> int:
        \\    mut acc = 0
        \\    @vectorize
        \\    for i in range(n):
        \\        acc = acc + i * 3 % 7
        \\    return acc
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, total(100000))
        \\    return 0
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "blocked.selka", .data = blocked_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "vectorized.selka", .data = vectorized_source });
    try requireRelease();
    const blocked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "build", "blocked.selka", "-o", "blocked", "--release" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(blocked.stdout);
    defer testing.allocator.free(blocked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, blocked.term);
    try testing.expect(std.mem.indexOf(u8, blocked.stdout, "error[E_VECTORIZE_FAILED]") != null or std.mem.indexOf(u8, blocked.stderr, "error[E_VECTORIZE_FAILED]") != null);
    const accepted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "build", "vectorized.selka", "-o", "vectorized", "--release" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expectEqualStrings("", accepted.stderr);
}

// spec: VECTORIZE-CHECK-FACTS-1
test "an instrumented --verify-facts release build does not check its @vectorize loops" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const blocked_source =
        \\func grow(n: int) -> int:
        \\    mut xs: int[] = []
        \\    @vectorize
        \\    for i in range(n):
        \\        append(mut xs, i * 3 % 7)
        \\    return len(xs)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, grow(100000))
        \\    return 0
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "blocked.selka", .data = blocked_source });
    try requireRelease();
    const verified = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "build", "blocked.selka", "-o", "blocked", "--release", "--verify-facts" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(verified.stdout);
    defer testing.allocator.free(verified.stderr);
    try testing.expect(std.mem.indexOf(u8, verified.stderr, "E_VECTORIZE_FAILED") == null);
    try testing.expect(std.mem.indexOf(u8, verified.stdout, "E_VECTORIZE_FAILED") == null);
}

test "F4 removing from breaks the interface and a declared borrowing caller" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "public func part(s: str) -> str from s:\n" ++
        "    return s\n" ++
        "func caller(s: str) -> str from s:\n" ++
        "    return part(s)\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
    _ = try f.run(&.{ "check", "main.selka" }, 0);
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    try f.write("main.selka", "public func part(s: str) -> str:\n" ++
        "    return copy(s)\n" ++
        "func caller(s: str) -> str from s:\n" ++
        "    return part(s)\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
    const changed_contract = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expect(std.mem.indexOf(u8, changed_contract.stdout, "\"breaking\":[\"main::part\"]") != null);
    const caller = try f.run(&.{ "check", "main.selka", "--diagnostics=json" }, 1);
    try testing.expect(std.mem.indexOf(u8, caller.stderr, "\"code\":\"E_BORROW_MIXED\"") != null);
    try testing.expect(std.mem.indexOf(u8, caller.stderr, "\"rule\":\"R5\"") != null);
}
test "F4 pre-source v1 baseline reports one actionable upgrade instead of declaration breaks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "public func size(a: int[]) -> int:\n" ++
        "    return len(a)\n" ++
        "\n" ++
        "public func name() -> str:\n" ++
        "    return \"x\"\n" ++
        "\n" ++
        "func main() -> int:\n" ++
        "    return 0\n");
    try f.write("before.txt", "# api-diff-baseline-v1\n" ++
        "3740c816f804a8bf9d3311659133dc53bc024bbec9242b48ae29d5c6c1655f5f\tmain::main\tfunction\t55311fd55deccdaf138741a4f" ++
        "ac096d7b911ade7bbb42dad54e5c1a5114a5761\t3a655b89bbc1d7549210f73aa3d9374159860a7f0f0d8a18fbc965bddd537e26\n" ++
        "fbafbdf9dd232fe2a1cfc3b4768e36d77cd77e8606c2ba0ee08502a414d0c86a\tmain::name\tfunction\t8e7889ae5d584f2882e9c4a20" ++
        "11d40395abceadb5a4fb7e72b495cfffc183d08\t8d2980aff8ef36813785bb5b9c6b0dd1848f618ae7f9e386c68e603f4ff33d4f\n" ++
        "92efd742e6bf34457ef961a5fcd50615bfc3013fe3b67099cb97119c0ffea360\tmain::size\tfunction\te7e8ab57effe9824507f2254b" ++
        "47e5a14311ebb8636e85b130fa89517efeed746\tb91a207205730720dd04db5396601f58263a3efa3357a500bf178c449479c73a\n");
    const original = try f.read("before.txt");
    // A legacy baseline is a tooling migration refusal, not a per-declaration API verdict.
    const legacy = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt" }, 2);
    try testing.expect(std.mem.indexOf(u8, legacy.stderr, "predates declared borrow sources") != null);
    try testing.expect(std.mem.indexOf(u8, legacy.stderr, "--write=before.txt") != null);
    try testing.expect(std.mem.indexOf(u8, legacy.stdout, "main::size") == null);
    try testing.expect(std.mem.indexOf(u8, legacy.stdout, "main::name") == null);
    const message = "api-diff: baseline predates declared borrow sources; re-record it with: selka api-diff main.selka --write=before.txt\n";
    try testing.expectEqualStrings(message, legacy.stderr);
    try testing.expectEqualStrings("", legacy.stdout);
    try testing.expectEqualStrings(original, try f.read("before.txt"));
    const json = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 2);
    try testing.expectEqualStrings(message, json.stderr);
    try testing.expectEqualStrings("", json.stdout);
    const diagnostic = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json", "--diagnostics=json" }, 2);
    const record = try std.json.parseFromSlice(std.json.Value, f.a, diagnostic.stderr, .{});
    defer record.deinit();
    try testing.expectEqualStrings("diagnostic-v1", record.value.object.get("version").?.string);
    try testing.expectEqualStrings("message", record.value.object.get("kind").?.string);
    try testing.expectEqualStrings(message, record.value.object.get("message").?.string);
    try testing.expectEqualStrings("", diagnostic.stdout);
    try testing.expectEqualStrings(original, try f.read("before.txt"));
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    const replaced = try f.read("before.txt");
    try testing.expect(std.mem.startsWith(u8, replaced, "# api-diff-baseline-v2\n"));
    const current = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expectEqualStrings("{\"version\":\"api-diff-v1\",\"additive\":[],\"compatible\":[],\"breaking\":[],\"unchanged\":3}\n", current.stdout);
}

test "F4 api-diff source reorder is neutral while nonempty narrowing is compatible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    const both = "public func part(a: str, b: str) -> str from a, b:\n    return a\nfunc main() -> int:\n    return 0\n";
    try f.write("main.selka", both);
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=before.txt" }, 0);
    try f.write("main.selka", "public func part(a: str, b: str) -> str from b, a:\n    return a\nfunc main() -> int:\n    return 0\n");
    const reordered = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expectEqualStrings("{\"version\":\"api-diff-v1\",\"additive\":[],\"compatible\":[],\"breaking\":[],\"unchanged\":2}\n", reordered.stdout);
    try f.write("main.selka", "public func part(a: str, b: str) -> str from a:\n    return a\nfunc main() -> int:\n    return 0\n");
    const narrowed = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 0);
    try testing.expectEqualStrings("{\"version\":\"api-diff-v1\",\"additive\":[],\"compatible\":[\"main::part\"],\"breaking\":[],\"unchanged\":1}\n", narrowed.stdout);
    _ = try f.run(&.{ "api-diff", "main.selka", "--write=one-source.txt" }, 0);
    try f.write("main.selka", both);
    const added = try f.run(&.{ "api-diff", "main.selka", "--against=one-source.txt", "--json" }, 0);
    try testing.expectEqualStrings("{\"version\":\"api-diff-v1\",\"additive\":[],\"compatible\":[],\"breaking\":[\"main::part\"],\"unchanged\":1}\n", added.stdout);
}

test "F4 api-diff upgrade command quotes baseline paths and leaves them unchanged" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "func main() -> int:\n    return 0\n");
    const baseline = "# api-diff-baseline-v1\nmain\tmain::main\tfunction\tinterface\tbody\n";
    try f.write("baseline files/before's.txt", baseline);
    const legacy = try f.run(&.{ "api-diff", "main.selka", "--against=baseline files/before's.txt" }, 2);
    try testing.expectEqualStrings("api-diff: baseline predates declared borrow sources; re-record it with: selka api-diff main.selka '--write=baseline files/before'\\''s.txt'\n", legacy.stderr);
    try testing.expectEqualStrings("", legacy.stdout);
    try testing.expectEqualStrings(baseline, try f.read("baseline files/before's.txt"));
}

test "F4 api-diff malformed and mixed-version baselines retain input errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const f: Fixture = .{ .a = arena.allocator(), .dir = temporary.dir };
    try f.write("selka.json", "{\"version\":2}\n");
    try f.write("main.selka", "func main() -> int:\n    return 0\n");
    const invalid = [_][]const u8{
        "# api-diff-baseline-v1\nwrong-column-count\n",
        "# api-diff-baseline-v1\n# api-diff-baseline-v2\nmain\tmain::main\tfunction\tinterface\tbody\tother\tfresh\n",
        "# api-diff-baseline-v2\n# api-diff-baseline-v1\nmain\tmain::main\tfunction\tinterface\tbody\tother\tfresh\n",
        "# api-diff-baseline-v3\nmain\tmain::main\tfunction\tinterface\tbody\n",
    };
    for (invalid) |bytes| {
        try f.write("before.txt", bytes);
        const malformed = try f.run(&.{ "api-diff", "main.selka", "--against=before.txt", "--json" }, 2);
        try testing.expectEqualStrings("api-diff: cannot read or classify the baseline\n", malformed.stderr);
        try testing.expectEqualStrings("", malformed.stdout);
        try testing.expectEqualStrings(bytes, try f.read("before.txt"));
    }
}
