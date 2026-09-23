// slice_walk: consume LIB.md's block repeated 8 times by slicing off its first
// line until nothing is left; a Zig slice is a view, so the walk is linear.
const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const lines_per_block: usize = @intCast(common.opaqueN(2000));
    const copies: usize = @intCast(common.opaqueN(8));
    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(gpa);
    for (0..lines_per_block) |i| {
        try block.print(gpa, "item{d},{d},", .{ i, (i * 7919) % 100003 });
        try block.appendNTimes(gpa, 'x', i % 7);
        try block.append(gpa, '\n');
    }
    var whole: std.ArrayList(u8) = .empty;
    defer whole.deinit(gpa);
    for (0..copies) |_| try whole.appendSlice(gpa, block.items);
    const rounds: usize = @intCast(common.opaqueN(3));
    var lines: usize = 0;
    var width: usize = 0;
    for (0..rounds) |_| {
        var rest: []const u8 = whole.items;
        while (rest.len > 0) {
            const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            width += rest[0..end].len;
            rest = rest[@min(end + 1, rest.len)..];
            lines += 1;
        }
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d} {d}\n", .{ lines, width });
    common.writeStdout(out.items);
}
