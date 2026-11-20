//! BLAKE3 compiled in its own ReleaseFast object (`src/core/fast_blake3.zig` is its caller).
//!
//! The development compiler is a Debug build, and the standard library's BLAKE3 inherits that
//! mode: its vector rounds run unoptimized, about 30 MB/s. Verifying a runtime object, a linked
//! program or a stage-pack index with it was a fifth of a `selka` invocation's samples. The same
//! code in this object runs at memory speed and gives the same digests.
const std = @import("std");
const builtin = @import("builtin");
const Blake3 = std.crypto.hash.Blake3;

/// Bytes of the opaque state the callers reserve (`fast_blake3.State`).
const state_bytes = 2560;
const State = extern struct { bytes: [state_bytes]u8 align(16) };

comptime {
    if (@sizeOf(Blake3) > state_bytes or @alignOf(Blake3) > 16)
        @compileError("the fast BLAKE3 state cannot hold the pinned standard state");
    if (builtin.mode != .fast)
        @compileError("the fast BLAKE3 implementation requires its optimized object boundary");
    @export(&init, .{ .name = "selka_fast_blake3_init" });
    @export(&update, .{ .name = "selka_fast_blake3_update" });
    @export(&final, .{ .name = "selka_fast_blake3_final" });
    @export(&hash, .{ .name = "selka_fast_blake3_hash" });
    @export(&mode, .{ .name = "selka_fast_blake3_mode" });
}

fn actual(state: *State) *Blake3 {
    return @ptrCast(state);
}
fn init(state: *State) callconv(.c) void {
    actual(state).* = Blake3.init(.{});
}
fn update(state: *State, bytes: [*]const u8, length: usize) callconv(.c) void {
    actual(state).update(bytes[0..length]);
}
fn final(state: *State, result: *[32]u8) callconv(.c) void {
    actual(state).final(result);
}
fn hash(bytes: [*]const u8, length: usize, result: *[32]u8) callconv(.c) void {
    Blake3.hash(bytes[0..length], result, .{});
}
fn mode() callconv(.c) u32 {
    return @backingInt(builtin.mode);
}
