const std = @import("std");
pub fn main(init: std.process.Init) !void {
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < 30000000) : (i += 1) {
        total = @mod(total + i * 7, 1000003);
    }
    var buf: [64]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}\n", .{total});
    try std.Io.File.stdout().writeStreamingAll(init.io, s);
}
