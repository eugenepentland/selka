//! Fatal provider replies release file helper scratch before native unwinding.
const std = @import("std");
extern fn myl_native_file_cleanup_verify() c_int;

// spec-case: IO-12
test "native file provider traps release partial scratch and unpublished results" {
    try std.testing.expectEqual(@as(c_int, 40), myl_native_file_cleanup_verify());
}
