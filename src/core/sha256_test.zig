//! SHA-256 in the C runtime (`runtime/core_sha256.c`): the portable compression and, where the CPU has them, the x86
//! SHA extensions agree with the FIPS 180-4 vectors, with each other (the portable path runs on a machine that has SHA-NI
//! too) and with `std.crypto.hash.sha2.Sha256` at every length from 0 to 200.
const std = @import("std");
const native = @import("native_fixture.zig");

fn pattern(buffer: []u8, length: usize) []const u8 {
    for (buffer[0..length], 0..) |*octet, index| octet.* = @intCast((index * 7 + 3) % 256);
    return buffer[0..length];
}

fn checkPaths(a: std.mem.Allocator) !void {
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const output = try native.buildProgram(a, root, .{ .source = @embedFile("runtime/sha256_fixture.c"), .binary_name = "harness", .source_name = "harness.c" });
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = &environment, .cwd = .{ .path = root } });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    var lines = std.mem.splitScalar(u8, ran.stdout, '\n');
    const shani = lines.next().?;
    try std.testing.expect(std.mem.eql(u8, shani, "shani 1") or std.mem.eql(u8, shani, "shani 0"));
    var buffer: [200]u8 = undefined;
    for (0..201) |length| {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(pattern(&buffer, length), &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const expected = try std.fmt.allocPrint(a, "{d} {s} {s}", .{ length, hex, if (std.mem.eql(u8, shani, "shani 1")) hex[0..] else "-" });
        try std.testing.expectEqualStrings(expected, lines.next().?);
    }
    try std.testing.expectEqualStrings("sha256 paths agree: 16809 inputs compared", lines.next().?);
}

test "the portable and SHA-NI compressions match the FIPS vectors, each other and Zig's Sha256 at every length from 0 to 200" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try checkPaths(arena.allocator());
}
