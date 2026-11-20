// hash_bytes: a hand-written SHA-256 (FIPS 180-4) and a table-driven CRC32 over a
// 64 MiB buffer filled from the xorshift generator (SUITE.md section 14).
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

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

/// One xorshift step; returns the new state.
fn xorshift(input: u64) u64 {
    var x = input;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return x;
}

/// Compresses one 64-byte block into the eight-word state `h`.
fn compress(h: *[8]u32, block: *const [64]u8) void {
    var w: [64]u32 = undefined;
    for (0..16) |i| w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
    for (16..64) |i| {
        const s0 = std.math.rotr(u32, w[i - 15], 7) ^ std.math.rotr(u32, w[i - 15], 18) ^ (w[i - 15] >> 3);
        const s1 = std.math.rotr(u32, w[i - 2], 17) ^ std.math.rotr(u32, w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }
    var a = h[0];
    var b = h[1];
    var c = h[2];
    var d = h[3];
    var e = h[4];
    var f = h[5];
    var g = h[6];
    var hh = h[7];
    for (0..64) |i| {
        const big_s1 = std.math.rotr(u32, e, 6) ^ std.math.rotr(u32, e, 11) ^ std.math.rotr(u32, e, 25);
        const choice = (e & f) ^ (~e & g);
        const t1 = hh +% big_s1 +% choice +% round_constants[i] +% w[i];
        const big_s0 = std.math.rotr(u32, a, 2) ^ std.math.rotr(u32, a, 13) ^ std.math.rotr(u32, a, 22);
        const majority = (a & b) ^ (a & c) ^ (b & c);
        const t2 = big_s0 +% majority;
        hh = g;
        g = f;
        f = e;
        e = d +% t1;
        d = c;
        c = b;
        b = a;
        a = t1 +% t2;
    }
    h[0] +%= a;
    h[1] +%= b;
    h[2] +%= c;
    h[3] +%= d;
    h[4] +%= e;
    h[5] +%= f;
    h[6] +%= g;
    h[7] +%= hh;
}

/// The SHA-256 digest of `data`, with the FIPS 180-4 padding applied to the final block(s).
fn sha256(data: []const u8) [32]u8 {
    var h = [8]u32{ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    const full = data.len / 64;
    for (0..full) |block| compress(&h, data[block * 64 ..][0..64]);
    var tail: [128]u8 = @splat(0);
    const rest = data.len - full * 64;
    @memcpy(tail[0..rest], data[full * 64 ..]);
    tail[rest] = 0x80;
    const tail_len: usize = if (rest < 56) 64 else 128;
    std.mem.writeInt(u64, tail[tail_len - 8 ..][0..8], @as(u64, data.len) * 8, .big);
    compress(&h, tail[0..64]);
    if (tail_len == 128) compress(&h, tail[64..128]);
    var digest: [32]u8 = undefined;
    for (h, 0..) |word, i| std.mem.writeInt(u32, digest[i * 4 ..][0..4], word, .big);
    return digest;
}

/// The CRC32 (IEEE, reflected) of `data`, using the 256-entry table `table`.
fn crc32(table: *const [256]u32, data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFF;
}

/// The CRC32 lookup table: the eight reflected shift steps for each byte value.
fn crcTable() [256]u32 {
    var table: [256]u32 = undefined;
    for (0..256) |n| {
        var c: u32 = @intCast(n);
        for (0..8) |_| c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        table[n] = c;
    }
    return table;
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const size: usize = @intCast(common.opaqueN(67108864));
    const data = try gpa.alloc(u8, size);
    defer gpa.free(data);
    var state: u64 = 88172645463325252;
    for (data) |*byte| {
        state = xorshift(state);
        byte.* = @intCast((state >> 33) & 255);
    }
    const abc = sha256("abc");
    const digest = sha256(data);
    const table = crcTable();
    const crc = crc32(&table, data);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    const abc_hex = std.fmt.bytesToHex(abc, .lower);
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    try out.print(gpa, "sha256 abc {s}\n", .{&abc_hex});
    try out.print(gpa, "sha256 {s}\n", .{&digest_hex});
    try out.print(gpa, "crc32 {d}\n", .{crc});
    common_c.writeStdout(out.items);
}
