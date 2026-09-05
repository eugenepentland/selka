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
};
pub const Kind = enum { shared, exclusive };
pub const Token = struct { index: usize, generation: u64 };
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
const Cell = struct { element_type: Type, values: []Value, shared: usize = 0, exclusive: bool = false };
const Lease = struct { allocation: Token, start: usize, length: usize, kind: Kind, parent: ?Token = null, children: usize = 0 };

/// Owns memory/lease registries. Do not copy an initialized Store. Values passed
/// to it use the same runtime allocator; successful reads return retained values.
/// A Store is used by one VM execution thread, and handles never outlive its ID.
pub const Store = struct {
    allocator: std.mem.Allocator,
    identity: u64,
    cells: Pool(Cell) = .{},
    leases: Pool(Lease) = .{},

    pub fn init(allocator: std.mem.Allocator) Error!Store {
        return .{ .allocator = allocator, .identity = try nextIdentity(&identities) };
    }
    /// Final execution cleanup releases cells even when a trap leaves active
    /// leases. Normal owner destruction uses destroy and refuses active borrows.
    pub fn deinit(self: *Store) void {
        if (self.identity == 0) return;
        for (self.cells.entries.items) |entry| if (entry.value) |owned| self.freeCell(owned);
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
        for (owned.values) |value| value.release(self.allocator);
        self.allocator.free(owned.values);
    }
    /// Retain a homogeneous buffer; input ownership stays with the caller.
    pub fn create(self: *Store, element_type: Type, inputs: []const Value) Error!Allocation {
        try self.checkMemory(self.identity);
        for (inputs) |input| if (input.typeOf() != element_type) return error.TypeMismatch;
        const buffer = try self.allocator.alloc(Value, inputs.len);
        for (inputs, buffer) |input, *output| output.* = input.retain();
        const owned: Cell = .{ .element_type = element_type, .values = buffer };
        errdefer self.freeCell(owned);
        return .{ .memory = self.identity, .token = try self.cells.insert(self.allocator, owned) };
    }
    pub fn destroy(self: *Store, allocation: Allocation) Error!void {
        const owned = try self.cell(allocation);
        if (owned.shared != 0 or owned.exclusive) return error.BorrowConflict;
        self.freeCell(self.cells.remove(allocation.token));
    }
    /// Root borrows currently conflict over the whole allocation, even for
    /// disjoint or empty ranges. Bounds are still narrowed on each view.
    pub fn borrow(self: *Store, allocation: Allocation, start: usize, length: usize, kind: Kind) Error!Borrow {
        const owned = try self.cell(allocation);
        try checkRange(owned.values.len, start, length);
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
        if (index >= owned.values.len) return error.Bounds;
        return owned.values[index].retain();
    }
    pub fn writeOwner(self: *Store, allocation: Allocation, index: usize, replacement: Value) Error!void {
        const owned = try self.cell(allocation);
        if (owned.exclusive or owned.shared != 0) return error.BorrowConflict;
        if (index >= owned.values.len) return error.Bounds;
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
