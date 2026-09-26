//! Cold cleanup for unique ABI arguments before a callee's RC journal exists.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
/// Failures shared with the native emitter.
pub const Error = frame.Error;

/// Whether admission owns arguments whose cleanup cannot wait for a frame.
pub fn needed(comptime E: type, self: *E) bool {
    const state = frame.get(E, self) orelse return false;
    for (state.contract.parameters) |parameter| if (parameter == .consume_on_entry) return true;
    return false;
}

/// Drop consumed incoming values on a cold refusal path, without allocating a
/// per-parameter journal or changing the packed/ordinary function ABI.
pub fn drop(comptime E: type, self: *E) Error!void {
    if (!needed(E, self)) return;
    const state = frame.get(E, self).?;
    const heap = self.temp();
    const word = self.temp();
    try self.print(" %v{d} =l call $myl_qbe_heap(l %ctx)\n %v{d} =l alloc8 8\n", .{ heap, word });
    var index = self.function.signature.parameter_count;
    while (index != 0) {
        index -= 1;
        if (state.contract.parameters[index] != .consume_on_entry) continue;
        const ty = self.function.scope.locals[index].ty;
        const address = try incoming(E, self, index, word);
        const descriptor = try self.descriptor(ty);
        try self.print(" call $myl_native_owned_drop(l %v{d}, l extern ${s}, l %v{d})\n", .{ heap, descriptor, address });
        if ((state.catalog.get(ty) catch return error.InternalError).counted) {
            try self.print(" call $myl_rc_native_drop(l %v{d}, l extern ${s}, l %v{d})\n", .{ heap, descriptor, address });
        }
    }
}

fn incoming(comptime E: type, self: *E, index: usize, word: usize) Error!usize {
    const ty = self.function.scope.locals[index].ty;
    const pointer = self.temp();
    if (try self.packedParameters(self.function)) {
        const slot = self.temp();
        try self.print(" %v{d} =l add %packed, {d}\n", .{ slot, index * 8 });
        if (self.isScalar(ty)) return slot;
        try self.print(" %v{d} =l loadl %v{d}\n", .{ pointer, slot });
    } else if (self.isScalar(ty)) {
        try self.print(" storel %a{d}, %v{d}\n", .{ index, word });
        return word;
    } else try self.print(" %v{d} =l copy %a{d}\n", .{ pointer, index });
    return pointer;
}

/// Indirect calls obey the same consume-on-entry contract as direct calls.
pub fn invoke(comptime E: type, self: *E, parameters: []const typed.Type, base: usize) Error!void {
    const state = frame.get(E, self) orelse return;
    for (parameters, 0..) |ty, index| {
        const shape = state.catalog.get(ty) catch return error.InternalError;
        if (shape.unique_drop) try frame.initialized(E, self, @import("qbe_rc_values.zig").journalIndex(E, self, base + index), false);
    }
}

/// Heap-backed admission defers its trap until consumed arguments are released.
pub fn allocate(comptime E: type, self: *E, bytes: u64) Error!bool {
    if (!needed(E, self)) return false;
    const label = self.temp();
    try self.print(" %frame_memory =l call $myl_qbe_frame_try_allocate(l %ctx, l {d})\n jnz %frame_memory, @rcadmitted{d}, @rcadmitfailed{d}\n@rcadmitfailed{d}\n", .{ bytes, label, label, label });
    try drop(E, self);
    try self.print(" call $myl_qbe_fail_frame_allocation(l %ctx)\n jmp @allocation_failure\n@rcadmitted{d}\n", .{label});
    return true;
}
