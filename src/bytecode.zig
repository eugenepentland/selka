//! In-memory instructions and a small emission-time stack-height/target check.
const std = @import("std");
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
pub const Equality = enum { eq, ne };
pub const SwitchArm = struct { target: usize, slot: ?typed.LocalId };
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        push_i64: i64,
        push_bool: bool,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        make_variant: struct { ty: typed.Type, tag: usize },
        switch_variant: struct { ty: typed.Type, arms: []const SwitchArm },
        cmp_enum: struct { ty: typed.Type, predicate: Equality },
        unwrap_domain: typed.Type,
        neg_integer: typed.Type,
        binary_integer: struct { ty: typed.Type, op: typed.BinaryOp },
        make_record: struct { ty: typed.Type, fields: usize, order: []const usize = &.{} },
        update_record: struct { ty: typed.Type, indices: []const usize },
        get_field: usize,
        get_index: typed.Type,
        replace_index: typed.Type,
        array_length: typed.Type,
        begin_borrow: typed.ReferenceId,
        end_borrow: typed.ReferenceId,
        read_ref: typed.ReferenceId,
        write_ref: typed.ReferenceId,
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
        call_refs: struct { function: typed.FunctionId, references: []const typed.ReferenceId },
        ret,
    },
};
pub const Function = struct { references: []const typed.Reference = &.{}, owner: ?typed.Type = null, restricted: bool = false, conversion: bool = false, id: typed.FunctionId, name: []const u8, parameter_count: usize = 0, return_type: typed.Type = .i64, locals: []const typed.Local = &.{}, instructions: []const Instruction };
pub const Program = struct { functions: []const Function, main: typed.FunctionId = @fromBackingInt(0), records: []const typed.Record = &.{} };
pub fn valueParameterCount(function: Function) usize {
    var count: usize = 0;
    for (function.locals[0..function.parameter_count]) |local| if (local.reference_parameter == null) {
        count += 1;
    };
    return count;
}
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
        if (record.variants) |variants| {
            if (record.array != null or record.domain != null or record.fields.len != 0 or variants.cases.len == 0) return error.InternalError;
            for (variants.cases) |variant| if (variant.payload) |ty| {
                if (!variants.is_union or !validType(ty, program)) return error.InternalError;
            };
        }
        if (record.domain) |backing| {
            if ((!backing.isInteger() and backing != .bool) or record.fields.len != 0 or record.array != null) return error.InternalError;
        }
        if (record.array) |array| {
            if (!validType(array.element, program) or array.length > std.math.maxInt(usize) / @sizeOf(typed.Value)) return error.InternalError;
            if (array.key) |key| {
                const variants = try variantSchema(key, program);
                if (variants.is_union or variants.cases.len != array.length or record.fields.len != array.length) return error.InternalError;
                for (record.fields, variants.cases) |field, variant| if (field.ty != array.element or !std.mem.eql(u8, field.name, variant.name)) return error.InternalError;
            } else if (record.fields.len != 0) return error.InternalError;
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
        for (function.references, 0..) |reference, index| {
            if (@backingInt(reference.owner) >= function.locals.len or reference.ty != function.locals[@backingInt(reference.owner)].ty) return error.InternalError;
            if (reference.parent) |parent| {
                if (@backingInt(parent) >= index) return error.InternalError;
                const previous = function.references[@backingInt(parent)];
                if (previous.owner != reference.owner or (reference.mutable and !previous.mutable)) return error.InternalError;
            } else if (!reference.parameter and reference.mutable and !function.locals[@backingInt(reference.owner)].mutable) return error.InternalError;
            if (!reference.parameter and reference.parent == null and function.locals[@backingInt(reference.owner)].reference_parameter != null) return error.InternalError;
            if (reference.parameter and index > 0 and (!function.references[index - 1].parameter or @backingInt(function.references[index - 1].owner) >= @backingInt(reference.owner))) return error.InternalError;
            if (reference.parameter and (reference.parent != null or @backingInt(reference.owner) >= function.parameter_count or function.locals[@backingInt(reference.owner)].reference_parameter != reference.mutable)) return error.InternalError;
        }
        for (function.locals, 0..) |local, slot| {
            if (!validType(local.ty, program)) return error.InternalError;
            if (local.reference_parameter != null) {
                if (slot >= function.parameter_count) return error.InternalError;
                var count: usize = 0;
                for (function.references) |reference| if (reference.parameter and @backingInt(reference.owner) == slot) {
                    count += 1;
                };
                if (count != 1) return error.InternalError;
            }
        }
        for (function.instructions) |instruction| switch (instruction.op) {
            .make_variant => |variant| {
                const schema = try variantSchema(variant.ty, program);
                if (variant.tag >= schema.cases.len) return error.InternalError;
            },
            .cmp_enum => |comparison| {
                if ((try variantSchema(comparison.ty, program)).is_union) return error.InternalError;
            },
            .switch_variant => |dispatch| {
                const schema = try variantSchema(dispatch.ty, program);
                if (schema.cases.len != dispatch.arms.len) return error.InternalError;
                for (dispatch.arms, schema.cases) |arm, variant| {
                    if (arm.target >= function.instructions.len) return error.InternalError;
                    if (arm.slot) |slot| {
                        if (@backingInt(slot) >= function.locals.len or variant.payload == null or function.locals[@backingInt(slot)].reference_parameter != null or function.locals[@backingInt(slot)].ty != variant.payload.?) return error.InternalError;
                    }
                }
            },
            .push_integer => |number| {
                if (!number.ty.isInteger() or !number.ty.fits(number.value)) return error.InternalError;
            },
            .cast_integer, .neg_integer => |ty| if (!ty.isInteger()) {
                return error.InternalError;
            },
            .binary_integer => |binary| {
                if (!binary.ty.isInteger() or binary.op == .logical_and or binary.op == .logical_or) return error.InternalError;
            },
            .begin_borrow, .end_borrow, .read_ref, .write_ref => |id| {
                if (@backingInt(id) >= function.references.len) return error.InternalError;
                if (instruction.op == .begin_borrow and function.references[@backingInt(id)].parameter) return error.InternalError;
                if (instruction.op == .write_ref and !function.references[@backingInt(id)].mutable) return error.InternalError;
            },
            .load_local, .store_local => |slot| if (@backingInt(slot) >= function.locals.len or function.locals[@backingInt(slot)].reference_parameter != null) {
                return error.InternalError;
            },
            .wrap_domain, .unwrap_domain => |ty| {
                if (function.owner != ty or !ty.isAggregate() or !validType(ty, program) or program.records[ty.recordIndex()].domain == null) return error.InternalError;
            },
            .make_record => |record| {
                if (!record.ty.isAggregate() or !validType(record.ty, program)) return error.InternalError;
                if (program.records[record.ty.recordIndex()].domain != null or program.records[record.ty.recordIndex()].variants != null) return error.InternalError;
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
                if (!program.records[update.ty.recordIndex()].isRecord()) return error.InternalError;
                try validateIndices(allocator, update.indices, program.records[update.ty.recordIndex()].fields.len);
            },
            .call => |id| {
                if (@backingInt(id) >= program.functions.len) return error.InternalError;
                const callee = program.functions[@backingInt(id)];
                if (callee.parameter_count > callee.locals.len) return error.InternalError;
                if (callee.restricted and function.owner != callee.owner) return error.InternalError;
                if (valueParameterCount(callee) != callee.parameter_count) return error.InternalError;
            },
            .call_refs => |call| {
                if (@backingInt(call.function) >= program.functions.len) return error.InternalError;
                const callee = program.functions[@backingInt(call.function)];
                if (callee.parameter_count > callee.locals.len) return error.InternalError;
                if (callee.restricted and function.owner != callee.owner) return error.InternalError;
                if (call.references.len != callee.parameter_count - valueParameterCount(callee)) return error.InternalError;
                var index: usize = 0;
                for (callee.references) |parameter| if (parameter.parameter) {
                    if (index >= call.references.len) return error.InternalError;
                    const id = call.references[index];
                    index += 1;
                    if (@backingInt(id) >= function.references.len) return error.InternalError;
                    const argument = function.references[@backingInt(id)];
                    if (argument.ty != parameter.ty or (parameter.mutable and !argument.mutable)) return error.InternalError;
                };
                if (index != call.references.len) return error.InternalError;
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
                .push_i64, .push_bool, .push_integer, .load_local, .read_ref => height += 1,
                .make_variant => |variant| {
                    const payload = (try variantSchema(variant.ty, program)).cases[variant.tag].payload;
                    if (payload != null) {
                        if (height == 0) return error.InternalError;
                    } else height += 1;
                },
                .switch_variant => |dispatch| {
                    if (height == 0) return error.InternalError;
                    for (dispatch.arms) |arm| try enqueue(heights, pending, &len, arm.target, height - 1);
                    continue;
                },
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
                .store_local, .pop, .jump_if_false, .write_ref => {
                    if (height == 0) return error.InternalError;
                    height -= 1;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool, .binary_integer, .get_index, .cmp_enum => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .neg_i64_checked, .not_bool, .get_field, .cast_integer, .neg_integer, .array_length, .wrap_domain, .unwrap_domain => if (height == 0) {
                    return error.InternalError;
                },
                .call, .call_refs => {
                    const id = if (instruction.op == .call) instruction.op.call else instruction.op.call_refs.function;
                    const count = valueParameterCount(program.functions[@backingInt(id)]);
                    if (height < count) return error.InternalError;
                    height = height - count + 1;
                },
                .ret => {
                    if (height != 1) return error.InternalError;
                    continue;
                },
                .jump, .begin_borrow, .end_borrow => {},
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

fn variantSchema(ty: typed.Type, program: Program) Error!typed.Variants {
    if (!ty.isAggregate() or !validType(ty, program)) return error.InternalError;
    return program.records[ty.recordIndex()].variants orelse error.InternalError;
}
