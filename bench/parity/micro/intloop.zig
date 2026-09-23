// intloop: checked integer arithmetic over a loop-carried dependency.
// total = (total + i * 7) % 1000003 for i in 0..N
const common = @import("common.zig");

pub fn main() void {
    const n = common.opaqueN(30000000);
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        total = @mod(total + i * 7, 1000003);
    }
    common.emit1(total);
}
