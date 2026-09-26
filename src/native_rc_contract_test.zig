//! Executable RC-v1 C ABI and allocation-free teardown contract evidence.
const std = @import("std");
extern fn myl_rc_contract_verify() c_int;

// spec: RC-LAYOUT-1
// spec: RC-COUNTS-1
// spec: RC-REGISTER-1
// spec: RC-RELEASE-1
// spec: RC-TRANSFER-1
// spec: RC-SCOPES-1
test "RC contract layout counts reservation failure and iterative teardown" {
    try std.testing.expectEqual(@as(c_int, 21), myl_rc_contract_verify());
}
