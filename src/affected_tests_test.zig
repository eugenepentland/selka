//! Boundary coverage for the `mylang test --affected` derivation.
const std = @import("std");
const language = @import("compiler.zig");

// spec-case: AFFECTED-TEST-1
test "affected selection rejects an entry that is not a mylang source" {
    const discovered = [_][]const u8{};
    const request: language.affected_tests.Request = .{
        .memory = std.testing.allocator,
        .io = std.testing.io,
        .load_root = ".",
        .git_root = ".",
        .entry = "main.txt",
        .reference = "HEAD",
        .discovered = &discovered,
    };
    try std.testing.expectError(error.InvalidEntry, language.affected_tests.select(request));
}
