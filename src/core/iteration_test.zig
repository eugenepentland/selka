//! Executable D1 live-place iteration contracts against the accepted checker forms.
const std = @import("std");
const options = @import("core_test_options");

fn liveRun(allocator: std.mem.Allocator, flags: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "test", try std.fs.path.join(a, &.{ options.fixtures, "i_live_place.my" }), "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "5 passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
}

// spec: NEW-CORE-ITERATION-1
test "live iteration refreshes shared elements, appends, mut callees and record fields while root rebinding snapshots" {
    try liveRun(std.testing.allocator, &.{});
    try liveRun(std.testing.allocator, &.{"--release"});
    try liveRun(std.testing.allocator, &.{ "--release", "--verify-facts" });
}
