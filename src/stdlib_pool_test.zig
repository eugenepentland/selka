//! Standard pools hand out generational handles that never trap when they go stale.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-POOL-1
test "standard pool reuses slots and reports stale handles as absent" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/pool_fixture.selka"), 42);
}

// spec-case: STANDARD-POOL-1
test "standard pool handles stay valid across collection of the released values" {
    try fixture.run(t.allocator, "import strings\n" ++
        "import pool\n" ++
        "func main() -> int:\n" ++
        "    mut seed: str[] = []\n" ++
        "    mut store = pool.create(seed)\n" ++
        "    mut kept = pool.insert(mut store, \"kept\")\n" ++
        "    mut index = 0\n" ++
        "    while index < 200:\n" ++
        "        mut temporary = pool.insert(mut store, \"temporary\")\n" ++
        "        if not pool.remove(mut store, temporary):\n" ++
        "            return 1\n" ++
        "        index += 1\n" ++
        "    if pool.count(store) != 1 or pool.capacity(store) != 2:\n" ++
        "        return 2\n" ++
        "    match pool.get(store, kept):\n" ++
        "        case Some(value):\n" ++
        "            return strings.char_count(value) + 38\n" ++
        "        case None:\n" ++
        "            return 3\n", 42);
}

// spec-case: STANDARD-POOL-1
test "standard accessors copy directly recursive records, so programs that hold them still check" {
    try fixture.run(t.allocator, "import dicts\n" ++
        "import lists\n" ++
        "import pool\n" ++
        "record Node:\n" ++
        "    value: int\n" ++
        "    next: Node?\n" ++
        "func main() -> int:\n" ++
        "    mut index: dict[str, Node] = {\"a\": Node(value=2, next=None)}\n" ++
        "    mut seed: Node[] = [Node(value=1, next=None)]\n" ++
        "    mut store = pool.create(seed)\n" ++
        "    const handles = pool.handles(store)\n" ++
        "    const found = dicts.find(index, \"a\")\n" ++
        "    const last = lists.last(seed)\n" ++
        "    const kept = pool.get(store, handles[0])\n" ++
        "    match found:\n" ++
        "        case Some(two):\n" ++
        "            match last:\n" ++
        "                case Some(one):\n" ++
        "                    match kept:\n" ++
        "                        case Some(three):\n" ++
        "                            return two.value + one.value + three.value + 38\n" ++
        "                        case None:\n" ++
        "                            return 3\n" ++
        "                case None:\n" ++
        "                    return 2\n" ++
        "        case None:\n" ++
        "            return 1\n", 42);
}
