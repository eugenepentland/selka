//! Structural and control-flow validation for the checked instruction model.
const callables = @import("callables.zig");
const std = @import("std");
const typed = @import("typed.zig");
const external_resources = @import("external_resources.zig");
const model = @import("bytecode_model.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferOperation = @FieldType(@FieldType(Instruction, "op"), "buffer_operation");
const prelude = @import("prelude.zig");
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

/// Validate one selective lowering without requiring unselected stubs to carry
/// instructions. Program-wide metadata and every selected function are still
/// checked; unselected functions only need the signatures/locals QBE reads when
/// resolving callee ABIs.
pub fn validateSelected(allocator: std.mem.Allocator, program: Program, selected: []const bool) Error!void {
    if (selected.len != program.functions.len) return error.InternalError;
    if (@backingInt(program.main) >= program.functions.len) return error.InternalError;
    try validateRecords(program);
    try @import("codec_bytecode.zig").validate(allocator, program);
    try validateEntry(program);
    for (program.functions, 0..) |function, index| {
        if (!selected[index]) continue;
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
        if (record.managed and !record.isRecord()) {
            if (!record.isCollection()) return error.InternalError;
        }
        if (record.isCell() and (record.fields.len != 1 or !std.mem.eql(u8, record.fields[0].name, "value"))) return error.InternalError;
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
    if (main.signature.parameter_count > main.scope.locals.len) return error.InternalError;
    if (main.signature.return_type != .i64) return error.InternalError;
    if (main.policy.owner != null) return error.InternalError;
    if (main.policy.restricted) return error.InternalError;
    var entry_capabilities: u8 = 0;
    var entry_streams: [2]bool = .{ false, false };
    var first_capability: usize = 0;
    if (main.signature.parameter_count != 0) {
        if (@import("entry_adapter.zig").argvElement(main.scope.locals[0].ty, program.records) != null) first_capability = 1;
    }
    for (main.scope.locals[first_capability..main.signature.parameter_count]) |parameter| {
        if (parameter.ty == .stream_cap) {
            const slot: usize = if (std.mem.eql(u8, parameter.name, "out")) 0 else if (std.mem.eql(u8, parameter.name, "err")) 1 else return error.InternalError;
            if (entry_streams[slot]) return error.InternalError;
            entry_streams[slot] = true;
            continue;
        }
        const index = parameter.ty.capabilityIndex() orelse return error.InternalError;
        const bit = @as(u8, 1) << index;
        if (entry_capabilities & bit != 0) return error.InternalError;
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
    for (function.scope.locals) |local| {
        if (!validType(local.ty, program)) return error.InternalError;
    }
}

fn validateHost(allocator: std.mem.Allocator, program: Program, function: Function) Error!void {
    if (function.scope.instructions.len != 0) return error.InternalError;
    if (function.policy.owner != null or function.policy.restricted or function.policy.conversion) return error.InternalError;
    if (function.signature.parameter_count != function.scope.locals.len) return error.InternalError;
    if (function.policy.c_abi) {
        const foreign = @import("c_abi.zig");
        if (function.scope.locals.len == 0 or function.scope.locals[0].ty != .host_cap) return error.InternalError;
        if (!foreign.validSymbol(foreign.symbol(function.name)) or !foreign.supported(function.signature.return_type, program.records, true)) return error.InternalError;
        for (function.scope.locals[1..]) |parameter| {
            if (parameter.mutable) return error.InternalError;
            if (!foreign.supported(parameter.ty, program.records, false)) return error.InternalError;
        }
        return;
    }
    if (function.scope.locals.len == 0 or function.scope.locals[0].ty != .host_cap) return error.InternalError;
    try validateHostType(allocator, program.records, function.signature.return_type);
    for (function.scope.locals[1..]) |parameter| {
        if (parameter.mutable) return error.InternalError;
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
    const function = program.functions[@backingInt(target)];
    if (function.signature.parameter_count > 16 or function.signature.parameter_count != contract.parameters.len) return error.InternalError;
    var parameters: [16]typed.Type = undefined;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |parameter, index| parameters[index] = parameter.ty;
    // An unannotated function value adopts the ceiling of the callback type it was
    // checked against, so the node's own contract is the bound to compare with.
    const allowed = if (function.policy.effect_bound) |bound| bound.allowed else contract.effects;
    const implementation: typed.Callable = .{
        .parameters = parameters[0..function.signature.parameter_count],
        .return_type = function.signature.return_type,
        .effects = allowed,
        .mutates = function.signature.declared_mutates,
        .return_origin = function.signature.return_origin,
    };
    if (!callables.assignable(implementation, contract)) return error.InternalError;
}
fn validateInvocation(program: Program, ty: typed.Type) Error!void {
    _ = callables.signature(ty, program.records) orelse return error.InternalError;
}
fn validateInstruction(allocator: std.mem.Allocator, program: Program, function: Function, instruction: Instruction) Error!void {
    switch (instruction.op) {
        .invoke => |ty| try validateInvocation(program, ty),
        .function_value => |value| try validateFunctionValue(program, value.ty, value.function),
        .make_variant => |variant| try validateOpMakeVariant(program, variant),
        .begin_arena, .end_arena => |watermark| try validateOpArena(function, watermark),
        .arena_escape => |ty| try validateOpArenaEscape(program, ty),
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
        .buffer_operation => |operation| try validateOpBufferOperation(program, function, operation),
        .resource_io => |io| try validateOpResourceIo(program, function, io),
        .restrict_resource => |restrict| {
            if (restrict.ty.resourceKind() == null or restrict.permissions & ~external_resources.all_permissions != 0) return error.InternalError;
        },
        .dir_resource => |dir| {
            const kind = dir.output.resourceKind() orelse return error.InternalError;
            if (kind != .filesystem or !typed.byteRequest(dir.path, program.records)) return error.InternalError;
        },
        .host_resource => |host| {
            const kind = host.output.resourceKind() orelse return error.InternalError;
            if (kind != .network or !typed.byteRequest(host.name, program.records)) return error.InternalError;
        },
        .environment_get => |get| try validateEnvironmentGet(program, get),
        .environment_only => |only| try validateEnvironmentOnly(program, only),
        .environment_names => |names| try validateEnvironmentNames(program, names),
        .complete_resource => |output| {
            if (typed.completionShape(output, program.records) == null) return error.InternalError;
        },
        .acquire_resource => |acquire| try validateOpAcquireResource(program, acquire),
        .external_read => |read| try validateOpExternalRead(program, read),
        .acquire_buffer => |ty| try validateOpAcquireBuffer(program, ty),
        .print => |output| for (output.types) |ty| {
            if (!validType(ty, program) or !@import("io_render.zig").printable(ty, program.records)) return error.InternalError;
        },
        .stream_write => |write| {
            if (write.stream != .stream_cap or !validType(write.text, program)) return error.InternalError;
        },
        .file_access, .file_method => try validateOpFile(program, function, instruction.op),
        .cast_integer => |ty| {
            const text_target = validType(ty, program) and sequenceType(program, ty);
            if (!ty.isInteger() and !text_target) return error.InternalError;
        },
        .neg_integer => |ty| if (!ty.isInteger()) {
            return error.InternalError;
        },
        .binary_integer => |binary| try validateCollectionBinary(program, binary),
        .load_local, .store_local, .move_local, .drop_local => |slot| if (@backingInt(slot) >= function.scope.locals.len) {
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
        .call => |id| try validateOpCall(program, function, id),
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

fn validateOpArena(function: Function, watermark: @FieldType(@FieldType(Instruction, "op"), "begin_arena")) Error!void {
    if (@backingInt(watermark) > function.scope.locals.len) return error.InternalError;
}

fn validateOpArenaEscape(program: Program, ty: @FieldType(@FieldType(Instruction, "op"), "arena_escape")) Error!void {
    if (!validType(ty, program)) return error.InternalError;
}

fn validateOpSwitchVariant(program: Program, function: Function, dispatch: @FieldType(@FieldType(Instruction, "op"), "switch_variant")) Error!void {
    const schema = try variantSchema(dispatch.ty, program);
    if (schema.cases.len != dispatch.arms.len) return error.InternalError;
    for (dispatch.arms, schema.cases) |arm, variant| {
        if (arm.target >= function.scope.instructions.len) return error.InternalError;
        if (arm.slot) |slot| {
            if (@backingInt(slot) >= function.scope.locals.len or variant.payload == null) return error.InternalError;
            const local = function.scope.locals[@backingInt(slot)];
            if (local.ty != variant.payload.?) return error.InternalError;
        }
    }
}

fn sequenceType(program: Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const kind = program.records[ty.recordIndex()].collection.kind;
    return kind == .string or kind == .bytes;
}

fn validateCollectionBinary(program: Program, binary: @FieldType(@FieldType(Instruction, "op"), "binary_integer")) Error!void {
    if (validType(binary.ty, program) and binary.ty.isAggregate()) {
        const concatenate = program.records[binary.ty.recordIndex()].managed and binary.op == .add and sequenceType(program, binary.ty);
        if (!concatenate and binary.op != .eq and binary.op != .ne) return error.InternalError;
        return;
    }
    if (!binary.ty.isInteger() or binary.op == .logical_and or binary.op == .logical_or) return error.InternalError;
    try validateFloatBinary(binary.ty, binary.op);
}

fn validateManagedOperation(program: Program, local: typed.Local, operation: BufferOperation) Error!void {
    const schema = program.records[local.ty.recordIndex()];
    if (schema.collection.kind == .list) return validateManagedListOperation(local, schema, operation);
    return validateManagedTextOperation(program, local, schema, operation);
}

fn validateManagedListOperation(local: typed.Local, schema: typed.Record, operation: BufferOperation) Error!void {
    const element = schema.shape.buffer.?;
    const expected: typed.Type = switch (operation.kind) {
        .length, .capacity => .u64,
        .read, .pop, .pop_at => element,
        .index_of => .i64,
        .copy => local.ty,
        .append, .write, .iteration_check => .unit,
        .extend, .insert, .remove, .reverse, .sort, .clear => .unit,
        .contains => .bool,
        .slice_step => local.ty,
        else => return error.InternalError,
    };
    if (operation.output != expected) return error.InternalError;
}

fn validateManagedTextOperation(program: Program, local: typed.Local, schema: typed.Record, operation: BufferOperation) Error!void {
    const element = schema.shape.buffer.?;
    const dictionary = schema.collection.kind == .dictionary;
    const byte_string = schema.collection.kind == .bytes;
    const expected: typed.Type = switch (operation.kind) {
        .length => .i64,
        .find => if (dictionary) return error.InternalError else .i64,
        .iteration_check => .unit,
        .key_at => if (dictionary) schema.collection.key.? else return error.InternalError,
        .slice => if (!dictionary) local.ty else return error.InternalError,
        .slice_step => if (!dictionary and !byte_string) local.ty else return error.InternalError,
        .read => if (dictionary or byte_string) element else local.ty,
        .write => if (dictionary) .unit else return error.InternalError,
        .get => if (dictionary) element else return error.InternalError,
        .contains => .bool,
        .starts_with, .ends_with => if (dictionary) return error.InternalError else .bool,
        .to_list, .hex, .decode => if (byte_string) try validateConversion(program, operation) else return error.InternalError,
        .encode, .from_hex => if (schema.collection.kind == .string) try validateConversion(program, operation) else return error.InternalError,
        .join => if (!dictionary) local.ty else return error.InternalError,
        .strip, .lstrip, .rstrip, .upper, .lower, .replace, .zfill => if (dictionary or byte_string) return error.InternalError else local.ty,
        .is_digit, .is_alpha, .is_space => if (dictionary or byte_string) return error.InternalError else .bool,
        .count => if (dictionary or byte_string) return error.InternalError else .i64,
        .splitlines, .parse_int, .parse_float => if (dictionary or byte_string) return error.InternalError else operation.output,
        .pop_key, .pop_default, .setdefault => if (dictionary) element else return error.InternalError,
        .update, .clear => if (dictionary) .unit else return error.InternalError,
        .copy => if (dictionary) local.ty else return error.InternalError,
        .split, .keys, .values, .items => list: {
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
}

fn validateConversion(program: Program, operation: BufferOperation) Error!typed.Type {
    const output = operation.output;
    if (!output.isAggregate() or !validType(output, program)) return error.InternalError;
    const schema = program.records[output.recordIndex()];
    const wanted: ?ManagedKind = switch (operation.kind) {
        .to_list => .list,
        .hex => .string,
        .encode => .bytes,
        else => null,
    };
    if (wanted) |kind| {
        if (!schema.managed or schema.collection.kind != kind) return error.InternalError;
        if (kind == .list and schema.shape.buffer != .i64) return error.InternalError;
        return output;
    }
    const shape = typed.resultShape(output, program.records) orelse return error.InternalError;
    const payload = program.records[shape.ok_type.recordIndex()];
    if (!shape.ok_type.isAggregate() or !payload.managed) return error.InternalError;
    if (payload.collection.kind != (if (operation.kind == .decode) ManagedKind.string else ManagedKind.bytes)) return error.InternalError;
    return output;
}

fn validateOpBufferOperation(program: Program, function: Function, operation: BufferOperation) Error!void {
    if (@backingInt(operation.owner) >= function.scope.locals.len or !validType(operation.output, program)) return error.InternalError;
    const local = function.scope.locals[@backingInt(operation.owner)];
    if (!local.ty.isAggregate()) return error.InternalError;
    const schema = program.records[local.ty.recordIndex()];
    if (schema.shape.buffer == null or !schema.managed) return error.InternalError;
    return validateManagedOperation(program, local, operation);
}

fn validateOpResourceIo(program: Program, function: Function, io: @FieldType(@FieldType(Instruction, "op"), "resource_io")) Error!void {
    if (@backingInt(io.owner) >= function.scope.locals.len) return error.InternalError;
    const local = function.scope.locals[@backingInt(io.owner)];
    if (!local.mutable or typed.resourceKind(local.ty, program.records) == null) return error.InternalError;
    if (io.kind == .read) {
        if (io.input != null or typed.resourceReadShape(io.output, program.records) == null) return error.InternalError;
    } else {
        const shape = typed.resultShape(io.output, program.records) orelse return error.InternalError;
        if (shape.ok_type != .u64) return error.InternalError;
        if (shape.error_type != .i64) return error.InternalError;
        if (!typed.byteRequest(io.input orelse return error.InternalError, program.records)) return error.InternalError;
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

/// A raw lookup carries a fixed byte name and either the declared result record
/// or the Python `Option[str]` surface.
fn validateEnvironmentGet(program: Program, get: @FieldType(@FieldType(Instruction, "op"), "environment_get")) Error!void {
    if (!typed.byteRequest(get.name, program.records)) return error.InternalError;
    if (typed.environmentShape(get.output, program.records) != null) return;
    const option = prelude.optionShape(get.output, program.records) orelse return error.InternalError;
    if (!option.element.isAggregate() or option.element.recordIndex() >= program.records.len) return error.InternalError;
    if (program.records[option.element.recordIndex()].collection.kind != .string) return error.InternalError;
}

fn validateEnvironmentOnly(program: Program, only: @FieldType(@FieldType(Instruction, "op"), "environment_only")) Error!void {
    if (only.output != .environment_cap or !typed.byteRequest(only.names, program.records)) return error.InternalError;
}

fn validateEnvironmentNames(program: Program, names: @FieldType(@FieldType(Instruction, "op"), "environment_names")) Error!void {
    if (!names.output.isAggregate() or names.output.recordIndex() >= program.records.len) return error.InternalError;
    if (program.records[names.output.recordIndex()].collection.kind != .list) return error.InternalError;
}

/// Check one file operation's operand count, owner slot and declared payloads.
fn validateOpFile(program: Program, function: Function, op: @FieldType(Instruction, "op")) Error!void {
    const files = @import("file_operations.zig");
    switch (op) {
        .file_access => |call| {
            if (call.operands != call.kind.arity() or !validType(call.output, program)) return error.InternalError;
            if (call.output.isFile() and call.kind != .open) return error.InternalError;
            if (call.kind == .open and files.parseMode(&.{call.mode}) == null) return error.InternalError;
        },
        .file_method => |call| {
            if (@backingInt(call.owner) >= function.scope.locals.len) return error.InternalError;
            if (!function.scope.locals[@backingInt(call.owner)].ty.isFile()) return error.InternalError;
            if (call.kind.requiresArgument() and !call.argument) return error.InternalError;
            if (call.argument and !call.kind.takesArgument()) return error.InternalError;
        },
        else => return error.InternalError,
    }
}
fn validateOpAcquireBuffer(program: Program, ty: @FieldType(@FieldType(Instruction, "op"), "acquire_buffer")) Error!void {
    if (!validType(ty, program) or !ty.isAggregate()) return error.InternalError;
    const record = program.records[ty.recordIndex()];
    if (!record.managed or record.shape.buffer == null) return error.InternalError;
}

fn validateOpMakeRecord(allocator: std.mem.Allocator, program: Program, record: @FieldType(@FieldType(Instruction, "op"), "make_record")) Error!void {
    if (!record.ty.isAggregate() or !validType(record.ty, program)) return error.InternalError;
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
    if (propagate.output != function.signature.return_type or propagate.error_target >= function.scope.instructions.len) return error.InternalError;
    if (typed.resultShape(propagate.input, program.records)) |input| {
        const output = typed.resultShape(propagate.output, program.records) orelse return error.InternalError;
        if (input.error_type != output.error_type and typed.wrappingCase(program.records, output.error_type, input.error_type) == null) return error.InternalError;
        return;
    }
    if (prelude.optionShape(propagate.input, program.records)) |input| {
        const output = prelude.optionShape(propagate.output, program.records) orelse return error.InternalError;
        if (input.element != output.element) return error.InternalError;
        return;
    }
    return error.InternalError;
}

fn validateOpCall(program: Program, function: Function, id: @FieldType(@FieldType(Instruction, "op"), "call")) Error!void {
    if (@backingInt(id) >= program.functions.len) return error.InternalError;
    const callee = program.functions[@backingInt(id)];
    if (callee.signature.parameter_count > callee.scope.locals.len) return error.InternalError;
    if (callee.policy.restricted and function.policy.owner != callee.policy.owner) return error.InternalError;
    if (valueParameterCount(callee) != callee.signature.parameter_count) return error.InternalError;
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
            .function_value, .push_unit, .push_i64, .push_bool, .push_integer, .load_local, .move_local => height += 1,
            .drop_local, .begin_arena, .end_arena => {},
            .resource_io => |io| {
                height = try resourceIoHeight(io, height);
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
            .store_local, .pop, .acknowledge, .jump_if_false, .assert_true => {
                if (height == 0) return error.InternalError;
                height -= 1;
            },
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .cmp_i64, .cmp_bool, .binary_integer, .get_index, .cmp_enum, .cmp_domain => {
                if (height < 2) return error.InternalError;
                height -= 1;
            },
            .acquire_resource, .environment_get, .environment_only, .dir_resource, .host_resource => {
                if (height < 2) return error.InternalError;
                height -= 1;
            },
            .print => |output| {
                const operands = output.types.len + @intFromBool(output.separator) + @intFromBool(output.terminator) + @intFromBool(output.stream);
                if (height < operands) return error.InternalError;
                height = height - operands + 1;
            },
            .stream_write => {
                if (height < 2) return error.InternalError;
                height -= 1;
            },
            .file_access => |call| {
                if (height < call.operands) return error.InternalError;
                height = height - call.operands + 1;
            },
            .file_method => |call| {
                if (call.argument) {
                    if (height == 0) return error.InternalError;
                } else height += 1;
            },
            .arena_escape,
            .acquire_buffer,
            .restrict_resource,
            .complete_resource,
            .external_read,
            .environment_names,
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
            .invoke => |ty| {
                const contract = callables.signature(ty, program.records) orelse return error.InternalError;
                if (height <= contract.valueCount()) return error.InternalError;
                height -= contract.valueCount();
            },
            .call => |id| {
                const count = valueParameterCount(program.functions[@backingInt(id)]);
                if (height < count) return error.InternalError;
                height = height - count + 1;
            },
            .try_result => |propagate| {
                if (height == 0) return error.InternalError;
                // Failure unwinds unfinished operands and carries one error result.
                try enqueue(heights, pending, &len, propagate.error_target, 1);
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
    if (ty == .unit or ty.isFile()) return true;
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

fn resourceIoHeight(io: @FieldType(@FieldType(Instruction, "op"), "resource_io"), height: usize) Error!usize {
    if (io.kind != .write) return height + 1;
    if (height == 0) return error.InternalError;
    return height;
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
        if (!record.managed or record.contract.move_only) return error.InternalError;
        if (typed.moveOnly(element, program.records)) return error.InternalError;
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

fn validateFloatUnary(op: typed.UnaryOp) Error!void {
    if (op == .neg or op == .not) return error.InternalError;
}

fn validateFloatBinary(ty: typed.Type, op: typed.BinaryOp) Error!void {
    if (std.mem.startsWith(u8, @tagName(op), "f64_") and ty != .u64) return error.InternalError;
}
