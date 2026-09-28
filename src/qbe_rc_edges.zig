//! Guarded releases of finished collection temporaries on empty-stack edges.
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
/// Failures shared with the concrete native emitter.
pub const Error = frame.Error;

/// Shared refusal boundary for proofs that retain an interior pointer to the next PC.
pub fn boundaryQuiet(op: @FieldType(bytecode.Instruction, "op")) bool {
    return op != .store_local;
}

/// Discharge the conservative straight-line part of the finalized CFG plan.
/// Nonparameter address borrowing is disabled in RC; captured receiver paths
/// retain their own holds, and final COW liveness includes implicit parent uses.
pub fn after(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) Error!void {
    const state = frame.get(E, self) orelse return;
    if (boundaryQuiet(op) or @import("qbe_rc_borrow.zig").active(E, self)) return;
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
    if (@import("qbe_rc_record_read.zig").empty(E, self, index)) return false;
    if (index < self.function.signature.parameter_count) return false;
    const local = self.function.scope.locals[index];
    if (!local.usage.temporary and !named(E, self, index)) return false;
    if (self.byReference(index) or self.callerStorage(index)) return false;
    const shape = self.cow.?.rc.?.catalog.get(local.ty) catch return error.InternalError;
    if (!shape.counted or shape.unique_drop) return false;
    if (!self.isScalar(local.ty) or !local.ty.isAggregate()) return false;
    // Recursive boxes and inline loans still require their physical anchors.
    const record = self.program.records[local.ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return false;
    if (neededByReceiver(E, self, pc, index)) return false;
    return !@import("qbe_rc_inert_receiver.zig").emptyLocal(E, self, index);
}

/// RC-NAMED-RELEASE-1: a named local the program only ever reads and
/// rebinds whole is released on the first straight-line store edge after its
/// last use, as a finished temporary is, instead of when its next value is
/// stored or the frame exits: an owning slot no move shares, no loop iterates,
/// no other local is filled from, and no copy-on-write site, place, alias or
/// loop entry names. A local another slot captured would only trade its
/// owner for that slot's hold, which then retires the value.
fn named(comptime E: type, self: *E, index: usize) bool {
    if (self.function.scope.locals[index].origin != .local) return false;
    if (self.moves.aliased(index) or @import("cow_plan.zig").iterationOwner(self.function, index)) return false;
    for (0..self.function.scope.locals.len) |other| if (other != index and self.moves.resolve(other) == index) return false;
    const code = self.function.scope.instructions;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .load_local or @backingInt(instruction.op.load_local) != index) continue;
        var next = pc + 1;
        if (next < code.len and code[next].op == .value_copy) next += 1;
        if (next < code.len and code[next].op == .store_local and @backingInt(code[next].op.store_local) != index) return false;
    }
    const entry = self.cow.?.rc.?.plan.locals.entry[index];
    if (@backingInt(entry.storage) != index or entry.ownership != .empty) return false;
    return unwritten(self.cow.?.plan, index);
}

/// No copy-on-write site, place, alias or loop entry names `local`: no
/// implicit clone installation or recovered place may publish it.
pub fn unwritten(plan: @import("cow_plan.zig").Plan, local: usize) bool {
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == local or unique.alias == local) return false;
        if (site.unique_field) |place| if (place.parent == local) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == local) return false;
    for (plan.aliases) |parent| if (parent == local) return false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (place.parent == local) return false;
        if (place.box) |box| if (box.owner == local) return false;
    };
    return true;
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
