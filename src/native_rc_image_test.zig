//! Execute the native registration image admission and metadata contracts.
const std = @import("std");
extern fn myl_rc_image_verify() c_int;

// spec: RC-STARTUP-IMAGE-1
test "RC image registration preserves private state, plans and rollback" {
    try std.testing.expectEqual(@as(c_int, 15), myl_rc_image_verify());
}
