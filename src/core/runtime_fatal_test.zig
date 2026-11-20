//! TASK-FATAL-1: timeouts, fatal re-entry and contended stream reports.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("runtime_fatal_fixture.c");

fn fatalMatrix(a: std.mem.Allocator) native.Error!usize {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, source, .{});
    defer fixture.environment.deinit();
    var passed: usize = 0;
    for ([_][]const u8{ "alarm-window", "alarm-worker" }) |mode| {
        const run = try fixture.run(mode, "2");
        try std.testing.expectEqual(@as(u8, 1), run.status);
        try std.testing.expectEqualStrings("", run.stdout);
        try std.testing.expect(std.mem.indexOf(u8, run.stderr, "R_TIMEOUT:") != null);
        passed += 1;
    }
    for ([_][]const u8{ "1", "2" }) |threads| {
        const run = try fixture.run("exit", threads);
        try std.testing.expectEqual(@as(u8, 2), run.status);
        try std.testing.expect(std.mem.indexOf(u8, run.stderr, "InvalidCapability") != null);
        passed += 1;
    }
    const reentry = try fixture.run("reentry", "2");
    try std.testing.expectEqual(@as(u8, 0), reentry.status);
    try std.testing.expectEqualStrings("", reentry.stderr);
    const waiting = try fixture.run("reentry-wait", "2");
    try std.testing.expectEqual(@as(u8, 0), waiting.status);
    try std.testing.expectEqualStrings("", waiting.stderr);
    return passed + 2;
}

// spec: TASK-FATAL-1
test "fatal timeouts escape a blocked winner and CAS interval and preserve exit status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 6), try fatalMatrix(arena.allocator()));
}

// spec-case: TASK-FATAL-1
test "fatal reporting waits for a slow pipe committing a complete one MiB unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try native.Fixture.init(a, root, source, .{});
    defer fixture.environment.deinit();
    const run = try fixture.run("slow-pipe", "2");
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqual(@as(usize, 1 << 20), run.stdout.len);
    try std.testing.expect(std.mem.allEqual(u8, run.stdout, 'x'));
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "fatal-task.selka:7:3: error[R_DIVISION_BY_ZERO]") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "item 37") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "R_TIMEOUT") == null);
}
