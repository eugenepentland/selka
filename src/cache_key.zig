//! Wave 3 cache-key contract: the six build dimensions that must distinguish
//! every incremental cache entry. A fingerprint is a domain-separated SHA-256
//! over a length-prefixed canonical encoding, so no two field values can alias
//! by concatenation and no field may be silently omitted.
const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

/// Domain string mixed into every contract fingerprint; bump with the encoding.
pub const domain = "selka-cache-contract-v1";

/// One compiler/tooling contract shared by frontend, semantic and object caches.
/// `null`/empty is a real, distinct value: the default `flags` and
/// `compiler_identity` are empty strings and still participate in the key.
pub const Contract = struct {
    bootstrap_language: []const u8,
    target: []const u8,
    runtime_abi: []const u8,
    effects: []const u8,
    flags: []const u8,
    compiler_identity: []const u8,

    /// Conservative default used until a host supplies its own identity.
    /// `runtime_abi` is frozen at `runtime-abi-v3`; additions to the native ABI bump it.
    pub const default: Contract = .{
        .bootstrap_language = "bootstrap-v1",
        .target = "native",
        .runtime_abi = "runtime-abi-v3",
        .effects = "effects-v4",
        .flags = "",
        .compiler_identity = "",
    };

    /// Write the lowercase hex SHA-256 of the canonical encoding into `out`.
    /// Allocation-free so key construction on hot paths stays infallible.
    pub fn fingerprintHex(self: Contract, out: *[64]u8) void {
        var hash = Sha256.init(.{});
        hash.update(domain);
        frame(&hash, self.bootstrap_language);
        frame(&hash, self.target);
        frame(&hash, self.runtime_abi);
        frame(&hash, self.effects);
        frame(&hash, self.flags);
        frame(&hash, self.compiler_identity);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        const hex = std.fmt.bytesToHex(digest, .lower);
        @memcpy(out, &hex);
    }

    /// Allocate the lowercase hex SHA-256 of the canonical encoding.
    pub fn fingerprint(self: Contract, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        var hex: [64]u8 = undefined;
        self.fingerprintHex(&hex);
        return allocator.dupe(u8, &hex) catch error.OutOfMemory;
    }

    /// Compare every dimension. Empty strings are values, not wildcards.
    pub fn eql(a: Contract, b: Contract) bool {
        return std.mem.eql(u8, a.bootstrap_language, b.bootstrap_language) and
            std.mem.eql(u8, a.target, b.target) and
            std.mem.eql(u8, a.runtime_abi, b.runtime_abi) and
            std.mem.eql(u8, a.effects, b.effects) and
            std.mem.eql(u8, a.flags, b.flags) and
            std.mem.eql(u8, a.compiler_identity, b.compiler_identity);
    }
};

/// Length-prefix one field so adjacent values cannot collide across the
/// concatenation boundary. Little-endian keeps the encoding architecture-stable.
fn frame(hash: *Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

const testing = std.testing;

// spec: INCREMENTAL-KEYS-1
test "cache key fingerprints are stable and every contract dimension changes them" {
    const base = Contract.default;
    const first = try base.fingerprint(testing.allocator);
    defer testing.allocator.free(first);
    const second = try base.fingerprint(testing.allocator);
    defer testing.allocator.free(second);
    try testing.expectEqualStrings(first, second);
    try testing.expectEqual(@as(usize, 64), first.len);

    const variants = [_]Contract{
        .{ .bootstrap_language = "bootstrap-v2", .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = "wasm32", .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = "runtime-abi-v4", .effects = base.effects, .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = "effects-v2", .flags = base.flags, .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = "--release", .compiler_identity = base.compiler_identity },
        .{ .bootstrap_language = base.bootstrap_language, .target = base.target, .runtime_abi = base.runtime_abi, .effects = base.effects, .flags = base.flags, .compiler_identity = "sha256:abc" },
    };
    for (variants) |variant| {
        const changed = try variant.fingerprint(testing.allocator);
        defer testing.allocator.free(changed);
        try testing.expect(!std.mem.eql(u8, first, changed));
    }
}

// spec-case: INCREMENTAL-KEYS-1
test "cache key equality compares all six fields and treats empty as a value" {
    const base = Contract.default;
    try testing.expect(Contract.eql(base, base));
    const empty: Contract = .{
        .bootstrap_language = "",
        .target = "",
        .runtime_abi = "",
        .effects = "",
        .flags = "",
        .compiler_identity = "",
    };
    try testing.expect(!Contract.eql(base, empty));
    try testing.expect(Contract.eql(empty, empty));
    var copy = base;
    copy.flags = "";
    try testing.expect(Contract.eql(base, copy));
    copy.flags = "true";
    try testing.expect(!Contract.eql(base, copy));
}

test "effects-v4 rejects old effects-v3 cache contract identities" {
    const base = Contract.default;
    try testing.expectEqualStrings("effects-v4", base.effects);
    var old = base;
    old.effects = "effects-v3";
    try testing.expect(!Contract.eql(base, old));
    const base_fingerprint = try base.fingerprint(testing.allocator);
    defer testing.allocator.free(base_fingerprint);
    const old_fingerprint = try old.fingerprint(testing.allocator);
    defer testing.allocator.free(old_fingerprint);
    try testing.expect(!std.mem.eql(u8, base_fingerprint, old_fingerprint));
}
