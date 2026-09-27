//! Operand result ownership at completed bytecode instruction boundaries.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Register a successful result before releasing the operands it consumed.
/// Branch payloads and local transfers publish at their explicit commit sites.
pub fn after(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!void {
    if (frame.get(E, self) == null or @import("qbe_rc_borrow.zig").active(E, self)) return;
    if (op == .get_field and @import("qbe_rc_record_read.zig").projection(E, self)) return;
    if (op == .get_field and try @import("qbe_rc_field_transfer.zig").project(E, self)) return;
    if (op == .store_local) try @import("qbe_rc_field_transfer.zig").committed(E, self);
    if (try @import("qbe_rc_views.zig").after(E, self, op, stack)) return;
    if (try @import("qbe_rc_variant_read.zig").after(E, self, op, stack)) return;
    if (try @import("qbe_rc_read_loans.zig").borrowedResult(E, self, op)) return;
    if (@import("qbe_rc_aggregate.zig").handles(self.program.records, op)) return;
    switch (op) {
        .load_local,
        .ref_local,
        .move_local,
        .value_copy,
        .store_local,
        .drop_local,
        .pop,
        .acknowledge,
        .ret,
        .jump,
        .jump_if_false,
        .switch_variant,
        .try_result,
        .assert_true,
        .begin_arena,
        .end_arena,
        .wrap_domain,
        .unwrap_domain,
        => return,
        else => {},
    }
    const next = self.states[self.pc + 1] orelse return error.InternalError;
    if (next.len == 0) return error.InternalError;
    const base = next.len - 1;
    if (base > stack.len) return error.InternalError;
    const cow = @import("qbe_cow.zig").Lower(E);
    if (cow.scopedProjection(self, self.pc) or @import("qbe_rc_inert_receiver.zig").projection(E, self, self.pc)) {
        // A prepared scope or proved stable owner keeps this receiver alive.
        // It is a physical projection, so no snapshot token is published.
        for (base..stack.len) |index| try values.drop(E, self, index);
    } else try values.finish(E, self, .{ .ty = next[base], .base = base, .consumed = stack.len - base, .origin = try origin(E, self, op) });
    if (op == .buffer_operation and (op.buffer_operation.kind.writesReceiver() or
        op.buffer_operation.kind == .set_add or op.buffer_operation.kind == .set_discard))
    {
        try cow.finishReceiver(self, @backingInt(op.buffer_operation.owner));
    }
}

/// Consumed unique arguments belong to the callee even when admission fails.
pub fn callEntry(comptime E: type, self: *E, callee: bytecode.Function, base: usize) Error!void {
    const state = frame.get(E, self) orelse return;
    for (callee.scope.locals[0..callee.signature.parameter_count], 0..) |local, index| {
        const shape = state.catalog.get(local.ty) catch return error.InternalError;
        if (shape.unique_drop) try frame.initialized(E, self, values.journalIndex(E, self, base + index), false);
    }
}

fn origin(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) Error!values.Origin {
    return switch (op) {
        .call => |target| if (try @import("qbe_rc_borrow.zig").certificate(E, self, self.program.functions[@backingInt(target)]) != null) .borrowed else .owned,
        .get_field => if (@import("qbe_rc_box_history.zig").boxMaterialization(E, self)) .owned else .borrowed,
        .cast_integer => |ty| identityCast(E, self, ty),
        .get_index => |access| if (self.program.records[access.ty.recordIndex()].collection.kind == .string) .owned else .borrowed,
        .make_record => |record| if (self.program.records[record.ty.recordIndex()].managed) .owned else .borrowed,
        .make_variant, .update_record, .replace_index => .borrowed,
        .buffer_operation => |operation| @import("qbe_rc_collections.zig").resultOrigin(self.program.records[self.function.scope.locals[@backingInt(operation.owner)].ty.recordIndex()].collection.kind, operation.kind),
        else => .owned,
    };
}

fn identityCast(comptime E: type, self: *E, ty: typed.Type) values.Origin {
    const stack = self.states[self.pc] orelse return .owned;
    return if (stack.len != 0 and stack[stack.len - 1] == ty) .borrowed else .owned;
}
