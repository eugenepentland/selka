// calls (inlinable variant): identical body with the noinline barrier removed.
const common = @import("common.zig");

fn step(a: i64, b: i64) i64 {
    return @mod(a + b, 1000003);
}

pub fn main() void {
    const n = common.opaqueN(30000000);
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        total = step(total, i);
    }
    common.emit1(total);
}
