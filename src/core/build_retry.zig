//! A lost demand artifact retries once, discarding diagnostics from partial work.
const std = @import("std");

/// Run a build attempt with demand enabled, then retry eagerly only on cache loss.
pub fn run(context: anytype, report: *std.ArrayList(u8), comptime attempt: anytype) @typeInfo(@TypeOf(attempt)).@"fn".return_type.? {
    const start = report.items.len;
    return attempt(context, true) catch |err| {
        if (err != error.CacheMiss) return err;
        report.shrinkRetainingCapacity(start);
        return attempt(context, false) catch |retry| switch (retry) {
            error.CacheMiss => error.InvalidIr,
            else => retry,
        };
    };
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    report: *std.ArrayList(u8),
    calls: usize = 0,
    fail_eager: bool = false,

    fn attempt(self: *Fixture, lazy: bool) error{ OutOfMemory, CacheMiss, InvalidIr }!u8 {
        self.calls += 1;
        try self.report.appendSlice(self.allocator, if (lazy) "partial" else "complete");
        if (lazy or self.fail_eager) return error.CacheMiss;
        return 0;
    }
};

// spec-case: NEW-CORE-DEMAND-1
test "run retries lost demand artifacts once and discards partial diagnostics" {
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(std.testing.allocator);
    try report.appendSlice(std.testing.allocator, "prefix:");
    var fixture: Fixture = .{ .allocator = std.testing.allocator, .report = &report };
    try std.testing.expectEqual(@as(u8, 0), try run(&fixture, &report, Fixture.attempt));
    try std.testing.expectEqual(@as(usize, 2), fixture.calls);
    try std.testing.expectEqualStrings("prefix:complete", report.items);
}

// spec-case: NEW-CORE-DEMAND-1
test "run stops after a failed eager retry instead of looping on CacheMiss" {
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(std.testing.allocator);
    var fixture: Fixture = .{ .allocator = std.testing.allocator, .report = &report, .fail_eager = true };
    try std.testing.expectError(error.InvalidIr, run(&fixture, &report, Fixture.attempt));
    try std.testing.expectEqual(@as(usize, 2), fixture.calls);
}
