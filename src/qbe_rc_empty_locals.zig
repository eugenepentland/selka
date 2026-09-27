//! Bounded certificates for managed local slots that never acquire a token.
const frame = @import("qbe_rc_frame.zig");
const cow = @import("cow_plan.zig");
const inert = @import("qbe_rc_inert_receiver.zig");

/// Finalize emission-only omissions after physical loop checks are settled.
/// Every uncertain writer retains its journal; operands and scratch stay owned.
pub fn finalize(comptime E: type, self: *E) frame.Error!void {
    const state = frame.get(E, self) orelse return;
    const empty = try self.allocator.alloc(bool, self.function.scope.locals.len);
    @memset(empty, false);
    var budget: usize = 262144;
    const code = self.function.scope.instructions;
    if (code.len <= 4096) for (self.function.scope.locals, 0..) |local, index| {
        if (!local.usage.temporary or index < self.function.signature.parameter_count) continue;
        if (self.byReference(index) or self.callerStorage(index)) continue;
        const shape = state.catalog.get(local.ty) catch return error.InternalError;
        if (!shape.counted or shape.unique_drop) continue;
        if (@import("qbe_rc_holds.zig").mayHold(E, self, local.ty)) continue;
        if (code.len > budget) break;
        budget -= code.len;
        const at = definition(E, self, index) orelse continue;
        if (!writers(self.cow.?.plan, index)) continue;
        empty[index] = anchored(E, self, index, at) or inert.emptyLocal(E, self, index);
    };
    const previous = state.plan.journal;
    state.plan.journal = try previous.omitting(self.allocator, empty);
    self.allocator.free(previous.prefix);
}

fn definition(comptime E: type, self: *E, index: usize) ?usize {
    var result: ?usize = null;
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == index) {
            if (result != null) return null;
            result = pc;
        },
        .move_local, .ref_local => |id| if (@backingInt(id) == index) return null,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == index) return null;
        },
        else => {},
    };
    const at = result orelse return null;
    return if (at == 0 or self.isBranchTarget(at)) null else at;
}

// These helpers can publish a clone or reset a role without a store opcode.
fn writers(plan: cow.Plan, index: usize) bool {
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == index or unique.alias == index) return false;
        if (site.unique_field) |place| if (place.parent == index) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == index) return false;
    for (plan.aliases) |parent| if (parent == index) return false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (place.parent == index) return false;
        if (place.box) |box| if (box.owner == index) return false;
    };
    return true;
}

fn anchored(comptime E: type, self: *E, index: usize, at: usize) bool {
    const entries = self.cow.?.rc.?.plan.locals.entry;
    const role = entries[index].ownership;
    if (role != .borrowed or role.borrowed != .storage) return false;
    const plan = self.cow.?.plan;
    for (at - 1..at + 1) |pc| {
        const site = plan.at(pc);
        if (site.read_captures.len != 0 or site.shares.len != 0) return false;
    }
    const op = self.function.scope.instructions[at - 1].op;
    if (op == .load_local) return @backingInt(op.load_local) == @backingInt(role.borrowed.storage);
    if (op != .buffer_operation or op.buffer_operation.kind != .read) return false;
    const parent = entries[@backingInt(op.buffer_operation.owner)].ownership;
    return parent == .borrowed and parent.borrowed == .storage and
        parent.borrowed.storage == role.borrowed.storage;
}
