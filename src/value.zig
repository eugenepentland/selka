//! Immutable ordinary aggregates and unique owned records with field transfer.
//! Every VM operand/local owns one retained value.
const std = @import("std");
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
    allocator,
    clock_cap,
    random_cap,
    filesystem_cap,
    network_cap,
    environment_cap,
    _,
    pub const record_base: usize = 15;
    pub fn capabilityIndex(self: Type) ?u3 {
        return switch (self) {
            .allocator => 0,
            .clock_cap => 1,
            .random_cap => 2,
            .filesystem_cap => 3,
            .network_cap => 4,
            .environment_cap => 5,
            else => null,
        };
    }
    pub fn resourceKind(self: Type) ?@import("external_resources.zig").Kind {
        return switch (self) {
            .filesystem_cap => .filesystem,
            .network_cap => .network,
            else => null,
        };
    }
    pub fn externalKind(self: Type) ?@import("external_capabilities.zig").Kind {
        return switch (self) {
            .clock_cap => .clock,
            .random_cap => .random,
            else => null,
        };
    }
    pub const Integer = struct { bits: u7, signed: bool };
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
    pub fn isInteger(self: Type) bool {
        return self.integer() != null;
    }
    pub fn isAggregate(self: Type) bool {
        return @backingInt(self) >= record_base;
    }
    pub fn recordIndex(self: Type) usize {
        return @backingInt(self) - record_base;
    }
    pub fn min(self: Type) i128 {
        const info = self.integer().?;
        return if (info.signed) -(@as(i128, 1) << (info.bits - 1)) else 0;
    }
    pub fn max(self: Type) i128 {
        const info = self.integer().?;
        return (@as(i128, 1) << (info.bits - @as(u7, if (info.signed) 1 else 0))) - 1;
    }
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
    pub fn fromName(name: []const u8) ?Type {
        return std.meta.stringToEnum(Type, name);
    }
    pub fn format(self: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.isAggregate()) try writer.print("type#{d}", .{@backingInt(self)}) else try writer.writeAll(@tagName(self));
    }
};

pub const Value = union(enum) {
    i64: i64,
    bool: bool,
    integer: struct { ty: Type, value: i128 },
    aggregate: *Aggregate,
    resource: *Resource,
    external_resource: *ExternalResource,
    pool: *@import("pool_runtime.zig").Owner,
    handle: struct { ty: Type, id: @import("pool_runtime.zig").Id },
    environment_capability: @import("environment.zig").Capability,
    resource_capability: @import("external_resources.zig").Capability,
    allocator: @import("memory.zig").AllocatorCapability,
    external: @import("external_capabilities.zig").Capability,

    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .pool => |owner| owner.ty,
            .handle => |handle| handle.ty,
            .allocator => .allocator,
            .environment_capability => .environment_cap,
            .external_resource => |resource| resource.ty,
            .resource_capability => |cap| if (cap.kind == .filesystem) .filesystem_cap else .network_cap,
            .external => |capability| switch (capability.kind) {
                .clock => .clock_cap,
                .random => .random_cap,
            },
            .i64 => .i64,
            .bool => .bool,
            .integer => |n| n.ty,
            .aggregate => |record| record.ty,
            .resource => |resource| resource.ty,
        };
    }

    pub fn number(ty: Type, value: i128) Value {
        std.debug.assert(ty.isInteger() and ty.fits(value));
        return if (ty == .i64) .{ .i64 = @intCast(value) } else .{ .integer = .{ .ty = ty, .value = value } };
    }
    pub fn asInteger(self: Value) error{InternalError}!i128 {
        return switch (self) {
            .i64 => |n| n,
            .integer => |n| n.value,
            else => error.InternalError,
        };
    }
    /// Borrow input fields; the returned value owns independent references.
    pub fn create(allocator: std.mem.Allocator, ty: Type, fields: []const Value) !Value {
        if (!ty.isAggregate()) return error.InvalidAggregateType;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, owned) |field, *out| out.* = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    pub fn createVariant(allocator: std.mem.Allocator, ty: Type, tag: usize, payload: ?Value) !Value {
        const value = try create(allocator, ty, if (payload) |input| &.{input} else &.{});
        value.aggregate.active_tag = tag;
        return value;
    }
    pub fn variantTag(self: Value) error{InternalError}!usize {
        if (self != .aggregate) return error.InternalError;
        return self.aggregate.active_tag orelse error.InternalError;
    }

    /// Input expressions are already evaluated in source order. Store in schema order.
    /// The emitter validates that order is a permutation before dispatch.
    pub fn createOrdered(allocator: std.mem.Allocator, ty: Type, fields: []const Value, order: []const usize) !Value {
        if (order.len == 0) return create(allocator, ty, fields);
        if (!ty.isAggregate() or order.len != fields.len) return error.InternalError;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, order) |field, index| owned[index] = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    pub fn updated(self: Value, allocator: std.mem.Allocator, indices: []const usize, replacements: []const Value) !Value {
        if (self != .aggregate or self.aggregate.moved_fields != null or indices.len != replacements.len) return error.InternalError;
        for (indices) |index| if (index >= self.aggregate.fields.len) {
            return error.InternalError;
        };
        const out = try create(allocator, self.aggregate.ty, self.aggregate.fields);
        const fields = @constCast(out.aggregate.fields);
        for (indices, replacements) |index, replacement| {
            fields[index].release(allocator);
            fields[index] = replacement.retain();
        }
        return out;
    }

    /// Success consumes the external allocation handle; failure leaves it owned
    /// by the caller. Internal retained temporaries share one cleanup record.
    pub fn ownBuffer(allocator: std.mem.Allocator, ty: Type, store: *@import("memory.zig").Store, owner: @import("memory.zig").Allocation) !Value {
        const resource = try allocator.create(Resource);
        errdefer allocator.destroy(resource);
        const moved = try store.transfer(owner);
        resource.* = .{ .ty = ty, .store = store, .owner = moved };
        return .{ .resource = resource };
    }
    pub fn ownExternal(allocator: std.mem.Allocator, ty: Type, store: *@import("external_resources.zig").Store, owner: @import("external_resources.zig").Owner) !Value {
        const resource = try allocator.create(ExternalResource);
        errdefer allocator.destroy(resource);
        const moved = try store.transfer(owner);
        resource.* = .{ .ty = ty, .store = store, .owner = moved };
        return .{ .external_resource = resource };
    }
    pub fn retain(self: Value) Value {
        if (self == .pool) self.pool.references += 1;
        if (self == .external_resource) self.external_resource.references += 1;
        if (self == .resource) self.resource.references += 1;
        if (self == .aggregate) self.aggregate.references += 1;
        return self;
    }

    /// Release without allocation or recursive host calls. Zero-reference nodes
    /// temporarily form an intrusive work list; shared live nodes never change.
    pub fn release(self: Value, allocator: std.mem.Allocator) void {
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
        if (value == .pool) {
            value.pool.release();
            return;
        }
        if (value == .external_resource) {
            const resource = value.external_resource;
            std.debug.assert(resource.references != 0);
            resource.references -= 1;
            if (resource.references == 0) {
                if (resource.owner) |owner| resource.store.release(owner) catch {};
                allocator.destroy(resource);
            }
            return;
        }
        if (value == .resource) {
            const resource = value.resource;
            std.debug.assert(resource.references != 0);
            resource.references -= 1;
            if (resource.references == 0) {
                resource.store.destroyForUnwind(resource.owner) catch {};
                allocator.destroy(resource);
            }
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

    /// Transfer one field from a unique aggregate without retaining it. Missing
    /// slots are tracked separately so cleanup never touches transferred values.
    /// Allocate bookkeeping before transfer; failure leaves the aggregate intact.
    pub fn takeField(self: Value, allocator: std.mem.Allocator, index: usize) !Value {
        if (self != .aggregate or self.aggregate.references != 1 or self.aggregate.active_tag != null or index >= self.aggregate.fields.len) return error.InternalError;
        const record = self.aggregate;
        if (record.moved_fields == null) {
            const moved = try allocator.alloc(bool, record.fields.len);
            @memset(moved, false);
            record.moved_fields = moved;
        }
        if (record.moved_fields.?[index]) return error.InternalError;
        record.moved_fields.?[index] = true;
        return record.fields[index];
    }

    pub fn getField(self: Value, index: usize) error{InternalError}!Value {
        if (self != .aggregate or index >= self.aggregate.fields.len) return error.InternalError;
        if (self.aggregate.moved_fields) |moved| if (moved[index]) return error.InternalError;
        return self.aggregate.fields[index].retain();
    }
};

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

pub const Resource = struct { ty: Type, store: *@import("memory.zig").Store, owner: @import("memory.zig").Allocation, references: usize = 1 };

pub const ExternalResource = struct { ty: Type, store: *@import("external_resources.zig").Store, owner: ?@import("external_resources.zig").Owner, references: usize = 1 };
