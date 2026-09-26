//! Compact journal indices retain physical obligations and exact cleanup prefixes.
const std = @import("std");
const journal = @import("qbe_rc_journal.zig");
const plan = @import("rc_plan.zig");
const shape = @import("rc_shape.zig");
const t = std.testing;

fn storage(facts: shape.Shape) plan.Storage {
    // Only finalized shape facts are inputs to this emission-only mapping.
    return .{ .id = @fromBackingInt(0), .ty = .unit, .shape = facts, .initial = .plain, .guard = null };
}

// spec: RC-COMPACT-JOURNAL-1
test "RC compact journal retains owner unique and scratch positions in logical order" {
    const locals = [_]plan.Storage{ storage(.{}), storage(.{ .counted = true }), storage(.{ .unique_drop = true }), storage(.{}) };
    const operands = [_]journal.Operand{ .{}, .{ .may_own = true } };
    const layout = try journal.build(t.allocator, &locals, &operands);
    defer t.allocator.free(layout.prefix);
    try t.expectEqualSlices(usize, &.{ 0, 0, 1, 2, 2, 2, 3, 4, 5 }, layout.prefix);
    try t.expectEqual(@as(usize, 5), layout.count());
    try t.expectEqual(@as(usize, 2), try layout.watermark(4));
    try t.expectEqual(@as(usize, 2), try layout.require(5));
    try t.expectEqual(@as(usize, 3), try layout.require(6));
    try t.expectEqual(@as(usize, 4), try layout.require(7));
    try t.expectError(error.InternalError, layout.require(0));
    try t.expectError(error.InternalError, layout.require(4));
    try t.expectError(error.InternalError, layout.require(8));
}

// spec-case: RC-COMPACT-JOURNAL-1
test "RC compact journal keeps both scratch entries when all typed positions are plain" {
    const locals = [_]plan.Storage{storage(.{})};
    const operands = [_]journal.Operand{.{}};
    const layout = try journal.build(t.allocator, &locals, &operands);
    defer t.allocator.free(layout.prefix);
    try t.expectEqual(@as(usize, 2), layout.count());
    try t.expectEqual(@as(usize, 0), try layout.watermark(1));
    try t.expectEqual(@as(usize, 0), try layout.require(2));
    try t.expectEqual(@as(usize, 1), try layout.require(3));
    try t.expectError(error.InternalError, layout.watermark(5));
}
