//! Allocation-free native frame journal over guarded physical RC slots.
const typed = @import("typed.zig");
const runtime = @import("runtime_mode.zig");
const state_model = @import("qbe_rc_state.zig");
const dictionary = @import("rc_dictionary_tail.zig");
const glue = @import("qbe_rc_glue.zig");
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
            var total = frame_bytes + count(state) * (entry_bytes + 8);
            for (state.operands) |operand| total += alignedBytes(operand.bytes) + @as(u64, if (operand.may_own) 8 else 0);
            for (self.function.scope.locals, 0..) |_, index| if (receiverStorage(E, self, index)) {
                total += 32;
            };
            return total + alignedBytes(state.pending) + 128 + state.plan.append_loops.len * 8;
        }
        /// Reserve table, guards and stable operand/pending-value buffers.
        pub fn allocate(self: *E) Error!void {
            const state = get(E, self) orelse return;
            try self.allocateSlot("rcframe", frame_bytes);
            try self.allocateSlot("rcentries", count(state) * entry_bytes);
            try self.allocateSlot("rcguards", count(state) * 8);
            for (state.operands, 0..) |operand, index| try self.allocateIndex("rcs", index, operand.bytes);
            // RC-OPERAND-STAGE-1: the address-taken copy of an owned one-word operand.
            for (state.operands, 0..) |operand, index| if (operand.may_own) try self.allocateIndex("rcstage", index, 8);
            try self.allocateSlot("rcwork", state.pending);
            try self.allocateSlot("rcinternal", 8);
            try self.allocateSlot("rcsort", 48);
            try self.allocateSlot("rccall", 32);
            try self.allocateSlot("rcplace", 32);
            try self.allocateSlot("rcarg", 8);
            for (state.plan.append_loops, 0..) |_, index| try self.allocateIndex("rcappend", index, 8);
            for (self.function.scope.locals, 0..) |_, index| if (receiverStorage(E, self, index)) {
                try self.allocateIndex("rcborrow", index, 32);
                try self.print(" call $memset(l %rcborrow{d}, w 0, l 32)\n", .{index});
            };
        }
        /// Link only after every guard is initialized and every parameter is stored.
        pub fn enter(self: *E) Error!void {
            const state = get(E, self) orelse return;
            if (fixedRegion(E, self)) try self.print(" %rcregion =l call $myl_qbe_region_mark(l %ctx)\n", .{});
            const size = count(state);
            // Every retained entry gets all semantic fields below before linking.
            // Guard words alone need clearing; the C slot's padding is unread.
            try self.print(" call $memset(l %rcguards, w 0, l {d})\n", .{size * 8});
            for (state.plan.locals.storage, 0..) |slot, index| {
                if (try state.plan.journal.slot(index) == null) continue;
                const address = self.temp();
                if (self.byReference(index)) {
                    try self.print(" %v{d} =l loadl %l{d}\n", .{ address, index });
                } else try self.print(" %v{d} =l copy %l{d}\n", .{ address, index });
                try entry(E, self, index, slot.ty, address);
                if (slot.initial == .owned) try initialized(E, self, index, true);
            }
            for (state.operands, 0..) |_, index| {
                if (try state.plan.journal.slot(localCount(E, self) + index) == null) continue;
                const address = self.temp();
                try self.print(" %v{d} =l copy %rcs{d}\n", .{ address, index });
                try entry(E, self, localCount(E, self) + index, .unit, address);
            }
            const work = self.temp();
            try self.print(" %v{d} =l copy %rcwork\n", .{work});
            try entry(E, self, pending(E, self), .unit, work);
            const internal = self.temp();
            try self.print(" %v{d} =l copy %rcinternal\n", .{internal});
            try entry(E, self, pending(E, self) + 1, .unit, internal);
            if (linked(E, self)) try self.print(" call $myl_qbe_rc_frame_enter(l %ctx, l %rcframe, l %rcentries, l {d})\n", .{size});
        }
        /// Release live obligations through the same order used by runtime traps.
        pub fn cleanup(self: *E) Error!void {
            if (!linked(E, self)) return;
            try self.print(" call $myl_qbe_rc_frame_cleanup(l %ctx, l %rcframe)\n", .{});
        }
        /// Unlink after the result has been published and all owners released.
        pub fn leave(self: *E) Error!void {
            if (!linked(E, self)) return;
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
/// A certified managed local never has O, H, loan or unique cleanup metadata.
pub fn emptyLocal(comptime E: type, self: *E, index: usize) bool {
    const state = get(E, self) orelse return false;
    return state.plan.journal.emptyLocal(index);
}
/// Only the bounded no-obligation certificate may omit runtime frame linkage.
pub fn linked(comptime E: type, self: *E) bool {
    const state = get(E, self) orelse return false;
    return !state.plan.journal.unlinked;
}
/// Refuse an unexpected ownership or scope publication in a certified body.
pub fn requireLinked(comptime E: type, self: *E) Error!void {
    if (!linked(E, self)) return error.InternalError;
}
/// The journal index of the pending result used for transactional replacement.
pub fn pending(comptime E: type, self: *E) usize {
    return localCount(E, self) + get(E, self).?.operands.len;
}
/// Set a guard only when its represented ownership token has committed.
pub fn initialized(comptime E: type, self: *E, index: usize, live: bool) Error!void {
    if (live) try requireLinked(E, self);
    if (live and dictionary.forbidsPublication(
        get(E, self).?.plan.dictionary_tails,
        self.pc,
        index,
        localCount(E, self),
    )) return error.InternalError;
    if (!live and try get(E, self).?.plan.journal.slot(index) == null) return;
    const pointer = try guard(E, self, index);
    try self.print(" storew {d}, %v{d}\n", .{ @intFromBool(live), pointer });
}
/// Address the stable guard word for one journal entry.
pub fn guard(comptime E: type, self: *E, index: usize) Error!usize {
    if (dictionary.closedOperand(
        get(E, self).?.plan.dictionary_tails,
        self.pc,
        index,
        localCount(E, self),
    )) return error.InternalError;
    const physical = try get(E, self).?.plan.journal.require(index);
    const result = self.temp();
    try self.print(" %v{d} =l add %rcguards, {d}\n", .{ result, physical * 8 });
    return result;
}
/// Read this transfer's arena depth, reusing the entry value in stable frames.
/// Callees restore their own scopes before returning, including on failure.
pub fn region(comptime E: type, self: *E) Error!usize {
    const result = self.temp();
    if (fixedRegion(E, self)) {
        try self.print(" %v{d} =l copy %rcregion\n", .{result});
    } else try self.print(" %v{d} =l call $myl_qbe_region_mark(l %ctx)\n", .{result});
    return result;
}
fn fixedRegion(comptime E: type, self: *E) bool {
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .begin_arena, .end_arena => return false,
        else => {},
    };
    return true;
}
/// Publish metadata while the entry has no initialized token.
pub fn entry(comptime E: type, self: *E, index: usize, ty: typed.Type, address: usize) Error!void {
    const pointer = try typedEntry(E, self, index, ty);
    const field = self.temp();
    try self.print(" %v{d} =l add %v{d}, 8\n storel %v{d}, %v{d}\n", .{ field, pointer, address, field });
    const at_guard = try self.address(pointer, 16);
    const guard_pointer = try guard(E, self, index);
    try self.print(" storel %v{d}, %v{d}\n", .{ guard_pointer, at_guard });
}
/// Change an operand or pending value's type while preserving its fixed addresses.
/// Entry initialized these address/guard pointers before linking the frame; all
/// later publications in these slots use the same physical operand/work storage.
pub fn stableEntry(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!void {
    if (index < localCount(E, self) or index > pending(E, self)) return error.InternalError;
    _ = try typedEntry(E, self, index, ty);
}
fn typedEntry(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!usize {
    const state = get(E, self) orelse return error.InternalError;
    const shape = state.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    const pointer = try entryField(E, self, index, 0);
    const flag = @as(u32, @intFromBool(shape.unique_drop)) | (@as(u32, @intFromBool(shape.counted)) << 1);
    try self.print(" storel extern ${s}, %v{d}\n", .{ try self.descriptor(ty), pointer });
    try self.print(" storew {d}, %v{d}\n", .{ flag, try self.address(pointer, 24) });
    return pointer;
}

/// Clear/drop one dynamic typed entry using the runtime's unique/count ordering.
pub fn drop(comptime E: type, self: *E, index: usize) Error!void {
    if (dictionary.emptyDrop(
        get(E, self).?.plan.dictionary_tails,
        self.pc,
        index,
        localCount(E, self),
    )) {
        try self.print(" # RC-DICTIONARY-EMPTY-DROPS-1 slot {d}\n", .{index});
        return;
    }
    if (try get(E, self).?.plan.journal.slot(index) == null) return;
    const live = self.temp();
    const label = self.temp();
    const flag = try guard(E, self, index);
    try self.print(" %v{d} =w loaduw %v{d}\n jnz %v{d}, @rcslotdrop{d}, @rcslotdone{d}\n@rcslotdrop{d}\n", .{ live, flag, live, label, label, label });
    const pointer = try entryField(E, self, index, 0);
    // RC-GLUE-1: a statically typed entry drops through its type's glue,
    // which confirms the entry's type and role before its fast path.
    if (staticType(E, self, index)) |ty| if (try glue.routed(E, self, ty)) {
        try glue.slotDrop(E, self, ty, pointer);
        try self.print("@rcslotdone{d}\n", .{label});
        return;
    };
    try self.print(" call $myl_qbe_rc_slot_drop(l %ctx, l %v{d})\n", .{pointer});
    try self.print("@rcslotdone{d}\n", .{label});
}

/// The type an entry is expected to carry at this pc: a local's declared type
/// or the current operand stack's type. The drop checks it at run time.
fn staticType(comptime E: type, self: *E, index: usize) ?typed.Type {
    if (index < localCount(E, self)) return self.function.scope.locals[index].ty;
    if (index >= pending(E, self)) return null;
    const stack = self.states[self.pc] orelse return null;
    const operand = index - localCount(E, self);
    return if (operand < stack.len) stack[operand] else null;
}

fn localCount(comptime E: type, self: *E) usize {
    return self.function.scope.locals.len;
}
fn count(state: *state_model.State) u64 {
    return state.plan.journal.count();
}
fn alignedBytes(bytes_value: u64) u64 {
    return (bytes_value + 7) & ~@as(u64, 7);
}

fn receiverStorage(comptime E: type, self: *E, index: usize) bool {
    // Certified reads never enter receiver setup; certified mutation captures
    // skip both scope begin and end. Neither can link a cleanup obligation.
    if (emptyLocal(E, self, index)) return false;
    const plan = self.cow.?.plan;
    return plan.place(index) != null or (index < plan.aliases.len and plan.aliases[index] != @import("cow_plan.zig").none);
}

/// Address a field in a retained logical entry without exposing dense indices.
pub fn entryField(comptime E: type, self: *E, index: usize, offset: u64) Error!usize {
    const physical = try get(E, self).?.plan.journal.require(index);
    const pointer = self.temp();
    try self.print(" %v{d} =l add %rcentries, {d}\n", .{ pointer, physical * entry_bytes + offset });
    return pointer;
}

/// Preserve the local-prefix boundary when arena cleanup scans a compact table.
pub fn watermark(comptime E: type, self: *E, logical: usize) Error!usize {
    if (logical > localCount(E, self)) return error.InternalError;
    return get(E, self).?.plan.journal.watermark(logical);
}
