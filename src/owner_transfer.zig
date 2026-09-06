//! Ownership-list transfer shared by guest allocations and external resources.
const std = @import("std");

/// Move a registered owner after the caller has validated its index and store.
/// Destination capacity is reserved before rekeying so failure preserves ownership.
pub fn between(
    comptime Owner: type,
    comptime TransferError: type,
    store: anytype,
    source: *std.ArrayList(Owner),
    index: usize,
    destination: *std.ArrayList(Owner),
) TransferError!Owner {
    const owner = source.items[index];
    if (source == destination) {
        const moved = try store.transfer(owner);
        source.items[index] = moved;
        return moved;
    }
    try destination.ensureUnusedCapacity(store.allocator, 1);
    const moved = try store.transfer(owner);
    _ = source.orderedRemove(index);
    destination.appendAssumeCapacity(moved);
    return moved;
}
