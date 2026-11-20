// spectral_norm: ten power-iteration rounds on the infinite matrix
// A(i, j) = 1 / ((i + j)(i + j + 1)/2 + i + 1), n = 2000. `a` stays a separate
// function. See SUITE.md section 3.
const std = @import("std");
const common = @import("common.zig");

fn a(i: usize, j: usize) f64 {
    return 1.0 / @as(f64, @floatFromInt((i + j) * (i + j + 1) / 2 + i + 1));
}

fn mulAv(v: []const f64, out: []f64) void {
    for (out, 0..) |*slot, i| {
        var s: f64 = 0.0;
        for (v, 0..) |vj, j| {
            s = s + a(i, j) * vj;
        }
        slot.* = s;
    }
}

fn mulAtv(v: []const f64, out: []f64) void {
    for (out, 0..) |*slot, i| {
        var s: f64 = 0.0;
        for (v, 0..) |vj, j| {
            s = s + a(j, i) * vj;
        }
        slot.* = s;
    }
}

fn mulAtAv(v: []const f64, out: []f64, tmp: []f64) void {
    mulAv(v, tmp);
    mulAtv(tmp, out);
}

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const n: usize = @intCast(common.opaqueN(2000));
    const u = gpa.alloc(f64, n) catch @panic("out of memory");
    defer gpa.free(u);
    const v = gpa.alloc(f64, n) catch @panic("out of memory");
    defer gpa.free(v);
    const tmp = gpa.alloc(f64, n) catch @panic("out of memory");
    defer gpa.free(tmp);
    @memset(u, 1.0);
    @memset(v, 0.0);
    @memset(tmp, 0.0);

    for (0..10) |_| {
        mulAtAv(u, v, tmp);
        mulAtAv(v, u, tmp);
    }

    var vbv: f64 = 0.0;
    var vv: f64 = 0.0;
    for (0..n) |i| {
        vbv = vbv + u[i] * v[i];
        vv = vv + v[i] * v[i];
    }
    common.emit1(@intFromFloat(@sqrt(vbv / vv) * 1e9));
}
