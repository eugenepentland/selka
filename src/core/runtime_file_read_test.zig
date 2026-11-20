//! NEW-CORE-FILE-READ-1: the sized whole-file read (FR-018).
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("runtime_file_read_fixture.c");

fn runFixture(a: std.mem.Allocator, mode: []const u8) !native.Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    try fixture.environment.put("SELKA_CORE_LEAKCHECK", "1");
    try fixture.environment.put("FIXTURE_DIRECTORY", root);
    return fixture.run(mode, "1");
}

// spec: NEW-CORE-FILE-READ-1
test "a whole-file read fills one sized block in two reads and falls back for unsized and changing files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "read");
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("read: sized single copies, two reads per transfer, every fallback exact\n", run.stdout);
}

// spec-case: NEW-CORE-FILE-READ-1
test "a whole-file read above the byte ceiling traps the memory budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "budget");
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "error[R_MEMORY_BUDGET]") != null);
}
