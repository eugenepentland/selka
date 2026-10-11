//! Executable D1 live-place iteration contracts against the accepted checker forms.
const std = @import("std");
const options = @import("core_test_options");

fn liveRun(allocator: std.mem.Allocator, fixture: []const u8, expected: []const u8, flags: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "test", try std.fs.path.join(a, &.{ options.fixtures, fixture }), "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, expected) != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
}

// spec: NEW-CORE-ITERATION-1
test "live iteration refreshes shared elements, appends, mut callees and record fields while root rebinding snapshots" {
    try liveRun(std.testing.allocator, "i_live_place.my", "5 passed", &.{});
    try liveRun(std.testing.allocator, "i_live_place.my", "5 passed", &.{"--release"});
    try liveRun(std.testing.allocator, "i_live_place.my", "5 passed", &.{ "--release", "--verify-facts" });
}

// spec-case: NEW-CORE-ITERATION-1
test "nested any and all gathers stop outer iteration with exact mut effects in every guest mode" {
    try liveRun(std.testing.allocator, "i_nested_gather.my", "2 passed", &.{});
    try liveRun(std.testing.allocator, "i_nested_gather.my", "2 passed", &.{"--release"});
    try liveRun(std.testing.allocator, "i_nested_gather.my", "2 passed", &.{ "--release", "--verify-facts" });
}
