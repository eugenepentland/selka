//! Fatal provider replies release file helper scratch before native unwinding.
const std = @import("std");
extern fn myl_native_file_cleanup_verify() c_int;

// spec-case: IO-12
test "native file provider traps release partial scratch and unpublished results" {
    try std.testing.expectEqual(@as(c_int, 40), myl_native_file_cleanup_verify());
}

fn openCleanup(allocator: std.mem.Allocator, source: []const u8, expected: bool) !void {
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try @import("compiler.zig").Compilation.init(allocator, "file_open_cleanup.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(allocator);
    defer allocator.free(text);
    const abort = std.mem.indexOf(u8, text, "call $myl_rc_construction_abort(l %heap");
    try std.testing.expectEqual(expected, abort != null);
    if (abort) |at| {
        const trap = std.mem.indexOfPos(u8, text, at, "call $myl_qbe_fail_file");
        try std.testing.expect(trap != null);
        try std.testing.expect(std.mem.indexOf(u8, text[0..at], "@fileerror") != null);
    }
}

// spec: RC-FILE-OPEN-TRAP-1
test "RC trapping open releases its unpublished error text before unwinding" {
    try openCleanup(std.testing.allocator,
        \\def main(fs: Filesystem) -> int:
        \\    with open(fs, "absent.txt", "r") as file:
        \\        return len(file.read())
    , true);
    try openCleanup(std.testing.allocator,
        \\def main(fs: Filesystem) -> int:
        \\    with arena():
        \\        with open(fs, "absent.txt", "r") as file:
        \\            return len(file.read())
    , true);
}

// spec-case: RC-FILE-OPEN-TRAP-1
test "RC fallible open preserves the owned error text for Result publication" {
    try openCleanup(std.testing.allocator,
        \\def main(fs: Filesystem) -> Result[int, str]:
        \\    with open(fs, "absent.txt", "r")? as file:
        \\        return Ok(len(file.read()))
    , false);
}
