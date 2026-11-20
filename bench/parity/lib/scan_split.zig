// scan_split: std.mem.splitSequence over LIB.md's 4 MB text.
const std = @import("std");
const common = @import("common.zig");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const text = try common.text(gpa);
    defer gpa.free(text);
    const rounds: usize = @intCast(common.opaqueN(3));
    var lines: usize = 0;
    var width: usize = 0;
    var fields: usize = 0;
    var runs: usize = 0;
    var run_width: usize = 0;
    for (0..rounds) |_| {
        var line_it = std.mem.splitSequence(u8, text, "\n");
        while (line_it.next()) |line| {
            lines += 1;
            width += line.len;
        }
        var field_it = std.mem.splitSequence(u8, text, ",");
        while (field_it.next()) |_| fields += 1;
        var run_it = std.mem.splitSequence(u8, text, "x\nitem");
        while (run_it.next()) |run| {
            runs += 1;
            run_width += run.len;
        }
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "{d} {d} {d} {d} {d}\n", .{ lines, width, fields, runs, run_width });
    common.writeStdout(out.items);
}
