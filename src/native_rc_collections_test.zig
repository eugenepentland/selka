//! Production RC allocator and collection ownership invariants.
const std = @import("std");
extern fn myl_rc_collections_verify() c_int;
extern fn myl_rc_registered_release_verify() c_int;

// spec: RC-STORAGE-1
// spec: RC-COLLECTION-1
// spec: RC-DICTIONARY-1
// spec: RC-VIEWS-1
// spec-case: RC-TRANSFER-1
// spec: RC-FLAT-SINGLE-DESTRUCTION-1
// spec: RC-PLAIN-REPLACE-1
// spec: RC-PLAIN-RETAIN-1
// spec-case: RC-PLAIN-APPEND-1
// spec-case: RC-PLAIN-POP-1
// spec: RC-PLAIN-READY-INLINE-1
// spec: RC-DICTIONARY-WORD-1
test "RC production storage and collection ownership" {
    try std.testing.expectEqual(@as(c_int, 47), myl_rc_collections_verify());
}

// spec: RC-REGISTERED-RELEASE-1
test "RC registered collection release preserves source admission" {
    try std.testing.expectEqual(@as(c_int, 13), myl_rc_registered_release_verify());
}
