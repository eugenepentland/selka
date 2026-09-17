//! Immutable ordinary aggregates and unique owned records with field transfer.
//! Every VM operand/local owns one retained value.
const std = @import("std");
const external_resources = @import("external_resources.zig");
const runtime_values = @This();
/// Scalar and nominal type identities shared by checked syntax and runtime values.
pub const Type = enum(usize) {
    i64,
    bool,
    i8,
    i16,
    i32,
    u8,
    u16,
    u32,
    u64,
    clock_cap,
    random_cap,
    filesystem_cap,
    network_cap,
    environment_cap,
    /// The authority behind an `extern def` or `host def`; checked at every call
    /// and dropped before the foreign call itself.
    host_cap,
    unit,
    /// An open byte-oriented file owned by the guest through a `with` scope.
    file,
    /// An open UTF-8 text file; its reads produce `str` rather than `bytes`.
    text_file,
    _,
    pub const record_base: usize = 18;
    /// Return the compact builtin capability index, or null for non-capabilities.
    pub fn capabilityIndex(self: Type) ?u3 {
        return switch (self) {
            .clock_cap => 0,
            .random_cap => 1,
            .filesystem_cap => 2,
            .network_cap => 3,
            .environment_cap => 4,
            .host_cap => 5,
            else => null,
        };
    }
    /// Return the external resource family represented by this builtin type.
    pub fn resourceKind(self: Type) ?external_resources.Kind {
        return switch (self) {
            .filesystem_cap => .filesystem,
            .network_cap => .network,
            else => null,
        };
    }
    /// Identify an open file handle, whose cleanup closes a provider resource.
    pub fn isFile(self: Type) bool {
        return self == .file or self == .text_file;
    }
    /// Integer width and signedness used for range checks and native layout.
    pub const Integer = struct { bits: u7, signed: bool };
    /// Return integer width and signedness, or null for other types.
    pub fn integer(self: Type) ?Integer {
        return switch (self) {
            .i8 => .{ .bits = 8, .signed = true },
            .i16 => .{ .bits = 16, .signed = true },
            .i32 => .{ .bits = 32, .signed = true },
            .i64 => .{ .bits = 64, .signed = true },
            .u8 => .{ .bits = 8, .signed = false },
            .u16 => .{ .bits = 16, .signed = false },
            .u32 => .{ .bits = 32, .signed = false },
            .u64 => .{ .bits = 64, .signed = false },
            else => null,
        };
    }
    /// Identify builtin signed and unsigned integer types.
    pub fn isInteger(self: Type) bool {
        return self.integer() != null;
    }
    /// Identify a nominal aggregate identity rather than a builtin scalar.
    pub fn isAggregate(self: Type) bool {
        return @backingInt(self) >= record_base;
    }
    /// Convert a nominal type identity into its schema table index.
    pub fn recordIndex(self: Type) usize {
        return @backingInt(self) - record_base;
    }
    /// Return the mathematical lower bound for this integer type.
    pub fn min(self: Type) i128 {
        const info = self.integer().?;
        return if (info.signed) -(@as(i128, 1) << (info.bits - 1)) else 0;
    }
    /// Return the mathematical upper bound for this integer type.
    pub fn max(self: Type) i128 {
        const info = self.integer().?;
        return (@as(i128, 1) << (info.bits - @as(u7, if (info.signed) 1 else 0))) - 1;
    }
    /// Check whether a mathematical integer lies within this type's bounds.
    pub fn fits(self: Type, value: i128) bool {
        return value >= self.min() and value <= self.max();
    }
    /// Canonical external decimal spelling shared by manifests and codecs.
    /// Language source literals have their own lexer and may use width suffixes.
    pub fn parseDecimal(self: Type, text: []const u8) error{ InvalidInteger, IntegerOutOfRange }!i128 {
        if (!self.isInteger() or text.len == 0 or text.len > 20) return error.InvalidInteger;
        const negative = text[0] == '-';
        const digits = text[@intFromBool(negative)..];
        if (digits.len == 0 or (digits[0] == '0' and (digits.len != 1 or negative))) return error.InvalidInteger;
        for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidInteger;
        const value = std.fmt.parseInt(i128, text, 10) catch return error.InvalidInteger;
        if (!self.fits(value)) return error.IntegerOutOfRange;
        return value;
    }
    /// Resolve a builtin type spelling without consulting nominal schemas.
    pub fn fromName(name: []const u8) ?Type {
        if (name.len == 0 or std.mem.eql(u8, name, "None")) return .unit;
        if (std.mem.eql(u8, name, "int")) return .i64;
        if (name.len >= 2 and name[0] == '(' and name[name.len - 1] == ')') {
            if (std.mem.trim(u8, name[1 .. name.len - 1], " \t\r\n").len == 0) return .unit;
        }
        return std.meta.stringToEnum(Type, name);
    }
    pub fn format(self: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isAggregate()) try writer.print("type#{d}", .{@backingInt(self)}) else try writer.writeAll(@tagName(self));
    }
};

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

    /// Test an authority category without reading an inactive union field.
    pub fn isCapability(self: Value, kind: std.meta.Tag(CapabilityValue)) bool {
        return self == .capability and self.capability == kind;
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

    /// Read and retain an initialized aggregate field, rejecting moved or missing fields.
    pub fn getField(self: Value, index: usize) error{InternalError}!Value {
        if (self != .aggregate or index >= self.aggregate.fields.len) return error.InternalError;
        if (self.aggregate.moved_fields) |moved| if (moved[index]) return error.InternalError;
        return self.aggregate.fields[index].retain();
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
/// Managed collection representation family.
pub const ManagedKind = enum { list, string, dictionary, bytes };

/// Representation metadata shared by checked schemas and GC headers.
pub const CollectionShape = struct { kind: ManagedKind = .list, key: ?Type = null, contains_cell: bool = false };

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
