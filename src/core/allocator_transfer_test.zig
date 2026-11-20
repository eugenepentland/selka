//! RUNTIME-THREADS-2: repeated cross-thread frees reuse bounded storage at every small size class.
const std = @import("std");
const native = @import("native_fixture.zig");
const source = @embedFile("allocator_transfer_fixture.c");

/// The most blocks a growth run may carve. Reuse keeps it near 200 at two threads and 400
/// at eight, whatever the round count; a run that stopped reusing what other threads freed
/// would carve 64 blocks a round, so this catches a leak of one block in every two rounds.
const growth_carved_limit: u64 = 4096;

fn checkTransfers(allocator: std.mem.Allocator, options: native.Options, mode: []const u8, carved_limit: ?u64) native.Error!u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = directory.dir.realPathFileAlloc(std.testing.io, ".", a) catch return error.TestUnexpectedResult;
    var fixture = try native.Fixture.init(a, root, source, options);
    defer fixture.environment.deinit();
    for ([_][]const u8{ "2", "8" }) |threads| {
        const ran = try fixture.run(mode, threads);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "live=0") != null);
        if (carved_limit) |limit| try std.testing.expect(try carved(ran.stdout) <= limit);
    }
    return 0;
}

/// The `carved=` count a transfer run prints.
fn carved(stdout: []const u8) native.Error!u64 {
    const start = (std.mem.indexOf(u8, stdout, "carved=") orelse return error.TestUnexpectedResult) + "carved=".len;
    const end = std.mem.indexOfScalarPos(u8, stdout, start, ' ') orelse return error.TestUnexpectedResult;
    return std.fmt.parseInt(u64, stdout[start..end], 10) catch error.TestUnexpectedResult;
}

// spec: RUNTIME-THREADS-2
test "allocator transfer reuses bounded storage over 10000 rounds under 64 MiB at two and eight threads" {
    try std.testing.expectEqual(@as(u8, 0), try checkTransfers(std.testing.allocator, .{}, native.stressMode("growth", "growth-full"), growth_carved_limit));
}

// spec-case: RUNTIME-THREADS-2
test "allocator transfer changing small size classes keeps exact live accounting" {
    try std.testing.expectEqual(@as(u8, 0), try checkTransfers(std.testing.allocator, .{ .counted = true }, "varied", null));
}

// spec-case: RUNTIME-THREADS-2
test "allocator transfer cross-thread reuse has no ThreadSanitizer races" {
    try std.testing.expectEqual(@as(u8, 0), try checkTransfers(std.testing.allocator, .{ .sanitized = true }, "sanitized-varied", null));
}

test "a transfer run's carved count is read from its report line" {
    try std.testing.expectEqual(@as(u64, 342), try carved("allocator transfer: growth rounds=10000 carved=342 live=0\n"));
    try std.testing.expectError(error.TestUnexpectedResult, carved("allocator transfer: growth rounds=10000 live=0\n"));
}
