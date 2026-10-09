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
