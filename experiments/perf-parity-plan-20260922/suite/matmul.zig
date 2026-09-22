// matmul: n x n f64 matrices in flat row-major slices, indexed i * n + j,
// C = A * B by the i-k-j loop; prints the trace and the sum of C, each scaled
// by 1000.
const std = @import("std");
const common = @import("common.zig");
const common_b = @import("common_b.zig");

const Lcg = struct {
    seed: i64 = 42,

    fn next(self: *Lcg) f64 {
        self.seed = @mod(self.seed * 3877 + 29573, 139968);
        return @as(f64, @floatFromInt(self.seed)) / 139968.0;
    }
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const n: usize = @intCast(common.opaqueN(500));
    var rng: Lcg = .{};
    const a = try gpa.alloc(f64, n * n);
    defer gpa.free(a);
    for (a) |*v| v.* = rng.next();
    const b = try gpa.alloc(f64, n * n);
    defer gpa.free(b);
    for (b) |*v| v.* = rng.next();
    const c = try gpa.alloc(f64, n * n);
    defer gpa.free(c);
    @memset(c, 0.0);
    for (0..n) |i| {
        for (0..n) |k| {
            const aik = a[i * n + k];
            for (0..n) |j| {
                c[i * n + j] = c[i * n + j] + aik * b[k * n + j];
            }
        }
    }
    var trace: f64 = 0.0;
    for (0..n) |i| trace = trace + c[i * n + i];
    var total: f64 = 0.0;
    for (0..n) |i| {
        for (0..n) |j| total = total + c[i * n + j];
    }
    const trace_scaled: i64 = @intFromFloat(trace * 1000.0);
    const total_scaled: i64 = @intFromFloat(total * 1000.0);
    common_b.print("{d}\n{d}\n", .{ trace_scaled, total_scaled });
}
