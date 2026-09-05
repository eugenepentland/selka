//! Immutable aggregate storage. Every VM operand/local owns one retained value.
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
    _,
    pub const record_base: usize = 9;
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

    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .i64 => .i64,
            .bool => .bool,
            .integer => |n| n.ty,
            .aggregate => |record| record.ty,
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
        if (self != .aggregate or indices.len != replacements.len) return error.InternalError;
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

    pub fn retain(self: Value) Value {
        if (self == .aggregate) self.aggregate.references += 1;
        return self;
    }

    /// Release without allocation or recursive host calls. Zero-reference nodes
    /// temporarily form an intrusive work list; immutable live nodes never change.
    pub fn release(self: Value, allocator: std.mem.Allocator) void {
        var pending: ?*Aggregate = null;
        enqueueRelease(self, &pending);
        while (pending) |record| {
            pending = record.next;
            for (record.fields) |field| enqueueRelease(field, &pending);
            allocator.free(record.fields);
            allocator.destroy(record);
        }
    }

    fn enqueueRelease(value: Value, pending: *?*Aggregate) void {
        if (value != .aggregate) return;
        const record = value.aggregate;
        std.debug.assert(record.references != 0);
        record.references -= 1;
        if (record.references == 0) {
            record.next = pending.*;
            pending.* = record;
        }
    }

    pub fn getField(self: Value, index: usize) error{InternalError}!Value {
        if (self != .aggregate or index >= self.aggregate.fields.len) return error.InternalError;
        return self.aggregate.fields[index].retain();
    }
};

pub const Aggregate = struct {
    active_tag: ?usize = null,
    ty: Type,
    fields: []const Value,
    references: usize = 1,
    next: ?*Aggregate = null,
};
