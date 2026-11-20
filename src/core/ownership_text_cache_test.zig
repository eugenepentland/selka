//! OWNERSHIP-TEXT-READONLY-1 (restated): published data, kind and length are never written after pool startup;
//! facts are written atomically into self-validated words; static storage is never written.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("ownership_text_cache_fixture.c");

fn runFixture(a: std.mem.Allocator, mode: []const u8) !native.Run {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    try fixture.environment.put("SELKA_CORE_LEAKCHECK", "1");
    return fixture.run(mode, "8");
}

// spec: OWNERSHIP-TEXT-READONLY-1
test "ownership text caches preserve cold and warm read-only pages across eight workers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "readonly");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("text cache: eight readers, cold and warm read-only pages, facts unchanged\n", run.stdout);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership runtime pointer-list drop preserves guarded deep and transferred owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const run = try runFixture(arena.allocator(), "drop");
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expectEqualStrings("owned drop: generated and general shapes, deep walk and eight transfers\n", run.stdout);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "ownership runtime drop keeps memory-budget enforcement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "budget", "buffer-budget" }) |mode| {
        const run = try runFixture(arena.allocator(), mode);
        try std.testing.expectEqual(@as(u8, 1), run.status);
        try std.testing.expectEqualStrings("", run.stdout);
        try std.testing.expect(std.mem.indexOf(u8, run.stderr, "error[R_MEMORY_BUDGET]") != null);
    }
}
