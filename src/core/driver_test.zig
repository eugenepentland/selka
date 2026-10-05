//! Native driver tests.
const std = @import("std");
const driver = @import("driver.zig");

// spec: NEW-CORE-DRIVER-1
test "a compiler that cannot run fails the build with ToolFailed and says why" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var environment = std.process.Environ.Map.init(arena.allocator());
    var log: std.ArrayList(u8) = .empty;
    const outcome = driver.link(arena.allocator(), std.testing.io, &environment, .{
        .zig = "/nonexistent/mylang-core-test/zig",
        .work = root,
        .program = try std.fs.path.join(arena.allocator(), &.{ root, "p.ll" }),
        .output = try std.fs.path.join(arena.allocator(), &.{ root, "p" }),
        .release = false,
        .links = &.{},
        .llvm = "",
    }, &log);
    try std.testing.expectError(error.ToolFailed, outcome);
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot run /nonexistent/mylang-core-test/zig") != null);
}
