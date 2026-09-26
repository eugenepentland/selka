//! Allocation-free native frame journal over guarded physical RC slots.
const typed = @import("typed.zig");
const runtime = @import("runtime_mode.zig");
const state_model = @import("qbe_rc_state.zig");
/// Errors shared with the native emitter.
pub const Error = state_model.Error;
/// Frozen C journal entry/frame sizes, verified against the runtime header.
pub const entry_bytes: u64 = 32;
/// The frame stores a previous link, table, count and scope checkpoint.
pub const frame_bytes: u64 = 32;

/// Bind frame storage emission without introducing a main-emitter import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Additional storage included in both native-stack and heap-frame bounds.
        pub fn bytes(self: *E) Error!u64 {
            const state = get(E, self) orelse return 0;
            var total = frame_bytes + count(E, self, state) * (entry_bytes + 8);
            for (state.operands) |operand| total += alignedBytes(operand.bytes);
            return total + alignedBytes(state.pending) + 56;
        }
        /// Reserve table, guards and stable operand/pending-value buffers.
        pub fn allocate(self: *E) Error!void {
            const state = get(E, self) orelse return;
            try self.allocateSlot("rcframe", frame_bytes);
            try self.allocateSlot("rcentries", count(E, self, state) * entry_bytes);
            try self.allocateSlot("rcguards", count(E, self, state) * 8);
            for (state.operands, 0..) |operand, index| try self.allocateIndex("rcs", index, operand.bytes);
            try self.allocateSlot("rcwork", state.pending);
            try self.allocateSlot("rcinternal", 8);
            try self.allocateSlot("rcsort", 48);
        }
        /// Link only after every guard is initialized and every parameter is stored.
        pub fn enter(self: *E) Error!void {
            const state = get(E, self) orelse return;
            const size = count(E, self, state);
            try self.print(" call $memset(l %rcguards, w 0, l {d})\n call $memset(l %rcentries, w 0, l {d})\n", .{ size * 8, size * entry_bytes });
            for (state.locals.storage, 0..) |slot, index| {
                const address = self.temp();
                if (self.byReference(index)) {
                    try self.print(" %v{d} =l loadl %l{d}\n", .{ address, index });
                } else try self.print(" %v{d} =l copy %l{d}\n", .{ address, index });
                try entry(E, self, index, slot.ty, address);
                if (slot.initial == .owned) try initialized(E, self, index, true);
            }
            for (state.operands, 0..) |_, index| {
                const address = self.temp();
                try self.print(" %v{d} =l copy %rcs{d}\n", .{ address, index });
                try entry(E, self, localCount(E, self) + index, .unit, address);
            }
            const work = self.temp();
            try self.print(" %v{d} =l copy %rcwork\n", .{work});
            try entry(E, self, size - 2, .unit, work);
            const internal = self.temp();
            try self.print(" %v{d} =l copy %rcinternal\n", .{internal});
            try entry(E, self, size - 1, .unit, internal);
            try self.print(" call $myl_qbe_rc_frame_enter(l %ctx, l %rcframe, l %rcentries, l {d})\n", .{size});
        }
        /// Release live obligations through the same order used by runtime traps.
        pub fn cleanup(self: *E) Error!void {
            if (get(E, self) == null) return;
            try self.print(" call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)\n", .{});
        }
        /// Unlink after the result has been published and all owners released.
        pub fn leave(self: *E) Error!void {
            if (get(E, self) == null) return;
            try self.print(" call $myl_qbe_rc_frame_leave(l %ctx, l %rcframe)\n", .{});
        }
        /// Drop an initialized local; borrowed parameters keep a clear guard.
        pub fn dropLocal(self: *E, index: usize) Error!void {
            if (get(E, self) == null) return;
            try drop(E, self, index);
        }
    };
}

/// Read the enabled function state without confusing semantic COW with RC.
pub fn get(comptime E: type, self: *E) ?*state_model.State {
    if (!runtime.enabled()) return null;
    const state = if (self.cow) |cow| cow.rc orelse return null else return null;
    return if (state.active) state else null;
}
/// The journal index of the pending result used for transactional replacement.
pub fn pending(comptime E: type, self: *E) usize {
    return localCount(E, self) + get(E, self).?.operands.len;
}
/// Set a guard only when its represented ownership token has committed.
pub fn initialized(comptime E: type, self: *E, index: usize, live: bool) Error!void {
    const pointer = try guard(E, self, index);
    try self.print(" storew {d}, %v{d}\n", .{ @intFromBool(live), pointer });
}
/// Address the stable guard word for one journal entry.
pub fn guard(comptime E: type, self: *E, index: usize) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l add %rcguards, {d}\n", .{ result, index * 8 });
    return result;
}
/// Publish metadata while the entry has no initialized token.
pub fn entry(comptime E: type, self: *E, index: usize, ty: typed.Type, address: usize) Error!void {
    const state = get(E, self) orelse return error.InternalError;
    const shape = state.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    const pointer = self.temp();
    const field = self.temp();
    const flag = @as(u32, @intFromBool(shape.unique_drop)) | (@as(u32, @intFromBool(shape.counted)) << 1);
    try self.print(" %v{d} =l add %rcentries, {d}\n storel extern ${s}, %v{d}\n", .{ pointer, index * entry_bytes, try self.descriptor(ty), pointer });
    try self.print(" %v{d} =l add %v{d}, 8\n storel %v{d}, %v{d}\n", .{ field, pointer, address, field });
    const at_guard = try self.address(pointer, 16);
    const guard_pointer = try guard(E, self, index);
    try self.print(" storel %v{d}, %v{d}\n", .{ guard_pointer, at_guard });
    try self.print(" storew {d}, %v{d}\n", .{ flag, try self.address(pointer, 24) });
}
/// Clear/drop one dynamic typed entry using the runtime's unique/count ordering.
pub fn drop(comptime E: type, self: *E, index: usize) Error!void {
    const pointer = self.temp();
    try self.print(" %v{d} =l add %rcentries, {d}\n call $myl_qbe_rc_slot_drop(l %ctx, l %v{d})\n", .{ pointer, index * entry_bytes, pointer });
}
fn localCount(comptime E: type, self: *E) usize {
    return self.function.scope.locals.len;
}
fn count(comptime E: type, self: *E, state: *state_model.State) u64 {
    return localCount(E, self) + state.operands.len + 2;
}
fn alignedBytes(bytes_value: u64) u64 {
    return (bytes_value + 7) & ~@as(u64, 7);
}
