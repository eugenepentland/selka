//! Source unit dictionary keys use physical placeholders without exposing them.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn qualified(a: std.mem.Allocator) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ options.fixtures, "m_none_keys.my" });
    var environment = try options.privateEnvironment(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", source, "--json", "--cache-dir", root });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1 or result.stderr.len != 0)
            report("S3 None keys fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 5), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_MISSING_KEY") != null);
        for (parsed.value.object.get("tests").?.array.items) |test_result| {
            const name = test_result.object.get("name").?.string;
            const status = test_result.object.get("status").?.string;
            try std.testing.expectEqualStrings(if (std.mem.endsWith(u8, name, "test_missing_none_key_traps")) "failed" else "passed", status);
        }
    }
}

// spec-case: NEW-CORE-S3-VALUES-1
// spec-case: HASH-KEYS-1
test "None dictionary keys preserve evaluation storage hashing mutation snapshots and exact missing-key traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}
