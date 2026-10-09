// str_build: append a short piece into a growable byte buffer 8,000,000 times.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const n = common.opaqueN(16000000);
    const piece = "mylang!\n";
    var buffer: std.ArrayList(u8) = .empty;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        buffer.appendSlice(gpa, piece) catch unreachable;
    }
    const length: i64 = @intCast(buffer.items.len);
    const samples = @divFloor(length, 1021);
    var total: i64 = 0;
    var j: i64 = 0;
    while (j < samples) : (j += 1) {
        total = @mod(total + @as(i64, buffer.items[@intCast(j * 1021)]), 1000003);
    }
    common.emit2(length, total);
}
