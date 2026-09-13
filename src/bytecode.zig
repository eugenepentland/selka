//! Structural and control-flow validation for the checked instruction model.
const callables = @import("callables.zig");
const std = @import("std");
const typed = @import("typed.zig");
const external_resources = @import("external_resources.zig");
const model = @import("bytecode_model.zig");
pub const Predicate = model.Predicate;
pub const Equality = model.Equality;
pub const SwitchArm = model.SwitchArm;
pub const Instruction = model.Instruction;
pub const Function = model.Function;
pub const FunctionScope = model.FunctionScope;
pub const Program = model.Program;
pub const valueParameterCount = model.valueParameterCount;
const Error = std.mem.Allocator.Error || error{InternalError};

/// Validate generated IDs, instruction operands, and stack heights at control-flow joins.
/// Runtime operand values and initialization are checked by the VM.
pub fn validate(allocator: std.mem.Allocator, program: Program) Error!void {
    if (@backingInt(program.main) >= program.functions.len) return error.InternalError;
    try @import("effects.zig").validate(allocator, program);
    try validateRecords(program);
    try @import("storage_contracts.zig").validate(allocator, program.records);
    try @import("codec_bytecode.zig").validate(allocator, program);
    try validateEntry(program);
    for (program.functions, 0..) |function, index| {
        try validateFunction(program, function, index);
        if (function.policy.c_abi and function.policy.host == null) return error.InternalError;
        if (function.policy.host != null) {
            try validateHost(allocator, program, function);
            continue;
        }
        for (function.scope.instructions) |instruction| try validateInstruction(allocator, program, function, instruction);
        try validateFlow(allocator, program, function);
    }
}

fn validateRecords(program: Program) Error!void {
    for (program.records, 0..) |record, i| {
        if (@backingInt(record.id) != i + typed.Type.record_base) return error.InternalError;
        if (record.managed and record.shape.buffer == null) return error.InternalError;
        try validatePoolRecord(program, record);
        try validateHandlePoolRecord(program, record);
        try validateResourceRecord(record);
        try validateBufferRecord(program, record);
        if (record.shape.variants) |variants| try validateVariantRecord(program, record, variants);
        try validateDomainRecord(record);
        try validateCallableRecord(program, record);
        try validateArrayRecord(program, record);
        for (record.fields) |field| if (!validType(field.ty, program)) {
            return error.InternalError;
        };
    }
}

fn validateEntry(program: Program) Error!void {
    const main = program.functions[@backingInt(program.main)];
    if (main.policy.host != null) return error.InternalError;
    if (main.signature.return_reference != null) return error.InternalError;
    if (main.signature.parameter_count > main.scope.locals.len) return error.InternalError;
    if (main.signature.return_type != .i64) return error.InternalError;
    if (main.policy.owner != null) return error.InternalError;
    if (main.policy.restricted) return error.InternalError;
    var entry_capabilities: u8 = 0;
    for (main.scope.locals[0..main.signature.parameter_count]) |parameter| {
        const index = parameter.ty.capabilityIndex() orelse return error.InternalError;
        const bit = @as(u8, 1) << index;
        if (parameter.parameter.reference_parameter != null or entry_capabilities & bit != 0) return error.InternalError;
        entry_capabilities |= bit;
    }
}

fn validateFunction(program: Program, function: Function, i: usize) Error!void {
    if (@backingInt(function.id) != i) return error.InternalError;
    if (function.policy.host == null and function.scope.instructions.len == 0) return error.InternalError;
    if (function.policy.owner) |owner| {
        if (!owner.isAggregate()) return error.InternalError;
        if (!validType(owner, program)) return error.InternalError;
        if (program.records[owner.recordIndex()].shape.domain == null) return error.InternalError;
    } else if (function.policy.restricted) return error.InternalError;
    if (function.signature.parameter_count > function.scope.locals.len or !validType(function.signature.return_type, program)) return error.InternalError;
    if (function.signature.return_reference) |contract| {
        if (@backingInt(contract.parameter) >= function.signature.parameter_count or function.policy.conversion) return error.InternalError;
        const parameter = function.scope.locals[@backingInt(contract.parameter)];
        const mutable = parameter.parameter.reference_parameter orelse return error.InternalError;
        if (contract.mutable and !mutable) return error.InternalError;
        if (contract.slice and !parameter.parameter.slice_parameter) {
            if (!parameter.ty.isAggregate() or !validType(parameter.ty, program)) return error.InternalError;
            const array = program.records[parameter.ty.recordIndex()].shape.array orelse return error.InternalError;
            if (array.key != null or array.element != function.signature.return_type) return error.InternalError;
        } else if (contract.slice != parameter.parameter.slice_parameter or function.signature.return_type != parameter.ty) return error.InternalError;
    }
    for (function.scope.references, 0..) |reference, index| try validateReference(program, function, reference, index);
    for (function.scope.locals, 0..) |local, slot| {
        if (!validType(local.ty, program) or (local.parameter.slice_parameter and local.parameter.reference_parameter == null)) return error.InternalError;
        if (local.parameter.reference_parameter != null) {
            if (slot >= function.signature.parameter_count) return error.InternalError;
            var count: usize = 0;
            for (function.scope.references) |reference| if (reference.mode.parameter and @backingInt(reference.owner) == slot) {
                count += 1;
            };
            if (count != 1) return error.InternalError;
        }
    }
}

fn validateHost(allocator: std.mem.Allocator, program: Program, function: Function) Error!void {
    if (function.scope.instructions.len != 0 or function.scope.references.len != 0) return error.InternalError;
    if (function.policy.owner != null or function.policy.restricted or function.policy.conversion) return error.InternalError;
    if (function.signature.return_reference != null or function.signature.parameter_count != function.scope.locals.len) return error.InternalError;
    if (function.policy.c_abi) {
        const foreign = @import("c_abi.zig");
        if (!foreign.validSymbol(foreign.symbol(function.name)) or !foreign.supported(function.signature.return_type, program.records, true)) return error.InternalError;
        for (function.scope.locals) |parameter| {
            if (parameter.parameter.reference_parameter != null or parameter.parameter.slice_parameter or parameter.mutable) return error.InternalError;
            if (!foreign.supported(parameter.ty, program.records, false)) return error.InternalError;
        }
        return;
    }
    try validateHostType(allocator, program.records, function.signature.return_type);
    for (function.scope.locals) |parameter| {
        if (parameter.parameter.reference_parameter != null or parameter.parameter.slice_parameter or parameter.mutable) return error.InternalError;
        try validateHostType(allocator, program.records, parameter.ty);
    }
}
fn validateHostType(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type) Error!void {
    @import("data_type.zig").check(allocator, records, ty, true) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
}

fn validateFunctionValue(program: Program, ty: typed.Type, target: typed.FunctionId) Error!void {
    const contract = callables.signature(ty, program.records) orelse return error.InternalError;
    if (@backingInt(target) >= program.functions.len) return error.InternalError;
    if (!callables.accepts(contract, program.functions[@backingInt(target)])) return error.InternalError;
}
fn validateInvocation(program: Program, function: Function, invocation: @FieldType(@FieldType(Instruction, "op"), "invoke")) Error!void {
    const ty = invocation.ty;
    const contract = callables.signature(ty, program.records) orelse return error.InternalError;
    if (invocation.references.len != @popCount(contract.borrowed)) return error.InternalError;
    var loan: usize = 0;
    for (contract.parameters, 0..) |parameter, i| if (contract.borrows(i)) {
        const id = @backingInt(invocation.references[loan]);
        loan += 1;
        if (id >= function.scope.references.len) return error.InternalError;
        const ref = function.scope.references[id];
        if (ref.ty != parameter or ref.mode.slice != contract.slice(i)) return error.InternalError;
    };
}
fn validateInstruction(allocator: std.mem.Allocator, program: Program, function: Function, instruction: Instruction) Error!void {
    switch (instruction.op) {
        .invoke => |invocation| try validateInvocation(program, function, invocation),
        .function_value => |value| try validateFunctionValue(program, value.ty, value.function),
        .make_variant => |variant| try validateOpMakeVariant(program, variant),
        .reset_arena => |output| try validateOpResetArena(program, output),
        .begin_region, .end_region => |slot| try validateOpBeginRegion(function, slot),
        .begin_arena, .end_arena => |watermark| try validateOpArena(function, watermark),
        .arena_escape => |ty| try validateOpArenaEscape(program, ty),
        .cmp_handle => |comparison| {
            if (!validType(comparison.ty, program)) return error.InternalError;
            if (!comparison.ty.isAggregate()) return error.InternalError;
            if (program.records[comparison.ty.recordIndex()].shape.handle_pool == null) return error.InternalError;
        },
        .cmp_domain => |comparison| {
            if (!validType(comparison.ty, program) or !comparison.ty.isAggregate()) return error.InternalError;
            const backing = program.records[comparison.ty.recordIndex()].shape.domain orelse return error.InternalError;
            if (!backing.isInteger() and backing != .bool) return error.InternalError;
        },
        .cmp_enum => |comparison| {
            if ((try variantSchema(comparison.ty, program)).is_union) return error.InternalError;
        },
        .switch_variant => |dispatch| try validateOpSwitchVariant(program, function, dispatch),
        .unary_float => |op| try validateFloatUnary(op),
        .push_integer => |number| {
            if (!number.ty.isInteger() or !number.ty.fits(number.value)) return error.InternalError;
        },
        .read_field, .take_field => |read| try validateOpReadField(program, function, instruction, read),
        .pool_operation => |operation| try validateOpPoolOperation(program, function, operation),
        .buffer_operation => |operation| try validateOpBufferOperation(program, function, operation),
        .resource_io => |io| try validateOpResourceIo(program, function, io),
        .restrict_resource => |restrict| {
            if (restrict.ty.resourceKind() == null or restrict.permissions & ~external_resources.all_permissions != 0) return error.InternalError;
        },
        .environment_get => |get| {
            if (typed.environmentShape(get.output, program.records) == null or !typed.byteRequest(get.name, program.records)) return error.InternalError;
        },
        .complete_resource => |output| {
            if (typed.completionShape(output, program.records) == null) return error.InternalError;
        },
        .acquire_resource => |acquire| try validateOpAcquireResource(program, acquire),
        .external_read => |read| try validateOpExternalRead(program, read),
        .acquire_pool => |ty| try validateOpAcquirePool(program, ty),
        .json_codec => |codec| try @import("codec_bytecode.zig").operation(allocator, program, codec),
        .acquire_buffer => |ty| try validateOpAcquireBuffer(program, ty),
        .cast_integer => |ty| {
            const text_target = validType(ty, program) and ty.isAggregate() and program.records[ty.recordIndex()].collection.kind == .string;
            if (!ty.isInteger() and !text_target) return error.InternalError;
        },
        .neg_integer => |ty| if (!ty.isInteger()) {
            return error.InternalError;
        },
        .binary_integer => |binary| try validateCollectionBinary(program, binary),
        .split_borrow => |pair| try validateSplit(function, pair.left, pair.right),
        .begin_borrow, .begin_slice, .end_borrow, .read_ref, .write_ref, .read_slice, .write_slice, .len_slice => |id| try validateOpBeginBorrow(program, function, instruction, id),
        .load_local, .store_local, .move_local, .drop_local => |slot| if (@backingInt(slot) >= function.scope.locals.len or function.scope.locals[@backingInt(slot)].parameter.reference_parameter != null) {
            return error.InternalError;
        },
        .wrap_domain, .unwrap_domain => |ty| {
            if (function.policy.owner != ty and !@import("numeric_surface.zig").isFloat(ty, program.records)) return error.InternalError;
            if (!ty.isAggregate()) return error.InternalError;
            if (!validType(ty, program)) return error.InternalError;
            if (program.records[ty.recordIndex()].shape.domain == null) return error.InternalError;
        },
        .make_record => |record| try validateOpMakeRecord(allocator, program, record),
        .get_index, .replace_index, .array_length => |ty| {
            if (!ty.isAggregate()) return error.InternalError;
            if (!validType(ty, program)) return error.InternalError;
            const schema = program.records[ty.recordIndex()];
            const collection = instruction.op != .replace_index and schema.managed and schema.collection.kind != .list;
            if (schema.shape.array == null and !collection) return error.InternalError;
        },
        .update_record => |update| try validateOpUpdateRecord(allocator, program, update),
        .try_result => |propagate| try validateOpTryResult(program, function, propagate),
        .acknowledge => |ty| {
            if (!validType(ty, program) or !typed.requiresHandling(ty, program.records)) return error.InternalError;
        },
        .capture_ref => |id| try validateOpCaptureRef(function, id),
        .ret => if (function.signature.return_reference != null) {
            return error.InternalError;
        },
        .ret_ref => if (function.signature.return_reference == null) {
            return error.InternalError;
        },
        .call => |id| try validateOpCall(program, function, id),
        .call_refs, .call_borrow => try validateOpCallRefs(program, function, instruction),
        .jump, .jump_if_false => |target| if (target >= function.scope.instructions.len) {
            return error.InternalError;
        },
        else => {},
    }
}

fn validateOpMakeVariant(program: Program, variant: @FieldType(@FieldType(Instruction, "op"), "make_variant")) Error!void {
    const schema = try variantSchema(variant.ty, program);
    if (variant.tag >= schema.cases.len) return error.InternalError;
}

fn validateOpResetArena(program: Program, output: @FieldType(@FieldType(Instruction, "op"), "reset_arena")) Error!void {
    const shape = typed.resultShape(output, program.records) orelse return error.InternalError;
    if (shape.ok_type != .bool or shape.error_type != .i64) return error.InternalError;
}

fn validateOpArena(function: Function, watermark: @FieldType(@FieldType(Instruction, "op"), "begin_arena")) Error!void {
    if (@backingInt(watermark) > function.scope.locals.len) return error.InternalError;
}

fn validateOpArenaEscape(program: Program, ty: @FieldType(@FieldType(Instruction, "op"), "arena_escape")) Error!void {
    if (!validType(ty, program)) return error.InternalError;
}

fn validateOpBeginRegion(function: Function, slot: @FieldType(@FieldType(Instruction, "op"), "begin_region")) Error!void {
    if (@backingInt(slot) >= function.scope.locals.len) return error.InternalError;
    const local = function.scope.locals[@backingInt(slot)];
    if (local.ty != .allocator or local.mutable or local.parameter.reference_parameter != null or local.ownership.arena_depth == 0) return error.InternalError;
}

fn validateOpSwitchVariant(program: Program, function: Function, dispatch: @FieldType(@FieldType(Instruction, "op"), "switch_variant")) Error!void {
    const schema = try variantSchema(dispatch.ty, program);
    if (schema.cases.len != dispatch.arms.len) return error.InternalError;
    for (dispatch.arms, schema.cases) |arm, variant| {
        if (arm.target >= function.scope.instructions.len) return error.InternalError;
        if (arm.slot) |slot| {
            if (@backingInt(slot) >= function.scope.locals.len or variant.payload == null) return error.InternalError;
            const local = function.scope.locals[@backingInt(slot)];
            if (local.parameter.reference_parameter != null or local.ty != variant.payload.?) return error.InternalError;
        }
    }
}

fn validateOperationOwner(function: Function, owner: typed.LocalId, reference_id: ?typed.ReferenceId, mutable: bool) Error!void {
    if (@backingInt(owner) >= function.scope.locals.len) return error.InternalError;
    const local = function.scope.locals[@backingInt(owner)];
    if (reference_id) |id| {
        if (@backingInt(id) >= function.scope.references.len) return error.InternalError;
        const reference = function.scope.references[@backingInt(id)];
        if (reference.owner != owner or reference.ty != local.ty or reference.mode.slice) return error.InternalError;
        if (mutable and !reference.mutable) return error.InternalError;
    } else {
        if (local.parameter.reference_parameter != null or (mutable and !local.mutable)) return error.InternalError;
    }
}

fn validateOpReadField(program: Program, function: Function, instruction: Instruction, read: @FieldType(@FieldType(Instruction, "op"), "read_field")) Error!void {
    if (@backingInt(read.owner) >= function.scope.locals.len or !validType(read.output, program)) return error.InternalError;
    const local = function.scope.locals[@backingInt(read.owner)];
    try validateOperationOwner(function, read.owner, read.reference, false);
    if (!validType(local.ty, program)) return error.InternalError;
    if (!local.ty.isAggregate()) return error.InternalError;
    const schema = program.records[local.ty.recordIndex()];
    if (!schema.isRecord()) return error.InternalError;
    if (read.field >= schema.fields.len) return error.InternalError;
    if (schema.fields[read.field].ty != read.output) return error.InternalError;
    if ((instruction.op == .read_field and (typed.moveOnly(read.output, program.records) or typed.requiresHandling(read.output, program.records)))) return error.InternalError;
    if (instruction.op == .take_field) {
        if (read.reference != null) return error.InternalError;
        if (!typed.moveOnly(local.ty, program.records) and !typed.requiresHandling(local.ty, program.records)) return error.InternalError;
    }
}

fn validateOpPoolOperation(program: Program, function: Function, operation: @FieldType(@FieldType(Instruction, "op"), "pool_operation")) Error!void {
    if (@backingInt(operation.owner) >= function.scope.locals.len or !validType(operation.output, program)) return error.InternalError;
    const local = function.scope.locals[@backingInt(operation.owner)];
    if (!validType(local.ty, program)) return error.InternalError;
    if (!local.ty.isAggregate()) return error.InternalError;
    try validateOperationOwner(function, operation.owner, operation.reference, operation.kind.mutates());
    const pool = program.records[local.ty.recordIndex()].shape.pool orelse return error.InternalError;
    const expected = operation.kind.output(pool);
    if (operation.kind.fallible()) {
        const shape = typed.resultShape(operation.output, program.records) orelse return error.InternalError;
        if (shape.ok_type != expected or shape.error_type != .i64) return error.InternalError;
    } else if (operation.output != expected) return error.InternalError;
}

fn validateCollectionBinary(program: Program, binary: @FieldType(@FieldType(Instruction, "op"), "binary_integer")) Error!void {
    if (validType(binary.ty, program) and binary.ty.isAggregate() and program.records[binary.ty.recordIndex()].managed) {
        const concatenate = binary.op == .add and program.records[binary.ty.recordIndex()].collection.kind == .string;
        if (!concatenate and binary.op != .eq and binary.op != .ne) return error.InternalError;
    } else {
        if (!binary.ty.isInteger() or binary.op == .logical_and or binary.op == .logical_or) return error.InternalError;
        try validateFloatBinary(binary.ty, binary.op);
    }
}

fn validateManagedOperation(program: Program, local: typed.Local, operation: @FieldType(@FieldType(Instruction, "op"), "buffer_operation")) Error!void {
    const schema = program.records[local.ty.recordIndex()];
    const element = schema.shape.buffer.?;

    if (operation.reference != null or local.parameter.reference_parameter != null) return error.InternalError;
    if (schema.collection.kind != .list) {
        const dictionary = schema.collection.kind == .dictionary;
        const expected: typed.Type = switch (operation.kind) {
            .length => .i64,
            .iteration_check => .unit,
            .key_at => if (dictionary) schema.collection.key.? else return error.InternalError,
            .slice => if (!dictionary) local.ty else return error.InternalError,
            .read => if (dictionary) element else local.ty,
            .write => if (dictionary) .unit else return error.InternalError,
            .get => if (dictionary) element else return error.InternalError,
            .contains => .bool,
            .join => if (!dictionary) local.ty else return error.InternalError,
            .split, .keys, .values => list: {
                if ((operation.kind == .split) == dictionary) return error.InternalError;
                if (!operation.output.isAggregate()) return error.InternalError;
                const result = program.records[operation.output.recordIndex()];
                const member = if (operation.kind == .split) local.ty else if (operation.kind == .keys) schema.collection.key.? else element;
                if (!result.managed or result.collection.kind != .list or result.shape.buffer != member) return error.InternalError;
                break :list operation.output;
            },
            else => return error.InternalError,
        };
        if (operation.output != expected) return error.InternalError;
        return;
    }
    const expected: typed.Type = switch (operation.kind) {
        .length, .capacity => .u64,
        .read => element,
        .append, .write, .iteration_check => .unit,
        .contains => .bool,
        else => return error.InternalError,
    };
    if (operation.output != expected) return error.InternalError;
    return;
}

fn validateOpBufferOperation(program: Program, function: Function, operation: @FieldType(@FieldType(Instruction, "op"), "buffer_operation")) Error!void {
    if (@backingInt(operation.owner) >= function.scope.locals.len or !validType(operation.output, program)) return error.InternalError;
    const local = function.scope.locals[@backingInt(operation.owner)];
    if (!local.ty.isAggregate()) return error.InternalError;
    const schema = program.records[local.ty.recordIndex()];
    const element = schema.shape.buffer orelse return error.InternalError;
    if (schema.managed) return validateManagedOperation(program, local, operation);
    if (operation.kind == .iteration_check) return error.InternalError;
    try validateOperationOwner(function, operation.owner, operation.reference, operation.kind.mutates());
    if ((operation.kind == .read or operation.kind == .resize) and typed.moveOnly(element, program.records)) return error.InternalError;
    if (operation.kind.mutates()) {
        const shape = typed.resultShape(operation.output, program.records) orelse return error.InternalError;
        if (shape.ok_type != (if (operation.kind == .take) element else typed.Type.bool) or shape.error_type != .i64) return error.InternalError;
    } else if (operation.output != (if (operation.kind == .read) element else typed.Type.u64)) return error.InternalError;
}

fn validateOpResourceIo(program: Program, function: Function, io: @FieldType(@FieldType(Instruction, "op"), "resource_io")) Error!void {
    if (@backingInt(io.owner) >= function.scope.locals.len) return error.InternalError;
    const local = function.scope.locals[@backingInt(io.owner)];
    if (!local.mutable or local.parameter.reference_parameter != null or typed.resourceKind(local.ty, program.records) == null) return error.InternalError;
    if (io.reference) |id| {
        if (@backingInt(id) >= function.scope.references.len or io.input != null) return error.InternalError;
        const reference = function.scope.references[@backingInt(id)];
        if (!reference.mode.slice) return error.InternalError;
        if (reference.ty != .u8) return error.InternalError;
        if ((io.kind == .read and !reference.mutable)) return error.InternalError;
    }
    if (io.kind == .read and io.reference != null) {
        if (typed.resourceSliceReadShape(io.output, program.records) == null) return error.InternalError;
    } else if (io.kind == .read) {
        if (io.input != null or typed.resourceReadShape(io.output, program.records) == null) return error.InternalError;
    } else {
        const shape = typed.resultShape(io.output, program.records) orelse return error.InternalError;
        if (shape.ok_type != .u64) return error.InternalError;
        if (shape.error_type != .i64) return error.InternalError;
        if ((io.reference == null and !typed.byteRequest(io.input orelse return error.InternalError, program.records))) return error.InternalError;
    }
}

fn validateOpAcquireResource(program: Program, acquire: @FieldType(@FieldType(Instruction, "op"), "acquire_resource")) Error!void {
    const shape = typed.resultShape(acquire.output, program.records) orelse return error.InternalError;
    if (typed.resourceKind(shape.ok_type, program.records) == null or shape.error_type != .i64 or !typed.acquisitionBytes(acquire.request, program.records)) return error.InternalError;
}

fn validateOpExternalRead(program: Program, read: @FieldType(@FieldType(Instruction, "op"), "external_read")) Error!void {
    const shape = typed.resultShape(read.output, program.records) orelse return error.InternalError;
    if (shape.ok_type != (if (read.kind == .clock) typed.Type.i64 else typed.Type.u64) or shape.error_type != .i64) return error.InternalError;
}

fn validateOpAcquirePool(program: Program, ty: @FieldType(@FieldType(Instruction, "op"), "acquire_pool")) Error!void {
    const shape = typed.resultShape(ty, program.records) orelse return error.InternalError;
    if (!validType(shape.ok_type, program)) return error.InternalError;
    if (!shape.ok_type.isAggregate()) return error.InternalError;
    if (program.records[shape.ok_type.recordIndex()].shape.pool == null) return error.InternalError;
    if (shape.error_type != .i64) return error.InternalError;
}

fn validateOpAcquireBuffer(program: Program, ty: @FieldType(@FieldType(Instruction, "op"), "acquire_buffer")) Error!void {
    if (validType(ty, program) and ty.isAggregate() and program.records[ty.recordIndex()].managed) {
        if (program.records[ty.recordIndex()].shape.buffer == null) return error.InternalError;
        return;
    }
    const shape = typed.resultShape(ty, program.records) orelse return error.InternalError;
    if (!validType(shape.ok_type, program)) return error.InternalError;
    if (!shape.ok_type.isAggregate()) return error.InternalError;
    if (program.records[shape.ok_type.recordIndex()].shape.buffer == null) return error.InternalError;
    if (program.records[shape.ok_type.recordIndex()].managed) return error.InternalError;
    if (shape.error_type != .i64) return error.InternalError;
}

fn validateSplit(function: Function, left: typed.ReferenceId, right: typed.ReferenceId) Error!void {
    if (left == right) return error.InternalError;
    if (@backingInt(left) >= function.scope.references.len or @backingInt(right) >= function.scope.references.len) return error.InternalError;
    const a = function.scope.references[@backingInt(left)];
    const b = function.scope.references[@backingInt(right)];
    if (a.mode.split_sibling != right or b.mode.split_sibling != left) return error.InternalError;
    if (a.parent == null or a.parent != b.parent) return error.InternalError;
    if (!a.mode.slice or !b.mode.slice) return error.InternalError;
    if (!a.mutable or !b.mutable) return error.InternalError;
    const parent = function.scope.references[@backingInt(a.parent.?)];
    if (!parent.mode.slice or !parent.mutable) return error.InternalError;
}

fn validateOpBeginBorrow(program: Program, function: Function, instruction: Instruction, id: @FieldType(@FieldType(Instruction, "op"), "begin_borrow")) Error!void {
    if (@backingInt(id) >= function.scope.references.len) return error.InternalError;
    const reference = function.scope.references[@backingInt(id)];
    if (instruction.op == .read_ref and (typed.moveOnly(reference.ty, program.records) or typed.requiresHandling(reference.ty, program.records))) return error.InternalError;
    if (instruction.op == .begin_borrow or instruction.op == .begin_slice) {
        if (reference.mode.split_sibling != null) return error.InternalError;
    }
    if ((instruction.op == .begin_borrow or instruction.op == .begin_slice) and reference.mode.parameter) return error.InternalError;
    if ((instruction.op == .write_ref or instruction.op == .write_slice) and !reference.mutable) return error.InternalError;
    switch (instruction.op) {
        .read_slice, .write_slice, .len_slice, .begin_slice => if (!reference.mode.slice) {
            return error.InternalError;
        },
        .read_ref, .write_ref => if (reference.mode.slice) {
            return error.InternalError;
        },
        .begin_borrow => if (reference.mode.slice and (reference.parent == null or !function.scope.references[@backingInt(reference.parent.?)].mode.slice)) {
            return error.InternalError;
        },
        else => {},
    }
}

fn validateOpMakeRecord(allocator: std.mem.Allocator, program: Program, record: @FieldType(@FieldType(Instruction, "op"), "make_record")) Error!void {
    if (!record.ty.isAggregate() or !validType(record.ty, program)) return error.InternalError;
    if (program.records[record.ty.recordIndex()].shape.pool != null) return error.InternalError;
    if (program.records[record.ty.recordIndex()].shape.handle_pool != null) return error.InternalError;
    if (program.records[record.ty.recordIndex()].shape.resource != null) return error.InternalError;
    if (program.records[record.ty.recordIndex()].managed and program.records[record.ty.recordIndex()].collection.kind != .list) {
        if (record.order.len != 0) return error.InternalError;
        if (program.records[record.ty.recordIndex()].collection.kind == .dictionary and record.fields % 2 != 0) return error.InternalError;
        return;
    }
    if (program.records[record.ty.recordIndex()].shape.buffer != null) return error.InternalError;
    if (program.records[record.ty.recordIndex()].shape.domain != null) return error.InternalError;
    if (program.records[record.ty.recordIndex()].shape.variants != null) return error.InternalError;
    if (record.fields != program.records[record.ty.recordIndex()].count()) return error.InternalError;
    if (record.order.len != 0) {
        if (record.order.len != record.fields) return error.InternalError;
        try validateIndices(allocator, record.order, record.fields);
    }
}

fn validateOpUpdateRecord(allocator: std.mem.Allocator, program: Program, update: @FieldType(@FieldType(Instruction, "op"), "update_record")) Error!void {
    if (!update.ty.isAggregate() or update.ty.recordIndex() >= program.records.len) return error.InternalError;
    if (!program.records[update.ty.recordIndex()].isRecord()) return error.InternalError;
    try validateIndices(allocator, update.indices, program.records[update.ty.recordIndex()].fields.len);
}

fn validateOpTryResult(program: Program, function: Function, propagate: @FieldType(@FieldType(Instruction, "op"), "try_result")) Error!void {
    const input = typed.resultShape(propagate.input, program.records) orelse return error.InternalError;
    const output = typed.resultShape(propagate.output, program.records) orelse return error.InternalError;
    if (input.error_type != output.error_type or propagate.output != function.signature.return_type or function.signature.return_reference != null or propagate.error_target >= function.scope.instructions.len) return error.InternalError;
}

fn validateOpCaptureRef(function: Function, id: @FieldType(@FieldType(Instruction, "op"), "capture_ref")) Error!void {
    const contract = function.signature.return_reference orelse return error.InternalError;
    if (@backingInt(id) >= function.scope.references.len) return error.InternalError;
    const reference = function.scope.references[@backingInt(id)];
    if (reference.owner != contract.parameter) return error.InternalError;
    if (reference.ty != function.signature.return_type) return error.InternalError;
    if (reference.mode.slice != contract.slice) return error.InternalError;
    if ((contract.mutable and !reference.mutable)) return error.InternalError;
}

fn validateOpCall(program: Program, function: Function, id: @FieldType(@FieldType(Instruction, "op"), "call")) Error!void {
    if (@backingInt(id) >= program.functions.len) return error.InternalError;
    const callee = program.functions[@backingInt(id)];
    if (callee.signature.parameter_count > callee.scope.locals.len) return error.InternalError;
    if (callee.policy.restricted and function.policy.owner != callee.policy.owner) return error.InternalError;
    if (callee.signature.return_reference != null or valueParameterCount(callee) != callee.signature.parameter_count) return error.InternalError;
}

fn validateOpCallRefs(program: Program, function: Function, instruction: Instruction) Error!void {
    const call: @FieldType(@FieldType(Instruction, "op"), "call_refs") = if (instruction.op == .call_refs) instruction.op.call_refs else .{
        .function = instruction.op.call_borrow.function,
        .references = instruction.op.call_borrow.references,
    };
    if (@backingInt(call.function) >= program.functions.len) return error.InternalError;
    const callee = program.functions[@backingInt(call.function)];
    if (callee.signature.parameter_count > callee.scope.locals.len) return error.InternalError;
    if (callee.policy.restricted and function.policy.owner != callee.policy.owner) return error.InternalError;
    if (call.references.len != callee.signature.parameter_count - valueParameterCount(callee)) return error.InternalError;
    var index: usize = 0;
    for (callee.scope.references) |parameter| if (parameter.mode.parameter) {
        if (index >= call.references.len) return error.InternalError;
        const id = call.references[index];
        index += 1;
        if (@backingInt(id) >= function.scope.references.len) return error.InternalError;
        const argument = function.scope.references[@backingInt(id)];
        if (argument.mode.slice != parameter.mode.slice) return error.InternalError;
        if (argument.ty != parameter.ty) return error.InternalError;
        if ((parameter.mutable and !argument.mutable)) return error.InternalError;
    };
    if (index != call.references.len) return error.InternalError;
    if (instruction.op == .call_borrow) {
        const contract = callee.signature.return_reference orelse return error.InternalError;
        if (@backingInt(contract.parameter) >= callee.signature.parameter_count) return error.InternalError;
        const destination = instruction.op.call_borrow.destination;
        if (@backingInt(destination) >= function.scope.references.len) return error.InternalError;
        const result = function.scope.references[@backingInt(destination)];
        var origin_index: usize = 0;
        for (callee.scope.locals[0..@backingInt(contract.parameter)]) |parameter| if (parameter.parameter.reference_parameter != null) {
            origin_index += 1;
        };
        if (origin_index >= call.references.len) return error.InternalError;
        if (result.mode.parameter) return error.InternalError;
        if (result.parent != call.references[origin_index]) return error.InternalError;
        if (result.ty != callee.signature.return_type) return error.InternalError;
        if (result.mode.slice != contract.slice) return error.InternalError;
        if ((result.mutable and !contract.mutable)) return error.InternalError;
    } else if (callee.signature.return_reference != null) return error.InternalError;
}

fn validateFlow(allocator: std.mem.Allocator, program: Program, function: Function) Error!void {
    const heights = try allocator.alloc(?usize, function.scope.instructions.len);
    defer allocator.free(heights);
    @memset(heights, null);
    const pending = try allocator.alloc(usize, function.scope.instructions.len);
    defer allocator.free(pending);
    var len: usize = 0;
    try enqueue(heights, pending, &len, 0, 0);
    while (len != 0) {
        len -= 1;
        const pc = pending[len];
        const instruction = function.scope.instructions[pc];
        var height = heights[pc].?;
        switch (instruction.op) {
            .function_value, .push_unit, .push_i64, .push_bool, .push_integer, .load_local, .move_local, .read_ref, .read_field, .take_field, .len_slice => height += 1,
            .drop_local, .end_region, .begin_arena, .end_arena => {},
            .resource_io => |io| {
                height = try resourceIoHeight(io, height);
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
            .json_codec, .replace_index => {
                if (height < 3) return error.InternalError;
                height -= 2;
            },
            .update_record => |update| {
                if (height <= update.indices.len) return error.InternalError;
                height -= update.indices.len;
            },
            .split_borrow, .begin_region, .store_local, .pop, .acknowledge, .jump_if_false, .write_ref => {
                if (height == 0) return error.InternalError;
                height -= 1;
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool, .binary_integer, .get_index, .cmp_enum, .cmp_handle, .cmp_domain => {
                if (height < 2) return error.InternalError;
                height -= 1;
            },
            .begin_slice, .write_slice => {
                if (height < 2) return error.InternalError;
                height -= 2;
            },
            .acquire_buffer => |ty| height = try acquiredHeight(program, ty, height),
            .acquire_pool, .acquire_resource, .environment_get => {
                if (height < 2) return error.InternalError;
                height -= 1;
            },
            .arena_escape,
            .reset_arena,
            .restrict_resource,
            .complete_resource,
            .external_read,
            .read_slice,
            .unary_float,
            .neg_i64_checked,
            .not_bool,
            .get_field,
            .cast_integer,
            .neg_integer,
            .array_length,
            .wrap_domain,
            .unwrap_domain,
            => if (height == 0) {
                return error.InternalError;
            },
            .invoke => |invocation| {
                const ty = invocation.ty;
                const contract = callables.signature(ty, program.records) orelse return error.InternalError;
                if (height <= contract.valueCount()) return error.InternalError;
                height -= contract.valueCount();
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
    if (ty == .unit) return true;
    return ty.isInteger() or ty == .bool or ty.capabilityIndex() != null or (ty.isAggregate() and ty.recordIndex() < program.records.len);
}

fn variantSchema(ty: typed.Type, program: Program) Error!typed.Variants {
    if (!ty.isAggregate() or !validType(ty, program)) return error.InternalError;
    return program.records[ty.recordIndex()].shape.variants orelse error.InternalError;
}

fn validateVariantRecord(program: Program, record: typed.Record, variants: typed.Variants) Error!void {
    if (variants.fallible) {
        if (!variants.is_union) return error.InternalError;
        if (variants.cases.len != 2) return error.InternalError;
        if (!record.contract.requires_handling) return error.InternalError;
        var ok = false;
        var err = false;
        for (variants.cases) |case| {
            if (case.payload == null) return error.InternalError;
            ok = ok or std.mem.eql(u8, case.name, "ok");
            err = err or std.mem.eql(u8, case.name, "err");
        }
        if (!ok or !err) return error.InternalError;
    }
    if (record.shape.array != null or record.shape.domain != null or record.fields.len != 0 or variants.cases.len == 0) return error.InternalError;
    for (variants.cases) |variant| if (variant.payload) |ty| {
        if (!variants.is_union or !validType(ty, program)) return error.InternalError;
    };
}

fn validateReference(program: Program, function: Function, reference: typed.Reference, index: usize) Error!void {
    if (@backingInt(reference.owner) >= function.scope.locals.len or !validType(reference.ty, program)) return error.InternalError;
    const local = function.scope.locals[@backingInt(reference.owner)];
    var source_type = local.ty;
    var source_slice = local.parameter.slice_parameter;
    if (reference.parent) |parent| {
        if (@backingInt(parent) >= index) return error.InternalError;
        source_type = function.scope.references[@backingInt(parent)].ty;
        source_slice = function.scope.references[@backingInt(parent)].mode.slice;
    }
    if (reference.mode.slice and typed.moveOnly(reference.ty, program.records)) return error.InternalError;
    if (reference.mode.slice and !source_slice) {
        if (!source_type.isAggregate() or !validType(source_type, program)) return error.InternalError;
        const schema = program.records[source_type.recordIndex()];
        if (reference.parent != null and schema.shape.buffer != null) return error.InternalError;
        if (schema.shape.buffer) |element| {
            if (element != reference.ty) return error.InternalError;
        } else {
            const array = schema.shape.array orelse return error.InternalError;
            if (array.key != null or array.element != reference.ty) return error.InternalError;
        }
    } else if (reference.mode.slice != source_slice or reference.ty != source_type) return error.InternalError;
    try validateReferenceOrigin(function, reference, index);
    if (reference.mode.split_sibling) |sibling| try validateSplit(function, @fromBackingInt(@intCast(index)), sibling);
}

fn resourceIoHeight(io: @FieldType(@FieldType(Instruction, "op"), "resource_io"), height: usize) Error!usize {
    if (io.kind != .write or io.reference != null) return height + 1;
    if (height == 0) return error.InternalError;
    return height;
}

fn validatePoolRecord(program: Program, record: typed.Record) Error!void {
    if (record.shape.pool) |pool| {
        if (!validType(pool.element, program)) return error.InternalError;
        if (typed.moveOnly(pool.element, program.records)) return error.InternalError;
        if (typed.requiresHandling(pool.element, program.records)) return error.InternalError;
        if (!validType(pool.handle, program)) return error.InternalError;
        if (!pool.handle.isAggregate()) return error.InternalError;
        if (program.records[pool.handle.recordIndex()].shape.handle_pool != record.id) return error.InternalError;
        if (!record.contract.move_only) return error.InternalError;
        if (record.contract.requires_handling) return error.InternalError;
        if (record.shape.handle_pool != null) return error.InternalError;
        if (record.shape.resource != null) return error.InternalError;
        if (record.shape.buffer != null) return error.InternalError;
        if (record.shape.array != null) return error.InternalError;
        if (record.shape.domain != null) return error.InternalError;
        if (record.shape.variants != null) return error.InternalError;
        if (record.fields.len != 0) return error.InternalError;
    }
}

fn validateHandlePoolRecord(program: Program, record: typed.Record) Error!void {
    if (record.shape.handle_pool) |owner| {
        if (!validType(owner, program) or !owner.isAggregate()) return error.InternalError;
        const pool = program.records[owner.recordIndex()].shape.pool orelse return error.InternalError;
        if (pool.handle != record.id) return error.InternalError;
        if (record.contract.move_only) return error.InternalError;
        if (record.contract.requires_handling) return error.InternalError;
        if (record.shape.pool != null) return error.InternalError;
        if (record.shape.resource != null) return error.InternalError;
        if (record.shape.buffer != null) return error.InternalError;
        if (record.shape.array != null) return error.InternalError;
        if (record.shape.domain != null) return error.InternalError;
        if (record.shape.variants != null) return error.InternalError;
        if (record.fields.len != 0) return error.InternalError;
    }
}

fn validateResourceRecord(record: typed.Record) Error!void {
    if (record.shape.resource != null) {
        if (!record.contract.move_only) return error.InternalError;
        if (record.contract.requires_handling) return error.InternalError;
        if (record.shape.buffer != null) return error.InternalError;
        if (record.shape.array != null) return error.InternalError;
        if (record.shape.domain != null) return error.InternalError;
        if (record.shape.variants != null) return error.InternalError;
        if (record.fields.len != 0) return error.InternalError;
    }
}

fn validateBufferRecord(program: Program, record: typed.Record) Error!void {
    if (record.shape.buffer) |element| {
        if (!validType(element, program)) return error.InternalError;
        if (!typed.storable(element, program.records)) return error.InternalError;
        if (typed.requiresHandling(element, program.records)) return error.InternalError;
        if (record.contract.move_only == record.managed) return error.InternalError;
        if (record.managed and typed.moveOnly(element, program.records)) return error.InternalError;
        if (record.contract.requires_handling) return error.InternalError;
        if (record.shape.array != null) return error.InternalError;
        if (record.shape.domain != null) return error.InternalError;
        if (record.shape.variants != null) return error.InternalError;
        if (record.fields.len != 0) return error.InternalError;
    }
}

fn validateCallableRecord(program: Program, record: typed.Record) Error!void {
    const contract = record.contract.callback orelse return;
    if (record.shape.domain != .u64) return error.InternalError;
    if (contract.parameters.len > 16 or !validType(contract.return_type, program)) return error.InternalError;
    if (contract.slices & ~contract.borrowed != 0) return error.InternalError;
    if (contract.parameters.len < 16 and contract.borrowed >> @as(u4, @intCast(contract.parameters.len)) != 0) return error.InternalError;
    if (contract.effects & ~@import("effect_set.zig").all != 0) return error.InternalError;
    for (contract.parameters) |parameter| if (!validType(parameter, program)) return error.InternalError;
}
fn validateDomainRecord(record: typed.Record) Error!void {
    if (record.shape.domain) |backing| {
        if ((!backing.isInteger() and backing != .bool)) return error.InternalError;
        if (record.fields.len != 0) return error.InternalError;
        if (record.shape.array != null) return error.InternalError;
    }
}

fn validateArrayRecord(program: Program, record: typed.Record) Error!void {
    if (record.shape.array) |array| {
        if (!validType(array.element, program) or array.length > std.math.maxInt(usize) / @sizeOf(typed.Value)) return error.InternalError;
        if (array.key) |key| {
            const variants = try variantSchema(key, program);
            if (variants.is_union or variants.cases.len != array.length or record.fields.len != array.length) return error.InternalError;
            for (record.fields, variants.cases) |field, variant| if (field.ty != array.element or !std.mem.eql(u8, field.name, variant.name)) return error.InternalError;
        } else if (record.fields.len != 0) return error.InternalError;
    }
}

fn validateReferenceOrigin(function: Function, reference: typed.Reference, index: usize) Error!void {
    const local = function.scope.locals[@backingInt(reference.owner)];
    if (reference.parent) |parent| {
        if (@backingInt(parent) >= index) return error.InternalError;
        const previous = function.scope.references[@backingInt(parent)];
        if (previous.owner != reference.owner) return error.InternalError;
        if (reference.mutable and !previous.mutable) return error.InternalError;
    } else if (!reference.mode.parameter) {
        if (reference.mutable and !local.mutable) return error.InternalError;
        if (local.parameter.reference_parameter != null) return error.InternalError;
    }
    if (!reference.mode.parameter) return;
    if (index > 0) {
        const previous = function.scope.references[index - 1];
        if (!previous.mode.parameter) return error.InternalError;
        if (@backingInt(previous.owner) >= @backingInt(reference.owner)) return error.InternalError;
    }
    if (reference.parent != null) return error.InternalError;
    if (@backingInt(reference.owner) >= function.signature.parameter_count) return error.InternalError;
    if (local.parameter.reference_parameter != reference.mutable) return error.InternalError;
    if (local.parameter.slice_parameter != reference.mode.slice) return error.InternalError;
}

fn validateFloatUnary(op: typed.UnaryOp) Error!void {
    if (op == .neg or op == .not) return error.InternalError;
}

fn validateFloatBinary(ty: typed.Type, op: typed.BinaryOp) Error!void {
    if (std.mem.startsWith(u8, @tagName(op), "f64_") and ty != .u64) return error.InternalError;
}

fn acquiredHeight(program: Program, ty: typed.Type, height: usize) Error!usize {
    const count: usize = if (program.records[ty.recordIndex()].managed) 1 else 2;
    if (height < count) return error.InternalError;
    return height - count + 1;
}
