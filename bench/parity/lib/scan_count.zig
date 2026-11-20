// scan_count: std.mem.count over LIB.md's 4 MB text.
const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const text = try common.text(gpa);
    defer gpa.free(text);
    const rounds: usize = @intCast(common.opaqueN(12));
    var total: usize = 0;
    var a: usize = 0;
    var b: usize = 0;
    var c: usize = 0;
    var d: usize = 0;
    for (0..rounds) |_| {
        a = std.mem.count(u8, text, ",1");
        b = std.mem.count(u8, text, "\n");
        c = std.mem.count(u8, text, "item1");
        d = std.mem.count(u8, text, "x\nitem");
        total += a + b + c + d;
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d} {d} {d} {d} {d} {d}\n", .{ text.len, a, b, c, d, total });
    common.writeStdout(out.items);
}
