//! Bounded structural validation and copying across host allocator boundaries.
const std = @import("std");
const typed = @import("typed.zig");
pub const Limits = struct { max_values: usize = 65536, max_depth: u8 = 64 };
pub const Copier = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    limits: Limits = .{},
    values: usize = 0,
    pub fn copy(self: *Copier, ty: typed.Type, input: typed.Value) !typed.Value {
        if (self.limits.max_values == 0 or self.limits.max_depth == 0 or self.limits.max_depth > 128) return error.InvalidValueLimits;
        try @import("data_type.zig").check(self.allocator, self.records, ty, true);
        return self.inner(ty, input, 1);
    }
    fn inner(self: *Copier, ty: typed.Type, input: typed.Value, depth: usize) anyerror!typed.Value {
        if (depth > self.limits.max_depth) return error.ValueDepthLimit;
        if (self.values == self.limits.max_values) return error.ValueCountLimit;
        self.values += 1;
        if (input.typeOf() != ty) return error.ValueTypeMismatch;
        if (ty.isInteger()) {
            const number = input.asInteger() catch return error.InvalidDataValue;
            if (!ty.fits(number)) return error.InvalidDataValue;
            return typed.Value.number(ty, number);
        }
        if (ty == .bool) return if (input == .bool) input else error.InvalidDataValue;
        if (input != .aggregate or input.aggregate.moved_fields != null) return error.InvalidDataValue;
        const record = self.records[ty.recordIndex()];
        const fields = input.aggregate.fields;
        var count: usize = undefined;
        var payload: ?typed.Type = null;
        if (record.variants) |variants| {
            const tag = input.aggregate.active_tag orelse return error.InvalidDataValue;
            if (tag >= variants.cases.len) return error.InvalidDataValue;
            payload = variants.cases[tag].payload;
            count = @intFromBool(payload != null);
        } else {
            if (input.aggregate.active_tag != null) return error.InvalidDataValue;
            count = if (record.domain != null) 1 else record.count();
        }
        if (fields.len != count) return error.InvalidDataValue;
        if (count > self.limits.max_values - self.values) return error.ValueCountLimit;
        const copied = try self.allocator.alloc(typed.Value, count);
        var initialized: usize = 0;
        defer {
            for (copied[0..initialized]) |value| value.release(self.allocator);
            self.allocator.free(copied);
        }
        for (copied, fields, 0..) |*out, field, index| {
            const child_type = record.domain orelse payload orelse record.elementType(index);
            out.* = try self.inner(child_type, field, depth + 1);
            initialized += 1;
        }
        const value = try typed.Value.create(self.allocator, ty, copied);
        value.aggregate.active_tag = input.aggregate.active_tag;
        return value;
    }
};
