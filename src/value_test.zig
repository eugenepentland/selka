//! Storage experiments precede record syntax so lifetime failures stay isolated.
const std = @import("std");
const testing = std.testing;
const values = @import("value.zig");
const Value = values.Value;
const record_type: values.Type = @fromBackingInt(values.Type.record_base);
test "nested immutable fields remain alive independently of their containing value" {
    const inner = try Value.create(testing.allocator, record_type, &.{.{ .i64 = 7 }});
    defer inner.release(testing.allocator);
    const outer = try Value.create(testing.allocator, @fromBackingInt(values.Type.record_base + 1), &.{ inner, inner, .{ .bool = true } });
    const copy = try outer.getField(1);
    defer copy.release(testing.allocator);
    outer.release(testing.allocator);
    try testing.expectEqual(@as(i64, 7), (try copy.getField(0)).i64);
    try testing.expectEqual(record_type, copy.typeOf());
}

test "deep aggregate release is iterative and needs no additional allocations" {
    var root: Value = .{ .i64 = 7 };
    defer root.release(testing.allocator);
    for (0..20_000) |_| {
        const next = try Value.create(testing.allocator, record_type, &.{root});
        root.release(testing.allocator);
        root = next;
    }
    // The final defer frees the entire chain; guest depth does not recurse here.
}

test "repeated record allocation retains bounded live storage" {
    // 10,000 overwrites at one local slot. A fixed live-memory allocator would
    // be obscured by allocation strategy, so cap outstanding bytes directly.
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    defer limiter.deinit();
    var live: Value = .{ .i64 = 0 };
    defer live.release(limiter.allocator());
    for (0..10_000) |i| {
        const next = try Value.create(limiter.allocator(), record_type, &.{.{ .i64 = @intCast(i) }});
        live.release(limiter.allocator());
        live = next;
    }
    try testing.expectEqual(@as(i64, 9999), (try live.getField(0)).i64);
}

const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;

test "aggregate construction rejects scalar type identity" {
    try testing.expectError(error.InvalidAggregateType, Value.create(testing.allocator, .i64, &.{}));
}
test "data graph validation rejects a nominal identity outside the schema table" {
    const unknown: values.Type = @fromBackingInt(values.Type.record_base);
    try testing.expectError(error.InvalidDataType, @import("data_type.zig").check(testing.allocator, &.{}, unknown, true));
}
