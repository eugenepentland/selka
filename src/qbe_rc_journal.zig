//! Dense emission indices for positions that can hold a physical RC obligation.
const std = @import("std");
const plan = @import("rc_plan.zig");

/// Stable operand storage and the union of its reachable cleanup obligations.
pub const Operand = struct { bytes: u64 = 8, may_own: bool = false };
/// A prefix count preserves logical cleanup order while omitting plain positions.
pub const Layout = struct {
    prefix: []const usize,

    /// Resolve a retained position; an omitted position has no physical slot.
    pub fn slot(self: Layout, logical: usize) error{InternalError}!?usize {
        if (logical >= self.prefix.len - 1) return error.InternalError;
        return if (self.prefix[logical + 1] == self.prefix[logical]) null else self.prefix[logical];
    }

    /// Require an actual entry rather than aliasing an omitted position's neighbor.
    pub fn require(self: Layout, logical: usize) error{InternalError}!usize {
        return (try self.slot(logical)) orelse error.InternalError;
    }

    /// Translate the number of logical locals surviving an arena boundary.
    pub fn watermark(self: Layout, logical: usize) error{InternalError}!usize {
        if (logical >= self.prefix.len) return error.InternalError;
        return self.prefix[logical];
    }

    /// Return the exact entry count, including both transactional scratch entries.
    pub fn count(self: Layout) usize {
        return self.prefix[self.prefix.len - 1];
    }
};

/// Build emission bookkeeping without changing the canonical ownership plan.
pub fn build(allocator: std.mem.Allocator, locals: []const plan.Storage, operands: []const Operand) error{OutOfMemory}!Layout {
    const prefix = try allocator.alloc(usize, locals.len + operands.len + 3);
    prefix[0] = 0;
    for (locals, 0..) |slot, index| prefix[index + 1] = prefix[index] + @intFromBool(slot.shape.counted or slot.shape.unique_drop);
    for (operands, locals.len..) |operand, index| prefix[index + 1] = prefix[index] + @intFromBool(operand.may_own);
    const pending = locals.len + operands.len;
    prefix[pending + 1] = prefix[pending] + 1;
    prefix[pending + 2] = prefix[pending + 1] + 1;
    return .{ .prefix = prefix };
}
