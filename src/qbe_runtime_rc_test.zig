//! Native RC startup registration and status-to-trap adapter evidence.
const std = @import("std");
extern fn myl_qbe_rc_contract_verify() c_int;

// spec: RC-STARTUP-1
test "RC startup registers metadata and preserves count region and budget failures" {
    try std.testing.expectEqual(@as(c_int, 5), myl_qbe_rc_contract_verify());
}
