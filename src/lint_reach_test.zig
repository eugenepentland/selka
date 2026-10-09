//! `untested-export` reachability: the `agent` profile counts an export any
//! discovered test reaches, directly or transitively, as tested, while `strict`
//! keeps the direct-call fact and names the transitive-only case instead of
//! claiming nothing calls it. Both readings come from the one index `mylang
//! tests-for` answers from, so the rule and the command cannot disagree.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const navigation = @import("navigation.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");

const lint = language.lint;

/// Fixture: one export a test reaches only through a private helper
/// (`as_text` <- `render` <- `test_render`), one export no test reaches at all
/// (`orphan`), and an entry point.
const reach_fixture =
    \\
    \\
    \\public func as_text(value: int) -> int:
    \\    return value + 1
    \\
    \\
    \\func render(value: int) -> int:
    \\    return as_text(value)
    \\
    \\
    \\public func orphan(value: int) -> int:
    \\    return value - 1
    \\
    \\
    \\func test_render() -> bool effects():
    \\    return render(1) == 2
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// Evaluate the whole lint pipeline over the fixture entry at `root` without
/// writing to stdout, which is the test runner's own protocol pipe.
fn evaluateFixture(scratch: std.mem.Allocator, root: []const u8, profile: ?lint_config.Profile, gate: bool) !lint.Outcome {
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
        .config = null,
        .entry_path = entry,
        .options = .{ .gate = gate, .profile = profile },
        .diagnostics = .text,
    }, scratch);
}

/// The `L_UNTESTED_EXPORT` finding one run reported for `qualified`, or null
/// when it reported none.
fn untestedFinding(outcome: lint.Outcome, qualified: []const u8) ?lint.Finding {
    for (outcome.findings) |finding| {
        if (!std.mem.eql(u8, finding.code, "L_UNTESTED_EXPORT")) continue;
        if (std.mem.eql(u8, finding.subject.qualified, qualified)) return finding;
    }
    return null;
}

/// Write the reachability fixture as one module entry under a fresh temp root.
/// The root keeps its sentinel so the caller frees the allocation it got.
fn writeReachFixture(temp: *std.testing.TmpDir) ![:0]u8 {
    try temp.dir.writeFile(t.io, .{ .sub_path = "main.my", .data = reach_fixture });
    return temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

// spec: LINT-7
test "untested-export counts transitive test reach under agent and names it under strict" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeReachFixture(&temp);
    defer t.allocator.free(root);

    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    // Under `agent` the transitively reached accessor is tested, the export no
    // test reaches is still reported, and only `strict` would make it refuse.
    const agent = try evaluateFixture(scratch, root, null, true);
    try t.expect(untestedFinding(agent, "main::as_text") == null);
    const orphan = untestedFinding(agent, "main::orphan");
    try t.expect(orphan != null);
    try t.expect(std.mem.indexOf(u8, orphan.?.message, "is not reached by any discovered test") != null);
    try t.expect(orphan.?.severity == .warning);

    // Under `strict` the direct-call fact still reports the accessor, with the
    // transitive-only wording rather than "not called", and it blocks.
    const strict = try evaluateFixture(scratch, root, .strict, true);
    const transitive = untestedFinding(strict, "main::as_text");
    try t.expect(transitive != null);
    try t.expect(std.mem.indexOf(u8, transitive.?.message, "reached only transitively") != null);
    try t.expect(transitive.?.severity == .err);
    const unreached = untestedFinding(strict, "main::orphan");
    try t.expect(unreached != null);
    try t.expect(std.mem.indexOf(u8, unreached.?.message, "is not called directly by any test_ function") != null);
}

// spec-case: LINT-7
test "the agent lint verdict and tests-for agree on every export of the fixture" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try writeReachFixture(&temp);
    defer t.allocator.free(root);

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
    const entry = try std.fs.path.join(scratch, &.{ root, "main.my" });
    const agent = try lint.evaluate(.{
        .memory = scratch,
        .io = t.io,
        .compilation = &compilation,
        .config = null,
        .entry_path = entry,
        .options = .{ .profile = null },
        .diagnostics = .text,
    }, scratch);

    const reached = try navigation.renderTestsFor(scratch, &compilation, "main::as_text");
    const orphan = try navigation.renderTestsFor(scratch, &compilation, "main::orphan");
    try t.expect(std.mem.indexOf(u8, reached.?, "reached-by (1):") != null);
    try t.expect(std.mem.indexOf(u8, reached.?, "main::test_render") != null);
    try t.expect(std.mem.indexOf(u8, orphan.?, "reached-by (0):") != null);
    try t.expect(untestedFinding(agent, "main::as_text") == null);
    try t.expect(untestedFinding(agent, "main::orphan") != null);
}
