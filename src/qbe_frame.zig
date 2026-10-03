//! A lowered function's storage and frame protocol: the local, stack and
//! temporary slots it allocates and zero-fills, the frame record it links on
//! entry and unlinks on exit, the admission checks against `--max-frames` and
//! the native stack floor, returns and the cleanup of owned locals, the
//! argument-vector packing of wide signatures, and the byte counts that size a
//! frame. Each step is a free function over the concrete emitter type; `Lower`
//! exposes the ones the rest of the emitter calls as `self.name(...)`.
const zero_local = @import("qbe_format.zig").zero_local;
const cow_lower = @import("qbe_cow.zig");
const arena_lower = @import("qbe_arena.zig");
const rc_frame = @import("qbe_rc_frame.zig");
const rc_admission = @import("qbe_rc_admission.zig");
const std = @import("std");
const runtime = @import("runtime_mode.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const qbe_wire = @import("qbe_wire.zig");
const scalar = qbe_wire.scalar;
const il_passes = @import("qbe_il_passes.zig");
const slotDefinition = il_passes.slotDefinition;
/// Failures a frame step reports: the same set as `qbe.GenerateError`.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
pub const drop_local = " call $myl_native_owned_drop(l %heap, l extern ${s}, l %l{d})\n";
/// The `dbgloc` column that marks an entry guard's frame-failure call for the
/// frame map. It is `qbe_frame_map.guard_column`; this file belongs to the
/// compiler module and that one to the native-build module, which cannot share
/// a file, so `src/qbe_frame_map_test.zig` checks the two are the same value.
pub const frame_map_guard_column: u32 = 1;
const impl = @This();
/// Bind frame lowering to the concrete emitter without an import cycle.
pub fn Lower(comptime Emitter: type) type {
    return struct {
        /// Bytes of native stack the function's ABI traffic can use: a bounded scalar spill
        /// reserve plus the exact argument, argument-vector and result copies.
        pub fn abiStackBytes(self: *Emitter) GenerateError!u64 {
            return impl.abiStackBytes(Emitter, self);
        }
        /// Reserve one named physical buffer within the selected frame.
        pub fn allocateSlot(self: *Emitter, name: []const u8, size: u64) GenerateError!void {
            return impl.allocateSlot(Emitter, self, name, size);
        }
        /// Reserve one indexed physical buffer within the selected frame.
        pub fn allocateIndex(self: *Emitter, name: []const u8, index: usize, size: u64) GenerateError!void {
            return impl.allocateIndex(Emitter, self, name, index, size);
        }
        /// Allocate the aggregate temporaries that live outside the entry block, unless
        /// the frame is heap-allocated.
        pub fn allocateDynamicTemporaries(self: *Emitter) GenerateError!void {
            return impl.allocateDynamicTemporaries(Emitter, self);
        }
        /// Allocate a native frame's local and stack slots and its entry-block temporaries;
        /// a heap frame emits its storage after its allocation succeeds.
        pub fn allocateNativeStorage(self: *Emitter, capacity: usize) GenerateError!void {
            return impl.allocateNativeStorage(Emitter, self, capacity);
        }
        /// Declare every slot this function needs. QBE's slot promotion only looks
        /// at the entry block, so for a native-stack frame these declarations are
        /// emitted before the frame protocol's labels; a heap-backed frame derives
        /// its slots from `%frame_memory`, so they follow that allocation instead.
        pub fn allocateStorage(self: *Emitter, capacity: usize) GenerateError!void {
            return impl.allocateStorage(Emitter, self, capacity);
        }
        /// Allocate the `agg`/`aux` buffer pair of every instruction that needs an aggregate
        /// temporary in the given placement.
        pub fn allocateTemporaries(self: *Emitter, placement: TemporaryPlacement) GenerateError!void {
            return impl.allocateTemporaries(Emitter, self, placement);
        }
        /// Release an owned value held in a stack slot, reading it through the slot when
        /// it is an aggregate.
        pub fn dropOperand(self: *Emitter, slot: usize, ty: typed.Type) GenerateError!void {
            return impl.dropOperand(Emitter, self, slot, ty);
        }
        /// Link this function's native-stack frame record and enforce the logical
        /// depth ceiling and the execution-stack floor without a runtime call. The
        /// record is `{prev, function, position, native_bytes}`; generated code owns
        /// the first three words and reads `ctx->frames`/`ctx->frame_limit`/
        /// `ctx->frame_floor` at their frozen offsets. The frame-map protocol
        /// links none and emits only the stack-floor test (see `frameMap`).
        pub fn enterFrame(self: *Emitter, name: []const u8) GenerateError!void {
            return impl.enterFrame(Emitter, self, name);
        }
        /// The frame this function needs with `temporaries` bytes of per-pc
        /// aggregate scratch: every local, operand and root slot, the return and
        /// argument storage and the widest outgoing argument list, doubled to
        /// cover the spills QBE adds. On the native stack it must stay within
        /// `native_frame_limit`; a heap frame is allocated at exactly this size.
        pub fn frameBytes(self: *Emitter, capacity: usize, temporaries: u64) GenerateError!u64 {
            return impl.frameBytes(Emitter, self, capacity, temporaries);
        }
        /// Whether this function transfers control to another guest frame. A leaf's
        /// stack use is bounded at compile time, which is what lets its prologue skip
        /// the floor guard: the caller already checked the headroom.
        pub fn frameLeaf(self: *Emitter) bool {
            return impl.frameLeaf(Emitter, self);
        }
        /// QBE-FRAMEMAP-1: the fast protocol (no step and no frame accounting)
        /// links no frame record at all. Every call instead
        /// names its bytecode position with `dbgloc PC+1`, the build turns those
        /// into a return-address table (`qbe_frame_map.zig`), and the runtime walks
        /// the frame-pointer chain only when a trap fires. Nothing else reads a
        /// record there: no step check, no depth counter.
        pub fn frameMap(self: *const Emitter) bool {
            return impl.frameMap(Emitter, self);
        }
        /// Zero-fill the locals a root push or drop could read before their first store, and
        /// store each parameter into its slot.
        pub fn initializeStorage(self: *Emitter) GenerateError!void {
            return impl.initializeStorage(Emitter, self);
        }
        /// Unlink the function's frame record and decrement the frame count, when the
        /// function linked one.
        pub fn leaveFrame(self: *Emitter) GenerateError!void {
            return impl.leaveFrame(Emitter, self);
        }
        /// Store one argument into the outgoing argument vector at position `i`.
        pub fn packArgument(self: *Emitter, i: usize, value: usize) GenerateError!void {
            return impl.packArgument(Emitter, self, i, value);
        }
        /// Whether a callback's parameters travel in an argument vector: more than 128 of
        /// them, or more than 4 KiB in total.
        pub fn packedCallback(self: *Emitter, signature: typed.Callable) GenerateError!bool {
            return impl.packedCallback(Emitter, self, signature);
        }
        /// Wide signatures pass normalized scalar words and aggregate pointers in one vector.
        pub fn packedParameters(self: *Emitter, function: bytecode.Function) GenerateError!bool {
            return impl.packedParameters(Emitter, self, function);
        }
        /// Every per-pc aggregate scratch pair the lowering might declare, each at
        /// the widest operand its instruction can see: the bound `frameBytes` has
        /// to use before the body exists, and the size a heap frame is given.
        pub fn possibleTemporaryBytes(self: *Emitter) GenerateError!u64 {
            return impl.possibleTemporaryBytes(Emitter, self);
        }
        /// Unlink this function's frame record and drop the frame count.
        /// Refuse, once at the entry point, any runtime ceiling this build omitted
        /// accounting for, so a mismatch is reported instead of silently ignored.
        pub fn requireAccounting(self: *Emitter) GenerateError!void {
            return impl.requireAccounting(Emitter, self);
        }
        /// Bytes of return storage an aggregate result needs in the frame; zero for a
        /// scalar or a large result returned through the caller.
        pub fn returnStorageBytes(self: *Emitter) GenerateError!u64 {
            return impl.returnStorageBytes(Emitter, self);
        }
        /// Return a value after releasing heap-backed execution storage safely.
        pub fn returnValue(self: *Emitter, value: usize) GenerateError!void {
            return impl.returnValue(Emitter, self, value);
        }
        /// Clear a traced local slot whose value has just been released, so a root
        /// push can never trace a stale reference. A one-word slot is cleared with a
        /// store, which keeps it promotable; an aggregate keeps the `memset`, since
        /// the address it takes is one the aggregate's own blits need anyway.
        pub fn zeroTracedLocal(self: *Emitter, index: usize, ty: typed.Type) GenerateError!void {
            return impl.zeroTracedLocal(Emitter, self, index, ty);
        }
    };
}
/// Declare every slot this function needs. QBE's slot promotion only looks
/// at the entry block, so for a native-stack frame these declarations are
/// emitted before the frame protocol's labels; a heap-backed frame derives
/// its slots from `%frame_memory`, so they follow that allocation instead.
fn allocateStorage(comptime Emitter: type, self: *Emitter, capacity: usize) GenerateError!void {
    const f = self.function;
    try rc_frame.Lower(Emitter).allocate(self);
    if (self.cow) |state| for (state.plan.places) |maybe| {
        const place = maybe orelse continue;
        if (!cow_lower.Lower(Emitter).scoped(self, place)) continue;
        try allocateIndex(Emitter, self, "cowscope", place.fill, cow_lower.Lower(Emitter).scopeStorage(self, place));
        const value = self.temp();
        try self.print(" %v{d} =l add %cowscope{d}, 24\n storel 0, %v{d}\n", .{ value, place.fill, value });
    };
    try allocateSlot(Emitter, self, "scratch", 16);
    try allocateSlot(Emitter, self, "arguments", try argumentVectorBytes(Emitter, self));
    for (f.scope.locals, 0..) |local, i| {
        try allocateIndex(Emitter, self, "l", i, try localSlotBytes(Emitter, self, i, local.ty));
        const placeholder = try placeholderBytes(Emitter, self, i, local.ty);
        if (placeholder != 0) try allocateIndex(Emitter, self, "lz", i, placeholder);
    }
    for (0..capacity) |i| try allocateIndex(Emitter, self, "s", i, 8);
    for (self.range_keys.locals, 0..) |used, i| if (used) try allocateIndex(Emitter, self, "rl", i, 16);
    for (self.range_keys.heights, 0..) |used, i| if (used) try allocateIndex(Emitter, self, "rs", i, 16);
    if (self.has_roots and !runtime.enabled()) for (0..f.scope.locals.len + capacity) |i| try allocateIndex(Emitter, self, "root", i, 32);
}
fn allocateNativeStorage(comptime Emitter: type, self: *Emitter, capacity: usize) GenerateError!void {
    // A heap frame cannot derive slot addresses until its allocation has
    // succeeded; the existing heap branch emits all of its storage later.
    if (self.heap_frame) return;
    try allocateStorage(Emitter, self, capacity);
    // Pure aggregate temporaries are indexed by bytecode pc and reused for
    // every execution of that instruction. Putting those buffers before the
    // block boundary makes QBE reserve them in the fixed frame. Buffers
    // passed through opaque runtime calls stay in the later class below.
    try allocateTemporaries(Emitter, self, .entry);
}
/// Per-pc aggregate scratch. Pure transformations use entry slots; opaque
/// runtime/provider calls retain QBE's later allocation because moving those
/// address-taken buffers into entry miscompiles retained resource ownership.
/// Each class still gets one pair per pc, reused by loops. Heap frames derive
/// every address from their allocated frame block instead.
const TemporaryPlacement = enum { entry, dynamic, all };
fn allocateTemporaries(comptime Emitter: type, self: *Emitter, placement: TemporaryPlacement) GenerateError!void {
    for (self.states, 0..) |state, pc| if (state != null and usesTemporary(Emitter, self, pc) and (placement == .all or (try temporaryInEntry(Emitter, self, pc)) == (placement == .entry))) {
        const size = try temporarySize(Emitter, self, pc);
        try allocateIndex(Emitter, self, "agg", pc, size);
        try allocateIndex(Emitter, self, "aux", pc, size);
    };
}
fn allocateDynamicTemporaries(comptime Emitter: type, self: *Emitter) GenerateError!void {
    if (self.heap_frame) return;
    // These constant-size buffers are still counted by `frameBytes`. They
    // sit below the probe at run time, within the 64 KiB reserve guarding a
    // native frame whose conservative estimate is capped at 32 KiB.
    try allocateTemporaries(Emitter, self, .dynamic);
}
fn temporaryInEntry(comptime Emitter: type, self: *Emitter, pc: usize) GenerateError!bool {
    // `temporarySize` deliberately reserves at least one word, but a typed
    // zero-sized aggregate must retain the later-allocation semantics. QBE
    // can otherwise fold its entry slot and propagate a null-like address
    // through the generic load/move path.
    if (try hasNonEntryAggregate(Emitter, self, pc)) return false;
    return switch (self.function.scope.instructions[pc].op) {
        .make_record, .make_variant, .get_field, .update_record, .replace_index, .get_index, .try_result, .value_copy => true,
        .load_local, .move_local => |slot| !try nonEntryType(Emitter, self, self.function.scope.locals[@backingInt(slot)].ty),
        else => false,
    };
}
fn hasNonEntryAggregate(comptime Emitter: type, self: *Emitter, pc: usize) GenerateError!bool {
    if (self.states[pc]) |stack| for (stack) |ty| if (try nonEntryType(Emitter, self, ty)) return true;
    if (pc + 1 < self.states.len) if (self.states[pc + 1]) |stack| for (stack) |ty| if (try nonEntryType(Emitter, self, ty)) return true;
    return false;
}
fn nonEntryType(comptime Emitter: type, self: *Emitter, ty: typed.Type) GenerateError!bool {
    if (!ty.isAggregate()) return false;
    if (self.program.records[ty.recordIndex()].shape.array) |array| if (array.length == 0) return true;
    return (try self.layout(ty)).size == 0;
}
fn initializeStorage(comptime Emitter: type, self: *Emitter) GenerateError!void {
    const f = self.function;
    for (f.scope.locals, 0..) |local, i| {
        // A parameter is stored into its slot below, before any instruction
        // can run, so a root push can never observe it unset.
        if (i < f.signature.parameter_count) continue;
        // Reads and roots of a COW move alias use its owner's storage, and
        // stores to it emit nothing. Its unused physical slot needs no clear.
        if (self.cow != null and self.moves.aliased(i)) continue;
        const placeholder = try placeholderBytes(Emitter, self, i, local.ty);
        if (placeholder != 0) {
            try self.print(" call $memset(l %lz{d}, w 0, l {d})\n storel %lz{d}, %l{d}\n", .{ i, placeholder, i, i });
        } else if (self.byReference(i)) {
            // A borrowed element's slot is one word and is never a root, so
            // clearing the word is all an unset slot needs.
            if ((try self.layout(local.ty)).trace) try self.print(" storel 0, %l{d}\n", .{i});
        } else if ((try self.layout(local.ty)).trace) try zeroTracedLocal(Emitter, self, i, local.ty);
    }
    const packed_args = try packedParameters(Emitter, self, f);
    for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, i| {
        if (packed_args) try unpackArgument(Emitter, self, i);
        if (scalar(local.ty, self.program.records)) {
            try self.print(" storel %a{d}, %l{d}\n", .{ i, i });
        } else if (self.byReference(i)) {
            // QBE-AGGREF-1: the slot holds the caller's address, so the
            // parameter is read through it and never copied at entry.
            try self.print(" storel %a{d}, %l{d}\n", .{ i, i });
        } else try self.print(" blit %a{d}, %l{d}, {d}\n", .{ i, i, (try self.layout(local.ty)).size });
    }
    for (self.arm_addresses) |entry| {
        // The payload already lives at a constant offset inside storage this
        // function never writes, so one store at entry gives every arm its
        // binding and no arm copies the payload out.
        const projected = self.temp();
        if (entry.indirect) {
            const base = try self.load("l", entry.source);
            try self.print(" %v{d} =l add %v{d}, {d}\n storel %v{d}, %l{d}\n", .{ projected, base, entry.offset, projected, entry.slot });
        } else try self.print(" %v{d} =l add %l{d}, {d}\n storel %v{d}, %l{d}\n", .{ projected, entry.source, entry.offset, projected, entry.slot });
    }
}
/// QBE-FRAMEMAP-1: the fast protocol (no step and no frame accounting) links
/// no frame record at all. Every call instead
/// names its bytecode position with `dbgloc PC+1`, the build turns those
/// into a return-address table (`qbe_frame_map.zig`), and the runtime walks
/// the frame-pointer chain only when a trap fires. Nothing else reads a
/// record there: no step check, no depth counter.
fn frameMap(comptime Emitter: type, self: *const Emitter) bool {
    return !self.step_checks and !self.frame_checks;
}
/// Link this function's native-stack frame record and enforce the logical
/// depth ceiling and the execution-stack floor without a runtime call. The
/// record is `{prev, function, position, native_bytes}`; generated code owns
/// the first three words and reads `ctx->frames`/`ctx->frame_limit`/
/// `ctx->frame_floor` at their frozen offsets. The frame-map protocol links
/// none and emits only the stack-floor test (see `frameMap`).
fn enterFrame(comptime Emitter: type, self: *Emitter, name: []const u8) GenerateError!void {
    if (frameMap(Emitter, self)) return guardFrame(Emitter, self);
    const admit = self.temp();
    const stack = self.temp();
    const limit_fail = self.temp();
    const floor_fail = self.temp();
    self.frame_frames = self.temp();
    self.frame_active = self.temp();
    self.record = self.temp();
    const frames = self.temp();
    const limit_slot = self.temp();
    const limit = self.temp();
    const at_limit = self.temp();
    const floor_slot = self.temp();
    const floor = self.temp();
    const below = self.temp();
    const previous = self.temp();
    const function_slot = self.temp();
    const position_slot = self.temp();
    const next = self.temp();
    if (self.frame_checks) {
        try self.print(
            " %v{d} =l add %ctx, 8\n %v{d} =l loadl %v{d}\n %v{d} =l add %ctx, 56\n %v{d} =l loadl %v{d}\n %v{d} =l ceql %v{d}, %v{d}\n" ++
                " jnz %v{d}, @limitfail{d}, @frameadmit{d}\n@limitfail{d}\n",
            .{ self.frame_frames, frames, self.frame_frames, limit_slot, limit, limit_slot, at_limit, frames, limit, at_limit, limit_fail, admit, limit_fail },
        );
        try rc_admission.drop(Emitter, self);
        try self.print(" call $myl_qbe_fail_frame(l %ctx)\n jmp @entry_failure\n@frameadmit{d}\n", .{admit});
    }
    // A leaf's own frame is bounded at compile time, and its caller already
    // proved the frame pointer sits a whole headroom above the guard page, so a
    // leaf that stays well inside that headroom cannot reach it. The guard is
    // redundant there and one comparison per call goes away.
    const guarded = !self.small_leaf;
    // Without logical depth accounting there is no `@frameadmit` block
    // above. Still end the entry block before allocating the probe record:
    // QBE reserves every constant allocation in entry in its static frame,
    // while a later allocation lowers to a stack adjustment after that
    // frame and its register saves. The latter address is the conservative
    // physical stack position the floor comparison requires.
    if (guarded and !self.frame_checks) try self.print(" jmp @frameadmit{d}\n@frameadmit{d}\n", .{ admit, admit });
    if (guarded) {
        try self.print(
            " %v{d} =l alloc8 32\n %v{d} =l add %ctx, 64\n %v{d} =l loadl %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n" ++
                " jnz %v{d}, @floorfail{d}, @stackadmit{d}\n@floorfail{d}\n",
            .{ self.record, floor_slot, floor, floor_slot, below, self.record, floor, below, floor_fail, stack, floor_fail },
        );
        try rc_admission.drop(Emitter, self);
        try self.print(" call $myl_qbe_fail_frame(l %ctx)\n jmp @entry_failure\n@stackadmit{d}\n", .{stack});
    } else try self.print(" %v{d} =l alloc8 32\n", .{self.record});
    try self.print(
        " %v{d} =l add %ctx, 48\n %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 8\n storel extern ${s}_meta, %v{d}\n",
        .{ self.frame_active, previous, self.frame_active, previous, self.record, function_slot, self.record, name, function_slot },
    );
    if (self.frame_checks) try self.print(
        " %v{d} =l add %v{d}, 16\n storel 0, %v{d}\n storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n",
        .{ position_slot, self.record, position_slot, self.record, self.frame_active, next, frames, next, self.frame_frames },
    ) else try self.print(
        " %v{d} =l add %v{d}, 16\n storel 0, %v{d}\n storel %v{d}, %v{d}\n",
        .{ position_slot, self.record, position_slot, self.record, self.frame_active },
    );
    try self.print(" %position =l add %v{d}, 16\n", .{self.record});
    self.linked = true;
}
/// The frame-map prologue (QBE-FRAMEMAP-1): only the execution-stack floor
/// test, with no record to link. The probe is a stack allocation made after
/// the static frame, exactly where the record used to sit, and the adapter
/// reads the real stack pointer in its place. The failure call is positioned
/// at pc 0 with the guard column, so the trace a floor failure builds starts
/// at the caller — the frame this prologue belongs to was never entered.
fn guardFrame(comptime Emitter: type, self: *Emitter) GenerateError!void {
    if (self.small_leaf) return;
    const admit = self.temp();
    const stack = self.temp();
    const floor_fail = self.temp();
    const probe = self.temp();
    const floor_slot = self.temp();
    const floor = self.temp();
    const below = self.temp();
    try self.print(
        " jmp @frameadmit{d}\n@frameadmit{d}\n %v{d} =l alloc8 8\n %v{d} =l add %ctx, 64\n %v{d} =l loadl %v{d}\n %v{d} =l cultl %v{d}, %v{d}\n" ++
            " jnz %v{d}, @floorfail{d}, @stackadmit{d}\n@floorfail{d}\n",
        .{ admit, admit, probe, floor_slot, floor, floor_slot, below, probe, floor, below, floor_fail, stack, floor_fail },
    );
    try rc_admission.drop(Emitter, self);
    try self.print(" dbgloc 1, {d}\n call $myl_qbe_fail_frame(l %ctx)\n jmp @entry_failure\n@stackadmit{d}\n", .{ frame_map_guard_column, stack });
}
/// Unlink this function's frame record and drop the frame count.
/// Refuse, once at the entry point, any runtime ceiling this build omitted
/// accounting for, so a mismatch is reported instead of silently ignored.
fn requireAccounting(comptime Emitter: type, self: *Emitter) GenerateError!void {
    if (!self.step_checks) try self.print(" call $myl_qbe_require_step_accounting(l %ctx)\n", .{});
    if (!self.frame_checks) try self.print(" call $myl_qbe_require_frame_accounting(l %ctx)\n", .{});
}
/// Whether this function transfers control to another guest frame. A leaf's
/// stack use is bounded at compile time, which is what lets its prologue skip
/// the floor guard: the caller already checked the headroom.
fn frameLeaf(comptime Emitter: type, self: *Emitter) bool {
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .call, .invoke => return false,
        else => {},
    };
    return true;
}
fn leaveFrame(comptime Emitter: type, self: *Emitter) GenerateError!void {
    if (!self.linked) return;
    const previous = self.temp();
    const frames = self.temp();
    const next = self.temp();
    if (self.frame_checks) try self.print(
        " %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l sub %v{d}, 1\n storel %v{d}, %v{d}\n",
        .{ previous, self.record, previous, self.frame_active, frames, self.frame_frames, next, frames, next, self.frame_frames },
    ) else try self.print(
        " %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n",
        .{ previous, self.record, previous, self.frame_active },
    );
}
fn allocateIndex(comptime Emitter: type, self: *Emitter, kind: []const u8, index: usize, size: u64) GenerateError!void {
    try allocateSlot(Emitter, self, try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ kind, index }), size);
}
fn allocateSlot(comptime Emitter: type, self: *Emitter, name: []const u8, size: u64) GenerateError!void {
    if (self.heap_frame) {
        try self.print(" %{s} =l add %frame_memory, {d}\n", .{ name, self.frame_offset });
        self.frame_offset = try addFrame(self.frame_offset, size);
    } else try self.print(" %{s} =l alloc8 {d}\n", .{ name, @max(8, size) });
}
/// Return a value after releasing heap-backed execution storage safely.
fn returnValue(comptime Emitter: type, self: *Emitter, value: usize) GenerateError!void {
    if (try @import("qbe_rc_return.zig").emit(Emitter, self, value)) return;
    try cow_lower.Lower(Emitter).clearScopes(self);
    try cleanupLocals(Emitter, self);
    try arena_lower.Lower(Emitter).restore(self);
    var output = value;
    const indirect = try self.largeResult(self.function);
    if (indirect) {
        try self.print(" blit %v{d}, %out, {d}\n", .{ value, (try self.layout(self.function.signature.return_type)).size });
        output = self.temp();
        try self.print(" %v{d} =l copy 0\n", .{output});
    }
    if (self.heap_frame) {
        const bytes = try returnStorageBytes(Emitter, self);
        if (bytes != 0) {
            try self.print(" blit %v{d}, %return_storage, {d}\n", .{ value, bytes });
            output = self.temp();
            try self.print(" %v{d} =l copy %return_storage\n", .{output});
        }
        try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n", .{});
    }
    try leaveFrame(Emitter, self);
    try self.print(" ret %v{d}\n", .{output});
}
fn dropOperand(comptime Emitter: type, self: *Emitter, slot: usize, ty: typed.Type) GenerateError!void {
    if (!(try self.layout(ty)).drop) return;
    if (self.isScalar(ty)) {
        try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %s{d})\n", .{ try self.descriptor(ty), slot });
    } else {
        try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), try self.load("s", slot) });
    }
}
fn cleanupLocals(comptime Emitter: type, self: *Emitter) GenerateError!void {
    var index = self.function.scope.locals.len;
    while (index > 0) {
        index -= 1;
        // A parameter read through the caller's address is the caller's
        // value: this frame never owned it and must not release it.
        if (self.byReference(index)) continue;
        const local = self.function.scope.locals[index];
        if (!(try self.layout(local.ty)).drop) continue;
        if (@import("qbe_aggregate.zig").borrowedPayload(self.function, index)) continue;
        try self.print(drop_local, .{ try self.descriptor(local.ty), index });
    }
}
fn returnStorageBytes(comptime Emitter: type, self: *Emitter) GenerateError!u64 {
    const f = self.function;
    if (self.isScalar(f.signature.return_type) or try self.largeResult(f)) return 0;
    return @max(8, (try self.layout(f.signature.return_type)).size);
}
fn valueStackBytes(comptime Emitter: type, self: *Emitter, ty: typed.Type) GenerateError!u64 {
    if (self.isScalar(ty) or try self.largeValue(ty)) return 8;
    return addFrame(0, @max(8, (try self.layout(ty)).size));
}
fn parameterStackBytes(comptime Emitter: type, self: *Emitter, local: typed.Local) GenerateError!u64 {
    return valueStackBytes(Emitter, self, local.ty);
}
/// Wide signatures pass normalized scalar words and aggregate pointers in one vector.
fn packedParameters(comptime Emitter: type, self: *Emitter, function: bytecode.Function) GenerateError!bool {
    if (function.signature.parameter_count > 128) return true;
    var bytes: u64 = 0;
    for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try parameterStackBytes(Emitter, self, local));
    return bytes > 4096;
}
fn packedCallback(comptime Emitter: type, self: *Emitter, signature: typed.Callable) GenerateError!bool {
    if (signature.parameters.len > 128) return true;
    var bytes: u64 = 0;
    for (signature.parameters) |ty| bytes = try addFrame(bytes, try valueStackBytes(Emitter, self, ty));
    return bytes > 4096;
}
/// Read one packed ABI parameter immediately before snapshotting its local value.
fn unpackArgument(comptime Emitter: type, self: *Emitter, i: usize) GenerateError!void {
    const pointer = self.temp();
    try self.print(" %v{d} =l add %packed, {d}\n %a{d} =l loadl %v{d}\n", .{ pointer, i * 8, i, pointer });
}
fn packArgument(comptime Emitter: type, self: *Emitter, i: usize, value: usize) GenerateError!void {
    const pointer = self.temp();
    try self.print(" %v{d} =l add %arguments, {d}\n storel %v{d}, %v{d}\n", .{ pointer, i * 8, value, pointer });
}
fn argumentVectorBytes(comptime Emitter: type, self: *Emitter) GenerateError!u64 {
    var count: usize = 0;
    for (self.function.scope.instructions) |instruction| {
        const target: ?typed.FunctionId = switch (instruction.op) {
            .call => |id| id,
            else => null,
        };
        if (target) |id| {
            const f = self.program.functions[@backingInt(id)];
            if (try packedParameters(Emitter, self, f)) count = @max(count, f.signature.parameter_count);
        }
        if (instruction.op == .invoke) {
            const sig = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
            if (try packedCallback(Emitter, self, sig)) count = @max(count, sig.parameters.len);
        }
    }
    return @max(8, @as(u64, count) * 8);
}
fn resultStackBytes(comptime Emitter: type, self: *Emitter, function: bytecode.Function) GenerateError!u64 {
    return valueStackBytes(Emitter, self, function.signature.return_type);
}
fn abiStackBytes(comptime Emitter: type, self: *Emitter) GenerateError!u64 {
    // Bounded scalar spill reserve plus exact native argument and result copies.
    var incoming: u64 = 4096;
    if (try packedParameters(Emitter, self, self.function)) {
        incoming += 8;
    } else {
        for (self.function.scope.locals[0..self.function.signature.parameter_count]) |local| incoming = try addFrame(incoming, try parameterStackBytes(Emitter, self, local));
    }
    incoming = try addFrame(incoming, (try resultStackBytes(Emitter, self, self.function)) * 2);
    var outgoing: u64 = 0;
    for (self.function.scope.instructions) |instruction| {
        var bytes: u64 = 0;
        const target: ?typed.FunctionId = switch (instruction.op) {
            .call => |id| id,
            else => null,
        };
        if (target) |id| {
            const function = self.program.functions[@backingInt(id)];
            if (try packedParameters(Emitter, self, function)) {
                bytes = 8;
            } else {
                for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try parameterStackBytes(Emitter, self, local));
            }
            bytes = try addFrame(bytes, try resultStackBytes(Emitter, self, function));
        }
        if (instruction.op == .invoke) {
            const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
            if (try packedCallback(Emitter, self, signature)) {
                bytes = 8;
            } else {
                for (signature.parameters) |ty| bytes = try addFrame(bytes, try valueStackBytes(Emitter, self, ty));
            }
            bytes = try addFrame(bytes, if (try self.largeValue(signature.return_type)) 8 else (try self.layout(signature.return_type)).size);
        }
        outgoing = @max(outgoing, bytes);
    }
    return addFrame(incoming, outgoing);
}
/// Clear a traced local slot whose value has just been released, so a root
/// push can never trace a stale reference. A one-word slot is cleared with a
/// store, which keeps it promotable; an aggregate keeps the `memset`, since
/// the address it takes is one the aggregate's own blits need anyway.
fn zeroTracedLocal(comptime Emitter: type, self: *Emitter, index: usize, ty: typed.Type) GenerateError!void {
    const value = try self.layout(ty);
    if (scalar(ty, self.program.records)) return self.print(" storel 0, %l{d}\n", .{index});
    try self.print(zero_local, .{ index, @max(8, value.size) });
}
fn usesTemporary(comptime Emitter: type, self: *Emitter, pc: usize) bool {
    return switch (self.function.scope.instructions[pc].op) {
        .make_record,
        .make_variant,
        .get_field,
        .update_record,
        .replace_index,
        .get_index,
        .arena_escape,
        .try_result,
        .acquire_buffer,
        .buffer_operation,
        .external_read,
        .environment_get,
        .acquire_resource,
        .complete_resource,
        .resource_io,
        .file_access,
        => true,
        .load_local, .move_local => |slot| !self.isScalar(self.function.scope.locals[@backingInt(slot)].ty),
        .value_copy => self.valueCopies(pc),
        .call => |id| self.largeResult(self.program.functions[@backingInt(id)]) catch false,
        .invoke => |ty| self.largeValue(self.program.records[ty.recordIndex()].contract.callback.?.return_type) catch false,
        else => false,
    };
}
fn temporarySize(comptime Emitter: type, self: *Emitter, pc: usize) GenerateError!u64 {
    var size: u64 = @max(8, try @import("qbe_rc_local_list.zig").scratchBytes(Emitter, self, pc));
    const op = self.function.scope.instructions[pc].op;
    if (op == .try_result) size = @max(size, (try self.layout(op.try_result.output)).size);
    if (self.states[pc]) |stack| for (stack) |ty| {
        size = @max(size, (try self.layout(ty)).size);
    };
    if (pc + 1 < self.states.len) if (self.states[pc + 1]) |stack| {
        for (stack) |ty| size = @max(size, (try self.layout(ty)).size);
    };
    return size;
}
/// The bytes local `index` occupies in the frame: one word when the slot
/// holds an address (QBE-AGGREF-1, QBE-MATCHPROJ-1), the value's own size
/// when it holds the value.
fn localSlotBytes(comptime Emitter: type, self: *Emitter, index: usize, ty: typed.Type) GenerateError!u64 {
    if (self.byReference(index)) return 8;
    return @max(8, (try self.layout(ty)).size);
}
/// The zero-filled buffer a borrowed local's slot points at until the store
/// that gives it its real address runs, or zero when it needs none.
///
/// A root push reads every traced local's slot, including at a safepoint
/// that runs before the store — the very case the per-local zero-fill was
/// written for. A slot that holds an address must therefore always name a
/// traceable value of the local's type, so it starts out naming an all-zero
/// one, which has no reference for the collector to follow. Only a local
/// this frame fills itself needs it: a parameter's address arrives before
/// any instruction runs, and a local whose type traces nothing is never
/// read by a root push.
fn placeholderBytes(comptime Emitter: type, self: *Emitter, index: usize, ty: typed.Type) GenerateError!u64 {
    if (!self.byReference(index) or self.borrowsElement(index)) return 0;
    if (index < self.function.signature.parameter_count) return 0;
    const value = try self.layout(ty);
    if (!value.trace) return 0;
    return @max(8, value.size);
}
/// The stack bytes one outgoing argument of this type can occupy: one word
/// for a value that crosses as a scalar or as an address, the value's own
/// size only for a move-only aggregate that still crosses by value. The
/// crossing answer is `qbe_wire.byAddress`, the one `argumentType` reads,
/// so the estimate and the call can never disagree.
fn argumentBytes(comptime Emitter: type, self: *Emitter, ty: typed.Type) GenerateError!u64 {
    const value = try self.layout(ty);
    if (self.isScalar(ty) or qbe_wire.byAddress(value, ty, self.program.records)) return 8;
    return @max(8, value.size);
}
/// Every per-pc aggregate scratch pair the lowering might declare, each at
/// the widest operand its instruction can see: the bound `frameBytes` has
/// to use before the body exists, and the size a heap frame is given.
fn possibleTemporaryBytes(comptime Emitter: type, self: *Emitter) GenerateError!u64 {
    var size: u64 = 0;
    for (self.states, 0..) |state, pc| if (state != null and usesTemporary(Emitter, self, pc)) {
        const temporary = try temporarySize(Emitter, self, pc);
        size = try addFrame(size, temporary);
        size = try addFrame(size, temporary);
    };
    return size;
}
/// The per-pc aggregate scratch a lowered body still declares, summed from
/// the `%agg{pc}` and `%aux{pc}` declarations that survived forwarding, the
/// borrow rule and `dropUnusedSlots`: what the frame really carries.
pub fn declaredTemporaryBytes(text: []const u8) GenerateError!u64 {
    var size: u64 = 0;
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        const name = slotDefinition(line) orelse continue;
        if (!isTemporarySlot(name)) continue;
        const marker = " =l alloc8 ";
        const at = std.mem.indexOf(u8, line, marker) orelse continue;
        const bytes = std.fmt.parseInt(u64, line[at + marker.len ..], 10) catch return error.InternalError;
        size = try addFrame(size, bytes);
    }
    return size;
}
/// Whether a slot name is one pc's aggregate scratch: `agg` or `aux`
/// followed by the pc.
fn isTemporarySlot(name: []const u8) bool {
    if (name.len < 4) return false;
    if (!std.mem.eql(u8, name[0..3], "agg") and !std.mem.eql(u8, name[0..3], "aux")) return false;
    for (name[3..]) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}
/// The frame this function needs with `temporaries` bytes of per-pc
/// aggregate scratch: every local, operand and root slot, the return and
/// argument storage and the widest outgoing argument list, doubled to
/// cover the spills QBE adds. On the native stack it must stay within
/// `native_frame_limit`; a heap frame is allocated at exactly this size.
fn frameBytes(comptime Emitter: type, self: *Emitter, capacity: usize, temporaries: u64) GenerateError!u64 {
    var size: u64 = (try argumentVectorBytes(Emitter, self)) + 64 + @as(u64, capacity) * 8;
    for (self.function.scope.locals, 0..) |local, i| {
        size = try addFrame(size, try localSlotBytes(Emitter, self, i, local.ty));
        size = try addFrame(size, try placeholderBytes(Emitter, self, i, local.ty));
    }
    size = try addFrame(size, cow_lower.Lower(Emitter).scopeBytes(self));
    size = try addFrame(size, try rc_frame.Lower(Emitter).bytes(self));
    size = try addFrame(size, temporaries);
    size = try addFrame(size, self.range_keys.frameBytes());
    if (self.has_roots and !runtime.enabled()) size = try addFrame(size, @as(u64, self.function.scope.locals.len + capacity) * 32);
    // A result that crosses through the caller's storage occupies nothing
    // here; any other aggregate result has its zeroed copy and, in a heap
    // frame, the copy the return path hands back.
    size = try addFrame(size, @max(16, (try returnStorageBytes(Emitter, self)) * 2));
    var outgoing: u64 = 0;
    for (self.function.scope.instructions) |instruction| {
        const target: ?typed.FunctionId = switch (instruction.op) {
            .call => |id| id,
            else => null,
        };
        if (instruction.op == .invoke) {
            const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
            var arguments: u64 = 0;
            for (signature.parameters) |ty| arguments = try addFrame(arguments, try argumentBytes(Emitter, self, ty));
            outgoing = @max(outgoing, arguments);
        }
        if (target) |id| {
            const callee = self.program.functions[@backingInt(id)];
            var arguments: u64 = 0;
            for (callee.scope.locals[0..callee.signature.parameter_count]) |local| arguments = try addFrame(arguments, try argumentBytes(Emitter, self, local.ty));
            outgoing = @max(outgoing, arguments);
        }
    }
    return std.math.mul(u64, try addFrame(size, outgoing), 2) catch error.InternalError;
}
fn addFrame(left: u64, right: u64) GenerateError!u64 {
    const aligned = std.math.add(u64, right, 7) catch return error.InternalError;
    return std.math.add(u64, left, aligned & ~@as(u64, 7)) catch error.InternalError;
}

test "a frame counts each aggregate temporary buffer rounded up to eight bytes" {
    const text = " %agg3 =l alloc8 12\n %aux3 =l alloc8 16\n %l0 =l alloc8 8\n %aggx =l alloc8 64\n";
    try std.testing.expectEqual(@as(u64, 32), try declaredTemporaryBytes(text));
    try std.testing.expectEqual(@as(u64, 24), try addFrame(8, 9));
    try std.testing.expectError(error.InternalError, addFrame(std.math.maxInt(u64), 8));
}
