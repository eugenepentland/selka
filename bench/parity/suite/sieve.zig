// sieve: Eratosthenes over a []bool of n + 1 flags; prints the prime count.
const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const n: usize = @intCast(common.opaqueN(20000000));
    const flags = try gpa.alloc(bool, n + 1);
    defer gpa.free(flags);
    @memset(flags, true);
    flags[0] = false;
    flags[1] = false;
    var i: usize = 2;
    while (i * i <= n) : (i += 1) {
        if (flags[i]) {
            var j = i * i;
            while (j <= n) : (j += i) {
                flags[j] = false;
            }
        }
    }
    var count: i64 = 0;
    for (flags) |flag| {
        if (flag) count += 1;
    }
    common.emit1(count);
}
