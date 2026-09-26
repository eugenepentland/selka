//! Copied host bridge ownership at callback success and trap boundaries.
const std = @import("std");
extern fn myl_rc_host_verify() c_int;

// spec: RC-HOST-OWNERSHIP-1
test "RC host bytes own copied payloads and node scratch survives callback failure" {
    try std.testing.expectEqual(@as(c_int, 4), myl_rc_host_verify());
}
