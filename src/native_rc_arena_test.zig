//! Counted arena ownership, charged reuse and callback cleanup evidence.
const std = @import("std");
extern fn myl_native_rc_arena_verify() c_int;

// spec: RC-ARENA-1
test "RC arenas release logical edges before chunks and charge retained storage" {
    try std.testing.expectEqual(@as(c_int, 6), myl_native_rc_arena_verify());
}
