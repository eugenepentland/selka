//! List library words preserve value semantics and total repetition counts.
const std = @import("std");
const fixture = @import("stdlib_fixture.zig");

// spec: STDLIB-LISTS-1
test "standard lists fill independent values scan equality and return the last option" {
    try fixture.run(std.testing.allocator, @embedFile("stdlib/fixtures/list_words.selka"), 42);
}
