//! Shared helpers for the matched Zig micro-kernels.
//!
//! `emit1`/`emit2` write the single checksum line straight to fd 1 with the
//! raw Linux write syscall, so no std.Io plumbing appears inside a timed
//! region. `opaqueN` multiplies a compile-time base by a volatile cell that
//! always holds 1: the value is identical, but the optimizer cannot see it,
//! so a whole kernel loop can never be constant-folded away. The mylang side
//! needs no such guard because its backends do not fold these loops.
const std = @import("std");

var scale_cell: i64 = 1;

/// Returns `base`, through a volatile load the optimizer cannot constant-fold.
pub fn opaqueN(base: i64) i64 {
    const cell: *volatile i64 = &scale_cell;
    return base * cell.*;
}

/// Writes one decimal value and a newline to standard output.
pub fn emit1(value: i64) void {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}\n", .{value}) catch unreachable;
    _ = std.os.linux.write(1, text.ptr, text.len);
}

/// Writes two space-separated decimal values and a newline to standard output.
pub fn emit2(first: i64, second: i64) void {
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d} {d}\n", .{ first, second }) catch unreachable;
    _ = std.os.linux.write(1, text.ptr, text.len);
}
