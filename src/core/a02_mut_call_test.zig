//! Checked mutable calls transfer and reattach exactly one interior child owner.
const std = @import("std");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_mut_call_fixture.my");

// spec: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A02 interior mut calls preserve child ownership and selected places" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.my", .data = fixture });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.my" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 interior mut calls build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 interior mut calls run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("41 1 8 19\n", ran.stdout);
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
        for ([_][]const u8{ "missing", "bounds" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expectEqualStrings("", failed.stdout);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "bounds")) "R_LIST_BOUNDS" else "R_MISSING_KEY") != null);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A02 interior mut calls reject overlapping parent roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const source =
        \\func pair(mut left: int[], mut right: int[]):
        \\    left.append(1)
        \\    right.append(2)
        \\func main() -> int:
        \\    mut rows = [[3], [4]]
        \\    pair(mut rows[0], mut rows[1])
        \\    return len(rows)
    ;
    try dir.dir.writeFile(io, .{ .sub_path = "overlap.my", .data = source });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "overlap.my" });
    const checked = try std.process.run(a, io, .{ .argv = &.{ options.core_path, "check", path, "--experimental-zero-rc" } });
    try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, checked.stderr, "E_SINGLE_OWNER_OVERLAP") != null);
}
