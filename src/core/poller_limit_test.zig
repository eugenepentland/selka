//! POLLER-LIMIT-1: a poller holds as many connections as the process may open descriptors, not 1,024.
//! The runtime's poller runs natively against real loopback sockets (`poller_limit_fixture.c`), under
//! AddressSanitizer's leak check, one mode of the fixture per test.
const std = @import("std");
const native = @import("native_fixture.zig");

fn expectMode(a: std.mem.Allocator, mode: []const u8, line: []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const binary = try native.buildProgram(a, root, .{
        .source = @embedFile("poller_limit_fixture.c"),
        .binary_name = "poller-limit",
        .flags = &.{ "-O1", "-fno-inline-functions", "-std=c11", "-pthread" },
        .address_sanitized = true,
    });
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{ binary, mode }, .environ_map = &environment });
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings(line, ran.stdout);
}

// spec-case: NETWORK-POLL-1
test "a poller holds more than 1,024 connections in one process and answers on the last" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectMode(arena.allocator(), "grow", "grow: held 1100 connections past 1,024, the last answered, the bound above 1,024\n");
}

// spec-case: NETWORK-POLL-4
test "a poller's connection limit is the descriptor limit less 64 and the first id is the one it always was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectMode(arena.allocator(), "bound", "bound: the connection limit is the descriptor limit less 64\n");
}

// spec-case: NETWORK-POLL-1
test "a poller at its limit answers full and takes the waiting client after a close" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectMode(arena.allocator(), "full", "full: 1236 connections held, the next answered full and taken after a close\n");
}

// spec-case: NETWORK-POLL-1
test "a poller whose process has no descriptor to accept with answers full, not failed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectMode(arena.allocator(), "descriptors", "descriptors: an accept without a descriptor answers full\n");
}
