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
const cow_plan = @import("cow_plan.zig");
const format = @import("qbe_format.zig");
const qbe_alloc = @import("qbe_alloc.zig");
const cow_keep_label = "@cowkeep{d}\n";
const store_pointer = " storel %v{d}, %v{d}\n";
const store_local = " storel %v{d}, %l{d}\n";

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

/// The copy-on-write state of the function being lowered.
pub const State = struct {
    plan: cow_plan.Plan = .{},
    /// Per instruction, the temporary holding an element place's index,
    /// captured by its base read for the fill's write-back.
    captures: []usize = &.{},
    /// Whether every inline mark, check and pin also counts itself.
    counting: bool,
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
        pub fn plan(self: *E, state: *State) Error!void {
            const analysis = self.ownership orelse return error.InternalError;
            const input: cow_plan.Input = .{
                .program = self.program,
                .function = self.function,
                .states = self.states,
                .analysis = analysis,
                .shares = !@import("value_semantics.zig").enabled(),
            };
            state.plan = cow_plan.plan(self.allocator, input) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InternalError => error.InternalError,
            };
            state.captures = try self.allocator.alloc(usize, self.function.scope.instructions.len);
            @memset(state.captures, 0);
        }
        /// Keep a versioned loop only when no check is left inside it
        /// (`QBE-LOOP-VERSION-1`): a copy there would move the storage its
        /// guard read.
        pub fn veto(self: *E, state: *State) Error!void {
            var kept: std.ArrayList(@TypeOf(self.loop_plan.loops[0])) = .empty;
            for (self.loop_plan.loops) |loop| {
                const checked = for (loop.head..loop.back + 1) |pc| {
                    if (pc < state.plan.checked.len and state.plan.checked[pc]) break true;
                } else false;
                if (!checked) try kept.append(self.allocator, loop);
            }
            self.loop_plan.loops = try kept.toOwnedSlice(self.allocator);
        }
        /// Emit what runs before instruction `pc`: captures, root checks,
        /// place fills and shares.
        pub fn before(self: *E, pc: usize, stack: []const typed.Type) Error!void {
            const state = self.cow orelse return;
            const site = state.plan.at(pc);
            if (site.capture) try capture(E, self, state, pc, stack);
            if (site.unique_field) |field| try uniqueField(E, self, field, stack);
            for (site.unique) |unique| try uniqueLocal(E, self, unique, stack);
            if (site.fill) try fillPlace(E, self, pc, stack);
            for (site.shares) |depth| try share(E, self, stack, depth);
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
            return pinCall(E, self, callee, args, base);
        }
        /// Undo `pins` after the call returned: a payload pinned by this call
        /// alone is unpinned; one an outer caller pinned stays pinned.
        pub fn unpin(self: *E, pins: Pins) Error!void {
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

fn pinCall(comptime E: type, self: *E, callee: bytecode.Function, args: []usize, base: usize) Error!Pins {
    var pins: Pins = .{};
    var owners: [8]u32 = @splat(cow_plan.none);
    var positions: [8]usize = undefined;
    const state = self.cow orelse return pins;
    for (args, 0..) |*arg, position| {
        if (position >= callee.signature.parameter_count) break;
        if (!writesParameter(callee, position)) continue;
        if (!cow_plan.payloadType(self.program, callee.scope.locals[position].ty)) continue;
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

fn reuseMutArgument(comptime E: type, self: *E, arg: *usize, previous: usize, slot: usize) Error!void {
    try self.print(" storel %v{d}, %s{d}\n", .{ previous, slot });
    arg.* = try self.load("s", slot);
}

/// A later snapshot can share a mut operand after the load's first uniqueness
/// check. The call already published roots, so this copy must use them rather
/// than pushing the same frames again and making their next links cyclic.
fn prepareMutArgument(comptime E: type, self: *E, arg: *usize, source: @import("ownership.zig").Source, slot: usize) Error!void {
    if (source.origin != .local or source.local >= self.function.scope.locals.len or
        (source.part != .whole and source.part != .field)) return;
    const label = self.temp();
    try testShared(E, self, arg.*, label);
    const copy = self.temp();
    try self.print(" %v{d} =l call $myl_native_cow_unique(l %heap, l %v{d})\n", .{ copy, arg.* });
    try self.require(copy, format.allocation_failure);
    if (source.part == .whole) {
        try self.print(store_local, .{ copy, source.local });
    } else {
        if (source.read == cow_plan.none) return error.InternalError;
        var end = source.read + 1;
        while (end < self.pc) : (end += 1) switch (self.function.scope.instructions[end].op) {
            .get_field, .wrap_domain, .unwrap_domain => {},
            else => break,
        };
        const cursor = try fieldChainRange(E, self, source.read + 1, end, try fieldBase(E, self, source.local));
        if (cursor.cell) |body| try qbe_alloc.barrier(*E, self, body);
        try self.print(store_pointer, .{ copy, cursor.address });
    }
    try self.print(" storel %v{d}, %s{d}\n", .{ copy, slot });
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
    } else try self.print(" %v{d} =l call $myl_native_cow_unique(l %heap, l %v{d})\n", .{ copy, value });
    if (pushed) try self.restoreRoots();
    try self.require(copy, format.allocation_failure);
    return copy;
}

/// Make local `unique.local`'s payload unique: copy it when it is shared and
/// store the copy into its slot and its alias's.
fn uniqueLocal(comptime E: type, self: *E, unique: cow_plan.Unique, stack: []const typed.Type) Error!void {
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
    const cursor = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent));
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
    state.captures[pc] = try self.load("s", stack.len - 1);
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
/// temporary holding that address, and the `class` body it lies in, whose
/// store needs the generational barrier, or null.
const Cursor = struct { address: usize, cell: ?usize };

/// Make the value a place's fill stores unique: copy it when it is shared,
/// write the copy back into the place it was read from, and store the copy.
/// The place's container is kept alive through the copy, because the local
/// that named it may be dead by now.
fn fillPlace(comptime E: type, self: *E, pc: usize, stack: []const typed.Type) Error!void {
    if (stack.len == 0) return error.InternalError;
    const place = (try filledPlace(E, self, pc)).place;
    const top = stack.len - 1;
    const label = self.temp();
    const value = try self.load("s", top);
    try testShared(E, self, value, label);
    var container: ?usize = null;
    var cursor: Cursor = switch (place.step) {
        .element => element: {
            const list = try self.load("l", place.parent);
            container = list;
            break :element .{ .address = try elementSlot(E, self, place, list), .cell = null };
        },
        .entry => entry: {
            const dictionary = try self.load("l", place.parent);
            container = dictionary;
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null };
        },
        .entry_field => entry: {
            const cursor_field = try fieldChainRange(E, self, place.base + 1, place.fields_end, try fieldBase(E, self, place.parent));
            const dictionary = try self.load("v", cursor_field.address);
            container = dictionary;
            break :entry .{ .address = try entrySlot(E, self, place, dictionary), .cell = null };
        },
        .field => try fieldBase(E, self, place.parent),
    };
    if (place.step != .entry_field) cursor = try fieldChain(E, self, place, cursor);
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

/// The address of the element a place's base read took, in its list's
/// storage, from the index the read captured.
fn elementSlot(comptime E: type, self: *E, place: cow_plan.Place, list: usize) Error!usize {
    const storage = try self.load("v", try self.address(list, format.list_storage_offset));
    const schema = self.program.records[self.function.scope.locals[place.parent].ty.recordIndex()];
    const element = schema.shape.buffer orelse return error.InternalError;
    const stride = (try self.layout(element)).size;
    const offset = self.temp();
    const slot = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, self.cow.?.captures[place.base], stride, slot, storage, offset });
    return slot;
}

/// The address of the value a place's base read looked up, found again with
/// the key its operand slot still holds: no instruction between the read and
/// the fill writes that slot. A described slice key (`DICT-RANGE-KEY-1`) is
/// looked up by its span.
fn entrySlot(comptime E: type, self: *E, place: cow_plan.Place, dictionary: usize) Error!usize {
    const read = if (place.step == .entry_field) place.read else place.base;
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
    return fieldChainRange(E, self, place.base + 1, place.fill, start);
}

fn fieldChainRange(comptime E: type, self: *E, begin: usize, end: usize, start: Cursor) Error!Cursor {
    var cursor = start;
    for (begin..end) |pc| {
        const index = switch (self.function.scope.instructions[pc].op) {
            .get_field => |field| field,
            .wrap_domain, .unwrap_domain => continue,
            else => return error.InternalError,
        };
        const operands = self.states[pc] orelse return error.InternalError;
        const source = operands[operands.len - 1];
        const member = try self.field(source, index);
        if (self.program.records[source.recordIndex()].isManagedRecord()) {
            const body = try self.load("v", cursor.address);
            cursor = .{ .address = try self.address(body, member.offset), .cell = body };
        } else cursor.address = try self.address(cursor.address, member.offset);
    }
    return cursor;
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
    if (try flatten(E, self, ty, 0, &flat)) {
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
    try self.print(" jnz %v{d}, @sharecopy{d}, @sharemark{d}\n@sharecopy{d}\n", .{ flag, label, label, label });
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
const Flat = struct { offsets: [flat_limit]u64 = undefined, len: usize = 0 };

/// Collect the offsets of every payload a value of `ty` at `base` holds
/// directly, or answer false for a shape the runtime must walk: a union, an
/// optional, more than `flat_limit` payloads.
fn flatten(comptime E: type, self: *E, ty: typed.Type, base: u64, flat: *Flat) Error!bool {
    const value = try self.layout(ty);
    if (!value.trace) return true;
    switch (value.kind) {
        .managed => {
            if (!cow_plan.payloadType(self.program, ty)) return true;
            if (flat.len == flat_limit) return false;
            flat.offsets[flat.len] = base;
            flat.len += 1;
            return true;
        },
        .record, .domain => {
            if (self.program.records[ty.recordIndex()].isManagedRecord()) return true;
            for (value.fields) |field| if (!try flatten(E, self, field.ty, base + field.offset, flat)) return false;
            return true;
        },
        .array => {
            for (0..value.count) |i| if (!try flatten(E, self, value.fields[0].ty, base + i * value.stride, flat)) return false;
            return true;
        },
        else => return false,
    }
}
