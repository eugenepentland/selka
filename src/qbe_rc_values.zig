//! Stable operand ownership and transactional value publication for RC lowering.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const slots = @import("qbe_rc_slots.zig");
const holds = @import("qbe_rc_holds.zig");
const loans = @import("qbe_rc_loans.zig");
const state_model = @import("qbe_rc_state.zig");
/// QBE byte relocation shared by transactional value and aggregate publication.
pub const blit_value = " blit %v{d}, %v{d}, {d}\n";
/// Errors shared with the native emitter.
pub const Error = slots.Error;
/// An already-owned runtime result is adopted; a read establishes a snapshot.
pub const Origin = enum { borrowed, owned };
/// The result replaces exactly the operand interval starting at base.
pub const Result = struct { ty: typed.Type, base: usize, consumed: usize, origin: Origin };

/// The stable value address held by a traced operand journal entry.
pub fn operand(comptime E: type, self: *E, index: usize) Error!usize {
    const address = self.temp();
    try self.print(" %v{d} =l copy %rcs{d}\n", .{ address, index });
    return address;
}
/// Address the current logical value; scalar operands live in the stack word.
pub fn source(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!usize {
    const address = self.temp();
    try self.print(" %v{d} =l {s} %s{d}\n", .{ address, if (self.isScalar(ty)) "copy" else "loadl", index });
    return address;
}
/// Drop the stable owned token without consulting an overwritten operand word.
pub fn drop(comptime E: type, self: *E, index: usize) Error!void {
    const state = frame.get(E, self) orelse return;
    const stack = self.states[self.pc] orelse return error.InternalError;
    if (index >= stack.len) return error.InternalError;
    // Every instruction consumes the prior owners before publishing its typed
    // result. A plain input therefore has no live obligation in this slot.
    if (!try state_model.owns(state, stack[index])) return;
    try frame.drop(E, self, journalIndex(E, self, index));
}
/// Prepare a borrowed publication before releasing any consumed owners.
pub fn copied(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const work = try workAddress(E, self);
    const region = try frame.region(E, self);
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = work, .source = address, .region = region, .mode = if (try loans.eligible(E, self, ty)) .retain_empty else .copy_empty });
    try markWork(E, self, ty);
}
/// Adopt the one edge returned by a runtime producer without another acquire.
pub fn adopted(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const work = try workAddress(E, self);
    try self.print(blit_value, .{ address, work, (try self.layout(ty)).size });
    try markWork(E, self, ty);
}
/// Materialize a result, drop its inputs, then relocate its obligation to the stack.
pub fn finish(comptime E: type, self: *E, result: Result) Error!void {
    const state = frame.get(E, self) orelse return;
    const owned = try state_model.owns(state, result.ty);
    if (owned) {
        const address = try source(E, self, result.base, result.ty);
        switch (result.origin) {
            .borrowed => if (try loans.eligible(E, self, result.ty))
                try loans.prepare(E, self, result.ty, address)
            else
                try copied(E, self, result.ty, address),
            .owned => try adopted(E, self, result.ty, address),
        }
    } else if (result.origin == .borrowed and !self.isScalar(result.ty)) {
        // A plain inline field can still live inside an owning operand. Its
        // parent cleanup clears that storage, so preserve the physical bytes
        // before dropping the parent even though the field owns no edges.
        const input = try self.load("s", result.base);
        const saved = try self.aggregatePointer();
        try self.print(blit_value, .{ input, saved, (try self.layout(result.ty)).size });
        try self.store(result.base, saved);
    }
    for (result.base..result.base + result.consumed) |index| try drop(E, self, index);
    if (owned) try publish(E, self, result.ty, result.base);
}
/// Relocate a fully prepared pending result into an empty operand position.
pub fn publish(comptime E: type, self: *E, ty: typed.Type, index: usize) Error!void {
    const address = try operand(E, self, index);
    const work = try workAddress(E, self);
    try self.print(blit_value, .{ work, address, (try self.layout(ty)).size });
    try frame.stableEntry(E, self, journalIndex(E, self, index), ty);
    try loans.copyRole(E, self, journalIndex(E, self, index), frame.pending(E, self));
    try frame.initialized(E, self, frame.pending(E, self), false);
    try frame.initialized(E, self, journalIndex(E, self, index), true);
    try self.store(index, try self.readValue(address, ty));
}
/// Publish a complete constructor whose input guards are already disarmed.
/// The caller retains an internal guard or proves its entire construction span
/// infallible. No callback may split this complete typed operand handoff.
pub fn constructed(comptime E: type, self: *E, ty: typed.Type, index: usize) Error!void {
    const state = frame.get(E, self) orelse return error.InternalError;
    if (try state_model.owns(state, ty)) {
        const input = try source(E, self, index, ty);
        const address = try operand(E, self, index);
        try self.print(blit_value, .{ input, address, (try self.layout(ty)).size });
        try frame.stableEntry(E, self, journalIndex(E, self, index), ty);
        try frame.initialized(E, self, journalIndex(E, self, index), true);
        try self.store(index, try self.readValue(address, ty));
    }
    try commitRuntime(E, self);
}
/// Index the operand's ownership flag independently of its logical stack value.
pub fn journalIndex(comptime E: type, self: *E, index: usize) usize {
    return self.function.scope.locals.len + index;
}
/// Address the frame-owned pending result, registered independently of operands.
pub fn workAddress(comptime E: type, self: *E) Error!usize {
    const work = self.temp();
    try self.print(" %v{d} =l copy %rcwork\n", .{work});
    return work;
}
fn markWork(comptime E: type, self: *E, ty: typed.Type) Error!void {
    try frame.stableEntry(E, self, frame.pending(E, self), ty);
    try frame.initialized(E, self, frame.pending(E, self), true);
}

/// Register a fresh pointer producer before any later fallible constructor step.
/// One internal producer may be active; its children are owned by that producer.
pub fn holdRuntime(comptime E: type, self: *E, ty: typed.Type, value: usize) Error!void {
    if (frame.get(E, self) == null) return;
    const address = self.temp();
    try self.print(" storel %v{d}, %rcinternal\n %v{d} =l copy %rcinternal\n", .{ value, address });
    const index = frame.pending(E, self) + 1;
    try frame.entry(E, self, index, ty, address);
    const flag = try frame.entryField(E, self, index, 24);
    try self.print(" storew 4, %v{d}\n", .{flag});
    try frame.initialized(E, self, frame.pending(E, self) + 1, true);
}
/// Hand the internal producer to the generic post-operation result adoption.
/// No fallible operation may intervene before that owned result is journaled.
pub fn commitRuntime(comptime E: type, self: *E) Error!void {
    if (frame.get(E, self) == null) return;
    try frame.initialized(E, self, frame.pending(E, self) + 1, false);
}

/// Consume an owned operand token, or copy a borrowed operand, into pending storage.
/// A pin-aware take can still allocate; its source guard changes only on success.
pub fn prepareOperand(comptime E: type, self: *E, ty: typed.Type, index: usize) Error!void {
    const address = try source(E, self, index, ty);
    if (try producedOwner(E, self, ty, index)) return prepareOwned(E, self, ty, address, journalIndex(E, self, index), true);
    try prepareGuarded(E, self, ty, address, journalIndex(E, self, index));
}

fn producedOwner(comptime E: type, self: *E, ty: typed.Type, index: usize) Error!bool {
    if (self.pc == 0 or self.branch_targets[self.pc]) return false;
    if (@import("qbe_rc_borrow.zig").active(E, self)) return false;
    if (holds.mayHold(E, self, ty)) return false;
    const state = frame.get(E, self) orelse return false;
    const shape = state.catalog.get(ty) catch return error.InternalError;
    if (!shape.counted or shape.unique_drop) return false;
    const stack = self.states[self.pc] orelse return false;
    if (stack.len == 0 or index != stack.len - 1) return false;
    var pc = self.pc;
    const no_scope = @import("cow_plan.zig").none;
    while (pc != 0) {
        if (self.branch_targets[pc]) return false;
        pc -= 1;
        const capture = self.cow.?.captures[pc];
        if (capture.begin != no_scope or capture.active != no_scope) return false;
        switch (self.function.scope.instructions[pc].op) {
            .value_copy => {
                const analysis = self.ownership orelse return true;
                if (pc >= analysis.copies.len or analysis.copies[pc]) return true;
            },
            .call => |target| {
                const certificate = try @import("qbe_rc_borrow.zig").certificate(E, self, self.program.functions[@backingInt(target)]);
                return certificate == null;
            },
            .make_record, .make_variant => return true,
            .move_local => |local| return !self.function.scope.locals[@backingInt(local)].usage.temporary,
            else => return false,
        }
    }
    return false;
}

fn prepareOwned(comptime E: type, self: *E, ty: typed.Type, address: usize, journal_index: usize, disjoint: bool) Error!void {
    const work = try workAddress(E, self);
    const region = try frame.region(E, self);
    // producedOwner admits only completed publications: scalar input bits are
    // in sN, wider values in rcsN. Both buffers are distinct from rcwork, whose
    // pending obligation was cleared before that producer finished publishing.
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = work, .source = address, .region = region, .mode = .take_empty, .disjoint = disjoint });
    try frame.initialized(E, self, journal_index, false);
    try markWork(E, self, ty);
}

/// Physical moves consume only an initialized owner; a borrowed local or operand
/// copies from its anchor even when semantic last-use analysis calls it a move.
pub fn prepareGuarded(comptime E: type, self: *E, ty: typed.Type, address: usize, journal_index: usize) Error!void {
    // Plain aggregate updates still stage their bits in work storage, but an
    // omitted operand has no ownership guard to inspect or transfer.
    if (!try state_model.owns(frame.get(E, self).?, ty)) return copied(E, self, ty, address);
    const label = self.temp();
    const transferable = try loans.owner(E, self, journal_index);
    try self.print(" jnz %v{d}, @rctake{d}, @rccopy{d}\n@rctake{d}\n", .{ transferable, label, label, label });
    try prepareOwned(E, self, ty, address, journal_index, false);
    try self.print(" jmp @rcprepared{d}\n@rccopy{d}\n", .{ label, label });
    try copied(E, self, ty, address);
    // A copied H token becomes an independent O only after success; refusal
    // keeps the original hold guarded for ordinary unwind.
    try frame.drop(E, self, journal_index);
    try self.print("@rcprepared{d}\n", .{label});
}

/// Preserve a compiler-private borrowed capture without creating a snapshot.
/// An existing ordinary owner remains an owner; a raw read acquires a loan.
pub fn preparePrivate(comptime E: type, self: *E, ty: typed.Type, address: usize, index: usize) Error!void {
    if (!try loans.eligible(E, self, ty)) return prepareGuarded(E, self, ty, address, index);
    const owner = try loans.owner(E, self, index);
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcprivateown{d}, @rcprivateloan{d}\n@rcprivateown{d}\n", .{ owner, label, label, label });
    try prepareOwned(E, self, ty, address, index, false);
    try self.print(" jmp @rcprivateprepared{d}\n@rcprivateloan{d}\n", .{ label, label });
    try loans.prepare(E, self, ty, address);
    try frame.drop(E, self, index);
    try self.print("@rcprivateprepared{d}\n", .{label});
}

/// Initialize an empty runtime output using pin-aware copy and mapped failure.
/// Its caller must immediately journal the successful result or commit it.
pub fn copyRuntime(comptime E: type, self: *E, ty: typed.Type, destination: usize, input: usize) Error!void {
    const region = try frame.region(E, self);
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = destination, .source = input, .region = region, .mode = if (try loans.eligible(E, self, ty)) .retain_empty else .copy_empty });
}
