//! `selka lint` declaration waivers: `@allow("rule", reason="...")` produces a
//! waiver keyed to its declaration, covers that declaration's findings, and
//! still records a missing reason for the blocking `L_WAIVER_REASON` rule.
//!
//! It also drives `change-without-test` end to end against a real temp git
//! repository: commit a fixture, edit a body, and read the verdict the public
//! `lint.evaluate` entry returns (never `lint.run`, whose stdout summary would
//! collide with the test runner's own protocol pipe).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");
const quality = @import("quality.zig");
const typed = @import("typed.zig");

const lint = language.lint;

const marked_dead_private =
    \\@allow("dead-private", reason="kept for the follow-up change")
    \\func helper() -> int:
    \\    return 1
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const unreasoned_dead_private =
    \\@allow("dead-private")
    \\func helper() -> int:
    \\    return 1
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// Build the `@allow` waivers one program's attributes contribute.
fn waiversFor(allocator: std.mem.Allocator, text: []const u8) ![]language.lint.Waiver {
    var compilation = try language.Compilation.init(allocator, "attrs.selka", text);
    defer compilation.deinit();
    try compilation.parse();
    var waivers: std.ArrayList(language.lint.Waiver) = .empty;
    try language.lint.scanAttributeWaivers(allocator, compilation.src, compilation.syntax.?, &waivers);
    return waivers.toOwnedSlice(allocator);
}

// spec: ATTR-4
test "an @allow attribute waives its declaration finding and records a missing reason" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const waivers = try waiversFor(scratch, marked_dead_private);
    try t.expectEqual(@as(usize, 1), waivers.len);
    try t.expectEqualStrings("dead-private", waivers[0].rule);
    try t.expect(waivers[0].has_reason);

    var compilation = try language.Compilation.init(scratch, "attrs.selka", marked_dead_private);
    defer compilation.deinit();
    try compilation.parse();
    const span = compilation.syntax.?.functions[0].name;
    const finding: language.lint.Finding = .{ .code = "L_DEAD_PRIVATE", .rule = "dead-private", .span = span, .message = "private helper has no call site" };
    try t.expect(language.lint.isWaived(waivers, finding, compilation.src));

    const missing = try waiversFor(scratch, unreasoned_dead_private);
    try t.expectEqual(@as(usize, 1), missing.len);
    try t.expect(!missing[0].has_reason);
}

/// Committed fixture: a private helper with one direct test and a main.
const initial_fixture =
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
    \\func main() -> int:
    \\    return 0
;

/// The helper body changed; its test did not.
const changed_helper =
    \\
    \\
    \\func helper(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// Both the helper and the test that calls it changed.
const changed_helper_and_test =
    \\
    \\
    \\func helper(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(2) == 4
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// The helper changed and no test calls it at all.
const changed_helper_uncalled =
    \\
    \\
    \\func helper(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// The helper changed under a directive-comment waiver.
const waived_comment =
    \\
    \\
    \\# lint: allow change-without-test reason="exercised by the integration suite"
    \\func helper(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// The helper changed under an `@allow` attribute waiver.
const waived_attribute =
    \\
    \\
    \\@allow("change-without-test", reason="exercised by the integration suite")
    \\func helper(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// A `selka.json` that exempts the fixture helper from test coverage.
const exemption_config =
    \\{"version":2,"lint":{"rules":{"test-coverage":{"exempt":[{"name":"main::helper","reason":"exercised by the integration suite"}]}}}}
;

/// Switches one fixture run hands to the public `lint.run` entry.
const Run = struct {
    gate: bool = false,
    against: ?[]const u8 = null,
    accept: bool = false,
    config: ?*const lint_config.Config = null,
    /// Report as if the linted entry were itself a standard-library module.
    entry_stdlib: bool = false,
    /// `cost --sites` rows for `L_ALLOC_IN_LOOP`, as the CLI hands them over.
    sites: []const lint.AllocationSite = &.{},
    /// The module the run loads as its entry; its file is `NAME.selka` under the root.
    module: []const u8 = "main",
};

/// Write the fixture entry file over the repository's `main.selka`.
fn writeFixture(temp: *std.testing.TmpDir, bytes: []const u8) !void {
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = bytes });
}

/// Write one fixture module, `NAME.selka`, under the repository root.
fn writeModule(temp: *std.testing.TmpDir, name: []const u8, bytes: []const u8) !void {
    const file = try std.fmt.allocPrint(t.allocator, "{s}.selka", .{name});
    defer t.allocator.free(file);
    try temp.dir.writeFile(t.io, .{ .sub_path = file, .data = bytes });
}

/// Run one git subcommand in `root`, failing unless it exits zero.
fn gitOk(allocator: std.mem.Allocator, root: []const u8, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "-C", root });
    try argv.appendSlice(allocator, args);
    const result = try std.process.run(allocator, t.io, .{ .argv = argv.items });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    const code: u8 = switch (result.term) {
        .exited => |status| status,
        else => 255,
    };
    try t.expectEqual(@as(u8, 0), code);
}

/// `git init` plus one commit so `HEAD` names the fixture as committed.
fn commitFixture(root: []const u8, allocator: std.mem.Allocator) !void {
    try gitOk(allocator, root, &.{ "init", "-q" });
    try gitOk(allocator, root, &.{ "add", "main.selka" });
    try gitOk(allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "fixture" });
}

/// Append the `change-without-test` findings for an already-loaded project,
/// deriving the same facts the public `lint.run` entry publishes.
fn collectChangeFindings(scratch: std.mem.Allocator, proj: *project.Project, root: []const u8, reference: []const u8, config: ?*const lint_config.Config, findings: *std.ArrayList(lint.Finding)) !void {
    var index = try interfaces.build(proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const program = compilation.program.?;
    const exports = try compilation.exportRoots(scratch);
    const test_ids = try compilation.testRoots(scratch);
    var analysis = try quality.analyzeWithExports(scratch, program, compilation.src, compilation.syntax, .{}, exports);
    defer analysis.deinit();
    const test_flags = try scratch.alloc(bool, program.functions.len);
    const export_flags = try scratch.alloc(bool, program.functions.len);
    @memset(test_flags, false);
    @memset(export_flags, false);
    var tests: std.ArrayList(typed.FunctionId) = .empty;
    for (test_ids) |id| {
        const function = program.functions[@backingInt(id)];
        if (!std.mem.startsWith(u8, lint.localName(function.name), "test_")) continue;
        test_flags[@backingInt(id)] = true;
        try tests.append(scratch, id);
    }
    for (exports) |id| export_flags[@backingInt(id)] = true;
    const facts: lint.Facts = .{
        .program = program,
        .src = compilation.src,
        .syntax = compilation.syntax,
        .functions = analysis.functions,
        .roots = .{ .exports = exports, .tests = tests.items, .test_flags = test_flags, .export_flags = export_flags },
    };
    try lint.appendChangeWithoutTestFindings(.{
        .memory = scratch,
        .facts = &facts,
        .index = &index,
        .config = config,
        .scope = .{ .io = t.io, .repo_root = root, .reference = reference },
    }, findings);
}

/// Evaluate the whole lint pipeline for the fixture rooted at `root` without
/// writing to stdout, which is the test runner's own protocol pipe.
fn evaluateFixture(scratch: std.mem.Allocator, root: []const u8, run: Run) !lint.Outcome {
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), run.module, .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = if (run.entry_stdlib)
        try scratch.dupe(u8, "@stdlib/lists.selka")
    else
        try std.fs.path.join(scratch, &.{ root, try std.fmt.allocPrint(scratch, "{s}.selka", .{run.module}) });
    return lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = run.config,
        .entry_path = entry,
        .options = .{ .gate = run.gate, .against = run.against, .accept = run.accept },
        .data = .{ .diagnostics = .text, .sites = run.sites },
    }, scratch);
}

// spec: CHANGE-WITHOUT-TEST-1
test "change-without-test blocks a changed helper and clears when its test changes" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, initial_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, changed_helper);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const flagged = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 1), flagged.blocking);
    try t.expectEqualStrings("L_CHANGE_WITHOUT_TEST", flagged.findings[0].code);

    // Without `--against` the rule judges nothing, even under `--gate`.
    const silent = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), silent.blocking);

    // Extending the direct test in the same diff clears the finding.
    try writeFixture(&temp, changed_helper_and_test);
    const cleared = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 0), cleared.blocking);
}

// spec-case: CHANGE-WITHOUT-TEST-1
test "change-without-test honors directive-comment and attribute waivers" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, initial_fixture);
    try commitFixture(root, t.allocator);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    try writeFixture(&temp, waived_comment);
    const comment = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 0), comment.blocking);
    try writeFixture(&temp, waived_attribute);
    const attribute = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 0), attribute.blocking);
}

// spec-case: CHANGE-WITHOUT-TEST-1
test "change-without-test honors the configured test-coverage exemption" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, initial_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, changed_helper);

    var failure: lint_config.Failure = .{};
    var config = try lint_config.parseConfig(t.allocator, exemption_config, &failure);
    defer config.deinit(t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const exempt = try evaluateFixture(arena.allocator(), root, .{ .gate = true, .against = "HEAD", .config = &config });
    try t.expectEqual(@as(usize, 0), exempt.blocking);
}

// spec-case: CHANGE-WITHOUT-TEST-1
test "change-without-test ignores a baseline row and is never adopted" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, initial_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, changed_helper);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // A hand-written baseline row must not silence a change-time finding.
    try temp.dir.createDirPath(t.io, ".selka/lint");
    try temp.dir.writeFile(t.io, .{ .sub_path = ".selka/lint/baseline-change-without-test.txt", .data = "main|main::helper\n" });
    const suppressed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 1), suppressed.blocking);

    // `--accept` must not create a baseline for the rule either.
    try temp.dir.deleteFile(t.io, ".selka/lint/baseline-change-without-test.txt");
    _ = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD", .accept = true });
    try t.expectError(error.FileNotFound, temp.dir.access(t.io, ".selka/lint/baseline-change-without-test.txt", .{}));
}

// spec-case: CHANGE-WITHOUT-TEST-1
test "change-without-test names the tests that call a changed helper" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, initial_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, changed_helper);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});

    var findings: std.ArrayList(lint.Finding) = .empty;
    try collectChangeFindings(scratch, &proj, root, "HEAD", null, &findings);
    try t.expectEqual(@as(usize, 1), findings.items.len);
    try t.expectEqualStrings("L_CHANGE_WITHOUT_TEST", findings.items[0].code);
    try t.expectEqualStrings("change-without-test", findings.items[0].rule);
    try t.expect(findings.items[0].related != null);
    try t.expect(std.mem.indexOf(u8, findings.items[0].related.?.message, "main::test_helper") != null);

    // A changed helper no test reaches says so explicitly.
    try writeFixture(&temp, changed_helper_uncalled);
    var proj2 = project.Project.init(scratch);
    defer proj2.deinit();
    try proj2.load(files.provider(), "main", .{});
    var orphans: std.ArrayList(lint.Finding) = .empty;
    try collectChangeFindings(scratch, &proj2, root, "HEAD", null, &orphans);
    try t.expectEqual(@as(usize, 1), orphans.items.len);
    try t.expect(std.mem.indexOf(u8, orphans.items[0].related.?.message, "no test calls") != null);
}

/// Section 9 advisory fixture: one module that trips every shipped report rule.
const advisory_fixture =
    \\
    \\
    \\record Big:
    \\    a: int
    \\    b: int
    \\    c: int
    \\    d: int
    \\    e: int
    \\    f: int
    \\    g: int
    \\    h: int
    \\
    \\
    \\func repeat(value: int) -> int:
    \\    return value + 7 + 7 + 7
    \\
    \\
    \\func pair(left: int, right: int) -> int:
    \\    return left + right
    \\
    \\
    \\func alpha(value: int) -> int:
    \\    mut total = value + 3
    \\    total += 4
    \\    return total
    \\
    \\
    \\func beta(value: int) -> int:
    \\    mut total = value + 3
    \\    total += 4
    \\    return total
    \\
    \\
    \\func gate(a: bool, b: bool, c: bool, d: bool) -> bool:
    \\    if a and b and c and d and a:
    \\        return True
    \\    return False
    \\
    \\
    \\func vague() -> int:
    \\    mut tmp = 1
    \\    return tmp
    \\
    \\
    \\func printer(out: Stream) -> int:
    \\    print(out, "hello")
    \\    return 0
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// A module with constants of every kind the rules judge: read, unread and oddly spelled.
const constants_fixture =
    \\const LIMIT: int = 10
    \\const GREETING: str = "hi"
    \\const UNUSED: int = 7
    \\const BadName: int = 3
    \\const lower: int = 5
    \\
    \\
    \\func over(n: int) -> bool:
    \\    return n > LIMIT and n < LIMIT + 5 and n != LIMIT
    \\
    \\
    \\func main() -> int:
    \\    if over(11):
    \\        return len(GREETING) + lower + BadName
    \\    return 0
;

/// How many evaluated findings carry `code` and mention `needle` in their message.
fn countFindings(outcome: lint.Outcome, code: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (std.mem.eql(u8, finding.code, code) and std.mem.indexOf(u8, finding.message, needle) != null) count += 1;
    }
    return count;
}

// spec: LINT-CONSTANTS-1
test "lint judges a module constant as a constant: a read one is live and UPPER_CASE is its spelling" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, constants_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", ""));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", "UNUSED"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_NAMING", ""));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_NAMING", "constant BadName"));
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_REPEATED_LITERAL", ""));
}

/// Private functions a module constant's initializer calls, directly or through the table builder that calls them, and one nothing calls.
const constant_callee_fixture =
    \\import buffers
    \\
    \\const TRIPLED: int = triple(3)
    \\const TABLE: bytes = squares(4)
    \\
    \\
    \\func triple(n: int) -> int:
    \\    return n * 3
    \\
    \\
    \\func square(n: int) -> int:
    \\    return n * n
    \\
    \\
    \\func squares(count: int) -> bytes:
    \\    mut table = buffers.empty()
    \\    for index in range(count):
    \\        _ = buffers.append_byte(mut table, square(index))
    \\    return bytes(table)
    \\
    \\
    \\func unused_builder(n: int) -> int:
    \\    return n
    \\
    \\
    \\func main() -> int:
    \\    return TRIPLED + len(TABLE)
;

// spec: LINT-CONSTANTS-1
test "lint counts a call from a constant's initializer as a call site of the private function it evaluates" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, constant_callee_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", ""));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", "unused_builder"));
}

/// A function passed as a value is used; one with no reference at all is not.
const value_reference_fixture =
    \\func by_key(value: int) -> int:
    \\    return value
    \\
    \\
    \\func never_used(value: int) -> int:
    \\    return value
    \\
    \\
    \\public func sorted_values() -> int[]:
    \\    mut values = [2, 1]
    \\    sort(mut values, key=by_key)
    \\    return values
    \\
    \\
    \\public func test_sorted() -> bool:
    \\    return sorted_values()[0] == 1
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: LINT-REACH-2
test "FR-420 a function passed as a value counts as a use for dead-private" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, value_reference_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", ""));
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_DEAD_PRIVATE", "by_key"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", "never_used"));
}

/// A private constant and an exported function used only by an example, plus a
/// private helper nothing names.
const example_use_helper =
    \\const EXAMPLE_LIB: bytes = b"x"
    \\
    \\
    \\public func label() -> bytes:
    \\    """The example library tag.
    \\
    \\    >>> label() == EXAMPLE_LIB
    \\    True
    \\    """
    \\    return b"x"
    \\
    \\
    \\func unused_helper() -> int:
    \\    return 1
;

// spec: LINT-REACH-3
test "FR-415 a docstring example counts as a use for dead-private and as a test for untested-export" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try temp.dir.writeFile(t.io, .{ .sub_path = "helper.selka", .data = example_use_helper });
    try writeFixture(&temp, "import helper\n\n\nfunc main() -> int:\n    return 0\n");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", ""));
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_DEAD_PRIVATE", "EXAMPLE_LIB"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_DEAD_PRIVATE", "unused_helper"));
    try t.expect(findFinding(outcome, "L_UNTESTED_EXPORT") == null);
}

/// Whether one evaluated outcome carries a finding with `code`.
fn hasFinding(outcome: lint.Outcome, code: []const u8) bool {
    for (outcome.findings) |finding| if (std.mem.eql(u8, finding.code, code)) return true;
    return false;
}

/// The first evaluated finding with `code`, or null.
fn findFinding(outcome: lint.Outcome, code: []const u8) ?lint.Finding {
    for (outcome.findings) |finding| if (std.mem.eql(u8, finding.code, code)) return finding;
    return null;
}

// spec: LINT-4
test "integration-tests flags a capability test outside an integration module and honors modules" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\
        \\
        \\func test_io(fs: Filesystem) -> bool:
        \\    _ = fs
        \\    return True
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const flagged = try evaluateFixture(scratch, root, .{});
    try t.expect(hasFinding(flagged, "L_TEST_CAPABILITY"));

    var config: lint_config.Config = .{};
    defer config.deinit(t.allocator);
    const modules = try t.allocator.alloc([]const u8, 1);
    modules[0] = try t.allocator.dupe(u8, "main");
    try config.rules.put(t.allocator, try t.allocator.dupe(u8, "integration-tests"), .{ .modules = modules });
    const allowed = try evaluateFixture(scratch, root, .{ .config = &config });
    try t.expect(!hasFinding(allowed, "L_TEST_CAPABILITY"));
}

// spec: LINT-5
test "lint attaches the transitive tests that reach a finding as a related note" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\
        \\
        \\public func outer() -> int:
        \\    return 1
        \\
        \\
        \\func middle() -> int:
        \\    return outer()
        \\
        \\
        \\func test_end_to_end() -> bool:
        \\    return middle() == 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Under `strict` the direct-call fact still reports `outer`, and the note
    // names the test that reaches it transitively.
    var strict_config: lint_config.Config = .{ .profile = .strict };
    defer strict_config.deinit(t.allocator);
    const strict = try evaluateFixture(scratch, root, .{ .config = &strict_config });
    const flagged = findFinding(strict, "L_UNTESTED_EXPORT");
    try t.expect(flagged != null);
    try t.expect(std.mem.indexOf(u8, flagged.?.message, "reached only transitively") != null);
    try t.expect(flagged.?.related != null);
    try t.expect(std.mem.indexOf(u8, flagged.?.related.?.message, "main::test_end_to_end") != null);

    // Under `agent` the same declaration counts as tested, so the note rides its
    // remaining reportable finding instead of an untested-export one.
    const agent = try evaluateFixture(scratch, root, .{});
    try t.expect(findFinding(agent, "L_UNTESTED_EXPORT") == null);
    const note = findFinding(agent, "L_UNDOCUMENTED_EXPORT");
    try t.expect(note != null);
    try t.expect(note.?.related != null);
    try t.expect(std.mem.indexOf(u8, note.?.related.?.message, "main::test_end_to_end") != null);
}

// spec: LINT-6
test "section-9 advisory rules report records files literals params naming conditions duplicates and output" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, advisory_fixture);
    var config: lint_config.Config = .{};
    defer config.deinit(t.allocator);
    try config.rules.put(t.allocator, try t.allocator.dupe(u8, "file-length"), .{ .max = 3 });
    // `main` is in the default output allow-list, so name a different allowed
    // module to make the library-side output rule fire on this fixture.
    const allowed_modules = try t.allocator.alloc([]const u8, 1);
    allowed_modules[0] = try t.allocator.dupe(u8, "allowed");
    try config.rules.put(t.allocator, try t.allocator.dupe(u8, "output-in-library"), .{ .modules = allowed_modules });
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{ .config = &config });
    try t.expect(hasFinding(outcome, "L_RECORD_SIZE"));
    try t.expect(hasFinding(outcome, "L_FILE_LENGTH"));
    try t.expect(hasFinding(outcome, "L_BOOL_OPS"));
    try t.expect(hasFinding(outcome, "L_NAMING"));
    try t.expect(hasFinding(outcome, "L_REPEATED_LITERAL"));
    try t.expect(hasFinding(outcome, "L_SAME_TYPE_ADJACENT_PARAMS"));
    // The finding names the parameters' type as the source spells it, never as the checker stores it (`i64`).
    const adjacent = findFinding(outcome, "L_SAME_TYPE_ADJACENT_PARAMS").?;
    try t.expect(std.mem.indexOf(u8, adjacent.message, "i64") == null);
    try t.expect(std.mem.indexOf(u8, adjacent.message, "adjacent parameters of type int") != null);
    try t.expect(hasFinding(outcome, "L_DUPLICATE_BODY"));
    try t.expect(hasFinding(outcome, "L_OUTPUT_IN_LIBRARY"));
}

/// One declared function and one record whose calls carry positional literals
/// beside the negated cases: a named call, a short call, and an intrinsic.
const positional_literal_fixture =
    \\
    \\
    \\record Point:
    \\    x: int
    \\    y: int
    \\    z: int
    \\
    \\
    \\func draw(canvas: int, x: int, y: int, filled: bool) -> int:
    \\    _ = canvas
    \\    _ = filled
    \\    return x + y
    \\
    \\
    \\func short(a: int, b: int) -> int:
    \\    return a + b
    \\
    \\
    \\func main() -> int:
    \\    mut canvas = 0
    \\    _ = draw(canvas=1, x=10, y=20, filled=True)
    \\    _ = short(1, 2)
    \\    return draw(canvas, 10, 20, True)
;

// spec: KEYWORD-ONLY-4
test "the positional-literal lint names the parameter a positional literal binds to" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, positional_literal_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    const finding = findFinding(outcome, "L_POSITIONAL_LITERAL");
    try t.expect(finding != null);
    try t.expectEqualStrings("positional-literal", finding.?.rule);
    try t.expectEqualStrings("`True` is passed positionally to `draw`'s 4th parameter `filled`; name it: `draw(canvas, x=10, y=20, filled=True)`", finding.?.message);
}

// spec-case: KEYWORD-ONLY-4
test "named record construction needs no positional literal advisory" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\
        \\
        \\record Point:
        \\    x: int
        \\    y: int
        \\    z: int
        \\
        \\
        \\func main() -> int:
        \\    mut point = Point(x=1, y=2, z=3)
        \\    return point.x
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    const finding = findFinding(outcome, "L_POSITIONAL_LITERAL");
    try t.expect(finding == null);
}

// spec-case: KEYWORD-ONLY-4
test "the positional-literal lint exempts named operands and an intrinsic" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\
        \\
        \\func draw(canvas: int, x: int, y: int) -> int:
        \\    _ = canvas
        \\    return x + y
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, 1, 2, 3)
        \\    return draw(canvas=1, x=2, y=3)
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expect(findFinding(outcome, "L_POSITIONAL_LITERAL") == null);
}

test "checked docs imported module diagnostics use original source lines and reasoned waivers" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", a);
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "import library\n\"\"\"Calls the documented module.\"\"\"\nfunc main() -> int:\n    return library.value() + library.waived()\n" });
    const library = "# lint: allow undocumented-module reason=\"this fixture isolates declaration docs\"\n" ++
        "public func value() -> int:\n    \"\"\"An integer without a transcript.\"\"\"\n    return 42\n" ++
        "# lint: allow missing-example reason=\"verified in an external integration suite\"\n" ++
        "public func waived() -> int:\n    \"\"\"An integer checked by the external suite.\"\"\"\n    return 1\n" ++
        "public record test_Result:\n    value: int\n";
    try temp.dir.writeFile(t.io, .{ .sub_path = "library.selka", .data = library });
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(a);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
    const outcome = try lint.evaluate(.{
        .memory = a,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{ .profile = .strict },
        .data = .{ .diagnostics = .json },
    }, a);
    const finding = findFinding(outcome, "L_MISSING_EXAMPLE").?;
    try t.expectEqualStrings("library.selka", compilation.src.locate(finding.span.start).path);
    try t.expectEqual(@as(usize, 2), compilation.src.locate(finding.span.start).line);
    const undocumented = findFinding(outcome, "L_UNDOCUMENTED_EXPORT").?;
    try t.expectEqualStrings("library::test_Result", undocumented.subject.qualified);
    try t.expectEqualStrings("library.selka", compilation.src.locate(undocumented.span.start).path);
    try t.expectEqual(@as(usize, 9), compilation.src.locate(undocumented.span.start).line);
    try t.expect(!hasFinding(outcome, "L_UNDOCUMENTED_MODULE"));
    try t.expectEqual(@as(usize, 2), outcome.waived);
    const rendered = try language.diagnostic_output.render(a, .{ .code = finding.code, .message = finding.message, .span = finding.span, .severity = finding.state.severity }, compilation.src, .json);
    try t.expect(std.mem.indexOf(u8, rendered, "library.selka") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "L_MISSING_EXAMPLE") != null);
}

// spec: LINT-SIZE-1
test "discarded-failure reports a dropped failing result and blocks under the gate" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, "func main(fs: Filesystem) -> int:\n    _ = fs.mkdir(\"data\")\n    _ = len([1])\n    return 0\n");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // A plain discard of a non-failing value is not a finding; the failing call is
    // reported, and `--gate` makes it refuse.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), reported.findings.len);
    try t.expectEqualStrings("L_DISCARDED_FAILURE", reported.findings[0].code);
    // Report-only until §3.5's block flip (DECISIONS F34): the gate counts it as a
    // report, not a refusal.
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 1), gated.blocking);
}

test "public-dict reports a bare dict in a public signature and blocks nothing yet" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the public-dict rule."""
        \\
        \\
        \\public type WordCounts = dict[str, int]
        \\
        \\
        \\public func named(counts: WordCounts) -> int:
        \\    return len(counts)
        \\
        \\
        \\public func bare(counts: dict[str, int]) -> int:
        \\    return len(counts)
        \\
        \\
        \\func hidden(counts: dict[str, int]) -> int:
        \\    return len(counts)
        \\
        \\
        \\func main() -> int:
        \\    const counts: dict[str, int] = {"a": 1}
        \\    return named(counts) + bare(counts) + hidden(counts)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // A `type` alias and a private signature are both accepted spellings: the
    // published bare `dict[...]` is the one finding, and it blocks nothing until
    // the §3.5 flip.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_PUBLIC_DICT", "bare"));
    const finding = findFinding(reported, "L_PUBLIC_DICT").?;
    try t.expectEqualStrings("bare", finding.subject.qualified);
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 1), gated.blocking);
    try t.expect(hasFinding(gated, "L_PUBLIC_DICT"));
}

test "call-nesting reports a four-deep call chain and leaves three-deep and sibling calls alone" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the call-nesting rule."""
        \\
        \\
        \\func inner(value: int) -> int:
        \\    return value
        \\
        \\
        \\func middle(value: int) -> int:
        \\    return inner(value)
        \\
        \\
        \\func three(value: int) -> int:
        \\    return middle(inner(inner(value)))
        \\
        \\
        \\func deep(value: int) -> int:
        \\    return middle(inner(inner(inner(value))))
        \\
        \\
        \\func shallow(value: int) -> int:
        \\    return middle(value) + inner(value)
        \\
        \\
        \\func main() -> int:
        \\    return shallow(1) + three(2) + deep(3)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Three nested calls are the budget (calibrated in wave 2 round 34), and
    // sibling calls in one expression are not nesting; only `deep`'s fourth
    // level reports, and nothing blocks.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_CALL_NESTING", ""));
    const finding = findFinding(reported, "L_CALL_NESTING").?;
    try t.expectEqualStrings("main::deep", finding.subject.qualified);
    try t.expect(std.mem.indexOf(u8, finding.message, "inner") != null);
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 1), gated.blocking);
}

test "nesting-depth allows five control levels and reports six" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the nesting-depth rule."""
        \\
        \\
        \\func five(n: int) -> int:
        \\    mut total = 0
        \\    for a in range(n):
        \\        if a > 0:
        \\            for b in range(a):
        \\                if b > 0:
        \\                    if b != a:
        \\                        total += 1
        \\    return total
        \\
        \\
        \\func six(n: int) -> int:
        \\    mut total = 0
        \\    for a in range(n):
        \\        if a > 0:
        \\            for b in range(a):
        \\                if b > 0:
        \\                    if b != a:
        \\                        if b > 1:
        \\                            total += 1
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return five(4) + six(4)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Five control levels are the budget (calibrated in wave 2 round 34): `five`
    // passes and `six` reports, and the report-only run blocks nothing.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_NESTING_DEPTH", ""));
    const finding = findFinding(reported, "L_NESTING_DEPTH").?;
    try t.expectEqualStrings("main::six", finding.subject.qualified);
    try t.expectEqual(@as(usize, 0), reported.blocking);
}

test "counting-while reports an exact counting loop and skips a stepped one" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the counting-while rule."""
        \\
        \\
        \\func counted(values: int[]) -> int:
        \\    mut index = 0
        \\    mut total = 0
        \\    while index < len(values):
        \\        total += values[index]
        \\        index += 1
        \\    return total
        \\
        \\
        \\func stepped(values: int[]) -> int:
        \\    mut index = 0
        \\    while index < len(values):
        \\        index += 2
        \\    return index
        \\
        \\
        \\func continued(values: int[]) -> int:
        \\    mut index = 0
        \\    mut total = 0
        \\    while index < len(values):
        \\        if values[index] == 7:
        \\            index += 1
        \\            continue
        \\        total += 1
        \\        index += 1
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    const values: int[] = [1, 7]
        \\    return counted(values) + stepped(values) + continued(values)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Only the exact shape reports: `stepped` steps by two, and `continued`
    // skips its step, so neither rewrite would preserve the loop.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COUNTING_WHILE", ""));
    const finding = findFinding(reported, "L_COUNTING_WHILE").?;
    try t.expectEqualStrings("main::counted", finding.subject.qualified);
    try t.expect(std.mem.indexOf(u8, finding.message, "for index in range(0, len(values)):") != null);
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 1), gated.blocking);
}

test "double-lookup reports one statement that reads and writes one dictionary key" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import dicts
        \\
        \\"""Isolates the double-lookup rule."""
        \\
        \\
        \\func bump(mut counts: dict[str, int]) -> int:
        \\    counts["a"] = dicts.get(counts, "a", 0) + 1
        \\    counts["b"] = counts["b"] + 1
        \\    counts["c"] = 1
        \\    counts["d"] = counts["c"] + 1
        \\    return counts["a"] + counts["b"] + counts["d"]
        \\
        \\
        \\func main() -> int:
        \\    mut counts: dict[str, int] = {"a": 1}
        \\    return bump(mut counts)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Two statements double-probe their key; a plain write and a write of a
    // different key stay silent.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 2), countFindings(reported, "L_DOUBLE_LOOKUP", ""));
    try t.expect(std.mem.indexOf(u8, findFinding(reported, "L_DOUBLE_LOOKUP").?.message, "dicts.add") != null);
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 2), gated.blocking);
}

test "copy-for-store reports a parameter copied into each storing shape and not a read copy" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the copy-for-store rule."""
        \\
        \\
        \\record State:
        \\    keys: int[]
        \\
        \\
        \\record Hub:
        \\    conns: dict[int, State]
        \\
        \\
        \\func built(keys: int[]) -> State:
        \\    return State(keys=copy(keys))
        \\
        \\
        \\func added(mut rows: State[], row: State):
        \\    append(mut rows, copy(row))
        \\
        \\
        \\func stored(mut hub: Hub, state: State):
        \\    hub.conns[1] = copy(state)
        \\
        \\
        \\func read_only(keys: int[]) -> int:
        \\    const held = keys
        \\    return len(held)
        \\
        \\
        \\func own_taken(own keys: int[]) -> State:
        \\    return State(keys=own keys)
        \\
        \\
        \\func main() -> int:
        \\    mut keys = [1, 2]
        \\    const made = built(keys)
        \\    mut rows: State[] = []
        \\    added(mut rows, made)
        \\    mut table: dict[int, State] = {}
        \\    mut hub = Hub(conns=own table)
        \\    stored(mut hub, made)
        \\    mut given = [3]
        \\    const taken = own_taken(own given)
        \\    return read_only(keys) + len(taken.keys)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The three storing shapes report; a read of a parameter, which needs no copy,
    // and an `own` parameter that takes the value stay silent.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 3), countFindings(reported, "L_COPY_FOR_STORE", ""));
    try t.expect(std.mem.indexOf(u8, findFinding(reported, "L_COPY_FOR_STORE").?.message, "declare it `own`") != null);
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `keys`"));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `row`"));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `state`"));
    // Report only: the same run never blocks, with or without `--gate`.
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 3), countFindings(gated, "L_COPY_FOR_STORE", ""));
    try t.expectEqual(@as(usize, 0), gated.blocking);
}

/// One parameter of each kind the copy-for-store advice is false for, and one it is true for.
const copy_for_store_excluded =
    \\"""Isolates the parameters the copy-for-store advice does not name."""
    \\
    \\
    \\record Band:
    \\    low: int
    \\    high: int
    \\
    \\
    \\record Window:
    \\    band: Band
    \\
    \\
    \\record State:
    \\    keys: int[]
    \\
    \\
    \\record Hub:
    \\    conns: dict[int, State]
    \\
    \\
    \\record Label:
    \\    text: str
    \\
    \\
    \\func borrowed(mut hub: Hub, mut state: State):
    \\    append(mut state.keys, 1)
    \\    hub.conns[1] = copy(state)
    \\
    \\
    \\func taken(mut rows: State[], own row: State):
    \\    append(mut rows, copy(row))
    \\
    \\
    \\func numbers(band: Band) -> Window:
    \\    return Window(band=copy(band))
    \\
    \\
    \\func labelled(text: str) -> Label:
    \\    return Label(text=copy(text))
    \\
    \\
    \\func main() -> int:
    \\    mut state = State(keys=[1])
    \\    mut table: dict[int, State] = {}
    \\    mut hub = Hub(conns=own table)
    \\    borrowed(mut hub, mut state)
    \\    mut rows: State[] = []
    \\    taken(mut rows, own state)
    \\    const window = numbers(Band(low=1, high=2))
    \\    const label = labelled("t")
    \\    return len(rows) + window.band.low + len(label.text)
    \\
;

test "copy-for-store stays silent for a mut parameter, an own one and one with no managed storage, and still names a plain text" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, copy_for_store_excluded);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const reported = try evaluateFixture(scratch, root, .{});
    // `mut state` writes the caller's value, `own row` already takes it, and `band` holds only numbers: `own` helps none.
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `state`"));
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `row`"));
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `band`"));
    // The plain text parameter keeps the one finding, with the text it has always had.
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", ""));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "labelled copies parameter `text` into storage; " ++
        "declare it `own` and pass `own text` where every caller can give the value up"));
}

/// A constructor that copies three parameters, one of them twice.
const copy_for_store_many =
    \\"""Isolates the copy-for-store rule on one constructor."""
    \\
    \\
    \\record Plan:
    \\    head: int[]
    \\    body: int[]
    \\    tail: str
    \\    name: str
    \\
    \\
    \\func plan(head: int[], body: int[], tail: str) -> Plan:
    \\    return Plan(head=copy(head), body=copy(body), tail=copy(tail), name=copy(tail))
    \\
    \\
    \\func main() -> int:
    \\    const made = plan([1], [2], "t")
    \\    return len(made.head) + len(made.body)
    \\
;

/// The one-based line and column the finding of the fixture at `root` starts at, in the file it was written in.
fn findingPlace(scratch: std.mem.Allocator, root: []const u8, finding: lint.Finding) !struct { line: usize, column: usize } {
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const at = compilation.src.locate(finding.span.start);
    return .{ .line = at.line, .column = at.column };
}

/// The one-based column `needle` starts at in the fixture line that holds it.
fn columnOf(text: []const u8, needle: []const u8) usize {
    const at = std.mem.indexOf(u8, text, needle).?;
    const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
    return at - line_start + 1;
}

test "copy-for-store names every parameter one statement copies, each at its own copy, and a parameter once" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, copy_for_store_many);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const reported = try evaluateFixture(scratch, root, .{});
    // Three parameters are copied by one `return`, `tail` twice: three findings, one for each parameter.
    try t.expectEqual(@as(usize, 3), countFindings(reported, "L_COPY_FOR_STORE", ""));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `head`"));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `body`"));
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_FOR_STORE", "copies parameter `tail`"));
    // Each starts at its own `copy(...)`, in the order the fields are written, not at the statement.
    const head = try findingPlace(scratch, root, reported.findings[firstFinding(reported, "L_COPY_FOR_STORE", "`head`")]);
    const body = try findingPlace(scratch, root, reported.findings[firstFinding(reported, "L_COPY_FOR_STORE", "`body`")]);
    const tail = try findingPlace(scratch, root, reported.findings[firstFinding(reported, "L_COPY_FOR_STORE", "`tail`")]);
    try t.expectEqual(@as(usize, 12), head.line);
    try t.expectEqual(columnOf(copy_for_store_many, "copy(head)"), head.column);
    try t.expectEqual(columnOf(copy_for_store_many, "copy(body)"), body.column);
    // A repeated copy of one parameter is named at the first.
    try t.expectEqual(columnOf(copy_for_store_many, "copy(tail)"), tail.column);
    try t.expectEqual(@as(usize, 0), reported.blocking);
}

/// The index of the first finding of `code` whose message holds `needle`.
fn firstFinding(outcome: lint.Outcome, code: []const u8, needle: []const u8) usize {
    for (outcome.findings, 0..) |finding, index| {
        if (std.mem.eql(u8, finding.code, code) and std.mem.indexOf(u8, finding.message, needle) != null) return index;
    }
    unreachable;
}

/// A test module with a copy in a loop, in a file whose name ends `_test.selka`.
const copy_loop_in_test_file =
    \\"""A test file with a copy in a loop."""
    \\
    \\
    \\func gather(rows: str[]) -> str[]:
    \\    mut kept: str[] = []
    \\    for row in rows:
    \\        append(mut kept, copy(row))
    \\    return kept
    \\
    \\
    \\public func test_gather() -> bool:
    \\    return len(gather(["a", "b"])) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

test "copy-in-loop reports a copy in a loop in a file named _test.selka" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeModule(&temp, "gather_test", copy_loop_in_test_file);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The row the Core analysis gives the test's copy (line 7, column 26) names the file by its name; the rule reads no name.
    const site: lint.AllocationSite = .{ .function = "gather", .path = "gather_test.selka", .line = 7, .column = 26, .kind = .copy, .loop_depth = 1, .hint = "ignored" };
    const reported = try evaluateFixture(scratch, root, .{ .module = "gather_test", .sites = &.{site} });
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_COPY_IN_LOOP", "a copy at loop depth 1 in `gather`"));
    try t.expectEqual(@as(usize, 0), reported.blocking);
}

test "data-clump reports a helper that writes three caller arguments at two sites" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\"""Isolates the data-clump rule."""
        \\
        \\
        \\func tally(mut left: int[], mut right: int[], mut seen: int[]) -> int:
        \\    append(mut left, 1)
        \\    append(mut right, 2)
        \\    append(mut seen, 3)
        \\    return len(left) + len(right) + len(seen)
        \\
        \\
        \\func pair(mut left: int[], mut right: int[]) -> int:
        \\    append(mut left, 1)
        \\    append(mut right, 2)
        \\    return len(left) + len(right)
        \\
        \\
        \\func main() -> int:
        \\    mut left: int[] = []
        \\    mut right: int[] = []
        \\    mut seen: int[] = []
        \\    const first = tally(mut left, mut right, mut seen)
        \\    const second = tally(mut left, mut right, mut seen)
        \\    return first + second + pair(mut left, mut right) + pair(mut left, mut right)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Three written arguments at two sites is the clump; two written arguments
    // are not, however often they are passed together.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(reported, "L_DATA_CLUMP", ""));
    const finding = findFinding(reported, "L_DATA_CLUMP").?;
    try t.expectEqualStrings("main::tally", finding.subject.qualified);
    try t.expectEqual(@as(usize, 0), reported.blocking);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    // The stage-5 block flip (DECISIONS F38): under `--gate` the finding refuses.
    try t.expectEqual(@as(usize, 1), gated.blocking);
}

test "a file that says it is generated is exempt from every rule" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\# generated by tools/kernels.py — do not edit
        \\"""A generated kernel."""
        \\
        \\
        \\func kernel(count: int) -> int:
        \\    mut index = 0
        \\    while index < count:
        \\        index += 1
        \\    return index
        \\
        \\
        \\func main() -> int:
        \\    return kernel(3)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The same counting loop reports in a hand-written file (the test beside
    // this one); the generated marker silences it by construction, gate or not.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_COUNTING_WHILE", ""));
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), gated.blocking);
}

test "a file whose first line says GENERATED in capitals is exempt from every rule" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\# GENERATED by gen_ports.py — do not edit
        \\"""A generated kernel."""
        \\
        \\
        \\func kernel(count: int) -> int:
        \\    mut index = 0
        \\    while index < count:
        \\        index += 1
        \\    return index
        \\
        \\
        \\func main() -> int:
        \\    return kernel(3)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_COUNTING_WHILE", ""));
}

// spec: PERFORMANCE-FEEDBACK-LINT-1
test "a project's lint never reports the standard library it imports" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import strings
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, strings.upper("a"))
        \\    return 0
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The module's exports are untested, undocumented and partly unreached;
    // none of that belongs to the project's review.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), reported.findings.len);
    // Linting the standard library itself keeps its findings.
    const self_reported = try evaluateFixture(scratch, root, .{ .entry_stdlib = true });
    try t.expect(self_reported.findings.len > 0);
}

// spec: PERFORMANCE-FEEDBACK-LINT-1
test "naming judges a generic instantiation by its source name" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\func contains[T: equality](values: T[], value: T) -> bool:
        \\    for element in values:
        \\        if element == value:
        \\            return True
        \\    return False
        \\
        \\
        \\func main() -> int:
        \\    if contains([1, 2], 2):
        \\        return 0
        \\    return 1
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The checked name is `contains[i64]`; the source name is `contains`, so no
    // naming finding can come from the specialization suffix.
    const reported = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(reported, "L_NAMING", ""));
}

/// `needless-copy`: `total` only reads `xs`, so the copy there carries no value.
const needless_copy_fixture =
    // migrate-embedded: skip original needless-copy warning and reasoned-waiver placement witness
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        append(mut xs, i)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += total(copy(xs))
    \\    return acc
    \\
    \\
    \\func main() -> int:
    \\    return run(2)
    \\
;

/// The same copy with a reasoned waiver on the line above it.
const waived_needless_copy_fixture =
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        append(mut xs, i)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        # lint: allow needless-copy reason="this benchmark measures the copy itself"
    \\        acc += total(copy(xs))
    \\    return acc
    \\
    \\
    \\func main() -> int:
    \\    return run(2)
    \\
;

// spec: NEEDLESS-COPY-1
test "needless-copy reads the checker warning and blocks under gate" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, needless_copy_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_NEEDLESS_COPY", ""));
    try t.expectEqual(@as(usize, 0), plain.blocking);
    const finding = findFinding(plain, "L_NEEDLESS_COPY").?;
    try t.expectEqualStrings("`total` only reads `xs`, so pass `xs` itself rather than a copy", finding.message);
    try t.expectEqualStrings("main::run", finding.subject.qualified);
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), gated.blocking);
    // The bound is freed by the arena, so a second evaluation reuses the entry.
    const waived = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(waived, "L_NEEDLESS_COPY", ""));
}

/// One function for each idiom rule (`syntax_hints.zig`).
const idiom_fixture =
    \\enum Node:
    \\    text(value: str)
    \\    leaf
    \\
    \\
    \\func sign(c: int) -> bool:
    \\    return c == 43 or c == 45 or c == 47
    \\
    \\
    \\func digit(c: int) -> bool:
    \\    return c >= 48 and c <= 57
    \\
    \\
    \\func weight(x: int) -> int:
    \\    if x == 1:
    \\        return 10
    \\    elif x == 2:
    \\        return 20
    \\    elif x == 3:
    \\        return 30
    \\    return 0
    \\
    \\
    \\func shape(node: Node) -> int:
    \\    match node:
    \\        case text(value=value):
    \\            return len(value)
    \\        case leaf:
    \\            return 0
    \\
    \\
    \\func first(values: int[]) -> int?:
    \\    return None
    \\
    \\
    \\func second(values: int[]) -> int?:
    \\    match first(values):
    \\        case Some(x):
    \\            return x + 1
    \\        case None:
    \\            return None
    \\
    \\
    \\func third(values: int[]) -> int?:
    \\    const x = first(values) else:
    \\        return None
    \\    return x + 1
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

// spec: SYNTAX-HINTS-7
test "the idiom rules read the checker warnings, name the rewrite and never block" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, idiom_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try evaluateFixture(scratch, root, .{});
    for ([_][]const u8{ "L_BYTE_SET", "L_RANGE_CHAIN", "L_LITERAL_MATCH", "L_PATTERN_SHORTHAND", "L_OPTION_TRY", "L_ELSE_IS_TRY" }) |code| {
        try t.expectEqual(@as(usize, 1), countFindings(plain, code, ""));
    }
    try t.expectEqualStrings("main::shape", findFinding(plain, "L_PATTERN_SHORTHAND").?.subject.qualified);
    // The fixture's unused helpers block under the gate (`dead-private`); the idiom findings do not.
    const gated = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), blockingIdioms(gated));
    try t.expectEqual(@as(usize, 6), idiomFindings(gated));
}

/// How many of an outcome's idiom findings refuse.
fn blockingIdioms(outcome: lint.Outcome) usize {
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (isIdiom(finding.code) and finding.state.severity == .err) count += 1;
    }
    return count;
}

/// How many idiom findings an outcome holds.
fn idiomFindings(outcome: lint.Outcome) usize {
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (isIdiom(finding.code)) count += 1;
    }
    return count;
}

fn isIdiom(code: []const u8) bool {
    for ([_][]const u8{ "L_BYTE_SET", "L_RANGE_CHAIN", "L_LITERAL_MATCH", "L_PATTERN_SHORTHAND", "L_OPTION_TRY", "L_ELSE_IS_TRY" }) |known| {
        if (std.mem.eql(u8, code, known)) return true;
    }
    return false;
}

// spec: NEEDLESS-COPY-2
test "needless-copy reports nothing where the copy is the point" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\func total(xs: int[]) -> int:
        \\    mut sum = 0
        \\    for x in xs:
        \\        sum += x
        \\    return sum
        \\
        \\
        \\func run() -> int:
        \\    mut xs: int[] = []
        \\    append(mut xs, 1)
        \\    const ys = copy(xs)
        \\    append(mut xs, 2)
        \\    return total(ys) + len(xs)
        \\
        \\
        \\func main() -> int:
        \\    return run()
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_NEEDLESS_COPY", ""));
}

// spec: NEEDLESS-COPY-1
test "needless-copy takes a reasoned site waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, waived_needless_copy_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The waiver silences the checker warning the rule reads, so the run has
    // nothing to report and nothing to refuse.
    const waived = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), waived.waived);
    try t.expectEqual(@as(usize, 0), countFindings(waived, "L_NEEDLESS_COPY", ""));
    try t.expectEqual(@as(usize, 0), waived.blocking);
}

/// The same waiver two lines above the copy, where it no longer applies.
const misplaced_waiver_fixture =
    // migrate-embedded: skip original needless-copy warning and reasoned-waiver placement witness
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        append(mut xs, i)
    \\    mut acc = 0
    \\    # lint: allow needless-copy reason="this benchmark measures the copy itself"
    \\    for i in range(n):
    \\        acc += total(copy(xs))
    \\    return acc
    \\
    \\
    \\func main() -> int:
    \\    return run(2)
    \\
;

// spec: NEEDLESS-COPY-1
test "needless-copy takes a waiver only from the line just above the copy" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, misplaced_waiver_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_NEEDLESS_COPY", ""));
}

/// `linear-search-in-loop`: a "seen list" the loop appends to and searches.
const linear_search_committed =
    \\import lists
    \\
    \\
    \\func first_hit(n: int) -> int:
    \\    mut seen: int[] = []
    \\    mut hits = 0
    \\    for i in range(n):
    \\        const value = (i * 7919) % 1000
    \\        if lists.contains(seen, value):
    \\            hits += 1
    \\        append(mut seen, value)
    \\    return hits
    \\
    \\
    \\func main() -> int:
    \\    return first_hit(2)
    \\
;

/// The same function with a changed body, so the diff covers its declaration.
const linear_search_changed =
    \\import lists
    \\
    \\
    \\func first_hit(n: int) -> int:
    \\    mut seen: int[] = []
    \\    mut hits = 0
    \\    for i in range(n):
    \\        const value = (i * 7919) % 1001
    \\        if lists.contains(seen, value):
    \\            hits += 1
    \\        append(mut seen, value)
    \\    return hits
    \\
    \\
    \\func main() -> int:
    \\    return first_hit(2)
    \\
;

// spec: LOOP-RULES-1
test "linear-search-in-loop blocks in a changed declaration and reports elsewhere" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, linear_search_committed);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // A plain run reports it and never refuses.
    const plain = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_LINEAR_SEARCH_IN_LOOP", ""));
    try t.expectEqual(language.diagnostic.Severity.warning, findFinding(plain, "L_LINEAR_SEARCH_IN_LOOP").?.state.severity);
    try t.expectEqual(@as(usize, 0), plain.blocking);
    // A changed declaration refuses under `--gate --against`, and the message
    // names the set or dict rewrite.
    try writeFixture(&temp, linear_search_changed);
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    const finding = findFinding(changed, "L_LINEAR_SEARCH_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.err, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "keep a `set` or `dict` beside it") != null);
}

// spec: LOOP-RULES-1
test "linear-search-in-loop reports a search the loop does not change" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import lists
        \\
        \\
        \\func count_hits(n: int) -> int:
        \\    mut pool: int[] = []
        \\    for i in range(64):
        \\        append(mut pool, i * 3)
        \\    mut hits = 0
        \\    for i in range(n):
        \\        if lists.contains(pool, (i * 7919) % 192):
        \\            hits += 1
        \\    return hits
        \\
        \\
        \\func main() -> int:
        \\    return count_hits(2)
        \\
    );
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // The unchanged list only reports, even in a changed declaration under gate.
    const reported = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    const finding = findFinding(reported, "L_LINEAR_SEARCH_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.warning, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "answers the same probe in constant time") != null);
}

// spec: LOOP-RULES-1
test "linear-search-in-loop ignores a list the loop declares itself" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import lists
        \\
        \\
        \\func count_hits(n: int) -> int:
        \\    mut hits = 0
        \\    for i in range(n):
        \\        mut pool: int[] = []
        \\        append(mut pool, i)
        \\        if lists.contains(pool, 1):
        \\            hits += 1
        \\    return hits
        \\
        \\
        \\func main() -> int:
        \\    return count_hits(2)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_LINEAR_SEARCH_IN_LOOP", ""));
}

/// `shift-in-loop`: a queue drained at index 0 of a list built outside the loop.
const shift_committed =
    \\import lists
    \\
    \\
    \\func drain(n: int) -> int:
    \\    mut queue: int[] = []
    \\    for i in range(n):
    \\        append(mut queue, i)
    \\    mut total = 0
    \\    while len(queue) > 0:
    \\        total += lists.pop_at(mut queue, 0)
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return drain(2)
    \\
;

/// The same loop with a changed body, so the diff covers its declaration.
const shift_changed =
    \\import lists
    \\
    \\
    \\func drain(n: int) -> int:
    \\    mut queue: int[] = []
    \\    for i in range(n):
    \\        append(mut queue, i + 1)
    \\    mut total = 0
    \\    while len(queue) > 0:
    \\        total += lists.pop_at(mut queue, 0)
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return drain(2)
    \\
;

// spec: LOOP-RULES-2
test "shift-in-loop blocks in a changed declaration and reports elsewhere" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, shift_committed);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_SHIFT_IN_LOOP", ""));
    try t.expectEqual(@as(usize, 0), plain.blocking);
    try writeFixture(&temp, shift_changed);
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    const finding = findFinding(changed, "L_SHIFT_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.err, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "keep an index cursor over the list") != null);
}

// spec: LOOP-RULES-2
test "shift-in-loop ignores a pop from the end" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import lists
        \\
        \\
        \\func drain(n: int) -> int:
        \\    mut stack: int[] = []
        \\    for i in range(n):
        \\        append(mut stack, i)
        \\    mut total = 0
        \\    while len(stack) > 0:
        \\        total += lists.pop(mut stack)
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return drain(2)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_SHIFT_IN_LOOP", ""));
}

// spec: LOOP-RULES-2
test "shift-in-loop takes a reasoned site waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\import lists
        \\
        \\
        \\func drain(n: int) -> int:
        \\    mut queue: int[] = []
        \\    for i in range(n):
        \\        append(mut queue, i)
        \\    mut total = 0
        \\    while len(queue) > 0:
        \\        # lint: allow shift-in-loop reason="a deque lands in B6; this queue is tiny"
        \\        total += lists.pop_at(mut queue, 0)
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return drain(2)
        \\
    );
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const waived = try evaluateFixture(arena.allocator(), root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 1), waived.waived);
    try t.expectEqual(@as(usize, 0), countFindings(waived, "L_SHIFT_IN_LOOP", ""));
}

/// `sort-in-loop`: a growing window re-sorted every iteration.
const sort_committed =
    \\func sort_as_it_grows(n: int) -> int:
    \\    mut window: int[] = []
    \\    for i in range(n):
    \\        append(mut window, (i * 7919) % 1000)
    \\        window = sorted(window)
    \\    return window[0]
    \\
    \\
    \\func main() -> int:
    \\    return sort_as_it_grows(2)
    \\
;

/// The same loop with a changed body, so the diff covers its declaration.
const sort_changed =
    \\func sort_as_it_grows(n: int) -> int:
    \\    mut window: int[] = []
    \\    for i in range(n):
    \\        append(mut window, (i * 7919) % 1001)
    \\        window = sorted(window)
    \\    return window[0]
    \\
    \\
    \\func main() -> int:
    \\    return sort_as_it_grows(2)
    \\
;

// spec: LOOP-RULES-3
test "sort-in-loop blocks in a changed declaration and reports elsewhere" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, sort_committed);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_SORT_IN_LOOP", ""));
    try t.expectEqual(@as(usize, 0), plain.blocking);
    try writeFixture(&temp, sort_changed);
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    const finding = findFinding(changed, "L_SORT_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.err, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "sort it once after the loop") != null);
}

// spec: LOOP-RULES-3
test "sort-in-loop blocks an in-place sort of a growing list" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\func sort_as_it_grows(n: int) -> int:
        \\    mut window: int[] = []
        \\    for i in range(n):
        \\        append(mut window, (i * 7919) % 1000)
        \\        sort(mut window)
        \\    return window[0]
        \\
        \\
        \\func main() -> int:
        \\    return sort_as_it_grows(2)
        \\
    );
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_SORT_IN_LOOP", ""));
    try t.expectEqual(@as(usize, 0), plain.blocking);
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(language.diagnostic.Severity.warning, findFinding(changed, "L_SORT_IN_LOOP").?.state.severity);
}

// spec: LOOP-RULES-3
test "sort-in-loop ignores a list built inside the iteration" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\func sorted_batches(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        mut batch: int[] = []
        \\        append(mut batch, (i * 7919) % 1000)
        \\        append(mut batch, i % 97)
        \\        batch = sorted(batch)
        \\        total += batch[0]
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return sorted_batches(2)
        \\
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outcome = try evaluateFixture(arena.allocator(), root, .{});
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_SORT_IN_LOOP", ""));
}

// spec: LOOP-RULES-3
test "sort-in-loop takes a reasoned site waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp,
        \\func sort_as_it_grows(n: int) -> int:
        \\    mut window: int[] = []
        \\    for i in range(n):
        \\        append(mut window, (i * 7919) % 1000)
        \\        # lint: allow sort-in-loop reason="a heap lands in B6; this window holds at most four"
        \\        window = sorted(window)
        \\    return window[0]
        \\
        \\
        \\func main() -> int:
        \\    return sort_as_it_grows(2)
        \\
    );
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const waived = try evaluateFixture(arena.allocator(), root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 1), waived.waived);
    try t.expectEqual(@as(usize, 0), countFindings(waived, "L_SORT_IN_LOOP", ""));
}

/// `alloc-in-loop`: a construction site the Core passes placed inside a loop.
/// Line 5 is `        const d = {"a": i}`, the site a real analysis reports.
const alloc_in_loop_fixture =
    \\func build(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        const d = {"a": i}
    \\        total += len(d)
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return build(2)
    \\
;

/// The same program with a changed builder body, so the diff covers the site.
const alloc_in_loop_changed =
    \\func build(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        const d = {"a": i}
    \\        total += len(d) + 1
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return build(2)
    \\
;

/// The same program with the site's declaration waived by a reasoned comment.
const alloc_in_loop_waived =
    \\func build(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        # lint: allow alloc-in-loop reason="small dict; the loop is at most four"
    \\        const d = {"a": i}
    \\        total += len(d) + 1
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return build(2)
    \\
;

/// One synthetic site row at line 5, column 9 of the fixture.
const construction_site: lint.AllocationSite = .{
    .function = "build",
    .path = "main.selka",
    .line = 5,
    .column = 9,
    .kind = .construction,
    .loop_depth = 1,
    .hint = "a new value: construct it once outside the loop or reuse storage",
};

// spec: LOOP-RULES-4
test "alloc-in-loop reports a loop-depth construction only in a changed declaration" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, alloc_in_loop_fixture);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Without a diff it reports nothing, even though the rows name a loop site.
    const plain = try evaluateFixture(scratch, root, .{ .gate = true, .sites = &.{construction_site} });
    try t.expectEqual(@as(usize, 0), countFindings(plain, "L_ALLOC_IN_LOOP", ""));
    // A changed declaration reports it, and the finding never refuses.
    try writeFixture(&temp, alloc_in_loop_changed);
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD", .sites = &.{construction_site} });
    const finding = findFinding(changed, "L_ALLOC_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.warning, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "a construction site at loop depth 1 in `build`") != null);
    try t.expect(std.mem.indexOf(u8, finding.message, "construct it once outside the loop") != null);
}

// spec: LOOP-RULES-4
test "alloc-in-loop ignores a shallow site, another kind, or an unchanged declaration" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, alloc_in_loop_fixture);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Only `main` changed, so the site's own declaration is outside the diff.
    try writeFixture(&temp,
        \\func build(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        const d = {"a": i}
        \\        total += len(d)
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return build(3)
        \\
    );
    const unchanged_site = try evaluateFixture(scratch, root, .{ .against = "HEAD", .sites = &.{construction_site} });
    try t.expectEqual(@as(usize, 0), countFindings(unchanged_site, "L_ALLOC_IN_LOOP", ""));
    // A changed declaration with a shallow site, a growth site, a copy site and
    // an unresolved call all stay silent: the rule reads construction and
    // conversion sites at loop depth 1 or more only.
    try writeFixture(&temp, alloc_in_loop_changed);
    const shallow: lint.AllocationSite = .{ .function = "build", .path = "main.selka", .line = 5, .column = 9, .kind = .construction, .loop_depth = 0, .hint = "ignored" };
    const growth: lint.AllocationSite = .{ .function = "build", .path = "main.selka", .line = 5, .column = 9, .kind = .growth, .loop_depth = 1, .hint = "ignored" };
    const copied: lint.AllocationSite = .{ .function = "build", .path = "main.selka", .line = 5, .column = 9, .kind = .copy, .loop_depth = 1, .hint = "ignored" };
    const unresolved: lint.AllocationSite = .{ .function = "build", .path = "main.selka", .line = 5, .column = 9, .kind = .unresolved_call, .loop_depth = 1, .hint = "ignored" };
    const absent: lint.AllocationSite = .{ .function = "build", .path = "other.selka", .line = 5, .column = 9, .kind = .construction, .loop_depth = 1, .hint = "ignored" };
    const quiet = try evaluateFixture(scratch, root, .{ .against = "HEAD", .sites = &.{ shallow, growth, copied, unresolved, absent } });
    try t.expectEqual(@as(usize, 0), countFindings(quiet, "L_ALLOC_IN_LOOP", ""));
}

// spec: LOOP-RULES-4
test "alloc-in-loop takes a reasoned site waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, alloc_in_loop_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, alloc_in_loop_waived);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const waived = try evaluateFixture(arena.allocator(), root, .{ .gate = true, .against = "HEAD", .sites = &.{construction_site} });
    try t.expectEqual(@as(usize, 1), waived.waived);
    try t.expectEqual(@as(usize, 0), countFindings(waived, "L_ALLOC_IN_LOOP", ""));
}

fn repeated(scratch: std.mem.Allocator, byte: u8, count: usize) ![]u8 {
    const result = try scratch.alloc(u8, count);
    @memset(result, byte);
    return result;
}

fn longOutputFixture(scratch: std.mem.Allocator, width: usize) ![]const u8 {
    const value = try repeated(scratch, 'x', width);
    return std.fmt.allocPrint(scratch,
        \\"""A fixture module with one printed value."""
        \\
        \\
        \\public func dump() -> str:
        \\    """Return a long value.
        \\
        \\    >>> dump()
        \\    {s}
        \\    """
        \\    return "{s}"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , .{ value, value });
}

const longBlockFixture =
    \\"""A fixture module with one long transcript."""
    \\
    \\
    \\public func walk(value: int) -> int:
    \\    """Walk a value one step at a time.
    \\
    \\    >>> walk(1)
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    7
    \\    """
    \\    return value
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const shortExampleFixture =
    \\"""A fixture module with compact examples."""
    \\
    \\
    \\public func walk(value: int) -> int:
    \\    """Walk a value one step at a time.
    \\
    \\    >>> walk(1)
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    ... + 1
    \\    6
    \\    """
    \\    return value
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

fn findingFor(findings: []const lint.Finding, code: []const u8) !lint.Finding {
    for (findings) |finding| if (std.mem.eql(u8, finding.code, code)) return finding;
    return error.TestUnexpectedResult;
}

fn countCode(findings: []const lint.Finding, code: []const u8) usize {
    var result: usize = 0;
    for (findings) |finding| result += @intFromBool(std.mem.eql(u8, finding.code, code));
    return result;
}

test "long-example reports a long expected line and a seven-line prompt block without blocking" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    try writeFixture(&temp, try longOutputFixture(scratch, 121));
    const long_line = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countCode(long_line.findings, "L_LONG_EXAMPLE"));
    try t.expectEqual(@as(usize, 0), long_line.blocking);
    try t.expectEqualStrings("long-example", (try findingFor(long_line.findings, "L_LONG_EXAMPLE")).rule);
    try t.expect(std.mem.indexOf(u8, (try findingFor(long_line.findings, "L_LONG_EXAMPLE")).message, "max 120") != null);
    try writeFixture(&temp, longBlockFixture);
    const long_block = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countCode(long_block.findings, "L_LONG_EXAMPLE"));
    try t.expectEqual(@as(usize, 0), long_block.blocking);
    try t.expect(std.mem.indexOf(u8, (try findingFor(long_block.findings, "L_LONG_EXAMPLE")).message, "max 6") != null);
}

test "long-example accepts a 120-character line and a six-line block and honors a waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    try writeFixture(&temp, try longOutputFixture(scratch, 120));
    const at_limit = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countCode(at_limit.findings, "L_LONG_EXAMPLE"));
    try writeFixture(&temp, shortExampleFixture);
    const short = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 0), countCode(short.findings, "L_LONG_EXAMPLE"));
    const waived = try std.mem.replaceOwned(u8, scratch, longBlockFixture, "public func walk", "# lint: allow long-example reason=\"the whole table is the point\"\npublic func walk");
    try writeFixture(&temp, waived);
    const covered = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), countCode(covered.findings, "L_LONG_EXAMPLE"));
    try t.expectEqual(@as(usize, 1), covered.waived);
    try t.expectEqual(@as(usize, 0), covered.blocking);
}

test "long-example waiver without a reason still blocks as L_WAIVER_REASON" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const waived = try std.mem.replaceOwned(u8, scratch, longBlockFixture, "public func walk", "# lint: allow long-example\npublic func walk");
    try writeFixture(&temp, waived);
    const result = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), countCode(result.findings, "L_LONG_EXAMPLE"));
    try t.expectEqual(@as(usize, 1), countCode(result.findings, "L_WAIVER_REASON"));
    try t.expectEqual(@as(usize, 1), result.blocking);
}

const file_waived_private =
    \\# lint: allow-file dead-private reason="these fixtures are exercised by the integration suite"
    \\func first() -> int:
    \\    return 1
    \\
    \\
    \\func second() -> int:
    \\    return 2
    \\
    \\
    \\public func answer() -> int:
    \\    """Short."""
    \\    return 3
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const unwaived_private =
    \\func first() -> int:
    \\    return 1
    \\
    \\
    \\func second() -> int:
    \\    return 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const file_waiver_without_reason =
    \\# lint: allow-file dead-private
    \\func first() -> int:
    \\    return 1
    \\
    \\
    \\func second() -> int:
    \\    return 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

test "a file-level waiver covers several declarations and needs a reason" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    try writeFixture(&temp, unwaived_private);
    const bare = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 2), countCode(bare.findings, "L_DEAD_PRIVATE"));
    try writeFixture(&temp, file_waived_private);
    const covered = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), countCode(covered.findings, "L_DEAD_PRIVATE"));
    try t.expectEqual(@as(usize, 2), covered.waived);
    try t.expectEqual(@as(usize, 0), covered.blocking);
    try writeFixture(&temp, file_waiver_without_reason);
    const silent = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 1), countCode(silent.findings, "L_WAIVER_REASON"));
    try t.expectEqual(@as(usize, 1), silent.blocking);
    try t.expectEqual(@as(usize, 0), countCode(silent.findings, "L_DEAD_PRIVATE"));
}

test "a file-level waiver covers only its named rule" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    try writeFixture(&temp, file_waived_private);
    const covered = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 0), countCode(covered.findings, "L_DEAD_PRIVATE"));
    try t.expectEqual(@as(usize, 1), countCode(covered.findings, "L_UNDOCUMENTED_EXPORT"));
}

/// A record and one function that copies a record inside a `for` loop.
const copy_loop_fixture =
    \\record Box:
    \\    items: int[]
    \\    tag: int
    \\
    \\
    \\func sum_copies(boxes: Box[]) -> int:
    \\    mut total = 0
    \\    for box in boxes:
    \\        mut local = copy(box)
    \\        total += len(local.items)
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return sum_copies([Box(items=[1, 2], tag=0)])
    \\
;

/// The same program with a changed loop body, so the diff covers the copy's declaration.
const copy_loop_changed =
    \\record Box:
    \\    items: int[]
    \\    tag: int
    \\
    \\
    \\func sum_copies(boxes: Box[]) -> int:
    \\    mut total = 0
    \\    for box in boxes:
    \\        mut local = copy(box)
    \\        total += len(local.items) + 1
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return sum_copies([Box(items=[1, 2], tag=0)])
    \\
;

/// The same program with the copy statement under a reasoned site waiver.
const copy_loop_waived =
    \\record Box:
    \\    items: int[]
    \\    tag: int
    \\
    \\
    \\func sum_copies(boxes: Box[]) -> int:
    \\    mut total = 0
    \\    for box in boxes:
    \\        # lint: allow copy-in-loop reason="the copy is the point of this fixture"
    \\        mut local = copy(box)
    \\        total += len(local.items)
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return sum_copies([Box(items=[1, 2], tag=0)])
    \\
;

/// Copies in a `while` loop, a nested loop, and outside any loop, plus a loop with no copy.
const copy_shapes_fixture =
    \\func while_copies(values: int[]) -> int:
    \\    mut total = 0
    \\    mut i = 0
    \\    while i < len(values):
    \\        mut snapshot = copy(values)
    \\        total += snapshot[i]
    \\        i += 1
    \\    return total
    \\
    \\
    \\func nested_copies(grid: int[][]) -> int:
    \\    mut total = 0
    \\    for row in grid:
    \\        for cell in row:
    \\            mut snap = copy(row)
    \\            total += snap[0] + cell
    \\    return total
    \\
    \\
    \\func outside_copy(values: int[]) -> int:
    \\    mut snap = copy(values)
    \\    return len(snap)
    \\
    \\
    \\func no_copy_loop(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        total += value
    \\    return total
    \\
    \\
    \\func main() -> int:
    \\    return while_copies([1, 2]) + nested_copies([[1, 2]]) + outside_copy([3]) + no_copy_loop([4])
    \\
;

/// The copy row of `copy_loop_fixture`: line 9, column 21, at loop depth 1.
const loop_copy_site: lint.AllocationSite = .{ .function = "sum_copies", .path = "main.selka", .line = 9, .column = 21, .kind = .copy, .loop_depth = 1, .hint = "ignored" };

test "copy-in-loop blocks in a changed declaration and reports elsewhere" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, copy_loop_fixture);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Every declaration reports the copy, and an unchanged one never refuses.
    const plain = try evaluateFixture(scratch, root, .{ .gate = true, .sites = &.{loop_copy_site} });
    try t.expectEqual(@as(usize, 1), countFindings(plain, "L_COPY_IN_LOOP", ""));
    try t.expectEqual(@as(usize, 0), plain.blocking);
    try writeFixture(&temp, copy_loop_changed);
    // In a changed declaration under `--gate`, the copy refuses with its form named.
    const changed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD", .sites = &.{loop_copy_site} });
    const finding = findFinding(changed, "L_COPY_IN_LOOP").?;
    try t.expectEqual(language.diagnostic.Severity.err, finding.state.severity);
    try t.expect(std.mem.indexOf(u8, finding.message, "a copy at loop depth 1 in `sum_copies`") != null);
    // A stored copy of a record that no form replaces is a real transfer, and the message says nothing more.
    try t.expect(std.mem.indexOf(u8, finding.message, "the value is stored, so the copy is a real transfer") != null);
    // Without `--gate` the same changed declaration only reports.
    const plain_changed = try evaluateFixture(scratch, root, .{ .against = "HEAD", .sites = &.{loop_copy_site} });
    try t.expectEqual(language.diagnostic.Severity.warning, findFinding(plain_changed, "L_COPY_IN_LOOP").?.state.severity);
}

test "copy-in-loop reports copies in while and nested loops, and ignores the rest" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, copy_shapes_fixture);
    try commitFixture(root, t.allocator);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // A copy in a `while` at depth 1 and one nested two loops deep report; the copy outside any loop does not.
    const sites = [_]lint.AllocationSite{
        .{ .function = "while_copies", .path = "main.selka", .line = 5, .column = 24, .kind = .copy, .loop_depth = 1, .hint = "ignored" },
        .{ .function = "nested_copies", .path = "main.selka", .line = 15, .column = 24, .kind = .copy, .loop_depth = 2, .hint = "ignored" },
        .{ .function = "outside_copy", .path = "main.selka", .line = 21, .column = 16, .kind = .copy, .loop_depth = 0, .hint = "ignored" },
    };
    const outcome = try evaluateFixture(scratch, root, .{ .sites = &sites });
    try t.expectEqual(@as(usize, 2), countFindings(outcome, "L_COPY_IN_LOOP", ""));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_COPY_IN_LOOP", "in `while_copies`"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_COPY_IN_LOOP", "in `nested_copies`"));
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_COPY_IN_LOOP", "outside_copy"));
    // A loop with no copy row, and a construction row at depth 1, stay silent under this rule.
    const shapes = [_]lint.AllocationSite{
        .{ .function = "no_copy_loop", .path = "main.selka", .line = 28, .column = 9, .kind = .construction, .loop_depth = 1, .hint = "ignored" },
    };
    const quiet = try evaluateFixture(scratch, root, .{ .sites = &shapes });
    try t.expectEqual(@as(usize, 0), countFindings(quiet, "L_COPY_IN_LOOP", ""));
}

test "copy-in-loop takes a reasoned site waiver" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, copy_loop_fixture);
    try commitFixture(root, t.allocator);
    try writeFixture(&temp, copy_loop_waived);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // The waived statement moved down one line, to line 10.
    const site: lint.AllocationSite = .{ .function = "sum_copies", .path = "main.selka", .line = 10, .column = 21, .kind = .copy, .loop_depth = 1, .hint = "ignored" };
    const waived = try evaluateFixture(arena.allocator(), root, .{ .gate = true, .against = "HEAD", .sites = &.{site} });
    try t.expectEqual(@as(usize, 1), waived.waived);
    try t.expectEqual(@as(usize, 0), countFindings(waived, "L_COPY_IN_LOOP", ""));
}

/// The row of the `which`-th `copy(` of `text`: its one-based line and column, at loop depth 1.
fn copySite(text: []const u8, function: []const u8, which: usize) lint.AllocationSite {
    var at: usize = 0;
    var seen: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "copy(")) |found| : (at = found + 1) {
        if (seen == which) {
            const line = std.mem.count(u8, text[0..found], "\n") + 1;
            const column = found - (std.mem.lastIndexOfScalar(u8, text[0..found], '\n') orelse 0);
            return .{ .function = function, .path = "main.selka", .line = @intCast(line), .column = @intCast(column), .kind = .copy, .loop_depth = 1, .hint = "ignored" };
        }
        seen += 1;
    }
    unreachable;
}

/// The message of the one `L_COPY_IN_LOOP` finding that `fixture`'s `which`-th copy draws.
fn copyLoopMessage(scratch: std.mem.Allocator, fixture: []const u8, function: []const u8, which: usize) ![]const u8 {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", scratch);
    try writeFixture(&temp, fixture);
    try commitFixture(root, scratch);
    const site = copySite(fixture, function, which);
    const outcome = try evaluateFixture(scratch, root, .{ .sites = &.{site} });
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_COPY_IN_LOOP", ""));
    const message = try scratch.dupe(u8, findFinding(outcome, "L_COPY_IN_LOOP").?.message);
    return message;
}

/// The copy of a loop element that a read-only callee takes: the checker's `W_NEEDLESS_COPY`, so the form is a borrow.
const copy_form_borrow =
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(rows: int[][]) -> int:
    \\    mut acc = 0
    \\    for row in rows:
    \\        acc += total(copy(row))
    \\    return acc
    \\
    \\
    \\func main() -> int:
    \\    return run([[1, 2]])
    \\
;

/// The copy of each element of a list nothing reads again: the consuming loop moves it.
const copy_form_own =
    \\func make(n: int) -> str[]:
    \\    mut xs: str[] = []
    \\    for i in range(n):
    \\        append(mut xs, "a" + str(i))
    \\    return xs
    \\
    \\
    \\func moved(n: int) -> str[]:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(moved(2))
    \\
;

/// A slice of the source kept in a record, and a name the loop does not change kept in every record: `bytes`, which a span and a
/// symbol hold.
const copy_form_span_and_symbol =
    \\record Token:
    \\    text: bytes
    \\    owner: bytes
    \\
    \\
    \\func tokens(source: bytes, owner: bytes) -> Token[]:
    \\    mut out: Token[] = []
    \\    mut start = 0
    \\    for i in range(len(source)):
    \\        if source[i] == 32:
    \\            append(mut out, Token(text=copy(source[start:i]), owner=copy(owner)))
    \\            start = i + 1
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(tokens(b"a b c", b"o"))
    \\
;

/// The same slice and name as `str`, which a span and a symbol are refused for: both take `bytes`.
const copy_form_str_slice_and_name =
    \\record Token:
    \\    text: str
    \\    owner: str
    \\
    \\
    \\func tokens(source: str, owner: str) -> Token[]:
    \\    mut out: Token[] = []
    \\    mut start = 0
    \\    for i in range(len(source)):
    \\        if source[i] == 32:
    \\            append(mut out, Token(text=copy(source[start:i]), owner=copy(owner)))
    \\            start = i + 1
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(tokens("a b c", "o"))
    \\
;

test "copy-in-loop names the form that fits where the copy goes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const borrow = try copyLoopMessage(scratch, copy_form_borrow, "run", 0);
    try t.expect(std.mem.indexOf(u8, borrow, "the copy-free form checks here, so `selka fix` deletes the copy (docs/tooling/lint.md#needless-copies)") != null);
    const own = try copyLoopMessage(scratch, copy_form_own, "moved", 0);
    try t.expect(std.mem.indexOf(u8, own, "its source is not read again, so a move replaces it: `own x`, `take(mut x.f)` or `for x in own xs` (docs/value-semantics.md#taking-and-exchanging-a-value)") != null);
    const span = try copyLoopMessage(scratch, copy_form_span_and_symbol, "tokens", 0);
    try t.expect(std.mem.indexOf(u8, span, "store a `spans.Span` into the source instead of a copy of its text (docs/value-semantics.md#long-lived-data-hold-the-key-not-the-borrow)") != null);
    const symbol = try copyLoopMessage(scratch, copy_form_span_and_symbol, "tokens", 1);
    try t.expect(std.mem.indexOf(u8, symbol, "the same name is copied every iteration; intern it once with `symbols` and store the key (docs/standard-library.md#symbols)") != null);
}

test "copy-in-loop calls a slice or a name of a str a real transfer, where a span and a symbol are refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const slice = try copyLoopMessage(scratch, copy_form_str_slice_and_name, "tokens", 0);
    try t.expect(std.mem.endsWith(u8, slice, "; the value is stored, so the copy is a real transfer"));
    const name = try copyLoopMessage(scratch, copy_form_str_slice_and_name, "tokens", 1);
    try t.expect(std.mem.endsWith(u8, name, "; the value is stored, so the copy is a real transfer"));
    try t.expect(std.mem.indexOf(u8, slice, "symbols") == null and std.mem.indexOf(u8, slice, "spans") == null);
    try t.expect(std.mem.indexOf(u8, name, "symbols") == null and std.mem.indexOf(u8, name, "spans") == null);
}

/// The copy of a field of each element of a list the function is lent, with the field's type and a value of it filled in.
/// The list is read after the loop, so no move is proved and the copy is a choice.
const copy_rows_plain =
    \\record Row:
    \\    name: {[kind]s}
    \\    count: int
    \\
    \\
    \\func names(rows: Row[]) -> int:
    \\    mut out: {[kind]s}[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row.name))
    \\    return len(out) + len(rows)
    \\
    \\
    \\func main() -> int:
    \\    const rows = [Row(name={[value]s}, count=1)]
    \\    return names(rows)
    \\
;

/// The same loop over a list the function owns as an `own` parameter.
const copy_rows_own_parameter =
    \\record Row:
    \\    name: {[kind]s}
    \\    count: int
    \\
    \\
    \\func names(own rows: Row[]) -> int:
    \\    mut out: {[kind]s}[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row.name))
    \\    return len(out) + len(rows)
    \\
    \\
    \\func main() -> int:
    \\    const rows = [Row(name={[value]s}, count=1)]
    \\    return names(own rows)
    \\
;

/// The same loop over a list the function owns as a local.
const copy_rows_local =
    \\record Row:
    \\    name: {[kind]s}
    \\    count: int
    \\
    \\
    \\func names(n: int) -> int:
    \\    const rows = [Row(name={[value]s}, count=n)]
    \\    mut out: {[kind]s}[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row.name))
    \\    return len(out) + len(rows)
    \\
    \\
    \\func main() -> int:
    \\    return names(1)
    \\
;

const copy_loop_take_advice = "if neither the list nor the element is read again, `for x in own xs` takes the elements and " ++
    "`own x` or `own x.field` moves each one without a copy (docs/value-semantics.md#taking-and-exchanging-a-value)";
const copy_loop_param_advice = "the value is stored, so the copy is a real transfer; an `own` list parameter would let the loop take the elements: " ++
    "`for x in own xs`, then `own x` or `own x.field` (docs/value-semantics.md#taking-and-exchanging-a-value)";
const copy_symbol_advice = "the same name is copied every iteration; intern it once with `symbols` and store the key (docs/standard-library.md#symbols)";

test "copy-in-loop for a str names the loop that takes the elements, never a symbol or a span" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_plain, .{ .kind = "str", .value = "\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, plain, copy_loop_param_advice) != null);
    const owned = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_own_parameter, .{ .kind = "str", .value = "\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, owned, copy_loop_take_advice) != null);
    const local = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_local, .{ .kind = "str", .value = "\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, local, copy_loop_take_advice) != null);
    for ([_][]const u8{ plain, owned, local }) |message| {
        try t.expect(std.mem.indexOf(u8, message, "symbols") == null);
        try t.expect(std.mem.indexOf(u8, message, "spans") == null);
    }
}

test "copy-in-loop for bytes keeps the symbol advice over a plain list, an own parameter and a local" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const plain = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_plain, .{ .kind = "bytes", .value = "b\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, plain, copy_symbol_advice) != null);
    const owned = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_own_parameter, .{ .kind = "bytes", .value = "b\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, owned, copy_symbol_advice) != null);
    const local = try copyLoopMessage(scratch, std.fmt.comptimePrint(copy_rows_local, .{ .kind = "bytes", .value = "b\"a\"" }), "names", 0);
    try t.expect(std.mem.indexOf(u8, local, copy_symbol_advice) != null);
}

/// A name that changes in the loop is not repeated: the loop writes it, so interning it once would be wrong.
const copy_form_changing_name =
    \\record Token:
    \\    owner: str
    \\
    \\
    \\func tokens(n: int) -> Token[]:
    \\    mut out: Token[] = []
    \\    mut owner = "o"
    \\    for i in range(n):
    \\        owner = owner + "x"
    \\        append(mut out, Token(owner=copy(owner)))
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(tokens(3))
    \\
;

test "copy-in-loop calls a name the loop changes a real transfer" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const message = try copyLoopMessage(scratch, copy_form_changing_name, "tokens", 0);
    try t.expect(std.mem.indexOf(u8, message, "the value is stored, so the copy is a real transfer") != null);
}

/// The three places of friction entry F-74, a slice with a start the program wrote and one it found, and the shapes the
/// rule leaves alone: `text-slice-octets` reports `text[0:WIDTH - 1]`, `kind[0:1]`, `text[at:at + 1]` and `text[2:]`.
const text_slice_octets_fixture =
    \\import strings
    \\
    \\
    \\const WIDTH: int = 8
    \\
    \\
    \\func short(text: str) -> str:
    \\    if len(text) > WIDTH:
    \\        return copy(text[0:WIDTH - 1]) + "x"
    \\    return copy(text)
    \\
    \\
    \\func title(kind: str) -> str:
    \\    return copy(kind[0:1])
    \\
    \\
    \\func count_a(text: str) -> int:
    \\    mut at = 0
    \\    mut count = 0
    \\    while at < len(text):
    \\        if text[at:at + 1] == "a":
    \\            count += 1
    \\        at += 1
    \\    return count
    \\
    \\
    \\func after_two(text: str) -> str:
    \\    return copy(text[2:])
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, short("abc"), title("k"), count_a("aa"), after_two("abcd"))
    \\    return 0
;

/// What the rule leaves alone: a start of 0, a found offset, a length, a prefix strip after the test of an ASCII
/// prefix, an empty slice, and a slice of `bytes` or of a list.
const text_slice_octets_exempt =
    \\import strings
    \\
    \\
    \\func found(text: str) -> str:
    \\    const at = strings.find(text, ":") else:
    \\        return ""
    \\    return copy(text[0:at]) + copy(text[at:]) + copy(text[0:len(text) - 1]) + copy(text[0:0])
    \\
    \\
    \\func strip_scheme(url: str) -> str:
    \\    if strings.starts_with(url, "http://"):
    \\        return copy(url[7:])
    \\    return copy(url)
    \\
    \\
    \\func not_text(raw: bytes, values: int[], at: int) -> int:
    \\    const piece = raw[at:at + 1]
    \\    const run = values[1:3]
    \\    return len(piece) + len(run)
    \\
    \\
    \\func written_here(n: int) -> int:
    \\    const data = "abcdefghijkl"
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += len(copy(data[i % 4:i % 4 + 2]))
    \\    return total + len(copy("héllo"[0:1]))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, found("a:b"), strip_scheme("http://x"), not_text(b"xyz", [1, 2, 3, 4], 1), written_here(3))
    \\    return 0
;

test "text-slice-octets reports a text cut at a literal, a constant, a step of one and a literal start, and names the helpers" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    const message = findFinding(outcome, "L_TEXT_SLICE_OCTETS").?.message;
    try t.expectEqual(@as(usize, 4), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "counts octets"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[0:WIDTH - 1]` counts octets: its end is a constant"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`kind[0:1]` counts octets: its end is an integer literal"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[at:at + 1]` counts octets: its end is the other bound plus or minus a literal"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[2:]` counts octets: its start is an integer literal"));
    try t.expect(std.mem.indexOf(u8, message, "`strings.cut_octets`") != null);
    try t.expect(std.mem.indexOf(u8, message, "`strings.char_slice`") != null);
    try t.expect(std.mem.indexOf(u8, message, "`strings.starts_with_at`") != null);
    try t.expect(!findFinding(outcome, "L_TEXT_SLICE_OCTETS").?.state.blocks_under_gate);
}

test "text-slice-octets leaves a found offset, a length, a start of 0, a tested prefix, bytes, lists and a text written in place alone" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_exempt);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expect(!hasFinding(outcome, "L_TEXT_SLICE_OCTETS"));
}

test "text-slice-octets never blocks, even under the gate" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{ .gate = true });
    try t.expectEqual(@as(usize, 4), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "counts octets"));
    try t.expect(findFinding(outcome, "L_TEXT_SLICE_OCTETS").?.state.report_only == false);
    try t.expect(!findFinding(outcome, "L_TEXT_SLICE_OCTETS").?.state.blocks_under_gate);
}

/// F-77: the length of a text literal or of a module constant is the fixed width it is: reported alone, in a sum, and as the base
/// of the other bound. No test of the text is in these functions.
const text_slice_octets_lengths =
    \\import strings
    \\
    \\
    \\const PREFIX: str = "content-length:"
    \\const SUFFIX: str = ".json"
    \\
    \\
    \\func literal_start(line: str) -> str:
    \\    return copy(line[len("content-length:"):])
    \\
    \\
    \\func constant_start(line: str) -> str:
    \\    return copy(line[len(PREFIX):len(line)])
    \\
    \\
    \\func sums(line: str) -> str:
    \\    return copy(line[len(PREFIX) + 1:]) + copy(line[1:len("ab") + 3])
    \\
    \\
    \\func base_of_the_other(line: str) -> str:
    \\    return copy(line[len("a"):len("a") + 1]) + copy(line[2:len(PREFIX) + 2])
    \\
    \\
    \\func from_the_end(text: str) -> str:
    \\    return copy(text[len(text) - len(SUFFIX):len(text)])
    \\
    \\
    \\func found_lengths(text: str, prefix: str) -> str:
    \\    return copy(text[len(prefix):]) + copy(text[0:len(text) - len(prefix)])
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, literal_start("content-length: 1"), constant_start(PREFIX), sums("abcdefghijklmnopqrst"))
    \\    print(out, base_of_the_other("abcdefghijklmnopqrst"), from_the_end("a.json"), found_lengths("abc", "a"))
    \\    return 0
;

/// F-77: the tests that keep a cut at the length of the tested prefix or suffix quiet: the true branch of an `if` (an `and`
/// chain too), the false branch of a `not` test, the rest of a block after an `if not` that leaves (an `or` chain too, inside a
/// loop), a suffix cut under `ends_with`, an exact count of octets of a non-ASCII prefix, and an element read.
const text_slice_octets_guarded =
    \\import strings
    \\
    \\
    \\const PREFIX: str = "content-length:"
    \\const SUFFIX: str = ".json"
    \\
    \\
    \\func then_branch(line: str) -> str:
    \\    if strings.starts_with(line, "content-length:") and len(line) > 3:
    \\        return copy(line[len("content-length:"):])
    \\    return ""
    \\
    \\
    \\func leaves(line: str) -> str:
    \\    if not strings.starts_with(line, PREFIX):
    \\        return ""
    \\    return copy(line[len(PREFIX):len(line)])
    \\
    \\
    \\func leaves_in_a_loop(lines: str[], flag: bool) -> int:
    \\    mut total = 0
    \\    for line in lines:
    \\        if flag or not strings.starts_with(line, PREFIX):
    \\            continue
    \\        total += len(copy(line[len(PREFIX):]))
    \\    return total
    \\
    \\
    \\func else_branch(line: str) -> str:
    \\    if not strings.starts_with(line, PREFIX):
    \\        return ""
    \\    else:
    \\        return copy(line[len(PREFIX):])
    \\
    \\
    \\func suffix(text: str) -> str:
    \\    if strings.ends_with(text, SUFFIX):
    \\        return copy(text[len(text) - len(SUFFIX):len(text)])
    \\    return ""
    \\
    \\
    \\func suffix_octets(text: str) -> str:
    \\    if strings.ends_with(text, "ab"):
    \\        return copy(text[len(text) - 2:len(text)])
    \\    return ""
    \\
    \\
    \\func non_ascii_prefix(text: str) -> str:
    \\    if strings.starts_with(text, "é:"):
    \\        return copy(text[3:]) + copy(text[len("é:"):])
    \\    return ""
    \\
    \\
    \\func element(args: str[]) -> str:
    \\    if strings.starts_with(args[2], "--timeout="):
    \\        return copy(args[2][len("--timeout="):len(args[2])])
    \\    return ""
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, then_branch("content-length: 1"), leaves("content-length: 2"), leaves_in_a_loop(["content-length: 3"], False))
    \\    print(out, else_branch("content-length: 4"), suffix("a.json"), suffix_octets("xab"), non_ascii_prefix("é:z"), element(["", "", "--timeout=5"]))
    \\    return 0
;

/// F-77: what a test does not cover: another prefix (with the note), another text, a text written in the stretch, an element
/// whose index is written, a test that does not hold on every path to the cut, a test after the cut, and a test of a prefix
/// that is neither a literal nor a constant.
const text_slice_octets_unguarded =
    \\import strings
    \\
    \\
    \\const PREFIX: str = "content-length:"
    \\const OTHER: str = "x-length:"
    \\
    \\
    \\func other_constant(line: str) -> str:
    \\    if strings.starts_with(line, OTHER):
    \\        return copy(line[len(PREFIX):])
    \\    return ""
    \\
    \\
    \\func other_literal(line: str) -> str:
    \\    if strings.starts_with(line, "x-length:"):
    \\        return copy(line[len("content-length:"):])
    \\    return ""
    \\
    \\
    \\func other_text(line: str, rest: str) -> str:
    \\    if strings.starts_with(rest, PREFIX):
    \\        return copy(line[len(PREFIX):])
    \\    return ""
    \\
    \\
    \\func written_inside(line: str) -> str:
    \\    mut text = line
    \\    if strings.starts_with(text, PREFIX):
    \\        text = "zzzzzzzzzzzzzzzzzzzzzz"
    \\        return copy(text[len(PREFIX):])
    \\    return ""
    \\
    \\
    \\func index_written(args: str[], mut i: int) -> str:
    \\    if strings.starts_with(args[i], "--timeout="):
    \\        i += 1
    \\        return copy(args[i][len("--timeout="):len(args[i])])
    \\    return ""
    \\
    \\
    \\func if_that_falls_through(line: str) -> str:
    \\    mut out = ""
    \\    if not strings.starts_with(line, PREFIX):
    \\        out = "no"
    \\    return out + copy(line[len(PREFIX):])
    \\
    \\
    \\func test_after_the_cut(line: str) -> str:
    \\    const early = copy(line[len(PREFIX):])
    \\    if strings.starts_with(line, PREFIX):
    \\        return early
    \\    return ""
    \\
    \\
    \\func prefix_a_variable(line: str, prefix: str) -> str:
    \\    if strings.starts_with(line, prefix):
    \\        return copy(line[len(PREFIX):])
    \\    return ""
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, other_constant("x-length: 1"), other_literal("x-length: 2"), other_text("content-length: 3", "content-length: 3"))
    \\    mut at = 0
    \\    print(out, written_inside("content-length: 4"), index_written(["--timeout=5", "--timeout=6"], mut at))
    \\    print(out, if_that_falls_through("content-length: 7"), test_after_the_cut("content-length: 8"), prefix_a_variable("content-length: 9", "c"))
    \\    return 0
;

test "text-slice-octets reads the length of a text literal or a constant as the fixed width it is" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_lengths);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 7), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "counts octets"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[len(\"content-length:\"):]` counts octets: its start is the length of a text literal"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[len(PREFIX):len(line)]` counts octets: its start is the length of a constant"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[len(PREFIX) + 1:]` counts octets: its start is the length of a constant"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[1:len(\"ab\") + 3]` counts octets: its end is the length of a text literal"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[len(\"a\"):len(\"a\") + 1]` counts octets: its end is the length of a text literal"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`line[2:len(PREFIX) + 2]` counts octets: its end is the length of a constant"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[len(text) - len(SUFFIX):len(text)]` counts octets: its start is the other bound plus or minus a literal"));
    try t.expectEqual(@as(usize, 0), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[len(prefix):]`"));
    try t.expect(!findFinding(outcome, "L_TEXT_SLICE_OCTETS").?.state.blocks_under_gate);
}

test "text-slice-octets is quiet where the program tested the prefix or suffix the cut measures" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_guarded);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expect(!hasFinding(outcome, "L_TEXT_SLICE_OCTETS"));
}

test "text-slice-octets still reports a cut whose test names another text, and says what the nearly right test needs" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, text_slice_octets_unguarded);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 8), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "counts octets"));
    // One clause, naming the guard as written and the width the cut counts (FR27).
    const note = "tests another text than";
    const width = ", the width this cut measures";
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "the guard `strings.starts_with(line, OTHER)` " ++ note ++ " `len(PREFIX)`" ++ width));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "the guard `strings.starts_with(line, \"x-length:\")` " ++ note ++ " `len(\"content-length:\")`" ++ width));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "the guard `strings.starts_with(line, prefix)` " ++ note ++ " `len(PREFIX)`" ++ width));
    try t.expectEqual(@as(usize, 3), countFindings(outcome, "L_TEXT_SLICE_OCTETS", note));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[len(PREFIX):]` counts octets"));
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`args[i][len(\"--timeout=\"):len(args[i])]` counts octets"));
}

/// The compiler's own owners a hidden move gives a name that is no identifier (`consumed list`, `temporary list`,
/// `temporary option`, `temporary default`, `temporary payload`, `temporary result`): a loop over `own CALL()`, an element
/// moved out of a call's list, and `unwrap_or` on a call's option with an owned default (F-71). Beside them one local the
/// author wrote badly (`tmp`, on the vague-name list), which the rule must still report.
const hidden_owner_fixture =
    \\import strings
    \\
    \\
    \\record Name:
    \\    value: str
    \\
    \\
    \\func lines_of(text: str) -> str[]:
    \\    return strings.split(text, "\n")
    \\
    \\
    \\func maybe(text: str) -> str?:
    \\    if len(text) > 0:
    \\        return Some(copy(text))
    \\    return None
    \\
    \\
    \\func consumed(text: str) -> str[]:
    \\    mut kept: str[] = []
    \\    for line in own lines_of(text):
    \\        if not strings.starts_with(line, "ok"):
    \\            append(mut kept, own line)
    \\    return kept
    \\
    \\
    \\func head(text: str) -> str:
    \\    return lines_of(text)[0]
    \\
    \\
    \\func unwrapped(text: str) -> Name:
    \\    const fallback = copy(text)
    \\    const value = maybe(text).unwrap_or(own fallback)
    \\    return Name(value=own value)
    \\
    \\
    \\func vague(text: str) -> int:
    \\    const tmp = len(text)
    \\    return tmp
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, str(consumed("ok\nbad")), head("a\nb"), unwrapped("x").value, vague("y"))
    \\    return 0
;

/// What the shapes that name no variable leave: a `match` scrutinee, a bind-or-else and a `try`, beside the vague local.
const hidden_temporaries_fixture =
    \\import strings
    \\
    \\
    \\func maybe(text: str) -> str?:
    \\    if len(text) > 0:
    \\        return Some(copy(text))
    \\    return None
    \\
    \\
    \\func scrutinee(text: str) -> int:
    \\    match maybe(text):
    \\        case Some(found):
    \\            return len(found)
    \\        case None:
    \\            return 0
    \\
    \\
    \\func bound(text: str) -> int:
    \\    const found = maybe(text) else:
    \\        return 0
    \\    return len(found)
    \\
    \\
    \\func tried(text: str) -> int?:
    \\    const found = try maybe(text)
    \\    return Some(len(found))
    \\
    \\
    \\func vague(text: str) -> int:
    \\    const tmp = len(text)
    \\    return tmp
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, scrutinee("a"), bound("b"), str(tried("c")), vague("d"))
    \\    return 0
;

/// Lint `fixture` with the off-by-default `dead-write` rule on, and answer how many findings of `code` and `rule`'s message
/// mention `needle`, so a test can say that no rule printed a name the compiler made up.
fn hiddenNameFindings(fixture: []const u8, needle: []const u8) !usize {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try writeFixture(&temp, fixture);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var files: project_files.Files = .{ .io = t.io, .root = root };
    var proj = project.Project.init(scratch);
    defer proj.deinit();
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(scratch, &.{ root, "main.selka" });
    const outcome = try lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{ .rule = "dead-write" },
        .data = .{ .diagnostics = .text },
    }, scratch);
    // The vague local is the one naming finding the program earned; it must survive.
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_NAMING", "local tmp does not follow"));
    var count: usize = 0;
    for (outcome.findings) |finding| {
        if (std.mem.indexOf(u8, finding.message, needle) != null) count += 1;
    }
    return count;
}

test "lint names no local the compiler made up for a consuming loop: consumed list" {
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "consumed list"));
}

test "lint names no local the compiler made up for an element moved out of a call's list: temporary list" {
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "temporary list"));
}

test "lint names no local the compiler made up for unwrap_or on a call's option: temporary option, default, payload and result" {
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "temporary option"));
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "temporary default"));
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "temporary payload"));
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_owner_fixture, "temporary result"));
}

test "lint names no local for a match scrutinee, a bind-or-else or a try, and still names a vague local the author wrote" {
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_temporaries_fixture, "temporary"));
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_temporaries_fixture, "consumed"));
    try t.expectEqual(@as(usize, 0), try hiddenNameFindings(hidden_temporaries_fixture, "<"));
}

test "a local the program wrote counts as written and a hidden owner's name does not (typed.Local.written)" {
    const base: typed.Local = .{ .name = "", .declaration = .{ .start = 0, .end = 0 }, .ty = .i64, .mutable = false };
    var local = base;
    local.name = "total";
    try t.expect(local.written());
    local.name = "_unused";
    try t.expect(local.written());
    local.name = "consumed list";
    try t.expect(!local.written());
    local.name = "temporary payload";
    try t.expect(!local.written());
    local.name = "<collection>";
    try t.expect(!local.written());
    local.name = "";
    try t.expect(!local.written());
    local.name = "total";
    local.usage.temporary = true;
    try t.expect(!local.written());
}

test "text-slice-octets reads a constant of another module as a constant" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try temp.dir.writeFile(t.io, .{ .sub_path = "config.selka", .data = "public const NAME_WIDTH: int = 12\n" });
    try writeFixture(&temp,
        \\import config
        \\
        \\
        \\func name_of(text: str) -> str:
        \\    return copy(text[0:config.NAME_WIDTH])
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, name_of("abc"))
        \\    return 0
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expectEqual(@as(usize, 1), countFindings(outcome, "L_TEXT_SLICE_OCTETS", "`text[0:config.NAME_WIDTH]` counts octets: its end is a constant"));
}

test "a failed analysis leaves the loop rules unjudged, and only a gate refuses for it" {
    var compilation: project_compile.Compilation = undefined;
    const ran: lint.Request = .{ .memory = t.allocator, .io = t.io, .compilation = &compilation, .config = null, .entry_path = "main.selka", .options = .{} };
    try t.expectEqual(lint.Unjudged{}, lint.unjudged(ran));
    var failed = ran;
    failed.data.analysis_failed = "E_NOALLOC_ALLOCATES";
    try t.expectEqual(lint.Unjudged{ .alloc_in_loop = true, .copy_in_loop = true }, lint.unjudged(failed));
    failed.options.gate = true;
    try t.expectEqual(lint.Unjudged{ .alloc_in_loop = true, .copy_in_loop = true, .refuses = true }, lint.unjudged(failed));
    // A gate whose analysis ran refuses nothing for it.
    var gated = ran;
    gated.options.gate = true;
    try t.expectEqual(lint.Unjudged{}, lint.unjudged(gated));
}
