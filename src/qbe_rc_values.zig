//! Stable operand ownership and transactional value publication for RC lowering.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const slots = @import("qbe_rc_slots.zig");
const blit_value = " blit %v{d}, %v{d}, {d}\n";
const region_mark = " %v{d} =l call $myl_qbe_region_mark(l %ctx)\n";
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
    if (!try @import("qbe_rc_state.zig").owns(state, stack[index])) return;
    try frame.drop(E, self, journalIndex(E, self, index));
}
/// Prepare a borrowed publication before releasing any consumed owners.
pub fn copied(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const work = try workAddress(E, self);
    const region = self.temp();
    try self.print(region_mark, .{region});
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = work, .source = address, .region = region, .mode = .copy_empty });
    try markWork(E, self, ty, work);
}
/// Adopt the one edge returned by a runtime producer without another acquire.
pub fn adopted(comptime E: type, self: *E, ty: typed.Type, address: usize) Error!void {
    const work = try workAddress(E, self);
    try self.print(blit_value, .{ address, work, (try self.layout(ty)).size });
    try markWork(E, self, ty, work);
}
/// Materialize a result, drop its inputs, then relocate its obligation to the stack.
pub fn finish(comptime E: type, self: *E, result: Result) Error!void {
    const state = frame.get(E, self) orelse return;
    const owned = try @import("qbe_rc_state.zig").owns(state, result.ty);
    if (owned) {
        const address = try source(E, self, result.base, result.ty);
        switch (result.origin) {
            .borrowed => try copied(E, self, result.ty, address),
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
    try frame.entry(E, self, journalIndex(E, self, index), ty, address);
    try frame.initialized(E, self, frame.pending(E, self), false);
    try frame.initialized(E, self, journalIndex(E, self, index), true);
    try self.store(index, try self.readValue(address, ty));
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
fn markWork(comptime E: type, self: *E, ty: typed.Type, work: usize) Error!void {
    try frame.entry(E, self, frame.pending(E, self), ty, work);
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
    const flag = self.temp();
    try self.print(" %v{d} =l add %rcentries, {d}\n storew 4, %v{d}\n", .{ flag, index * frame.entry_bytes + 24, flag });
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
    try prepareGuarded(E, self, ty, address, journalIndex(E, self, index));
}

/// Physical moves consume only an initialized owner; a borrowed local or operand
/// copies from its anchor even when semantic last-use analysis calls it a move.
pub fn prepareGuarded(comptime E: type, self: *E, ty: typed.Type, address: usize, journal_index: usize) Error!void {
    const guard_pointer = try frame.guard(E, self, journal_index);
    const live = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n jnz %v{d}, @rctake{d}, @rccopy{d}\n@rctake{d}\n", .{ live, guard_pointer, live, label, label, label });
    const work = try workAddress(E, self);
    const region = self.temp();
    try self.print(region_mark, .{region});
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = work, .source = address, .region = region, .mode = .take_empty });
    try frame.initialized(E, self, journal_index, false);
    try markWork(E, self, ty, work);
    try self.print(" jmp @rcprepared{d}\n@rccopy{d}\n", .{ label, label });
    try copied(E, self, ty, address);
    try self.print("@rcprepared{d}\n", .{label});
}

/// Initialize an empty runtime output using pin-aware copy and mapped failure.
/// Its caller must immediately journal the successful result or commit it.
pub fn copyRuntime(comptime E: type, self: *E, ty: typed.Type, destination: usize, input: usize) Error!void {
    const region = self.temp();
    try self.print(region_mark, .{region});
    try slots.Lower(E).transfer(self, .{ .ty = ty, .destination = destination, .source = input, .region = region, .mode = .copy_empty });
}
