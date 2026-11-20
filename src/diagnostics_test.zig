//! Shared diagnostic reporting for compiler fixtures; preserve source failures during test failures.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const print = std.debug.print;
/// Render every compiler diagnostic using a consistent test failure format.
pub fn report(items: []const diagnostic.Diagnostic) void {
    for (items) |item| print("{s}: {s}\n", .{ item.code, item.message });
}
