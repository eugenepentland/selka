//! Independent set construction and owned text selection from generator folds.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const report = std.debug.print;
const release_flag = @import("e2e_test.zig").optimize_flag;
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const language = @import("selka");

// spec-case: SET-1
// spec-case: PY-GENERATOR-1
test "zero RC A02 public constructors preserve owned keys and generator results" {
    try qualifies(std.testing.allocator, @embedFile("a02_public_constructors_fixture.selka"), "3 2 2 pear-1 value-4 value-5\n");
}

// The original fixture remains an executable retirement witness; the modern
// fixture above retains every native ownership mode and empty-fold trap check.
// spec-case: PY-GENERATOR-1
test "zero RC A02 original generator constructor source remains rejected" {
    var compilation = try language.Compilation.init(std.testing.allocator, "original-constructors.selka", @embedFile("a02_public_constructors_original.selka"));
    defer compilation.deinit();
    try std.testing.expectError(error.SourceError, compilation.check());
    try std.testing.expectEqualStrings("E_GENERATOR_REMOVED", compilation.diagnostics.items[0].code);
}

fn qualifies(parent: std.mem.Allocator, source_text: []const u8, expected: []const u8) !void {
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
    const modes = [_][]const []const u8{ &.{release_flag}, &.{ release_flag, "--verify-facts" }, &.{"--optimize-debug"}, &.{ release_flag, "--no-facts" } };
    for (modes) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("A02 public constructors build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("A02 public constructors run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings(expected, ran.stdout);
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
        for ([_][]const u8{ "min", "max" }) |scenario| {
            const trapped = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            try std.testing.expect(trapped.term == .exited and trapped.term.exited == 1);
            try std.testing.expectEqualStrings("", trapped.stdout);
            try std.testing.expect(std.mem.indexOf(u8, trapped.stderr, "arg is an empty sequence") != null);
        }
    }
}
