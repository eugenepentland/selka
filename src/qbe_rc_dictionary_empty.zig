//! Exact zero-guard consumers after a canonical fresh dictionary handoff.
const model = @import("rc_dictionary_tail.zig");
const cow = @import("cow_plan.zig");
/// Optional physical proof failures leave every original drop in place.
pub const Error = @import("qbe_rc_frame.zig").Error;

/// The caller already proved the whole reset-to-backedge CFG/effects corridor.
/// Check actual store lowering and every remaining operand publisher separately.
pub fn certify(comptime E: type, self: *E, proof: model.Certificate, reset: usize, back: usize, budget: *model.Budget) Error!?model.EmptyDrops {
    if (!budget.take(self.cow.?.rc.?.plan.dictionary_tails.len + 1)) return null;
    if (!canonical(E, self, proof, reset)) return null;
    const code = self.function.scope.instructions;
    var get: ?usize = null;
    for (reset + 1..back + 1) |pc| {
        if (!budget.take(1)) return null;
        const op = code[pc].op;
        const stack = self.states[pc] orelse return null;
        for (stack, 0..) |ty, index| {
            if (!budget.take(1)) return null;
            const shape = self.cow.?.rc.?.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
            if (shape.unique_drop) return null;
            if (!shape.counted) continue;
            if (index != 0 or !rawInput(E, self, proof, pc, ty)) return null;
        }
        if (op != .buffer_operation or op.buffer_operation.kind != .get) continue;
        if (get != null or @backingInt(op.buffer_operation.owner) != proof.root) return null;
        if (stack.len != 2 or stack[0] != self.function.scope.locals[proof.key].ty) return null;
        get = pc;
    }
    return .{ .reset = reset, .back = back, .get = get orelse return null };
}

// These conditions select ordinary named store -> prepareOperand. Its complete
// successful paths clear the input guard before local replacement/publication.
// The late loop's quiet scan includes this store's after/early-release hooks.
fn canonical(comptime E: type, self: *E, proof: model.Certificate, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (pc == 0 or proof.key_authority != .anchored) return false;
    const stack = self.states[pc] orelse return false;
    const before = self.states[pc - 1] orelse return false;
    const after = self.states[pc + 1] orelse return false;
    if (before.len != 0 or stack.len != 1 or after.len != 0) return false;
    const local = self.function.scope.locals[proof.root];
    if (stack[0] != local.ty or local.usage.temporary) return false;
    if (code[pc].op != .store_local or @backingInt(code[pc].op.store_local) != proof.root) return false;
    if (code[pc - 1].op != .make_record or code[pc - 1].op.make_record.fields != 0) return false;
    if (code[pc - 1].op.make_record.ty != local.ty) return false;
    const state = self.cow.?.rc.?;
    const role = state.plan.locals.entry[proof.root];
    if (@backingInt(role.storage) != proof.root or (role.ownership != .empty and role.ownership != .plain)) return false;
    if (self.byReference(proof.root) or self.callerStorage(proof.root) or self.moves.resolve(proof.root) != proof.root) return false;
    if (self.cow.?.plan.place(proof.root) != null or self.cow.?.plan.aliases[proof.root] != cow.none) return false;
    // The finalized tail already refuses type-wide mayHold/iteration roots;
    // the successful late lifetime scan includes this store's interceptors.
    return !model.borrowedStore(state.plan.dictionary_tails, pc, proof.root);
}

// Only exact already-raw producers may carry a managed word in the closed
// corridor. Other admitted opcodes have scalar inputs and no guard-address API.
fn rawInput(comptime E: type, self: *E, proof: model.Certificate, pc: usize, ty: @import("typed.zig").Type) bool {
    const code = self.function.scope.instructions;
    const key = proof.key_authority.anchored;
    const locals = self.function.scope.locals;
    if (pc == key.capture) return ty == locals[key.receiver].ty;
    if (pc == key.projection + 1) return ty == locals[proof.key].ty;
    if (pc == proof.start + 1) return ty == locals[proof.root].ty;
    if (pc <= key.projection + 1 or ty != locals[proof.key].ty) return false;
    const op = code[pc].op;
    if (op == .load_local) return pc == proof.start + 3;
    if (op == .buffer_operation) return op.buffer_operation.kind == .get or pc == proof.start + 4;
    // A scalar default literal may be pushed after the raw key load.
    return op == .push_i64 or op == .push_integer or op == .push_bool;
}
