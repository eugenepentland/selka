//! Ownership backend for provider-backed external resources. Source integration
//! is separate. Providers and this store must not be copied or reentered.
const std = @import("std");
const external = @import("external_capabilities.zig");
/// External resource provider family and its associated source effect.
pub const Kind = enum {
    filesystem,
    network,
    /// Return the source effect needed to access this provider family.
    pub fn effect(self: Kind) @import("effect_set.zig").Effect {
        return switch (self) {
            .filesystem => .filesystem,
            .network => .network,
        };
    }
};
pub const Error = external.CallError || error{ Closed, InvalidCapability, InvalidOwner, IdentityExhausted, ResourceLimit, InvalidProvider };
/// Direction of a resource byte transfer.
pub const IoKind = enum { read, write };
/// Provider-reported byte count and end-of-stream state.
pub const Read = struct { length: usize, eof: bool };
/// Individually attenuable read, write, and completion authority.
pub const Permission = enum { read, write, complete };
pub const Permissions = u8;
pub const all_permissions: Permissions = 7;
/// Return the mask bit for one resource permission.
pub fn permissionBit(permission: Permission) Permissions {
    return @as(Permissions, 1) << @intCast(@backingInt(permission));
}
/// Store-bound provider authority with an attenuable permission mask.
pub const Capability = struct { store: u64, kind: Kind, permissions: Permissions = all_permissions };
/// Generation-checked external resource identity bound to one store.
pub const Owner = struct { store: u64, index: usize, generation: u64 };
/// Trusted synchronous callbacks. Context outlives the store. Acquire failures
/// retain no resource; successful completion consumes the host handle, whereas
/// failed completion leaves it valid for retry or release. Release must terminate
/// without allocating/failing and must not imply completion. Requests are borrowed
/// only for the acquire call. Numeric handles are private to this host adapter.
pub const Provider = struct {
    /// Read/write keep the handle live, including on errors. Buffers are borrowed
    /// only for the callback. Counts describe actual progress, never exceed the
    /// buffer, and need not fill it. EOF is explicit even for zero-capacity reads.
    read: ?*const fn (*anyopaque, u64, []u8) external.CallError!Read = null,
    write: ?*const fn (*anyopaque, u64, []const u8) external.CallError!usize = null,
    context: *anyopaque,
    /// Acquisition must honor the requested permissions when choosing open modes
    /// and interpreting requests. Deny requests that require excluded authority.
    acquire: *const fn (*anyopaque, []const u8, Permissions) external.CallError!u64,
    complete: *const fn (*anyopaque, u64) external.CallError!void,
    release: *const fn (*anyopaque, u64) void,
};
/// Live resources and cumulative acquisition, completion, release, and transfer counts.
pub const Statistics = struct { live: usize = 0, acquired: u64 = 0, completed: u64 = 0, released: u64 = 0, transfers: u64 = 0 };
const identities = @import("wiring/identity.zig");
const Entry = struct {
    permissions: Permissions = all_permissions,
    generation: u64 = 1,
    handle: ?u64 = null,
    previous: ?usize = null,
    next: ?usize = null,
    free_next: ?usize = null,
};
/// Owns the registry mapping checked resource identities to provider handles.
pub const Store = struct {
    allocator: std.mem.Allocator,
    id: u64,
    kind: Kind,
    provider: Provider,
    max_live: usize,
    registry: struct {
        entries: std.ArrayList(Entry) = .empty,
        free_head: ?usize = null,
        tail: ?usize = null,
    } = .{},
    statistics: Statistics = .{},

    /// Initialize a generation-checked owner registry borrowing the provider callbacks.
    pub fn init(allocator: std.mem.Allocator, kind: Kind, provider: Provider, max_live: usize) Error!Store {
        return .{ .allocator = allocator, .id = try identities.acquire(), .kind = kind, .provider = provider, .max_live = max_live };
    }
    /// Grant a capability for this live provider store.
    pub fn grant(self: *Store) Error!Capability {
        if (self.id == 0) return error.Closed;
        return .{ .store = self.id, .kind = self.kind };
    }
    fn checkCapability(self: *Store, capability: Capability) Error!void {
        if (self.id == 0) return error.Closed;
        if (capability.store != self.id or capability.kind != self.kind or capability.permissions & ~all_permissions != 0) return error.InvalidCapability;
    }
    /// Intersection cannot amplify authority, even when the caller requests more.
    /// Existing grants/owners remain unchanged; copies share the original quotas.
    pub fn restrict(self: *Store, capability: Capability, permissions: Permissions) Error!Capability {
        try self.checkCapability(capability);
        if (permissions & ~all_permissions != 0) return error.InvalidCapability;
        var restricted = capability;
        restricted.permissions &= permissions;
        return restricted;
    }
    fn get(self: *Store, owner: Owner) error{ Closed, InvalidOwner }!*Entry {
        if (self.id == 0) return error.Closed;
        if (owner.store != self.id or owner.index >= self.registry.entries.items.len) return error.InvalidOwner;
        const entry = &self.registry.entries.items[owner.index];
        if (entry.handle == null or entry.generation != owner.generation) return error.InvalidOwner;
        return entry;
    }
    /// Reserve bookkeeping before invoking the provider. Nothing can fail after
    /// successful acquisition and before registration in the cleanup chain.
    pub fn acquire(self: *Store, capability: Capability, request: []const u8) Error!Owner {
        try self.checkCapability(capability);
        if (self.statistics.live >= self.max_live) return error.ResourceLimit;
        if (self.registry.free_head == null) {
            const index = self.registry.entries.items.len;
            try self.registry.entries.append(self.allocator, .{});
            self.registry.free_head = index;
        }
        const index = self.registry.free_head.?;
        const handle = try self.provider.acquire(self.provider.context, request, capability.permissions);
        const entry = &self.registry.entries.items[index];
        self.registry.free_head = entry.free_next;
        entry.free_next = null;
        entry.handle = handle;
        entry.permissions = capability.permissions;
        entry.previous = self.registry.tail;
        entry.next = null;
        if (self.registry.tail) |tail| self.registry.entries.items[tail].next = index;
        self.registry.tail = index;
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
        const entry = &self.registry.entries.items[index];
        if (entry.previous) |previous| self.registry.entries.items[previous].next = entry.next;
        if (entry.next) |next| self.registry.entries.items[next].previous = entry.previous else self.registry.tail = entry.previous;
        entry.handle = null;
        entry.previous = null;
        entry.next = null;
        // Retire exhausted slots permanently; never revive an old owner token.
        if (entry.generation != std.math.maxInt(u64)) {
            entry.generation += 1;
            entry.free_next = self.registry.free_head;
            self.registry.free_head = index;
        }
        self.statistics.live -= 1;
    }
    /// Validate ownership and read permission before filling caller-owned byte storage.
    pub fn read(self: *Store, owner: Owner, output: []u8) Error!Read {
        const entry = try self.get(owner);
        if (entry.permissions & permissionBit(.read) == 0) return error.Denied;
        const callback = self.provider.read orelse return error.Unavailable;
        @memset(output, 0);
        const result = try callback(self.provider.context, entry.handle.?, output);
        if (result.length > output.len) return error.InvalidProvider;
        @memset(output[result.length..], 0);
        return result;
    }
    /// Validate ownership and write permission before sending the supplied bytes.
    pub fn write(self: *Store, owner: Owner, input: []const u8) Error!usize {
        const entry = try self.get(owner);
        if (entry.permissions & permissionBit(.write) == 0) return error.Denied;
        const callback = self.provider.write orelse return error.Unavailable;
        const length = try callback(self.provider.context, entry.handle.?, input);
        if (length > input.len) return error.InvalidProvider;
        return length;
    }
    /// Complete a tracked resource; failed completion preserves the live owner.
    pub fn complete(self: *Store, owner: Owner) Error!void {
        const entry = try self.get(owner);
        if (entry.permissions & permissionBit(.complete) == 0) return error.Denied;
        try self.provider.complete(self.provider.context, entry.handle.?);
        self.remove(owner.index);
        self.statistics.completed +|= 1;
    }
    /// Release a tracked owner without completing it and invalidate its identity.
    pub fn release(self: *Store, owner: Owner) error{ Closed, InvalidOwner }!void {
        const entry = try self.get(owner);
        self.provider.release(self.provider.context, entry.handle.?);
        self.remove(owner.index);
        self.statistics.released +|= 1;
    }
    /// Release a still-live owner during terminal cleanup. Stale identities and
    /// closed stores return false and never release a replacement generation.
    pub fn releaseIfLive(self: *Store, owner: Owner) bool {
        self.release(owner) catch return false;
        return true;
    }
    /// Reverse acquisition order, including after recoverable provider failures
    /// and ordinary host OOM. Does not attempt completion. Process termination or
    /// a host callback that cannot return is outside this cleanup guarantee.
    pub fn deinit(self: *Store) void {
        while (self.registry.tail) |index| {
            self.provider.release(self.provider.context, self.registry.entries.items[index].handle.?);
            self.remove(index);
            self.statistics.released +|= 1;
        }
        self.registry.entries.deinit(self.allocator);
        self.registry.entries = .empty;
        self.registry.free_head = null;
        self.id = 0;
    }
};

/// A lexical cleanup scope. The store must outlive it. All scoped ownership
/// changes go through this API; direct Store mutation is reserved for unscoped
/// owners. Taking an owner transfers cleanup responsibility to the caller.
pub const Scope = struct {
    store: *Store,
    owners: std.ArrayList(Owner) = .empty,
    /// Create an empty cleanup scope borrowing the external resource store.
    pub fn init(store: *Store) Scope {
        return .{ .store = store };
    }
    fn indexOf(self: *Scope, owner: Owner) Error!usize {
        for (self.owners.items, 0..) |item, index| if (std.meta.eql(item, owner)) return index;
        return error.InvalidOwner;
    }
    /// Acquire provider ownership and register it for lifetime tracking, cleaning up registration failures.
    pub fn acquire(self: *Scope, capability: Capability, request: []const u8) Error!Owner {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const owner = try self.store.acquire(capability, request);
        self.owners.appendAssumeCapacity(owner);
        return owner;
    }
    /// Register an existing live owner for cleanup in this scope.
    pub fn adopt(self: *Scope, owner: Owner) Error!Owner {
        try self.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const moved = try self.store.transfer(owner);
        self.owners.appendAssumeCapacity(moved);
        return moved;
    }
    /// Remove an owner from scope cleanup and transfer its ownership to the caller.
    pub fn take(self: *Scope, owner: Owner) Error!Owner {
        const index = try self.indexOf(owner);
        const moved = try self.store.transfer(owner);
        _ = self.owners.orderedRemove(index);
        return moved;
    }
    /// Transfer tracked ownership to another scope without duplicating provider ownership.
    pub fn moveTo(self: *Scope, owner: Owner, destination: *Scope) Error!Owner {
        const index = try self.indexOf(owner);
        if (self.store != destination.store) return error.InvalidOwner;
        const owner_list = &self.owners;
        if (owner_list == &destination.owners) {
            const moved = try self.store.transfer(owner);
            owner_list.items[index] = moved;
            return moved;
        }
        // Destination capacity is reserved before rekeying so failure preserves ownership.
        try destination.owners.ensureUnusedCapacity(self.store.allocator, 1);
        const moved = try self.store.transfer(owner);
        _ = owner_list.orderedRemove(index);
        destination.owners.appendAssumeCapacity(moved);
        return moved;
    }
    /// Complete a tracked resource; failed completion preserves the live owner.
    pub fn complete(self: *Scope, owner: Owner) Error!void {
        const index = try self.indexOf(owner);
        try self.store.complete(owner);
        _ = self.owners.orderedRemove(index);
    }
    /// Release a tracked owner without completing it and invalidate its identity.
    pub fn release(self: *Scope, owner: Owner) Error!void {
        const index = try self.indexOf(owner);
        try self.store.release(owner);
        _ = self.owners.orderedRemove(index);
    }
    pub fn deinit(self: *Scope) void {
        while (self.owners.pop()) |owner| {
            // Closed stores have already released every resource. Stale tokens
            // cannot release a newer owner even after misuse of the host API.
            _ = self.store.releaseIfLive(owner);
        }
        self.owners.deinit(self.store.allocator);
        self.owners = .empty;
    }
};
