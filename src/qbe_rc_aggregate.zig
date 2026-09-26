//! Transactional aggregate ownership while constructors and updates can fail.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const slots = @import("qbe_rc_slots.zig");
const state = @import("qbe_rc_state.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Native emitter failures shared by aggregate publication helpers.
pub const Error = values.Error;

/// Operations whose complete output ownership is published in this module.
pub fn handles(records: []const typed.Record, op: Op) bool {
    return switch (op) {
        .make_record => |record| !records[record.ty.recordIndex()].isCollection(),
        .make_variant, .update_record, .switch_variant => true,
        .replace_index => |access| !records[access.ty.recordIndex()].managed,
        else => false,
    };
}

/// Handle aggregates only when this function has a live ownership journal.
pub fn emit(comptime E: type, self: *E, op: Op, stack: []const typed.Type) Error!bool {
    if (frame.get(E, self) == null or !handles(self.program.records, op) or op == .replace_index) return false;
    switch (op) {
        .make_record => |record| try construct(E, self, record, stack.len),
        .make_variant => |variant| try variantValue(E, self, variant, stack.len),
        .update_record => |update| try updateValue(E, self, update, stack.len),
        .switch_variant => |dispatch| try dispatchValue(E, self, dispatch, stack.len),
        else => return error.InternalError,
    }
    return true;
}

fn region(comptime E: type, self: *E) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l call $myl_qbe_region_mark(l %ctx)\n", .{result});
    return result;
}

fn internal(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const index = frame.pending(E, self) + 1;
    try frame.entry(E, self, index, ty, address);
    try frame.initialized(E, self, index, true);
}

fn pending(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const index = frame.pending(E, self);
    try frame.entry(E, self, index, ty, address);
    try frame.initialized(E, self, index, true);
}

fn zero(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    try self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ address, (try self.layout(ty)).size });
}

const Field = struct { ty: typed.Type, source: usize, destination: usize, region: usize, operand: ?usize = null };
fn initialize(comptime E: type, self: *E, field: Field) Error!void {
    const shape = frame.get(E, self).?.catalog.get(field.ty) catch return error.InternalError;
    if (!shape.counted and !shape.unique_drop) {
        try self.writeValue(field.destination, try self.readValue(field.source, field.ty), field.ty);
        return;
    }
    try slots.Lower(E).transfer(self, .{ .ty = field.ty, .source = field.source, .destination = field.destination, .region = field.region, .mode = if (shape.unique_drop) .take_empty else .copy_empty });
    if (shape.unique_drop) if (field.operand) |index|
        try frame.initialized(E, self, values.journalIndex(E, self, index), false);
}

fn construct(comptime E: type, self: *E, record: @FieldType(Op, "make_record"), height: usize) Error!void {
    const managed = self.program.records[record.ty.recordIndex()].isManagedRecord();
    const pointer = if (managed)
        try @import("qbe_alloc.zig").cell(*E, self, record.ty, self.states[self.pc].?)
    else
        try self.aggregatePointer();
    if (managed) {
        try values.holdRuntime(E, self, record.ty, pointer);
    } else {
        try zero(E, self, record.ty, pointer);
        try internal(E, self, record.ty, pointer);
    }
    const depth = try region(E, self);
    const base = height - record.fields;
    for (0..record.fields) |i| {
        const index = if (record.order.len == 0) i else record.order[i];
        const member = try self.field(record.ty, index);
        try initialize(E, self, .{ .ty = member.ty, .source = try values.source(E, self, base + i, member.ty), .destination = try self.address(pointer, member.offset), .region = depth, .operand = base + i });
    }
    try self.store(base, pointer);
    try finish(E, self, .{ .ty = record.ty, .base = base, .consumed = record.fields, .origin = .owned });
}

fn variantValue(comptime E: type, self: *E, variant: @FieldType(Op, "make_variant"), height: usize) Error!void {
    const pointer = try self.aggregatePointer();
    try zero(E, self, variant.ty, pointer);
    try self.writeTag(variant.ty, variant.tag, pointer);
    try internal(E, self, variant.ty, pointer);
    const payload = self.program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag].payload;
    const base = height - @intFromBool(payload != null);
    if (payload) |ty| try initialize(E, self, .{
        .ty = ty,
        .source = try values.source(E, self, base, ty),
        .destination = try self.address(pointer, (try self.layout(variant.ty)).payload_offset),
        .region = try region(E, self),
        .operand = base,
    });
    try self.store(base, pointer);
    try @import("qbe_error_trace.zig").Lower(E).construction(self, variant.ty, variant.tag);
    try finish(E, self, .{ .ty = variant.ty, .base = base, .consumed = @intFromBool(payload != null), .origin = .owned });
}

fn finish(comptime E: type, self: *E, result: values.Result) Error!void {
    // Ownership moves into pending storage before any input destructor can run.
    // The intervening result load and journal stores cannot fail or call out.
    try values.commitRuntime(E, self);
    try values.finish(E, self, result);
}

/// Own the complete base before a fallible aggregate update or index check.
pub fn prepareBase(comptime E: type, self: *E, ty: typed.Type, base: usize) Error!usize {
    try values.prepareOperand(E, self, ty, base);
    const work = try values.workAddress(E, self);
    const managed = self.program.records[ty.recordIndex()].isManagedRecord();
    const storage = if (managed) blk: {
        const address = self.temp();
        try self.print(" %v{d} =l copy %rcinternal\n", .{address});
        break :blk address;
    } else try self.aggregatePointer();
    try self.print(" blit %v{d}, %v{d}, {d}\n", .{ work, storage, (try self.layout(ty)).size });
    try frame.initialized(E, self, frame.pending(E, self), false);
    try internal(E, self, ty, storage);
    if (managed) {
        const guard = try frame.guard(E, self, frame.pending(E, self) + 1);
        const unique = self.temp();
        try self.print(" %v{d} =w call $myl_qbe_rc_unique_local(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ unique, try self.descriptor(ty), storage, guard });
        try @import("qbe_rc_unique.zig").success(E, self, unique);
    }
    return if (managed) self.readValue(storage, ty) else storage;
}

fn replace(comptime E: type, self: *E, field: Field) Error!void {
    const work = try values.workAddress(E, self);
    try initialize(E, self, .{ .ty = field.ty, .source = field.source, .destination = work, .region = field.region, .operand = field.operand });
    try pending(E, self, field.ty, work);
    const shape = frame.get(E, self).?.catalog.get(field.ty) catch return error.InternalError;
    if (shape.unique_drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(field.ty), field.destination });
    if (shape.counted) try self.print(" call $myl_rc_native_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(field.ty), field.destination });
    try self.print(" blit %v{d}, %v{d}, {d}\n", .{ work, field.destination, (try self.layout(field.ty)).size });
    try frame.initialized(E, self, frame.pending(E, self), false);
}

fn updateValue(comptime E: type, self: *E, update: @FieldType(Op, "update_record"), height: usize) Error!void {
    const base = height - update.indices.len - 1;
    const pointer = try prepareBase(E, self, update.ty, base);
    const depth = if (self.program.records[update.ty.recordIndex()].isManagedRecord()) blk: {
        const result = self.temp();
        try self.print(" %v{d} =w call $myl_native_header_region(l %v{d})\n", .{ result, pointer });
        break :blk result;
    } else try region(E, self);
    for (update.indices, 0..) |index, i| {
        const member = try self.field(update.ty, index);
        try replace(E, self, .{ .ty = member.ty, .source = try values.source(E, self, base + 1 + i, member.ty), .destination = try self.address(pointer, member.offset), .region = depth, .operand = base + 1 + i });
    }
    try self.store(base, pointer);
    try finish(E, self, .{ .ty = update.ty, .base = base, .consumed = update.indices.len + 1, .origin = .owned });
}

fn dispatchValue(comptime E: type, self: *E, dispatch: @FieldType(Op, "switch_variant"), height: usize) Error!void {
    const pointer = try self.load("s", height - 1);
    const tag = try self.readTag(dispatch.ty, pointer);
    for (dispatch.arms, 0..) |arm, i| {
        const matches = self.temp();
        try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @rcarm{d}, @rcarmnext{d}\n@rcarm{d}\n", .{ matches, tag, i, matches, matches, matches, matches });
        if (arm.slot) |slot| if (!try @import("qbe_rc_narrowing.zig").bind(E, self, dispatch, @backingInt(slot))) {
            const index = @backingInt(slot);
            const ty = self.function.scope.locals[index].ty;
            const work = try values.workAddress(E, self);
            try initialize(E, self, .{ .ty = ty, .source = try self.address(pointer, (try self.layout(dispatch.ty)).payload_offset), .destination = work, .region = try region(E, self) });
            try pending(E, self, ty, work);
            try frame.drop(E, self, index);
            try self.print(" blit %v{d}, %l{d}, {d}\n", .{ work, index, (try self.layout(ty)).size });
            try frame.initialized(E, self, frame.pending(E, self), false);
            try frame.initialized(E, self, index, try state.owns(frame.get(E, self).?, ty));
        };
        try values.drop(E, self, height - 1);
        try self.print(" jmp @{s}{d}\n@rcarmnext{d}\n", .{ self.labelPrefix(arm.target), arm.target, matches });
    }
    try self.print(" jmp @failure\n", .{});
}

/// One checked fixed-array update and the instruction's consumed operand range.
pub const ArrayUpdate = struct { array: typed.Type, element: typed.Type, address: usize, source: usize, base: usize, input: usize };
/// Prepare the new element before retiring the old owning field, then publish.
pub fn arrayElement(comptime E: type, self: *E, update: ArrayUpdate) Error!void {
    try replace(E, self, .{ .ty = update.element, .source = try values.source(E, self, update.input, update.element), .destination = update.address, .region = try region(E, self), .operand = update.input });
    try self.store(update.base, update.source);
    try finish(E, self, .{ .ty = update.array, .base = update.base, .consumed = 3, .origin = .owned });
}

const Propagate = @FieldType(Op, "try_result");
const ErrorPayload = struct { input: typed.Type, output: typed.Type };
const TryShape = struct { success: typed.Type, success_tag: usize, error_tag: usize, payload: ?ErrorPayload = null };

/// Own the selected payload before retiring a consumed result or option.
pub fn propagation(comptime E: type, self: *E, operation: Propagate, stack: []const typed.Type) Error!bool {
    if (frame.get(E, self) == null) return false;
    const shape: TryShape = if (typed.resultShape(operation.input, self.program.records)) |input| blk: {
        const output = typed.resultShape(operation.output, self.program.records).?;
        break :blk .{ .success = input.ok_type, .success_tag = input.ok_tag, .error_tag = output.error_tag, .payload = .{ .input = input.error_type, .output = output.error_type } };
    } else if (@import("prelude.zig").optionShape(operation.input, self.program.records)) |input| blk: {
        const output = @import("prelude.zig").optionShape(operation.output, self.program.records).?;
        break :blk .{ .success = input.element, .success_tag = input.some, .error_tag = output.none };
    } else return error.InternalError;
    const source = try self.load("s", stack.len - 1);
    const tag = try self.readTag(operation.input, source);
    const success = self.temp();
    try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @rctryok{d}, @rctryerror{d}\n@rctryerror{d}\n", .{ success, tag, shape.success_tag, success, tag, tag, tag });
    if (typed.resultShape(operation.input, self.program.records)) |input| {
        try @import("qbe_error_trace.zig").Lower(E).propagation(self, input, typed.resultShape(operation.output, self.program.records).?);
    }
    const payload = try self.address(source, (try self.layout(operation.input)).payload_offset);
    try errorValue(E, self, operation, shape, .{ .address = payload, .height = stack.len });
    try self.print(" jmp @{s}{d}\n@rctryok{d}\n", .{ self.labelPrefix(operation.error_target), operation.error_target, tag });
    const pointer = try self.aggregatePointer();
    try zero(E, self, shape.success, pointer);
    try internal(E, self, shape.success, pointer);
    const selected = try self.address(source, (try self.layout(operation.input)).payload_offset);
    try initialize(E, self, .{ .ty = shape.success, .source = selected, .destination = pointer, .region = try region(E, self) });
    try self.store(stack.len - 1, try self.readValue(pointer, shape.success));
    try finish(E, self, .{ .ty = shape.success, .base = stack.len - 1, .consumed = 1, .origin = .owned });
    return true;
}

const InputPayload = struct { address: usize, height: usize };
fn errorValue(comptime E: type, self: *E, operation: Propagate, shape: TryShape, input: InputPayload) Error!void {
    const pointer = try self.aggregatePointer();
    try zero(E, self, operation.output, pointer);
    try self.writeTag(operation.output, shape.error_tag, pointer);
    if (shape.payload) |failure| {
        var destination = try self.address(pointer, (try self.layout(operation.output)).payload_offset);
        if (failure.input != failure.output) {
            const tag = typed.wrappingCase(self.program.records, failure.output, failure.input) orelse return error.InternalError;
            try self.writeTag(failure.output, tag, destination);
            destination = try self.address(destination, (try self.layout(failure.output)).payload_offset);
        }
        try internal(E, self, operation.output, pointer);
        try initialize(E, self, .{ .ty = failure.input, .source = input.address, .destination = destination, .region = try region(E, self) });
    } else try internal(E, self, operation.output, pointer);
    try self.store(0, pointer);
    try finish(E, self, .{ .ty = operation.output, .base = 0, .consumed = input.height, .origin = .owned });
}
