//! Native lowering of copy-on-write over the tracing collector (D9 stage 3b;
//! `COW-SHARED-1`, `COW-UNIQUE-1`, `COW-HOIST-1`, `COW-NESTED-1`,
//! `COW-PIN-1`, `COW-STATS-1`; runtime in `native_cow.h`).
//!
//! Every check is inline: one header load and one bit test on the path that
//! finds the payload unique, and a runtime call, under the root protocol, only
//! on the path that copies. The plan (`cow_plan.zig`) says where each check
//! goes; this file emits it:
//!
//! - before an instruction, the root payloads it writes are made unique and
//!   the slot holding each copy is redirected (with every whole alias of it);
//! - before a `store_local` filling a place, the value is made unique and a
//!   copy is written back into the element, dictionary value or field it was
//!   read from;
//! - on the entry edges of a loop, the checks the ownership analysis proved
//!   the loop cannot invalidate (a jump from outside the loop lands on the
//!   block `@ce<head>` instead of the header);
//! - around a call, every list or dictionary a `mut` parameter receives is
//!   pinned, so nothing the callee does can share it (`COW-PIN-1`);
//! - at a transfer the ownership analysis calls a copy, its payloads are
//!   shared: one bit set per payload, or a copy of a pinned one.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const rc_values = @import("qbe_rc_values.zig");
const cow_plan = @import("cow_plan.zig");
const format = @import("qbe_format.zig");
const qbe_alloc = @import("qbe_alloc.zig");
const runtime_mode = @import("runtime_mode.zig");
const rc_unique = @import("qbe_rc_unique.zig");
const rc_scope = @import("qbe_rc_scope.zig");
const inert_receiver = @import("qbe_rc_inert_receiver.zig");
const semantics = @import("value_semantics.zig");
const cow_keep_label = "@cowkeep{d}\n";
const store_pointer = " storel %v{d}, %v{d}\n";
const store_local = " storel %v{d}, %l{d}\n";
const store_operand = " storel %v{d}, %s{d}\n";
const unique_call = " %v{d} =l call $myl_native_cow_unique(l %heap, l %v{d})\n";

/// Failures emitting copy-on-write code can meet.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Two-word object header in front of every managed payload.
const header_bytes = 16;
/// `MYL_NATIVE_OBJECT_SHARED` and `MYL_NATIVE_OBJECT_PINNED` (`native_heap.h`).
pub const shared_flag: u64 = 1 << 61;
/// See `shared_flag`.
pub const pinned_flag: u64 = 1 << 60;
/// Every mark-word bit but `pinned_flag`, as the signed literal QBE reads.
const unpinned_mask: i64 = @bitCast(~pinned_flag);
/// The event kinds `myl_native_cow_tally` counts (`native_cow.h`).
const Tally = enum(u32) { mark = 0, check = 1, hoisted = 2, pin = 3 };

/// One instruction's saved array index and pending-scope plan. Scope indices
/// name place locals; `active` excludes a scope beginning at this instruction.
const Capture = struct { index: usize = 0, begin: u32 = cow_plan.none, active: u32 = cow_plan.none };

/// The copy-on-write state of the function being lowered.
pub const State = struct {
    plan: cow_plan.Plan = .{},
    /// Per instruction, the temporary holding an element place's index,
    /// captured by its base read for the fill's write-back.
    captures: []Capture = &.{},
    /// Whether every inline mark, check and pin also counts itself.
    counting: bool,
    /// Physical ownership state in the experimental RC lane.
    rc: ?*@import("qbe_rc_state.zig").State = null,
};

/// The state a function's lowering starts from when the build emits
/// copy-on-write code; `Lower.plan` fills it in once the ownership analysis
/// has run.
pub fn request(allocator: std.mem.Allocator, counting: bool) Error!*State {
    const state = try allocator.create(State);
    state.* = .{ .counting = counting };
    return state;
}

/// The pins one call placed, undone in reverse order after it returns.
pub const Pins = struct { headers: [8]usize = undefined, olds: [8]usize = undefined, len: usize = 0 };

/// Bind copy-on-write lowering to the concrete emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Plan the function under the ownership analysis already run.
        pub fn plan(self: *E, state: *State) Error!bool {
            const analysis = try rc_unique.analysis(E, self);
            const input: cow_plan.Input = .{
                .program = self.program,
                .function = self.function,
                .states = self.states,
                .analysis = analysis,
                .shares = !semantics.enabled(),
            };
            state.plan = cow_plan.plan(self.allocator, input) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InternalError => error.InternalError,
            };
            state.captures = try self.allocator.alloc(Capture, self.function.scope.instructions.len);
            @memset(state.captures, .{});
            prepareScopes(E, self, state);
            return retainPlaces(E, self, state.plan);
        }
        /// Keep a versioned loop only when no check is left inside it
        /// (`QBE-LOOP-VERSION-1`): a copy there would move the storage its
        /// guard read.
        pub fn veto(self: *E, state: *State) Error!void {
            try refineRcLoops(E, self, state);
            var kept: std.ArrayList(@TypeOf(self.loop_plan.loops[0])) = .empty;
            for (self.loop_plan.loops) |loop| {
                const checked = for (loop.head..loop.back + 1) |pc| {
                    if (pc < state.plan.checked.len and state.plan.checked[pc]) break true;
                } else false;
                if (!checked and versionLifetime(E, self, loop.head, loop.back)) try kept.append(self.allocator, loop);
            }
            self.loop_plan.loops = try kept.toOwnedSlice(self.allocator);
        }
        /// Emit what runs before instruction `pc`: captures, root checks,
        /// place fills and shares.
        pub fn before(self: *E, pc: usize, stack: []const typed.Type) Error!void {
            const state = self.cow orelse return;
            const site = state.plan.at(pc);
            if (site.capture) try capture(E, self, state, pc, stack);
            try readCaptures(E, self, stack, site.read_captures);
            if (site.unique_field) |field| try uniqueField(E, self, field, stack);
            for (site.unique) |unique| try uniqueLocal(E, self, unique, stack);
            const beginning = state.captures[pc].begin;
            if (beginning != cow_plan.none) try beginScope(E, self, state.plan.places[beginning].?, stack);
            if (site.fill) try fillPlace(E, self, pc, stack);
            if (!runtime_mode.enabled()) for (site.shares) |depth| try share(E, self, stack, depth);
        }
        /// Whether this place retains temporary pins across an index callback.
        pub fn scoped(self: *const E, place: cow_plan.Place) bool {
            return scopePlace(E, self, place);
        }
        /// Bytes reserved for the persistent roots of pending array receivers.
        pub fn scopeBytes(self: *const E) usize {
            const state = self.cow orelse return 0;
            var count: usize = 0;
            for (state.plan.places) |maybe| if (maybe) |place| {
                if (scopePlace(E, self, place)) count += scopeStorageBytes(E, self, place);
            };
            return count;
        }
        /// Storage for one scope root and its finite source-path projection.
        pub fn scopeStorage(self: *const E, place: cow_plan.Place) usize {
            return scopeStorageBytes(E, self, place);
        }
        /// A boxed projection already detached and protected by a pending path
        /// reads that prepared body without creating an independent value.
        pub fn scopedProjection(self: *const E, pc: usize) bool {
            const state = self.cow orelse return false;
            if (runtime_mode.enabled() and state.captures[pc].begin != cow_plan.none) return true;
            const active = state.captures[pc].active;
            if (active == cow_plan.none) return false;
            const place = state.plan.places[active].?;
            return pc < place.fill and pathStep(E, self, place, pc);
        }
        /// A prepared compiler receiver borrows a held, pinned path through use.
        pub fn borrowReceiver(self: *E, local: usize, payload: usize) Error!void {
            return borrowReceiverImpl(E, self, local, payload);
        }
        /// Release a GC receiver scope only after its consuming operation.
        pub fn after(self: *E, pc: usize) Error!void {
            try finishCallReceivers(E, self, pc);
            return finishGcScopes(E, self, pc);
        }
        /// End receiver holds only after the mutator and its result publication.
        pub fn finishReceiver(self: *E, owner: usize) Error!void {
            return finishReceiverImpl(E, self, owner);
        }
        /// The persistent root left after an instruction's temporary roots.
        pub fn scopeRoot(self: *const E, pc: usize) ?usize {
            if (runtime_mode.enabled()) return null;
            return activeScope(E, self, pc, null);
        }
        /// Undo every still-active pending receiver before returning or trapping.
        pub fn clearScopes(self: *E) Error!void {
            return clearScopesImpl(E, self);
        }
        /// Emit the entry block of the loop headed at `head`: its hoisted
        /// checks, entered by every jump from outside the loop.
        pub fn entry(self: *E, head: usize) Error!void {
            const state = self.cow orelse return;
            const hoisted = state.plan.entry(head);
            if (hoisted.len == 0) return;
            const stack = self.states[head] orelse return;
            try self.print("@ce{d}\n storel {d}, %position\n", .{ head, head });
            const saved = self.pc;
            self.pc = head;
            defer self.pc = saved;
            for (hoisted) |check| {
                if (state.counting) try tally(E, self, .hoisted);
                if (check.elements) try uniqueElements(E, self, check.local, stack) else try uniqueLocal(E, self, .{ .local = check.local }, stack);
            }
        }
        /// Whether a jump from the current instruction to `target` enters a
        /// loop with entry checks, and so lands on its `@ce` block.
        pub fn enters(self: *const E, target: usize) bool {
            const state = self.cow orelse return false;
            return state.plan.loops.enters(target, self.pc);
        }
        /// Pin every list or dictionary argument a `mut` parameter of
        /// `callee` receives, before the call.
        pub fn pin(self: *E, callee: bytecode.Function, args: []usize, base: usize) Error!Pins {
            return pinCall(E, self, .{ .direct = callee }, args, base);
        }
        /// Prepare and pin the mutable parameters of an indirect call.
        pub fn pinIndirect(self: *E, callee: typed.Callable, args: []usize, base: usize) Error!Pins {
            return pinCall(E, self, .{ .indirect = callee }, args, base);
        }
        /// Undo `pins` after the call returned: a payload pinned by this call
        /// alone is unpinned; one an outer caller pinned stays pinned.
        pub fn unpin(self: *E, pins: Pins) Error!void {
            if (runtime_mode.enabled()) {
                if (pins.len != 0) try rc_scope.end(E, self, pins.headers[0]);
                return;
            }
            var index = pins.len;
            while (index > 0) {
                index -= 1;
                const label = self.temp();
                const word = self.temp();
                const next = self.temp();
                try self.print(" jnz %v{d}, @pinned{d}, @unpin{d}\n@unpin{d}\n", .{ pins.olds[index], label, label, label });
                try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, {d}\n storel %v{d}, %v{d}\n@pinned{d}\n", .{ word, pins.headers[index], next, word, unpinned_mask, next, pins.headers[index], label });
            }
        }
    };
}

fn refineRcLoops(comptime E: type, self: *E, state: *State) Error!void {
    if (!try @import("qbe_rc_hoist.zig").refine(E, self)) return;
    @memset(state.captures, .{});
    prepareScopes(E, self, state);
}

/// The emitter reads place parents and saved keys after their final bytecode
/// use. Include those reads before move, borrow and GC-root planning.
fn retainPlaces(comptime E: type, self: *E, plan: cow_plan.Plan) bool {
    const live = self.live orelse return false;
    var changed = false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (!plan.at(place.fill).fill) continue;
        changed = retainPlace(E, self, live, place, place.fill) or changed;
        if (!scopePlace(E, self, place)) continue;
        var local: usize = place.parent;
        var guard: usize = 0;
        while (guard < self.function.scope.locals.len) : (guard += 1) {
            const ancestor = plan.place(local) orelse break;
            changed = retainPlace(E, self, live, ancestor, place.fill) or changed;
            local = ancestor.parent;
        }
    };
    return changed;
}

fn retainPlace(comptime E: type, self: *E, live: @import("qbe_liveness.zig").Solution, place: cow_plan.Place, end: usize) bool {
    var changed = false;
    const key = cow_plan.entryKey(place, self.ownership.?.operands);
    // An element-address borrow was proved only over the original bytecode
    // uses. An implicit COW read/allocation needs stable copied storage.
    if (self.by_reference[place.parent] == .element) @constCast(self.by_reference)[place.parent] = .none;
    if (key) |local| if (self.by_reference[local] == .element) {
        @constCast(self.by_reference)[local] = .none;
    };
    for (place.base + 1..end + 1) |pc| {
        changed = retainLocal(live, pc, place.parent) or changed;
        if (key) |local| changed = retainLocal(live, pc, local) or changed;
    }
    return changed;
}

fn retainLocal(live: @import("qbe_liveness.zig").Solution, pc: usize, local: usize) bool {
    const at = pc * live.words + local / 64;
    const bit = @as(usize, 1) << @intCast(local % 64);
    const changed = live.live_in[at] & live.live_out[at] & bit == 0;
    @constCast(live.live_in)[at] |= bit;
    @constCast(live.live_out)[at] |= bit;
    return changed;
}

const Callee = union(enum) {
    direct: bytecode.Function,
    indirect: typed.Callable,

    fn count(self: Callee) usize {
        return switch (self) {
            .direct => |function| function.signature.parameter_count,
            .indirect => |signature| signature.parameters.len,
        };
    }
    fn valueCount(self: Callee) usize {
        return switch (self) {
            .direct => |function| bytecode.valueParameterCount(function),
            .indirect => |signature| signature.valueCount(),
        };
    }
    fn parameter(self: Callee, position: usize) typed.Type {
        return switch (self) {
            .direct => |function| function.scope.locals[position].ty,
            .indirect => |signature| signature.parameters[position],
        };
    }
    fn writes(self: Callee, position: usize) bool {
        return switch (self) {
            .direct => |function| writesParameter(function, position),
            .indirect => |signature| std.mem.indexOfScalar(u16, signature.mutates, @intCast(position)) != null,
        };
    }
};

fn pinCall(comptime E: type, self: *E, callee: Callee, args: []usize, base: usize) Error!Pins {
    if (runtime_mode.enabled()) return pinCallRc(E, self, callee, args, base);
    var pins: Pins = .{};
    var owners: [8]u32 = @splat(cow_plan.none);
    var positions: [8]usize = undefined;
    const state = self.cow orelse return pins;
    for (args, 0..) |*arg, position| {
        if (position >= callee.count()) break;
        if (!callee.writes(position)) continue;
        if (!cow_plan.payloadType(self.program, callee.parameter(position))) continue;
        // A later read-only argument can have shared this same root
        // after its earlier mut-argument load was checked. Resolve
        // that new sharing before pinning and calling the callee.
        const operands = self.ownership.?.operands[self.pc] orelse return error.InternalError;
        const source = operands[base + position];
        if (pins.len == pins.headers.len) return error.InternalError;
        var repeated: ?usize = null;
        if (source.origin == .local and source.part == .whole) for (owners[0..pins.len], 0..) |owner, index| {
            if (owner == source.local) {
                repeated = positions[index];
                break;
            }
        };
        if (repeated) |previous|
            try reuseMutArgument(E, self, arg, args[previous], base + position)
        else
            try prepareMutArgument(E, self, arg, source, base + position);
        owners[pins.len] = if (source.origin == .local and source.part == .whole) source.local else cow_plan.none;
        positions[pins.len] = position;
        if (state.counting) try tally(E, self, .pin);
        const mark = try pinPayload(E, self, arg.*);
        pins.headers[pins.len] = mark.header;
        pins.olds[pins.len] = mark.old;
        pins.len += 1;
    }
    return pins;
}

fn pinCallRc(comptime E: type, self: *E, callee: Callee, args: []usize, base: usize) Error!Pins {
    var pins: Pins = .{};
    if (self.cow == null) return pins;
    for (args, 0..) |*arg, position| {
        if (position >= callee.count()) break;
        if (!callee.writes(position)) continue;
        if (!cow_plan.payloadType(self.program, callee.parameter(position))) continue;
        if (pins.len == 0) {
            pins.headers[0] = try rc_scope.callAddress(E, self);
            try rc_scope.begin(E, self, pins.headers[0]);
            pins.len = 1;
        }
        const operands = self.ownership.?.operands[self.pc] orelse return error.InternalError;
        try prepareMutArgument(E, self, arg, operands[base + position], base + position);
        try rc_scope.pin(E, self, pins.headers[0], arg.*);
    }
    return pins;
}

fn prepareMutArgumentRc(comptime E: type, self: *E, arg: *usize, source: @import("ownership.zig").Source, slot: usize) Error!void {
    try rc_values.drop(E, self, slot);
    if (source.part == .whole) {
        const root = rc_unique.receiverParent(E, self, source.local) orelse source.local;
        try rc_unique.local(E, self, .{ .local = root, .alias = if (root != source.local) source.local else cow_plan.none });
        const current = try self.load("l", source.local);
        try self.store(slot, current);
    } else {
        if (source.read == cow_plan.none) return error.InternalError;
        var end = source.read + 1;
        while (end < self.pc) : (end += 1) switch (self.function.scope.instructions[end].op) {
            .get_field, .wrap_domain, .unwrap_domain => {},
            else => break,
        };
        const cursor = try fieldChainRange(E, self, source.read + 1, end, try fieldBase(E, self, source.local), .published);
        const types = self.states[self.pc] orelse return error.InternalError;
        try rc_unique.field(E, self, .{ .ty = types[slot], .address = cursor.address, .container = cursor.cell orelse cursor.holder, .held = cursor.held });
        try self.store(slot, try self.load("v", cursor.address));
    }
    arg.* = try self.load("s", slot);
}

fn reuseMutArgument(comptime E: type, self: *E, arg: *usize, previous: usize, slot: usize) Error!void {
    try self.print(store_operand, .{ previous, slot });
    arg.* = try self.load("s", slot);
}

/// A later snapshot can share a mut operand after the load's first uniqueness
/// check. The call already published roots, so this copy must use them rather
/// than pushing the same frames again and making their next links cyclic.
fn prepareMutArgument(comptime E: type, self: *E, arg: *usize, source: @import("ownership.zig").Source, slot: usize) Error!void {
    if (source.origin != .local or source.local >= self.function.scope.locals.len or
        (source.part != .whole and source.part != .field)) return;
    if (runtime_mode.enabled()) return prepareMutArgumentRc(E, self, arg, source, slot);
    const label = self.temp();
    if (source.part == .whole) {
        try testShared(E, self, arg.*, label);
        const copy = self.temp();
        try self.print(unique_call, .{ copy, arg.* });
        try self.require(copy, format.allocation_failure);
        try self.print(store_local, .{ copy, source.local });
        try self.print(store_operand, .{ copy, slot });
    } else {
        if (source.read == cow_plan.none) return error.InternalError;
        var end = source.read + 1;
        while (end < self.pc) : (end += 1) switch (self.function.scope.instructions[end].op) {
            .get_field, .wrap_domain, .unwrap_domain => {},
            else => break,
        };
        const cursor = try fieldChainRange(E, self, source.read + 1, end, try fieldBase(E, self, source.local), .published);
        // Detachment can share an old direct child or replace a pinned one in
        // the new body. Reload the current child before checking uniqueness.
        // The unique copy then lives in an SSA temporary only until its store,
        // with no allocating operation between them.
        const current = try self.load("v", cursor.address);
        try self.print(store_operand, .{ current, slot });
        try testShared(E, self, current, label);
        const copy = self.temp();
        if (cursor.cell orelse cursor.holder) |held| {
            try self.print(" %v{d} =l call $myl_native_cow_unique_in(l %heap, l %v{d}, l %v{d})\n", .{ copy, current, held });
        } else try self.print(unique_call, .{ copy, current });
        try self.require(copy, format.allocation_failure);
        if (cursor.cell) |body| try qbe_alloc.barrier(*E, self, body);
        try self.print(store_pointer, .{ copy, cursor.address });
        try self.print(store_operand, .{ copy, slot });
    }
    try self.print(cow_keep_label, .{label});
    arg.* = try self.load("s", slot);
}

const PinMark = struct { header: usize, old: usize };
fn pinPayload(comptime E: type, self: *E, arg: usize) Error!PinMark {
    const header = self.temp();
    const word = self.temp();
    const old = self.temp();
    const next = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ header, arg, header_bytes, word, header });
    try self.print(" %v{d} =l and %v{d}, {d}\n %v{d} =l or %v{d}, {d}\n storel %v{d}, %v{d}\n", .{ old, word, pinned_flag, next, word, pinned_flag, next, header });
    try self.print(" %v{d} =l cnel %v{d}, 0\n", .{ old, old });
    return .{ .header = header, .old = old };
}

/// Whether `function`'s body may write parameter `position` in place.
fn writesParameter(function: bytecode.Function, position: usize) bool {
    for (function.signature.declared_mutates) |p| if (p == position) return true;
    for (function.signature.mutates) |p| if (p == position) return true;
    return false;
}

fn tally(comptime E: type, self: *E, kind: Tally) Error!void {
    try self.print(" call $myl_native_cow_tally(w {d})\n", .{@backingInt(kind)});
}

/// Test the shared flag of the payload in `value`: jump to the copy block
/// `@cowcopy<label>` when it is set, else past it to `@cowkeep<label>`.
fn testShared(comptime E: type, self: *E, value: usize, label: usize) Error!void {
    const state = self.cow.?;
    if (state.counting) try tally(E, self, .check);
    const header = self.temp();
    const word = self.temp();
    const flag = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n %v{d} =l loadl %v{d}\n %v{d} =l shr %v{d}, 61\n %v{d} =l and %v{d}, 1\n", .{ header, value, header_bytes, word, header, flag, word, flag, flag });
    try self.print(" jnz %v{d}, @cowcopy{d}, @cowkeep{d}\n@cowcopy{d}\n", .{ flag, label, label, label });
}

/// Call the runtime's copy under the root protocol and answer the copy.
/// `container` names a temporary whose payload the runtime keeps alive
/// through the copy, or is null.
fn copyCall(comptime E: type, self: *E, value: usize, container: ?usize, stack: []const typed.Type) Error!usize {
    const pushed = try self.roots(stack);
    const copy = self.temp();
    if (container) |held| {
        try self.print(" %v{d} =l call $myl_native_cow_unique_in(l %heap, l %v{d}, l %v{d})\n", .{ copy, value, held });
    } else try self.print(unique_call, .{ copy, value });
    if (pushed) try self.restoreRoots();
    try self.require(copy, format.allocation_failure);
    return copy;
}

/// Make local `unique.local`'s payload unique: copy it when it is shared and
/// store the copy into its slot and its alias's.
fn uniqueLocal(comptime E: type, self: *E, unique: cow_plan.Unique, stack: []const typed.Type) Error!void {
    if (runtime_mode.enabled()) return rc_unique.local(E, self, unique);
    const label = self.temp();
    const value = try self.load("l", unique.local);
    try testShared(E, self, value, label);
    const copy = try copyCall(E, self, value, null, stack);
    try self.print(store_local, .{ copy, unique.local });
    if (unique.alias != cow_plan.none) try self.print(store_local, .{ copy, unique.alias });
    try self.print(cow_keep_label, .{label});
}

/// Clone a dictionary stored through record fields before reading an entry
/// for a nested write; the clone marks held values shared.
fn uniqueField(comptime E: type, self: *E, place: cow_plan.Place, stack: []const typed.Type) Error!void {
    const cursor = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent), .detach);
    if (runtime_mode.enabled()) {
        const types = self.states[place.fields_end] orelse return error.InternalError;
        return rc_unique.field(E, self, .{ .ty = types[types.len - 1], .address = cursor.address, .container = cursor.cell orelse cursor.holder, .held = cursor.held });
    }
    const value = try self.load("v", cursor.address);
    const label = self.temp();
    try testShared(E, self, value, label);
    const copy = try copyCall(E, self, value, cursor.cell, stack);
    if (cursor.cell) |body| try qbe_alloc.barrier(*E, self, body);
    try self.print(store_pointer, .{ copy, cursor.address });
    try self.print(cow_keep_label, .{label});
}

/// Make every element of list local `local` unique where it lives.
fn uniqueElements(comptime E: type, self: *E, local: u32, stack: []const typed.Type) Error!void {
    const list = try self.load("l", local);
    if (runtime_mode.enabled()) {
        const done = self.temp();
        const ty = self.function.scope.locals[local].ty;
        try self.print(" %v{d} =w call $myl_qbe_rc_unique_elements(l %ctx, l extern ${s}, l %v{d})\n", .{ done, try self.descriptor(ty), list });
        return rc_unique.success(E, self, done);
    }
    const pushed = try self.roots(stack);
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_native_cow_elements(l %heap, l %v{d})\n", .{ done, list });
    if (pushed) try self.restoreRoots();
    try self.require(done, format.allocation_failure);
}

/// Keep the index an element place's base read takes, which the read itself
/// consumes, for the fill's write-back.
fn capture(comptime E: type, self: *E, state: *State, pc: usize, stack: []const typed.Type) Error!void {
    if (stack.len == 0) return error.InternalError;
    const op = self.function.scope.instructions[pc].op;
    state.captures[pc].index = if (op == .get_index)
        try captureArrayIndex(E, self, op.get_index, stack)
    else
        try self.load("s", stack.len - 1);
}

/// Keep the checked read's effective index, including a negative index or
/// enum-table key, without evaluating its expression a second time.
fn captureArrayIndex(comptime E: type, self: *E, access: bytecode.Access, stack: []const typed.Type) Error!usize {
    const raw = try self.load("s", stack.len - 1);
    const ty = stack[stack.len - 1];
    if (!self.isScalar(ty)) {
        const tag = self.temp();
        try self.print(" %v{d} =l loaduw %v{d}\n", .{ tag, raw });
        return tag;
    }
    const signed = if (ty.integer()) |info| info.signed else false;
    if (!access.from_end or !signed) return raw;
    const mask = self.temp();
    const correction = self.temp();
    const index = self.temp();
    try self.print(" %v{d} =l sar %v{d}, 63\n %v{d} =l and %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ mask, raw, correction, mask, (try self.layout(access.ty)).count, index, raw, correction });
    return index;
}

/// The place local `index` fills at the current instruction.
fn filledPlace(comptime E: type, self: *E, pc: usize) Error!struct { local: u32, place: cow_plan.Place } {
    const state = self.cow.?;
    const slot = switch (self.function.scope.instructions[pc].op) {
        .store_local => |target| @backingInt(target),
        else => return error.InternalError,
    };
    const place = state.plan.place(slot) orelse return error.InternalError;
    return .{ .local = @intCast(slot), .place = place };
}

/// Where a place's value lives while its write-back address is computed: the
/// temporary holding that address, the `class` or detached box body it lies
/// in, and an outer list/dictionary keeping an element address alive.
const Cursor = struct { address: usize, cell: ?usize, holder: ?usize = null, held: bool = false };

/// Make the value a place's fill stores unique: copy it when it is shared,
/// write the copy back into the place it was read from, and store the copy.
/// The place's container is kept alive through the copy, because the local
/// that named it may be dead by now.
fn fillPlace(comptime E: type, self: *E, pc: usize, stack: []const typed.Type) Error!void {
    if (stack.len == 0) return error.InternalError;
    const place = (try filledPlace(E, self, pc)).place;
    if (scopePlace(E, self, place)) {
        if (runtime_mode.enabled() or scopeEnd(E, self, place) != place.fill) return;
        try releaseScope(E, self, place);
        return scopeRootStore(E, self, activeScope(E, self, pc, place.fill));
    }
    const top = stack.len - 1;
    const label = self.temp();
    var value = try self.load("s", top);
    const box_path = placeHasBox(E, self, place);
    if (!box_path and !runtime_mode.enabled()) try testShared(E, self, value, label);
    var container: ?usize = null;
    var cursor: Cursor = switch (place.step) {
        .element => element: {
            const list = try self.load("l", place.parent);
            container = list;
            break :element .{ .address = try elementSlot(E, self, place, list), .cell = null, .holder = list };
        },
        .entry => entry: {
            const dictionary = try self.load("l", place.parent);
            container = dictionary;
            const slot = try entrySlot(E, self, place, dictionary);
            break :entry .{ .address = slot, .cell = null, .holder = dictionary };
        },
        .entry_field => entry: {
            const cursor_field = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent), .detach);
            const dictionary = try self.load("v", cursor_field.address);
            container = dictionary;
            const slot = try entrySlot(E, self, place, dictionary);
            break :entry .{ .address = slot, .cell = null, .holder = dictionary };
        },
        .field => try fieldBase(E, self, place.parent),
    };
    if (runtime_mode.enabled()) try rc_values.drop(E, self, top);
    cursor = try fieldChain(E, self, place, cursor);
    if (runtime_mode.enabled()) {
        try rc_unique.field(E, self, .{ .ty = stack[top], .address = cursor.address, .container = cursor.cell orelse container, .held = cursor.held });
        return self.store(top, try self.load("v", cursor.address));
    }
    if (box_path) {
        // Detaching a box shares its old direct child (or replaces a pinned
        // one), so the operand read before the detachment is stale. Test and
        // mutate the child now held by the detached path.
        value = try self.load("v", cursor.address);
        try self.store(top, value);
        try testShared(E, self, value, label);
    }
    const copy = try copyCall(E, self, value, cursor.cell orelse container, stack);
    if (cursor.cell) |body| try qbe_alloc.barrier(*E, self, body);
    try self.print(store_pointer, .{ copy, cursor.address });
    if (place.box) |box| {
        const owner_type = self.function.scope.locals[box.owner].ty;
        if ((try self.layout(owner_type)).size != 8) return error.InternalError;
        const old = self.temp();
        const new = self.temp();
        const body = (try fieldBase(E, self, place.parent)).address;
        try self.print(" %v{d} =l loadl %l{d}\n", .{ old, box.owner });
        try self.print(" %v{d} =l call $myl_native_cow_rebox(l %heap, l extern ${s}, l %v{d}, l %v{d})\n", .{ new, try self.descriptor(box.ty), old, body });
        try self.require(new, format.allocation_failure);
        try self.print(store_local, .{ new, box.owner });
    }
    try self.store(top, copy);
    try self.print(cow_keep_label, .{label});
}

fn placeHasArray(comptime E: type, self: *const E, place: cow_plan.Place) bool {
    const begin = chainBegin(place);
    const first = self.states[begin] orelse return false;
    for (begin..place.fill) |pc| {
        const operands = self.states[pc] orelse continue;
        const op = self.function.scope.instructions[pc].op;
        if (op == .get_index and operands.len == first.len + 1 and self.cow.?.plan.at(pc).capture) return true;
    }
    return false;
}

/// Pinning is needed only when a callback can replace the already-evaluated
/// inline aggregate before its leaf receiver is filled.
fn clearScopesImpl(comptime E: type, self: *E) Error!void {
    if (runtime_mode.enabled()) return;
    const state = self.cow orelse return;
    if (Lower(E).scopeBytes(self) == 0) return;
    var pc = state.captures.len;
    while (pc != 0) {
        pc -= 1;
        const beginning = state.captures[pc].begin;
        if (beginning != cow_plan.none) try releaseScope(E, self, state.plan.places[beginning].?);
    }
    try scopeRootStore(E, self, null);
}

fn pathStep(comptime E: type, self: *const E, place: cow_plan.Place, pc: usize) bool {
    const stack = self.states[pc] orelse return false;
    const depth = (self.states[chainBegin(place)] orelse return false).len;
    return switch (self.function.scope.instructions[pc].op) {
        .get_field => stack.len == depth,
        .get_index => stack.len == depth + 1 and self.cow.?.plan.at(pc).capture,
        else => false,
    };
}

fn scopeStorageBytes(comptime E: type, self: *const E, place: cow_plan.Place) usize {
    var count: usize = 0;
    const first = chainBegin(place);
    for (first..place.fill) |pc| if (pathStep(E, self, place, pc)) {
        count += 1;
    };
    return 32 + count * 16;
}

const Projection = struct { address: usize, count: usize };
fn scopePath(comptime E: type, self: *E, place: cow_plan.Place) Error!Projection {
    const first = chainBegin(place);
    const path = self.temp();
    try self.print(" %v{d} =l add %cowscope{d}, 32\n", .{ path, place.fill });
    var count: usize = 0;
    for (first..place.fill) |pc| {
        if (!pathStep(E, self, place, pc)) continue;
        const op = self.function.scope.instructions[pc].op;
        const stack = self.states[pc].?;
        const ty = if (op == .get_index) op.get_index.ty else stack[stack.len - 1];
        const offset = if (op == .get_field) (try self.field(ty, op.get_field)).offset else 0;
        const at = try self.address(path, count * 16);
        const position = try self.address(at, 8);
        try self.print(" storel extern ${s}, %v{d}\n storel {d}, %v{d}\n", .{ try self.descriptor(ty), at, offset, position });
        count += 1;
    }
    return .{ .address = path, .count = count };
}

fn prepareScopes(comptime E: type, self: *E, state: *State) void {
    for (state.plan.places, 0..) |maybe, local| {
        const place = maybe orelse continue;
        if (!needsScope(E, self, place)) continue;
        const start = scopeStart(place);
        state.captures[start].begin = @intCast(local);
        for (start + 1..scopeEnd(E, self, place) + 1) |pc| {
            const previous = state.captures[pc].active;
            if (previous == cow_plan.none or scopeStart(state.plan.places[previous].?) < start) state.captures[pc].active = @intCast(local);
        }
    }
}

fn scopePlace(comptime E: type, self: *const E, place: cow_plan.Place) bool {
    const state = self.cow.?;
    const local = state.captures[scopeStart(place)].begin;
    return local != cow_plan.none and state.plan.places[local].?.fill == place.fill;
}

fn needsScope(comptime E: type, self: *const E, place: cow_plan.Place) bool {
    if (!self.cow.?.plan.at(place.fill).fill) return false;
    const end = scopeEnd(E, self, place);
    if (end != place.fill) switch (self.function.scope.instructions[end].op) {
        .call, .invoke => return true,
        else => {},
    };
    if (end == place.fill and !placeHasArray(E, self, place)) return false;
    for (scopeStart(place) + 1..end) |pc| switch (self.function.scope.instructions[pc].op) {
        .call, .invoke => return true,
        else => {},
    };
    return false;
}

// A source receiver remains selected while later arguments run callbacks.
// The single-assignment place local identifies the consuming mutation without
// extending unrelated projections beyond their existing fill-time scope.
fn scopeEnd(comptime E: type, self: *const E, place: cow_plan.Place) usize {
    if (runtime_mode.enabled()) return place.fill;
    const code = self.function.scope.instructions;
    const target = switch (code[place.fill].op) {
        .store_local => |local| local,
        else => return place.fill,
    };
    for (code[place.fill + 1 ..], place.fill + 1..) |instruction, pc| {
        if (mutArgumentLocal(E, self, pc, @backingInt(target))) return pc;
        if (instruction.op != .buffer_operation) continue;
        const operation = instruction.op.buffer_operation;
        if (operation.owner == target and (operation.kind.writesReceiver() or
            operation.kind == .set_add or operation.kind == .set_discard)) return pc;
    }
    return place.fill;
}

fn finishGcScopes(comptime E: type, self: *E, pc: usize) Error!void {
    if (runtime_mode.enabled()) return;
    const state = self.cow orelse return;
    switch (self.function.scope.instructions[pc].op) {
        .call, .invoke => {},
        .buffer_operation => |operation| if (!operation.kind.writesReceiver() and operation.kind != .set_add and operation.kind != .set_discard) return,
        else => return,
    }
    var next: ?usize = null;
    var closed = false;
    var at = @min(pc + 1, state.captures.len);
    while (at != 0) {
        at -= 1;
        const local = state.captures[at].begin;
        if (local == cow_plan.none) continue;
        const place = state.plan.places[local].?;
        const end = scopeEnd(E, self, place);
        if (end == pc and end != place.fill) {
            try releaseScope(E, self, place);
            closed = true;
        } else if (end > pc and next == null) next = place.fill;
    }
    if (closed) try scopeRootStore(E, self, next);
}

/// A hidden argument place remains selected until its consuming call.
fn mutArgumentLocal(comptime E: type, self: *const E, pc: usize, local: usize) bool {
    const callee: Callee = switch (self.function.scope.instructions[pc].op) {
        .call => |target| .{ .direct = self.program.functions[@backingInt(target)] },
        .invoke => |ty| .{ .indirect = self.program.records[ty.recordIndex()].contract.callback.? },
        else => return false,
    };
    const operands = self.ownership.?.operands[pc] orelse return false;
    const base = operands.len - callee.valueCount();
    for (0..callee.count()) |position| {
        if (!callee.writes(position)) continue;
        const source = operands[base + position];
        if (source.origin == .local and source.part == .whole and source.local == local) return true;
    }
    return false;
}

/// Close the lifetime loan after the call's result has been published.
fn finishCallReceivers(comptime E: type, self: *E, pc: usize) Error!void {
    if (!runtime_mode.enabled()) return;
    switch (self.function.scope.instructions[pc].op) {
        .call, .invoke => {},
        else => return,
    }
    const state = self.cow orelse return;
    var at = pc;
    while (at != 0) {
        at -= 1;
        const local = switch (self.function.scope.instructions[at].op) {
            .store_local => |local| @backingInt(local),
            else => continue,
        };
        if (state.plan.place(local) != null and mutArgumentLocal(E, self, pc, local)) try finishReceiverImpl(E, self, local);
    }
}

fn scopeStart(place: cow_plan.Place) usize {
    return if (place.step == .entry_field) place.read else place.base;
}

fn activeScope(comptime E: type, self: *const E, pc: usize, excluded: ?usize) ?usize {
    const state = self.cow orelse return null;
    if (pc >= state.captures.len) return null;
    var local = state.captures[pc].active;
    if (local == cow_plan.none) return null;
    const place = state.plan.places[local].?;
    if (excluded == place.fill) local = state.captures[scopeStart(place)].active;
    return if (local == cow_plan.none) null else state.plan.places[local].?.fill;
}

fn scopeRootStore(comptime E: type, self: *E, root: ?usize) Error!void {
    if (runtime_mode.enabled()) return;
    const head = self.temp();
    try self.print(" %v{d} =l add %heap, 16\n", .{head});
    if (root) |fill| try self.print(" storel %cowscope{d}, %v{d}\n", .{ fill, head }) else try self.print(" storel %root_mark, %v{d}\n", .{head});
}

fn releaseScope(comptime E: type, self: *E, place: cow_plan.Place) Error!void {
    if (runtime_mode.enabled()) return rc_scope.end(E, self, try rc_scope.receiverAddress(E, self, place.fill));
    const address = self.temp();
    const pins = self.temp();
    try self.print(" %v{d} =l add %cowscope{d}, 24\n %v{d} =l loadl %v{d}\n call $myl_native_cow_scope_release(l %v{d})\n storel 0, %v{d}\n", .{ address, place.fill, pins, address, pins, address });
}

fn beginScope(comptime E: type, self: *E, place: cow_plan.Place, stack: []const typed.Type) Error!void {
    const previous = self.temp();
    const head = self.temp();
    const address = self.temp();
    const descriptor = self.temp();
    const pins = self.temp();
    if (runtime_mode.enabled()) {
        try self.print(" %v{d} =l copy %cowscope{d}\n", .{ pins, place.fill });
        try rc_scope.begin(E, self, pins);
    } else {
        try self.print(" %v{d} =l add %heap, 16\n %v{d} =l loadl %v{d}\n storel %v{d}, %cowscope{d}\n", .{ head, previous, head, previous, place.fill });
        try self.print(" %v{d} =l add %cowscope{d}, 8\n %v{d} =l add %cowscope{d}, 16\n %v{d} =l add %cowscope{d}, 24\n", .{ address, place.fill, descriptor, place.fill, pins, place.fill });
        try self.print(" storel %v{d}, %v{d}\n storel extern $myl_native_cow_scope_type, %v{d}\n storel %cowscope{d}, %v{d}\n", .{ pins, address, descriptor, place.fill, head });
        _ = try self.roots(stack);
    }
    try pinAncestors(E, self, place, pins);
    const cursor: Cursor = switch (place.step) {
        .element => element: {
            const list = try self.load("l", place.parent);
            break :element .{ .address = try elementSlot(E, self, place, list), .cell = null, .holder = list };
        },
        .entry => entry: {
            const dictionary = try self.load("l", place.parent);
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null, .holder = dictionary };
        },
        .entry_field => entry: {
            const field = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent), .published);
            const dictionary = try self.load("v", field.address);
            try scopePin(E, self, pins, dictionary);
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null, .holder = dictionary };
        },
        .field => try fieldBase(E, self, place.parent),
    };
    if (place.step == .element) {
        const length = try self.load("v", cursor.holder.?);
        const present = self.temp();
        try self.print(" %v{d} =w cultl %v{d}, %v{d}\n jnz %v{d}, @cowvalid{d}, @cowempty{d}\n@cowvalid{d}\n", .{ present, self.cow.?.captures[place.base].index, length, present, place.fill, place.fill, place.fill });
    } else if (place.step != .field) {
        try self.print(" jnz %v{d}, @cowvalid{d}, @cowempty{d}\n@cowvalid{d}\n", .{ cursor.address, place.fill, place.fill, place.fill });
    }
    const path = try scopePath(E, self, place);
    const done = self.temp();
    if (runtime_mode.enabled()) {
        try rc_scope.prepare(E, self, .{ .scope = pins, .address = cursor.address, .container = cursor.cell orelse cursor.holder, .path = path.address, .count = path.count });
    } else {
        try self.print(" %v{d} =w call $myl_native_cow_scope_prepare(l %heap, l %v{d}, l %v{d}, l %v{d}, l {d})\n", .{ done, pins, cursor.address, path.address, path.count });
        if (cursor.cell) |body| try qbe_alloc.barrier(*E, self, body);
        try self.require(done, format.allocation_failure);
    }
    if (place.step != .field) try self.print("@cowempty{d}\n", .{place.fill});
    try scopeRootStore(E, self, place.fill);
}

fn scopePin(comptime E: type, self: *E, pins: usize, payload: usize) Error!void {
    if (runtime_mode.enabled()) return rc_scope.pin(E, self, pins, payload);
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_native_cow_scope_pin(l %heap, l %v{d}, l %v{d})\n", .{ done, pins, payload });
    try self.require(done, format.allocation_failure);
}

fn pinAncestors(comptime E: type, self: *E, place: cow_plan.Place, pins: usize) Error!void {
    var local: usize = place.parent;
    var guard: usize = 0;
    while (guard < self.function.scope.locals.len) : (guard += 1) {
        if (cow_plan.payloadType(self.program, self.function.scope.locals[local].ty)) try scopePin(E, self, pins, try self.load("l", local));
        const ancestor = self.cow.?.plan.place(local) orelse break;
        if (placeHasBox(E, self, ancestor) or ancestor.step == .entry_field) try pinAncestorBoxes(E, self, ancestor, pins);
        local = ancestor.parent;
    }
}

fn pinAncestorBoxes(comptime E: type, self: *E, place: cow_plan.Place, pins: usize) Error!void {
    const cursor: Cursor = switch (place.step) {
        .element => element: {
            const list = try self.load("l", place.parent);
            break :element .{ .address = try elementSlot(E, self, place, list), .cell = null, .holder = list };
        },
        .entry => entry: {
            const dictionary = try self.load("l", place.parent);
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null, .holder = dictionary };
        },
        .entry_field => entry: {
            const field = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent), .{ .pin = pins });
            const dictionary = try self.load("v", field.address);
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null, .holder = dictionary };
        },
        .field => try fieldBase(E, self, place.parent),
    };
    _ = try fieldChainRange(E, self, chainBegin(place), place.fill, cursor, .{ .pin = pins });
}

fn firstArray(comptime E: type, self: *const E, place: cow_plan.Place) ?usize {
    const begin = chainBegin(place);
    const first = self.states[begin] orelse return null;
    for (begin..place.fill) |pc| {
        const operands = self.states[pc] orelse continue;
        const op = self.function.scope.instructions[pc].op;
        if (op == .get_index and operands.len == first.len + 1 and self.cow.?.plan.at(pc).capture) return pc;
    }
    return null;
}

fn placeHasBox(comptime E: type, self: *E, place: cow_plan.Place) bool {
    const begin = chainBegin(place);
    const first = self.states[begin] orelse return false;
    for (begin..place.fill) |pc| {
        if (self.function.scope.instructions[pc].op != .get_field) continue;
        const operands = self.states[pc] orelse continue;
        if (operands.len != first.len) continue;
        const source = operands[operands.len - 1];
        if (self.program.records[source.recordIndex()].collection.box) return true;
    }
    return false;
}

/// The address of the element a place's base read took, in its list's
/// storage, from the index the read captured.
fn elementSlot(comptime E: type, self: *E, place: cow_plan.Place, list: usize) Error!usize {
    const storage = try self.load("v", try self.address(list, format.list_storage_offset));
    const schema = self.program.records[self.function.scope.locals[place.parent].ty.recordIndex()];
    const element = schema.shape.buffer orelse return error.InternalError;
    const stride = (try self.layout(element)).size;
    const offset = self.temp();
    const slot = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, self.cow.?.captures[place.base].index, stride, slot, storage, offset });
    return slot;
}

/// The address of the value a place's base read looked up, found again with
/// the key its operand slot still holds: no instruction between the read and
/// the fill writes that slot. A described slice key (`DICT-RANGE-KEY-1`) is
/// looked up by its span.
fn entrySlot(comptime E: type, self: *E, place: cow_plan.Place, dictionary: usize) Error!usize {
    const read = if (place.step == .entry_field) place.read else place.base;
    if (cow_plan.entryKey(place, self.ownership.?.operands)) |local| {
        const slot = self.temp();
        if (local < self.range_keys.locals.len and self.range_keys.locals[local]) {
            const text = try self.load("l", local);
            try self.print(" %v{d} =l call $myl_native_dictionary_find_range(l %heap, l %v{d}, l %v{d}, l %rl{d})\n", .{ slot, dictionary, text, local });
            return slot;
        }
        const key = (try fieldBase(E, self, @intCast(local))).address;
        try self.print(" %v{d} =l call $myl_native_dictionary_find(l %v{d}, l %v{d})\n", .{ slot, dictionary, key });
        return slot;
    }
    return lookupSlot(E, self, read, dictionary);
}

fn lookupSlot(comptime E: type, self: *E, read: usize, dictionary: usize) Error!usize {
    const operands = self.states[read] orelse return error.InternalError;
    if (operands.len < 2) return error.InternalError;
    const key_slot = operands.len - 1;
    const slot = self.temp();
    if (self.range_keys.role(read) == .key) {
        const text = try self.load("s", key_slot);
        try self.print(" %v{d} =l call $myl_native_dictionary_find_range(l %heap, l %v{d}, l %v{d}, l %rs{d})\n", .{ slot, dictionary, text, key_slot });
        return slot;
    }
    const key = self.temp();
    if (self.isScalar(operands[key_slot])) try self.print(" %v{d} =l copy %s{d}\n", .{ key, key_slot }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ key, key_slot });
    try self.print(" %v{d} =l call $myl_native_dictionary_find(l %v{d}, l %v{d})\n", .{ slot, dictionary, key });
    return slot;
}

/// Where local `parent`'s value lives: its own slot, or the caller's storage
/// a `mut` or read-only aggregate parameter names.
fn fieldBase(comptime E: type, self: *E, parent: u32) Error!Cursor {
    const address = self.temp();
    if (self.byReference(parent) or self.callerStorage(parent)) {
        try self.print(" %v{d} =l loadl %l{d}\n", .{ address, parent });
    } else try self.print(" %v{d} =l copy %l{d}\n", .{ address, self.moves.resolve(parent) });
    return .{ .address = address, .cell = null };
}

/// Follow the field reads between a place's base read and its fill: a field
/// of an inline record lies inside the value, one of a `class` inside the
/// body its reference names.
fn fieldChain(comptime E: type, self: *E, place: cow_plan.Place, start: Cursor) Error!Cursor {
    return fieldChainRange(E, self, chainBegin(place), place.fill, start, .detach);
}

fn chainBegin(place: cow_plan.Place) usize {
    return (if (place.step == .entry_field) place.read else place.base) + 1;
}

const Walk = union(enum) { detach, published, read, pin: usize };

fn fieldChainRange(comptime E: type, self: *E, begin: usize, end: usize, start: Cursor, walk: Walk) Error!Cursor {
    var cursor = start;
    const depth = (self.states[begin] orelse return error.InternalError).len;
    for (begin..end) |pc| {
        const operands = self.states[pc] orelse continue;
        const op = self.function.scope.instructions[pc].op;
        if (op == .get_index and operands.len == depth + 1) {
            const array = try self.layout(op.get_index.ty);
            if (array.kind != .array) return error.InternalError;
            const offset = self.temp();
            const address = self.temp();
            try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, self.cow.?.captures[pc].index, array.stride, address, cursor.address, offset });
            cursor.address = address;
            continue;
        }
        if (operands.len != depth) continue;
        const index = switch (self.function.scope.instructions[pc].op) {
            .get_field => |field| field,
            .wrap_domain, .unwrap_domain => continue,
            else => continue,
        };
        const source = operands[operands.len - 1];
        const member = try self.field(source, index);
        if (self.program.records[source.recordIndex()].isManagedRecord()) {
            const body = try self.load("v", cursor.address);
            const boxed = self.program.records[source.recordIndex()].collection.box;
            if (walk == .pin and boxed) try scopePin(E, self, walk.pin, body);
            const detaching = walk == .detach or walk == .published;
            if (detaching and boxed and semantics.enabled()) {
                // A nested write must never target an immutable box's old
                // body. Detach each box on the path before descending; the
                // previous cursor then names either owned inline storage or
                // an ancestor box already detached by this walk.
                const copy = try detachBox(E, self, source, body, cursor, walk == .published);
                cursor = .{ .address = try self.address(copy, member.offset), .cell = copy };
            } else cursor = .{ .address = try self.address(body, member.offset), .cell = body };
        } else cursor.address = try self.address(cursor.address, member.offset);
        cursor.held = semantics.isLiveView(self.program.records, source);
    }
    return cursor;
}

fn detachBox(comptime E: type, self: *E, ty: typed.Type, body: usize, cursor: Cursor, roots_published: bool) Error!usize {
    if (runtime_mode.enabled()) {
        try rc_unique.field(E, self, .{ .ty = ty, .address = cursor.address, .container = cursor.cell orelse cursor.holder, .held = cursor.held });
        return self.load("v", cursor.address);
    }
    const pushed = if (roots_published) false else try self.roots(self.states[self.pc] orelse return error.InternalError);
    const copy = self.temp();
    const descriptor = try self.descriptor(ty);
    if (cursor.cell orelse cursor.holder) |parent| {
        try self.print(" %v{d} =l call $myl_native_cow_clone_box(l %heap, l extern ${s}, l %v{d}, l %v{d})\n", .{ copy, descriptor, body, parent });
    } else try self.print(" %v{d} =l call $myl_native_cow_clone_box(l %heap, l extern ${s}, l %v{d}, l 0)\n", .{ copy, descriptor, body });
    if (pushed) try self.restoreRoots();
    try self.require(copy, format.allocation_failure);
    if (cursor.cell) |parent| try qbe_alloc.barrier(*E, self, parent);
    try self.print(store_pointer, .{ copy, cursor.address });
    return copy;
}

fn readCaptures(comptime E: type, self: *E, stack: []const typed.Type, depths: []const u8) Error!void {
    for (depths) |depth| try readCapture(E, self, stack, depth);
}

/// Preserve a selected read receiver before evaluating a mutating key.
fn readCapture(comptime E: type, self: *E, stack: []const typed.Type, depth: u8) Error!void {
    if (!runtime_mode.enabled()) return share(E, self, stack, depth);
    const slot = stack.len - 1 - depth;
    try rc_values.prepareOperand(E, self, stack[slot], slot);
    try rc_values.publish(E, self, stack[slot], slot);
}

/// Share the payloads of the operand `depth` places below the top.
fn share(comptime E: type, self: *E, stack: []const typed.Type, depth: u8) Error!void {
    if (depth >= stack.len) return error.InternalError;
    const slot = stack.len - 1 - depth;
    const ty = stack[slot];
    if (cow_plan.payloadType(self.program, ty)) return sharePayload(E, self, .{ .value = try self.load("s", slot), .slot = slot }, stack);
    const value = try self.layout(ty);
    if (!value.trace or self.isScalar(ty)) return;
    var flat: Flat = .{};
    if (try flatten(E, self, ty, 0, &flat, false)) {
        const base = try self.load("s", slot);
        for (flat.offsets[0..flat.len]) |offset| {
            const address = try self.address(base, offset);
            try sharePayload(E, self, .{ .value = try self.load("v", address), .address = address }, stack);
        }
        return;
    }
    const pushed = try self.roots(stack);
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_native_cow_share_value(l %heap, l extern ${s}, l %v{d})\n", .{ done, try self.descriptor(ty), try self.load("s", slot) });
    if (pushed) try self.restoreRoots();
    try self.require(done, format.allocation_failure);
}

/// One payload being shared: the temporary holding it, and where a copy of a
/// pinned one goes — an operand slot, or an address inside the operand.
const Shared = struct { value: usize, slot: ?usize = null, address: ?usize = null };

/// Set the shared flag of one payload inline; a pinned one is copied instead
/// and the copy stored where the payload was.
fn sharePayload(comptime E: type, self: *E, payload: Shared, stack: []const typed.Type) Error!void {
    const state = self.cow.?;
    if (state.counting) try tally(E, self, .mark);
    const label = self.temp();
    const header = self.temp();
    const word = self.temp();
    const flag = self.temp();
    const next = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, {d}\n", .{ header, payload.value, header_bytes, word, header, flag, word, pinned_flag });
    try self.print(" %v{d} =l cnel %v{d}, 0\n jnz %v{d}, @sharecopy{d}, @sharemark{d}\n@sharecopy{d}\n", .{ flag, flag, flag, label, label, label });
    const pushed = try self.roots(stack);
    const copy = self.temp();
    try self.print(" %v{d} =l call $myl_native_cow_share(l %heap, l %v{d})\n", .{ copy, payload.value });
    if (pushed) try self.restoreRoots();
    try self.require(copy, format.allocation_failure);
    if (payload.slot) |slot| try self.store(slot, copy);
    if (payload.address) |address| try self.print(store_pointer, .{ copy, address });
    try self.print(" jmp @shared{d}\n@sharemark{d}\n %v{d} =l or %v{d}, {d}\n storel %v{d}, %v{d}\n@shared{d}\n", .{ label, label, next, word, shared_flag, next, header, label });
}

/// The most payload fields one aggregate's share is spelled out for.
const flat_limit = 8;
/// The payload fields of one aggregate, at their byte offsets.
pub const Flat = struct { offsets: [flat_limit]u64 = undefined, len: usize = 0 };

/// Static mutable leaves of a value transfer. A hidden recursive box needs
/// the runtime's descriptor walk, because the box body may hold collections.
pub fn valueLeaves(comptime E: type, self: *E, ty: typed.Type) Error!?Flat {
    var flat: Flat = .{};
    if (!try flatten(E, self, ty, 0, &flat, false)) return null;
    return flat;
}

/// Collect the offsets of every payload a value of `ty` at `base` holds
/// directly, or answer false for a shape the runtime must walk: a union, an
/// optional, more than `flat_limit` payloads.
fn flatten(comptime E: type, self: *E, ty: typed.Type, base: u64, flat: *Flat, trust_box: bool) Error!bool {
    const value = try self.layout(ty);
    if (!value.trace) return true;
    switch (value.kind) {
        .managed => {
            if (!trust_box and self.program.records[ty.recordIndex()].collection.box) return false;
            if (!cow_plan.payloadType(self.program, ty)) return true;
            if (flat.len == flat_limit) return false;
            flat.offsets[flat.len] = base;
            flat.len += 1;
            return true;
        },
        .record, .domain => {
            if (self.program.records[ty.recordIndex()].isManagedRecord()) return true;
            for (value.fields) |field| if (!try flatten(E, self, field.ty, base + field.offset, flat, trust_box)) return false;
            return true;
        },
        .array => {
            for (0..value.count) |i| if (!try flatten(E, self, value.fields[0].ty, base + i * value.stride, flat, trust_box)) return false;
            return true;
        },
        else => return false,
    }
}

fn finishReceiverImpl(comptime E: type, self: *E, owner: usize) Error!void {
    if (!runtime_mode.enabled()) return;
    const state = self.cow orelse return;
    var local = owner;
    var remaining = state.plan.places.len;
    while (remaining != 0) : (remaining -= 1) {
        if (state.plan.place(local)) |place| {
            if (!inert_receiver.proven(E, self, local)) try rc_scope.end(E, self, try rc_scope.borrowAddress(E, self, local));
            if (scopePlace(E, self, place)) try releaseScope(E, self, place);
            local = place.parent;
        } else if (local < state.plan.aliases.len and state.plan.aliases[local] != cow_plan.none) {
            if (!inert_receiver.proven(E, self, local)) try rc_scope.end(E, self, try rc_scope.borrowAddress(E, self, local));
            local = state.plan.aliases[local];
        } else break;
    }
}

fn borrowReceiverImpl(comptime E: type, self: *E, local: usize, payload: usize) Error!void {
    if (inert_receiver.proven(E, self, local)) return;
    const scope = try rc_scope.borrowAddress(E, self, local);
    try rc_scope.begin(E, self, scope);
    const plan = self.cow.?.plan;
    if (plan.place(local)) |place| {
        try pinAncestors(E, self, place, scope);
    } else if (rc_unique.receiverParent(E, self, local)) |parent| {
        if (plan.place(parent)) |place| try pinAncestors(E, self, place, scope);
    }
    try rc_scope.pin(E, self, scope, payload);
}

fn versionLifetime(comptime E: type, self: *E, head: usize, back: usize) bool {
    if (!runtime_mode.enabled()) return true;
    return @import("qbe_rc_hoist.zig").permitsVersion(E, self, head, back);
}
