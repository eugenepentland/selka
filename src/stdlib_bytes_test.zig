//! The byte-string module's search, split, join, trim and window words.
const std = @import("std");
const fixture = @import("stdlib_fixture.zig");

// spec: STDLIB-BYTES-1
test "standard bytes search split join trim and parse a window" {
    try fixture.run(std.testing.allocator, @embedFile("stdlib/fixtures/bytes_fixture.selka"), 42);
}
