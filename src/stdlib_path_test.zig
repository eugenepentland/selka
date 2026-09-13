//! Standard path operations are pure text algebra and never touch a filesystem.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-PATH-1
test "standard path joins splits and normalizes without filesystem authority" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/path.my"), 42);
}

// spec-case: STANDARD-PATH-1
test "standard path helpers need no capability and stay inside a noio ceiling" {
    try fixture.run(t.allocator, "module main\nimport path\n" ++
        "def cleaned(value: str) -> str noio:\n" ++
        "    return path.normalize(value)\n" ++
        "def main() -> int:\n" ++
        "    if cleaned(\"/a/b/../c//\") != \"/a/c\":\n" ++
        "        return 1\n" ++
        "    return len(cleaned(\"/usr/local/lib/mylang\")) + 21\n", 42);
}
