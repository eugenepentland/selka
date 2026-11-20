// float_loop: a binary64 multiply-add-sqrt dependency chain.
const common = @import("common.zig");

pub fn main() void {
    const n = common.opaqueN(20000000);
    var x: f64 = 0.0;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        x = x * 0.999 + @sqrt(@as(f64, @floatFromInt(i)));
    }
    common.emit1(@intFromFloat(x * 1000.0));
}
