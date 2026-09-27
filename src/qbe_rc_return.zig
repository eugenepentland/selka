//! Publish the canonical owned result before frame owners, scopes or arenas die.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Return through the ordinary guest ABI after transferring the result token.
pub fn emit(comptime E: type, self: *E, value: usize) Error!bool {
    const state = frame.get(E, self) orelse return false;
    const ty = self.function.signature.return_type;
    const owned = !@import("qbe_rc_borrow.zig").active(E, self) and try @import("qbe_rc_state.zig").owns(state, ty);
    var source = value;
    if (owned) {
        try fresh(E, self, value);
        const stack = self.states[self.pc] orelse return error.InternalError;
        if (returnedLocal(E, self, ty, stack.len)) |local| {
            // RC-RETURN-MOVE-1: the returned local's own owner becomes the
            // result; a local without one is still copied from its anchor.
            const address = self.temp();
            try self.print(" # RC-RETURN-MOVE-1 local {d}\n %v{d} =l copy %l{d}\n", .{ local, address, local });
            try values.prepareGuarded(E, self, ty, address, local);
        } else try values.prepareOperand(E, self, ty, stack.len - 1);
        source = try self.readValue(try values.workAddress(E, self), ty);
    }
    var output = source;
    if (try self.largeResult(self.function)) {
        try self.print(" blit %v{d}, %out, {d}\n", .{ source, (try self.layout(ty)).size });
        output = self.temp();
        try self.print(" %v{d} =l copy 0\n", .{output});
    } else if (self.heap_frame and !self.isScalar(ty)) {
        try self.print(" blit %v{d}, %return_storage, {d}\n", .{ source, try self.returnStorageBytes() });
        output = self.temp();
        try self.print(" %v{d} =l copy %return_storage\n", .{output});
    }
    if (owned) try frame.initialized(E, self, frame.pending(E, self), false);
    try frame.Lower(E).cleanup(self);
    try frame.Lower(E).leave(self);
    try @import("qbe_arena.zig").Lower(E).restore(self);
    if (self.heap_frame) try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n", .{});
    try self.leaveFrame();
    try self.print(" ret %v{d}\n", .{output});
    return true;
}

/// The named local `return local` reads, when the operand is that plain read
/// and the local's own frame slot and journal entry hold its value.
fn returnedLocal(comptime E: type, self: *E, ty: @import("typed.zig").Type, depth: usize) ?usize {
    const code = self.function.scope.instructions;
    if (depth != 1 or self.pc == 0 or self.isBranchTarget(self.pc)) return null;
    const read = code[self.pc - 1].op;
    if (read != .load_local) return null;
    const local = @backingInt(read.load_local);
    if (local < self.function.signature.parameter_count or self.function.scope.locals[local].ty != ty) return null;
    if (self.byReference(local) or self.callerStorage(local) or frame.emptyLocal(E, self, local)) return null;
    if (@import("qbe_rc_record_read.zig").empty(E, self, local)) return null;
    const state = frame.get(E, self) orelse return null;
    const slot = state.plan.journal.slot(local) catch return null;
    return if (slot == null) null else local;
}

// The closed constructor grammar has only scalar locals and linear owned
// operands. Every producer consumes its inputs and clears pending/internal
// guards; empty-stack branch edges preserve that fact. At ret, the sole live
// token is the ordinary result. The full journal remains linked until here,
// so allocation/arithmetic/frame/step failures keep their existing unwind.
fn fresh(comptime E: type, self: *E, value: usize) Error!void {
    const ty = self.function.signature.return_type;
    if ((try self.layout(ty)).size > 256) return;
    if (try self.largeResult(self.function)) return;
    if (!try @import("qbe_rc_fresh_constructor.zig").certify(E, self)) return;
    const index = values.journalIndex(E, self, 0);
    const owner = try @import("qbe_rc_loans.zig").owner(E, self, index);
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcfreshreturn{d}, @rcfreshreturnslow{d}\n@rcfreshreturn{d}\n", .{ owner, label, label, label });
    var output = value;
    if (!self.isScalar(ty)) {
        // The existing return work buffer is disjoint from stable operands.
        // Materialize the complete ABI result before disarming its source;
        // this successful path needs no pending token or source zeroing.
        output = try values.workAddress(E, self);
        try self.print(values.blit_value, .{ value, output, (try self.layout(ty)).size });
    }
    try frame.initialized(E, self, index, false);
    // No scope/arena instruction or external call is admitted. Self callees
    // preserve the entry region and scope checkpoint, including inside arenas.
    // Leave only validates/unlinks; no cleanup callback can split this handoff.
    try frame.Lower(E).leave(self);
    try self.leaveFrame();
    try self.print(" ret %v{d}\n@rcfreshreturnslow{d}\n", .{ output, label });
}
