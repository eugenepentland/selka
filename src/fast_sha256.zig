//! SHA-256 with the standard library type's interface, run by the compiler's ReleaseFast digest
//! object (`core/juice/bytes_hash_impl.zig`, exported as `selka_juice_sha256_*`).
//!
//! The development compiler is a Debug build and the standard library's SHA-256 rounds inherit
//! that mode: about 15 MB/s, so verifying the 700 KB of component artifacts for every `selka
//! test` or `build` takes 50 ms and approving a Zig toolchain from a cold cache takes 40 s. The
//! same rounds in the separately optimized object run at memory speed and give the same digests.
//! Every executable that compiles this file links the object (`build.zig`).
const std = @import("std");
const Standard = std.crypto.hash.sha2.Sha256;

/// The object's opaque, 16-aligned state, large enough for the pinned standard state.
const State = extern struct { bytes: [128]u8 align(16) };
const Digest = [Standard.digest_length]u8;

extern fn selka_juice_sha256_init(state: *State) void;
extern fn selka_juice_sha256_update(state: *State, bytes: [*]const u8, length: usize) void;
extern fn selka_juice_sha256_final(state: *State, result: *Digest) void;
extern fn selka_juice_sha256_mode() u32;

/// The mode the linked digest object was compiled in; `.ReleaseFast` is what makes it fast.
pub fn objectMode() std.lang.Optimize {
    return @fromBackingInt(@intCast(selka_juice_sha256_mode()));
}

/// A SHA-256 hasher with `std.crypto.hash.sha2.Sha256`'s `init`, `update`, `final` and `hash`.
pub const Sha256 = struct {
    /// Bytes in a digest.
    pub const digest_length = Standard.digest_length;
    /// The standard type's options, of which there are none.
    pub const Options = Standard.Options;

    state: State,

    /// Start a fresh digest.
    pub fn init(options: Options) Sha256 {
        _ = options;
        var result: Sha256 = undefined;
        selka_juice_sha256_init(&result.state);
        return result;
    }

    /// Consume `bytes`.
    pub fn update(self: *Sha256, bytes: []const u8) void {
        selka_juice_sha256_update(&self.state, bytes.ptr, bytes.len);
    }

    /// Finish the digest into `out`.
    pub fn final(self: *Sha256, out: *Digest) void {
        selka_juice_sha256_final(&self.state, out);
    }

    /// The digest of `bytes` in one call.
    pub fn hash(bytes: []const u8, out: *Digest, options: Options) void {
        var hasher = init(options);
        hasher.update(bytes);
        hasher.final(out);
    }
};
