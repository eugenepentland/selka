//! Immutable aggregate storage. Every VM operand/local owns one retained value.
const std = @import("std");
pub const Type = enum(usize) {
    i64,
    bool,
    _,
    pub fn format(self: Type, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .i64 => try writer.writeAll("i64"),
            .bool => try writer.writeAll("bool"),
            else => try writer.print("type#{d}", .{@backingInt(self)}),
        }
    }
};

pub const Value = union(enum) {
    i64: i64,
    bool: bool,
    aggregate: *Aggregate,

    pub fn typeOf(self: Value) Type {
        return switch (self) {
            .i64 => .i64,
            .bool => .bool,
            .aggregate => |record| record.ty,
        };
    }

    /// Borrow input fields; the returned value owns independent references.
    pub fn create(allocator: std.mem.Allocator, ty: Type, fields: []const Value) !Value {
        if (ty == .i64 or ty == .bool) return error.InvalidAggregateType;
        const record = try allocator.create(Aggregate);
        errdefer allocator.destroy(record);
        const owned = try allocator.alloc(Value, fields.len);
        for (fields, owned) |field, *out| out.* = field.retain();
        record.* = .{ .ty = ty, .fields = owned };
        return .{ .aggregate = record };
    }

    /// Input expressions are already evaluated in source order. Store in schema order.
    /// The emitter validates that order is a permutation before dispatch.
    pub fn createOrdered(allocator: std.mem.Allocator, ty: Type, fields: []const Value, order: []const usize) !Value {
        if (order.len == 0) return create(allocator, ty, fields);
        if (ty == .i64 or ty == .bool or order.len != fields.len) return error.InternalError;
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
    ty: Type,
    fields: []const Value,
    references: usize = 1,
    next: ?*Aggregate = null,
};
