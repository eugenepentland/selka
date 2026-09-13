//! Standard math covers binary64 classification, rounding, roots and integer helpers.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-MATH-1
test "standard math roots rounding classification and checked integer helpers" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/math.my"), 42);
}

// spec-case: STANDARD-MATH-1
test "standard math results keep the must-handle obligation of a checked failure" {
    try fixture.reject(t.allocator, "module main\nimport math\ndef main() -> int:\n    math.abs(0 - 1)\n    return 0\n");
    try fixture.reject(t.allocator, "module main\nimport math\ndef main() -> int:\n    return math.sqrt(1.0)\n");
}

// spec: STANDARD-INTEGER-EXTREMA-1
test "standard integer extrema and clamp cover every width and full signed range" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/integer_extrema.my"), 42);
}
