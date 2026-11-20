//! Exact ownership rejection witnesses for source behavior tests.
const std = @import("std");
const language = @import("selka");
const ownership = @import("single_owner.zig");

const Error = language.diagnostic.Error || error{ TestUnexpectedResult, TestExpectedEqual };

/// Check the same source under ownership and require its stated refusal.
pub fn refuses(gpa: std.mem.Allocator, source: []const u8, code: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "ownership.selka", source);
    const program = try unit.checkLibraryProgram();
    var failure: ownership.Failure = .{};
    ownership.check(a, program, &failure) catch |err| {
        try std.testing.expect(err == error.Rejected);
        try std.testing.expectEqualStrings(code, failure.code);
        return;
    };
    return error.TestUnexpectedResult;
}
