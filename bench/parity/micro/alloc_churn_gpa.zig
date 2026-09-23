// alloc_churn (general-allocator variant): the same batch body over
// std.heap.smp_allocator, freeing each batch's list instead of resetting.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const n = common.opaqueN(1000000);
    var total: i64 = 0;
    var batch: i64 = 0;
    while (batch < n) : (batch += 1) {
        var values: std.ArrayList(i64) = .empty;
        var j: i64 = 0;
        while (j < 16) : (j += 1) {
            values.append(gpa, batch + j) catch unreachable;
        }
        for (values.items) |v| {
            total = @mod(total + v, 1000003);
        }
        values.deinit(gpa);
    }
    common.emit1(total);
}
