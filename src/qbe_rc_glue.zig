//! RC-GLUE-1: the one emission helper per ownership operation kind.
//!
//! Every loan, unloan, retain, take and drop the RC lowering emits for a
//! counted inline type goes through here. A value that is one pointer edge
//! gets an inline fast path (null test, mark test, one count update) whose
//! rare cases call that type's generated glue (`rc_glue.zig`); every other
//! value calls its glue directly. Counting builds always call the glue, which
//! records the same events as the runtime and checks its invariants.
const typed = @import("typed.zig");
const runtime = @import("runtime_mode.zig");
const glue = @import("rc_glue.zig");
const semantics = @import("value_semantics.zig");

/// Native emission failures shared with the RC slot operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// A value copy or move between two addresses; region is an SSA depth value.
pub const Transfer = struct { ty: typed.Type, destination: usize, source: usize, region: usize = 0 };
/// A release of the value at address; heap names a temporary when `%heap` is absent.
pub const Release = struct { ty: typed.Type, address: usize, heap: ?usize = null };

// Common-header mark bits (native_heap.h). Neither arena nor immortal objects
// carry the counted prefix; an arena edge still needs its region checked.
const uncounted_marks: u64 = (@as(u64, 1) << 62) | 2;
const arena_mark: u64 = @as(u64, 1) << 62;
// Immortal or copy-on-write shared payloads are never unique.
const shared_marks: u64 = (@as(u64, 1) << 61) | 2;
// Prefix words below the payload (native_rc.h): owners, holds, mark.
const owners_offset: u64 = 32;
const holds_offset: u64 = 24;
const mark_offset: u64 = 16;

// A fallible glue entry returning its w status; a word loaded below a payload.
const status_call = " %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d}, w %v{d})\n";
const load_below = " %v{d} =l sub %v{d}, {d}\n %v{d} =l loadl %v{d}\n";
const mask = " %v{d} =l and %v{d}, {d}\n";

/// Journal roles (MYL_QBE_RC_*): a frame-private loan, a hold-pointer H token
/// and an ordinary counted owner with no unique-drop obligation.
pub const loan_role: u32 = 16;
/// The H-token role of a one-word hold-pointer slot.
pub const hold_role: u32 = 8;
/// The role of an ordinary counted owner (MYL_QBE_RC_COUNTED alone).
pub const owner_role: u32 = 2;

/// Which count the single edge of a pointer value's operation touches.
const Count = enum { owners, holds };

/// Whether ownership operations on `ty` run through generated glue.
pub fn routed(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    // Test stand-in emitters carry no catalog and always keep the runtime path.
    if (comptime !(@hasField(E, "cow") and @hasField(E, "layouts"))) return false;
    if (!runtime.enabled()) return false;
    const cow = self.cow orelse return false;
    const state = cow.rc orelse return false;
    return glue.eligible(self.layouts, &state.catalog, ty) catch |err| translate(err);
}

/// Copy the value and acquire one hold per edge. A loan cannot fail or kill.
pub fn loan(comptime E: type, self: *E, operation: Transfer) Error!void {
    try marker(E, self, .loan);
    if (try pointerEdge(E, self, operation.ty)) |_| {
        const payload = self.temp();
        try self.print(" %v{d} =l loadl %v{d}\n storel %v{d}, %v{d}\n", .{ payload, operation.source, payload, operation.destination });
        const label = self.temp();
        _ = try increment(E, self, .{ .payload = payload, .count = .holds, .label = label, .on_null = "done", .on_special = "done" });
        try self.print("@rcgdone{d}\n", .{label});
        return;
    }
    try self.print(" call ${s}{s}(l %heap, l %v{d}, l %v{d})\n", .{ try self.descriptor(operation.ty), glue.Operation.loan.suffix(), operation.destination, operation.source });
}

/// Copy the value and acquire each edge's own token; only an arena edge can
/// refuse, through the glue's runtime fallback and the usual failure path.
pub fn retain(comptime E: type, self: *E, operation: Transfer) Error!void {
    try marker(E, self, .retain);
    const symbol = try self.descriptor(operation.ty);
    const suffix = glue.Operation.retain.suffix();
    const edge = try pointerEdge(E, self, operation.ty) orelse {
        const result = self.temp();
        try self.print(status_call, .{ result, symbol, suffix, operation.destination, operation.source, operation.region });
        return requireSuccess(E, self, result);
    };
    const payload = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n", .{ payload, operation.source });
    const mark = try increment(E, self, .{ .payload = payload, .count = edge, .label = label, .on_null = "plain", .on_special = "special" });
    try self.print(" jmp @rcgplain{d}\n@rcgspecial{d}\n", .{ label, label });
    // Immortal edges need nothing; an arena edge needs its region checked.
    const arena = self.temp();
    try self.print(" %v{d} =l and %v{d}, {d}\n jnz %v{d}, @rcgslow{d}, @rcgplain{d}\n@rcgslow{d}\n", .{ arena, mark, arena_mark, arena, label, label, label });
    const result = self.temp();
    try self.print(status_call, .{ result, symbol, suffix, operation.destination, operation.source, operation.region });
    try requireSuccess(E, self, result);
    try self.print(" jmp @rcgdone{d}\n@rcgplain{d}\n storel %v{d}, %v{d}\n@rcgdone{d}\n", .{ label, label, payload, operation.destination, label });
}

/// Semantic direct publication of the value into empty storage; mode is a w
/// temporary holding the MYL_RC_HISTORY_* bits.
pub const Publish = struct { move: Transfer, mode: usize };

/// Publish through the type's glue, which keeps child-history modes, pins
/// and arenas on the runtime's semantic transaction.
pub fn publish(comptime E: type, self: *E, operation: Publish) Error!void {
    try marker(E, self, .publish);
    const result = self.temp();
    const move = operation.move;
    try self.print(" %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d}, w %v{d}, w %v{d})\n", .{ result, try self.descriptor(move.ty), glue.Operation.publish.suffix(), move.destination, move.source, move.region, operation.mode });
    try requireSuccess(E, self, result);
}

/// One list element write: the list payload, the element index (set only)
/// and the address of the value to retain into it.
pub const ListWrite = struct { element: typed.Type, result: usize, list: usize, index: ?usize = null, value: usize };

/// Replace or append a list element through the element type's glue. The
/// result is the runtime's w status; the caller maps a refusal as before.
pub fn listWrite(comptime E: type, self: *E, write: ListWrite) Error!void {
    try marker(E, self, if (write.index == null) .list_append else .list_set);
    if (write.index) |index| {
        try self.print(" %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d}, l %v{d})\n", .{ write.result, try self.descriptor(write.element), glue.Operation.list_set.suffix(), write.list, index, write.value });
    } else try self.print(" %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d})\n", .{ write.result, try self.descriptor(write.element), glue.Operation.list_append.suffix(), write.list, write.value });
}

/// Move the value and clear its source through the type's glue; a pinned or
/// arena source takes the runtime transaction inside the glue.
pub fn take(comptime E: type, self: *E, operation: Transfer) Error!void {
    try marker(E, self, .take);
    const result = self.temp();
    try self.print(status_call, .{ result, try self.descriptor(operation.ty), glue.Operation.take.suffix(), operation.destination, operation.source, operation.region });
    try requireSuccess(E, self, result);
}

/// Clear the value and release each edge's own token.
pub fn drop(comptime E: type, self: *E, operation: Release) Error!void {
    const edge = try pointerEdge(E, self, operation.ty);
    return release(E, self, operation, .drop, edge);
}

/// Clear the value and release the hold each edge carries as a loan (or as
/// the H token of a hold-pointer slot).
pub fn unloan(comptime E: type, self: *E, operation: Release) Error!void {
    const edge: ?Count = if (try pointerEdge(E, self, operation.ty) != null) .holds else null;
    return release(E, self, operation, .unloan, edge);
}

/// Skip a uniqueness helper whose payload is already unique, exactly as
/// myl_rc_unique decides: null and arena payloads are unique; immortal and
/// shared ones are not; otherwise at most one owner. Branches to
/// @rcgunique{label} when nothing needs to change and falls through to the
/// caller's runtime helper otherwise. Counting builds always call the helper.
pub fn uniqueFast(comptime E: type, self: *E, address: usize, label: usize) Error!void {
    if (runtime.counting()) return;
    const payload = self.temp();
    const header = self.temp();
    const mark = self.temp();
    const shared = self.temp();
    const arena = self.temp();
    const counter = self.temp();
    const owners = self.temp();
    const single = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n jnz %v{d}, @rcguniquenn{d}, @rcgunique{d}\n@rcguniquenn{d}\n", .{ payload, address, payload, label, label, label });
    try self.print(load_below ++ mask, .{ header, payload, mark_offset, mark, header, shared, mark, shared_marks });
    try self.print(" jnz %v{d}, @rcguniqueslow{d}, @rcguniquemark{d}\n@rcguniquemark{d}\n", .{ shared, label, label, label });
    try self.print(" %v{d} =l and %v{d}, {d}\n jnz %v{d}, @rcgunique{d}, @rcguniquecount{d}\n@rcguniquecount{d}\n", .{ arena, mark, arena_mark, arena, label, label, label });
    try self.print(load_below ++ " %v{d} =w cultl %v{d}, 2\n", .{ counter, payload, owners_offset, owners, counter, single, owners });
    try self.print(" jnz %v{d}, @rcgunique{d}, @rcguniqueslow{d}\n@rcguniqueslow{d}\n", .{ single, label, label, label });
}

/// Close a uniqueFast region after the caller's helper and its success check.
pub fn uniqueJoin(comptime E: type, self: *E, label: usize) Error!void {
    if (!runtime.counting()) try self.print("@rcgunique{d}\n", .{label});
}

/// Map a sticky RC refusal before any compiler ownership guard changes.
pub fn requireSuccess(comptime E: type, self: *E, result: usize) Error!void {
    const branch = self.temp();
    const status = self.temp();
    const checked = self.temp();
    try self.print(" jnz %v{d}, @rcsuccess{d}, @rcfailure{d}\n@rcfailure{d}\n", .{ result, branch, branch, branch });
    try self.print(" %v{d} =w call $myl_rc_take_failure(l %heap)\n %v{d} =w call $myl_qbe_rc_status(l %ctx, w %v{d})\n", .{ status, checked, status });
    try self.print(" jmp @failure\n@rcsuccess{d}\n", .{branch});
}

/// Whether `ty` is exactly one pointer edge whose operation can run inline,
/// and which count its own token uses. Counting builds keep every event in
/// the glue, so they never inline.
fn pointerEdge(comptime E: type, self: *E, ty: typed.Type) Error!?Count {
    if (comptime !@hasField(E, "layouts")) return null;
    if (runtime.counting()) return null;
    if (!try routed(E, self, ty)) return null;
    const layout = self.layouts.layout(ty) catch |err| return translate(err);
    if (layout.size != 8) return null;
    if (semantics.isLiveView(self.layouts.records, ty)) return .holds;
    return switch (layout.kind) {
        .managed, .niche => .owners,
        else => null,
    };
}

/// One inline count increment: labels are `@rcg<name><label>`.
const Increment = struct { payload: usize, count: Count, label: usize, on_null: []const u8, on_special: []const u8 };

// Increment the payload's count unless it is null (jump to on_null) or
// uncounted (jump to on_special); the counted path falls through. Returns the
// temporary holding the loaded mark.
fn increment(comptime E: type, self: *E, step: Increment) Error!usize {
    const header = self.temp();
    const mark = self.temp();
    const special = self.temp();
    const counter = self.temp();
    const old = self.temp();
    const new = self.temp();
    try self.print(" jnz %v{d}, @rcgnn{d}, @rcg{s}{d}\n@rcgnn{d}\n", .{ step.payload, step.label, step.on_null, step.label, step.label });
    try self.print(load_below, .{ header, step.payload, mark_offset, mark, header });
    try self.print(mask, .{ special, mark, uncounted_marks });
    try self.print(" jnz %v{d}, @rcg{s}{d}, @rcginc{d}\n@rcginc{d}\n", .{ special, step.on_special, step.label, step.label, step.label });
    try self.print(load_below, .{ counter, step.payload, offset(step.count), old, counter });
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n", .{ new, old, new, counter });
    return mark;
}

fn offset(count: Count) u64 {
    return if (count == .owners) owners_offset else holds_offset;
}

fn release(comptime E: type, self: *E, operation: Release, operation_kind: glue.Operation, edge: ?Count) Error!void {
    try marker(E, self, operation_kind);
    const symbol = try self.descriptor(operation.ty);
    const suffix = operation_kind.suffix();
    const heap = self.temp();
    if (operation.heap) |value| {
        try self.print(" %v{d} =l copy %v{d}\n", .{ heap, value });
    } else try self.print(" %v{d} =l copy %heap\n", .{heap});
    const count = edge orelse {
        try self.print(" call ${s}{s}(l %v{d}, l %v{d})\n", .{ symbol, suffix, heap, operation.address });
        return;
    };
    const other: Count = if (count == .owners) .holds else .owners;
    const payload = self.temp();
    const header = self.temp();
    const mark = self.temp();
    const special = self.temp();
    const counter = self.temp();
    const value = self.temp();
    const last = self.temp();
    const other_counter = self.temp();
    const other_value = self.temp();
    const reduced = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n jnz %v{d}, @rcgnn{d}, @rcgdone{d}\n@rcgnn{d}\n", .{ payload, operation.address, payload, label, label, label });
    try self.print(load_below ++ mask, .{ header, payload, mark_offset, mark, header, special, mark, uncounted_marks });
    try self.print(" jnz %v{d}, @rcgclear{d}, @rcgcounted{d}\n@rcgcounted{d}\n", .{ special, label, label, label });
    try self.print(load_below ++ " %v{d} =w ceql %v{d}, 1\n", .{ counter, payload, offset(count), value, counter, last, value });
    try self.print(" jnz %v{d}, @rcglast{d}, @rcgdec{d}\n@rcglast{d}\n", .{ last, label, label, label });
    try self.print(load_below, .{ other_counter, payload, offset(other), other_value, other_counter });
    // The last token of an otherwise unheld object dies: the glue clears the
    // slot, queues the death and drains.
    try self.print(" jnz %v{d}, @rcgdec{d}, @rcgslow{d}\n@rcgslow{d}\n", .{ other_value, label, label, label });
    try self.print(" call ${s}{s}(l %v{d}, l %v{d})\n jmp @rcgdone{d}\n@rcgdec{d}\n", .{ symbol, suffix, heap, operation.address, label, label });
    try self.print(" %v{d} =l sub %v{d}, 1\n storel %v{d}, %v{d}\n@rcgclear{d}\n storel 0, %v{d}\n@rcgdone{d}\n", .{ reduced, value, reduced, counter, label, operation.address, label });
}

/// A comment naming the operation, so IL readers and tests can find every
/// glue site whether its fast path is inline or a call.
fn marker(comptime E: type, self: *E, operation: glue.Operation) Error!void {
    try self.print(" # RC-GLUE-1 {s}\n", .{@tagName(operation)});
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
