// sort_records: one million {key, id} records stable-sorted by key through
// std.mem.sort with a lessThan on key; prints the first and last key and a
// checksum over the ids in sorted order. Fields are i64 to match selka's int.
const std = @import("std");
const common = @import("common.zig");
const common_b = @import("common_b.zig");

const Rec = struct { key: i64, id: i64 };

fn xorshift(state: u64) u64 {
    var x = state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return x;
}

fn mix(c: i64, v: i64) i64 {
    return @mod(c * 31 + v, 1000000007);
}

fn byKey(_: void, a: Rec, b: Rec) bool {
    return a.key < b.key;
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const n: usize = @intCast(common.opaqueN(1000000));
    const records = try gpa.alloc(Rec, n);
    defer gpa.free(records);
    var state: u64 = 88172645463325252;
    for (records, 0..) |*r, i| {
        state = xorshift(state);
        r.* = .{ .key = @intCast((state >> 33) % 100000), .id = @intCast(i) };
    }
    std.mem.sort(Rec, records, {}, byKey);
    var c: i64 = 0;
    for (records) |r| c = mix(c, r.id);
    common_b.print("{d} {d}\n{d}\n", .{ records[0].key, records[n - 1].key, c });
}
