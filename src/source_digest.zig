//! The digest every cache of the front end takes of a module's bytes.
//!
//! BLAKE3-256 under a domain string. It replaced a SHA-256 whose portable compression ran at 250 MB/s on every core of the build
//! hosts (17 ms for the 99k port's 4 MB, 38 ms at 400k), while BLAKE3 takes 0.4 ms per MiB on a performance core and 0.8 on an
//! efficiency core. Every consumer treats the 32 bytes as opaque; a receipt that must be a SHA-256 (`Module.sha256`) computes one.
const std = @import("std");

/// The domain string the digest starts with; another domain over the same bytes is another digest.
pub const domain = "selka-source-v1";

/// The digest of `bytes`.
pub fn of(bytes: []const u8) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    state.update(&.{0});
    state.update(bytes);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

test "the digest is BLAKE3 under its domain and is not a SHA-256 of the bytes" {
    var expected: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(domain ++ "\x00hello", &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &of("hello"));
    var sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("hello", &sha, .{});
    try std.testing.expect(!std.mem.eql(u8, &sha, &of("hello")));
    try std.testing.expect(!std.mem.eql(u8, &of(""), &of("\n")));
}

test "the digest of a large buffer equals the digest of its one-shot input" {
    var buffer: [70_000]u8 = undefined;
    for (&buffer, 0..) |*byte, i| byte.* = @truncate(i *% 31);
    var one_shot: [32]u8 = undefined;
    var joined: [domain.len + 1 + buffer.len]u8 = undefined;
    @memcpy(joined[0..domain.len], domain);
    joined[domain.len] = 0;
    @memcpy(joined[domain.len + 1 ..], &buffer);
    std.crypto.hash.Blake3.hash(&joined, &one_shot, .{});
    try std.testing.expectEqualSlices(u8, &one_shot, &of(&buffer));
}
