//! SHA-256 with a portable compression function. Its digests equal
//! `std.crypto.hash.sha2.Sha256`; only the compression differs. The standard
//! library's path that uses the x86 SHA extensions ran about 10x slower than
//! this one for a 10.8 MB source tree in ReleaseFast on the measured host, which
//! put 0.8 s into every project check.
const std = @import("std");

const round_constants = [64]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

/// Fold one 64-byte block into the eight-word chaining state.
fn compress(state: *[8]u32, block: *const [64]u8) void {
    var w: [64]u32 = undefined;
    for (0..16) |i| w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
    for (16..64) |i| {
        const s0 = std.math.rotr(u32, w[i - 15], 7) ^ std.math.rotr(u32, w[i - 15], 18) ^ (w[i - 15] >> 3);
        const s1 = std.math.rotr(u32, w[i - 2], 17) ^ std.math.rotr(u32, w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }
    var a = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];
    var f = state[5];
    var g = state[6];
    var h = state[7];
    for (0..64) |i| {
        const s1 = std.math.rotr(u32, e, 6) ^ std.math.rotr(u32, e, 11) ^ std.math.rotr(u32, e, 25);
        const choice = (e & f) ^ (~e & g);
        const t1 = h +% s1 +% choice +% round_constants[i] +% w[i];
        const s0 = std.math.rotr(u32, a, 2) ^ std.math.rotr(u32, a, 13) ^ std.math.rotr(u32, a, 22);
        const majority = (a & b) ^ (a & c) ^ (b & c);
        const t2 = s0 +% majority;
        h = g;
        g = f;
        f = e;
        e = d +% t1;
        d = c;
        c = b;
        b = a;
        a = t1 +% t2;
    }
    state[0] +%= a;
    state[1] +%= b;
    state[2] +%= c;
    state[3] +%= d;
    state[4] +%= e;
    state[5] +%= f;
    state[6] +%= g;
    state[7] +%= h;
}

/// The SHA-256 digest of `bytes`, byte-for-byte what `std.crypto.hash.sha2.Sha256` returns.
pub fn hash(bytes: []const u8, out: *[32]u8) void {
    var state = [8]u32{ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    var offset: usize = 0;
    while (offset + 64 <= bytes.len) : (offset += 64) compress(&state, bytes[offset..][0..64]);
    // Padding: one 0x80 byte, zeros, then the message length in bits; one or two blocks.
    var tail: [128]u8 = @splat(0);
    const rest = bytes.len - offset;
    @memcpy(tail[0..rest], bytes[offset..]);
    tail[rest] = 0x80;
    const tail_len: usize = if (rest + 9 <= 64) 64 else 128;
    std.mem.writeInt(u64, tail[tail_len - 8 ..][0..8], @as(u64, bytes.len) *% 8, .big);
    compress(&state, tail[0..64]);
    if (tail_len == 128) compress(&state, tail[64..128]);
    for (state, 0..) |word, i| std.mem.writeInt(u32, out[i * 4 ..][0..4], word, .big);
}

fn hexOf(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

test "portable sha256 matches published vectors for the empty and short messages" {
    var digest: [32]u8 = undefined;
    hash("", &digest);
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &hexOf(digest));
    hash("abc", &digest);
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &hexOf(digest));
}

/// A deterministic sample of `data.len` bytes whose values vary with position.
fn fillSample(data: []u8) void {
    for (data, 0..) |*byte, i| byte.* = @truncate(i *% 131 +% 7);
}

test "portable sha256 equals the standard library at every padding boundary" {
    var data: [300]u8 = undefined;
    fillSample(&data);
    const lengths = [_]usize{ 0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 255, 256, 300 };
    for (lengths) |length| {
        var ours: [32]u8 = undefined;
        var theirs: [32]u8 = undefined;
        hash(data[0..length], &ours);
        std.crypto.hash.sha2.Sha256.hash(data[0..length], &theirs, .{});
        try std.testing.expectEqualSlices(u8, &theirs, &ours);
    }
}
