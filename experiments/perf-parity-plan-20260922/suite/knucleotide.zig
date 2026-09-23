// knucleotide: every k-letter substring of a generated DNA sequence counted in a
// std.StringHashMap(u32) keyed by slices of one byte sequence (SUITE.md section 6).
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

const Entry = struct {
    key: []const u8,
    count: u32,
};

fn generate(gpa: std.mem.Allocator, length: usize) ![]u8 {
    const bases = "ACGT";
    const seq = try gpa.alloc(u8, length);
    var seed: i64 = 42;
    for (seq) |*base| {
        seed = @mod(seed * 3877 + 29573, 139968);
        base.* = bases[@intCast(@divTrunc(seed * 4, 139968))];
    }
    return seq;
}

fn frequencies(gpa: std.mem.Allocator, seq: []const u8, k: usize) !std.StringHashMap(u32) {
    var counts: std.StringHashMap(u32) = .init(gpa);
    var i: usize = 0;
    while (i + k <= seq.len) : (i += 1) {
        const slot = try counts.getOrPut(seq[i .. i + k]);
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
    }
    return counts;
}

/// Count descending, then key ascending in byte order.
fn moreFrequent(_: void, a: Entry, b: Entry) bool {
    if (a.count != b.count) return a.count > b.count;
    return std.mem.order(u8, a.key, b.key) == .lt;
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const seq = try generate(gpa, @intCast(common.opaqueN(1000000)));
    defer gpa.free(seq);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for ([_]usize{ 1, 2 }) |k| {
        var counts = try frequencies(gpa, seq, k);
        defer counts.deinit();
        var entries: std.ArrayList(Entry) = .empty;
        defer entries.deinit(gpa);
        var it = counts.iterator();
        while (it.next()) |kv| try entries.append(gpa, .{ .key = kv.key_ptr.*, .count = kv.value_ptr.* });
        std.mem.sort(Entry, entries.items, {}, moreFrequent);
        for (entries.items) |entry| try out.print(gpa, "{s} {d}\n", .{ entry.key, entry.count });
    }
    const keys = [_][]const u8{ "GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT" };
    for (keys) |key| {
        var counts = try frequencies(gpa, seq, key.len);
        defer counts.deinit();
        try out.print(gpa, "{d}\t{s}\n", .{ counts.get(key) orelse 0, key });
    }
    common_c.writeStdout(out.items);
}
