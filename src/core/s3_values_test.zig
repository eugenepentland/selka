//! Deep shared value graphs, rendering and repeat snapshot qualification.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const fixture = try std.fmt.allocPrint(a, "{s}/m_recursive_values.my", .{options.fixtures});
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "test", fixture, "--json", "--cache-dir", root });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 0 or result.stderr.len != 0)
            report("S3 values fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 6), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
    }
}

// spec: NEW-CORE-S3-VALUES-1
test "S3 values preserve source shapes unit payloads marker data and ancestor supersession" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}
