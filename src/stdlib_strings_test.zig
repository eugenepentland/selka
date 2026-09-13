//! Standard text helpers cover the operations the builtin str type does not provide.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-STRINGS-1
test "standard strings classify search trim pad and convert text at signed boundaries" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/strings.my"), 42);
}

// spec-case: STANDARD-STRINGS-1
test "standard string results survive collection at every managed allocation" {
    try fixture.stress(t.allocator, "module main\nimport strings\n" ++
        "def main() -> int:\n" ++
        "    total = 0\n" ++
        "    for line in strings.lines(\"a\\r\\nbb\\nccc\"):\n" ++
        "        total += len(strings.strip(line))\n" ++
        "    match strings.pad_left(strings.upper(\"ff\"), 4, \"0\"):\n" ++
        "        case Ok(text):\n" ++
        "            if text != \"00FF\":\n" ++
        "                return 1\n" ++
        "        case Err(_):\n" ++
        "            return 2\n" ++
        "    return total + 36\n", 42);
}
