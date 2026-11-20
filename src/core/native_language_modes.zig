//! Run a complete guest suite through the required native ownership modes.
const std = @import("std");
const report = std.debug.print;
const options = @import("core_test_options");
const support = @import("test_support.zig");
const Error = std.mem.Allocator.Error || std.process.RunError ||
    std.process.Environ.CreateMapError || std.Io.Dir.RealPathFileAllocError ||
    std.json.ParseError(std.json.Scanner) || error{ TestUnexpectedResult, TestExpectedEqual, SkipZigTest };

/// One guest file's exact expected result and failure context.
pub const Suite = struct { path: []const u8, passed: i64, label: []const u8 };

fn runMode(a: std.mem.Allocator, environment: *std.process.Environ.Map, cache: []const u8, suite: Suite, flags: []const []const u8) !void {
    const argv = try std.mem.concat(a, []const u8, &.{
        &.{ options.corePath(), "test", suite.path, "--force", "--json", "--jobs", "1", "--max-memory", "0", "--cache-dir", cache }, flags,
    });
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = environment });
    if (ran.term != .exited or ran.term.exited != 0) report("{s}: {s}{s}\n", .{ suite.label, ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    const result = try std.json.parseFromSliceLeaky(std.json.Value, a, ran.stdout, .{});
    try std.testing.expectEqual(suite.passed, result.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), result.object.get("failed").?.integer);
    try std.testing.expectEqual(@as(i64, 0), result.object.get("unsupported").?.integer);
    try std.testing.expectEqualStrings("", ran.stderr);
}

/// Force debug, verified release and AddressSanitizer release with leak checking,
/// using a private cache shared across these three modes of the same guest file.
pub fn run(backing: std.mem.Allocator, suite: Suite) Error!usize {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const cache = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    try runMode(a, &environment, cache, suite, &.{});
    // The release and sanitized release runs are skipped while -Dtest-release is off; the debug run above has run and asserted.
    try support.requireRelease();
    try runMode(a, &environment, cache, suite, &.{ "--release", "--verify-facts" });
    try environment.put("SELKA_CORE_SANITIZE", "address");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    try runMode(a, &environment, cache, suite, &.{ "--release", "--verify-facts" });
    return 3;
}
