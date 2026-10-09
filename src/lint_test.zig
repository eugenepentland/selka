//! `mylang lint` declaration waivers: `@allow("rule", reason="...")` produces a
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
    var compilation = try language.Compilation.init(allocator, "attrs.my", text);
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

    var compilation = try language.Compilation.init(scratch, "attrs.my", marked_dead_private);
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
    \\func test_helper() -> bool effects():
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
    \\func test_helper() -> bool effects():
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
    \\func test_helper() -> bool effects():
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
    \\func test_helper() -> bool effects():
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
    \\func test_helper() -> bool effects():
    \\    return helper(1) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// A `mylang.json` that exempts the fixture helper from test coverage.
const exemption_config =
    \\{"version":2,"lint":{"rules":{"test-coverage":{"exempt":[{"name":"main::helper","reason":"exercised by the integration suite"}]}}}}
;

/// Switches one fixture run hands to the public `lint.run` entry.
const Run = struct {
    gate: bool = false,
    against: ?[]const u8 = null,
    accept: bool = false,
    config: ?*const lint_config.Config = null,
};

/// Write the fixture entry file over the repository's `main.my`.
fn writeFixture(temp: *std.testing.TmpDir, bytes: []const u8) !void {
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = bytes });
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
    try gitOk(allocator, root, &.{ "add", "main.my" });
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
    var analysis = try quality.analyzeWithExports(scratch, program, compilation.src, .{}, exports);
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
    try proj.load(files.provider(), "main", .{});
    var index = try interfaces.build(&proj);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const entry = try std.fs.path.join(scratch, &.{ root, "main.my" });
    return lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = run.config,
        .entry_path = entry,
        .options = .{ .gate = run.gate, .against = run.against, .accept = run.accept },
        .diagnostics = .text,
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
    try temp.dir.createDirPath(t.io, ".mylang/lint");
    try temp.dir.writeFile(t.io, .{ .sub_path = ".mylang/lint/baseline-change-without-test.txt", .data = "main|main::helper\n" });
    const suppressed = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD" });
    try t.expectEqual(@as(usize, 1), suppressed.blocking);

    // `--accept` must not create a baseline for the rule either.
    try temp.dir.deleteFile(t.io, ".mylang/lint/baseline-change-without-test.txt");
    _ = try evaluateFixture(scratch, root, .{ .gate = true, .against = "HEAD", .accept = true });
    try t.expectError(error.FileNotFound, temp.dir.access(t.io, ".mylang/lint/baseline-change-without-test.txt", .{}));
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
    \\    out.print("hello")
    \\    return 0
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

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
        \\func test_io(fs: Filesystem) -> bool effects():
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
        \\func test_end_to_end() -> bool effects():
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
        \\    out.print(1, 2, 3)
        \\    return draw(canvas=1, x=2, y=3)
    );
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try evaluateFixture(scratch, root, .{});
    try t.expect(findFinding(outcome, "L_POSITIONAL_LITERAL") == null);
}
