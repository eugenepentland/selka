//! The optimized SHA-256 wrapper (`src/fast_sha256.zig`) against the standard library, in a
//! binary that links the optimized digest object.
const std = @import("std");
const fast = @import("selka").fast_sha256;

fn expectSame(bytes: []const u8) !void {
    var standard: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &standard, .{});
    var one_call: [32]u8 = undefined;
    fast.Sha256.hash(bytes, &one_call, .{});
    try std.testing.expectEqualSlices(u8, &standard, &one_call);
    // Streaming in odd pieces reaches the same digest.
    var hasher = fast.Sha256.init(.{});
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

/// A deterministic buffer of `length` bytes that does not repeat within a block.
fn pattern(buffer: []u8) []u8 {
    for (buffer, 0..) |*byte, index| byte.* = @truncate(index *% 31 +% 7);
    return buffer;
}

fn expectEveryBoundary() !void {
    var bytes: [70000]u8 = undefined;
    _ = pattern(&bytes);
    try expectSame("");
    try expectSame("abc");
    inline for ([_]usize{ 1, 54, 55, 56, 57, 63, 64, 65, 119, 120, 121, 127, 128, 129, 1000, 65536, 70000 }) |length| try expectSame(bytes[0..length]);
}

// spec: FAST-SHA256-1
test "the optimized SHA-256 object is linked here and agrees with the standard library at every padding boundary" {
    try std.testing.expectEqual(std.lang.Optimize.ReleaseFast, fast.objectMode());
    try expectEveryBoundary();
    // The published test vector, so the comparison does not rest on the standard library alone.
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    var abc: [32]u8 = undefined;
    fast.Sha256.hash("abc", &abc, .{});
    try std.testing.expectEqualSlices(u8, &expected, &abc);
}
