//! Bounded artifact SHA-256 through the narrow LLVM helper object.
const std = @import("std");
const State = @import("component_digest_abi.zig").State;
extern fn mylang_component_sha_hash(bytes: [*]const u8, length: usize, digest: *[32]u8) callconv(.c) void;
extern fn mylang_component_sha_init(state: *State) callconv(.c) void;
extern fn mylang_component_sha_update(state: *State, bytes: [*]const u8, length: usize) callconv(.c) void;
extern fn mylang_component_sha_final(state: *State, digest: *[32]u8) callconv(.c) void;
/// Incremental content authentication with private fixed storage.
pub const Hasher = struct {
    state: State,
    /// Initialize an independent stream.
    pub fn init() Hasher {
        var self: Hasher = undefined;
        mylang_component_sha_init(&self.state);
        return self;
    }
    /// Authenticate another chunk, including an empty one.
    pub fn update(self: *Hasher, bytes: []const u8) void {
        mylang_component_sha_update(&self.state, bytes.ptr, bytes.len);
    }
    /// Finish the stream and return its exact SHA-256 identity.
    pub fn final(self: *Hasher) [32]u8 {
        var digest: [32]u8 = undefined;
        mylang_component_sha_final(&self.state, &digest);
        return digest;
    }
};
/// Authenticate an immutable snapshot using the same implementation as streams.
pub fn hash(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    mylang_component_sha_hash(bytes.ptr, bytes.len, &digest);
    return digest;
}
fn fillData(bytes: []u8) void {
    for (bytes, 0..) |*byte, index| byte.* = @truncate(index *% 137);
}
// spec-case: SELFHOST-FRONTEND-VERIFY-1
test "component SHA matches standard SHA across chunks and padding boundaries" {
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &std.fmt.bytesToHex(hash(""), .lower));
    var data: [65537]u8 = undefined;
    fillData(&data);
    for ([_]usize{ 0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 65535, 65536, 65537 }) |length| {
        var expected: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data[0..length], &expected, .{});
        try std.testing.expectEqualSlices(u8, &expected, &hash(data[0..length]));
        for ([_]usize{ 1, 7, 63, 64, 65, 4096, 65536 }) |chunk| {
            var stream = Hasher.init();
            var position: usize = 0;
            stream.update("");
            while (position < length) {
                const end = @min(length, position + chunk);
                stream.update(data[position..end]);
                position = end;
            }
            try std.testing.expectEqualSlices(u8, &expected, &stream.final());
        }
    }
}
fn unevenStream(data: []const u8) [32]u8 {
    var stream = Hasher.init();
    var at: usize = 0;
    while (at < data.len) {
        const end = @min(data.len, at + 8191);
        stream.update(data[at..end]);
        at = end;
    }
    return stream.final();
}
// spec-case: SELFHOST-FRONTEND-VERIFY-1
test "component SHA one-shot authenticates large bytes like streaming and standard SHA" {
    const data = try std.testing.allocator.alloc(u8, 1048577);
    defer std.testing.allocator.free(data);
    fillData(data);
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &hash(data));
    try std.testing.expectEqualSlices(u8, &expected, &unevenStream(data));
}
