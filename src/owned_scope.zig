//! Runtime ownership cleanup records for C. Guest ownership syntax is separate.
const std = @import("std");
const memory = @import("memory.zig");
const values = @import("value.zig");
pub const Error = memory.Error || error{NotOwned};

/// A scope owns each registered allocation until release, take, or moveTo.
/// The returned handles permit access; callers must transfer ownership through
/// this scope rather than rekeying its allocations directly through Store.
/// Store and Scope must not be copied after initialization.
pub const Scope = struct {
    store: *memory.Store,
    owners: std.ArrayList(memory.Allocation) = .empty,

    /// Create an empty ownership scope borrowing its guest memory store.
    pub fn init(store: *memory.Store) Scope {
        return .{ .store = store };
    }
    /// Final cleanup also works during a trap with outstanding borrows. Normal
    /// code uses rollback/release first so borrow errors remain observable.
    pub fn deinit(self: *Scope) void {
        while (self.owners.pop()) |owner| {
            // A closed store already cleaned everything. A stale owner must
            // never destroy a newer generation owned somewhere else.
            _ = self.store.destroyIfLiveForUnwind(owner);
        }
        self.owners.deinit(self.store.allocator);
        self.owners = .empty;
    }
    fn indexOf(self: *Scope, owner: memory.Allocation) Error!usize {
        for (self.owners.items, 0..) |item, index| if (std.meta.eql(item, owner)) return index;
        return error.NotOwned;
    }
    /// Create an allocation and register its owner for scope cleanup.
    pub fn acquire(self: *Scope, element_type: values.Type, inputs: []const values.Value, capacity: usize) Error!memory.Allocation {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const owner = try self.store.createWithCapacity(element_type, inputs, capacity);
        self.owners.appendAssumeCapacity(owner);
        return owner;
    }
    /// Fallible cleanup-record growth occurs before consuming the external owner.
    pub fn adopt(self: *Scope, owner: memory.Allocation) Error!memory.Allocation {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const moved = try self.store.transfer(owner);
        self.owners.appendAssumeCapacity(moved);
        return moved;
    }
    /// Remove an owner from this scope and transfer cleanup responsibility to the caller.
    pub fn take(self: *Scope, owner: memory.Allocation) Error!memory.Allocation {
        const index = try self.indexOf(owner);
        const moved = try self.store.transfer(owner);
        _ = self.owners.orderedRemove(index);
        return moved;
    }
    /// Transfer an owner between scopes without releasing its guest allocation.
    pub fn moveTo(self: *Scope, owner: memory.Allocation, destination: *Scope) Error!memory.Allocation {
        const index = try self.indexOf(owner);
        if (self.store != destination.store) return error.ForeignMemory;
        return @import("owner_transfer.zig").between(memory.Allocation, Error, self.store, &self.owners, index, &destination.owners);
    }
    /// Remove a tracked owner and destroy its guest allocation.
    pub fn release(self: *Scope, owner: memory.Allocation) Error!void {
        const index = try self.indexOf(owner);
        try self.store.destroy(owner);
        _ = self.owners.orderedRemove(index);
    }
    /// Reverse acquisition order, without allocation. If an active borrow blocks
    /// cleanup, already released entries stay removed and remaining entries can
    /// be retried after the borrow ends.
    pub fn rollback(self: *Scope) Error!void {
        while (self.owners.items.len != 0) {
            const owner = self.owners.items[self.owners.items.len - 1];
            try self.store.destroy(owner);
            _ = self.owners.pop();
        }
    }
};
