//! Publish the canonical owned result before frame owners, scopes or arenas die.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Return through the ordinary guest ABI after transferring the result token.
pub fn emit(comptime E: type, self: *E, value: usize) Error!bool {
    const state = frame.get(E, self) orelse return false;
    const ty = self.function.signature.return_type;
    const owned = try @import("qbe_rc_state.zig").owns(state, ty);
    var source = value;
    if (owned) {
        const stack = self.states[self.pc] orelse return error.InternalError;
        try values.prepareOperand(E, self, ty, stack.len - 1);
        source = try self.readValue(try values.workAddress(E, self), ty);
    }
    var output = source;
    if (try self.largeResult(self.function)) {
        try self.print(" blit %v{d}, %out, {d}\n", .{ source, (try self.layout(ty)).size });
        output = self.temp();
        try self.print(" %v{d} =l copy 0\n", .{output});
    } else if (self.heap_frame and !self.isScalar(ty)) {
        try self.print(" blit %v{d}, %return_storage, {d}\n", .{ source, try self.returnStorageBytes() });
        output = self.temp();
        try self.print(" %v{d} =l copy %return_storage\n", .{output});
    }
    if (owned) try frame.initialized(E, self, frame.pending(E, self), false);
    try frame.Lower(E).cleanup(self);
    try frame.Lower(E).leave(self);
    try @import("qbe_arena.zig").Lower(E).restore(self);
    if (self.heap_frame) try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n", .{});
    try self.leaveFrame();
    try self.print(" ret %v{d}\n", .{output});
    return true;
}
