//! Standard SHA-256 compiled in its own ReleaseFast object, including all rounds.
const std = @import("std");
const builtin = @import("builtin");
const api = @import("bytes_hash.zig");
const Sha256 = std.crypto.hash.sha2.Sha256;

comptime {
    if (@sizeOf(Sha256) > @sizeOf(api.State) or @alignOf(Sha256) > @alignOf(api.State))
        @compileError("Juice digest ABI cannot hold the pinned standard SHA-256 state");
    if (builtin.mode != .fast)
        @compileError("Juice digest implementation requires its optimized object boundary");
    @export(&init, .{ .name = "mylang_juice_sha256_init" });
    @export(&update, .{ .name = "mylang_juice_sha256_update" });
    @export(&final, .{ .name = "mylang_juice_sha256_final" });
    @export(&hash, .{ .name = "mylang_juice_sha256_hash" });
    @export(&mode, .{ .name = "mylang_juice_sha256_mode" });
}

fn actual(state: *api.State) *Sha256 {
    return @ptrCast(state);
}
fn init(state: *api.State) callconv(.c) void {
    actual(state).* = Sha256.init(.{});
}
fn update(state: *api.State, bytes: [*]const u8, length: usize) callconv(.c) void {
    actual(state).update(bytes[0..length]);
}
fn final(state: *api.State, result: *api.Digest) callconv(.c) void {
    actual(state).final(result);
}
fn hash(bytes: [*]const u8, length: usize, result: *api.Digest) callconv(.c) void {
    Sha256.hash(bytes[0..length], result, .{});
}
fn mode() callconv(.c) u32 {
    return @backingInt(builtin.mode);
}
