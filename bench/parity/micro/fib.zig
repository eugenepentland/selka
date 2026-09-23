// fib: naive double recursion; measures call/frame protocol at depth.
const common = @import("common.zig");

fn fib(n: i64) i64 {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

pub fn main() void {
    common.emit1(fib(common.opaqueN(36)));
}
