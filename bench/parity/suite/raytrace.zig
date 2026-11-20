// raytrace: small value structs passed and returned by value (SUITE.md section 10).
// The scene is built at run time into an ArrayList and passed as a slice, the
// shape the selka port's list[Sphere] has, so no sphere data is comptime-known.
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,
};

const Sphere = struct {
    center: Vec3,
    radius: f64,
    color: Vec3,
};

fn add(a: Vec3, b: Vec3) Vec3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn scale(v: Vec3, s: f64) Vec3 {
    return .{ .x = v.x * s, .y = v.y * s, .z = v.z * s };
}

fn dot(a: Vec3, b: Vec3) f64 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn normalize(v: Vec3) Vec3 {
    return scale(v, 1.0 / @sqrt(dot(v, v)));
}

fn intersect(origin: Vec3, dir: Vec3, s: Sphere) f64 {
    const oc = sub(origin, s.center);
    const b = dot(oc, dir);
    const c = dot(oc, oc) - s.radius * s.radius;
    const disc = b * b - c;
    if (disc < 0.0) return -1.0;
    const root = @sqrt(disc);
    var t = (0.0 - b) - root;
    if (t > 0.001) return t;
    t = (0.0 - b) + root;
    if (t > 0.001) return t;
    return -1.0;
}

fn shade(origin: Vec3, dir: Vec3, spheres: []const Sphere, light: Vec3) Vec3 {
    var best: f64 = -1.0;
    var hit_index: ?usize = null;
    for (spheres, 0..) |s, k| {
        const t = intersect(origin, dir, s);
        if (t > 0.0 and (hit_index == null or t < best)) {
            best = t;
            hit_index = k;
        }
    }
    const hit = spheres[hit_index orelse return .{ .x = 0.6, .y = 0.7, .z = 0.9 }];
    const point = add(origin, scale(dir, best));
    const normal = normalize(sub(point, hit.center));
    var diffuse = dot(normal, light);
    if (diffuse < 0.0) diffuse = 0.0;
    if (diffuse > 0.0) {
        for (spheres) |q| {
            if (intersect(point, light, q) > 0.0) {
                diffuse = 0.0;
                break;
            }
        }
    }
    return scale(hit.color, 0.1 + 0.9 * diffuse);
}

fn mix(c: i64, v: i64) i64 {
    return @mod(c * 31 + v, 1000000007);
}

fn channel(value: f64) i64 {
    return @intFromFloat(@min(value, 1.0) * 255.0);
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var spheres: std.ArrayList(Sphere) = .empty;
    defer spheres.deinit(gpa);
    try spheres.appendSlice(gpa, &.{
        .{ .center = .{ .x = 0.0, .y = -1000.0, .z = 0.0 }, .radius = 999.0, .color = .{ .x = 0.5, .y = 0.5, .z = 0.5 } },
        .{ .center = .{ .x = 0.0, .y = 0.0, .z = -3.0 }, .radius = 1.0, .color = .{ .x = 1.0, .y = 0.2, .z = 0.2 } },
        .{ .center = .{ .x = -2.0, .y = 0.0, .z = -4.0 }, .radius = 1.0, .color = .{ .x = 0.2, .y = 1.0, .z = 0.2 } },
        .{ .center = .{ .x = 2.0, .y = 0.0, .z = -4.0 }, .radius = 1.0, .color = .{ .x = 0.2, .y = 0.2, .z = 1.0 } },
        .{ .center = .{ .x = 0.0, .y = 2.0, .z = -6.0 }, .radius = 1.5, .color = .{ .x = 1.0, .y = 1.0, .z = 0.2 } },
        .{ .center = .{ .x = -1.5, .y = -0.5, .z = -2.0 }, .radius = 0.5, .color = .{ .x = 0.2, .y = 1.0, .z = 1.0 } },
    });
    const light = normalize(.{ .x = 1.0, .y = 1.0, .z = 1.0 });
    const width = common.opaqueN(1920);
    const height = common.opaqueN(1080);
    const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
    const origin: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var checksum: i64 = 0;
    var y: i64 = 0;
    while (y < height) : (y += 1) {
        var x: i64 = 0;
        while (x < width) : (x += 1) {
            const u = (2.0 * (@as(f64, @floatFromInt(x)) + 0.5) / @as(f64, @floatFromInt(width)) - 1.0) * aspect;
            const v = 1.0 - 2.0 * (@as(f64, @floatFromInt(y)) + 0.5) / @as(f64, @floatFromInt(height));
            const c = shade(origin, normalize(.{ .x = u, .y = v, .z = -1.5 }), spheres.items, light);
            checksum = mix(checksum, channel(c.x) * 65536 + channel(c.y) * 256 + channel(c.z));
        }
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d}\n", .{checksum});
    common_c.writeStdout(out.items);
}
