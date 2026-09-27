//! Stack-local RC drop flags and statically elaborated frame drops.
//!
//! Traps are fatal (the runtime tears the whole heap down), so a frame keeps no
//! runtime journal and links nothing into the context. Each physical slot that
//! can hold an obligation has two frame words: its initialization guard and its
//! role (ordinary owner flags, a private loan, a held pointer or a partial
//! construction). Both are private to the frame, so the backend can forward and
//! fold them. Every drop names the slot's static type and address; only the
//! guard and, for copyable counted values, the role are read at run time.
const typed = @import("typed.zig");
const runtime = @import("runtime_mode.zig");
const state_model = @import("qbe_rc_state.zig");
const dictionary = @import("rc_dictionary_tail.zig");
/// Errors shared with the native emitter.
pub const Error = state_model.Error;
/// Frame bytes one physical slot's guard and role words reserve.
const flag_bytes: u64 = 16;
/// Byte offset of `myl_rc_scope.active`, checked against the runtime header.
pub const scope_active_offset: u64 = 24;
/// Role bits that are not an ordinary owner: construction, held pointer, loan.
const special_roles: u32 = 4 | 8 | 16;

/// Bind frame storage emission without introducing a main-emitter import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Additional storage included in both native-stack and heap-frame bounds.
        pub fn bytes(self: *E) Error!u64 {
            const state = get(E, self) orelse return 0;
            var total = count(state) * flag_bytes;
            for (state.operands) |operand| total += alignedBytes(operand.bytes);
            for (self.function.scope.locals, 0..) |_, index| if (receiverStorage(E, self, index)) {
                total += 32;
            };
            total += 8 * @as(u64, scopeCount(E, self));
            return total + alignedBytes(state.pending) + 120 + state.plan.append_loops.len * 8;
        }
        /// Reserve guards, roles and stable operand/pending-value buffers.
        pub fn allocate(self: *E) Error!void {
            const state = get(E, self) orelse return;
            for (0..count(state)) |physical| {
                try self.allocateIndex("rcg", physical, 4);
                try self.allocateIndex("rcr", physical, 4);
            }
            for (state.operands, 0..) |operand, index| try self.allocateIndex("rcs", index, operand.bytes);
            try self.allocateSlot("rcwork", state.pending);
            try self.allocateSlot("rcinternal", 8);
            try self.allocateSlot("rcsort", 48);
            try self.allocateSlot("rccall", 32);
            try self.allocateSlot("rcplace", 32);
            for (state.plan.append_loops, 0..) |_, index| try self.allocateIndex("rcappend", index, 8);
            for (self.function.scope.locals, 0..) |_, index| if (receiverStorage(E, self, index)) {
                try self.allocateIndex("rcborrow", index, 32);
                // Only the active word is read before a scope begins (RC-EXIT-SCOPES-1).
                const active = self.temp();
                try self.print(" %v{d} =l add %rcborrow{d}, {d}\n storel 0, %v{d}\n", .{ active, index, scope_active_offset, active });
            };
            const scopes = scopeCount(E, self);
            if (scopes != 0) try self.allocateSlot("rcscopes", 8 * @as(u64, scopes));
        }
        /// Clear every guard and give each local its ordinary owner role.
        pub fn enter(self: *E) Error!void {
            const state = get(E, self) orelse return;
            // A linked frame carries obligations; tests and readers find it here.
            if (linked(E, self)) try self.print(" # rc-frame {d}\n", .{count(state)});
            if (fixedRegion(E, self)) try self.print(" %rcregion =l call $myl_qbe_region_mark(l %ctx)\n", .{});
            for (0..count(state)) |physical| try self.print(" storew 0, %rcg{d}\n storew 0, %rcr{d}\n", .{ physical, physical });
            for (state.plan.locals.storage, 0..) |slot, index| {
                if (try state.plan.journal.slot(index) == null) continue;
                try typedRole(E, self, index, slot.ty);
                if (slot.initial == .owned) try initialized(E, self, index, true);
            }
        }
        /// Close this frame's open receiver scopes, then drop every live operand
        /// below and including the result and every live local, newest first.
        /// The result's own token has already been handed to the caller.
        pub fn exit(self: *E) Error!void {
            if (!linked(E, self)) return;
            try self.print(" # rc-exit\n", .{});
            try closeScopes(E, self);
            const stack = self.states[self.pc] orelse return error.InternalError;
            var operand = stack.len;
            while (operand != 0) {
                operand -= 1;
                try dropTyped(E, self, localCount(E, self) + operand, stack[operand]);
            }
            var local = localCount(E, self);
            while (local != 0) {
                local -= 1;
                try drop(E, self, local);
            }
        }
        /// Drop an initialized local; borrowed parameters keep a clear guard.
        pub fn dropLocal(self: *E, index: usize) Error!void {
            if (get(E, self) == null) return;
            try drop(E, self, index);
        }
        /// An arena statement ends with no live operand stack. Restore scopes
        /// born in its region, then drop the locals declared inside it while
        /// its chunks still live.
        pub fn arenaEnd(self: *E, scanned: usize) Error!void {
            if (get(E, self) == null) return;
            try self.print(" call $myl_qbe_rc_arena_scopes(l %ctx)\n", .{});
            var local = localCount(E, self);
            while (local > scanned) {
                local -= 1;
                try drop(E, self, local);
            }
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
/// Only a frame without the bounded no-obligation certificate drops on exit.
pub fn linked(comptime E: type, self: *E) bool {
    const state = get(E, self) orelse return false;
    return !state.plan.journal.unlinked;
}
/// Refuse an unexpected ownership or scope publication in a certified body.
pub fn requireLinked(comptime E: type, self: *E) Error!void {
    if (!linked(E, self)) return error.InternalError;
}
/// The slot index of the pending result used for transactional replacement.
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
/// Address the stable guard word for one slot.
pub fn guard(comptime E: type, self: *E, index: usize) Error!usize {
    if (dictionary.closedOperand(
        get(E, self).?.plan.dictionary_tails,
        self.pc,
        index,
        localCount(E, self),
    )) return error.InternalError;
    const physical = try get(E, self).?.plan.journal.require(index);
    const result = self.temp();
    try self.print(" %v{d} =l copy %rcg{d}\n", .{ result, physical });
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
/// Give a slot the ordinary owner role of its newly published type. The
/// address is static (the slot's own storage), so only the role is recorded.
pub fn entry(comptime E: type, self: *E, index: usize, ty: typed.Type, address: usize) Error!void {
    _ = address;
    try typedRole(E, self, index, ty);
}
/// Change an operand or pending value's type while preserving its fixed addresses.
pub fn stableEntry(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!void {
    if (index < localCount(E, self) or index > pending(E, self)) return error.InternalError;
    try typedRole(E, self, index, ty);
}
fn typedRole(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!void {
    const shape = try shapeOf(E, self, ty);
    const flag = @as(u32, @intFromBool(shape.unique_drop)) | (@as(u32, @intFromBool(shape.counted)) << 1);
    try self.print(" storew {d}, %v{d}\n", .{ flag, try entryField(E, self, index, 24) });
}
fn shapeOf(comptime E: type, self: *E, ty: typed.Type) Error!@import("rc_shape.zig").Shape {
    const state = get(E, self) orelse return error.InternalError;
    return state.catalog.get(ty) catch |err| if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

/// Clear/drop one guarded slot using the runtime's unique/count ordering.
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
    try dropTyped(E, self, index, try slotType(E, self, index));
}
/// The static type of a slot's value at the current instruction: a local's
/// declared type, or the operand stack's type at this position.
fn slotType(comptime E: type, self: *E, index: usize) Error!typed.Type {
    const locals = localCount(E, self);
    if (index < locals) return self.function.scope.locals[index].ty;
    const stack = self.states[self.pc] orelse return error.InternalError;
    if (index - locals >= stack.len) return error.InternalError;
    return stack[index - locals];
}
/// RC-STATIC-DROPS-1: a guarded drop with the slot's static type and address.
/// Only a copyable counted value can hold a loan or held-pointer role, so only
/// its drop reads the role word; every other drop is the owner's release.
fn dropTyped(comptime E: type, self: *E, index: usize, ty: typed.Type) Error!void {
    if (try get(E, self).?.plan.journal.slot(index) == null) return;
    const shape = try shapeOf(E, self, ty);
    const flag = try guard(E, self, index);
    const live = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n jnz %v{d}, @rcslotdrop{d}, @rcslotdone{d}\n@rcslotdrop{d}\n", .{ live, flag, live, label, label, label });
    try self.print(" storew 0, %v{d}\n", .{flag});
    if (shape.counted or shape.unique_drop) {
        const address = try slotAddress(E, self, index);
        if (shape.counted and !shape.unique_drop) {
            const role = self.temp();
            const special = self.temp();
            try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w and %v{d}, {d}\n", .{ role, try entryField(E, self, index, 24), special, role, special_roles });
            try self.print(" jnz %v{d}, @rcslotrole{d}, @rcslotowner{d}\n@rcslotrole{d}\n", .{ special, label, label, label });
            try roleRelease(E, self, ty, address, role);
            try self.print(" jmp @rcslotdone{d}\n@rcslotowner{d}\n", .{ label, label });
        }
        try ownerRelease(E, self, ty, shape, address);
    }
    try self.print("@rcslotdone{d}\n", .{label});
}
/// Release an ordinary owner of a static type: unique resources close through
/// their scheduler before any counted child is released. This is the one
/// emission point for an owner's static drop (per-type glue composes here).
fn ownerRelease(comptime E: type, self: *E, ty: typed.Type, shape: @import("rc_shape.zig").Shape, address: usize) Error!void {
    const descriptor = try self.descriptor(ty);
    if (shape.unique_drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ descriptor, address });
    if (shape.counted) try self.print(" call $myl_rc_native_drop(l %heap, l extern ${s}, l %v{d})\n", .{ descriptor, address });
}
/// Release a loan, held pointer or partial construction by its role word.
/// This is the one emission point for a non-owner role's static drop.
fn roleRelease(comptime E: type, self: *E, ty: typed.Type, address: usize, role: usize) Error!void {
    try self.print(" call $myl_qbe_rc_drop_role(l %ctx, l extern ${s}, l %v{d}, w %v{d})\n", .{ try self.descriptor(ty), address, role });
}
/// The fixed storage a slot's value lives in.
fn slotAddress(comptime E: type, self: *E, index: usize) Error!usize {
    const locals = localCount(E, self);
    const result = self.temp();
    if (index < locals) {
        const operation: []const u8 = if (self.byReference(index)) "loadl" else "copy";
        try self.print(" %v{d} =l {s} %l{d}\n", .{ result, operation, index });
    } else if (index < pending(E, self)) {
        try self.print(" %v{d} =l copy %rcs{d}\n", .{ result, index - locals });
    } else return error.InternalError;
    return result;
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

/// Receiver scope records a return can leave open: `?` inside a receiver
/// statement returns between the scope's begin and its write-back.
fn scopeCount(comptime E: type, self: *E) usize {
    var total: usize = 0;
    for (scope_kinds) |kind| {
        var iterator = scopeRecords(E, self, kind);
        while (iterator.next()) |_| total += 1;
    }
    return total;
}
const scope_kinds = [_][]const u8{ "rcborrow", "cowscope" };
/// RC-EXIT-SCOPES-1: test each scope record's active word; only when one is
/// open does the frame pass its records to the runtime, which closes exactly
/// the open ones at the head of the chain with the ordinary scope unwind.
fn closeScopes(comptime E: type, self: *E) Error!void {
    var any: ?usize = null;
    for (scope_kinds) |kind| {
        var iterator = scopeRecords(E, self, kind);
        while (iterator.next()) |number| {
            const at = self.temp();
            const active = self.temp();
            try self.print(" %v{d} =l add %{s}{d}, {d}\n %v{d} =w loaduw %v{d}\n", .{ at, kind, number, scope_active_offset, active, at });
            if (any) |previous| {
                const joined = self.temp();
                try self.print(" %v{d} =w or %v{d}, %v{d}\n", .{ joined, previous, active });
                any = joined;
            } else any = active;
        }
    }
    const open = any orelse return;
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcscopesopen{d}, @rcscopesclosed{d}\n@rcscopesopen{d}\n", .{ open, label, label, label });
    var listed: usize = 0;
    for (scope_kinds) |kind| {
        var iterator = scopeRecords(E, self, kind);
        while (iterator.next()) |number| {
            const at = self.temp();
            try self.print(" %v{d} =l add %rcscopes, {d}\n storel %{s}{d}, %v{d}\n", .{ at, listed * 8, kind, number, at });
            listed += 1;
        }
    }
    try self.print(" call $myl_qbe_rc_scopes_close(l %ctx, l %rcscopes, l {d})\n@rcscopesclosed{d}\n", .{ listed, label });
}
fn ScopeRecords(comptime E: type) type {
    return struct {
        self: *E,
        kind: []const u8,
        cursor: usize = 0,
        fn next(iterator: *@This()) ?usize {
            const self = iterator.self;
            if (iterator.kind.ptr == scope_kinds[0].ptr) {
                while (iterator.cursor < self.function.scope.locals.len) {
                    const index = iterator.cursor;
                    iterator.cursor += 1;
                    if (receiverStorage(E, self, index)) return index;
                }
                return null;
            }
            const records = (get(E, self) orelse return null).plan.scope_records;
            if (iterator.cursor >= records.len) return null;
            iterator.cursor += 1;
            return records[iterator.cursor - 1];
        }
    };
}
fn scopeRecords(comptime E: type, self: *E, kind: []const u8) ScopeRecords(E) {
    return .{ .self = self, .kind = kind };
}

/// Address the role word of a retained slot (offset 24 of the former journal
/// entry, kept as the one field callers name).
pub fn entryField(comptime E: type, self: *E, index: usize, offset: u64) Error!usize {
    if (offset != 24) return error.InternalError;
    const physical = try get(E, self).?.plan.journal.require(index);
    const pointer = self.temp();
    try self.print(" %v{d} =l copy %rcr{d}\n", .{ pointer, physical });
    return pointer;
}
