//! RC local stores, moves and canonical owned return publication.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const state_model = @import("qbe_rc_state.zig");
const views = @import("qbe_rc_views.zig");
const loans = @import("qbe_rc_loans.zig");
/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Handle local ownership instructions whose legacy lowering copies raw bytes.
pub fn emit(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!bool {
    if (try @import("qbe_rc_borrow.zig").local(E, self, op, stack)) |handled| return handled;
    if (frame.get(E, self) == null) return false;
    if (try @import("qbe_rc_field_transfer.zig").local(E, self)) return true;
    if (try @import("qbe_rc_plain_record_write.zig").local(E, self, op, stack)) return true;
    switch (try views.local(E, self, op, stack)) {
        .handled => return true,
        .unhandled => return ordinary(E, self, op, stack),
        .ordinary => |label| {
            if (!try ordinary(E, self, op, stack)) return error.InternalError;
            try views.joined(E, self, label);
            return true;
        },
    }
}

fn ordinary(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!bool {
    const state = frame.get(E, self) orelse return false;
    switch (op) {
        .value_copy => |copy| {
            if (!try state_model.owns(state, copy.ty)) return true;
            const base = stack.len - 1;
            if (!@import("qbe_value_copy.zig").Lower(E).copies(self, self.pc)) return true;
            if (try loans.eligible(E, self, copy.ty)) {
                const history = @import("qbe_rc_history.zig");
                try history.prepare(E, self, .{
                    .ty = copy.ty,
                    .source = try values.source(E, self, base, copy.ty),
                    .journal = values.journalIndex(E, self, base),
                    .mode = history.mode(E, self, copy),
                });
            } else try values.prepareOperand(E, self, copy.ty, base);
            try values.publish(E, self, copy.ty, base);
        },
        .store_local => |local| {
            const index = @backingInt(local);
            const ty = self.function.scope.locals[index].ty;
            if (!try state_model.owns(state, ty)) return false;
            if (@import("qbe_value_copy.zig").Lower(E).selfStore(self, self.pc, index)) return selfStore(E, self, index, stack.len - 1);
            try store(E, self, index, stack.len - 1);
        },
        .drop_local => |local| try frame.drop(E, self, @backingInt(local)),
        .move_local => |local| {
            const index = @backingInt(local);
            const ty = self.function.scope.locals[index].ty;
            if (!try state_model.owns(state, ty)) return false;
            try move(E, self, index, stack.len);
        },
        .pop, .acknowledge => try values.drop(E, self, stack.len - 1),
        else => return false,
    }
    return true;
}

fn store(comptime E: type, self: *E, index: usize, operand: usize) Error!void {
    if (try @import("qbe_rc_record_read.zig").store(E, self, index, operand)) return;
    if (try @import("qbe_rc_readonly_anchor.zig").store(E, self, index, operand)) return;
    if (try @import("qbe_rc_read_loans.zig").store(E, self, index, operand)) return;
    const ty = self.function.scope.locals[index].ty;
    if (@import("qbe_rc_unique.zig").receiverParent(E, self, index)) |parent| {
        try receiverCleanup(E, self, index, operand);
        if (@import("qbe_rc_dictionary_tail.zig").store(E, self, index)) {
            try self.print(" # RC-DICTIONARY-TAIL-1 local {d} root {d}\n", .{ index, parent });
        } else try @import("qbe_rc_unique.zig").local(E, self, .{ .local = parent });
        const value = try self.load("l", parent);
        try @import("qbe_cow.zig").Lower(E).borrowReceiver(self, index, value);
        try self.print(" storel %v{d}, %l{d}\n", .{ value, index });
        return;
    }
    if (self.cow.?.plan.place(index) != null) {
        const value = try self.load("s", operand);
        try receiverCleanup(E, self, index, operand);
        try @import("qbe_cow.zig").Lower(E).borrowReceiver(self, index, value);
        try self.print(" storel %v{d}, %l{d}\n", .{ value, index });
        return;
    }
    if (self.function.scope.locals[index].usage.temporary and !self.callerStorage(index)) {
        try values.preparePrivate(E, self, ty, try values.source(E, self, operand, ty), values.journalIndex(E, self, operand));
    } else try values.prepareOperand(E, self, ty, operand);
    const destination = self.temp();
    if (self.callerStorage(index)) {
        try self.print(" %v{d} =l loadl %l{d}\n", .{ destination, index });
        // A mut reference is the caller's initialized owning slot, never a loan
        // that can be dropped through this frame's local ownership guard.
        const shape = frame.get(E, self).?.catalog.get(ty) catch return error.InternalError;
        if (shape.unique_drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), destination });
        if (shape.counted) try @import("qbe_rc_glue.zig").drop(E, self, .{ .ty = ty, .address = destination });
    } else {
        try frame.drop(E, self, index);
        try self.print(" %v{d} =l copy %l{d}\n", .{ destination, index });
    }
    const work = try values.workAddress(E, self);
    try self.print(" blit %v{d}, %v{d}, {d}\n", .{ work, destination, (try self.layout(ty)).size });
    try frame.initialized(E, self, frame.pending(E, self), false);
    if (!self.callerStorage(index)) {
        // This local may previously have held an H receiver token. The new
        // publication is an ordinary owning value, so restore its typed role.
        try frame.entry(E, self, index, ty, destination);
        try loans.copyRole(E, self, index, frame.pending(E, self));
        try frame.initialized(E, self, index, true);
    }
}

/// RC-SELF-STORE-1: `x = copy(x)` for a match binding whose payload copy the
/// ownership analysis elided stores the same bits back into `x`. While `x`
/// holds an ordinary owner the store is skipped; it used to retain the value
/// again and release the owner it replaced. Any other role takes the store.
fn selfStore(comptime E: type, self: *E, index: usize, operand: usize) Error!bool {
    // RC-READONLY-ANCHOR-1: a binding borrowed in place already holds the bits.
    if (@import("qbe_rc_readonly_anchor.zig").anchoredLocal(E, self, index)) return true;
    const owner = try loans.owner(E, self, index);
    const label = self.temp();
    try self.print(" # RC-SELF-STORE-1 local {d}\n jnz %v{d}, @rcselfkept{d}, @rcselfstore{d}\n@rcselfstore{d}\n", .{ index, owner, label, label, label });
    try store(E, self, index, operand);
    try self.print("@rcselfkept{d}\n", .{label});
    return true;
}

fn receiverCleanup(comptime E: type, self: *E, index: usize, operand: usize) Error!void {
    // This proof certifies both a permanently empty local guard and its
    // immediate borrowed input, including absence of a capture snapshot.
    if (@import("qbe_rc_inert_receiver.zig").emptyLocal(E, self, index)) return;
    try values.drop(E, self, operand);
    try frame.drop(E, self, index);
}

fn move(comptime E: type, self: *E, index: usize, operand_index: usize) Error!void {
    const ty = self.function.scope.locals[index].ty;
    const address = self.temp();
    const operation: []const u8 = if (self.byReference(index) or self.callerStorage(index)) "loadl" else "copy";
    try self.print(" %v{d} =l {s} %l{d}\n", .{ address, operation, index });
    if (self.function.scope.locals[index].usage.temporary and !self.callerStorage(index)) {
        try values.preparePrivate(E, self, ty, address, index);
    } else try values.prepareGuarded(E, self, ty, address, index);
    try values.publish(E, self, ty, operand_index);
}
