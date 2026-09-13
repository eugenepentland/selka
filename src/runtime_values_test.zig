//! Boundary tests for external scalar parsing and runtime value construction.
const std = @import("std");
const values = @import("value.zig");
const t = std.testing;

test "decimal boundary rejects InvalidInteger spellings and IntegerOutOfRange values" {
    for ([_][]const u8{ "", "-", "-0", "01", "+1", " 1", "1 ", "1u8", "1.0", "1e2", "184467440737095516150" }) |text| {
        try t.expectError(error.InvalidInteger, values.Type.i64.parseDecimal(text));
    }
    try t.expectError(error.InvalidInteger, values.Type.bool.parseDecimal("1"));
    try t.expectError(error.IntegerOutOfRange, values.Type.u8.parseDecimal("256"));
    try t.expectError(error.IntegerOutOfRange, values.Type.u8.parseDecimal("-1"));
    try t.expectError(error.IntegerOutOfRange, values.Type.i8.parseDecimal("-129"));
    try t.expectEqual(@as(i128, -128), try values.Type.i8.parseDecimal("-128"));
    try t.expectEqual(@as(i128, std.math.maxInt(u64)), try values.Type.u64.parseDecimal("18446744073709551615"));
}

test "scalar aggregate constructors return InvalidAggregateType before allocating" {
    try t.expectError(error.InvalidAggregateType, values.Value.create(t.allocator, .i64, &.{}));
    try t.expectError(error.InvalidAggregateType, values.Value.createVariant(t.allocator, .bool, 0, null));
    try t.expectError(error.InvalidAggregateType, values.Value.createOrdered(t.allocator, .u8, &.{}, &.{}));
}
