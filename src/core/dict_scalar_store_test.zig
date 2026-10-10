//! Scalar dictionary stores retain COW, exact narrow/float bits and unit layouts.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(arena: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena);
    const source = try std.fs.path.join(arena, &.{ options.fixtures, "d_scalar_stores.my" });
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{"--unoptimized"}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(arena, &.{ options.core_path, "test", source, "--json", "--cache-dir", root });
        try argv.appendSlice(arena, mode);
        const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 0) report("scalar store fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, arena, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 5), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
    }
}

// spec-case: NEW-CORE-DICT-1
test "scalar dictionary stores preserve snapshots, indexed tombstones, bool, unit, narrow integers and float NaNs in every mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}
