//! Exact field-read normalization preserves scalar stores after managed child updates.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const report = std.debug.print;
const release_flag = "--release";
const options = @import("core_test_options");
const language = @import("selka");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const fixture = @embedFile("a02_scalar_child_fixture.selka");

/// The historical fixture rewritten to statement form, with its stream method spelling replaced by the stream-first form.
fn statementControl(a: std.mem.Allocator, historical: []const u8) ![]const u8 {
    const statement_form = try std.mem.replaceOwned(u8, a, historical, "    const index = if len(args) > 0 then - 3 else -1", "    mut index = -1\n    if len(args) > 0:\n        index = -3");
    // The preserved historical text spells its stream methods; the derived control writes the stream-first form.
    return std.mem.replaceOwned(u8, a, statement_form, "out.print(", "print(out, ");
}

// spec-case: NEW-CORE-CE-LISTS-1
test "zero RC A02 scalar child writes preserve nested owned fields" {
    const historical = @embedFile("a02_scalar_child_control.selka");
    var retired = try language.Compilation.init(std.testing.allocator, "a02-historical.selka", historical);
    defer retired.deinit();
    try std.testing.expectError(error.SourceError, retired.check());
    try std.testing.expect(retired.diagnostics.items.len > 0);
    // The historical fixture is preserved byte for byte: its stream spelling in `main` is refused
    // first, and the conditional expression in its own body keeps its subject.
    try std.testing.expectEqualStrings("E_METHOD_REMOVED", retired.diagnostics.items[0].code);
    try std.testing.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", retired.diagnostics.items[1].code);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const statement_control = try statementControl(arena.allocator(), historical);
    try qualifies(std.testing.allocator, fixture, "302 2\n550278 1 1\n", false);
    try qualifies(std.testing.allocator, @embedFile("a02_scalar_child_reduced.selka"), "", false);
    try qualifiesOutcome(arena.allocator(), statement_control, .{ .stdout = "rhs\n", .trap = "R_LIST_BOUNDS" }, false);
    const modern = try std.mem.replaceOwned(u8, arena.allocator(), statement_control, "mut index = -1", "mut index = len(box.items) - 1");
    try qualifies(arena.allocator(), modern, "rhs\n99 2 1\n", false);
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "zero RC A02 scalar child writes preserve nested owned fields (release)" {
    try support.requireRelease();
    const historical = @embedFile("a02_scalar_child_control.selka");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const statement_control = try statementControl(arena.allocator(), historical);
    try std.testing.expect(!std.mem.eql(u8, statement_control, historical));
    try qualifies(std.testing.allocator, fixture, "302 2\n550278 1 1\n", true);
    try qualifies(std.testing.allocator, @embedFile("a02_scalar_child_reduced.selka"), "", true);
    try qualifiesOutcome(arena.allocator(), statement_control, .{ .stdout = "rhs\n", .trap = "R_LIST_BOUNDS" }, true);
    const modern = try std.mem.replaceOwned(u8, arena.allocator(), statement_control, "mut index = -1", "mut index = len(box.items) - 1");
    try qualifies(arena.allocator(), modern, "rhs\n99 2 1\n", true);
}

const Qualification = struct { stdout: []const u8, trap: ?[]const u8 = null };

fn qualifies(parent: std.mem.Allocator, source_text: []const u8, expected: []const u8, release: bool) !void {
    try qualifiesOutcome(parent, source_text, .{ .stdout = expected }, release);
}

/// Builds `source_text` in the debug mode (`release` false) or in the three release modes and checks the run against `expected`.
fn qualifiesOutcome(parent: std.mem.Allocator, source_text: []const u8, expected: Qualification, release: bool) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(a, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.selka", .data = source_text });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{release_flag}, &.{ release_flag, "--verify-facts" }, &.{ release_flag, "--no-facts" } };
    const selected: []const []const []const u8 = if (release) modes[1..] else modes[0..1];
    for (selected) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("A02 scalar child writes build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (expected.trap) |code| {
            try std.testing.expect(ran.term == .exited and ran.term.exited == 1);
            try std.testing.expectEqualStrings(expected.stdout, ran.stdout);
            try std.testing.expect(std.mem.indexOf(u8, ran.stderr, code) != null);
            continue;
        }
        if (ran.term != .exited or ran.term.exited != 0) report("A02 scalar child writes run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings(expected.stdout, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "retain", "release", "release_unique", "unique_test", "uniqueness" }) |kind| {
            for (parsed.object.get("sites").?.array.items) |site| {
                try std.testing.expect(!std.mem.eql(u8, site.object.get("kind").?.string, kind));
            }
        }
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |kind|
            try std.testing.expect(totals.get(kind) == null);
    }
}
