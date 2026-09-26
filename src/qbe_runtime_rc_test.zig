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
    try std.testing.expectEqual(@as(c_int, 20), myl_qbe_rc_frame_verify());
}

extern fn myl_qbe_rc_loan_verify() c_int;

// spec: RC-SEMANTIC-HISTORY-1
// spec: RC-PHYSICAL-RETAIN-1
test "RC loan cleanup clears guards and restores scopes before lifetime release" {
    try std.testing.expectEqual(@as(c_int, 1), myl_qbe_rc_loan_verify());
}

extern fn myl_rc_loan_verify() c_int;

// spec-case: RC-SEMANTIC-HISTORY-1
test "RC loans preserve pinned identity and roll back aggregate lifetime holds" {
    try std.testing.expectEqual(@as(c_int, 9), myl_rc_loan_verify());
}

extern fn myl_rc_history_verify() c_int;

// spec: RC-HISTORY-PUBLISH-1
test "RC semantic publication commits history atomically and preserves pinned snapshot identity" {
    try std.testing.expectEqual(@as(c_int, 35), myl_rc_history_verify());
}
