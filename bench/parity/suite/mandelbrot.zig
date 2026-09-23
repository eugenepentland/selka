// mandelbrot: a 1600 x 1600 escape-time bitmap (50 iterations, limit 4.0),
// packed eight pixels per byte and folded into a checksum instead of being
// written out. See SUITE.md section 5.
const std = @import("std");
const common = @import("common.zig");
const common_a = @import("common_a.zig");

fn mix(c: i64, v: i64) i64 {
    return @mod(c * 31 + v, 1000000007);
}

pub fn main() void {
    const size: usize = @intCast(common.opaqueN(1600));
    const iterations: i64 = 50;
    const limit: f64 = 4.0;
    var checksum: i64 = 0;
    for (0..size) |y| {
        const ci = 2.0 * @as(f64, @floatFromInt(y)) / @as(f64, @floatFromInt(size)) - 1.0;
        var byte: i64 = 0;
        var bits: i64 = 0;
        for (0..size) |x| {
            const cr = 2.0 * @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(size)) - 1.5;
            var zr: f64 = 0.0;
            var zi: f64 = 0.0;
            var tr: f64 = 0.0;
            var ti: f64 = 0.0;
            var i: i64 = 0;
            while (i < iterations and tr + ti <= limit) {
                zi = 2.0 * zr * zi + ci;
                zr = tr - ti + cr;
                tr = zr * zr;
                ti = zi * zi;
                i = i + 1;
            }
            byte = byte * 2 + @intFromBool(tr + ti <= limit);
            bits = bits + 1;
            if (bits == 8) {
                checksum = mix(checksum, byte);
                byte = 0;
                bits = 0;
            }
        }
        if (bits > 0) {
            byte = byte << @intCast(8 - bits);
            checksum = mix(checksum, byte);
        }
    }
    var out: common_a.Lines = .{};
    out.print("P4 {d} {d}\n{d}\n", .{ size, size, checksum });
    out.flush();
}
