//! Source pool owners share per-execution quotas. Registry storage may use checked
//! region backing; owner wrappers and retained values use the execution allocator.
//! Limits count reserved slots, not physical bytes or current live node counts.
const std = @import("std");
const values = @import("value.zig");
const memory = @import("memory.zig");
const backend = @import("typed_pool.zig");
const SourceTag = struct {};
pub const Registry = backend.Pool(SourceTag, values.Value);
pub const Id = backend.Handle(SourceTag);
pub const Limits = struct { max_pools: usize = 64, max_pool_slots: usize = 4096, max_total_slots: usize = 16384 };
pub const Statistics = struct { live_pools: usize = 0, reserved_slots: usize = 0, acquired: u64 = 0, released: u64 = 0 };
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    limits: Limits,
    statistics: Statistics = .{},

    pub fn acquire(self: *Runtime, ty: values.Type, capacity: usize) backend.Error!values.Value {
        return self.acquireBacking(ty, capacity, self.allocator, null, null);
    }
    pub fn acquireAuthorized(self: *Runtime, ty: values.Type, capacity: usize, store: *memory.Store, capability: memory.AllocatorCapability) (memory.Error || backend.Error)!values.Value {
        const backing = try store.acquireBacking(capability);
        errdefer store.releaseBacking(backing);
        return self.acquireBacking(ty, capacity, backing.allocator, store, backing);
    }
    fn acquireBacking(self: *Runtime, ty: values.Type, capacity: usize, backing_allocator: std.mem.Allocator, store: ?*memory.Store, backing: ?memory.BackingLease) backend.Error!values.Value {
        if (self.statistics.live_pools >= self.limits.max_pools or capacity > self.limits.max_pool_slots or capacity > self.limits.max_total_slots - self.statistics.reserved_slots) return error.CapacityLimit;
        const owner = try self.allocator.create(Owner);
        errdefer self.allocator.destroy(owner);
        owner.* = .{ .ty = ty, .runtime = self, .backing_store = store, .backing = backing, .registry = try Registry.init(backing_allocator, capacity, .{ .retain = values.Value.retain, .release = values.Value.release }) };
        owner.registry.value_allocator = self.allocator;
        errdefer owner.registry.deinit();
        try owner.registry.reserve(capacity);
        self.statistics.live_pools += 1;
        self.statistics.reserved_slots += capacity;
        self.statistics.acquired +|= 1;
        return .{ .pool = owner };
    }
};
pub const Owner = struct {
    ty: values.Type,
    runtime: *Runtime,
    registry: Registry,
    references: usize = 1,
    backing_store: ?*memory.Store = null,
    backing: ?memory.BackingLease = null,

    /// Borrows arguments; success returns one owned snapshot or inert scalar/ID.
    pub fn perform(self: *Owner, kind: @import("pool_operations.zig").Kind, schema: @import("typed.zig").Pool, arguments: []const values.Value) (backend.Error || error{InternalError})!values.Value {
        if (arguments.len != kind.arity()) return error.InternalError;
        for (arguments, 0..) |argument, index| {
            if (argument.typeOf() != (if (kind == .insert or index == 1) schema.element else schema.handle)) return error.InternalError;
        }
        switch (kind) {
            .length => return values.Value.number(.u64, self.registry.statistics.live),
            .capacity => return values.Value.number(.u64, self.registry.max_slots),
            .clear => {
                try self.registry.clear();
                return .{ .bool = true };
            },
            .insert => return .{ .handle = .{ .ty = schema.handle, .id = try self.registry.insert(arguments[0]) } },
            .read, .replace, .remove => {
                if (arguments[0] != .handle) return error.InternalError;
                const id = arguments[0].handle.id;
                switch (kind) {
                    .read => return self.registry.get(id),
                    .replace => try self.registry.replace(id, arguments[1]),
                    .remove => try self.registry.remove(id),
                    else => unreachable,
                }
                return .{ .bool = true };
            },
        }
    }

    pub fn release(self: *Owner) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references != 0) return;
        const runtime = self.runtime;
        const capacity = self.registry.max_slots;
        self.registry.deinit();
        if (self.backing_store) |store| store.releaseBacking(self.backing.?);
        runtime.statistics.live_pools -= 1;
        runtime.statistics.reserved_slots -= capacity;
        runtime.statistics.released +|= 1;
        runtime.allocator.destroy(self);
    }
};
