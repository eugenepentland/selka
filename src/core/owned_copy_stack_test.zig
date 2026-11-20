//! Only initialized worklist slots are read across growth and recursive copies.
const std = @import("std");
const native = @import("native_fixture.zig");

fn checkOwned(a: std.mem.Allocator) !void {
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const output = try native.buildProgram(a, root, .{ .source = @embedFile("runtime/owned_copy_stack_fixture.c"), .binary_name = "harness", .source_name = "harness.c" });
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    try environment.put("SELKA_COUNTERS", try std.fs.path.join(a, &.{ root, "counts.json" }));
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = &environment, .cwd = .{ .path = root } });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("copy stack paths passed; live=0\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "copy worklist initialized slots preserve active owners through boundary growth and recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try checkOwned(arena.allocator());
}
