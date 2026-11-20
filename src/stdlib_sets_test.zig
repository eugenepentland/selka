//! The set module's nine operations keep set semantics over guest values.
const std = @import("std");
const fixture = @import("stdlib_fixture.zig");

// spec: STDLIB-SETS-1
test "standard sets add discard and combine without changing set semantics" {
    try fixture.run(std.testing.allocator, @embedFile("stdlib/fixtures/sets_fixture.selka"), 42);
}

// W3 step 2, move 1: the combining operations copy a kept managed element into the result (copy on insert), so a set of
// text intersects, subtracts and symmetric-subtracts instead of being refused at the call (`E_SINGLE_OWNER_OVERLAP`).
test "W3 the set operations of two text sets keep their own copy of each element" {
    try fixture.run(std.testing.allocator,
        \\import sets
        \\
        \\
        \\func main() -> int:
        \\    mut left: set[str] = set()
        \\    sets.add(mut left, "a")
        \\    sets.add(mut left, "b")
        \\    mut right: set[str] = set()
        \\    sets.add(mut right, "b")
        \\    const both = sets.intersection(left, right)
        \\    const only = sets.difference(left, right)
        \\    const either = sets.symmetric_difference(left, right)
        \\    return len(both) * 100 + len(only) * 10 + len(either) + len(left)
        \\
    , 113);
}
