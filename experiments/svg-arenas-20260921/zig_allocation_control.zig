const std = @import("std");
const groups = 96;
const width = 64;

fn batch(allocator: std.mem.Allocator, explicit_free: bool) !i64 {
    const rows = try allocator.alloc([]i64, groups);
    var made: usize = 0;
    defer if (explicit_free) {
        for (rows[0..made]) |row| allocator.free(row);
        allocator.free(rows);
    };
    for (rows, 0..) |*row, group| {
        row.* = try allocator.alloc(i64, width);
        made += 1;
        for (row.*, 0..) |*item, index| item.* = @intCast(group + index);
    }
    var checksum: i64 = 0;
    for (rows) |row| {
        for (row) |item| checksum = @mod(checksum + item, 1000000007);
    }
    return checksum;
}

pub fn main() !void {
    var gc_total: i64 = 0;
    for (0..64) |_| gc_total = @mod(gc_total + try batch(std.heap.page_allocator, true), 1000000007);
    var arena_total: i64 = 0;
    for (0..64) |_| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        arena_total = @mod(arena_total + try batch(arena.allocator(), false), 1000000007);
    }
    if (gc_total != 31064064 or arena_total != 31064064) return error.WrongChecksum;
}
