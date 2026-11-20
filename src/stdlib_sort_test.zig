//! Standard ordering is a stable merge over copies, with keys supplied by callbacks.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-SORT-1
test "standard sort orders integers floats and text stably and searches the result" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/sort_fixture.selka"), 42);
}

// spec-case: STANDARD-SORT-1
test "standard sort keeps its copies rooted under collection stress" {
    try fixture.run(t.allocator, "import sort\n" ++
        "func main() -> int:\n" ++
        "    mut values: int[] = []\n" ++
        "    mut index = 0\n" ++
        "    while index < 64:\n" ++
        "        append(mut values, (index * 37) % 64)\n" ++
        "        index += 1\n" ++
        "    mut ordered = sort.sort_ints(values)\n" ++
        "    if not sort.is_sorted_ints(ordered) or len(ordered) != 64:\n" ++
        "        return 1\n" ++
        "    match sort.binary_search(ordered, 42):\n" ++
        "        case Some(position):\n" ++
        "            return ordered[position]\n" ++
        "        case None:\n" ++
        "            return 2\n", 42);
}

// spec-case: STANDARD-SORT-KEY-1
test "keyed sort computes each key once in input order" {
    // Element 1 overflows and element 2 divides by zero: sort_by_key forwards
    // to the keyed sort, which asks for keys in input order, so the first
    // trapping element in the list decides the trap.
    // migrate-embedded: skip preserved original effect retirement witness
    const original_0 = "import sort\n" ++
        "func fragile(value: int) -> int effects():\n" ++
        "    if value == 1:\n" ++
        "        return 9223372036854775807 + value\n" ++
        "    if value == 2:\n" ++
        "        return 10 // (value - 2)\n" ++
        "    return value\n" ++
        "func main() -> int:\n" ++
        "    mut ordered = sort.sort_by_key([0, 1, 2, 3, 4, 5, 6], fragile)\n" ++
        "    return ordered[0]\n";
    try expectEffectsRemoved(t.allocator, original_0);
    try fixture.trap(t.allocator, "import sort\n" ++
        "func fragile(value: int) -> int:\n" ++
        "    if value == 1:\n" ++
        "        return 9223372036854775807 + value\n" ++
        "    if value == 2:\n" ++
        "        return 10 // (value - 2)\n" ++
        "    return value\n" ++
        "func main() -> int:\n" ++
        "    mut ordered = sort.sort_by_key([0, 1, 2, 3, 4, 5, 6], fragile)\n" ++
        "    return ordered[0]\n", .{}, "R_OVERFLOW");
    // migrate-embedded: skip preserved original effect retirement witness
    const original_1 = "import sort\n" ++
        "func fragile(value: int) -> int effects():\n" ++
        "    if value == 0:\n" ++
        "        return 10 // value\n" ++
        "    if value == 1:\n" ++
        "        return 9223372036854775807 + value\n" ++
        "    return value\n" ++
        "func main() -> int:\n" ++
        "    mut ordered = sort.sort_by_key([1, 0, 2, 3], fragile)\n" ++
        "    return ordered[0]\n";
    try expectEffectsRemoved(t.allocator, original_1);
    try fixture.trap(t.allocator, "import sort\n" ++
        "func fragile(value: int) -> int:\n" ++
        "    if value == 0:\n" ++
        "        return 10 // value\n" ++
        "    if value == 1:\n" ++
        "        return 9223372036854775807 + value\n" ++
        "    return value\n" ++
        "func main() -> int:\n" ++
        "    mut ordered = sort.sort_by_key([1, 0, 2, 3], fragile)\n" ++
        "    return ordered[0]\n", .{}, "R_OVERFLOW");
}

// spec-case: STANDARD-SORT-KEY-1
test "keyed sort keeps records and their text rooted under collection stress" {
    try fixture.run(t.allocator, "import sort\n" ++
        "record Entry:\n" ++
        "    name: str\n" ++
        "    score: int\n" ++
        "func by_score(entry: Entry) -> int:\n" ++
        "    return entry.score\n" ++
        "func main() -> int:\n" ++
        "    mut entries: Entry[] = []\n" ++
        "    mut index = 0\n" ++
        "    while index < 300:\n" ++
        "        append(mut entries, Entry(name=chr(19968 + index), score=(index * 37) % 11))\n" ++
        "        index += 1\n" ++
        "    mut ranked = sort.sort_by_key(entries, by_score)\n" ++
        "    mut at = 1\n" ++
        "    while at < 300:\n" ++
        "        mut earlier = ord(ranked[at - 1].name) - 19968\n" ++
        "        mut later = ord(ranked[at].name) - 19968\n" ++
        "        if ranked[at - 1].score > ranked[at].score:\n" ++
        "            return 1\n" ++
        "        if ranked[at - 1].score == ranked[at].score and earlier >= later:\n" ++
        "            return 2\n" ++
        "        if (earlier * 37) % 11 != ranked[at - 1].score:\n" ++
        "            return 3\n" ++
        "        at += 1\n" ++
        "    return 42\n", 42);
}

// spec-case: STANDARD-SORT-KEY-1
test "comparison sort moves records and their text rooted under collection stress" {
    try fixture.run(t.allocator, "import sort\n" ++
        "record Entry:\n" ++
        "    name: str\n" ++
        "    score: int\n" ++
        "func by_score(first: Entry, second: Entry, falling: bool) -> int:\n" ++
        "    if falling:\n" ++
        "        return second.score - first.score\n" ++
        "    return first.score - second.score\n" ++
        "func main() -> int:\n" ++
        "    mut entries: Entry[] = []\n" ++
        "    mut index = 0\n" ++
        "    while index < 300:\n" ++
        "        append(mut entries, Entry(name=chr(19968 + index), score=(index * 37) % 11))\n" ++
        "        index += 1\n" ++
        "    sort.sort_by_compare_with(mut entries, by_score, True)\n" ++
        "    mut at = 1\n" ++
        "    while at < 300:\n" ++
        "        mut earlier = ord(entries[at - 1].name) - 19968\n" ++
        "        mut later = ord(entries[at].name) - 19968\n" ++
        "        if entries[at - 1].score < entries[at].score:\n" ++
        "            return 1\n" ++
        "        if entries[at - 1].score == entries[at].score and earlier >= later:\n" ++
        "            return 2\n" ++
        "        if (earlier * 37) % 11 != entries[at - 1].score:\n" ++
        "            return 3\n" ++
        "        at += 1\n" ++
        "    return 42\n", 42);
}

fn expectEffectsRemoved(allocator: std.mem.Allocator, source: []const u8) !void {
    const language = @import("compiler.zig");
    var unit = try language.Compilation.init(allocator, "sort_effects.selka", source);
    defer unit.deinit();
    try t.expectError(error.SourceError, unit.formatModule(allocator));
    try t.expect(unit.diagnostics.items.len > 0);
    try t.expectEqualStrings("E_EFFECTS_REMOVED", unit.diagnostics.items[0].code);
}
