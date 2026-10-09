//! Process-lifetime identity allocation for independent runtime stores.
//! A single monotonic namespace prevents stale handles from becoming valid in
//! a later store. Instances expose the same algorithm for exhaustion tests;
//! only the process wiring owns mutable global state.
const std = @import("std");

/// Atomic nonzero identities; the maximum value permanently marks exhaustion.
pub const Sequence = struct {
    counter: std.atomic.Value(u64) = .init(1),

    /// Issue one identity without wrapping, including under concurrent callers.
    pub fn next(self: *Sequence) error{IdentityExhausted}!u64 {
        var current = self.counter.load(.monotonic);
        while (true) {
            if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
            if (self.counter.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| {
                current = observed;
            } else return current;
        }
    }
};

var process_sequence: Sequence = .{};

/// Allocate an identity shared by memory, region, pool, and external stores.
pub fn acquire() error{IdentityExhausted}!u64 {
    return process_sequence.next();
}

test "identity sequence remains exhausted instead of issuing a stale identity" {
    var sequence: Sequence = .{ .counter = .init(std.math.maxInt(u64) - 1) };
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, try sequence.next());
    try std.testing.expectError(error.IdentityExhausted, sequence.next());
    try std.testing.expectError(error.IdentityExhausted, sequence.next());
}
