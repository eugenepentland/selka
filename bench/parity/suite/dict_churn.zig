// dict_churn: insert, lookup, delete, reinsert and iterate over a std.StringHashMap
// keyed by generated strings, then over a std.AutoHashMap keyed by u64 values
// (SUITE.md section 15). Keys live in one arena; the maps own only their tables.
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

const Gen = struct {
    x: u64 = 88172645463325252,

    /// One xorshift step; returns the whole state.
    fn full(self: *Gen) u64 {
        var x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        return x;
    }

    /// The step's output, shifted right by 33.
    fn draw(self: *Gen) u64 {
        return self.full() >> 33;
    }
};

/// Writes the five phases of one string-keyed map to `out`.
fn strPhases(gpa: std.mem.Allocator, arena: std.mem.Allocator, gen: *Gen, out: *std.ArrayList(u8), count: usize) !void {
    const keys = try arena.alloc([]const u8, count);
    for (keys, 0..) |*key, i| key.* = try std.fmt.allocPrint(arena, "n{d}_{d}", .{ gen.draw(), i });
    const miss = try arena.alloc([]const u8, count);
    for (miss, 0..) |*key, i| key.* = try std.fmt.allocPrint(arena, "n{d}_{d}", .{ gen.draw(), i });

    var map: std.StringHashMap(i64) = .init(gpa);
    defer map.deinit();
    for (keys, 0..) |key, i| try map.put(key, @intCast(i));
    try out.print(gpa, "str insert {d}\n", .{count});

    var hits: i64 = 0;
    for (keys) |key| hits += map.get(key) orelse 0;
    var misses: usize = 0;
    for (miss) |key| {
        if (!map.contains(key)) misses += 1;
    }
    try out.print(gpa, "str lookup hits_sum {d} misses {d}\n", .{ hits, misses });

    var removed: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 3) {
        if (map.remove(keys[i])) removed += 1;
    }
    try out.print(gpa, "str delete removed {d} size {d}\n", .{ removed, map.count() });

    var reinserted: usize = 0;
    i = 0;
    while (i < count) : (i += 6) {
        try map.put(keys[i], @intCast(2 * i));
        reinserted += 1;
    }
    try out.print(gpa, "str reinsert reinserted {d} size {d}\n", .{ reinserted, map.count() });

    var value_sum: i64 = 0;
    var key_len_sum: usize = 0;
    var it = map.iterator();
    while (it.next()) |entry| {
        value_sum += entry.value_ptr.*;
        key_len_sum += entry.key_ptr.*.len;
    }
    try out.print(gpa, "str iterate size {d} value_sum {d} key_len_sum {d}\n", .{ map.count(), value_sum, key_len_sum });
}

/// Writes the five phases of one u64-keyed map to `out`.
fn intPhases(gpa: std.mem.Allocator, arena: std.mem.Allocator, gen: *Gen, out: *std.ArrayList(u8), count: usize) !void {
    const keys = try arena.alloc(u64, count);
    for (keys) |*key| key.* = gen.full();
    const miss = try arena.alloc(u64, count);
    for (miss) |*key| key.* = gen.full();

    var map: std.AutoHashMap(u64, i64) = .init(gpa);
    defer map.deinit();
    for (keys, 0..) |key, i| try map.put(key, @intCast(i));
    try out.print(gpa, "int insert {d}\n", .{count});

    var hits: i64 = 0;
    for (keys) |key| hits += map.get(key) orelse 0;
    var misses: usize = 0;
    for (miss) |key| {
        if (!map.contains(key)) misses += 1;
    }
    try out.print(gpa, "int lookup hits_sum {d} misses {d}\n", .{ hits, misses });

    var removed: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 3) {
        if (map.remove(keys[i])) removed += 1;
    }
    try out.print(gpa, "int delete removed {d} size {d}\n", .{ removed, map.count() });

    var reinserted: usize = 0;
    i = 0;
    while (i < count) : (i += 6) {
        try map.put(keys[i], @intCast(2 * i));
        reinserted += 1;
    }
    try out.print(gpa, "int reinsert reinserted {d} size {d}\n", .{ reinserted, map.count() });

    var value_sum: i64 = 0;
    var key_sum: i64 = 0;
    var it = map.iterator();
    while (it.next()) |entry| {
        value_sum += entry.value_ptr.*;
        key_sum += @intCast(entry.key_ptr.* >> 33);
    }
    try out.print(gpa, "int iterate size {d} value_sum {d} key_sum {d}\n", .{ map.count(), value_sum, key_sum });
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var gen: Gen = .{};
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try strPhases(gpa, arena, &gen, &out, @intCast(common.opaqueN(800000)));
    try intPhases(gpa, arena, &gen, &out, @intCast(common.opaqueN(2000000)));
    common_c.writeStdout(out.items);
}
