//! Actual RC count traffic, independent of semantic move/copy classifications.
const std = @import("std");
extern fn myl_rc_stats_verify() c_int;

// spec: RC-STATISTICS-1
test "RC counting separates physical traffic holds cloned shells and count refusal" {
    try std.testing.expectEqual(@as(c_int, 4), myl_rc_stats_verify());
}
