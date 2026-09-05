const std = @import("std");
const t = std.testing;
const memory = @import("memory.zig");
const values = @import("value.zig");
const pools = @import("pool_runtime.zig");
const typed = @import("typed.zig");
const arena = @import("arena.zig");
const node_type: values.Type = @fromBackingInt(values.Type.record_base);
const pool_type: values.Type = @fromBackingInt(values.Type.record_base + 1);
const handle_type: values.Type = @fromBackingInt(values.Type.record_base + 2);
const schema: typed.Pool = .{ .element = node_type, .handle = handle_type };

fn scenario(allocator: std.mem.Allocator) !void {
    var store = try memory.Store.init(allocator);
    defer store.deinit();
    var runtime: pools.Runtime = .{ .allocator = allocator, .limits = .{ .max_pools = 1, .max_total_slots = 2 } };
    const root = try store.allocatorCapability();
    const outer = try store.beginRegion(root);
    const inner = try store.beginRegion(outer);
    try t.expectError(error.ChildrenActive, store.endRegion(outer));
    const value = try values.Value.create(allocator, node_type, &.{.{ .i64 = 7 }});
    defer value.release(allocator);
    var snapshot: ?values.Value = null;
    defer if (snapshot) |retained| retained.release(allocator);
    {
        const owner = try runtime.acquireAuthorized(pool_type, 2, &store, inner);
        defer owner.release(allocator);
        const id = try owner.pool.perform(.insert, schema, &.{value});
        snapshot = try owner.pool.perform(.read, schema, &.{id});
        const buffer = try store.createAuthorized(inner, node_type, &.{value}, 1);
        defer store.destroyForUnwind(buffer) catch unreachable;
        _ = try store.reserve(buffer, 3);
        try t.expectError(error.RegionInUse, store.endRegion(inner));
        try t.expectError(error.InvalidCapability, store.checkAllocationAllocator(buffer, root));
        try store.checkAllocationAllocator(buffer, inner);
        const replacement = try values.Value.create(allocator, node_type, &.{.{ .i64 = 9 }});
        defer replacement.release(allocator);
        discardValue(try owner.pool.perform(.replace, schema, &.{ id, replacement }), allocator);
    }
    try store.endRegion(inner);
    try store.endRegion(outer);
    try t.expectError(error.InvalidCapability, store.checkAllocator(inner));
    try t.expectError(error.InvalidCapability, store.beginRegion(outer));
    const field = try snapshot.?.getField(0);
    defer field.release(allocator);
    try t.expectEqual(@as(i64, 7), field.i64);
    try t.expectEqual(@as(usize, 0), store.statistics.live_allocations);
    try t.expectEqual(@as(usize, 0), runtime.statistics.live_pools);
    try t.expectEqual(@as(usize, 0), runtime.statistics.reserved_slots);
}
fn discardValue(value: values.Value, allocator: std.mem.Allocator) void {
    value.release(allocator);
}
test "nested arena backing supports pools buffers and independent node snapshots" {
    try scenario(t.allocator);
}
test "mixed arena buffers pools and snapshots unwind at every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "region capacity and generations constrain copied and foreign capabilities" {
    var store = try memory.Store.initWithLimits(t.allocator, .{ .max_regions = 1 });
    defer store.deinit();
    var other = try memory.Store.init(t.allocator);
    defer other.deinit();
    const root = try store.allocatorCapability();
    const region = try store.beginRegion(root);
    try t.expectError(error.CapacityLimit, store.beginRegion(root));
    try t.expectError(error.CapacityLimit, store.beginRegion(region));
    try t.expectError(error.InvalidCapability, other.checkAllocator(region));
    try t.expectError(error.InvalidCapability, store.endRegion(root));
    try store.endRegion(region);
    const replacement = try store.beginRegion(root);
    try t.expect(!std.meta.eql(region, replacement));
    try t.expectError(error.InvalidCapability, store.createAuthorized(region, .i64, &.{}, 0));
    try t.expectError(error.InvalidCapability, store.endRegion(region));
    try store.endRegion(replacement);
}
test "ending a region cannot free buffer backing with an outstanding loan" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    const region = try store.beginRegion(try store.allocatorCapability());
    const buffer = try store.createAuthorized(region, .i64, &.{.{ .i64 = 7 }}, 1);
    const loan = try store.borrow(buffer, 0, 1, .shared);
    try t.expectError(error.RegionInUse, store.endRegion(region));
    try t.expectError(error.BorrowConflict, store.destroy(buffer));
    const value = try store.read(loan, 0);
    defer value.release(t.allocator);
    try t.expectEqual(@as(i64, 7), value.i64);
    try store.destroyForUnwind(buffer);
    try store.endRegion(region);
    try t.expectError(error.ExpiredBorrow, store.read(loan, 0));
}
test "arena reset rejects retained root pool backing before changing buffers" {
    var region: arena.Arena = undefined;
    try region.init(t.allocator, .{});
    defer region.deinit();
    var runtime: pools.Runtime = .{ .allocator = t.allocator, .limits = .{} };
    const cap = try region.store.allocatorCapability();
    const buffer = try region.store.createAuthorized(cap, .i64, &.{.{ .i64 = 4 }}, 1);
    {
        const owner = try runtime.acquireAuthorized(pool_type, 1, &region.store, cap);
        defer owner.release(t.allocator);
        try t.expectError(error.RegionInUse, region.reset(.free_all));
        const value = try region.store.readOwner(buffer, 0);
        defer value.release(t.allocator);
        try t.expectEqual(@as(i64, 4), value.i64);
    }
    try t.expect(try region.reset(.free_all));
    try t.expectError(error.InvalidAllocation, region.store.info(buffer));
}
test "arena pool clear frees retained values with their parent allocator" {
    var region: arena.Arena = undefined;
    try region.init(t.allocator, .{});
    defer region.deinit();
    var runtime: pools.Runtime = .{ .allocator = t.allocator, .limits = .{} };
    const owner = try runtime.acquireAuthorized(pool_type, 1, &region.store, try region.store.allocatorCapability());
    defer owner.release(t.allocator);
    {
        const value = try values.Value.create(t.allocator, node_type, &.{.{ .i64 = 7 }});
        defer value.release(t.allocator);
        discardValue(try owner.pool.perform(.insert, schema, &.{value}), t.allocator);
    }
    // The pool now owns the only reference. Clearing must free parent-allocated
    // Aggregate and field storage, never pass them to the arena allocator.
    discardValue(try owner.pool.perform(.clear, schema, &.{}), t.allocator);
    try t.expectEqual(@as(usize, 0), owner.pool.registry.statistics.live);
}

test "region storage and registry slots remain bounded across ten thousand pool and buffer scopes" {
    var bounded: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    {
        const allocator = bounded.allocator();
        var store = try memory.Store.initWithLimits(allocator, .{ .max_regions = 1 });
        defer store.deinit();
        var runtime: pools.Runtime = .{ .allocator = allocator, .limits = .{ .max_pools = 1 } };
        const root = try store.allocatorCapability();
        for (0..10000) |n| {
            const region = try store.beginRegion(root);
            {
                const owner = try runtime.acquireAuthorized(pool_type, 1, &store, region);
                defer owner.release(allocator);
                const value = try values.Value.create(allocator, node_type, &.{.{ .i64 = @intCast(n) }});
                defer value.release(allocator);
                const id = try owner.pool.perform(.insert, schema, &.{value});
                const snapshot = try owner.pool.perform(.read, schema, &.{id});
                defer snapshot.release(allocator);
                const buffer = try store.createAuthorized(region, node_type, &.{snapshot}, 1);
                defer store.destroyForUnwind(buffer) catch unreachable;
                const field = try snapshot.getField(0);
                defer field.release(allocator);
                try t.expectEqual(@as(i64, @intCast(n)), field.i64);
            }
            try store.endRegion(region);
        }
        try t.expectEqual(@as(usize, 0), store.regions.registry.statistics.live);
        try t.expectEqual(@as(u64, 10000), runtime.statistics.released);
        try t.expectEqual(@as(u64, 10000), store.statistics.released);
    }
    try t.expectEqual(@as(usize, 0), bounded.live);
}
test "failed pool acquisition and zero-capacity backing cannot bypass region lifetime guards" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    var runtime: pools.Runtime = .{ .allocator = t.allocator, .limits = .{ .max_pools = 1 } };
    const region = try store.beginRegion(try store.allocatorCapability());
    {
        const owner = try runtime.acquireAuthorized(pool_type, 0, &store, region);
        defer owner.release(t.allocator);
        try t.expectError(error.CapacityLimit, runtime.acquireAuthorized(pool_type, 0, &store, region));
        try t.expectError(error.RegionInUse, store.endRegion(region));
    }
    const zero = try store.createAuthorized(region, .i64, &.{}, 0);
    try t.expectError(error.RegionInUse, store.endRegion(region));
    try store.destroy(zero);
    try store.endRegion(region);
    try t.expectError(error.InvalidCapability, runtime.acquireAuthorized(pool_type, 0, &store, region));
}
