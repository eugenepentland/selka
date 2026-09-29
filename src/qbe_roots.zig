//! The garbage-collection root protocol at safepoints: which instructions can
//! allocate or reach a collection, which locals are live and traced across one,
//! and the root records pushed before and restored after it. Each step is a
//! free function over the concrete emitter type; `Lower` exposes the ones the
//! rest of the emitter calls as `self.name(...)`.
const liveness = @import("qbe_liveness.zig");
const runtime = @import("runtime_mode.zig");
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const qbe_wire = @import("qbe_wire.zig");
const scalar = qbe_wire.scalar;
/// Failures a root-protocol step reports: the same set as `qbe.GenerateError`.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Frozen byte offset of `myl_native_heap.roots`, matched by the
/// `_Static_assert(offsetof(myl_native_heap, roots) == 16, ...)` in
/// `src/qbe_runtime.c`. Generated root pushes and restores read and write this
/// field directly, so it must change only together with the header.
const heap_roots_offset: u64 = 16;
/// One live root at a safepoint: the `%root{i}` slot that receives it, the
/// slot or pointer the traced value is read from, and the descriptor naming the
/// traced layout.
const RootSlot = struct {
    /// Index of the `%root{i}` slot this root occupies.
    index: usize,
    /// IL reference to the slot holding the traced value (`%l{i}`, `%s{i}`) when
    /// `copy` is set, or to the storage the collector walks directly.
    source: []const u8,
    /// Whether `source` names a slot that holds the traced value itself. The
    /// push copies the slot into the record's value word and points the traced
    /// address at that copy, so the collector never takes the slot's address and
    /// QBE can keep it in a register. An aggregate's `source` is already the
    /// storage address the collector must walk, so it is stored as it stands.
    copy: bool,
    /// Descriptor symbol naming the traced layout.
    descriptor: []const u8,
};
/// Runtime callees a lowering may name that allocate nothing and can collect
/// no garbage. A caller that only reaches these (or a `myl_qbe_fail_*` trap
/// helper, matched by prefix) therefore needs no roots around the instruction.
/// Everything else — a guest function, a collection constructor, a print sink,
/// a provider — stays a safepoint.
const pure_callees = [_][]const u8{
    "memset",
    "myl_native_owned_drop",
    "myl_native_list_get",
    // The pinned number grammar and the validating scalar count read their input
    // in place: no allocation, so a function whose only calls are these starts no
    // collection and needs neither a root protocol nor a safepoint.
    "myl_native_number_parse",
    "myl_native_text_compare",
    "myl_native_bytes_compare",
    // `round(x, n)` reads and answers bits; it never allocates.
    "myl_native_float_round",
    "myl_native_text_payload",
    "myl_native_bytes_number_parse",
    "myl_native_bytes_range",
    "myl_native_bytes_scalar_count",
    "myl_qbe_int_cast",
    "myl_qbe_int_neg",
    "myl_qbe_int_binary",
    "myl_qbe_float_check",
    "myl_qbe_float_unary",
    "myl_qbe_float_integer",
    // The read-only collection surfaces: a dictionary probe, a byte search and
    // the octet copy the inlined buffer append performs all take a `const`
    // receiver, walk storage the caller already holds, and allocate nothing. The
    // one write any of them makes is the hash a text caches in its own header, so
    // a frame whose only calls are these never reaches a collection and needs no
    // root record around them.
    "myl_native_dictionary_read",
    "myl_native_dictionary_contains",
    // A described slice (`DICT-RANGE-KEY-1`): the span computation and the two
    // lookups by span read the heap's collection count and nothing else of it.
    "myl_native_text_range",
    "myl_native_dictionary_read_range",
    "myl_native_dictionary_contains_range",
    // The allocation-free half of a dictionary write (`DICT-OVERWRITE-1`): it
    // replaces a present key's value and never inserts.
    "myl_native_dictionary_overwrite",
    "myl_native_dictionary_overwrite_range",
    "myl_native_dictionary_length",
    "myl_native_dictionary_key_at",
    "myl_native_dictionary_value_at",
    "myl_native_bytes_find",
    "myl_native_bytes_find_any",
    "myl_native_bytes_starts_with",
    "myl_native_bytes_ends_with",
    "myl_native_bytes_has_byte",
    "myl_native_bytes_copy_octets",
    // ERROR-TRACE-1: the error return trace recorders write two words of a
    // static ring and a count, and touch nothing else.
    "myl_qbe_error_trace_append",
    "myl_qbe_error_trace_origin",
};
/// A call names a callee that allocates nothing and can collect nothing: one
/// of the pure runtime helpers or a `myl_qbe_fail_*` cold trap helper.
pub fn pureCalleeName(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "myl_qbe_fail_")) return true;
    for (pure_callees) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}
/// Whether the text invokes a function value (`QBE-INVOKE-SAFEPOINT-1`). The
/// callee is whatever top-level function the value names, known only at run
/// time, so the call is a safepoint and its caller can allocate — exactly like a
/// direct call to a function that can.
pub fn callsIndirectly(text: []const u8) bool {
    return std.mem.indexOf(u8, text, " call %") != null;
}
const impl = @This();
/// Bind the root protocol to the concrete emitter without an import cycle.
pub fn Lower(comptime Emitter: type) type {
    return struct {
        /// Whether this function keeps the root protocol at all: it has a live
        /// traced local or operand and at least one instruction that can collect.
        /// A lowering that roots only its allocating branch asks first, because
        /// without the protocol there is no `%root_mark` or root slot to link.
        pub fn needsRootProtocol(self: *Emitter) bool {
            return impl.needsRootProtocol(Emitter, self);
        }
        /// Restore the heap's root chain to this frame's mark with one store,
        /// replacing the former `myl_qbe_root_restore` call.
        pub fn restoreRoots(self: *Emitter) GenerateError!void {
            return impl.restoreRoots(Emitter, self);
        }
        /// Leave the function with exactly the caller's root chain, regardless
        /// of the bytecode position retained while emitting a failure block.
        pub fn restoreFrameRoots(self: *Emitter) GenerateError!void {
            return impl.restoreTo(Emitter, self, null);
        }
        /// Answer which locals each safepoint publishes. A local whose type owns
        /// something is pinned: the epilogue and every overwriting store release it
        /// through its slot, so it stays published wherever it was before.
        pub fn rootLiveness(self: *Emitter) GenerateError!liveness.Roots {
            return impl.rootLiveness(Emitter, self);
        }
        /// Whether an instruction needs the root protocol: its opcode admits
        /// allocation, and it is not a call to a function that cannot collect.
        pub fn rootedSafepoint(self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
            return impl.rootedSafepoint(Emitter, self, op);
        }
        /// Push every live traced local and operand as a `myl_native_root` link
        /// built from straight-line stores instead of a runtime call. The chain
        /// head is loaded once from the frozen `myl_native_heap.roots` offset, and
        /// each slot's `previous` names the link pushed before it, so the collector
        /// walks every live root. Field order matches `struct myl_native_root`.
        /// Returns whether any root was pushed.
        pub fn roots(self: *Emitter, stack: []const typed.Type) GenerateError!bool {
            return impl.roots(Emitter, self, stack);
        }
    };
}
/// Whether a bytecode operation can allocate, and so be a safepoint, before its
/// lowering is known.
pub fn allocates(op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .cast_integer,
        .call,
        .invoke,
        .acquire_buffer,
        .buffer_operation,
        .make_record,
        .get_index,
        .binary_integer,
        .acquire_resource,
        .complete_resource,
        .resource_io,
        .file_access,
        .file_method,
        // `print` begins a sink that can allocate its buffer, so managed
        // operands and locals must be rooted across it.
        .print,
        // A value-semantics copy allocates unless the ownership analysis
        // proved it a move or a borrow, which then lowers to nothing.
        .value_copy,
        => true,
        else => false,
    };
}
/// Whether a lowered call's callee allocates nothing and so is no safepoint.
pub fn pureCallee(name: []const u8) bool {
    return pureCalleeName(name);
}
/// Whether an instruction needs the root protocol: its opcode admits
/// allocation, and it is not a call to a function that cannot collect.
fn rootedSafepoint(comptime Emitter: type, self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
    if (!needsRootProtocol(Emitter, self)) return false;
    if (!allocates(op) and !self.boxProjectionAt(self.pc, op)) return false;
    return !callsPureFunction(Emitter, self, op) or cowMutCallMayCopy(Emitter, self, op);
}
/// Preparing a mutable collection argument can copy it before a callee runs,
/// including a callee otherwise classified noalloc. The call's outer root
/// chain must already be published when that preparation begins.
fn cowMutCallMayCopy(comptime Emitter: type, self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
    if (self.cow == null) return false;
    const id = switch (op) {
        .call => |callee| @backingInt(callee),
        else => return false,
    };
    const function = self.program.functions[id];
    for (function.signature.declared_mutates) |position| {
        if (position < function.scope.locals.len and @import("cow_plan.zig").payloadType(self.program, function.scope.locals[position].ty)) return true;
    }
    for (function.signature.mutates) |position| {
        if (position < function.scope.locals.len and @import("cow_plan.zig").payloadType(self.program, function.scope.locals[position].ty)) return true;
    }
    return false;
}
/// Whether this instruction is a direct call to a function that can neither
/// allocate nor reach an allocation, so no collection can run inside it and
/// the caller needs no roots across it.
fn callsPureFunction(comptime Emitter: type, self: *Emitter, op: @FieldType(bytecode.Instruction, "op")) bool {
    const id = switch (op) {
        .call => |callee| @backingInt(callee),
        else => return false,
    };
    return id < self.pure.len and self.pure[id];
}
/// Whether this safepoint has at least one live traced local or operand.
/// With none there is nothing to link, and the push and its restore are
/// omitted, exactly as the former per-root call sequence omitted them.
fn liveRoots(comptime Emitter: type, self: *Emitter, stack: []const typed.Type) GenerateError!bool {
    for (self.function.scope.locals, 0..) |local, i| if (try publishedRoot(Emitter, self, i, local.ty)) return true;
    for (stack) |ty| if ((try self.layout(ty)).trace) return true;
    return false;
}
/// Whether local `index` is one the root protocol reads. A borrowed element
/// is not: no collection can run while its borrow is live, and once the
/// borrow is dead the address it holds could name storage the receiver has
/// since reallocated or the sweep has freed.
fn tracedRoot(comptime Emitter: type, self: *Emitter, index: usize, ty: typed.Type) GenerateError!bool {
    if (self.borrowsElement(index)) return false;
    return (try self.layout(ty)).trace;
}
/// Whether a safepoint at the current instruction publishes local `index`:
/// the root protocol reads it and its value is live there
/// (`QBE-ROOTLIVE-1`). A dead local's value is never read again, so a
/// collection that frees what only it named frees garbage.
fn publishedRoot(comptime Emitter: type, self: *Emitter, index: usize, ty: typed.Type) GenerateError!bool {
    if (!try tracedRoot(Emitter, self, index, ty)) return false;
    const live = self.live_roots orelse return true;
    if (!live.has(self.pc, index)) return false;
    // QBE-BORROW-ROOT-1: a borrowed local whose owner reaches its value here
    // needs no record of its own.
    if (self.coverage.owners.len == 0) return true;
    const flags = try publishedFlags(Emitter, self);
    return flags[index];
}
/// How many owners a chain of covered locals may pass through before the
/// cover is refused; a chain that long is published instead.
const cover_depth = 8;
/// What the safepoint decided for one local: nothing (not a live traced
/// local), a published anchor, a covered local whose value an anchor reaches,
/// or not yet decided.
const Decision = enum(u8) { none, anchor, covered, pending };
/// Whether a covered local's owner chain reaches a published anchor.
const Reach = enum(u8) { yes, no, wait };
/// Per local, whether the safepoint at the current pc publishes it
/// (`QBE-BORROW-ROOT-1`). Live traced locals no owner covers are anchors and
/// always published. A covered local is dropped when its owner chain — through
/// dead locals that are covered themselves, or live ones already dropped —
/// reaches an anchor; when it cannot, it becomes an anchor itself. Each
/// dropped value is therefore reachable from a published root through a
/// finite chain, and no two locals are dropped on each other's account.
fn publishedFlags(comptime Emitter: type, self: *Emitter) GenerateError![]const bool {
    if (self.published_pc == self.pc) return self.published_flags;
    const locals = self.function.scope.locals;
    const decisions = try self.allocator.alloc(Decision, locals.len);
    defer self.allocator.free(decisions);
    const live = self.live_roots.?;
    for (locals, decisions, 0..) |local, *decision, index| {
        const published = try tracedRoot(Emitter, self, index, local.ty) and live.has(self.pc, index);
        decision.* = if (!published) .none else if (self.coverage.owner(self.pc, index) != null) .pending else .anchor;
    }
    while (true) {
        var progress = false;
        var first_pending: ?usize = null;
        for (decisions, 0..) |*decision, index| {
            if (decision.* != .pending) continue;
            switch (try reaches(Emitter, self, decisions, index)) {
                .yes => decision.* = .covered,
                .no => decision.* = .anchor,
                .wait => {
                    if (first_pending == null) first_pending = index;
                    continue;
                },
            }
            progress = true;
        }
        if (progress) continue;
        // Owners waiting on each other: publish the first to break the cycle.
        const stuck = first_pending orelse break;
        decisions[stuck] = .anchor;
    }
    const flags = try self.allocator.alloc(bool, locals.len);
    for (flags, decisions) |*flag, decision| flag.* = decision == .anchor;
    self.published_pc = self.pc;
    self.published_flags = flags;
    return flags;
}
/// Walk local `index`'s owner chain to a published anchor, a local already
/// dropped (whose own chain reaches one), or a dead end.
fn reaches(comptime Emitter: type, self: *Emitter, decisions: []const Decision, index: usize) GenerateError!Reach {
    var at = self.coverage.owner(self.pc, index) orelse return .no;
    for (0..cover_depth) |_| {
        switch (decisions[at]) {
            .anchor, .covered => return .yes,
            .pending => return .wait,
            .none => {
                // A dead local still holds what it read from its own owner.
                if (!try tracedRoot(Emitter, self, at, self.function.scope.locals[at].ty)) return .no;
                at = self.coverage.owner(self.pc, at) orelse return .no;
            },
        }
    }
    return .no;
}
/// Answer which locals each safepoint publishes. A local whose type owns
/// something is pinned: the epilogue and every overwriting store release it
/// through its slot, so it stays published wherever it was before.
fn rootLiveness(comptime Emitter: type, self: *Emitter) GenerateError!liveness.Roots {
    const locals = self.function.scope.locals;
    const pinned = try self.allocator.alloc(bool, locals.len);
    defer self.allocator.free(pinned);
    for (locals, pinned) |local, *pin| pin.* = (try self.layout(local.ty)).drop;
    const input: liveness.Input = .{ .function = self.function, .states = self.states, .pinned = pinned };
    // OWNERSHIP-ANALYSIS-1: the solution the ownership analysis read.
    if (self.live) |solution| return liveness.roots(self.allocator, input, solution);
    return liveness.analyze(self.allocator, input);
}
/// Whether this function keeps the root protocol at all: it has a live
/// traced local or operand and at least one instruction that can collect.
/// A lowering that roots only its allocating branch asks first, because
/// without the protocol there is no `%root_mark` or root slot to link.
fn needsRootProtocol(comptime Emitter: type, self: *Emitter) bool {
    return !runtime.enabled() and self.has_roots and self.has_safepoints;
}
/// Push every live traced local and operand as a `myl_native_root` link
/// built from straight-line stores instead of a runtime call. The chain
/// head is loaded once from the frozen `myl_native_heap.roots` offset, and
/// each slot's `previous` names the link pushed before it, so the collector
/// walks every live root. Field order matches `struct myl_native_root`.
/// Returns whether any root was pushed.
fn roots(comptime Emitter: type, self: *Emitter, stack: []const typed.Type) GenerateError!bool {
    // Counted heaps drain journaled obligations; they never trace this chain.
    if (runtime.enabled() or !try liveRoots(Emitter, self, stack)) return false;
    const base = self.temp();
    try self.print(" %v{d} =l add %heap, {d}\n", .{ base, heap_roots_offset });
    const head = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n", .{ head, base });
    var count: usize = 0;
    var previous = try std.fmt.allocPrint(self.allocator, "%v{d}", .{head});
    for (self.function.scope.locals, 0..) |local, i| if (try publishedRoot(Emitter, self, i, local.ty)) {
        // A parameter read through the caller's address is traced where it
        // lives; every other aggregate local is traced at its own slot.
        // QBE-MOVE-ELIDE-1: an alias's value lives in the slot it names.
        const storage = self.moves.resolve(i);
        const traced = if (self.byReference(storage))
            try std.fmt.allocPrint(self.allocator, "%v{d}", .{try self.load("l", storage)})
        else
            try std.fmt.allocPrint(self.allocator, "%l{d}", .{storage});
        try pushRoot(Emitter, self, .{ .index = count, .source = traced, .copy = scalar(local.ty, self.program.records), .descriptor = try self.descriptor(local.ty) }, previous, base);
        previous = try std.fmt.allocPrint(self.allocator, "%root{d}", .{count});
        count += 1;
    };
    for (stack, 0..) |ty, i| if ((try self.layout(ty)).trace) {
        const by_value = scalar(ty, self.program.records);
        const traced = if (by_value)
            try std.fmt.allocPrint(self.allocator, "%s{d}", .{i})
        else
            try std.fmt.allocPrint(self.allocator, "%v{d}", .{try self.load("s", i)});
        try pushRoot(Emitter, self, .{ .index = count, .source = traced, .copy = by_value, .descriptor = try self.descriptor(ty) }, previous, base);
        previous = try std.fmt.allocPrint(self.allocator, "%root{d}", .{count});
        count += 1;
    };
    return true;
}
/// Fill one `myl_native_root` slot in place — `previous`, the traced
/// address, the type descriptor, then the value word — and link it into the
/// heap's chain through `base`, the address of `myl_native_heap.roots`. A
/// scalar root is copied into the record's fourth word and the traced
/// address points at that copy, so the slot it came from is only ever read;
/// an aggregate root is already an address and is traced where it lives.
fn pushRoot(comptime Emitter: type, self: *Emitter, slot: RootSlot, previous: []const u8, base: usize) GenerateError!void {
    const at = self.temp();
    const ty = self.temp();
    try self.print(" storel {s}, %root{d}\n %v{d} =l add %root{d}, 8\n", .{ previous, slot.index, at, slot.index });
    if (slot.copy) {
        const value = self.temp();
        const held = self.temp();
        try self.print(
            " %v{d} =l loadl {s}\n %v{d} =l add %root{d}, 24\n storel %v{d}, %v{d}\n storel %v{d}, %v{d}\n",
            .{ value, slot.source, held, slot.index, value, held, held, at },
        );
    } else try self.print(" storel {s}, %v{d}\n", .{ slot.source, at });
    try self.print(
        " %v{d} =l add %root{d}, 16\n storel extern ${s}, %v{d}\n storel %root{d}, %v{d}\n",
        .{ ty, slot.index, slot.descriptor, ty, slot.index, base },
    );
}
/// Restore the heap's root chain to this frame's mark with one store,
/// replacing the former `myl_qbe_root_restore` call.
fn restoreRoots(comptime Emitter: type, self: *Emitter) GenerateError!void {
    return restoreTo(Emitter, self, @import("qbe_cow.zig").Lower(Emitter).scopeRoot(self, self.pc));
}

fn restoreTo(comptime Emitter: type, self: *Emitter, scope: ?usize) GenerateError!void {
    if (runtime.enabled()) return;
    const base = self.temp();
    try self.print(" %v{d} =l add %heap, {d}\n", .{ base, heap_roots_offset });
    if (scope) |fill| {
        try self.print(" storel %cowscope{d}, %v{d}\n", .{ fill, base });
    } else try self.print(" storel %root_mark, %v{d}\n", .{base});
}

test "trap helpers and listed runtime reads are no safepoint, an indirect call always is" {
    try std.testing.expect(pureCalleeName("myl_qbe_fail_step"));
    try std.testing.expect(pureCalleeName("myl_native_dictionary_read"));
    try std.testing.expect(!pureCalleeName("myl_native_list_append"));
    try std.testing.expect(callsIndirectly(" %v3 =l call %v2(l %ctx)\n"));
    try std.testing.expect(!callsIndirectly(" %v3 =l call $myl_f_1(l %ctx)\n"));
}
