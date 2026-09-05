//! In-memory instructions and a small emission-time stack-height/target check.
const std = @import("std");
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
pub const Equality = enum { eq, ne };
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        push_i64: i64,
        push_bool: bool,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        unwrap_domain: typed.Type,
        neg_integer: typed.Type,
        binary_integer: struct { ty: typed.Type, op: typed.BinaryOp },
        make_record: struct { ty: typed.Type, fields: usize, order: []const usize = &.{} },
        update_record: struct { ty: typed.Type, indices: []const usize },
        get_field: usize,
        get_index: typed.Type,
        replace_index: typed.Type,
        array_length: typed.Type,
        load_local: typed.LocalId,
        store_local: typed.LocalId,
        add_i64_checked,
        sub_i64_checked,
        mul_i64_checked,
        div_i64_checked,
        rem_i64_checked,
        neg_i64_checked,
        cmp_i64: Predicate,
        cmp_bool: Equality,
        not_bool,
        pop,
        jump: usize,
        jump_if_false: usize,
        call: typed.FunctionId,
        ret,
    },
};
pub const Function = struct { owner: ?typed.Type = null, restricted: bool = false, conversion: bool = false, id: typed.FunctionId, name: []const u8, parameter_count: usize = 0, return_type: typed.Type = .i64, locals: []const typed.Local = &.{}, instructions: []const Instruction };
pub const Program = struct { functions: []const Function, main: typed.FunctionId = @fromBackingInt(0), records: []const typed.Record = &.{} };
const Error = std.mem.Allocator.Error || error{InternalError};

fn enqueue(heights: []?usize, pending: []usize, len: *usize, target: usize, height: usize) Error!void {
    if (target >= heights.len) return error.InternalError;
    if (heights[target]) |existing| {
        if (existing != height) return error.InternalError;
    } else {
        heights[target] = height;
        pending[len.*] = target;
        len.* += 1;
    }
}
/// Validate generated IDs, targets, and stack heights at control-flow joins.
/// Operand types and initialization remain checked by the VM; there is no untrusted loader.
pub fn validate(allocator: std.mem.Allocator, program: Program) Error!void {
    if (@backingInt(program.main) >= program.functions.len) return error.InternalError;
    for (program.records, 0..) |record, i| {
        if (@backingInt(record.id) != i + typed.Type.record_base) return error.InternalError;
        if (record.domain) |backing| {
            if ((!backing.isInteger() and backing != .bool) or record.fields.len != 0 or record.array != null) return error.InternalError;
        }
        if (record.array) |array| {
            if (!validType(array.element, program) or record.fields.len != 0 or array.length > std.math.maxInt(usize) / @sizeOf(typed.Value)) return error.InternalError;
        }
        for (record.fields) |field| if (!validType(field.ty, program)) {
            return error.InternalError;
        };
    }
    const main = program.functions[@backingInt(program.main)];
    if (main.parameter_count != 0 or main.return_type != .i64 or main.owner != null or main.restricted) return error.InternalError;
    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.id) != i or function.instructions.len == 0) return error.InternalError;
        if (function.owner) |owner| {
            if (!owner.isAggregate() or !validType(owner, program) or program.records[owner.recordIndex()].domain == null) return error.InternalError;
        } else if (function.restricted) return error.InternalError;
        if (function.parameter_count > function.locals.len or !validType(function.return_type, program)) return error.InternalError;
        for (function.locals) |local| if (!validType(local.ty, program)) {
            return error.InternalError;
        };
        for (function.instructions) |instruction| switch (instruction.op) {
            .push_integer => |number| {
                if (!number.ty.isInteger() or !number.ty.fits(number.value)) return error.InternalError;
            },
            .cast_integer, .neg_integer => |ty| if (!ty.isInteger()) {
                return error.InternalError;
            },
            .binary_integer => |binary| {
                if (!binary.ty.isInteger() or binary.op == .logical_and or binary.op == .logical_or) return error.InternalError;
            },
            .load_local, .store_local => |slot| if (@backingInt(slot) >= function.locals.len) {
                return error.InternalError;
            },
            .wrap_domain, .unwrap_domain => |ty| {
                if (function.owner != ty or !ty.isAggregate() or !validType(ty, program) or program.records[ty.recordIndex()].domain == null) return error.InternalError;
            },
            .make_record => |record| {
                if (!record.ty.isAggregate() or !validType(record.ty, program)) return error.InternalError;
                if (program.records[record.ty.recordIndex()].domain != null) return error.InternalError;
                if (record.fields != program.records[record.ty.recordIndex()].count()) return error.InternalError;
                if (record.order.len != 0) {
                    if (record.order.len != record.fields) return error.InternalError;
                    try validateIndices(allocator, record.order, record.fields);
                }
            },
            .get_index, .replace_index, .array_length => |ty| {
                if (!ty.isAggregate() or !validType(ty, program) or program.records[ty.recordIndex()].array == null) return error.InternalError;
            },
            .update_record => |update| {
                if (!update.ty.isAggregate() or update.ty.recordIndex() >= program.records.len) return error.InternalError;
                if (program.records[update.ty.recordIndex()].array != null or program.records[update.ty.recordIndex()].domain != null) return error.InternalError;
                try validateIndices(allocator, update.indices, program.records[update.ty.recordIndex()].fields.len);
            },
            .call => |id| {
                if (@backingInt(id) >= program.functions.len) return error.InternalError;
                const callee = program.functions[@backingInt(id)];
                if (callee.restricted and function.owner != callee.owner) return error.InternalError;
            },
            .jump, .jump_if_false => |target| if (target >= function.instructions.len) {
                return error.InternalError;
            },
            else => {},
        };
        const heights = try allocator.alloc(?usize, function.instructions.len);
        defer allocator.free(heights);
        @memset(heights, null);
        const pending = try allocator.alloc(usize, function.instructions.len);
        defer allocator.free(pending);
        var len: usize = 0;
        try enqueue(heights, pending, &len, 0, 0);
        while (len != 0) {
            len -= 1;
            const pc = pending[len];
            const instruction = function.instructions[pc];
            var height = heights[pc].?;
            switch (instruction.op) {
                .push_i64, .push_bool, .push_integer, .load_local => height += 1,
                .make_record => |record| {
                    if (height < record.fields) return error.InternalError;
                    height = height - record.fields + 1;
                },
                .replace_index => {
                    if (height < 3) return error.InternalError;
                    height -= 2;
                },
                .update_record => |update| {
                    if (height <= update.indices.len) return error.InternalError;
                    height -= update.indices.len;
                },
                .store_local, .pop, .jump_if_false => {
                    if (height == 0) return error.InternalError;
                    height -= 1;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool, .binary_integer, .get_index => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .neg_i64_checked, .not_bool, .get_field, .cast_integer, .neg_integer, .array_length, .wrap_domain, .unwrap_domain => if (height == 0) {
                    return error.InternalError;
                },
                .call => |id| {
                    const count = program.functions[@backingInt(id)].parameter_count;
                    if (height < count) return error.InternalError;
                    height = height - count + 1;
                },
                .ret => {
                    if (height != 1) return error.InternalError;
                    continue;
                },
                .jump => {},
            }
            if (instruction.op == .jump) {
                try enqueue(heights, pending, &len, instruction.op.jump, height);
            } else {
                if (instruction.op == .jump_if_false) try enqueue(heights, pending, &len, instruction.op.jump_if_false, height);
                try enqueue(heights, pending, &len, pc + 1, height);
            }
        }
    }
}

fn validateIndices(allocator: std.mem.Allocator, indices: []const usize, count: usize) Error!void {
    const seen = try allocator.alloc(bool, count);
    defer allocator.free(seen);
    @memset(seen, false);
    for (indices) |index| {
        if (index >= count or seen[index]) return error.InternalError;
        seen[index] = true;
    }
}

fn validType(ty: typed.Type, program: Program) bool {
    return ty.isInteger() or ty == .bool or (ty.isAggregate() and ty.recordIndex() < program.records.len);
}
