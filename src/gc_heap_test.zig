//! Tracing roots, cycles, allocation failures, and stable managed identities.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const t = std.testing;
const list_type: values.Type = @fromBackingInt(@intCast(32));
const record_type: values.Type = @fromBackingInt(@intCast(33));
// spec: GC-ROOTS-1
test "GC-ROOTS-1 retained aliases and temporaries survive stress growth" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.stress = true;
    const list = try heap.create(list_type, .i64, 0);
    defer list.release(t.allocator);
    const alias = list.retain();
    defer alias.release(t.allocator);
    for (0..150) |i| try heap.append(list, .{ .i64 = @intCast(i) });
    try heap.write(alias, 37, .{ .i64 = 999 });
    try t.expectEqual(@as(usize, 150), try heap.len(alias));
    try t.expectEqual(@as(i64, 999), (try heap.read(list, 37)).i64);
    try t.expect(list.managed == alias.managed);
    try t.expect(heap.statistics.collections >= 150);
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
}
// spec: GC-CYCLES-1
test "GC-CYCLES-1 reachable self cycle survives and unreachable self cycle is reclaimed" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const list = try heap.create(list_type, list_type, 0);
    try heap.append(list, list);
    try heap.collect();
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
    const element = try heap.read(list, 0);
    try t.expect(element.managed == list.managed);
    list.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
    element.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
    try t.expectEqual(@as(u64, 1), heap.statistics.reclaimed);
}
test "GC-CYCLES-1 aggregate bridge cycles preserve external snapshots then reclaim" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const list = try heap.create(list_type, record_type, 0);
    const bridge = try values.Value.create(t.allocator, record_type, &.{list});
    try heap.append(list, bridge);
    try heap.append(list, bridge);
    list.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
    bridge.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
}
test "GC-CYCLES-1 two object cycle releases fields before destroying headers" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const a = try heap.create(list_type, list_type, 0);
    const b = try heap.create(list_type, list_type, 0);
    try heap.append(a, b);
    try heap.append(b, a);
    a.release(t.allocator);
    b.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
    try t.expectEqual(@as(u64, 2), heap.statistics.reclaimed);
}
// spec: GC-BOUNDARY-1
test "GC-BOUNDARY-1 foreign heaps, wrong element types, and invalid indices reject" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    var foreign = gc.Heap.init(t.allocator);
    defer foreign.deinit();
    const a = try heap.create(list_type, list_type, 0);
    defer a.release(t.allocator);
    const b = try foreign.create(list_type, list_type, 0);
    defer b.release(t.allocator);
    try t.expectError(error.ForeignMemory, heap.append(a, b));
    try t.expectError(error.ForeignMemory, heap.len(b));
    try t.expectError(error.TypeMismatch, heap.append(a, .{ .i64 = 0 }));
    try t.expectError(error.Bounds, heap.read(a, 0));
    try t.expectError(error.Bounds, heap.write(a, 0, a));
}
fn allocationFailures(allocator: std.mem.Allocator) !void {
    var heap = gc.Heap.init(allocator);
    defer heap.deinit();
    heap.stress = true;
    const list = try heap.create(list_type, record_type, 0);
    defer list.release(allocator);
    const bridge = try values.Value.create(allocator, record_type, &.{list});
    defer bridge.release(allocator);
    try heap.append(list, bridge);
    try heap.collect();
    const saved = try heap.read(list, 0);
    defer saved.release(allocator);
    try t.expectEqual(@as(usize, 1), try heap.len(list));
}
// spec: GC-FAILURE-1
test "GC-FAILURE-1 every allocation failure preserves root cleanup and heap teardown" {
    try t.checkAllAllocationFailures(t.allocator, allocationFailures, .{});
}
test "GC-CYCLES-1 deep graph traces and sweeps without recursive host calls" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    heap.next_collection = std.math.maxInt(usize);
    const root = try heap.create(list_type, list_type, 0);
    var tail = root.retain();
    for (0..10000) |_| {
        const next = try heap.create(list_type, list_type, 0);
        try heap.append(tail, next);
        tail.release(t.allocator);
        tail = next;
    }
    try heap.append(tail, root);
    tail.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 10001), heap.statistics.live_objects);
    root.release(t.allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
}
test "GC-FAILURE-1 failed collection leaves aliases and cycles usable for retry" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    const allocator = failing.allocator();
    var heap = gc.Heap.init(allocator);
    defer heap.deinit();
    const list = try heap.create(list_type, list_type, 0);
    try heap.append(list, list);
    failing.fail_index = failing.alloc_index;
    try t.expectError(error.OutOfMemory, heap.collect());
    try t.expectEqual(@as(usize, 1), try heap.len(list));
    try t.expectEqual(@as(usize, 1), heap.statistics.live_objects);
    try t.expectEqual(@as(u64, 0), heap.statistics.collections);
    failing.fail_index = std.math.maxInt(usize);
    try heap.collect();
    const alias = try heap.read(list, 0);
    try t.expect(alias.managed == list.managed);
    alias.release(allocator);
    list.release(allocator);
    try heap.collect();
    try t.expectEqual(@as(usize, 0), heap.statistics.live_objects);
}
// spec: GC-GRAPH-1
test "managed element validation visits shared aggregate DAGs once" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const list = try heap.create(list_type, record_type, 0);
    defer list.release(t.allocator);
    var value = try values.Value.create(t.allocator, record_type, &.{.{ .i64 = 42 }});
    defer value.release(t.allocator);
    for (0..64) |_| {
        const outer = try values.Value.create(t.allocator, record_type, &.{ value, value });
        value.release(t.allocator);
        value = outer;
    }
    try heap.append(list, value);
    try heap.collect();
    try t.expectEqual(@as(usize, 1), try heap.len(list));
}
test "GC-BOUNDARY-1 nested foreign references cannot enter managed storage" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const list = try heap.create(list_type, record_type, 0);
    defer list.release(t.allocator);
    var foreign = gc.Heap.init(t.allocator);
    defer foreign.deinit();
    const other = try foreign.create(list_type, list_type, 0);
    defer other.release(t.allocator);
    const foreign_wrapper = try values.Value.create(t.allocator, record_type, &.{other});
    defer foreign_wrapper.release(t.allocator);
    try t.expectError(error.ForeignMemory, heap.append(list, foreign_wrapper));
    try t.expectEqual(@as(usize, 0), try heap.len(list));
}
// spec: GC-CAPABILITY-1
test "managed heap rejects capability grants and nested authority" {
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const authority: values.Value = .{ .capability = .{ .external = .{ .execution = 1, .kind = .clock } } };
    const list = try heap.create(list_type, .clock_cap, 0);
    defer list.release(t.allocator);
    try t.expectError(error.InvalidDataValue, heap.append(list, authority));
    const wrapper = try values.Value.create(t.allocator, record_type, &.{authority});
    defer wrapper.release(t.allocator);
    const wrapped = try heap.create(list_type, record_type, 0);
    defer wrapped.release(t.allocator);
    try t.expectError(error.InvalidDataValue, heap.append(wrapped, wrapper));
}
