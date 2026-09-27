//! Native startup ownership through successful and refused argument construction.
const std = @import("std");
extern fn myl_native_argv_verify() c_int;

// spec: RC-ARGV-OWNERSHIP-1
test "RC argv transfers text owners and rolls back before sticky failures or longjmp" {
    try std.testing.expectEqual(@as(c_int, 15), myl_native_argv_verify());
}
