//! Source type facts for the 5C migration. Since 5C every capability is a scalar handle, so a type owns no provider
//! state and the checker keeps no provider facts; what remains names the capabilities that did (`formerLeaf`) so the
//! `W_CAPABILITY_OWN` migration can find an `own` marker the old rules required.
const std = @import("std");
const typed = @import("typed.zig");

/// Whether a source type is a capability that owned provider state before 5C (every capability but `Stream`, `Input`
/// and `Host`). Only the migration warnings read it: an `own` marker on such a value, or on a value that held one,
/// was required then and is redundant now.
pub fn formerLeaf(ty: typed.Type) bool {
    return ty.capabilityIndex() != null and !ty.isHandle() and ty != .host_cap;
}

/// Whether a value of `ty` held a capability that owned provider state before 5C: a `formerLeaf`, or a record, union,
/// option, list, dictionary or fixed array that stores one. Such a value was owned only because of it, so an `own`
/// marker on it was required then; the migration warning removes the marker where the value owns nothing else now.
/// The walk is bounded by `depth_limit` and by a visited set, so a recursive schema terminates.
pub fn holdsFormerLeaf(records: []const typed.Record, ty: typed.Type) bool {
    var visited: [depth_limit]usize = undefined;
    return holds(records, ty, &visited, 0);
}

const depth_limit = 32;

fn holds(records: []const typed.Record, ty: typed.Type, visited: *[depth_limit]usize, depth: usize) bool {
    if (formerLeaf(ty)) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth == depth_limit) return false;
    const index = ty.recordIndex();
    for (visited[0..depth]) |seen| if (seen == index) return false;
    visited[depth] = index;
    const value = records[index];
    for (value.fields) |field| if (holds(records, field.ty, visited, depth + 1)) return true;
    if (value.shape.buffer) |element| if (holds(records, element, visited, depth + 1)) return true;
    if (value.collection.key) |key| if (holds(records, key, visited, depth + 1)) return true;
    if (value.shape.array) |array| if (holds(records, array.element, visited, depth + 1)) return true;
    if (value.shape.variants) |variants| for (variants.cases) |variant| {
        if (variant.payload) |payload| if (holds(records, payload, visited, depth + 1)) return true;
    };
    return false;
}

test "a capability and a record or list that holds one held a former provider leaf; a stream does not" {
    const records: [0]typed.Record = .{};
    try std.testing.expect(holdsFormerLeaf(&records, .filesystem_cap));
    try std.testing.expect(holdsFormerLeaf(&records, .clock_cap));
    try std.testing.expect(!holdsFormerLeaf(&records, .stream_cap));
    try std.testing.expect(!holdsFormerLeaf(&records, .host_cap));
    try std.testing.expect(!holdsFormerLeaf(&records, .i64));
}
