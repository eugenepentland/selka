// scan_replace: std.mem.replaceOwned over LIB.md's 4 MB text.
const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const text = try common.text(gpa);
    defer gpa.free(text);
    const rounds: usize = @intCast(common.opaqueN(4));
    var total: usize = 0;
    var a: usize = 0;
    var b: usize = 0;
    var c: usize = 0;
    for (0..rounds) |_| {
        const shrunk = try std.mem.replaceOwned(u8, gpa, text, "item", "it");
        defer gpa.free(shrunk);
        const grown = try std.mem.replaceOwned(u8, gpa, text, ",", ";;");
        defer gpa.free(grown);
        const rare = try std.mem.replaceOwned(u8, gpa, text, "x\nitem1", "|");
        defer gpa.free(rare);
        a = shrunk.len;
        b = grown.len;
        c = rare.len;
        total += a + b + c;
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d} {d} {d} {d}\n", .{ a, b, c, total });
    common.writeStdout(out.items);
}
