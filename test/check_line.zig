//! The status line a successful `selka check` writes to standard error (CHECK-SUCCESS-LINE-1).
const std = @import("std");
const testing = std.testing;

/// Expect `stderr` to hold exactly one line, `check: ok (N modules, M cached)`, and nothing else.
pub fn expectPassed(stderr: []const u8) !void {
    try testing.expect(std.mem.startsWith(u8, stderr, "check: ok"));
    try testing.expect(std.mem.endsWith(u8, stderr, ")\n") or std.mem.eql(u8, stderr, "check: ok\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, stderr, "\n"));
}
