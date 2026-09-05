const std = @import("std");
const t = std.testing;
const Arena = @import("arena.zig").Arena;
const memory = @import("memory.zig");
const Value = @import("value.zig").Value;
const Type = @import("value.zig").Type;

test "arena reset rejects nested and empty live borrows without partial cleanup" {
    var arena: Arena = undefined;
    try arena.init(t.allocator, .{});
    defer arena.deinit();
    const first = try arena.store.create(.i64, &.{.{ .i64 = 7 }});
    const second = try arena.store.create(.i64, &.{.{ .i64 = 9 }});
    const root = try arena.store.borrow(first, 0, 1, .exclusive);
    const child = try arena.store.reborrow(root, 1, 0, .shared);
    try t.expectError(error.BorrowConflict, arena.reset(.free_all));
    try t.expectEqual(@as(i64, 9), (try arena.store.readOwner(second, 0)).i64);
    try t.expectEqual(@as(usize, 2), arena.store.statistics.live_allocations);
    try t.expectEqual(@as(usize, 0), (try arena.store.describe(child)).length);
    try arena.store.end(child);
    try t.expectError(error.BorrowConflict, arena.reset(.retain_capacity));
    try arena.store.write(root, 0, .{ .i64 = 11 });
    try arena.store.end(root);
    try t.expect(try arena.reset(.free_all));
    try t.expectError(error.InvalidAllocation, arena.store.info(first));
    try t.expectError(error.InvalidAllocation, arena.store.info(second));
    try t.expectError(error.ExpiredBorrow, arena.store.describe(root));
    try t.expectError(error.ExpiredBorrow, arena.store.describe(child));
}

test "arena reuse preserves allocator authority without reviving allocation or lease IDs" {
    var arena: Arena = undefined;
    try arena.init(t.allocator, .{ .max_allocations = 1, .max_total_capacity = 4 });
    defer arena.deinit();
    const grant = try arena.store.allocatorCapability();
    const original = try arena.store.createWithCapacity(.i64, &.{.{ .i64 = 7 }}, 4);
    const loan = try arena.store.borrow(original, 0, 1, .shared);
    try arena.store.end(loan);
    _ = try arena.reset(.retain_capacity);
    try arena.store.checkAllocator(grant);
    const next = try arena.store.createWithCapacity(.i64, &.{.{ .i64 = 9 }}, 4);
    const new_loan = try arena.store.borrow(next, 0, 1, .shared);
    try t.expectEqual(original.token.index, next.token.index);
    try t.expect(original.token.generation != next.token.generation);
    try t.expectEqual(loan.token.index, new_loan.token.index);
    try t.expectError(error.InvalidAllocation, arena.store.readOwner(original, 0));
    try t.expectError(error.ExpiredBorrow, arena.store.read(loan, 0));
    try t.expectEqual(@as(i64, 9), (try arena.store.read(new_loan, 0)).i64);
    // Terminal cleanup must also work with a live loan.
    arena.deinit();
    arena.deinit();
    try t.expectError(error.MemoryClosed, arena.reset(.free_all));
    try t.expectError(error.InvalidCapability, arena.store.checkAllocator(grant));
}

fn snapshotScenario(allocator: std.mem.Allocator) !void {
    var arena: Arena = undefined;
    try arena.init(allocator, .{});
    defer arena.deinit();
    const record_type: Type = @fromBackingInt(Type.record_base);
    const input = try Value.create(allocator, record_type, &.{.{ .i64 = 23 }});
    defer input.release(allocator);
    const owner = try arena.store.create(record_type, &.{input});
    const snapshot = try arena.store.readOwner(owner, 0);
    defer snapshot.release(allocator);
    _ = try arena.store.reserve(owner, 64);
    try t.expect(try arena.reset(.free_all));
    arena.deinit();
    const field = try snapshot.getField(0);
    defer field.release(allocator);
    try t.expectEqual(@as(i64, 23), field.i64);
}
test "arena reset and destruction preserve retained aggregate snapshots through every allocation failure" {
    try snapshotScenario(t.allocator);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), snapshotScenario, .{});
}

test "preheated arena region cycles reuse backing and registries without host allocation" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var arena: Arena = undefined;
    try arena.init(failing.allocator(), .{});
    defer arena.deinit();
    for (0..20) |iteration| {
        const owner = try arena.store.createWithCapacity(.i64, &.{.{ .i64 = 7 }}, 16);
        const loan = try arena.store.borrow(owner, 0, 1, .exclusive);
        try arena.store.write(loan, 0, .{ .i64 = 9 });
        try arena.store.end(loan);
        try t.expect(try arena.reset(.retain_capacity));
        if (iteration == 1) {
            failing.fail_index = failing.alloc_index;
            failing.resize_fail_index = failing.resize_index;
        }
    }
}

test "repeated arena regions have bounded live storage and independent lifetimes" {
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16384 };
    var arena: Arena = undefined;
    try arena.init(limited.allocator(), .{});
    defer arena.deinit();
    var other: Arena = undefined;
    try other.init(limited.allocator(), .{});
    defer other.deinit();
    const independent = try other.store.create(.i64, &.{.{ .i64 = 41 }});
    const independent_loan = try other.store.borrow(independent, 0, 1, .shared);
    for (0..10000) |_| {
        const a = try arena.store.createWithCapacity(.i64, &.{.{ .i64 = 7 }}, 16);
        const b = try arena.store.create(.i64, &.{.{ .i64 = 9 }});
        _ = try arena.store.reserve(a, 32);
        try t.expectError(error.ForeignMemory, other.store.info(a));
        _ = try arena.reset(.retain_capacity);
        try t.expectError(error.InvalidAllocation, arena.store.info(b));
        try t.expectEqual(@as(usize, 0), arena.store.statistics.total_capacity);
    }
    try t.expectEqual(@as(i64, 41), (try other.store.read(independent_loan, 0)).i64);
    arena.deinit();
    other.deinit();
    try t.expectEqual(@as(usize, 0), limited.live);
}

test "ordinary memory reset does not allocate and preserves closed-store errors" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var store = try memory.Store.init(failing.allocator());
    defer store.deinit();
    const owner = try store.create(.i64, &.{.{ .i64 = 7 }});
    failing.fail_index = failing.alloc_index;
    try store.reset();
    try store.reset();
    try t.expectError(error.InvalidAllocation, store.info(owner));
    try t.expectEqual(@as(u64, 1), store.statistics.released);
    store.deinit();
    try t.expectError(error.MemoryClosed, store.reset());
}
