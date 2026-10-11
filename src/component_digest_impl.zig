//! Narrow LLVM ReleaseSafe object, preserving std SHA-256 hardware acceleration.
const std = @import("std");
const builtin = @import("builtin");
const State = @import("component_digest_abi.zig").State;
const Sha = std.crypto.hash.sha2.Sha256;
comptime {
    if (@sizeOf(Sha) > @sizeOf(State) or @alignOf(Sha) > @alignOf(State)) @compileError("component SHA storage is too small");
}
fn clearUpperLanes() void {
    if (comptime builtin.cpu.arch == .x86_64 and builtin.cpu.has(.x86, .avx)) {
        // Native callers do not necessarily emit the LLVM AVX/SSE call boundary.
        asm volatile ("vzeroupper" ::: .{
                .ymm0 = true,
                .ymm1 = true,
                .ymm2 = true,
                .ymm3 = true,
                .ymm4 = true,
                .ymm5 = true,
                .ymm6 = true,
                .ymm7 = true,
                .ymm8 = true,
                .ymm9 = true,
                .ymm10 = true,
                .ymm11 = true,
                .ymm12 = true,
                .ymm13 = true,
                .ymm14 = true,
                .ymm15 = true,
                .memory = true,
            });
    }
}
fn context(state: *State) *Sha {
    return @ptrCast(state);
}
export fn mylang_component_sha_init(state: *State) callconv(.c) void {
    clearUpperLanes();
    context(state).* = Sha.init(.{});
}
export fn mylang_component_sha_update(state: *State, bytes: [*]const u8, length: usize) callconv(.c) void {
    clearUpperLanes();
    context(state).update(bytes[0..length]);
}
export fn mylang_component_sha_final(state: *State, digest: *[32]u8) callconv(.c) void {
    clearUpperLanes();
    context(state).final(digest);
}

export fn mylang_component_sha_hash(bytes: [*]const u8, length: usize, digest: *[32]u8) callconv(.c) void {
    clearUpperLanes();
    Sha.hash(bytes[0..length], digest, .{});
}
