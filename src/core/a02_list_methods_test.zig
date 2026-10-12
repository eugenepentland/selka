//! Managed list permutations preserve one owner of every stored child.
const std = @import("std");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_list_methods_fixture.my");

// spec: OWNED-LIST-MUTATION-1
// spec: OWNED-LIST-COPYING-1
test "zero RC A02 list methods move nested wide recursive children and preserve traps" {
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
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 list methods build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_list_rotate") != null);
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_list_reverse") != null);
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 list methods run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("500\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "retain", "release", "uniqueness" }) |kind| {
            for (parsed.object.get("sites").?.array.items) |site| {
                if (std.mem.eql(u8, site.object.get("kind").?.string, kind)) try std.testing.expectEqual(@as(i64, 0), site.object.get("count").?.integer);
            }
        }
        for ([_][]const u8{ "negative", "positive", "empty", "missing" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            if (failed.term != .exited or failed.term.exited != 1) std.debug.print("A02 trap {s}: {any} {s}{s}\n", .{ scenario, failed.term, failed.stdout, failed.stderr });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "missing")) "error[R_LIST_VALUE]" else "error[R_LIST_BOUNDS]") != null);
            if (!std.mem.eql(u8, scenario, "missing")) try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "\"operation\":\"pop\"") != null);
        }
    }
}
