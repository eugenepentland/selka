// text_ops: building, splitting, parsing and rewriting text with
// std.ArrayList(u8), std.fmt, std.mem.splitScalar, std.fmt.parseInt,
// std.mem.replaceOwned and std.mem.count (SUITE.md section 11). The lines are
// printed straight into one buffer with "\n" between them, which is how Zig
// joins text it is producing.
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const lines: usize = @intCast(common.opaqueN(200000));
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    for (0..lines) |i| {
        if (i > 0) try text.append(gpa, '\n');
        try text.print(gpa, "item{d},{d},", .{ i, (i * 7919) % 100003 });
        try text.appendNTimes(gpa, 'x', i % 7);
    }
    var total: i64 = 0;
    var widths: usize = 0;
    var sevens: usize = 0;
    var line_it = std.mem.splitScalar(u8, text.items, '\n');
    while (line_it.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, ',');
        const name = fields.next().?;
        const number = fields.next().?;
        const pad = fields.next().?;
        total += try std.fmt.parseInt(i64, number, 10);
        widths += pad.len;
        if (std.mem.endsWith(u8, name, "7")) sevens += 1;
    }
    const rewritten = try std.mem.replaceOwned(u8, gpa, text.items, "item", "it");
    defer gpa.free(rewritten);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d} {d} {d}\n", .{ total, widths, sevens });
    try out.print(gpa, "{d} {d} {d}\n", .{ text.items.len, rewritten.len, std.mem.count(u8, text.items, ",1") });
    common_c.writeStdout(out.items);
}
