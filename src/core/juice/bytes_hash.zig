//! Exact byte hashing through a separately optimized native object.
const std = @import("std");

/// Standard SHA-256 result bytes, independent of metadata and compiler identity.
pub const Digest = [32]u8;
/// Fixed opaque C ABI storage checked against the pinned standard-library state.
pub const State = extern struct { bytes: [128]u8 align(16) };
extern fn mylang_juice_sha256_init(state: *State) void;
extern fn mylang_juice_sha256_update(state: *State, bytes: [*]const u8, length: usize) void;
extern fn mylang_juice_sha256_final(state: *State, result: *Digest) void;
extern fn mylang_juice_sha256_hash(bytes: [*]const u8, length: usize, result: *Digest) void;
extern fn mylang_juice_sha256_mode() u32;

/// Report the linked digest object's compilation mode, independent of its caller.
pub fn compiledOptimize() std.lang.Optimize {
    return @fromBackingInt(@intCast(mylang_juice_sha256_mode()));
}
/// Bounded streaming SHA-256 state; callers retain their existing file-read guards.
pub const Hasher = struct {
    state: State,

    /// Start a fresh digest; no persistent or invocation-local result is memoized.
    pub fn init() Hasher {
        var result: Hasher = undefined;
        mylang_juice_sha256_init(&result.state);
        return result;
    }
    /// Consume every supplied byte using the independently optimized digest object.
    pub fn update(self: *Hasher, bytes: []const u8) void {
        mylang_juice_sha256_update(&self.state, bytes.ptr, bytes.len);
    }
    /// Finalize the consumed bytes using standard SHA-256 padding rules.
    pub fn final(self: *Hasher) Digest {
        var result: Digest = undefined;
        mylang_juice_sha256_final(&self.state, &result);
        return result;
    }
};
/// Hash an in-memory input using the same algorithm as streamed files.
pub fn hash(bytes: []const u8) Digest {
    var result: Digest = undefined;
    mylang_juice_sha256_hash(bytes.ptr, bytes.len, &result);
    return result;
}
