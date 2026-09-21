// list_records: a list of 32-byte structs, then ten field-summing passes.
const std = @import("std");
const common = @import("common.zig");

const Row = struct {
    a: i64,
    b: i64,
    c: i64,
    d: i64,
};

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const n = common.opaqueN(2000000);
    var rows: std.ArrayList(Row) = .empty;
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        rows.append(gpa, Row{ .a = i, .b = i + 1, .c = i + 2, .d = i + 3 }) catch unreachable;
    }
    var total: i64 = 0;
    var pass_index: i64 = 0;
    while (pass_index < 10) : (pass_index += 1) {
        total += pass_index;
        for (rows.items) |row| {
            total += row.c;
        }
    }
    common.emit1(total);
}
