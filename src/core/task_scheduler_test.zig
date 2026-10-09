//! TASK-SCHEDULER-1: C runtime stress, lazy startup and forbidden-fork guards.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("task_scheduler_fixture.c");
const Error = native.Error;
fn matrix(allocator: std.mem.Allocator) Error!usize {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, source, .{});
    var passed: usize = 0;
    for ([_][]const u8{ "1", "2", "8" }) |threads| {
        for ([_][]const u8{ "lazy", "budget", "frames", "stress" }) |mode| {
            const run = try fixture.run(mode, threads);
            try std.testing.expectEqual(@as(u8, 0), run.status);
            try std.testing.expectEqualStrings("", run.stderr);
            try std.testing.expect(run.stdout.len != 0);
            if (std.mem.eql(u8, mode, "stress")) try std.testing.expect(std.mem.indexOf(u8, run.stdout, "1010000 submits, binary depth 12, chain 2048") != null);
            passed += 1;
        }
        const batch = try fixture.run("batch", threads);
        try std.testing.expectEqual(@as(u8, 1), batch.status);
        try std.testing.expect(std.mem.indexOf(u8, batch.stderr, "R_TASK_FORK") != null);
    }
    for ([_][]const u8{ "2", "8" }) |threads| {
        const fork = try fixture.run("fork", threads);
        try std.testing.expectEqual(@as(u8, 1), fork.status);
        try std.testing.expect(std.mem.indexOf(u8, fork.stderr, "R_TASK_FORK") != null);
    }
    return passed;
}
// spec: TASK-SCHEDULER-1
test "scheduler runs million-submit deep nested and own-deque waits at 1 2 8 threads and prohibits fork" {
    try std.testing.expectEqual(@as(usize, 12), try matrix(std.testing.allocator));
}
