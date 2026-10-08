//! Standard base64 and hexadecimal transcoding accept only canonical encodings.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-CODECS-1
test "standard base64 and hex match their vectors and reject noncanonical input" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/codecs.my"), 42);
}

// spec-case: STANDARD-CODECS-1
test "standard base64 round-trips every byte value under collection stress" {
    try fixture.run(t.allocator, "module main\nimport base64\n" ++
        "def main() -> int:\n" ++
        "    octets: list[int] = []\n" ++
        "    value = 0\n" ++
        "    while value < 256:\n" ++
        "        octets.append(value)\n" ++
        "        value += 1\n" ++
        "    raw = bytes(octets)\n" ++
        "    encoded = base64.b64encode(raw)\n" ++
        "    if len(encoded) != 344:\n" ++
        "        return 1\n" ++
        "    match base64.b64decode(encoded):\n" ++
        "        case Ok(decoded):\n" ++
        "            if decoded != raw:\n" ++
        "                return 2\n" ++
        "            return len(decoded) - 214\n" ++
        "        case Err(_):\n" ++
        "            return 3\n", 42);
}
