//! Standard pools hand out generational handles that never trap when they go stale.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-POOL-1
test "standard pool reuses slots and reports stale handles as absent" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/pool.my"), 42);
}

// spec-case: STANDARD-POOL-1
test "standard pool handles stay valid across collection of the released values" {
    try fixture.run(t.allocator, "module main\nimport pool\n" ++
        "def main() -> int:\n" ++
        "    seed: list[str] = []\n" ++
        "    store = pool.create(seed)\n" ++
        "    kept = pool.insert(mut store, \"kept\")\n" ++
        "    index = 0\n" ++
        "    while index < 200:\n" ++
        "        temporary = pool.insert(mut store, \"temporary\")\n" ++
        "        if not pool.remove(mut store, temporary):\n" ++
        "            return 1\n" ++
        "        index += 1\n" ++
        "    if pool.count(store) != 1 or pool.capacity(store) != 2:\n" ++
        "        return 2\n" ++
        "    match pool.get(store, kept):\n" ++
        "        case Some(value):\n" ++
        "            return len(value) + 38\n" ++
        "        case None:\n" ++
        "            return 3\n", 42);
}
