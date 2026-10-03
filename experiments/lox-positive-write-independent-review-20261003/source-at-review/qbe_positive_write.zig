//! Skip only a quiet negative-index normalizer; the checked write stays intact.
const positive = @import("qbe_positive_index.zig");
const Error = @import("qbe_managed.zig").Error;

/// QBE-POSITIVE-WRITE-1: reuse the original index-load/RHS/write join when the
/// original signed index is nonnegative. A failed guard keeps the whole body.
pub fn emit(comptime E: type, self: *E, start: usize) Error!void {
    if (!self.checks or self.step_checks) return;
    if (self.version != null or self.original != null) return;
    const proof = positive.normalizerPrefix(self.function.scope.instructions, start) orelse return;
    if (!try plainWrite(E, self, proof)) return;
    if (!try quietPrefix(E, self, proof)) return;
    const value = try self.load("l", proof.index);
    const valid = self.temp();
    try self.print(" # QBE-POSITIVE-WRITE-1 start {d} join {d}\n", .{ start, start + 9 });
    try self.print(" %v{d} =w csgel %v{d}, 0\n", .{ valid, value });
    try self.print(" jnz %v{d}, @{s}{d}, @{s}{d}\n", .{ valid, self.labelPrefix(start + 9), start + 9, self.labelPrefix(start), start });
}

fn plainWrite(comptime E: type, self: *E, proof: positive.Certificate) Error!bool {
    const code = self.function.scope.instructions;
    const at = proof.start + 11;
    if (at >= code.len or code[at].op != .buffer_operation) return false;
    const op = code[at].op.buffer_operation;
    if (op.kind != .write or @backingInt(op.owner) != proof.owner or op.output != .unit) return false;
    if (code[at - 1].op != .load_local) return false;
    const value = @backingInt(code[at - 1].op.load_local);
    const locals = self.function.scope.locals;
    const index = locals[proof.index];
    if (index.ty != .i64 or !index.usage.temporary) return false;
    if (self.byReference(proof.index) or self.callerStorage(proof.index)) return false;
    if (!plainReceiver(E, self, proof.owner)) return false;
    const receiver = locals[proof.owner].ty;
    const element = self.program.records[receiver.recordIndex()].shape.buffer orelse return false;
    if (locals[value].ty != element) return false;
    const layout = try self.layout(element);
    if (layout.drop or layout.trace or layout.size < 2) return false;
    return !@import("value_semantics.zig").containsLiveView(self.program.records, element);
}

fn plainReceiver(comptime E: type, self: *E, owner: usize) bool {
    if (self.byReference(owner) or self.callerStorage(owner)) return false;
    // Named mut-list receiver aliases may carry a pin scope even when there
    // is no pending field place in captures[]. Keep that full original route.
    const cow = self.cow orelse return false;
    if (cow.rc == null) return false;
    if (cow.plan.aliases[owner] != @import("cow_plan.zig").none) return false;
    const receiver = self.function.scope.locals[owner].ty;
    if (!receiver.isAggregate()) return false;
    const schema = self.program.records[receiver.recordIndex()];
    if (!schema.isCollection() or schema.collection.kind != .list or schema.collection.box) return false;
    // A callback can end the pending place scope before normalization while
    // leaving an RC receiver pin outside captures[]. Require the existing
    // whole capture-to-write inert proof, not merely a quiet scalar prefix.
    return @import("qbe_rc_inert_receiver.zig").proven(E, self, owner);
}

fn quietPrefix(comptime E: type, self: *E, proof: positive.Certificate) Error!bool {
    const start = proof.start;
    const before = self.states[start] orelse return false;
    const join = self.states[start + 9] orelse return false;
    if (before.len != join.len) return false;
    for (before, join) |left, right| {
        const layout = try self.layout(left);
        if (left != right or layout.drop or layout.trace) return false;
    }
    if (positive.extraEntry(self.function.scope.instructions, start)) return false;
    for (start..start + 9) |pc| {
        if (self.states[pc] == null) return false;
        if (pc != start and self.isBranchTarget(pc)) return false;
        if (!try positive.quiet(E, self, pc)) return false;
    }
    return true;
}
