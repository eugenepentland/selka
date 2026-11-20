//! The release switch of the tests (`-Dtest-release=true`): a release build in a test runs only when the switch is on,
//! and the debug half of the same test runs and asserts either way.
const std = @import("std");
const support = @import("test_support.zig");
const build = @import("build.zig");

const program =
    \\func main(out: Stream) -> int:
    \\    mut total = 0
    \\    for i in range(4):
    \\        total = total + i
    \\    print(out, total)
    \\    return 0
    \\
;

test "the release switch skips a release build unless -Dtest-release=true runs it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    // The debug half: an ordinary debug build runs and asserts whether or not the switch is on.
    var debug_module = try support.buildSource(a, program, &refusal);
    const debug = try support.runOwned(a, &debug_module, .{});
    try std.testing.expectEqual(@as(u8, 0), debug.status);
    try std.testing.expectEqualStrings("6\n", debug.stdout);
    // The release half: skipped (reported as skipped, not passed) unless -Dtest-release=true; with it, the release build runs.
    try support.requireRelease();
    try std.testing.expect(support.releaseEnabled());
    var release_module = try support.buildSource(a, program, &refusal);
    const release = try support.runOwned(a, &release_module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 0), release.status);
    try std.testing.expectEqualStrings("6\n", release.stdout);
}

test "a command line without --release is never skipped, and one with it follows the switch" {
    try support.requireReleaseArgs(&.{ "--counters", "--verify-facts" });
    const with_release = support.requireReleaseArgs(&.{ "--counters", "--release" });
    try std.testing.expectEqual(!support.releaseEnabled(), std.meta.isError(with_release));
}
