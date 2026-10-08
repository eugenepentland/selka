//! Immutable ordinary aggregates and unique owned records with field transfer.
//! Every VM operand/local owns one retained value.
const std = @import("std");
const external_resources = @import("external_resources.zig");
const runtime_values = @This();
const identity = @import("type_identity.zig");
/// The checked program's type identities (`type_identity.zig`).
pub const Type = identity.Type;

/// Runtime scalar, aggregate, capability, or owned resource representation.
pub const Value = union(enum) {
    unit,
    i64: i64,
    bool: bool,
    integer: struct { ty: Type, value: i128 },
    aggregate: *Aggregate,
    managed: *ManagedObject,
    owned: OwnedValue,
    capability: CapabilityValue,

    /// Return the scalar or nominal type carried by this value.
    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .owned => |owned| owned.typeOf(),
            .capability => |capability| capability.typeOf(),
            .unit => .unit,
            .i64 => .i64,
            .bool => .bool,
            .integer => |n| n.ty,
            .aggregate => |record| record.ty,
            .managed => |object| object.ty,
        };
    }

    /// Construct the representation of a previously range-checked integer.
    pub fn number(ty: Type, value: i128) Value {
        std.debug.assert(ty.isInteger());
        std.debug.assert(ty.fits(value));
        return if (ty == .i64) .{ .i64 = @intCast(value) } else .{ .integer = .{ .ty = ty, .value = value } };
    }
    /// Extract a mathematical integer, rejecting noninteger representations.
    pub fn asInteger(self: Value) error{InternalError}!i128 {
        return switch (self) {
            .i64 => |n| n,
            .integer => |n| n.value,
            else => error.InternalError,
        };
    }
    /// Borrow input fields; the returned value owns independent references.
    pub fn create(allocator: std.mem.Allocator, ty: Type, fields: []const Value) error{ OutOfMemory, InvalidAggregateType }!Value {
        if (!ty.isAggregate()) return error.InvalidAggregateType;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, owned) |field, *out| out.* = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    /// Allocate a nominal variant and retain its optional payload.
    pub fn createVariant(allocator: std.mem.Allocator, ty: Type, tag: usize, payload: ?Value) error{ OutOfMemory, InvalidAggregateType }!Value {
        const value = try create(allocator, ty, if (payload) |input| &.{input} else &.{});
        value.aggregate.active_tag = tag;
        return value;
    }
    /// Input expressions are already evaluated in source order. Store in schema order.
    /// The emitter validates that order is a permutation before dispatch.
    pub fn createOrdered(allocator: std.mem.Allocator, ty: Type, fields: []const Value, order: []const usize) error{ OutOfMemory, InvalidAggregateType, InternalError }!Value {
        if (order.len == 0) return create(allocator, ty, fields);
        if (!ty.isAggregate() or order.len != fields.len) return error.InternalError;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, order) |field, index| owned[index] = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    /// Add a reference to owned backing and return another value sharing it.
    pub fn retain(self: Value) Value {
        if (self == .managed) self.managed.retain();
        if (self == .owned) self.owned.retain();
        if (self == .aggregate) self.aggregate.references += 1;
        return self;
    }

    /// Release without allocation or recursive host calls. Zero-reference nodes
    /// temporarily form an intrusive work list; shared live nodes never change.
    pub fn release(self: Value, allocator: std.mem.Allocator) void {
        if (self == .managed) {
            self.managed.release();
            return;
        }
        if (self != .aggregate and self != .owned) return;
        releaseManaged(self, allocator);
    }

    noinline fn releaseManaged(self: Value, allocator: std.mem.Allocator) void {
        var pending: ?*Aggregate = null;
        enqueueRelease(self, &pending, allocator);
        while (pending) |record| {
            if (record.release_index != 0) {
                record.release_index -= 1;
                if (record.moved_fields == null or !record.moved_fields.?[record.release_index]) enqueueRelease(record.fields[record.release_index], &pending, allocator);
            } else {
                pending = record.next;
                if (record.moved_fields) |moved| allocator.free(moved);
                allocator.free(record.fields);
                allocator.destroy(record);
            }
        }
    }

    fn enqueueRelease(value: Value, pending: *?*Aggregate, allocator: std.mem.Allocator) void {
        if (value == .managed) {
            value.managed.release();
            return;
        }
        if (value == .owned) {
            value.owned.release(allocator);
            return;
        }
        if (value != .aggregate) return;
        const record = value.aggregate;
        std.debug.assert(record.references != 0);
        record.references -= 1;
        if (record.references == 0) {
            record.release_index = record.fields.len;
            record.next = pending.*;
            pending.* = record;
        }
    }
};

/// Reference-counted aggregate fields with variant and partial-move bookkeeping.
pub const Aggregate = struct {
    /// A moved slot contains a stale value representation and must never be read
    /// or released. Only the separately transferred owner may access that value.
    moved_fields: ?[]bool = null,
    active_tag: ?usize = null,
    ty: Type,
    fields: []const Value,
    references: usize = 1,
    next: ?*Aggregate = null,
    release_index: usize = 0,
};

/// Stable object identity; resizing backing storage never moves this header.
/// Managed collection family and shape (`type_identity.zig`).
pub const ManagedKind = identity.ManagedKind;
/// Collection shape metadata of a managed record (`type_identity.zig`).
pub const CollectionShape = identity.CollectionShape;

/// Collector mark bit and the arena nesting depth that owns one managed object.
/// Depth 0 is the ordinary heap; depth k is the k-th nested active arena scope.
pub const ObjectTrace = struct { marked: bool = false, region: u32 = 0 };

/// Stable GC identity with representation-specific collection metadata.
pub const ManagedObject = struct {
    collection: CollectionShape = .{},
    heap: *anyopaque,
    ty: Type,
    element_type: Type,
    items: std.ArrayList(Value) = .empty,
    references: usize = 1,
    next: ?*ManagedObject = null,
    trace: ObjectTrace = .{},

    /// Acquire another VM, aggregate, or heap-edge reference.
    pub fn retain(self: *ManagedObject) void {
        self.references += 1;
    }
    /// Drop a reference; tracing, rather than reference count zero, frees storage.
    pub fn release(self: *ManagedObject) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
    }
    /// Read an independent retained element from an aliased list.
    pub fn get(self: *ManagedObject, index: usize) error{Bounds}!Value {
        if (index >= self.items.items.len) return error.Bounds;
        return self.items.items[index].retain();
    }
};

/// Reference-counted wrapper for an owned guest memory allocation.
/// Reference-counted external owner; a null owner records completed or transferred ownership.
pub const ExternalResource = struct { ty: Type, store: *external_resources.Store, owner: ?external_resources.Owner, references: usize = 1 };

/// Inert environment authority tied to a single execution identity.
pub const EnvironmentCapability = struct { execution: u64 };

/// Resource categories whose retained wrappers own a runtime cleanup obligation.
pub const OwnedValue = union(enum) {
    external_resource: *ExternalResource,

    fn typeOf(self: OwnedValue) Type {
        return switch (self) {
            .external_resource => |resource| resource.ty,
        };
    }
    fn retain(self: OwnedValue) void {
        switch (self) {
            .external_resource => |resource| resource.references += 1,
        }
    }
    fn release(self: OwnedValue, allocator: std.mem.Allocator) void {
        const resource = self.external_resource;
        std.debug.assert(resource.references != 0);
        resource.references -= 1;
        if (resource.references == 0) {
            if (resource.owner) |owner| _ = resource.store.releaseIfLive(owner);
            allocator.destroy(resource);
        }
    }
};

/// Inert grants whose authority is checked by their associated execution store.
pub const CapabilityValue = union(enum) {
    environment_capability: EnvironmentCapability,
    resource_capability: external_resources.Capability,
    external: @import("external_capabilities.zig").Capability,

    fn typeOf(self: CapabilityValue) Type {
        return switch (self) {
            .environment_capability => .environment_cap,
            .resource_capability => |cap| if (cap.kind == .filesystem) .filesystem_cap else .network_cap,
            .external => |cap| switch (cap.kind) {
                .clock => .clock_cap,
                .random => .random_cap,
            },
        };
    }
};
