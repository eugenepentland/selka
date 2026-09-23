// fannkuch_redux: the benchmarks-game C algorithm over three small slices.
// Flips prefixes of every permutation of 0..n-1 in the incremental order the C
// program generates; prints the alternating flip checksum and the maximum.
const std = @import("std");
const common = @import("common.zig");
const common_b = @import("common_b.zig");

const Result = struct { checksum: i64, max_flips: i64 };

fn fannkuch(gpa: std.mem.Allocator, n: usize) !Result {
    const perm = try gpa.alloc(usize, n);
    defer gpa.free(perm);
    const perm1 = try gpa.alloc(usize, n);
    defer gpa.free(perm1);
    const count = try gpa.alloc(usize, n);
    defer gpa.free(count);

    for (perm1, 0..) |*p, i| p.* = i;
    var max_flips: i64 = 0;
    var checksum: i64 = 0;
    var perm_count: u64 = 0;
    var r = n;
    while (true) {
        while (r != 1) : (r -= 1) {
            count[r - 1] = r;
        }
        @memcpy(perm, perm1);
        var flips: i64 = 0;
        var k = perm[0];
        while (k != 0) : (k = perm[0]) {
            const k2 = (k + 1) >> 1;
            for (0..k2) |i| {
                std.mem.swap(usize, &perm[i], &perm[k - i]);
            }
            flips += 1;
        }
        max_flips = @max(max_flips, flips);
        checksum += if (perm_count % 2 == 0) flips else -flips;
        while (true) {
            if (r == n) return .{ .checksum = checksum, .max_flips = max_flips };
            const perm0 = perm1[0];
            for (0..r) |i| {
                perm1[i] = perm1[i + 1];
            }
            perm1[r] = perm0;
            count[r] -= 1;
            if (count[r] > 0) break;
            r += 1;
        }
        perm_count += 1;
    }
}

pub fn main() !void {
    const n: usize = @intCast(common.opaqueN(10));
    const result = try fannkuch(std.heap.smp_allocator, n);
    common_b.print("{d}\nPfannkuchen({d}) = {d}\n", .{ result.checksum, n, result.max_flips });
}
