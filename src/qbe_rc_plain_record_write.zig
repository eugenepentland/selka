//! Publish one proved scalar field without moving its managed siblings.
const frame = @import("qbe_rc_frame.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Errors shared by native value reads and stores.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Captures remain uninitialized; only the original final store writes memory.
pub fn local(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!bool {
    if (op != .load_local and op != .store_local) return false;
    const state = frame.get(E, self) orelse return false;
    for (state.plan.plain_writes) |proof| {
        if (self.pc == proof.start + 1 or self.pc == proof.start + 3) return true;
        if (self.pc == proof.start + 4) {
            try self.store(stack.len, try address(E, self, proof));
            return true;
        }
        if (self.pc != proof.start + 7) continue;
        const member = try self.field(self.function.scope.locals[proof.root].ty, proof.field);
        const value = try self.load("l", proof.value);
        const root = try address(E, self, proof);
        try self.print(" # RC-PLAIN-RECORD-WRITE-1 root {d} field {d} capture {d}\n", .{ proof.root, proof.field, proof.capture });
        try self.writeValue(try self.address(root, member.offset), value, member.ty);
        return true;
    }
    return false;
}

/// Delay the scalar write until STORE_LOCAL, preserving an intervening step trap.
pub fn update(comptime E: type, self: *E, height: usize) Error!bool {
    const state = frame.get(E, self) orelse return false;
    for (state.plan.plain_writes) |proof| if (self.pc == proof.start + 6) {
        try self.store(height - 2, try address(E, self, proof));
        return true;
    };
    return false;
}

fn address(comptime E: type, self: *E, proof: @import("rc_plain_record_write.zig").Certificate) Error!usize {
    if (proof.home == .caller) return self.load("l", proof.root);
    const result = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ result, proof.root });
    return result;
}
