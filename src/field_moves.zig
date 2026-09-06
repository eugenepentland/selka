//! Immutable partial-move witnesses preserve availability independently of diagnostic locations.
const std = @import("std");
const Span = @import("source.zig").Span;
/// Null entries are available fields; an empty state means no fields have moved.
pub const State = []const ?Span;
/// Compare ownership state without requiring alternative paths to move at the same site.
pub fn same(left: State, right: State) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if ((a == null) != (b == null)) return false;
    return true;
}
/// Copy the state before recording a take so earlier branch snapshots remain immutable.
pub fn take(allocator: std.mem.Allocator, state: State, count: usize, index: usize, span: Span) std.mem.Allocator.Error!State {
    std.debug.assert(index < count);
    std.debug.assert(state.len == 0 or state.len == count);
    const next = try allocator.alloc(?Span, count);
    @memset(next, null);
    if (state.len != 0) @memcpy(next, state);
    next[index] = span;
    return next;
}
/// Select the earliest recorded source witness for an invalid whole-record use.
pub fn first(state: State) ?Span {
    var earliest: ?Span = null;
    for (state) |entry| if (entry) |span| {
        if (earliest == null or span.start < earliest.?.start) earliest = span;
    };
    return earliest;
}
