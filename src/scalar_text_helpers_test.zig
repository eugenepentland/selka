//! Wave 3's scalar helper names: which qualified spelling selects which helper,
//! and which argument positions accept an omitted endpoint.
const std = @import("std");
const scalar_text_helpers = @import("scalar_text_helpers.zig");

// spec: TEXT-SCALARS-1
test "a helper is selected by its dotted spelling in both parsed call shapes" {
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .char_count), scalar_text_helpers.named("strings", "char_count"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .char_at), scalar_text_helpers.named("strings", "char_at"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .char_slice), scalar_text_helpers.named("strings", "char_slice"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .char_stride), scalar_text_helpers.named("strings", "char_stride"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .chars), scalar_text_helpers.named("strings", "chars"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .bytes), scalar_text_helpers.named("strings", "bytes"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, .list_stride), scalar_text_helpers.named("lists", "stride"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, null), scalar_text_helpers.named("lists", "contains"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, null), scalar_text_helpers.named("strings", "split"));
    try std.testing.expectEqual(@as(?scalar_text_helpers.ScalarHelper, null), scalar_text_helpers.named("math", "char_count"));
}

// spec: TEXT-SCALARS-1
test "only the slice and stride helpers accept an omitted endpoint" {
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, scalar_text_helpers.optionalPositions(.char_slice));
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, scalar_text_helpers.optionalPositions(.char_stride));
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, scalar_text_helpers.optionalPositions(.list_stride));
    try std.testing.expectEqualSlices(usize, &.{}, scalar_text_helpers.optionalPositions(.char_count));
    try std.testing.expectEqualSlices(usize, &.{}, scalar_text_helpers.optionalPositions(.char_at));
    try std.testing.expectEqualSlices(usize, &.{}, scalar_text_helpers.optionalPositions(.chars));
    try std.testing.expectEqualSlices(usize, &.{}, scalar_text_helpers.optionalPositions(.bytes));
}

// spec: TEXT-SCALARS-1
test "chars and bytes are the only loop sources among the helpers" {
    try std.testing.expect(scalar_text_helpers.loopSource(.chars));
    try std.testing.expect(scalar_text_helpers.loopSource(.bytes));
    try std.testing.expect(!scalar_text_helpers.loopSource(.char_count));
    try std.testing.expect(!scalar_text_helpers.loopSource(.char_at));
    try std.testing.expect(!scalar_text_helpers.loopSource(.char_slice));
    try std.testing.expect(!scalar_text_helpers.loopSource(.char_stride));
    try std.testing.expect(!scalar_text_helpers.loopSource(.list_stride));
}
