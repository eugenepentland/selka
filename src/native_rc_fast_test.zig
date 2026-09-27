//! RC runtime internal fast paths: probe-based metadata, variant flat plans,
//! immediate edge-free retirement, recycled journal nodes and heap teardown.
const std = @import("std");
extern fn myl_rc_fast_verify() c_int;

// spec: RC-FLAT-VARIANT-1
// spec: RC-METADATA-MAP-1
// spec: RC-LEAF-RETIRE-1
// spec: RC-STORAGE-TEARDOWN-1
// spec: RC-SLAB-POOLS-1
// spec: RC-SCOPE-SPARE-1
// spec: RC-CHECKED-1
// spec: RC-SHALLOW-WALK-1
// spec: RC-LIST-DIRECT-APPEND-1
// spec: RC-RAW-BLOCK-1
// spec: RC-CLONE-SPAN-1
// spec: RC-SEMANTIC-FLAT-1
// spec: RC-FLAT-TAKE-1
// spec: RC-OPAQUE-EXTEND-1
// spec: RC-DRAIN-FLAT-1
// spec: RC-PLAIN-TYPE-1
test "RC runtime fast paths keep ownership, accounting and teardown exact" {
    try std.testing.expectEqual(@as(c_int, 18), myl_rc_fast_verify());
}
