const std = @import("std");
fn fib(n: i64) i64 {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
pub fn main(init: std.process.Init) !void {
    var buf: [64]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}\n", .{fib(32)});
    try std.Io.File.stdout().writeStreamingAll(init.io, s);
}
