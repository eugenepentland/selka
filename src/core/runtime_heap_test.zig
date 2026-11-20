//! RUNTIME-HEAP-RETAIN-1: the program entry's heap policy (FR-017). RUNTIME-HEAP-RETURN-1: what an idle poller wait gives back.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("runtime_heap_fixture.c");

fn runFixture(a: std.mem.Allocator, mode: []const u8) !native.Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    try fixture.environment.put("SELKA_CORE_LEAKCHECK", "1");
    return fixture.run(mode, "1");
}

// spec: RUNTIME-HEAP-RETAIN-1
test "runtime start keeps request-sized blocks in the heap with exact budget and leak counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "heap");
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("heap: request-shaped cycles stay in the heap; budget and leak counts exact\n", run.stdout);
}

// spec: RUNTIME-HEAP-RETURN-1
test "an idle poller wait gives free memory back once, and a busy or short one leaves it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "trim");
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("trim: an idle poller wait gives free memory back once; a busy or short one leaves it\n", run.stdout);
}
