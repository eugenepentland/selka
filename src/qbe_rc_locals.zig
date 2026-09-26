//! RC local stores, moves and canonical owned return publication.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const state_model = @import("qbe_rc_state.zig");
/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Handle local ownership instructions whose legacy lowering copies raw bytes.
pub fn emit(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!bool {
    const state = frame.get(E, self) orelse return false;
    switch (op) {
        .value_copy => |copy| {
            if (!try state_model.owns(state, copy.ty)) return true;
            const base = stack.len - 1;
            try values.prepareOperand(E, self, copy.ty, base);
            try values.publish(E, self, copy.ty, base);
        },
        .store_local => |local| {
            const index = @backingInt(local);
            const ty = self.function.scope.locals[index].ty;
            if (!try state_model.owns(state, ty)) return false;
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
    const ty = self.function.scope.locals[index].ty;
    if (@import("qbe_rc_unique.zig").receiverParent(E, self, index)) |parent| {
        try values.drop(E, self, operand);
        try frame.drop(E, self, index);
        const value = try self.load("l", parent);
        try self.print(" storel %v{d}, %l{d}\n", .{ value, index });
        return;
    }
    try values.prepareOperand(E, self, ty, operand);
    const destination = self.temp();
    if (self.callerStorage(index)) {
        try self.print(" %v{d} =l loadl %l{d}\n", .{ destination, index });
        // A mut reference is the caller's initialized owning slot, never a loan
        // that can be dropped through this frame's local ownership guard.
        const shape = frame.get(E, self).?.catalog.get(ty) catch return error.InternalError;
        if (shape.unique_drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), destination });
        if (shape.counted) try self.print(" call $myl_rc_native_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), destination });
    } else {
        try frame.drop(E, self, index);
        try self.print(" %v{d} =l copy %l{d}\n", .{ destination, index });
    }
    const work = try values.workAddress(E, self);
    try self.print(" blit %v{d}, %v{d}, {d}\n", .{ work, destination, (try self.layout(ty)).size });
    try frame.initialized(E, self, frame.pending(E, self), false);
    if (!self.callerStorage(index)) try frame.initialized(E, self, index, true);
}

fn move(comptime E: type, self: *E, index: usize, operand_index: usize) Error!void {
    const ty = self.function.scope.locals[index].ty;
    const address = self.temp();
    const region = self.temp();
    const work = try values.workAddress(E, self);
    try self.print(" %v{d} =l copy %l{d}\n %v{d} =l call $myl_qbe_region_mark(l %ctx)\n", .{ address, index, region });
    try @import("qbe_rc_slots.zig").Lower(E).transfer(self, .{ .ty = ty, .destination = work, .source = address, .region = region, .mode = .take_empty });
    try frame.initialized(E, self, index, false);
    try frame.entry(E, self, frame.pending(E, self), ty, work);
    try frame.initialized(E, self, frame.pending(E, self), true);
    try values.publish(E, self, ty, operand_index);
}
