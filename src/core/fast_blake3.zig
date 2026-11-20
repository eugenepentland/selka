//! BLAKE3 with the standard library type's `init`, `update`, `final` and `hash`, run by the
//! separately optimized object `fast_blake3_impl.zig`. See that file for why: the Debug
//! compiler's own BLAKE3 is about 30 MB/s. Every executable that compiles this file links the
//! object (`build.zig`). Only the unkeyed 32-byte form is offered.
const std = @import("std");
const Standard = std.crypto.hash.Blake3;

/// The object's opaque, 16-aligned state, large enough for the pinned standard state.
const State = extern struct { bytes: [2560]u8 align(16) };

extern fn selka_fast_blake3_init(state: *State) void;
extern fn selka_fast_blake3_update(state: *State, bytes: [*]const u8, length: usize) void;
extern fn selka_fast_blake3_final(state: *State, result: *[32]u8) void;
extern fn selka_fast_blake3_hash(bytes: [*]const u8, length: usize, result: *[32]u8) void;
extern fn selka_fast_blake3_mode() u32;

/// The mode the linked object was compiled in; `.ReleaseFast` is what makes it fast.
pub fn objectMode() std.lang.Optimize {
    return @fromBackingInt(@intCast(selka_fast_blake3_mode()));
}

/// The BLAKE3 digest of `bytes` in one call, into a pointer to an array or a slice of at most
/// 32 bytes. A shorter output is the prefix of the 32-byte digest, as the standard type's is.
pub fn hash(bytes: []const u8, out: anytype) void {
    const Pointer = @typeInfo(@TypeOf(out)).pointer;
    if (comptime Pointer.size != .slice and Pointer.child == [32]u8) {
        selka_fast_blake3_hash(bytes.ptr, bytes.len, out);
        return;
    }
    const length = if (comptime Pointer.size == .slice) out.len else @typeInfo(Pointer.child).array.len;
    std.debug.assert(length <= Standard.digest_length);
    var full: [32]u8 = undefined;
    selka_fast_blake3_hash(bytes.ptr, bytes.len, &full);
    @memcpy(out[0..length], full[0..length]);
}

/// An unkeyed BLAKE3 hasher with `std.crypto.hash.Blake3`'s `init`, `update` and `final`.
pub const Blake3 = struct {
    /// Bytes in a digest.
    pub const digest_length = Standard.digest_length;
    /// The standard type's options; only the default (unkeyed) form is supported.
    pub const Options = Standard.Options;

    state: State,

    /// Start a fresh digest.
    pub fn init(options: Options) Blake3 {
        std.debug.assert(options.key == null);
        var result: Blake3 = undefined;
        selka_fast_blake3_init(&result.state);
        return result;
    }

    /// Consume `bytes`.
    pub fn update(self: *Blake3, bytes: []const u8) void {
        selka_fast_blake3_update(&self.state, bytes.ptr, bytes.len);
    }

    /// Finish the 32-byte digest into `out`.
    pub fn final(self: *Blake3, out: []u8) void {
        std.debug.assert(out.len == digest_length);
        selka_fast_blake3_final(&self.state, out[0..digest_length]);
    }
};
