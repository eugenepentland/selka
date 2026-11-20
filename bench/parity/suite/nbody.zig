// nbody: five bodies advanced 5,000,000 steps; an array of structs updated in
// place through pointers. See SUITE.md section 2.
const std = @import("std");
const common = @import("common.zig");
const common_a = @import("common_a.zig");

// Typed f64 constants, so `4.0 * pi * pi` is evaluated in binary64 exactly as
// the other ports evaluate it (an untyped comptime_float would use f128).
const pi: f64 = 3.141592653589793;
const solar_mass: f64 = 4.0 * pi * pi;
const days_per_year: f64 = 365.24;

const Body = struct {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
};

fn offsetMomentum(bodies: []Body) void {
    var px: f64 = 0.0;
    var py: f64 = 0.0;
    var pz: f64 = 0.0;
    for (bodies) |b| {
        px = px + b.vx * b.mass;
        py = py + b.vy * b.mass;
        pz = pz + b.vz * b.mass;
    }
    bodies[0].vx = (0.0 - px) / solar_mass;
    bodies[0].vy = (0.0 - py) / solar_mass;
    bodies[0].vz = (0.0 - pz) / solar_mass;
}

fn energy(bodies: []const Body) f64 {
    var e: f64 = 0.0;
    for (bodies, 0..) |b, i| {
        e = e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
        for (bodies[i + 1 ..]) |c| {
            const dx = b.x - c.x;
            const dy = b.y - c.y;
            const dz = b.z - c.z;
            e = e - (b.mass * c.mass) / @sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

fn advance(bodies: []Body, dt: f64) void {
    for (bodies, 0..) |*bi, i| {
        for (bodies[i + 1 ..]) |*bj| {
            const dx = bi.x - bj.x;
            const dy = bi.y - bj.y;
            const dz = bi.z - bj.z;
            const d2 = dx * dx + dy * dy + dz * dz;
            const mag = dt / (d2 * @sqrt(d2));
            bi.vx = bi.vx - dx * bj.mass * mag;
            bi.vy = bi.vy - dy * bj.mass * mag;
            bi.vz = bi.vz - dz * bj.mass * mag;
            bj.vx = bj.vx + dx * bi.mass * mag;
            bj.vy = bj.vy + dy * bi.mass * mag;
            bj.vz = bj.vz + dz * bi.mass * mag;
        }
    }
    for (bodies) |*b| {
        b.x = b.x + dt * b.vx;
        b.y = b.y + dt * b.vy;
        b.z = b.z + dt * b.vz;
    }
}

pub fn main() void {
    const steps = common.opaqueN(5000000);
    const dt: f64 = 0.01;
    var bodies = [_]Body{
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .vx = 0.0, .vy = 0.0, .vz = 0.0, .mass = solar_mass },
        .{
            .x = 4.84143144246472090e+00,
            .y = -1.16032004402742839e+00,
            .z = -1.03622044471123109e-01,
            .vx = 1.66007664274403694e-03 * days_per_year,
            .vy = 7.69901118419740425e-03 * days_per_year,
            .vz = -6.90460016972063023e-05 * days_per_year,
            .mass = 9.54791938424326609e-04 * solar_mass,
        },
        .{
            .x = 8.34336671824457987e+00,
            .y = 4.12479856412430479e+00,
            .z = -4.03523417114321381e-01,
            .vx = -2.76742510726862411e-03 * days_per_year,
            .vy = 4.99852801234917238e-03 * days_per_year,
            .vz = 2.30417297573763929e-05 * days_per_year,
            .mass = 2.85885980666130812e-04 * solar_mass,
        },
        .{
            .x = 1.28943695621391310e+01,
            .y = -1.51111514016986312e+01,
            .z = -2.23307578892655734e-01,
            .vx = 2.96460137564761618e-03 * days_per_year,
            .vy = 2.37847173959480950e-03 * days_per_year,
            .vz = -2.96589568540237556e-05 * days_per_year,
            .mass = 4.36624404335156298e-05 * solar_mass,
        },
        .{
            .x = 1.53796971148509165e+01,
            .y = -2.59193146099879641e+01,
            .z = 1.79258772950371181e-01,
            .vx = 2.68067772490389322e-03 * days_per_year,
            .vy = 1.62824170038242295e-03 * days_per_year,
            .vz = -9.51592254519715870e-05 * days_per_year,
            .mass = 5.15138902046611451e-05 * solar_mass,
        },
    };

    var out: common_a.Lines = .{};
    offsetMomentum(&bodies);
    out.print("{d}\n", .{@as(i64, @intFromFloat(energy(&bodies) * 1e9))});
    var step: i64 = 0;
    while (step < steps) : (step += 1) {
        advance(&bodies, dt);
    }
    out.print("{d}\n", .{@as(i64, @intFromFloat(energy(&bodies) * 1e9))});
    out.flush();
}
