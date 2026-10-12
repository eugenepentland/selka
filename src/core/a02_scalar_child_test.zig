//! Exact field-read normalization preserves scalar stores after managed child updates.
const std = @import("std");
const report = std.debug.print;
const release_flag = "--release";
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_scalar_child_fixture.my");

// spec-case: NEW-CORE-CE-LISTS-1
test "zero RC A02 scalar child writes preserve nested owned fields" {
    try qualifies(std.testing.allocator, fixture, "302 2\n550278 1 1\n");
    try qualifies(std.testing.allocator, @embedFile("a02_scalar_child_reduced.my"), "");
    try qualifies(std.testing.allocator, @embedFile("a02_scalar_child_control.my"), "rhs\n99 2 1\n");
}

fn qualifies(parent: std.mem.Allocator, source_text: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.my", .data = source_text });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.my" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    const modes = [_][]const []const u8{ &.{release_flag}, &.{"--unoptimized"}, &.{ release_flag, "--verify-facts" }, &.{"--optimize-debug"}, &.{ release_flag, "--no-facts" } };
    for (modes) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("A02 scalar child writes build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("A02 scalar child writes run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings(expected, ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "retain", "release", "unique_test", "uniqueness" }) |kind| {
            for (parsed.object.get("sites").?.array.items) |site| {
                if (std.mem.eql(u8, site.object.get("kind").?.string, kind)) try std.testing.expectEqual(@as(i64, 0), site.object.get("count").?.integer);
            }
        }
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |kind|
            try std.testing.expectEqual(@as(i64, 0), totals.get(kind).?.integer);
    }
}
