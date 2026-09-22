//! Shared helpers for the runtime-library micro benchmarks: the same
//! `opaqueN` guard and single-write output as `../suite/common.zig` and
//! `../suite/common_c.zig` (a Zig root module cannot import outside its own
//! directory), plus the shared text every program scans.
const std = @import("std");

var scale_cell: i64 = 1;

/// Returns `base`, through a volatile load the optimizer cannot constant-fold.
pub fn opaqueN(base: i64) i64 {
    const cell: *volatile i64 = &scale_cell;
    return base * cell.*;
}

/// Writes every byte of `bytes` to standard output with the raw Linux write
/// syscall, retrying after a partial write and giving up on an error.
pub fn writeStdout(bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const rc = std.os.linux.write(1, rest.ptr, rest.len);
        if (std.os.linux.errno(rc) != .SUCCESS) return;
        rest = rest[rc..];
    }
}

/// LIB.md's shared text: 2000 formatted lines, the block copied 110 times.
pub fn text(gpa: std.mem.Allocator) ![]u8 {
    const lines: usize = @intCast(opaqueN(2000));
    const copies: usize = @intCast(opaqueN(110));
    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(gpa);
    for (0..lines) |i| {
        try block.print(gpa, "item{d},{d},", .{ i, (i * 7919) % 100003 });
        try block.appendNTimes(gpa, 'x', i % 7);
        try block.append(gpa, '\n');
    }
    var whole: std.ArrayList(u8) = .empty;
    try whole.ensureTotalCapacity(gpa, block.items.len * copies);
    for (0..copies) |_| whole.appendSliceAssumeCapacity(block.items);
    return whole.toOwnedSlice(gpa);
}
