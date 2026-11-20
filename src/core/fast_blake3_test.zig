//! The optimized BLAKE3 wrapper (`fast_blake3.zig`) against the standard library, in a binary
//! that links the optimized object.
const std = @import("std");
const fast = @import("fast_blake3.zig");

fn pattern(buffer: []u8) []u8 {
    for (buffer, 0..) |*byte, index| byte.* = @truncate(index *% 131 +% 17);
    return buffer;
}

fn expectSame(bytes: []const u8) !void {
    var standard: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &standard, .{});
    var one_call: [32]u8 = undefined;
    fast.hash(bytes, &one_call);
    try std.testing.expectEqualSlices(u8, &standard, &one_call);
    // Streaming in growing odd pieces reaches the same digest.
    var hasher = fast.Blake3.init(.{});
    var at: usize = 0;
    var piece: usize = 1;
    while (at < bytes.len) : (piece = piece * 3 + 1) {
        const end = @min(bytes.len, at + piece);
        hasher.update(bytes[at..end]);
        at = end;
    }
    var streamed: [32]u8 = undefined;
    hasher.final(&streamed);
    try std.testing.expectEqualSlices(u8, &standard, &streamed);
}

fn expectEveryBoundary() !void {
    var bytes: [200000]u8 = undefined;
    _ = pattern(&bytes);
    try expectSame("");
    try expectSame("abc");
    // Block (64), chunk (1024) and tree boundaries, and sizes that need several subtrees.
    inline for ([_]usize{ 1, 63, 64, 65, 127, 128, 129, 1023, 1024, 1025, 2047, 2048, 2049, 3072, 4096, 4097, 8192, 8193, 65536, 65537, 131072, 200000 }) |length| try expectSame(bytes[0..length]);
}

// spec-case: FAST-BLAKE3-1
test "a shorter output of the one-call hash is the prefix of the standard library's digest" {
    var bytes: [3000]u8 = undefined;
    _ = pattern(&bytes);
    var standard: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(&bytes, &standard, .{});
    var eight: [8]u8 = undefined;
    var sixteen: [16]u8 = undefined;
    var slice_buffer: [20]u8 = undefined;
    fast.hash(&bytes, &eight);
    fast.hash(&bytes, &sixteen);
    fast.hash(&bytes, slice_buffer[0..20]);
    try std.testing.expectEqualSlices(u8, standard[0..8], &eight);
    try std.testing.expectEqualSlices(u8, standard[0..16], &sixteen);
    try std.testing.expectEqualSlices(u8, standard[0..20], &slice_buffer);
}

// spec: FAST-BLAKE3-1
test "the optimized BLAKE3 object is linked here and agrees with the standard library at every block and chunk boundary" {
    try std.testing.expectEqual(std.lang.Optimize.ReleaseFast, fast.objectMode());
    try expectEveryBoundary();
    // The reference vector for the empty input from the BLAKE3 specification.
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262");
    var empty: [32]u8 = undefined;
    fast.hash("", &empty);
    try std.testing.expectEqualSlices(u8, &expected, &empty);
}
