//! Managed list permutations preserve one owner of every stored child.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_list_methods_fixture.selka");

// spec: OWNED-LIST-MUTATION-1
// spec: OWNED-LIST-COPYING-1
test "zero RC A02 list methods move nested wide recursive children and preserve traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.selka", .data = fixture });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    // Keep the embedded historical fixture intact and execute its published migration.
    // Its seven method spellings are now refused first, one per function body, so the
    // negative-index refusal it also carries is shadowed in this compilation; the
    // fixture's `max(len(rows) - 999, 0)` repair below still proves that rule fires.
    const rejected = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", source } });
    try std.testing.expect(rejected.term == .exited and rejected.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_METHOD_REMOVED") != null);
    const repaired = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "fix", source } });
    try std.testing.expect(repaired.term == .exited and repaired.term.exited == 0);
    const modern = try std.Io.Dir.cwd().readFileAlloc(io, source, a, .limited(1 << 20));
    try std.testing.expect(!std.mem.eql(u8, fixture, modern));
    try std.testing.expect(std.mem.indexOf(u8, modern, "max(len(rows) - 999, 0)") != null);
    const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } };
    for (modes) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 list methods build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_list_rotate") != null);
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_list_reverse") != null);
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_same_block") != null);
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 list methods run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("500\n", ran.stdout);
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
        for ([_][]const u8{ "negative", "positive", "empty", "missing" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            if (failed.term != .exited or failed.term.exited != 1) std.debug.print("A02 trap {s}: {any} {s}{s}\n", .{ scenario, failed.term, failed.stdout, failed.stderr });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "missing")) "error[R_LIST_VALUE]" else "error[R_LIST_BOUNDS]") != null);
            if (!std.mem.eql(u8, scenario, "missing")) try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "\"operation\":\"pop\"") != null);
        }
    }
}
