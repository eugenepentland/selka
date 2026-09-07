//! Owned-scope acquisition, moves, and cleanup tests covering allocator failures and nested resource lifetime transitions.
const value_module = @import("value.zig");
const std = @import("std");
const t = std.testing;
const memory = @import("memory.zig");
const Scope = @import("owned_scope.zig").Scope;
const Value = value_module.Value;
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;

test "buffer transfers consume identities and growth respects active views" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    const original = try store.createWithCapacity(.i64, &.{.{ .i64 = 7 }}, 2);
    const view = try store.borrow(original, 0, 1, .shared);
    try t.expectError(error.BorrowConflict, store.transfer(original));
    try t.expectError(error.BorrowConflict, store.reserve(original, 4));
    try t.expectError(error.BorrowConflict, store.appendWithinCapacity(original, .{ .i64 = 8 }));
    try t.expectError(error.BorrowConflict, store.resizeWithinCapacity(original, 0, .{ .i64 = 0 }));
    try store.end(view);
    const moved = try store.transfer(original);
    try t.expectEqual(original.token.index, moved.token.index);
    try t.expectError(error.InvalidAllocation, store.readOwner(original, 0));
    try t.expectError(error.InvalidAllocation, store.destroy(original));
    try t.expectError(error.InvalidAllocation, store.borrow(original, 0, 0, .shared));
    try t.expectEqual(memory.Growth.allocated, try store.reserve(moved, 4));
    try t.expectEqual(memory.Growth.unchanged, try store.reserve(moved, 2));
    try t.expectEqual(@as(i64, 7), (try store.readOwner(moved, 0)).i64);
    try t.expectError(error.ExpiredBorrow, store.read(view, 0));
    try store.destroy(moved);
    try t.expectEqual(memory.Statistics{ .created = 1, .released = 1, .transfers = 1, .peak_capacity = 4, .peak_allocations = 1 }, store.statistics);
}

test "buffer capacity never exposes uninitialized elements and quotas recover" {
    var store = try memory.Store.initWithLimits(t.allocator, .{ .max_buffer_capacity = 4, .max_total_capacity = 5, .max_allocations = 2 });
    defer store.deinit();
    const a = try store.createWithCapacity(.i64, &.{.{ .i64 = 1 }}, 3);
    try t.expectError(error.Bounds, store.readOwner(a, 1));
    try t.expectError(error.Bounds, store.borrow(a, 0, 2, .shared));
    try t.expectError(error.TypeMismatch, store.appendWithinCapacity(a, .{ .bool = true }));
    try store.appendWithinCapacity(a, .{ .i64 = 2 });
    try store.resizeWithinCapacity(a, 3, .{ .i64 = 9 });
    try t.expectEqual(@as(i64, 9), (try store.readOwner(a, 2)).i64);
    try t.expectError(error.NoCapacity, store.appendWithinCapacity(a, .{ .i64 = 4 }));
    try t.expectError(error.NoCapacity, store.resizeWithinCapacity(a, 4, .{ .i64 = 0 }));
    const b = try store.createWithCapacity(.bool, &.{}, 2);
    try t.expectError(error.CapacityLimit, store.reserve(a, 4));
    try t.expectError(error.CapacityLimit, store.create(.bool, &.{}));
    try t.expectEqual(@as(usize, 3), (try store.bufferInfo(a)).capacity);
    try store.destroy(b);
    try t.expectError(error.CapacityLimit, store.reserve(a, 5));
    _ = try store.reserve(a, 4);
    try store.resizeWithinCapacity(a, 0, .{ .bool = false });
    try t.expectError(error.Bounds, store.readOwner(a, 0));
    try t.expectError(error.TypeMismatch, store.resizeWithinCapacity(a, 1, .{ .bool = false }));
    try store.destroy(a);
    try t.expectEqual(@as(usize, 0), store.statistics.total_capacity);
}

test "partial acquisition rollback releases in reverse order and can retry a blocked owner" {
    var store = try memory.Store.initWithLimits(t.allocator, .{ .max_allocations = 2 });
    defer store.deinit();
    var scope = Scope.init(&store);
    defer scope.deinit();
    const a = try scope.acquire(.i64, &.{.{ .i64 = 1 }}, 1);
    const loan = try store.borrow(a, 0, 1, .shared);
    const b = try scope.acquire(.i64, &.{}, 0);
    try t.expectError(error.CapacityLimit, scope.acquire(.i64, &.{}, 0));
    try t.expectError(error.BorrowConflict, scope.rollback());
    try t.expectError(error.InvalidAllocation, store.bufferInfo(b));
    try t.expectEqual(@as(u64, 1), store.statistics.released);
    try t.expectEqual(@as(usize, 1), scope.owners.items.len);
    try store.end(loan);
    try scope.rollback();
    try scope.rollback();
    scope.deinit();
    try t.expectEqual(@as(u64, 2), store.statistics.released);
    try t.expectEqual(@as(usize, 0), store.statistics.live_allocations);
}

test "scope moves and adoption preserve one cleanup owner" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    var a = Scope.init(&store);
    defer a.deinit();
    var b = Scope.init(&store);
    defer b.deinit();
    const external = try store.create(.i64, &.{.{ .i64 = 42 }});
    const adopted = try a.adopt(external);
    try t.expectError(error.InvalidAllocation, store.bufferInfo(external));
    const moved = try a.moveTo(adopted, &b);
    try t.expectError(error.NotOwned, a.release(adopted));
    try t.expectError(error.InvalidAllocation, store.bufferInfo(adopted));
    const self_moved = try b.moveTo(moved, &b);
    const taken = try b.take(self_moved);
    a.deinit();
    b.deinit();
    try t.expectEqual(@as(i64, 42), (try store.readOwner(taken, 0)).i64);
    try store.destroy(taken);
    try t.expectEqual(memory.Statistics{ .created = 1, .released = 1, .transfers = 4, .peak_capacity = 1, .peak_allocations = 1 }, store.statistics);
}

test "terminal scope cleanup invalidates nested loans without disturbing other owners" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    var scope = Scope.init(&store);
    defer scope.deinit();
    const owner = try scope.acquire(.i64, &.{.{ .i64 = 3 }}, 2);
    const other = try store.create(.i64, &.{.{ .i64 = 5 }});
    const other_view = try store.borrow(other, 0, 1, .shared);
    const root = try store.borrow(owner, 0, 1, .exclusive);
    const child = try store.reborrow(root, 0, 1, .exclusive);
    const leaf = try store.reborrow(child, 0, 1, .shared);
    scope.deinit();
    for ([_]memory.Borrow{ root, child, leaf }) |loan| try t.expectError(error.ExpiredBorrow, store.describe(loan));
    try t.expectEqual(@as(i64, 5), (try store.read(other_view, 0)).i64);
    try store.end(other_view);
    try store.destroy(other);
    const reused = try scope.acquire(.i64, &.{.{ .i64 = 8 }}, 1);
    const live = try store.borrow(reused, 0, 1, .shared);
    try t.expectError(error.ExpiredBorrow, store.describe(leaf));
    try store.end(live);
}

test "failed reserve and destination bookkeeping preserve ownership; reserved operations do not allocate" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var store = try memory.Store.init(failing.allocator());
    defer store.deinit();
    var source = Scope.init(&store);
    defer source.deinit();
    var destination = Scope.init(&store);
    defer destination.deinit();
    const owner = try source.acquire(.i64, &.{.{ .i64 = 1 }}, 3);
    const cleanup = try source.acquire(.bool, &.{.{ .bool = true }}, 1);
    const allocations_before = failing.alloc_index;
    failing.fail_index = allocations_before;
    try t.expectError(error.OutOfMemory, store.reserve(owner, 4));
    try t.expectError(error.OutOfMemory, source.moveTo(owner, &destination));
    try t.expectEqual(@as(usize, 3), (try store.bufferInfo(owner)).capacity);
    try t.expectEqual(@as(usize, 2), source.owners.items.len);
    try t.expectEqual(@as(usize, 0), destination.owners.items.len);
    try store.appendWithinCapacity(owner, .{ .i64 = 2 });
    try store.resizeWithinCapacity(owner, 3, .{ .i64 = 9 });
    const taken = try source.take(owner);
    try store.resizeWithinCapacity(taken, 0, .{ .i64 = 0 });
    try store.destroy(taken);
    try source.rollback();
    try t.expectError(error.InvalidAllocation, store.bufferInfo(cleanup));
    try t.expectEqual(@as(u64, 2), store.statistics.released);
    try t.expectEqual(allocations_before, failing.alloc_index);
}

fn acquisitionScenario(allocator: std.mem.Allocator) !void {
    var store = try memory.Store.init(allocator);
    defer store.deinit();
    var a = Scope.init(&store);
    defer a.deinit();
    var b = Scope.init(&store);
    defer b.deinit();
    const ty: value_module.Type = @fromBackingInt(value_module.Type.record_base);
    const snapshot = try Value.create(allocator, ty, &.{.{ .i64 = 7 }});
    defer snapshot.release(allocator);
    const first = try a.acquire(ty, &.{snapshot}, 2);
    _ = try store.reserve(first, 16);
    _ = try a.acquire(.bool, &.{.{ .bool = true }}, 3);
    const moved = try a.moveTo(first, &b);
    const root = try store.borrow(moved, 0, 1, .exclusive);
    _ = try store.reborrow(root, 0, 1, .shared);
    // Simulates an error with a partially acquired scope and live nested borrows.
}

test "every allocation failure during resource acquisition growth move and unwind releases storage" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), acquisitionScenario, .{});
}

test "ten thousand acquire transfer and cleanup cycles use bounded live storage" {
    var limiter = LimitedLiveAllocator{ .parent = t.allocator, .limit = 16384 };
    defer limiter.deinit();
    {
        var store = try memory.Store.init(limiter.allocator());
        defer store.deinit();
        var a = Scope.init(&store);
        defer a.deinit();
        var b = Scope.init(&store);
        defer b.deinit();
        for (0..10000) |_| {
            const first = try a.acquire(.i64, &.{.{ .i64 = 7 }}, 4);
            const moved = try a.moveTo(first, &b);
            const loan = try store.borrow(moved, 0, 1, .exclusive);
            try store.write(loan, 0, .{ .i64 = 9 });
            try store.end(loan);
            try b.rollback();
        }
        try t.expectEqual(@as(u64, 10000), store.statistics.created);
        try t.expectEqual(store.statistics.created, store.statistics.released);
        try t.expectEqual(@as(usize, 0), store.statistics.live_allocations);
    }
    try t.expectEqual(@as(usize, 0), limiter.live);
}

test "aggregate snapshots survive buffer growth shrink transfer and unwind" {
    const ty: value_module.Type = @fromBackingInt(value_module.Type.record_base);
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    var scope = Scope.init(&store);
    defer scope.deinit();
    const original = try Value.create(t.allocator, ty, &.{.{ .i64 = 42 }});
    const owner = try scope.acquire(ty, &.{original}, 2);
    original.release(t.allocator);
    const snapshot = try store.readOwner(owner, 0);
    defer snapshot.release(t.allocator);
    _ = try store.reserve(owner, 8);
    try store.resizeWithinCapacity(owner, 8, snapshot);
    const moved = try scope.take(owner);
    const adopted = try scope.adopt(moved);
    try store.resizeWithinCapacity(adopted, 1, .{ .bool = false });
    _ = try store.borrow(adopted, 0, 1, .exclusive);
    scope.deinit();
    const field = try snapshot.getField(0);
    defer field.release(t.allocator);
    try t.expectEqual(@as(i64, 42), field.i64);
    try t.expectEqual(@as(u64, 1), store.statistics.released);
}

test "foreign scope moves and borrowed adoption leave original owners usable" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    var other_store = try memory.Store.init(t.allocator);
    defer other_store.deinit();
    var a = Scope.init(&store);
    defer a.deinit();
    var b = Scope.init(&other_store);
    defer b.deinit();
    const owner = try a.acquire(.i64, &.{.{ .i64 = 7 }}, 1);
    try t.expectError(error.ForeignMemory, a.moveTo(owner, &b));
    try t.expectError(error.ForeignMemory, b.adopt(owner));
    const external = try a.take(owner);
    const loan = try store.borrow(external, 0, 1, .shared);
    try t.expectError(error.BorrowConflict, a.adopt(external));
    try t.expectEqual(@as(usize, 0), a.owners.items.len);
    try store.end(loan);
    const adopted = try a.adopt(external);
    try a.release(adopted);
    store.deinit();
    try t.expectError(error.MemoryClosed, a.acquire(.i64, &.{}, 0));
}

test "failed second acquisition releases the first exactly once and successful take survives cleanup" {
    var store = try memory.Store.initWithLimits(t.allocator, .{ .max_allocations = 1 });
    defer store.deinit();
    var scope = Scope.init(&store);
    defer scope.deinit();
    const a = try scope.acquire(.i64, &.{.{ .i64 = 7 }}, 1);
    try t.expectError(error.CapacityLimit, scope.acquire(.bool, &.{.{ .bool = true }}, 1));
    try t.expectEqual(@as(u64, 1), store.statistics.created);
    scope.deinit();
    try t.expectError(error.InvalidAllocation, store.bufferInfo(a));
    try t.expectEqual(@as(u64, 1), store.statistics.released);
    const successful = try scope.acquire(.i64, &.{.{ .i64 = 9 }}, 1);
    const caller_owned = try scope.take(successful);
    scope.deinit();
    try t.expectEqual(@as(u64, 1), store.statistics.released);
    try t.expectEqual(@as(i64, 9), (try store.readOwner(caller_owned, 0)).i64);
    try store.destroy(caller_owned);
    try t.expectEqual(@as(u64, 2), store.statistics.released);
}
