// records: construct a 3-field value struct per iteration and pass it by value.
const common = @import("common.zig");

const Vec = struct {
    x: i64,
    y: i64,
    z: i64,
};

fn norm1(v: Vec) i64 {
    return v.x + v.y + v.z;
}

pub fn main() void {
    const n = common.opaqueN(20000000);
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        const v = Vec{ .x = i, .y = i + 1, .z = i + 2 };
        total = @mod(total + norm1(v), 1000003);
    }
    common.emit1(total);
}
