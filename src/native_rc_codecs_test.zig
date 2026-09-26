//! Production codec ownership and cleanup across guest callback failure.
const std = @import("std");
extern fn myl_rc_codecs_verify() c_int;

// spec: RC-CODEC-OWNERSHIP-1
test "RC codecs retire temporary values and copied arguments on success rejection and guest traps" {
    try std.testing.expectEqual(@as(c_int, 11), myl_rc_codecs_verify());
}
