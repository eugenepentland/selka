//! In-memory instructions and a small emission-time stack-height/target check.
const std = @import("std");
const FieldAccess = struct { owner: typed.LocalId, field: usize, output: typed.Type };
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
pub const Equality = enum { eq, ne };
pub const SwitchArm = struct { target: usize, slot: ?typed.LocalId };
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        try_result: struct { input: typed.Type, output: typed.Type, error_target: usize },
        push_i64: i64,
        push_bool: bool,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        make_variant: struct { ty: typed.Type, tag: usize },
        switch_variant: struct { ty: typed.Type, arms: []const SwitchArm },
        cmp_handle: struct { ty: typed.Type, predicate: Equality },
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
        begin_slice: typed.ReferenceId,
        read_slice: typed.ReferenceId,
        write_slice: typed.ReferenceId,
        len_slice: typed.ReferenceId,
        end_borrow: typed.ReferenceId,
        read_ref: typed.ReferenceId,
        read_field: FieldAccess,
        take_field: FieldAccess,
        write_ref: typed.ReferenceId,
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        pool_operation: struct { kind: @import("pool_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        complete_resource: typed.Type,
        acquire_resource: struct { output: typed.Type, request: typed.Type },
        resource_io: struct { reference: ?typed.ReferenceId = null, kind: @import("external_resources.zig").IoKind, owner: typed.LocalId, output: typed.Type, input: ?typed.Type },
        restrict_resource: struct { permissions: @import("external_resources.zig").Permissions, ty: typed.Type },
        environment_get: struct { output: typed.Type, name: typed.Type },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, output: typed.Type },
        acquire_pool: typed.Type,
        acquire_buffer: typed.Type,
        move_local: typed.LocalId,
        drop_local: typed.LocalId,
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
        acknowledge: typed.Type,
        jump: usize,
        jump_if_false: usize,
        call: typed.FunctionId,
        call_refs: struct { function: typed.FunctionId, references: []const typed.ReferenceId },
        ret,
        ret_ref,
        capture_ref: typed.ReferenceId,
        call_borrow: struct { function: typed.FunctionId, references: []const typed.ReferenceId, destination: typed.ReferenceId },
    },
};
pub const Function = struct { effects: @import("effect_set.zig").Mask = 0, effect_bound: ?@import("effect_set.zig").Bound = null, return_reference: ?typed.ReturnReference = null, references: []const typed.Reference = &.{}, owner: ?typed.Type = null, restricted: bool = false, conversion: bool = false, id: typed.FunctionId, name: []const u8, parameter_count: usize = 0, return_type: typed.Type = .i64, locals: []const typed.Local = &.{}, instructions: []const Instruction };
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
    try @import("effects.zig").validate(allocator, program);
    for (program.records, 0..) |record, i| {
        if (@backingInt(record.id) != i + typed.Type.record_base) return error.InternalError;
        if (record.pool) |pool| {
            if (!validType(pool.element, program) or typed.moveOnly(pool.element, program.records) or typed.requiresHandling(pool.element, program.records) or !validType(pool.handle, program) or !pool.handle.isAggregate()) return error.InternalError;
            if (program.records[pool.handle.recordIndex()].handle_pool != record.id or !record.move_only or record.requires_handling or record.handle_pool != null or record.resource != null or record.buffer != null or record.array != null or record.domain != null or record.variants != null or record.fields.len != 0) return error.InternalError;
        }
        if (record.handle_pool) |owner| {
            if (!validType(owner, program) or !owner.isAggregate()) return error.InternalError;
            const pool = program.records[owner.recordIndex()].pool orelse return error.InternalError;
            if (pool.handle != record.id or record.move_only or record.requires_handling or record.pool != null or record.resource != null or record.buffer != null or record.array != null or record.domain != null or record.variants != null or record.fields.len != 0) return error.InternalError;
        }
        if (record.resource != null) {
            if (!record.move_only or record.requires_handling or record.buffer != null or record.array != null or record.domain != null or record.variants != null or record.fields.len != 0) return error.InternalError;
        }
        if (record.buffer) |element| {
            if (!validType(element, program) or typed.moveOnly(element, program.records) or typed.requiresHandling(element, program.records) or !record.move_only or record.requires_handling or record.array != null or record.domain != null or record.variants != null or record.fields.len != 0) return error.InternalError;
        }
        if (record.variants) |variants| {
            if (variants.fallible) {
                if (!variants.is_union or variants.cases.len != 2 or !record.requires_handling) return error.InternalError;
                var ok = false;
                var err = false;
                for (variants.cases) |case| {
                    if (case.payload == null) return error.InternalError;
                    ok = ok or std.mem.eql(u8, case.name, "ok");
                    err = err or std.mem.eql(u8, case.name, "err");
                }
                if (!ok or !err) return error.InternalError;
            }
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
    if (main.return_reference != null or main.parameter_count > main.locals.len or main.return_type != .i64 or main.owner != null or main.restricted) return error.InternalError;
    var entry_capabilities: u8 = 0;
    for (main.locals[0..main.parameter_count]) |parameter| {
        const index = parameter.ty.capabilityIndex() orelse return error.InternalError;
        const bit = @as(u8, 1) << index;
        if (parameter.reference_parameter != null or entry_capabilities & bit != 0) return error.InternalError;
        entry_capabilities |= bit;
    }
    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.id) != i or function.instructions.len == 0) return error.InternalError;
        if (function.owner) |owner| {
            if (!owner.isAggregate() or !validType(owner, program) or program.records[owner.recordIndex()].domain == null) return error.InternalError;
        } else if (function.restricted) return error.InternalError;
        if (function.parameter_count > function.locals.len or !validType(function.return_type, program)) return error.InternalError;
        if (function.return_reference) |contract| {
            if (@backingInt(contract.parameter) >= function.parameter_count or function.conversion) return error.InternalError;
            const parameter = function.locals[@backingInt(contract.parameter)];
            const mutable = parameter.reference_parameter orelse return error.InternalError;
            if (contract.mutable and !mutable) return error.InternalError;
            if (contract.slice and !parameter.slice_parameter) {
                if (!parameter.ty.isAggregate() or !validType(parameter.ty, program)) return error.InternalError;
                const array = program.records[parameter.ty.recordIndex()].array orelse return error.InternalError;
                if (array.key != null or array.element != function.return_type) return error.InternalError;
            } else if (contract.slice != parameter.slice_parameter or function.return_type != parameter.ty) return error.InternalError;
        }
        for (function.references, 0..) |reference, index| {
            if (@backingInt(reference.owner) >= function.locals.len or !validType(reference.ty, program)) return error.InternalError;
            const local = function.locals[@backingInt(reference.owner)];
            var source_type = local.ty;
            var source_slice = local.slice_parameter;
            if (reference.parent) |parent| {
                if (@backingInt(parent) >= index) return error.InternalError;
                source_type = function.references[@backingInt(parent)].ty;
                source_slice = function.references[@backingInt(parent)].slice;
            }
            if (reference.slice and !source_slice) {
                if (!source_type.isAggregate() or !validType(source_type, program)) return error.InternalError;
                const schema = program.records[source_type.recordIndex()];
                if (schema.buffer) |element| {
                    if (element != reference.ty) return error.InternalError;
                } else {
                    const array = schema.array orelse return error.InternalError;
                    if (array.key != null or array.element != reference.ty) return error.InternalError;
                }
            } else if (reference.slice != source_slice or reference.ty != source_type) return error.InternalError;
            if (reference.parent) |parent| {
                if (@backingInt(parent) >= index) return error.InternalError;
                const previous = function.references[@backingInt(parent)];
                if (previous.owner != reference.owner or (reference.mutable and !previous.mutable)) return error.InternalError;
            } else if (!reference.parameter and reference.mutable and !function.locals[@backingInt(reference.owner)].mutable) return error.InternalError;
            if (!reference.parameter and reference.parent == null and function.locals[@backingInt(reference.owner)].reference_parameter != null) return error.InternalError;
            if (reference.parameter and index > 0 and (!function.references[index - 1].parameter or @backingInt(function.references[index - 1].owner) >= @backingInt(reference.owner))) return error.InternalError;
            if (reference.parameter and (reference.parent != null or @backingInt(reference.owner) >= function.parameter_count or function.locals[@backingInt(reference.owner)].reference_parameter != reference.mutable or function.locals[@backingInt(reference.owner)].slice_parameter != reference.slice)) return error.InternalError;
        }
        for (function.locals, 0..) |local, slot| {
            if (!validType(local.ty, program) or (local.slice_parameter and local.reference_parameter == null)) return error.InternalError;
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
            .cmp_handle => |comparison| {
                if (!validType(comparison.ty, program) or !comparison.ty.isAggregate() or program.records[comparison.ty.recordIndex()].handle_pool == null) return error.InternalError;
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
            .read_field, .take_field => |read| {
                if (@backingInt(read.owner) >= function.locals.len or !validType(read.output, program)) return error.InternalError;
                const local = function.locals[@backingInt(read.owner)];
                if (local.reference_parameter != null or !validType(local.ty, program) or !local.ty.isAggregate()) return error.InternalError;
                const schema = program.records[local.ty.recordIndex()];
                if (!schema.isRecord() or read.field >= schema.fields.len or schema.fields[read.field].ty != read.output or (instruction.op == .read_field and (typed.moveOnly(read.output, program.records) or typed.requiresHandling(read.output, program.records))) or (instruction.op == .take_field and !typed.moveOnly(local.ty, program.records) and !typed.requiresHandling(local.ty, program.records))) return error.InternalError;
            },
            .pool_operation => |operation| {
                if (@backingInt(operation.owner) >= function.locals.len or !validType(operation.output, program)) return error.InternalError;
                const local = function.locals[@backingInt(operation.owner)];
                if (local.reference_parameter != null or !validType(local.ty, program) or !local.ty.isAggregate() or (operation.kind.mutates() and !local.mutable)) return error.InternalError;
                const pool = program.records[local.ty.recordIndex()].pool orelse return error.InternalError;
                const expected = operation.kind.output(pool);
                if (operation.kind.fallible()) {
                    const shape = typed.resultShape(operation.output, program.records) orelse return error.InternalError;
                    if (shape.ok_type != expected or shape.error_type != .i64) return error.InternalError;
                } else if (operation.output != expected) return error.InternalError;
            },
            .buffer_operation => |operation| {
                if (@backingInt(operation.owner) >= function.locals.len or !validType(operation.output, program)) return error.InternalError;
                const local = function.locals[@backingInt(operation.owner)];
                if (local.reference_parameter != null or !local.ty.isAggregate() or (operation.kind.mutates() and !local.mutable)) return error.InternalError;
                const element = program.records[local.ty.recordIndex()].buffer orelse return error.InternalError;
                if (operation.kind.mutates()) {
                    const shape = typed.resultShape(operation.output, program.records) orelse return error.InternalError;
                    if (shape.ok_type != .bool or shape.error_type != .i64) return error.InternalError;
                } else if (operation.output != (if (operation.kind == .read) element else typed.Type.u64)) return error.InternalError;
            },
            .resource_io => |io| {
                if (@backingInt(io.owner) >= function.locals.len) return error.InternalError;
                const local = function.locals[@backingInt(io.owner)];
                if (!local.mutable or local.reference_parameter != null or typed.resourceKind(local.ty, program.records) == null) return error.InternalError;
                if (io.reference) |id| {
                    if (@backingInt(id) >= function.references.len or io.input != null) return error.InternalError;
                    const reference = function.references[@backingInt(id)];
                    if (!reference.slice or reference.ty != .u8 or (io.kind == .read and !reference.mutable)) return error.InternalError;
                }
                if (io.kind == .read and io.reference != null) {
                    if (typed.resourceSliceReadShape(io.output, program.records) == null) return error.InternalError;
                } else if (io.kind == .read) {
                    if (io.input != null or typed.resourceReadShape(io.output, program.records) == null) return error.InternalError;
                } else {
                    const shape = typed.resultShape(io.output, program.records) orelse return error.InternalError;
                    if (shape.ok_type != .u64 or shape.error_type != .i64 or (io.reference == null and !typed.byteRequest(io.input orelse return error.InternalError, program.records))) return error.InternalError;
                }
            },
            .restrict_resource => |restrict| {
                if (restrict.ty.resourceKind() == null or restrict.permissions & ~@import("external_resources.zig").all_permissions != 0) return error.InternalError;
            },
            .environment_get => |get| {
                if (typed.environmentShape(get.output, program.records) == null or !typed.byteRequest(get.name, program.records)) return error.InternalError;
            },
            .complete_resource => |output| {
                if (typed.completionShape(output, program.records) == null) return error.InternalError;
            },
            .acquire_resource => |acquire| {
                const shape = typed.resultShape(acquire.output, program.records) orelse return error.InternalError;
                if (typed.resourceKind(shape.ok_type, program.records) == null or shape.error_type != .i64 or !typed.byteRequest(acquire.request, program.records)) return error.InternalError;
            },
            .external_read => |read| {
                const shape = typed.resultShape(read.output, program.records) orelse return error.InternalError;
                if (shape.ok_type != (if (read.kind == .clock) typed.Type.i64 else typed.Type.u64) or shape.error_type != .i64) return error.InternalError;
            },
            .acquire_pool => |ty| {
                const shape = typed.resultShape(ty, program.records) orelse return error.InternalError;
                if (!validType(shape.ok_type, program) or !shape.ok_type.isAggregate() or program.records[shape.ok_type.recordIndex()].pool == null or shape.error_type != .i64) return error.InternalError;
            },
            .acquire_buffer => |ty| {
                const shape = typed.resultShape(ty, program.records) orelse return error.InternalError;
                if (!validType(shape.ok_type, program) or !shape.ok_type.isAggregate() or program.records[shape.ok_type.recordIndex()].buffer == null or shape.error_type != .i64) return error.InternalError;
            },
            .cast_integer, .neg_integer => |ty| if (!ty.isInteger()) {
                return error.InternalError;
            },
            .binary_integer => |binary| {
                if (!binary.ty.isInteger() or binary.op == .logical_and or binary.op == .logical_or) return error.InternalError;
            },
            .begin_borrow, .begin_slice, .end_borrow, .read_ref, .write_ref, .read_slice, .write_slice, .len_slice => |id| {
                if (@backingInt(id) >= function.references.len) return error.InternalError;
                const reference = function.references[@backingInt(id)];
                if ((instruction.op == .begin_borrow or instruction.op == .begin_slice) and reference.parameter) return error.InternalError;
                if ((instruction.op == .write_ref or instruction.op == .write_slice) and !reference.mutable) return error.InternalError;
                switch (instruction.op) {
                    .read_slice, .write_slice, .len_slice, .begin_slice => if (!reference.slice) {
                        return error.InternalError;
                    },
                    .read_ref, .write_ref => if (reference.slice) {
                        return error.InternalError;
                    },
                    .begin_borrow => if (reference.slice and (reference.parent == null or !function.references[@backingInt(reference.parent.?)].slice)) {
                        return error.InternalError;
                    },
                    else => {},
                }
            },
            .load_local, .store_local, .move_local, .drop_local => |slot| if (@backingInt(slot) >= function.locals.len or function.locals[@backingInt(slot)].reference_parameter != null) {
                return error.InternalError;
            },
            .wrap_domain, .unwrap_domain => |ty| {
                if (function.owner != ty or !ty.isAggregate() or !validType(ty, program) or program.records[ty.recordIndex()].domain == null) return error.InternalError;
            },
            .make_record => |record| {
                if (!record.ty.isAggregate() or !validType(record.ty, program)) return error.InternalError;
                if (program.records[record.ty.recordIndex()].pool != null or program.records[record.ty.recordIndex()].handle_pool != null or program.records[record.ty.recordIndex()].resource != null or program.records[record.ty.recordIndex()].buffer != null or program.records[record.ty.recordIndex()].domain != null or program.records[record.ty.recordIndex()].variants != null) return error.InternalError;
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
            .try_result => |propagate| {
                const input = typed.resultShape(propagate.input, program.records) orelse return error.InternalError;
                const output = typed.resultShape(propagate.output, program.records) orelse return error.InternalError;
                if (input.error_type != output.error_type or propagate.output != function.return_type or function.return_reference != null or propagate.error_target >= function.instructions.len) return error.InternalError;
            },
            .acknowledge => |ty| {
                if (!validType(ty, program) or !typed.requiresHandling(ty, program.records)) return error.InternalError;
            },
            .capture_ref => |id| {
                const contract = function.return_reference orelse return error.InternalError;
                if (@backingInt(id) >= function.references.len) return error.InternalError;
                const reference = function.references[@backingInt(id)];
                if (reference.owner != contract.parameter or reference.ty != function.return_type or reference.slice != contract.slice or (contract.mutable and !reference.mutable)) return error.InternalError;
            },
            .ret => if (function.return_reference != null) {
                return error.InternalError;
            },
            .ret_ref => if (function.return_reference == null) {
                return error.InternalError;
            },
            .call => |id| {
                if (@backingInt(id) >= program.functions.len) return error.InternalError;
                const callee = program.functions[@backingInt(id)];
                if (callee.parameter_count > callee.locals.len) return error.InternalError;
                if (callee.restricted and function.owner != callee.owner) return error.InternalError;
                if (callee.return_reference != null or valueParameterCount(callee) != callee.parameter_count) return error.InternalError;
            },
            .call_refs, .call_borrow => {
                const call: @FieldType(@FieldType(Instruction, "op"), "call_refs") = if (instruction.op == .call_refs) instruction.op.call_refs else .{ .function = instruction.op.call_borrow.function, .references = instruction.op.call_borrow.references };
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
                    if (argument.slice != parameter.slice or argument.ty != parameter.ty or (parameter.mutable and !argument.mutable)) return error.InternalError;
                };
                if (index != call.references.len) return error.InternalError;
                if (instruction.op == .call_borrow) {
                    const contract = callee.return_reference orelse return error.InternalError;
                    if (@backingInt(contract.parameter) >= callee.parameter_count) return error.InternalError;
                    const destination = instruction.op.call_borrow.destination;
                    if (@backingInt(destination) >= function.references.len) return error.InternalError;
                    const result = function.references[@backingInt(destination)];
                    var origin_index: usize = 0;
                    for (callee.locals[0..@backingInt(contract.parameter)]) |parameter| if (parameter.reference_parameter != null) {
                        origin_index += 1;
                    };
                    if (origin_index >= call.references.len or result.parameter or result.parent != call.references[origin_index] or result.ty != callee.return_type or result.slice != contract.slice or (result.mutable and !contract.mutable)) return error.InternalError;
                } else if (callee.return_reference != null) return error.InternalError;
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
                .push_i64, .push_bool, .push_integer, .load_local, .move_local, .read_ref, .read_field, .take_field, .len_slice => height += 1,
                .drop_local => {},
                .resource_io => |io| {
                    if (io.kind == .write and io.reference == null) {
                        if (height == 0) return error.InternalError;
                    } else height += 1;
                },
                .pool_operation => |operation| {
                    const count = operation.kind.arity();
                    if (height < count) return error.InternalError;
                    height = height - count + 1;
                },
                .buffer_operation => |operation| {
                    const count = operation.kind.arity();
                    if (height < count) return error.InternalError;
                    height = height - count + 1;
                },
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
                .store_local, .pop, .acknowledge, .jump_if_false, .write_ref => {
                    if (height == 0) return error.InternalError;
                    height -= 1;
                },
                .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool, .binary_integer, .get_index, .cmp_enum, .cmp_handle => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .begin_slice, .write_slice => {
                    if (height < 2) return error.InternalError;
                    height -= 2;
                },
                .acquire_buffer, .acquire_pool, .acquire_resource, .environment_get => {
                    if (height < 2) return error.InternalError;
                    height -= 1;
                },
                .restrict_resource, .complete_resource, .external_read, .read_slice, .neg_i64_checked, .not_bool, .get_field, .cast_integer, .neg_integer, .array_length, .wrap_domain, .unwrap_domain => if (height == 0) {
                    return error.InternalError;
                },
                .call, .call_refs, .call_borrow => {
                    const id = switch (instruction.op) {
                        .call => |id| id,
                        .call_refs => |call| call.function,
                        .call_borrow => |call| call.function,
                        else => unreachable,
                    };
                    const count = valueParameterCount(program.functions[@backingInt(id)]);
                    if (height < count) return error.InternalError;
                    height = height - count + @as(usize, if (instruction.op == .call_borrow) 0 else 1);
                },
                .try_result => |propagate| {
                    if (height == 0) return error.InternalError;
                    // Failure unwinds unfinished operands and carries one error result.
                    try enqueue(heights, pending, &len, propagate.error_target, 1);
                },
                .ret_ref => {
                    if (height != 0) return error.InternalError;
                    continue;
                },
                .ret => {
                    if (height != 1) return error.InternalError;
                    continue;
                },
                .jump, .begin_borrow, .end_borrow, .capture_ref => {},
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
    return ty.isInteger() or ty == .bool or ty.capabilityIndex() != null or (ty.isAggregate() and ty.recordIndex() < program.records.len);
}

fn variantSchema(ty: typed.Type, program: Program) Error!typed.Variants {
    if (!ty.isAggregate() or !validType(ty, program)) return error.InternalError;
    return program.records[ty.recordIndex()].variants orelse error.InternalError;
}
