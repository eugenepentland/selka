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
        .output = try std.fs.path.join(arena.allocator(), &.{ root, "p" }),
        .mode = .debug,
        .links = &.{},
    }, &log);
    try std.testing.expectError(error.ToolFailed, outcome);
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot run /nonexistent/mylang-core-test/zig") != null);
}

// spec: NEW-CORE-S4-RUNTIME-CACHE-1
test "runtime objects share one per-user directory unless the override keeps them local" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const work = try std.fs.path.join(a, &.{ root, "work" });
    var environ: std.process.Environ.Map = .init(a);
    try std.testing.expectEqualStrings(work, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("HOME", root);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, ".cache", "mylang", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("XDG_CACHE_HOME", "relative");
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, ".cache", "mylang", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("XDG_CACHE_HOME", root);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "mylang", "core-runtime" }), try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    const explicit = try std.fs.path.join(a, &.{ root, "explicit" });
    try environ.put("MYLANG_CORE_RUNTIME_CACHE", explicit);
    try std.testing.expectEqualStrings(explicit, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
    try environ.put("MYLANG_CORE_RUNTIME_CACHE", "");
    try std.testing.expectEqualStrings(work, try driver.runtimeDirectory(a, std.testing.io, &environ, work));
}
