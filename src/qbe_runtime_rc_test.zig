//! Native RC startup registration and status-to-trap adapter evidence.
const std = @import("std");
extern fn myl_qbe_rc_contract_verify() c_int;
extern fn myl_qbe_rc_frame_verify() c_int;

// spec: RC-STARTUP-1
test "RC startup registers metadata and preserves count region and budget failures" {
    try std.testing.expectEqual(@as(c_int, 5), myl_qbe_rc_contract_verify());
}

// spec: RC-FRAME-1
test "RC frame unwind restores scopes before releasing guarded owners and resources" {
    try std.testing.expectEqual(@as(c_int, 6), myl_qbe_rc_frame_verify());
}
