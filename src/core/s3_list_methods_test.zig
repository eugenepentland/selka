//! List mutation, receiver snapshots and checked failures at every core mode.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ options.fixtures, "m_list_methods.my" });
    var environment = try options.privateEnvironment(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{"--unoptimized"}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", source, "--json", "--cache-dir", root });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1 or result.stderr.len != 0)
            report("S3 list methods fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_VALUE") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_BOUNDS") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_SLICE_STEP") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_BOUNDS (index -99, length 2)") != null);
    }
}

// spec: NEW-CORE-LIST-S3-2
test "list search splice and stepped slices preserve snapshots owned children and exact failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}

// spec-case: OWNED-LIST-MUTATION-1
// spec-case: LIST-SORT-KEY-1
test "zero RC keyed sorting gathers wide managed records with stable independent children" {
    const zero = @import("zero_rc.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "sort.my", .data = @embedFile("gap_sort_fixture.my") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "sort.my" });
    const binary = try std.fs.path.join(a, &.{ root, "sort" });
    const llvm = try std.fs.path.join(a, &.{ root, "sort.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    for ([_][]const []const u8{ &.{"--unoptimized"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("owned keyed sort build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_sort_keyed") != null);
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("owned keyed sort run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("owned keyed sorting preserved children and stability\n", ran.stdout);
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

// spec-case: OWNED-LIST-MUTATION-1
// spec-case: LIST-SORT-KEY-1
test "zero RC keyed sorting optional scratch failure preserves managed cycle fallback" {
    const driver = @import("driver.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "core_rt.c", .data = driver.runtime_source });
    try dir.dir.writeFile(io, .{ .sub_path = "fixture.c", .data = @embedFile("gap_sort_failure_fixture.c") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const source = try std.fs.path.join(a, &.{ root, "fixture.c" });
    const binary = try std.fs.path.join(a, &.{ root, "fixture" });
    const built = try std.process.run(a, io, .{
        .argv = &.{ environment.get("ZIG") orelse "zig", "cc", "-O2", "-std=c11", "-pthread", "-DMYL_ZERO_RC=1", source, "-o", binary },
        .environ_map = &environment,
    });
    try std.testing.expectEqualStrings("", built.stderr);
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expectEqualStrings("scratch success and failure preserve stable managed ownership\n", ran.stdout);
}
