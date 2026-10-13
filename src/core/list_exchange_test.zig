//! Exchange transfers exactly one owner without allocating a replacement list.
const std = @import("std");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");

// spec: OWNED-LIST-EXCHANGE-1
test "list exchange transfers nested wide recursive values in every ownership build mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "exchange.my", .data = @embedFile("list_exchange_fixture.my") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "exchange.my" });
    const binary = try std.fs.path.join(a, &.{ root, "exchange" });
    const llvm = try std.fs.path.join(a, &.{ root, "exchange.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    for ([_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("exchange build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("exchange run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("exchange passed\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        for ([_][]const u8{ "live_bytes_at_exit", "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
            try std.testing.expectEqual(@as(i64, 0), totals.get(name).?.integer);
        const kinds = parsed.object.get("kinds").?.object;
        for ([_][]const u8{ "retain", "release", "unique_test" }) |name|
            try std.testing.expectEqual(@as(i64, 0), kinds.get(name).?.object.get("count").?.integer);
        for ([_][]const u8{ "negative", "positive", "empty", "unsigned-max" }) |scenario| {
            // Fatal counted runs use the default counter filename. Keep their
            // output inside this test's temporary directory as well.
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .cwd = .{ .path = root } });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "error[R_LIST_BOUNDS]") != null);
        }
    }
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "list exchange RC snapshots preserve independent old and replacement values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const fixture =
        \\func main(out: Stream) -> int:
        \\    mut rows = [[1], [2]]
        \\    mut saved = rows.snapshot()
        \\    mut old = rows.exchange(-1, [7])
        \\    old.append(9)
        \\    saved[0].append(8)
        \\    assert old == [2, 9]
        \\    assert rows == [[1], [7]]
        \\    assert saved == [[1, 8], [2]]
        \\    out.print("RC exchange passed")
        \\    return 0
    ;
    try dir.dir.writeFile(io, .{ .sub_path = "snapshot.my", .data = fixture });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "snapshot.my" });
    const binary = try std.fs.path.join(a, &.{ root, "snapshot" });
    for ([_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--cache-dir", root, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("RC exchange build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("RC exchange run ({any}): {s}{s}\n", .{ ran.term, ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("RC exchange passed\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}
