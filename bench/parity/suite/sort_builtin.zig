// sort_builtin: two million xorshift values sorted in place by std.mem.sort
// (the standard stable sort); prints three order statistics and a checksum.
const std = @import("std");
const common = @import("common.zig");
const common_b = @import("common_b.zig");

fn xorshift(state: u64) u64 {
    var x = state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return x;
}

fn mix(c: i64, v: i64) i64 {
    return @mod(c * 31 + v, 1000000007);
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const n: usize = @intCast(common.opaqueN(2000000));
    const values = try gpa.alloc(i64, n);
    defer gpa.free(values);
    var state: u64 = 88172645463325252;
    for (values) |*v| {
        state = xorshift(state);
        v.* = @intCast(state >> 33);
    }
    std.mem.sort(i64, values, {}, std.sort.asc(i64));
    var c: i64 = 0;
    for (values) |v| c = mix(c, v);
    common_b.print("{d} {d} {d}\n{d}\n", .{ values[0], values[n / 2], values[n - 1], c });
}
