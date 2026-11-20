// sort_quick: two million xorshift values sorted in place by the SUITE.md
// recursive Hoare quicksort (recurse on the smaller side, loop on the larger);
// prints three order statistics and a checksum. Bounds are signed because
// `j` can step to lo - 1.
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

fn quicksort(xs: []i64, lo_start: isize, hi_start: isize) void {
    var lo = lo_start;
    var hi = hi_start;
    while (lo < hi) {
        const pivot = xs[@intCast(lo + @divTrunc(hi - lo, 2))];
        var i = lo;
        var j = hi;
        while (i <= j) {
            while (xs[@intCast(i)] < pivot) i += 1;
            while (xs[@intCast(j)] > pivot) j -= 1;
            if (i <= j) {
                std.mem.swap(i64, &xs[@intCast(i)], &xs[@intCast(j)]);
                i += 1;
                j -= 1;
            }
        }
        if (j - lo < hi - i) {
            quicksort(xs, lo, j);
            lo = i;
        } else {
            quicksort(xs, i, hi);
            hi = j;
        }
    }
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
    quicksort(values, 0, @as(isize, @intCast(n)) - 1);
    var c: i64 = 0;
    for (values) |v| c = mix(c, v);
    common_b.print("{d} {d} {d}\n{d}\n", .{ values[0], values[n / 2], values[n - 1], c });
}
