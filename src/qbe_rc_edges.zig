//! Guarded releases of finished collection temporaries on empty-stack edges.
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
/// Failures shared with the concrete native emitter.
pub const Error = frame.Error;

/// Discharge the conservative straight-line part of the finalized CFG plan.
/// Nonparameter address borrowing is disabled in RC; captured receiver paths
/// retain their own holds, and final COW liveness includes implicit parent uses.
pub fn after(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) Error!void {
    const state = frame.get(E, self) orelse return;
    if (op != .store_local or @import("qbe_rc_borrow.zig").active(E, self)) return;
    for (state.plan.locals.edges) |edge| {
        if (edge.from != self.pc or edge.to != self.pc + 1) continue;
        for (edge.releases) |release| {
            const index = @backingInt(release.storage);
            if (!try eligible(E, self, self.pc, index)) continue;
            try frame.drop(E, self, index);
        }
    }
}

/// Whether an exact straight-line store edge really drops this physical local.
/// This includes emitter-only parent anchors omitted from semantic liveness.
pub fn releasesAt(comptime E: type, self: *E, pc: usize, index: usize) Error!bool {
    const state = frame.get(E, self) orelse return false;
    if (@import("qbe_rc_borrow.zig").active(E, self)) return false;
    if (self.function.scope.instructions[pc].op != .store_local) return false;
    if (!try eligible(E, self, pc, index)) return false;
    for (state.plan.locals.edges) |edge| {
        if (edge.from != pc or edge.to != pc + 1) continue;
        for (edge.releases) |release| if (@backingInt(release.storage) == index) return true;
    }
    return false;
}

fn eligible(comptime E: type, self: *E, pc: usize, index: usize) Error!bool {
    if (index < self.function.signature.parameter_count) return false;
    const local = self.function.scope.locals[index];
    if (!local.usage.temporary or self.byReference(index) or self.callerStorage(index)) return false;
    const shape = self.cow.?.rc.?.catalog.get(local.ty) catch return error.InternalError;
    if (!shape.counted or shape.unique_drop) return false;
    if (!self.isScalar(local.ty) or !local.ty.isAggregate()) return false;
    // Recursive boxes and inline loans still require their physical anchors.
    const record = self.program.records[local.ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return false;
    if (neededByReceiver(E, self, pc, index)) return false;
    return !@import("qbe_rc_inert_receiver.zig").emptyLocal(E, self, index);
}

fn neededByReceiver(comptime E: type, self: *E, pc: usize, owner: usize) bool {
    const plan = self.cow.?.plan;
    for (self.function.scope.locals, 0..) |_, index| {
        if (!self.live.?.after(pc, index)) continue;
        var at = index;
        var remaining = self.function.scope.locals.len;
        while (remaining != 0) : (remaining -= 1) {
            // A receiver can be read after its mutation scope ends. Its H
            // then no longer keeps the payload alive; the owning parent must.
            const parent = if (plan.place(at)) |place| place.parent else @import("qbe_rc_receivers.zig").receiverParent(E, self, at) orelse break;
            if (parent == owner) return true;
            at = parent;
        }
        // Malformed cyclic physical aliases must never authorize a release.
        if (remaining == 0) return true;
    }
    return false;
}
