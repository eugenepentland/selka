//! SHARED-COUNTS-2: independent ownership counts check every enumerated edge.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("share_walk_fixture.c");
// spec: SHARED-COUNTS-2
test "share traversal matches destruction for every block kind and a hundred thousand levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var fixture = try native.Fixture.init(arena.allocator(), root, source, .{ .counted = true });
    const run = try fixture.run("normal", "1");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("share walk: all block kinds, aliases, guards, tombstones, providers and 100000 levels ok\n", run.stdout);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"live_bytes_at_exit\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"share_marks\":100033,") != null);
}
// spec-case: SHARED-COUNTS-2
test "plain saturation shares descendants before future immortal publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var fixture = try native.Fixture.init(arena.allocator(), root, source, .{ .counted = true });
    const run = try fixture.run("saturation", "8");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("plain saturation shares descendants before immortal publication (8 workers)\n", run.stdout);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"share_marks\":2,") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.counts, "\"share_bytes\":128,") != null);
}
