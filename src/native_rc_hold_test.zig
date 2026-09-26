//! Live dictionary view holds preserve identity independently of ordinary owners.
const std = @import("std");
extern fn myl_rc_hold_verify() c_int;

// spec: RC-HOLD-VIEW-1
test "RC held edges retain live identity and roll back count and escape failures" {
    try std.testing.expectEqual(@as(c_int, 12), myl_rc_hold_verify());
}
