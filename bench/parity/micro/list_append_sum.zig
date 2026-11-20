// list_append_sum: grow an ArrayList(i64) by append, then fold it.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const n = common.opaqueN(16000000);
    var values: std.ArrayList(i64) = .empty;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        values.append(gpa, i) catch unreachable;
    }
    var total: i64 = 0;
    for (values.items) |v| {
        total += v;
    }
    common.emit1(total);
}
