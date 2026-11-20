//! The fixed-width byte reads: the `__read_*` spellings the `bytes.read_*` functions call are reserved for
//! standard-library sources, and float reads have no big-endian form. (Accepted reads import `bytes`, which a unit
//! compilation cannot do; tests/lang/byte_reads.selka and test/integration.zig cover them.)
const std = @import("std");
const t = std.testing;

/// Check a program that must be rejected with `code` as its first diagnostic. The programs import `strings` for
/// `strings.encode` (W13-S5), so they are checked as embedded projects.
fn expectRejected(text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try @import("stdlib_fixture.zig").rejectsWith(arena.allocator(), text, code);
}

test "the compiler-internal byte read spelling is reserved for standard-library sources" {
    try expectRejected(
        \\import strings
        \\
        \\func main() -> int:
        \\    const data = strings.encode("ABCD")
        \\    return int(__read_u32_be(data, 0))
    , "E_INTERNAL_NAME");
    try expectRejected(
        \\import strings
        \\
        \\func main() -> int:
        \\    const data = strings.encode("ABCD")
        \\    return int(__read_f64_le(data, 0))
    , "E_INTERNAL_NAME");
}
