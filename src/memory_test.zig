//! Guest allocation identity and dynamic borrow tests, including lease growth failures and recovery after allocation errors.
const std = @import("std");
const testing = std.testing;
const memory = @import("memory.zig");
const Value = @import("value.zig").Value;
const Type = @import("value.zig").Type;
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;

fn number(store: *memory.Store, borrow: memory.Borrow, index: usize, expected: i64) !void {
    const value = try store.read(borrow, index);
    defer value.release(store.allocator);
    try testing.expectEqual(expected, value.i64);
}

test "shared and exclusive memory borrows enforce owner and alias access" {
    var store = try memory.Store.init(testing.allocator);
    defer store.deinit();
    const owner = try store.create(.i64, &.{ .{ .i64 = 3 }, .{ .i64 = 7 } });
    const a = try store.borrow(owner, 0, 2, .shared);
    const b = try store.borrow(owner, 1, 1, .shared);
    try store.checkOwnerAccess(owner, false);
    try testing.expectError(error.BorrowConflict, store.checkOwnerAccess(owner, true));
    try number(&store, a, 0, 3);
    try number(&store, b, 0, 7);
    try testing.expectEqual(@as(i64, 7), (try store.readOwner(owner, 1)).i64);
    try testing.expectError(error.ReadOnly, store.write(a, 0, .{ .i64 = 8 }));
    try testing.expectError(error.BorrowConflict, store.writeOwner(owner, 0, .{ .i64 = 8 }));
    try testing.expectError(error.BorrowConflict, store.borrow(owner, 0, 1, .exclusive));
    try testing.expectError(error.BorrowConflict, store.destroy(owner));
    try store.end(a);
    try testing.expectError(error.BorrowConflict, store.borrow(owner, 0, 1, .exclusive));
    try store.end(b);
    const exclusive = try store.borrow(owner, 0, 2, .exclusive);
    try store.write(exclusive, 1, .{ .i64 = 9 });
    try number(&store, exclusive, 1, 9);
    try testing.expectError(error.BorrowConflict, store.readOwner(owner, 0));
    try testing.expectError(error.BorrowConflict, store.borrow(owner, 0, 0, .shared));
    try store.end(exclusive);
    try testing.expectEqual(@as(i64, 9), (try store.readOwner(owner, 1)).i64);
    try store.destroy(owner);
}

test "memory bounds cover empty views subviews maximum indices and exact element types" {
    var store = try memory.Store.init(testing.allocator);
    defer store.deinit();
    const owner = try store.create(.u8, &.{Value.number(.u8, 7)});
    const empty = try store.borrow(owner, 1, 0, .shared);
    try testing.expectEqual(@as(usize, 0), (try store.describe(empty)).length);
    try testing.expectError(error.Bounds, store.read(empty, 0));
    try testing.expectError(error.Bounds, store.borrow(owner, 2, 0, .shared));
    try testing.expectError(error.Bounds, store.borrow(owner, 1, std.math.maxInt(usize), .shared));
    try store.end(empty);
    const view = try store.borrow(owner, 0, 1, .exclusive);
    try testing.expectError(error.TypeMismatch, store.write(view, 0, .{ .i64 = 7 }));
    try testing.expectError(error.Bounds, store.write(view, std.math.maxInt(usize), Value.number(.u8, 8)));
    try testing.expectError(error.Bounds, store.reborrow(view, std.math.maxInt(usize), 1, .shared));
    try store.end(view);
    try testing.expectError(error.TypeMismatch, store.create(.bool, &.{.{ .i64 = 1 }}));
    try store.destroy(owner);
}

test "exclusive reborrows suspend parents and end in child before parent order" {
    var store = try memory.Store.init(testing.allocator);
    defer store.deinit();
    const owner = try store.create(.i64, &.{ .{ .i64 = 2 }, .{ .i64 = 3 }, .{ .i64 = 4 } });
    const root = try store.borrow(owner, 0, 3, .exclusive);
    const child = try store.reborrow(root, 1, 2, .exclusive);
    const grandchild = try store.reborrow(child, 1, 1, .shared);
    const view = try store.describe(grandchild);
    try testing.expectEqual(@as(usize, 2), view.start);
    try testing.expectEqual(owner, view.allocation);
    try number(&store, grandchild, 0, 4);
    try testing.expectError(error.BorrowSuspended, store.read(root, 0));
    try testing.expectError(error.BorrowSuspended, store.write(child, 0, .{ .i64 = 9 }));
    try testing.expectError(error.ChildrenActive, store.end(root));
    try testing.expectError(error.ChildrenActive, store.end(child));
    try store.end(grandchild);
    try store.write(child, 1, .{ .i64 = 11 });
    try store.end(child);
    try number(&store, root, 2, 11);
    try store.end(root);
    try store.destroy(owner);
}

test "shared reborrows remain readable but cannot escalate permissions or outlive parents" {
    var store = try memory.Store.init(testing.allocator);
    defer store.deinit();
    const owner = try store.create(.i64, &.{.{ .i64 = 7 }});
    const root = try store.borrow(owner, 0, 1, .shared);
    const a = try store.reborrow(root, 0, 1, .shared);
    const b = try store.reborrow(root, 0, 1, .shared);
    try number(&store, root, 0, 7);
    try testing.expectError(error.ReadOnly, store.reborrow(root, 0, 1, .exclusive));
    try store.end(a);
    try testing.expectError(error.ChildrenActive, store.end(root));
    try store.end(b);
    try store.end(root);
    try testing.expectError(error.ExpiredBorrow, store.read(a, 0));
    try store.destroy(owner);
}

test "stale allocation and borrow handles cannot alias recycled slots or another store" {
    var first = try memory.Store.init(testing.allocator);
    defer first.deinit();
    var second = try memory.Store.init(testing.allocator);
    defer second.deinit();
    const owner = try first.create(.i64, &.{.{ .i64 = 1 }});
    const old = try first.borrow(owner, 0, 1, .shared);
    try first.end(old);
    const fresh = try first.borrow(owner, 0, 1, .exclusive);
    try testing.expectEqual(old.token.index, fresh.token.index);
    try testing.expect(old.token.generation != fresh.token.generation);
    try testing.expectError(error.ExpiredBorrow, first.read(old, 0));
    try testing.expectError(error.ExpiredBorrow, first.end(old));
    const other = try second.create(.i64, &.{.{ .i64 = 2 }});
    _ = try second.borrow(other, 0, 1, .exclusive);
    try testing.expectError(error.ForeignMemory, second.read(fresh, 0));
    try testing.expectError(error.ForeignMemory, second.destroy(owner));
    try first.end(fresh);
    try first.destroy(owner);
    const next = try first.create(.i64, &.{.{ .i64 = 3 }});
    try testing.expectEqual(owner.token.index, next.token.index);
    try testing.expectError(error.InvalidAllocation, first.borrow(owner, 0, 1, .shared));
    first.deinit();
    try testing.expectError(error.MemoryClosed, first.readOwner(next, 0));
    try testing.expectError(error.MemoryClosed, first.create(.i64, &.{}));
}

test "memory stores retain nested value snapshots independently of later writes" {
    var store = try memory.Store.init(testing.allocator);
    defer store.deinit();
    const ty: Type = @fromBackingInt(Type.record_base);
    const a = try Value.create(store.allocator, ty, &.{.{ .i64 = 7 }});
    defer a.release(store.allocator);
    const b = try Value.create(store.allocator, ty, &.{.{ .i64 = 9 }});
    defer b.release(store.allocator);
    const owner = try store.create(ty, &.{a});
    const reference = try store.borrow(owner, 0, 1, .exclusive);
    const snapshot = try store.read(reference, 0);
    defer snapshot.release(store.allocator);
    try store.write(reference, 0, b);
    try store.end(reference);
    try store.destroy(owner);
    try testing.expectEqual(@as(i64, 7), (try snapshot.getField(0)).i64);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var store = try memory.Store.init(allocator);
    defer store.deinit();
    const ty: Type = @fromBackingInt(Type.record_base);
    const nested = try Value.create(allocator, ty, &.{.{ .i64 = 7 }});
    defer nested.release(allocator);
    const owner = try store.create(ty, &.{ nested, nested });
    const parent = try store.borrow(owner, 0, 2, .exclusive);
    const child = try store.reborrow(parent, 1, 1, .shared);
    const read = try store.read(child, 0);
    defer read.release(allocator);
    try store.end(child);
    try store.end(parent);
    try store.destroy(owner);
}

test "guest memory allocation failures clean up nested cells and active leases" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "memory registries recycle allocation and lease slots under a fixed live budget" {
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    var store = try memory.Store.init(limiter.allocator());
    defer store.deinit();
    for (0..10000) |i| {
        const owner = try store.create(.i64, &.{.{ .i64 = @intCast(i) }});
        const root = try store.borrow(owner, 0, 1, .exclusive);
        const child = try store.reborrow(root, 0, 1, .shared);
        try number(&store, child, 0, @intCast(i));
        try store.end(child);
        try store.end(root);
        try store.destroy(owner);
    }
    try testing.expectEqual(@as(usize, 1), store.cells.entries.items.len);
    try testing.expectEqual(@as(usize, 2), store.leases.entries.items.len);
    store.deinit();
    try testing.expectEqual(@as(usize, 0), limiter.live);
}

test "failed root and child borrow allocation leaves existing access and lifetimes unchanged" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    var store = try memory.Store.init(failing.allocator());
    defer store.deinit();
    const owner = try store.create(.i64, &.{.{ .i64 = 7 }});
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, store.borrow(owner, 0, 1, .exclusive));
    failing.fail_index = std.math.maxInt(usize);
    try store.writeOwner(owner, 0, .{ .i64 = 8 });
    const root = try store.borrow(owner, 0, 1, .exclusive);
    const other = try store.create(.i64, &.{.{ .i64 = 9 }});
    var fillers: std.ArrayList(memory.Borrow) = .empty;
    defer fillers.deinit(testing.allocator);
    try fillLeaseCapacity(&store, other, &fillers);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, store.reborrow(root, 0, 1, .shared));
    failing.fail_index = std.math.maxInt(usize);
    try store.write(root, 0, .{ .i64 = 10 });
    try number(&store, root, 0, 10);
    try store.end(root);
    for (fillers.items) |filler| try store.end(filler);
    try store.destroy(owner);
    try store.destroy(other);
}

fn fillLeaseCapacity(store: *memory.Store, other: memory.Allocation, fillers: *std.ArrayList(memory.Borrow)) !void {
    while (store.leases.entries.items.len < store.leases.entries.capacity) {
        try fillers.append(testing.allocator, try store.borrow(other, 0, 1, .shared));
    }
}
