//! Production RC allocator and collection ownership invariants.
const std = @import("std");
extern fn myl_rc_collections_verify() c_int;

// spec: RC-STORAGE-1
// spec: RC-COLLECTION-1
// spec: RC-DICTIONARY-1
// spec: RC-VIEWS-1
test "RC production storage and collection ownership" {
    try std.testing.expectEqual(@as(c_int, 13), myl_rc_collections_verify());
}
