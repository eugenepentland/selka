//! Standard ordering is a stable merge over copies, with keys supplied by callbacks.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-SORT-1
test "standard sort orders integers floats and text stably and searches the result" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/sort.my"), 42);
}

// spec-case: STANDARD-SORT-1
test "standard sort keeps its copies rooted under collection stress" {
    try fixture.stress(t.allocator, "module main\nimport sort\n" ++
        "def main() -> int:\n" ++
        "    values: list[int] = []\n" ++
        "    index = 0\n" ++
        "    while index < 64:\n" ++
        "        values.append((index * 37) % 64)\n" ++
        "        index += 1\n" ++
        "    ordered = sort.sort_ints(values)\n" ++
        "    if not sort.is_sorted_ints(ordered) or len(ordered) != 64:\n" ++
        "        return 1\n" ++
        "    match sort.binary_search(ordered, 42):\n" ++
        "        case Some(position):\n" ++
        "            return ordered[position]\n" ++
        "        case None:\n" ++
        "            return 2\n", 42);
}
