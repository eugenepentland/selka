//! List mutation, receiver snapshots and checked failures at every core mode.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ options.fixtures, "m_list_methods.selka" });
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "test", source, "--json", "--cache-dir", root });
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
