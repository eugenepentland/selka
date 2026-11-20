//! Standard time arithmetic and reproducible random streams preserve explicit authority.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-TIME-RANDOM-1
test "standard time random boundary arithmetic and independent deterministic streams" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/time_random.selka"), 0);
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/time_random.selka"), 0);
}

const failed = "        case Err(_):\n";
const authority =
    "import time\n" ++
    "import random\n" ++
    "func main(clock: Clock, entropy: Entropy) -> int:\n" ++
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
    try fixture.reject(t.allocator, "import time\nfunc main() -> int:\n    _ = time.now(7)\n    return 0\n");
    try fixture.reject(t.allocator, "import random\nfunc main() -> int:\n    _ = random.from_entropy(True)\n    return 0\n");
    try fixture.run(t.allocator, authority, 0);
    try fixture.trap(t.allocator, authority, .{ .arguments = &.{"--restrict"} }, "CapabilityUnavailable");
    try fixture.trap(t.allocator, authority, .{ .arguments = &.{ "--restrict", "--allow-clock" } }, "CapabilityUnavailable");
    // STOPWATCH: the Clock starts without `--allow-clock`, and its wall-clock read fails (2) until it is granted.
    try fixture.expect(t.allocator, authority, .{ .arguments = &.{ "--restrict", "--allow-random" } }, 2);
    try fixture.expect(t.allocator, authority, .{ .arguments = &.{ "--restrict", "--allow-random", "--allow-clock" } }, 0);
}

const seeded =
    "import random\n" ++
    "func main(entropy: Entropy) -> int:\n" ++
    "    match random.from_entropy(entropy):\n" ++
    "        case Ok(sampled):\n" ++
    "            mut generator = own sampled\n" ++
    "            mut replay = random.from_word(generator.state[0])\n" ++
    "            if random.next_word(mut generator) != random.next_word(mut replay):\n" ++
    "                return 1\n" ++
    "            return 42\n" ++
    failed ++
    "            return 2\n";
// spec: STANDARD-TIME-RANDOM-3
test "standard time random calls preserve effect ceilings and reproducible draws" {
    try fixture.reject(t.allocator, "import time\nfunc main(c: Clock) -> int effects():\n    _ = time.now(c)\n    return 0\n");
    try fixture.reject(t.allocator, "import random\nfunc main(c: Entropy) -> int effects(random):\n    _ = random.from_entropy(c)\n    return 0\n");
    try fixture.expect(t.allocator, seeded, .{ .arguments = &.{"--allow-random=42"} }, 42);
    try fixture.expect(t.allocator, seeded, .{}, 42);
}
