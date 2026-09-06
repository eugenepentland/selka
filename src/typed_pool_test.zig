const std = @import("std");
const t = std.testing;
const pools = @import("typed_pool.zig");
const NodeTag = enum { node };
const EdgeTag = enum { edge };
const Node = struct { value: i64, next: ?pools.Handle(NodeTag) = null };
const Nodes = pools.Pool(NodeTag, Node);

test "nominal handle categories and pool identities prevent cross-category and cross-instance access" {
    try t.expect(pools.Handle(NodeTag) != pools.Handle(EdgeTag));
    var first = try Nodes.init(t.allocator, 2, .{});
    defer first.deinit();
    var second = try Nodes.init(t.allocator, 2, .{});
    defer second.deinit();
    const id = try first.insert(.{ .value = 7 });
    _ = try second.insert(.{ .value = 9 });
    try t.expectError(error.ForeignPool, second.get(id));
    // Identity is global across payload specializations sharing the same category.
    var other_layout = try pools.Pool(NodeTag, i64).init(t.allocator, 1, .{});
    defer other_layout.deinit();
    _ = try other_layout.insert(11);
    try t.expectError(error.ForeignPool, other_layout.get(id));
    first.deinit();
    try t.expectError(error.PoolClosed, first.get(id));
    first = try Nodes.init(t.allocator, 2, .{});
    try t.expectError(error.ForeignPool, first.get(id));
}
test "cyclic graph edges remain stale after removal and slot reuse" {
    var nodes = try Nodes.init(t.allocator, 2, .{});
    defer nodes.deinit();
    const a = try nodes.insert(.{ .value = 1 });
    const b = try nodes.insert(.{ .value = 2, .next = a });
    try nodes.replace(a, .{ .value = 1, .next = b });
    var cursor = a;
    var sum: i64 = 0;
    for (0..20) |_| {
        const node = try nodes.get(cursor);
        sum += node.value;
        cursor = node.next.?;
    }
    try t.expectEqual(@as(i64, 30), sum);
    const snapshot = try nodes.get(a);
    try nodes.remove(b);
    const c = try nodes.insert(.{ .value = 3 });
    try t.expectEqual(b.index, c.index);
    try t.expect(b.generation != c.generation);
    try t.expectError(error.InvalidHandle, nodes.get(snapshot.next.?));
    try nodes.replace(a, .{ .value = 1, .next = c });
    try t.expectEqual(@as(i64, 3), (try nodes.get((try nodes.get(a)).next.?)).value);
    try t.expectError(error.CapacityLimit, nodes.insert(.{ .value = 4 }));
}
test "bulk clear invalidates all handles while retaining reusable capacity" {
    var nodes = try Nodes.init(t.allocator, 3, .{});
    defer nodes.deinit();
    const a = try nodes.insert(.{ .value = 1 });
    const b = try nodes.insert(.{ .value = 2 });
    const capacity = nodes.entries.capacity;
    try nodes.clear();
    try nodes.clear();
    try t.expectEqual(capacity, nodes.entries.capacity);
    try t.expectError(error.InvalidHandle, nodes.get(a));
    try t.expectError(error.InvalidHandle, nodes.remove(b));
    const replacement = try nodes.insert(.{ .value = 3 });
    try t.expect(replacement.generation > 1);
    try t.expectEqual(@as(usize, 1), nodes.statistics.live);
    try t.expectEqual(@as(u64, 2), nodes.statistics.removed);
}
test "reserved insert replace get remove and clear do not allocate" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var nodes = try Nodes.init(failing.allocator(), 3, .{});
    defer nodes.deinit();
    try nodes.reserve(3);
    failing.fail_index = failing.alloc_index;
    const a = try nodes.insert(.{ .value = 1 });
    _ = try nodes.insert(.{ .value = 2 });
    _ = try nodes.insert(.{ .value = 3 });
    try nodes.replace(a, .{ .value = 7 });
    try t.expectEqual(@as(i64, 7), (try nodes.get(a)).value);
    try nodes.remove(a);
    _ = try nodes.insert(.{ .value = 4 });
    try nodes.clear();
    _ = try nodes.insert(.{ .value = 5 });
}
test "failed registry growth preserves the existing graph" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var nodes = try Nodes.init(failing.allocator(), 1000, .{});
    defer nodes.deinit();
    const a = try nodes.insert(.{ .value = 7 });
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try t.expectError(error.OutOfMemory, nodes.reserve(1000));
    try t.expectEqual(@as(i64, 7), (try nodes.get(a)).value);
    try t.expectEqual(@as(usize, 1), nodes.statistics.live);
}
const Value = @import("value.zig").Value;
const ValuePool = pools.Pool(NodeTag, Value);
fn valuesScenario(allocator: std.mem.Allocator) !void {
    var pool = try ValuePool.init(allocator, 30, .{ .retain = Value.retain, .release = Value.release });
    defer pool.deinit();
    const value = try Value.create(allocator, @fromBackingInt(@import("value.zig").Type.record_base), &.{.{ .i64 = 7 }});
    defer value.release(allocator);
    var first: ?ValuePool.Id = null;
    for (0..30) |_| {
        const id = try pool.insert(value);
        if (first == null) first = id;
    }
    const snapshot = try pool.get(first.?);
    defer snapshot.release(allocator);
    try pool.replace(first.?, snapshot);
    try pool.clear();
    const field = try snapshot.getField(0);
    defer field.release(allocator);
    try t.expectEqual(@as(i64, 7), field.i64);
}
test "retained guest value snapshots survive replacement and bulk reset with allocation failures" {
    try valuesScenario(t.allocator);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), valuesScenario, .{});
}
test "exhausted generations retire slots instead of reviving stale graph IDs" {
    var nodes = try Nodes.init(t.allocator, 2, .{});
    defer nodes.deinit();
    var last = try nodes.insert(.{ .value = 7 });
    const original = last;
    nodes.entries.items[last.index].generation = std.math.maxInt(u64);
    last.generation = std.math.maxInt(u64);
    try nodes.remove(last);
    const next = try nodes.insert(.{ .value = 9 });
    try t.expect(next.index != last.index);
    try t.expectEqual(@as(usize, 1), nodes.statistics.retired);
    try t.expectError(error.InvalidHandle, nodes.get(original));
    try t.expectError(error.InvalidHandle, nodes.get(last));
    try nodes.remove(next);
    _ = try nodes.insert(.{ .value = 11 });
    try t.expectError(error.CapacityLimit, nodes.insert(.{ .value = 13 }));
}
test "recycled pool slots and bulk resets stay within a fixed live memory bound" {
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 4096 };
    defer limited.deinit();
    var nodes = try Nodes.init(limited.allocator(), 2, .{});
    defer nodes.deinit();
    for (0..10000) |index| {
        const id = try nodes.insert(.{ .value = @intCast(index) });
        const next = try nodes.insert(.{ .value = @intCast(index), .next = id });
        try nodes.replace(id, .{ .value = @intCast(index), .next = next });
        try nodes.clear();
        try t.expectError(error.InvalidHandle, nodes.get(id));
    }
    try t.expectEqual(@as(usize, 2), nodes.entries.items.len);
    nodes.deinit();
    try t.expectEqual(@as(usize, 0), limited.live);
}

const Tracked = struct {
    references: usize = 1,
    fn retain(value: *Tracked) *Tracked {
        value.references += 1;
        return value;
    }
    fn release(value: *Tracked, _: std.mem.Allocator) void {
        value.references -= 1;
    }
};
test "failed insert and invalid mutations never acquire or release payload ownership" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var pool = try pools.Pool(NodeTag, *Tracked).init(failing.allocator(), 1, .{
        .retain = Tracked.retain,
        .release = Tracked.release,
    });
    defer pool.deinit();
    var payload: Tracked = .{};
    failing.fail_index = failing.alloc_index;
    try t.expectError(error.OutOfMemory, pool.insert(&payload));
    try t.expectEqual(@as(usize, 1), payload.references);
    failing.fail_index = std.math.maxInt(usize);
    const old = try pool.insert(&payload);
    try t.expectEqual(@as(usize, 2), payload.references);
    try t.expectError(error.CapacityLimit, pool.insert(&payload));
    try pool.remove(old);
    const current = try pool.insert(&payload);
    try t.expectError(error.InvalidHandle, pool.replace(old, &payload));
    try t.expectError(error.InvalidHandle, pool.remove(old));
    var forged = current;
    forged.index = std.math.maxInt(usize);
    try t.expectError(error.InvalidHandle, pool.get(forged));
    try t.expectEqual(@as(usize, 2), payload.references);
    try pool.replace(current, &payload);
    try t.expectEqual(@as(usize, 2), payload.references);
    pool.deinit();
    pool.deinit();
    try t.expectError(error.PoolClosed, pool.insert(&payload));
    try t.expectEqual(@as(usize, 1), payload.references);
}
