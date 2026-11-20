//! Allocation arithmetic must refuse impossible storage before allocation or copying.
const std = @import("std");
const native = @import("native_fixture.zig");
const fixture = @embedFile("a02_capacity_fixture.c");

// spec: OWNED-CAPACITY-BOUNDS-1
test "A02 capacity rejects arithmetic overflow and preserves ordinary owned growth" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const binary = try native.buildProgram(a, root, .{ .source = fixture });
    for (0..13) |scenario| {
        const ran = try std.process.run(a, io, .{
            .argv = &.{ binary, try std.fmt.allocPrint(a, "{d}", .{scenario}) },
            .environ_map = &environment,
        });
        try std.testing.expect(ran.term == .exited);
        try std.testing.expectEqual(@as(u8, if (scenario == 0) 0 else 1), ran.term.exited);
        try std.testing.expectEqualStrings(if (scenario == 0) "preserved\n" else "", ran.stdout);
        try std.testing.expectEqualStrings(if (scenario == 0) "" else if (scenario == 9)
            "error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE\n"
        else
            "fatal: out of memory\n", ran.stderr);
    }
}
