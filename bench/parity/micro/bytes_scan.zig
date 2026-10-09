// bytes_scan: index an 8 MiB byte slice and count one octet value, sixteen times.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const piece = "mylang micro benchmark kernel payload 0123456789 abcdefghijklmno";
    const chunks = common.opaqueN(131072);
    var buffer: std.ArrayList(u8) = .empty;
    var i: i64 = 0;
    while (i < chunks) : (i += 1) {
        buffer.appendSlice(gpa, piece) catch unreachable;
    }
    const data = buffer.items;
    var count: i64 = 0;
    var pass_index: i64 = 0;
    while (pass_index < 16) : (pass_index += 1) {
        count += pass_index;
        var k: usize = 0;
        while (k < data.len) : (k += 1) {
            if (data[k] == 109) count += 1;
        }
    }
    common.emit1(count);
}
