//! Live dictionary views retain header identity through H-only physical tokens.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const semantics = @import("value_semantics.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Native emitter failures shared with typed ownership lowering.
pub const Error = values.Error;
const holds = @import("qbe_rc_holds.zig");
/// A held branch either completed an operation or wraps its ordinary branch.
pub const Local = union(enum) { unhandled, handled, ordinary: usize };

fn dictionary(comptime E: type, self: *E, ty: typed.Type) bool {
    return ty.isAggregate() and self.program.records[ty.recordIndex()].collection.kind == .dictionary;
}

/// Construct the inline view through its H shape while the input O is still live.
pub fn construct(comptime E: type, self: *E, record: @FieldType(Op, "make_record"), height: usize) Error!bool {
    if (!semantics.isLiveView(self.program.records, record.ty)) return false;
    if (record.fields != 1 or (try self.layout(record.ty)).size != 8) return error.InternalError;
    const base = height - 1;
    const source_type = self.states[self.pc].?[base];
    if (!dictionary(E, self, source_type)) return error.InternalError;
    try values.copied(E, self, record.ty, try values.source(E, self, base, source_type));
    try values.drop(E, self, base);
    try values.publish(E, self, record.ty, base);
    return true;
}

/// Replacing the public mapping field retires and publishes held view tokens.
pub fn update(comptime E: type, self: *E, record: @FieldType(Op, "update_record"), height: usize) Error!bool {
    if (!semantics.isLiveView(self.program.records, record.ty)) return false;
    if (record.indices.len != 1 or record.indices[0] != 0) return error.InternalError;
    const base = height - 2;
    const input = self.states[self.pc].?[base + 1];
    if (!dictionary(E, self, input)) return error.InternalError;
    try values.copied(E, self, record.ty, try values.source(E, self, base + 1, input));
    // A field assignment stages its RHS in a compiler temporary. Retaining its
    // dead O token would turn the newly installed live view into a snapshot.
    // The normal liveness solution proves the local has no remaining reads.
    if (self.pc != 0) {
        const prior = self.function.scope.instructions[self.pc - 1].op;
        if (prior == .load_local) {
            const local_index = @backingInt(prior.load_local);
            if (self.function.scope.locals[local_index].usage.temporary and !self.live.?.after(self.pc, local_index))
                try frame.drop(E, self, local_index);
        }
    }
    try values.drop(E, self, base + 1);
    try values.drop(E, self, base);
    try values.publish(E, self, record.ty, base);
    return true;
}

/// Extracting the mapping retains identity rather than creating a COW snapshot.
pub fn after(comptime E: type, self: *E, op: Op, stack: []const typed.Type) Error!bool {
    if (op != .get_field or stack.len == 0) return false;
    const base = stack.len - 1;
    if (!semantics.isLiveView(self.program.records, stack[base])) return false;
    if (op.get_field != 0) return error.InternalError;
    const ty = self.states[self.pc + 1].?[base];
    if (!dictionary(E, self, ty)) return error.InternalError;
    try acquire(E, self, ty, try self.load("s", base));
    try values.drop(E, self, base);
    try publish(E, self, ty, base);
    return true;
}

fn entry(comptime E: type, self: *E, ty: typed.Type, index: usize, address: usize) Error!void {
    try frame.entry(E, self, index, ty, address);
    const at = self.temp();
    try self.print(" %v{d} =l add %rcentries, {d}\n storew {d}, %v{d}\n", .{ at, index * frame.entry_bytes + 24, holds.flag, at });
    try frame.initialized(E, self, index, true);
}

fn acquire(comptime E: type, self: *E, ty: typed.Type, payload: usize) Error!void {
    const work = try values.workAddress(E, self);
    const status = self.temp();
    const ok = self.temp();
    try self.print(" storel 0, %v{d}\n", .{work});
    try self.print(" %v{d} =w call $myl_rc_hold_acquire(l %heap, l %v{d}, l %v{d})\n", .{ status, payload, work });
    try self.print(" %v{d} =w call $myl_qbe_rc_status(l %ctx, w %v{d})\n", .{ ok, status });
    try @import("qbe_rc_unique.zig").success(E, self, ok);
    try entry(E, self, ty, frame.pending(E, self), work);
}

fn publish(comptime E: type, self: *E, ty: typed.Type, index: usize) Error!void {
    const address = try values.operand(E, self, index);
    const work = try values.workAddress(E, self);
    const payload = try self.readValue(work, ty);
    try self.writeValue(address, payload, ty);
    try entry(E, self, ty, values.journalIndex(E, self, index), address);
    try frame.initialized(E, self, frame.pending(E, self), false);
    try self.store(index, payload);
}

/// Preserve H for compiler receiver temporaries; named bindings use ordinary O.
/// On an H branch, this emits the complete operation and jumps past its normal
/// lowering. The caller emits that normal lowering and then calls joined().
pub fn local(comptime E: type, self: *E, op: Op, stack: []const typed.Type) Error!Local {
    switch (op) {
        .load_local => |id| {
            const index = @backingInt(id);
            const ty = self.function.scope.locals[index].ty;
            if (!holds.mayHold(E, self, ty)) return .unhandled;
            try load(E, self, ty, index, stack.len);
            return .handled;
        },
        .move_local => |id| {
            const index = @backingInt(id);
            const ty = self.function.scope.locals[index].ty;
            if (!holds.mayHold(E, self, ty)) return .unhandled;
            const label = try branch(E, self, index);
            try move(E, self, ty, index, stack.len);
            try ordinary(E, self, label);
            return .{ .ordinary = label };
        },
        .store_local => |id| {
            const index = @backingInt(id);
            const target = self.function.scope.locals[index];
            if (!target.usage.temporary or !holds.mayHold(E, self, target.ty)) return .unhandled;
            const operand = stack.len - 1;
            const label = try branch(E, self, values.journalIndex(E, self, operand));
            try store(E, self, target.ty, index, operand);
            try ordinary(E, self, label);
            return .{ .ordinary = label };
        },
        .value_copy => |copy| {
            if (copy.site != .assign or !holds.mayHold(E, self, copy.ty)) return .unhandled;
            const label = try branch(E, self, values.journalIndex(E, self, stack.len - 1));
            try ordinary(E, self, label);
            return .{ .ordinary = label };
        },
        else => return .unhandled,
    }
}

fn branch(comptime E: type, self: *E, index: usize) Error!usize {
    const label = self.temp();
    const condition = try holds.held(E, self, index);
    try self.print(" jnz %v{d}, @rchold{d}, @rcordinary{d}\n@rchold{d}\n", .{ condition, label, label, label });
    return label;
}
fn ordinary(comptime E: type, self: *E, label: usize) Error!void {
    try self.print(" jmp @rcholdjoined{d}\n@rcordinary{d}\n", .{ label, label });
}
/// Finish the ordinary alternative of a terminal H-token operation.
pub fn joined(comptime E: type, self: *E, label: usize) Error!void {
    try self.print("@rcholdjoined{d}\n", .{label});
}

fn load(comptime E: type, self: *E, ty: typed.Type, index: usize, operand: usize) Error!void {
    const payload = try self.load("l", index);
    const label = try branch(E, self, index);
    try acquire(E, self, ty, payload);
    try publish(E, self, ty, operand);
    try ordinary(E, self, label);
    try self.store(operand, payload);
    try joined(E, self, label);
}

fn move(comptime E: type, self: *E, ty: typed.Type, index: usize, operand: usize) Error!void {
    const work = try values.workAddress(E, self);
    try self.writeValue(work, try self.load("l", index), ty);
    try entry(E, self, ty, frame.pending(E, self), work);
    try frame.initialized(E, self, index, false);
    try self.print(" storel 0, %l{d}\n", .{index});
    try publish(E, self, ty, operand);
}

fn store(comptime E: type, self: *E, ty: typed.Type, index: usize, operand: usize) Error!void {
    const work = try values.workAddress(E, self);
    try self.writeValue(work, try self.load("s", operand), ty);
    try entry(E, self, ty, frame.pending(E, self), work);
    try frame.initialized(E, self, values.journalIndex(E, self, operand), false);
    try frame.drop(E, self, index);
    const address = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, index });
    try self.writeValue(address, try self.readValue(work, ty), ty);
    try entry(E, self, ty, index, address);
    try frame.initialized(E, self, frame.pending(E, self), false);
}
