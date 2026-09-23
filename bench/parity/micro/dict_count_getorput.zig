// dict_count (idiomatic variant): one getOrPut lookup instead of get + put.
const std = @import("std");
const common = @import("common.zig");

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    var keys: std.ArrayList([]const u8) = .empty;
    var k: i64 = 0;
    while (k < 1000) : (k += 1) {
        keys.append(gpa, std.fmt.allocPrint(gpa, "key{d}", .{k}) catch unreachable) catch unreachable;
    }
    var counts: std.StringHashMap(i64) = .init(gpa);
    const n = common.opaqueN(2000000);
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        const key = keys.items[@intCast(@mod(i * 7919, 1000))];
        const entry = counts.getOrPut(key) catch unreachable;
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    var total: i64 = 0;
    for (keys.items) |name| {
        const count = counts.get(name) orelse 0;
        total = @mod(total + count * @as(i64, @intCast(name.len)), 1000003);
    }
    common.emit1(total);
}
