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
        make_record: struct { ty: typed.Type, fields: usize, order: []const usize = &.{} },
        update_record: struct { ty: typed.Type, indices: []const usize },
        get_field: usize,
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
pub const Function = struct { conversion: bool = false, id: typed.FunctionId, name: []const u8, parameter_count: usize = 0, return_type: typed.Type = .i64, locals: []const typed.Local = &.{}, instructions: []const Instruction };
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
        if (@backingInt(record.id) != i + 2) return error.InternalError;
        for (record.fields) |field| if (!validType(field.ty, program)) {
            return error.InternalError;
        };
    }
    const main = program.functions[@backingInt(program.main)];
    if (main.parameter_count != 0 or main.return_type != .i64) return error.InternalError;
    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.id) != i or function.instructions.len == 0) return error.InternalError;
        if (function.parameter_count > function.locals.len or !validType(function.return_type, program)) return error.InternalError;
        for (function.locals) |local| if (!validType(local.ty, program)) {
            return error.InternalError;
        };
        for (function.instructions) |instruction| switch (instruction.op) {
            .load_local, .store_local => |slot| if (@backingInt(slot) >= function.locals.len) {
                return error.InternalError;
            },
            .make_record => |record| {
                if (record.ty == .i64 or record.ty == .bool or !validType(record.ty, program)) return error.InternalError;
                if (record.fields != program.records[@backingInt(record.ty) - 2].fields.len) return error.InternalError;
                if (record.order.len != 0) {
                    if (record.order.len != record.fields) return error.InternalError;
                    try validateIndices(allocator, record.order, record.fields);
                }
            },
            .update_record => |update| {
                if (update.ty == .i64 or update.ty == .bool or @backingInt(update.ty) - 2 >= program.records.len) return error.InternalError;
                try validateIndices(allocator, update.indices, program.records[@backingInt(update.ty) - 2].fields.len);
            },
            .call => |id| if (@backingInt(id) >= program.functions.len) {
                return error.InternalError;
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
                .push_i64, .push_bool, .load_local => height += 1,
                .make_record => |record| {
                    if (height < record.fields) return error.InternalError;
                    height = height - record.fields + 1;
                },
                .update_record => |update| {
                    if (height <= update.indices.len) return error.InternalError;
                    height -= update.indices.len;
                },
                .store_local, .pop, .jump_if_false => {
                    if (height == 0) return error.InternalError;
                    height -= 1;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .neg_i64_checked, .not_bool, .get_field => if (height == 0) {
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
    return ty == .i64 or ty == .bool or @backingInt(ty) - 2 < program.records.len;
}
