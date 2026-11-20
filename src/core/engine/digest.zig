//! Digests of the incremental engine (spec `docs/design/incremental-engine.md` §2): the 32-byte BLAKE3 digest, its
//! hexadecimal form, and the key of a query. Every digest in a record, a key or an object name comes from here, so
//! the Selka port has one place to match.
const std = @import("std");
const fast_blake3 = @import("../fast_blake3.zig");

/// A BLAKE3-256 digest: keys, code identities, result digests, object names.
pub const Digest = [32]u8;

/// The domain string that starts every key.
pub const key_domain = "selka-engine-key-v1";

/// The longest argument a key accepts. An argument is a digest, a name or a small setting, never the data itself.
pub const max_argument = 64 << 20;

/// The BLAKE3-256 digest of `bytes`.
pub fn hash(bytes: []const u8) Digest {
    var out: Digest = undefined;
    fast_blake3.hash(bytes, &out);
    return out;
}

/// The key of a query: BLAKE3-256 over the key domain, the kind's name, its code identity and the argument, each part
/// preceded by its length as a u32 little-endian. The caller has checked the argument against `max_argument`.
pub fn key(kind: []const u8, identity: Digest, argument: []const u8) Digest {
    std.debug.assert(argument.len <= max_argument);
    var state = fast_blake3.Blake3.init(.{});
    part(&state, key_domain);
    part(&state, kind);
    part(&state, &identity);
    part(&state, argument);
    var out: Digest = undefined;
    state.final(&out);
    return out;
}

fn part(state: *fast_blake3.Blake3, bytes: []const u8) void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(bytes.len), .little);
    state.update(&length);
    state.update(bytes);
}

/// The domain string that starts every variant key.
pub const variant_domain = "selka-engine-variant-v1";

/// The address of slot `slot` of the query under `key` in the shared tier. Slot 0 is the key itself, so a record published before the
/// tier had slots is slot 0; the others are named by BLAKE3-256 over the variant domain, the key and the slot. The tier keeps one record
/// per address, and the engine keeps up to a few variants of a key in the slots (`Engine.shared_variants`).
pub fn variantKey(base: Digest, slot: usize) Digest {
    if (slot == 0) return base;
    var state = fast_blake3.Blake3.init(.{});
    part(&state, variant_domain);
    part(&state, &base);
    part(&state, &.{@intCast(slot)});
    var out: Digest = undefined;
    state.final(&out);
    return out;
}

/// The lowercase hexadecimal form of `digest`.
pub fn hex(digest: Digest) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

/// The digest `text` spells (64 hexadecimal digits of either case), or null for anything else.
pub fn parseHex(text: []const u8) ?Digest {
    if (text.len != 64) return null;
    var out: Digest = undefined;
    _ = std.fmt.hexToBytes(&out, text) catch return null;
    return out;
}

/// The domain string that starts every listing digest.
pub const listing_domain = "selka-engine-listing-v1";

/// The digest of a directory listing: BLAKE3-256 over the listing domain and then each name in byte order, every
/// part preceded by its length as a u32 little-endian. `names` is not changed; the sorted copy lives in `arena`.
pub fn listingDigest(arena: std.mem.Allocator, names: []const []const u8) error{OutOfMemory}!Digest {
    const sorted = try arena.dupe([]const u8, names);
    defer arena.free(sorted);
    std.mem.sort([]const u8, sorted, {}, nameBefore);
    var state = fast_blake3.Blake3.init(.{});
    part(&state, listing_domain);
    for (sorted) |name| part(&state, name);
    var out: Digest = undefined;
    state.final(&out);
    return out;
}

fn nameBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The first four bytes of a key as a number: the stable sample point of verify mode and the fan-out of the store.
pub fn sample(digest: Digest) u32 {
    return std.mem.readInt(u32, digest[0..4], .little);
}

test "a key depends on every part, and the parts cannot run together" {
    const identity: Digest = @splat(7);
    const base = key("kind", identity, "argument");
    try std.testing.expectEqual(base, key("kind", identity, "argument"));
    try std.testing.expect(!std.mem.eql(u8, &base, &key("kinds", identity, "argument")));
    try std.testing.expect(!std.mem.eql(u8, &base, &key("kind", @splat(8), "argument")));
    try std.testing.expect(!std.mem.eql(u8, &base, &key("kind", identity, "arguments")));
    // "ab" + "c" and "a" + "bc" give different keys: the lengths are part of the input.
    try std.testing.expect(!std.mem.eql(u8, &key("ab", identity, "c"), &key("a", identity, "bc")));
}

test "hexadecimal digests round-trip and refuse anything that is not 64 digits" {
    const digest = hash("selka");
    const text = hex(digest);
    try std.testing.expectEqual(@as(?Digest, digest), parseHex(&text));
    try std.testing.expectEqual(@as(?Digest, null), parseHex(text[0..63]));
    try std.testing.expectEqual(@as(?Digest, null), parseHex("zz" ++ text[2..]));
}

test "a listing digest ignores the order the world listed the names in and sees every name" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try listingDigest(a, &.{ "b.txt", "a.txt", "notes" });
    try std.testing.expectEqual(first, try listingDigest(a, &.{ "notes", "a.txt", "b.txt" }));
    try std.testing.expect(!std.mem.eql(u8, &first, &(try listingDigest(a, &.{ "b.txt", "a.txt" }))));
    try std.testing.expect(!std.mem.eql(u8, &(try listingDigest(a, &.{ "ab", "c" })), &(try listingDigest(a, &.{ "a", "bc" }))));
    try std.testing.expect(!std.mem.eql(u8, &(try listingDigest(a, &.{})), &first));
}
