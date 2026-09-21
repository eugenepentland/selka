// alloc_churn: build, fold and drop a 16-element list once per batch,
// over an ArenaAllocator reset between batches.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const n = common.opaqueN(1000000);
    var total: i64 = 0;
    var batch: i64 = 0;
    while (batch < n) : (batch += 1) {
        _ = arena_state.reset(.retain_capacity);
        const gpa = arena_state.allocator();
        var values: std.ArrayList(i64) = .empty;
        var j: i64 = 0;
        while (j < 16) : (j += 1) {
            values.append(gpa, batch + j) catch unreachable;
        }
        for (values.items) |v| {
            total = @mod(total + v, 1000003);
        }
    }
    common.emit1(total);
}
