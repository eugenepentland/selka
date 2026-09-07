//! Nested accounting checks distinct parent/child exhaustion and cleanup.
const std = @import("std");
const t = std.testing;
const Memory = @import("compiler.zig").allocation_budget.Memory;
// spec: RUNTIME-BYTES-1
test "child budgets cannot amplify parent authority and release live bytes" {
    var total: Memory = .{ .parent = t.allocator, .limit = 100 };
    var left = total.child(80);
    var right = total.child(200);
    try t.expectEqual(@as(usize, 100), right.limit);
    const a = try left.allocator().alloc(u8, 60);
    try t.expectError(error.OutOfMemory, left.allocator().alloc(u8, 21));
    try t.expectError(error.OutOfMemory, right.allocator().alloc(u8, 41));
    const b = try right.allocator().alloc(u8, 40);
    try t.expectEqual(@as(usize, 100), total.peak);
    try t.expectEqual(@as(usize, 100), total.live);
    right.allocator().free(b);
    left.allocator().free(a);
    try t.expectEqual(@as(usize, 0), total.live);
    try t.expectEqual(@as(usize, 0), left.live);
    try t.expectEqual(@as(usize, 0), right.live);
}
test "nested budget allocator resize and failed growth preserve accounting" {
    var total: Memory = .{ .parent = t.allocator, .limit = 100 };
    var child = total.child(50);
    var grandchild = child.child(100);
    var bytes = try grandchild.allocator().alloc(u8, 30);
    defer grandchild.allocator().free(bytes);
    try t.expectError(error.OutOfMemory, grandchild.allocator().realloc(bytes, 51));
    try t.expectEqual(@as(usize, 30), total.live);
    bytes = try grandchild.allocator().realloc(bytes, 10);
    try t.expectEqual(@as(usize, 10), total.live);
    try t.expectEqual(@as(usize, 30), total.peak);
}

// spec: RUNTIME-CATEGORIES-1
test "backing categories distinguish retained arena chunks from logical live slots" {
    var total: Memory = .{ .parent = t.allocator, .limit = 1_000_000 };
    var backing = total.child(100_000);
    var bookkeeping = total.child(100_000);
    var arena: @import("arena.zig").Arena = undefined;
    try arena.initWithBacking(bookkeeping.allocator(), backing.allocator(), .{});
    defer arena.deinit();
    const store = &arena.store;
    const grant = try store.allocatorCapability();
    const child = try store.beginRegion(grant);
    const nested = try store.beginRegion(child);
    const allocation = try store.createAuthorized(nested, .i64, &.{.{ .i64 = 7 }}, 4);
    _ = try store.reserve(allocation, 8);
    const retained = backing.live;
    try t.expect(retained > 0);
    try t.expect(bookkeeping.live > 0);
    try t.expectEqual(total.live, backing.live + bookkeeping.live);
    try store.destroy(allocation);
    try t.expectEqual(@as(usize, 0), store.statistics.total_capacity);
    try t.expectEqual(@as(usize, 8), store.statistics.peak_capacity);
    try t.expectEqual(retained, backing.live);
    try store.resetRegion(nested);
    try t.expectEqual(@as(usize, 0), backing.live);
    try store.endRegion(nested);
    try store.endRegion(child);
    arena.deinit();
    try t.expectEqual(@as(usize, 0), total.live);
}
test "backing quota rejects acquisition without changing logical accounting" {
    var backing: Memory = .{ .parent = t.allocator, .limit = 0 };
    var arena: @import("arena.zig").Arena = undefined;
    try arena.initWithBacking(t.allocator, backing.allocator(), .{});
    defer arena.deinit();
    const child = try arena.store.beginRegion(try arena.store.allocatorCapability());
    try t.expectError(error.OutOfMemory, arena.store.createAuthorized(child, .i64, &.{}, 4));
    try t.expectEqual(@as(usize, 0), arena.store.statistics.peak_capacity);
    try t.expectEqual(@as(usize, 0), backing.live);
    try arena.store.endRegion(child);
}
