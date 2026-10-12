//! Exact number grammar/formatting contracts, including safe partial SWAR words.
const std = @import("std");
const options = @import("core_test_options");

fn numberRun(allocator: std.mem.Allocator, flags: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "test", try std.fs.path.join(a, &.{ options.fixtures, "n_numbers.my" }), "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "3 passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
}

// spec: NEW-CORE-NUMBER-1
test "number text preserves all word widths, signs, grammar, overflow and decimal edges" {
    try numberRun(std.testing.allocator, &.{});
    try numberRun(std.testing.allocator, &.{"--release"});
    try numberRun(std.testing.allocator, &.{ "--release", "--verify-facts" });
}
