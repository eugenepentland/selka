//! Standard time arithmetic and reproducible random streams preserve explicit authority.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const values = @import("value_semantics.zig");

// spec: STANDARD-TIME-RANDOM-1
test "standard time random boundary arithmetic and independent deterministic streams" {
    const saved = values.enabled();
    values.setEnabled(true);
    defer values.setEnabled(saved);
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/time_random.my"), 0);
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/time_random.my"), 0);
}

const shared_stream =
    \\module main
    \\import random
    \\
    \\def main() -> int:
    \\    generator = random.seeded(0)
    \\    alias = generator
    \\    first = random.next_word(mut alias)
    \\    second = random.next_word(mut generator)
    \\    if first != 16294208416658607535u64 or second != 7960286522194355700u64:
    \\        return 1
    \\    return 0
;

const failed = "        case Err(_):\n";
const authority =
    "module main\nimport time\nimport random\n" ++
    "def main(clock: Clock, entropy: Entropy) -> int:\n" ++
    "    match time.now(clock):\n" ++
    "        case Ok(instant):\n" ++
    "            if instant.unix_nanoseconds <= 0:\n" ++
    "                return 1\n" ++
    failed ++
    "            return 2\n" ++
    "    match random.from_entropy(entropy):\n" ++
    "        case Ok(generator):\n" ++
    "            if generator.state[0] == 0u64:\n" ++
    "                return 3\n" ++
    failed ++
    "            return 4\n" ++
    "    return 0\n";
// spec: STANDARD-TIME-RANDOM-2
test "standard time random calls reach the machine only through granted capabilities" {
    try fixture.reject(t.allocator, "module main\nimport time\ndef main() -> int:\n    _ = time.now(7)\n    return 0\n");
    try fixture.reject(t.allocator, "module main\nimport random\ndef main() -> int:\n    _ = random.from_entropy(True)\n    return 0\n");
    try fixture.run(t.allocator, authority, 0);
    try fixture.trap(t.allocator, authority, .{ .arguments = &.{"--restrict"} }, "CapabilityUnavailable");
    try fixture.trap(t.allocator, authority, .{ .arguments = &.{ "--restrict", "--allow-clock" } }, "CapabilityUnavailable");
}

const seeded =
    "module main\nimport random\n" ++
    "def main(entropy: Entropy) -> int:\n" ++
    "    match random.from_entropy(entropy):\n" ++
    "        case Ok(sampled):\n" ++
    "            generator = sampled\n" ++
    "            replay = random.from_word(generator.state[0])\n" ++
    "            if random.next_word(mut generator) != random.next_word(mut replay):\n" ++
    "                return 1\n" ++
    "            return 42\n" ++
    failed ++
    "            return 2\n";
// spec: STANDARD-TIME-RANDOM-3
test "standard time random calls preserve effect ceilings and reproducible draws" {
    try fixture.reject(t.allocator, "module main\nimport time\ndef main(c: Clock) -> int effects():\n    _ = time.now(c)\n    return 0\n");
    try fixture.reject(t.allocator, "module main\nimport random\ndef main(c: Entropy) -> int noalloc:\n    _ = random.from_entropy(c)\n    return 0\n");
    try fixture.expect(t.allocator, seeded, .{ .arguments = &.{"--allow-random=42"} }, 42);
    try fixture.expect(t.allocator, seeded, .{}, 42);
}
