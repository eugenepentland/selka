//! Guest memory identity, bounds, and dynamic borrow lifetimes for the B backend.
//! No host address is exposed in a guest handle. Each Store has one runtime allocator.
const std = @import("std");
const values = @import("value.zig");
const Value = values.Value;
const Type = values.Type;

pub const Error = std.mem.Allocator.Error || error{
    IdentityExhausted,
    MemoryClosed,
    ForeignMemory,
    InvalidAllocation,
    ExpiredBorrow,
    BorrowConflict,
    BorrowSuspended,
    ChildrenActive,
    ReadOnly,
    Bounds,
    TypeMismatch,
    CapacityLimit,
    NoCapacity,
    InvalidCapability,
};
pub const Limits = struct {
    max_buffer_capacity: usize = std.math.maxInt(usize) / @sizeOf(Value),
    max_total_capacity: usize = std.math.maxInt(usize) / @sizeOf(Value),
    max_allocations: usize = std.math.maxInt(usize),
};
pub const Statistics = struct { live_allocations: usize = 0, total_capacity: usize = 0, created: u64 = 0, released: u64 = 0, transfers: u64 = 0 };
pub const BufferInfo = struct { element_type: Type, length: usize, capacity: usize };
pub const Growth = enum { unchanged, allocated };
pub const Kind = enum { shared, exclusive };
pub const Token = struct { index: usize, generation: u64 };
pub const AllocatorCapability = struct { memory: u64 };
pub const Allocation = struct { memory: u64, token: Token };
pub const Borrow = struct { memory: u64, token: Token };
pub const View = struct { allocation: Allocation, start: usize, length: usize, kind: Kind, element_type: Type };

var identities: std.atomic.Value(u64) = .init(1);
fn nextIdentity(counter: *std.atomic.Value(u64)) Error!u64 {
    var current = counter.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
        if (counter.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| current = observed else return current;
    }
}

// Slots are reused only with a new generation. Exhausted generations retire
// permanently; wrapping a generation would make an old handle valid again.
fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();
        const Entry = struct { generation: u64 = 1, value: ?T = null, next: ?usize = null };
        entries: std.ArrayList(Entry) = .empty,
        free_head: ?usize = null,

        fn insert(self: *Self, allocator: std.mem.Allocator, value: T) !Token {
            if (self.free_head) |index| {
                const entry = &self.entries.items[index];
                self.free_head = entry.next;
                entry.next = null;
                entry.value = value;
                return .{ .index = index, .generation = entry.generation };
            }
            const index = self.entries.items.len;
            try self.entries.append(allocator, .{ .value = value });
            return .{ .index = index, .generation = 1 };
        }
        fn get(self: *Self, token: Token) ?*T {
            if (token.index >= self.entries.items.len) return null;
            const entry = &self.entries.items[token.index];
            if (entry.generation != token.generation) return null;
            return if (entry.value) |*value| value else null;
        }
        fn rekey(self: *Self, token: Token) Error!Token {
            const entry = &self.entries.items[token.index];
            std.debug.assert(entry.generation == token.generation and entry.value != null);
            if (entry.generation == std.math.maxInt(u64)) return error.IdentityExhausted;
            entry.generation += 1;
            return .{ .index = token.index, .generation = entry.generation };
        }
        fn remove(self: *Self, token: Token) T {
            const entry = &self.entries.items[token.index];
            std.debug.assert(entry.generation == token.generation and entry.value != null);
            const value = entry.value.?;
            entry.value = null;
            if (entry.generation != std.math.maxInt(u64)) {
                entry.generation += 1;
                entry.next = self.free_head;
                self.free_head = token.index;
            }
            return value;
        }
    };
}
const Cell = struct { element_type: Type, values: []Value, length: usize, shared: usize = 0, exclusive: bool = false };
const Lease = struct { allocation: Token, start: usize, length: usize, kind: Kind, parent: ?Token = null, children: usize = 0 };

/// Owns memory/lease registries. Do not copy an initialized Store. Values passed
/// to it use the same runtime allocator; successful reads return retained values.
/// A Store is used by one VM execution thread, and handles never outlive its ID.
pub const Store = struct {
    allocator: std.mem.Allocator,
    identity: u64,
    limits: Limits = .{},
    statistics: Statistics = .{},
    cells: Pool(Cell) = .{},
    leases: Pool(Lease) = .{},

    pub fn init(allocator: std.mem.Allocator) Error!Store {
        return .{ .allocator = allocator, .identity = try nextIdentity(&identities) };
    }
    /// Called only by the embedding runtime; guest code cannot mint this value.
    pub fn allocatorCapability(self: *Store) Error!AllocatorCapability {
        try self.checkMemory(self.identity);
        return .{ .memory = self.identity };
    }
    pub fn checkAllocator(self: *Store, capability: AllocatorCapability) Error!void {
        if (self.identity == 0 or capability.memory != self.identity) return error.InvalidCapability;
    }
    pub fn initWithLimits(allocator: std.mem.Allocator, limits: Limits) Error!Store {
        var store = try init(allocator);
        store.limits = limits;
        return store;
    }
    /// Final execution cleanup releases cells even when a trap leaves active
    /// leases. Normal owner destruction uses destroy and refuses active borrows.
    pub fn deinit(self: *Store) void {
        if (self.identity == 0) return;
        for (self.cells.entries.items) |entry| if (entry.value) |owned| self.releaseOwned(owned);
        self.cells.entries.deinit(self.allocator);
        self.leases.entries.deinit(self.allocator);
        self.cells = .{};
        self.leases = .{};
        self.identity = 0;
    }
    fn checkMemory(self: *Store, identity: u64) Error!void {
        if (self.identity == 0) return error.MemoryClosed;
        if (self.identity != identity) return error.ForeignMemory;
    }
    fn cell(self: *Store, allocation: Allocation) Error!*Cell {
        try self.checkMemory(allocation.memory);
        return self.cells.get(allocation.token) orelse error.InvalidAllocation;
    }
    fn lease(self: *Store, reference: Borrow) Error!*Lease {
        try self.checkMemory(reference.memory);
        const active = self.leases.get(reference.token) orelse return error.ExpiredBorrow;
        if (self.cells.get(active.allocation) == null) return error.InvalidAllocation;
        return active;
    }
    fn freeCell(self: *Store, owned: Cell) void {
        var i = owned.length;
        while (i != 0) {
            i -= 1;
            owned.values[i].release(self.allocator);
        }
        self.allocator.free(owned.values);
    }
    fn releaseOwned(self: *Store, owned: Cell) void {
        self.statistics.live_allocations -= 1;
        self.statistics.total_capacity -= owned.values.len;
        self.statistics.released +|= 1;
        self.freeCell(owned);
    }
    fn capacityAllowed(self: *Store, capacity: usize, increase: usize) Error!void {
        if (capacity > self.limits.max_buffer_capacity or capacity > std.math.maxInt(usize) / @sizeOf(Value) or self.statistics.total_capacity > self.limits.max_total_capacity or increase > self.limits.max_total_capacity - self.statistics.total_capacity) return error.CapacityLimit;
    }
    fn unborrowed(owned: Cell) Error!void {
        if (owned.shared != 0 or owned.exclusive) return error.BorrowConflict;
    }
    /// Retain homogeneous ordinary values; input ownership stays with the caller.
    pub fn create(self: *Store, element_type: Type, inputs: []const Value) Error!Allocation {
        return self.createWithCapacity(element_type, inputs, inputs.len);
    }
    pub fn createWithCapacity(self: *Store, element_type: Type, inputs: []const Value, capacity: usize) Error!Allocation {
        try self.checkMemory(self.identity);
        if (inputs.len > capacity) return error.Bounds;
        for (inputs) |input| if (input.typeOf() != element_type) return error.TypeMismatch;
        try self.capacityAllowed(capacity, capacity);
        if (self.statistics.live_allocations >= self.limits.max_allocations) return error.CapacityLimit;
        const buffer = try self.allocator.alloc(Value, capacity);
        for (inputs, buffer[0..inputs.len]) |input, *output| output.* = input.retain();
        const owned: Cell = .{ .element_type = element_type, .values = buffer, .length = inputs.len };
        errdefer self.freeCell(owned);
        const token = try self.cells.insert(self.allocator, owned);
        self.statistics.live_allocations += 1;
        self.statistics.total_capacity += capacity;
        self.statistics.created +|= 1;
        return .{ .memory = self.identity, .token = token };
    }
    pub fn info(self: *Store, allocation: Allocation) Error!BufferInfo {
        const owned = try self.cell(allocation);
        if (owned.exclusive) return error.BorrowConflict;
        return .{ .element_type = owned.element_type, .length = owned.length, .capacity = owned.values.len };
    }
    /// Consume the owner identity without allocating or copying buffer contents.
    /// Active borrows prevent transfer. A failed transfer leaves the old owner valid.
    pub fn transfer(self: *Store, allocation: Allocation) Error!Allocation {
        try unborrowed((try self.cell(allocation)).*);
        const token = try self.cells.rekey(allocation.token);
        self.statistics.transfers +|= 1;
        return .{ .memory = self.identity, .token = token };
    }
    pub fn reserve(self: *Store, allocation: Allocation, capacity: usize) Error!Growth {
        const owned = try self.cell(allocation);
        try unborrowed(owned.*);
        if (capacity <= owned.values.len) return .unchanged;
        const increase = capacity - owned.values.len;
        try self.capacityAllowed(capacity, increase);
        const grown = try self.allocator.alloc(Value, capacity);
        @memcpy(grown[0..owned.length], owned.values[0..owned.length]);
        // Transfer existing Value ownership; releasing the old elements here
        // would invalidate the moved snapshots in the new backing buffer.
        self.allocator.free(owned.values);
        owned.values = grown;
        self.statistics.total_capacity += increase;
        return .allocated;
    }
    pub fn appendWithinCapacity(self: *Store, allocation: Allocation, value: Value) Error!void {
        const owned = try self.cell(allocation);
        try unborrowed(owned.*);
        if (value.typeOf() != owned.element_type) return error.TypeMismatch;
        if (owned.length == owned.values.len) return error.NoCapacity;
        owned.values[owned.length] = value.retain();
        owned.length += 1;
    }
    pub fn resizeWithinCapacity(self: *Store, allocation: Allocation, length: usize, fill: Value) Error!void {
        const owned = try self.cell(allocation);
        try unborrowed(owned.*);
        if (length > owned.values.len) return error.NoCapacity;
        if (length > owned.length and fill.typeOf() != owned.element_type) return error.TypeMismatch;
        while (owned.length > length) {
            owned.length -= 1;
            owned.values[owned.length].release(self.allocator);
        }
        while (owned.length < length) {
            owned.values[owned.length] = fill.retain();
            owned.length += 1;
        }
    }
    pub fn destroy(self: *Store, allocation: Allocation) Error!void {
        try unborrowed((try self.cell(allocation)).*);
        self.releaseOwned(self.cells.remove(allocation.token));
    }
    /// Terminal unwind only: invalidate all views before releasing this owner.
    /// Normal scope exit uses destroy and diagnoses outstanding borrows.
    pub fn destroyForUnwind(self: *Store, allocation: Allocation) Error!void {
        _ = try self.cell(allocation);
        for (self.leases.entries.items, 0..) |entry, index| if (entry.value) |lease_value| {
            if (std.meta.eql(lease_value.allocation, allocation.token)) _ = self.leases.remove(.{ .index = index, .generation = entry.generation });
        };
        self.releaseOwned(self.cells.remove(allocation.token));
    }
    /// Root borrows currently conflict over the whole allocation, even for
    /// disjoint or empty ranges. Bounds are still narrowed on each view.
    pub fn borrow(self: *Store, allocation: Allocation, start: usize, length: usize, kind: Kind) Error!Borrow {
        const owned = try self.cell(allocation);
        try checkRange(owned.length, start, length);
        if (owned.exclusive or (kind == .exclusive and owned.shared != 0)) return error.BorrowConflict;
        if (kind == .shared and owned.shared == std.math.maxInt(usize)) return error.IdentityExhausted;
        const token = try self.leases.insert(self.allocator, .{ .allocation = allocation.token, .start = start, .length = length, .kind = kind });
        // Lease insertion cannot relocate cells. Commit the lock only on success.
        if (kind == .shared) owned.shared += 1 else owned.exclusive = true;
        return .{ .memory = self.identity, .token = token };
    }
    /// Narrow a live borrow. Exclusive parents are suspended until their child
    /// ends. Shared parents permit shared children and remain readable.
    pub fn reborrow(self: *Store, parent: Borrow, start: usize, length: usize, kind: Kind) Error!Borrow {
        const previous = (try self.lease(parent)).*;
        try usable(previous);
        if (previous.kind == .shared and kind == .exclusive) return error.ReadOnly;
        try checkRange(previous.length, start, length);
        if (previous.children == std.math.maxInt(usize)) return error.IdentityExhausted;
        const token = try self.leases.insert(self.allocator, .{ .allocation = previous.allocation, .start = previous.start + start, .length = length, .kind = kind, .parent = parent.token });
        // Insertion may relocate leases, so resolve the parent again by identity.
        self.leases.get(parent.token).?.children += 1;
        return .{ .memory = self.identity, .token = token };
    }
    pub fn end(self: *Store, reference: Borrow) Error!void {
        const active = (try self.lease(reference)).*;
        if (active.children != 0) return error.ChildrenActive;
        _ = self.leases.remove(reference.token);
        if (active.parent) |parent| {
            self.leases.get(parent).?.children -= 1;
        } else {
            const owned = self.cells.get(active.allocation).?;
            if (active.kind == .shared) owned.shared -= 1 else owned.exclusive = false;
        }
    }
    pub fn describe(self: *Store, reference: Borrow) Error!View {
        const active = (try self.lease(reference)).*;
        try usable(active);
        return .{ .allocation = .{ .memory = self.identity, .token = active.allocation }, .start = active.start, .length = active.length, .kind = active.kind, .element_type = self.cells.get(active.allocation).?.element_type };
    }
    pub fn read(self: *Store, reference: Borrow, index: usize) Error!Value {
        const active = (try self.lease(reference)).*;
        try usable(active);
        if (index >= active.length) return error.Bounds;
        return self.cells.get(active.allocation).?.values[active.start + index].retain();
    }
    pub fn write(self: *Store, reference: Borrow, index: usize, replacement: Value) Error!void {
        const active = (try self.lease(reference)).*;
        try usable(active);
        if (active.kind != .exclusive) return error.ReadOnly;
        if (index >= active.length) return error.Bounds;
        try self.replace(self.cells.get(active.allocation).?, active.start + index, replacement);
    }
    pub fn readOwner(self: *Store, allocation: Allocation, index: usize) Error!Value {
        const owned = try self.cell(allocation);
        if (owned.exclusive) return error.BorrowConflict;
        if (index >= owned.length) return error.Bounds;
        return owned.values[index].retain();
    }
    pub fn writeOwner(self: *Store, allocation: Allocation, index: usize, replacement: Value) Error!void {
        const owned = try self.cell(allocation);
        if (owned.exclusive or owned.shared != 0) return error.BorrowConflict;
        if (index >= owned.length) return error.Bounds;
        try self.replace(owned, index, replacement);
    }
    fn replace(self: *Store, owned: *Cell, index: usize, replacement: Value) Error!void {
        if (replacement.typeOf() != owned.element_type) return error.TypeMismatch;
        const next = replacement.retain();
        owned.values[index].release(self.allocator);
        owned.values[index] = next;
    }
};
fn usable(lease: Lease) Error!void {
    if (lease.kind == .exclusive and lease.children != 0) return error.BorrowSuspended;
}
fn checkRange(capacity: usize, start: usize, length: usize) Error!void {
    // Subtraction avoids overflow in start + length, including hostile indices.
    if (start > capacity or length > capacity - start) return error.Bounds;
}

test "memory identities and slot generations never wrap into stale handles" {
    var counter: std.atomic.Value(u64) = .init(std.math.maxInt(u64) - 1);
    try std.testing.expectEqual(std.math.maxInt(u64) - 1, try nextIdentity(&counter));
    try std.testing.expectError(error.IdentityExhausted, nextIdentity(&counter));
    var pool: Pool(u8) = .{};
    defer pool.entries.deinit(std.testing.allocator);
    const first = try pool.insert(std.testing.allocator, 7);
    pool.entries.items[first.index].generation = std.math.maxInt(u64);
    const last: Token = .{ .index = first.index, .generation = std.math.maxInt(u64) };
    try std.testing.expectEqual(@as(u8, 7), pool.remove(last));
    const next = try pool.insert(std.testing.allocator, 9);
    try std.testing.expect(next.index != last.index);
    try std.testing.expect(pool.get(first) == null and pool.get(last) == null);
}

test "exhausted ownership generations fail transfer without losing the buffer" {
    const t = std.testing;
    var store = try Store.init(t.allocator);
    defer store.deinit();
    const first = try store.create(.i64, &.{.{ .i64 = 7 }});
    store.cells.entries.items[first.token.index].generation = std.math.maxInt(u64);
    const last: Allocation = .{ .memory = first.memory, .token = .{ .index = first.token.index, .generation = std.math.maxInt(u64) } };
    try t.expectError(error.IdentityExhausted, store.transfer(last));
    try t.expectEqual(@as(i64, 7), (try store.readOwner(last, 0)).i64);
    try t.expectEqual(@as(u64, 0), store.statistics.transfers);
    try store.destroy(last);
    const next = try store.create(.i64, &.{});
    try t.expect(next.token.index != last.token.index);
    try t.expectError(error.InvalidAllocation, store.info(last));
}
