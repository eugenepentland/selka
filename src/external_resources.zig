//! Ownership backend for provider-backed external resources. Source integration
//! is separate. Providers and this store must not be copied or reentered.
const std = @import("std");
const external = @import("external_capabilities.zig");
pub const Kind = enum {
    filesystem,
    network,
    pub fn effect(self: Kind) @import("effect_set.zig").Effect {
        return switch (self) {
            .filesystem => .filesystem,
            .network => .network,
        };
    }
};
pub const Error = external.CallError || error{ Closed, InvalidCapability, InvalidOwner, IdentityExhausted, ResourceLimit };
pub const Capability = struct { store: u64, kind: Kind };
pub const Owner = struct { store: u64, index: usize, generation: u64 };
/// Trusted synchronous callbacks. Context outlives the store. Acquire failures
/// retain no resource; successful completion consumes the host handle, whereas
/// failed completion leaves it valid for retry or release. Release must terminate
/// without allocating/failing and must not imply completion. Requests are borrowed
/// only for the acquire call. Numeric handles are private to this host adapter.
pub const Provider = struct {
    context: *anyopaque,
    acquire: *const fn (*anyopaque, []const u8) external.CallError!u64,
    complete: *const fn (*anyopaque, u64) external.CallError!void,
    release: *const fn (*anyopaque, u64) void,
};
pub const Statistics = struct { live: usize = 0, acquired: u64 = 0, completed: u64 = 0, released: u64 = 0, transfers: u64 = 0 };
var identities: std.atomic.Value(u64) = .init(1);
fn identity() Error!u64 {
    var current = identities.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64)) return error.IdentityExhausted;
        if (identities.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| current = observed else return current;
    }
}
const Entry = struct {
    generation: u64 = 1,
    handle: ?u64 = null,
    previous: ?usize = null,
    next: ?usize = null,
    free_next: ?usize = null,
};
pub const Store = struct {
    allocator: std.mem.Allocator,
    id: u64,
    kind: Kind,
    provider: Provider,
    max_live: usize,
    entries: std.ArrayList(Entry) = .empty,
    free_head: ?usize = null,
    tail: ?usize = null,
    statistics: Statistics = .{},

    pub fn init(allocator: std.mem.Allocator, kind: Kind, provider: Provider, max_live: usize) Error!Store {
        return .{ .allocator = allocator, .id = try identity(), .kind = kind, .provider = provider, .max_live = max_live };
    }
    pub fn grant(self: *Store) Error!Capability {
        if (self.id == 0) return error.Closed;
        return .{ .store = self.id, .kind = self.kind };
    }
    fn checkCapability(self: *Store, capability: Capability) Error!void {
        if (self.id == 0) return error.Closed;
        if (capability.store != self.id or capability.kind != self.kind) return error.InvalidCapability;
    }
    fn get(self: *Store, owner: Owner) Error!*Entry {
        if (self.id == 0) return error.Closed;
        if (owner.store != self.id or owner.index >= self.entries.items.len) return error.InvalidOwner;
        const entry = &self.entries.items[owner.index];
        if (entry.handle == null or entry.generation != owner.generation) return error.InvalidOwner;
        return entry;
    }
    /// Reserve bookkeeping before invoking the provider. Nothing can fail after
    /// successful acquisition and before registration in the cleanup chain.
    pub fn acquire(self: *Store, capability: Capability, request: []const u8) Error!Owner {
        try self.checkCapability(capability);
        if (self.statistics.live >= self.max_live) return error.ResourceLimit;
        if (self.free_head == null) {
            const index = self.entries.items.len;
            try self.entries.append(self.allocator, .{});
            self.free_head = index;
        }
        const index = self.free_head.?;
        const handle = try self.provider.acquire(self.provider.context, request);
        const entry = &self.entries.items[index];
        self.free_head = entry.free_next;
        entry.free_next = null;
        entry.handle = handle;
        entry.previous = self.tail;
        entry.next = null;
        if (self.tail) |tail| self.entries.items[tail].next = index;
        self.tail = index;
        self.statistics.live += 1;
        self.statistics.acquired +|= 1;
        return .{ .store = self.id, .index = index, .generation = entry.generation };
    }
    /// Rekeying invalidates the old owner without allocation or provider calls.
    /// Transfers preserve acquisition order for final store-wide unwinding.
    pub fn transfer(self: *Store, owner: Owner) Error!Owner {
        const entry = try self.get(owner);
        if (entry.generation == std.math.maxInt(u64)) return error.IdentityExhausted;
        entry.generation += 1;
        self.statistics.transfers +|= 1;
        return .{ .store = self.id, .index = owner.index, .generation = entry.generation };
    }
    fn remove(self: *Store, index: usize) void {
        const entry = &self.entries.items[index];
        if (entry.previous) |previous| self.entries.items[previous].next = entry.next;
        if (entry.next) |next| self.entries.items[next].previous = entry.previous else self.tail = entry.previous;
        entry.handle = null;
        entry.previous = null;
        entry.next = null;
        // Retire exhausted slots permanently; never revive an old owner token.
        if (entry.generation != std.math.maxInt(u64)) {
            entry.generation += 1;
            entry.free_next = self.free_head;
            self.free_head = index;
        }
        self.statistics.live -= 1;
    }
    pub fn complete(self: *Store, owner: Owner) Error!void {
        const entry = try self.get(owner);
        try self.provider.complete(self.provider.context, entry.handle.?);
        self.remove(owner.index);
        self.statistics.completed +|= 1;
    }
    pub fn release(self: *Store, owner: Owner) Error!void {
        const entry = try self.get(owner);
        self.provider.release(self.provider.context, entry.handle.?);
        self.remove(owner.index);
        self.statistics.released +|= 1;
    }
    /// Reverse acquisition order, including after recoverable provider failures
    /// and ordinary host OOM. Does not attempt completion. Process termination or
    /// a host callback that cannot return is outside this cleanup guarantee.
    pub fn deinit(self: *Store) void {
        while (self.tail) |index| {
            self.provider.release(self.provider.context, self.entries.items[index].handle.?);
            self.remove(index);
            self.statistics.released +|= 1;
        }
        self.entries.deinit(self.allocator);
        self.entries = .empty;
        self.free_head = null;
        self.id = 0;
    }
};

/// A lexical cleanup scope. The store must outlive it. All scoped ownership
/// changes go through this API; direct Store mutation is reserved for unscoped
/// owners. Taking an owner transfers cleanup responsibility to the caller.
pub const Scope = struct {
    store: *Store,
    owners: std.ArrayList(Owner) = .empty,
    pub fn init(store: *Store) Scope {
        return .{ .store = store };
    }
    fn indexOf(self: *Scope, owner: Owner) Error!usize {
        for (self.owners.items, 0..) |item, index| if (std.meta.eql(item, owner)) return index;
        return error.InvalidOwner;
    }
    pub fn acquire(self: *Scope, capability: Capability, request: []const u8) Error!Owner {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const owner = try self.store.acquire(capability, request);
        self.owners.appendAssumeCapacity(owner);
        return owner;
    }
    pub fn adopt(self: *Scope, owner: Owner) Error!Owner {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const moved = try self.store.transfer(owner);
        self.owners.appendAssumeCapacity(moved);
        return moved;
    }
    pub fn take(self: *Scope, owner: Owner) Error!Owner {
        const index = try self.indexOf(owner);
        const moved = try self.store.transfer(owner);
        _ = self.owners.orderedRemove(index);
        return moved;
    }
    pub fn moveTo(self: *Scope, owner: Owner, destination: *Scope) Error!Owner {
        const index = try self.indexOf(owner);
        if (self.store != destination.store) return error.InvalidOwner;
        if (self == destination) {
            const moved = try self.store.transfer(owner);
            self.owners.items[index] = moved;
            return moved;
        }
        try destination.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const moved = try self.store.transfer(owner);
        _ = self.owners.orderedRemove(index);
        destination.owners.appendAssumeCapacity(moved);
        return moved;
    }
    pub fn complete(self: *Scope, owner: Owner) Error!void {
        const index = try self.indexOf(owner);
        try self.store.complete(owner);
        _ = self.owners.orderedRemove(index);
    }
    pub fn release(self: *Scope, owner: Owner) Error!void {
        const index = try self.indexOf(owner);
        try self.store.release(owner);
        _ = self.owners.orderedRemove(index);
    }
    pub fn deinit(self: *Scope) void {
        while (self.owners.pop()) |owner| {
            // Closed stores have already released every resource. Stale tokens
            // cannot release a newer owner even after misuse of the host API.
            self.store.release(owner) catch {};
        }
        self.owners.deinit(self.store.allocator);
        self.owners = .empty;
    }
};
