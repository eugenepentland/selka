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
// Immortal, copy-on-write shared or arena payloads keep the runtime helper.
const shared_marks: u64 = (@as(u64, 1) << 62) | (@as(u64, 1) << 61) | 2;
// Publication marks (RC-PUBLISH-FAST-1): pinned or arena payloads need the
// runtime transaction; shared or immortal ones are not marked again.
const pinned_or_arena: u64 = (@as(u64, 1) << 62) | (@as(u64, 1) << 60);
const shared_or_immortal: u64 = (@as(u64, 1) << 61) | 2;
const shared_mark: u64 = @as(u64, 1) << 61;
// Prefix words below the payload (native_rc.h): owners, holds, mark.
const prefix = @import("qbe_rc_prefix.zig");
const owners_offset = prefix.owners_offset;
const holds_offset = prefix.holds_offset;
const mark_offset = prefix.mark_offset;
const count_result = " %v{d} =" ++ prefix.count_type;
const count_equal = " %v{d} =w ceq" ++ prefix.count_type ++ " %v{d}, ";

// A fallible glue entry returning its w status; a word loaded below a payload.
const status_call = " %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d}, w %v{d})\n";
// LLVM-RC-PREFIX-1: the marker names the address as a word of the counted
// prefix, which the LLVM translator keeps apart from frame, object and
// element memory; QBE reads it as a comment.
const load_below = " %v{d} =l sub %v{d}, {d}\n # myl-rc %v{d}\n %v{d} =l loadl %v{d}\n";
const mask = " %v{d} =l and %v{d}, {d}\n";
const load_word = @import("qbe_format.zig").load_word;

/// Frame role words (MYL_QBE_RC_*): a frame-private loan and a hold-pointer H
/// token; a static drop of either returns its holds through unloan glue.
pub const loan_role: u32 = 16;
/// The H-token role of a one-word hold-pointer slot.
pub const hold_role: u32 = 8;

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

/// Whether a list element write of `ty` runs through glue: the type must be
/// some collection's element and routed; a room append also takes a plain
/// inline aggregate, whose append is a byte copy.
pub fn listRouted(comptime E: type, self: *E, ty: typed.Type, operation: glue.Operation) Error!bool {
    if (comptime !(@hasField(E, "cow") and @hasField(E, "layouts"))) return false;
    if (!runtime.enabled() or !glue.listElement(self.layouts, ty)) return false;
    if (try routed(E, self, ty)) return true;
    if (operation != .list_append) return false;
    const cow = self.cow orelse return false;
    const state = cow.rc orelse return false;
    return glue.plainAggregate(self.layouts, &state.catalog, ty) catch |err| translate(err);
}

/// Copy the value and acquire one hold per edge, mapping a refused count before publishing the loan.
pub fn loan(comptime E: type, self: *E, operation: Transfer) Error!void {
    try marker(E, self, .loan);
    if (try pointerEdge(E, self, operation.ty)) |_| {
        const payload = self.temp();
        try self.print(" %v{d} =l loadl %v{d}\n", .{ payload, operation.source });
        const label = self.temp();
        _ = try increment(E, self, .{ .payload = payload, .count = .holds, .label = label, .on_null = "store", .on_special = "store" });
        try self.print("@rcgstore{d}\n storel %v{d}, %v{d}\n", .{ label, payload, operation.destination });
        return;
    }
    const result = self.temp();
    try self.print(" %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d})\n", .{ result, try self.descriptor(operation.ty), glue.Operation.loan.suffix(), operation.destination, operation.source });
    try requireSuccess(E, self, result);
}

/// Take one H token on the payload in %v{payload} into the empty hold slot at
/// %v{slot}, inline, when `ty` is a one-word counted value; returns false when
/// the caller must use the runtime's counting hold acquisition instead.
pub fn holdAcquire(comptime E: type, self: *E, ty: typed.Type, payload: usize, slot: usize) Error!bool {
    if (try pointerEdge(E, self, ty) == null) return false;
    try self.print(" # RC-GLUE-1 hold\n", .{});
    const label = self.temp();
    _ = try increment(E, self, .{ .payload = payload, .count = .holds, .label = label, .on_null = "store", .on_special = "store" });
    try self.print("@rcgstore{d}\n storel %v{d}, %v{d}\n", .{ label, payload, slot });
    return true;
}

/// Copy the value and acquire each edge's own token, mapping count and region refusals before publishing output.
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
    try self.print(load_word, .{ payload, operation.source });
    const mark = try increment(E, self, .{ .payload = payload, .count = edge, .label = label, .on_null = "plain", .on_special = "special" });
    try self.print(" jmp @rcgplain{d}\n@rcgspecial{d}\n", .{ label, label });
    // Immortal edges need nothing; an arena edge needs its region checked.
    const arena = self.temp();
    try self.print(mask, .{ arena, mark, arena_mark });
    try self.print(" jnz %v{d}, @rcgslow{d}, @rcgplain{d}\n@rcgslow{d}\n", .{ try nonzero(E, self, arena), label, label, label });
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
    const label = self.temp();
    const inline_path = try mutablePointer(E, self, operation.move.ty);
    if (inline_path) try publishFast(E, self, operation, label);
    const result = self.temp();
    const move = operation.move;
    try self.print(" %v{d} =w call ${s}{s}(l %heap, l %v{d}, l %v{d}, w %v{d}, w %v{d})\n", .{ result, try self.descriptor(move.ty), glue.Operation.publish.suffix(), move.destination, move.source, move.region, operation.mode });
    try requireSuccess(E, self, result);
    if (inline_path) try self.print("@rcgpublished{d}\n", .{label});
}

// Whether `ty` is one pointer to a list or dictionary: a payload the glue's
// share step always marks when it is not already shared or immortal.
fn mutablePointer(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    if (comptime !@hasField(E, "layouts")) return false;
    if (try pointerEdge(E, self, ty) != .owners) return false;
    if (!ty.isAggregate()) return false;
    const record = self.layouts.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return false;
    return record.collection.kind == .list or record.collection.kind == .dictionary;
}

/// RC-PUBLISH-FAST-1: the direct publication of one list or dictionary
/// pointer runs inline exactly as its glue does: a null copies through; a
/// payload neither pinned nor in an arena is marked shared unless it already
/// is (or is immortal), its pointer is stored, and then either the source is
/// cleared (a take) or one owner is acquired (immortal payloads count none).
/// Child-history modes, pinned and arena payloads fall through to the glue.
fn publishFast(comptime E: type, self: *E, operation: Publish, label: usize) Error!void {
    const move = operation.move;
    const child = self.temp();
    const payload = self.temp();
    const header = self.temp();
    const mark = self.temp();
    const special = self.temp();
    const already = self.temp();
    const marked = self.temp();
    const taken = self.temp();
    const immortal = self.temp();
    const counter = self.temp();
    const old = self.temp();
    const new = self.temp();
    // Every emitted publication targets private work or aggregate scratch,
    // never its own source, so the glue's overlap test cannot fire here.
    try self.print(" %v{d} =w and %v{d}, 3\n", .{ child, operation.mode });
    try self.print(" jnz %v{d}, @rcgpublishslow{d}, @rcgpublishmode{d}\n@rcgpublishmode{d}\n", .{ try wordFlag(E, self, child), label, label, label });
    try self.print(load_word, .{ payload, move.source });
    try self.print(" jnz %v{d}, @rcgpublishnn{d}, @rcgpublishstore{d}\n@rcgpublishnn{d}\n", .{ try nonzero(E, self, payload), label, label, label });
    try self.print(load_below ++ mask, .{ header, payload, mark_offset, header, mark, header, special, mark, pinned_or_arena });
    try self.print(" jnz %v{d}, @rcgpublishslow{d}, @rcgpublishshare{d}\n@rcgpublishshare{d}\n", .{ try nonzero(E, self, special), label, label, label });
    const copy_mode = self.temp();
    const ordinary = self.temp();
    const capacity = self.temp();
    const capacity_at = self.temp();
    const saturated = self.temp();
    try self.print(" %v{d} =w and %v{d}, 4\n %v{d} =l and %v{d}, 2\n", .{ copy_mode, operation.mode, ordinary, mark });
    try self.print(" jnz %v{d}, @rcgpublishmarkcheck{d}, @rcgpublishordinary{d}\n@rcgpublishordinary{d}\n", .{ try wordFlag(E, self, copy_mode), label, label, label });
    try self.print(" jnz %v{d}, @rcgpublishmarkcheck{d}, @rcgpublishcapacity{d}\n@rcgpublishcapacity{d}\n", .{ try nonzero(E, self, ordinary), label, label, label });
    try self.print(prefix.load_count, .{ capacity_at, payload, owners_offset, capacity_at, capacity, capacity_at });
    try self.print(count_equal ++ "{d}\n jnz %v{d}, @rcgpublishslow{d}, @rcgpublishmarkcheck{d}\n@rcgpublishmarkcheck{d}\n", .{ saturated, capacity, prefix.count_max, saturated, label, label, label });
    try self.print(mask, .{ already, mark, shared_or_immortal });
    try self.print(" jnz %v{d}, @rcgpublishstore{d}, @rcgpublishmark{d}\n@rcgpublishmark{d}\n", .{ try nonzero(E, self, already), label, label, label });
    try self.print(" %v{d} =l or %v{d}, {d}\n storel %v{d}, %v{d}\n", .{ marked, mark, shared_mark, marked, header });
    try self.print("@rcgpublishstore{d}\n storel %v{d}, %v{d}\n %v{d} =w and %v{d}, 4\n", .{ label, payload, move.destination, taken, operation.mode });
    const moves = try wordFlag(E, self, taken);
    try self.print(" jnz %v{d}, @rcgpublishtake{d}, @rcgpublishnull{d}\n@rcgpublishtake{d}\n storel 0, %v{d}\n jmp @rcgpublished{d}\n", .{ moves, label, label, label, move.source, label });
    // A null payload acquires nothing; an immortal one counts no owners.
    try self.print("@rcgpublishnull{d}\n", .{label});
    const present = try nonzero(E, self, payload);
    try self.print(" jnz %v{d}, @rcgpublishcount{d}, @rcgpublished{d}\n@rcgpublishcount{d}\n", .{ present, label, label, label });
    try self.print(" %v{d} =l and %v{d}, 2\n", .{ immortal, mark });
    const uncounted = try nonzero(E, self, immortal);
    try self.print(" jnz %v{d}, @rcgpublished{d}, @rcgpublishinc{d}\n@rcgpublishinc{d}\n", .{ uncounted, label, label, label });
    try self.print(prefix.load_count, .{ counter, payload, owners_offset, counter, old, counter });
    try self.print(count_result ++ " add %v{d}, 1\n " ++ prefix.count_store ++ " %v{d}, %v{d}\n jmp @rcgpublished{d}\n@rcgpublishslow{d}\n", .{ new, old, new, counter, label, label });
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
    if (comptime @hasField(E, "layouts") and @hasField(E, "function")) {
        if (edge == null and hotSite(E, self)) if (try flatOwners(E, self, operation.ty)) |flat| return dropFlat(E, self, operation, flat);
    }
    return release(E, self, operation, .drop, edge);
}

// Only a local's replacement (`store_local`) or explicit release
// (`drop_local`) is worth its inline size: an operand consumed by a
// projection usually holds no token, and a return's exit drops run once.
fn hotSite(comptime E: type, self: *E) bool {
    if (comptime !@hasField(E, "function")) return false;
    const code = self.function.scope.instructions;
    if (self.pc >= code.len) return false;
    return switch (code[self.pc].op) {
        .store_local, .drop_local => true,
        else => false,
    };
}

/// The one-word owner leaves of an inline record: at most four, each a
/// routed type released through its own inline fast path.
const Leaves = struct { offsets: [4]u64 = undefined, types: [4]typed.Type = undefined, len: usize = 0 };

// A plain inline record (no variant, array, view or unique resource) whose
// counted leaves are all one-word owner pointers, found through nested
// records; anything else keeps the type's own glue call.
fn flatOwners(comptime E: type, self: *E, ty: typed.Type) Error!?Leaves {
    if (comptime !@hasField(E, "layouts")) return null;
    if (runtime.counting() or !ty.isAggregate()) return null;
    if (!try routed(E, self, ty)) return null;
    // A wider value's inline clear costs more than the glue's vector memset.
    const layout = self.layouts.layout(ty) catch |err| return translate(err);
    if (layout.size > 64) return null;
    var leaves: Leaves = .{};
    if (!try collect(E, self, ty, 0, &leaves, 4) or leaves.len == 0) return null;
    return leaves;
}

fn collect(comptime E: type, self: *E, ty: typed.Type, base: u64, leaves: *Leaves, depth: usize) Error!bool {
    if (depth == 0 or semantics.isLiveView(self.layouts.records, ty)) return false;
    const layout = self.layouts.layout(ty) catch |err| return translate(err);
    if (layout.drop) return false;
    switch (layout.kind) {
        .scalar => return true,
        .managed => {
            if (try pointerEdge(E, self, ty) != .owners or leaves.len == leaves.offsets.len) return false;
            leaves.offsets[leaves.len] = base;
            leaves.types[leaves.len] = ty;
            leaves.len += 1;
            return true;
        },
        .record => {
            if (self.layouts.records[ty.recordIndex()].isManagedRecord()) return false;
            for (layout.fields) |field| if (!try collect(E, self, field.ty, base + field.offset, leaves, depth - 1)) return false;
            return true;
        },
        else => return false,
    }
}

/// RC-FLAT-DROP-1: drop a plain record of at most four one-word owner leaves
/// as one inline owner release per leaf (the leaf's own glue takes the last
/// token and drains), then clear the whole value, as the record's glue does
/// edge by edge, where a local's previous value is replaced or released.
fn dropFlat(comptime E: type, self: *E, operation: Release, leaves: Leaves) Error!void {
    try self.print(" # RC-FLAT-DROP-1\n", .{});
    for (leaves.offsets[0..leaves.len], leaves.types[0..leaves.len]) |at, leaf| {
        const address = self.temp();
        try self.print(" %v{d} =l add %v{d}, {d}\n", .{ address, operation.address, at });
        try release(E, self, .{ .ty = leaf, .address = address, .heap = operation.heap }, .drop, .owners);
    }
    const layout = self.layouts.layout(operation.ty) catch |err| return translate(err);
    try @import("qbe_zero.zig").clear(*E, self, operation.address, layout.size, layout.alignment);
}

/// Clear the value and release the hold each edge carries as a loan (or as
/// the H token of a hold-pointer slot).
pub fn unloan(comptime E: type, self: *E, operation: Release) Error!void {
    const edge: ?Count = if (try pointerEdge(E, self, operation.ty) != null) .holds else null;
    return release(E, self, operation, .unloan, edge);
}

/// Skip a uniqueness helper whose payload is already unique, as myl_rc_unique
/// decides: a null payload is unique and a counted unshared one with at most
/// one owner is too. Immortal, shared and arena payloads (whose held slots
/// also check regions) keep the helper. Branches to
/// @rcgunique{label} when nothing needs to change and falls through to the
/// caller's runtime helper otherwise. Counting builds always call the helper.
pub fn uniqueFast(comptime E: type, self: *E, address: usize, label: usize) Error!void {
    if (runtime.counting()) return;
    const payload = self.temp();
    const header = self.temp();
    const mark = self.temp();
    const shared = self.temp();
    const counter = self.temp();
    const owners = self.temp();
    const single = self.temp();
    try self.print(load_word, .{ payload, address });
    try self.print(" jnz %v{d}, @rcguniquenn{d}, @rcgunique{d}\n@rcguniquenn{d}\n", .{ try nonzero(E, self, payload), label, label, label });
    try self.print(load_below ++ mask, .{ header, payload, mark_offset, header, mark, header, shared, mark, shared_marks });
    try self.print(" jnz %v{d}, @rcguniqueslow{d}, @rcguniquecount{d}\n@rcguniquecount{d}\n", .{ try nonzero(E, self, shared), label, label, label });
    try self.print(prefix.load_count ++ " %v{d} =w cult" ++ prefix.count_type ++ " %v{d}, 2\n", .{ counter, payload, owners_offset, counter, owners, counter, single, owners });
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
    try self.print(" jnz %v{d}, @rcgnn{d}, @rcg{s}{d}\n@rcgnn{d}\n", .{ try nonzero(E, self, step.payload), step.label, step.on_null, step.label, step.label });
    try self.print(load_below, .{ header, step.payload, mark_offset, header, mark, header });
    try self.print(mask, .{ special, mark, uncounted_marks });
    try self.print(" jnz %v{d}, @rcg{s}{d}, @rcginc{d}\n@rcginc{d}\n", .{ try nonzero(E, self, special), step.on_special, step.label, step.label, step.label });
    try self.print(prefix.load_count, .{ counter, step.payload, offset(step.count), counter, old, counter });
    const limit = self.temp();
    const status = self.temp();
    try self.print(count_equal ++ "{d}\n jnz %v{d}, @rcglimit{d}, @rcgcapacity{d}\n@rcglimit{d}\n", .{ limit, old, prefix.count_max, limit, step.label, step.label, step.label });
    try self.print(" %v{d} =w call $myl_qbe_rc_status(l %ctx, w 2)\n jmp @failure\n@rcgcapacity{d}\n", .{ status, step.label });
    try self.print(count_result ++ " add %v{d}, 1\n " ++ prefix.count_store ++ " %v{d}, %v{d}\n", .{ new, old, new, counter });
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
    try self.print(load_word, .{ payload, operation.address });
    try self.print(" jnz %v{d}, @rcgnn{d}, @rcgdone{d}\n@rcgnn{d}\n", .{ try nonzero(E, self, payload), label, label, label });
    try self.print(load_below ++ mask, .{ header, payload, mark_offset, header, mark, header, special, mark, uncounted_marks });
    try self.print(" jnz %v{d}, @rcgclear{d}, @rcgcounted{d}\n@rcgcounted{d}\n", .{ try nonzero(E, self, special), label, label, label });
    try self.print(prefix.load_count ++ count_equal ++ "1\n", .{ counter, payload, offset(count), counter, value, counter, last, value });
    try self.print(" jnz %v{d}, @rcglast{d}, @rcgdec{d}\n@rcglast{d}\n", .{ last, label, label, label });
    try self.print(prefix.load_count, .{ other_counter, payload, offset(other), other_counter, other_value, other_counter });
    // The last token of an otherwise unheld object dies: the glue clears the
    // slot, queues the death and drains.
    try self.print(" jnz %v{d}, @rcgdec{d}, @rcgslow{d}\n@rcgslow{d}\n", .{ try nonzero(E, self, other_value), label, label, label });
    try self.print(" call ${s}{s}(l %v{d}, l %v{d})\n jmp @rcgdone{d}\n@rcgdec{d}\n", .{ symbol, suffix, heap, operation.address, label, label });
    try self.print(count_result ++ " sub %v{d}, 1\n " ++ prefix.count_store ++ " %v{d}, %v{d}\n@rcgclear{d}\n storel 0, %v{d}\n@rcgdone{d}\n", .{ reduced, value, reduced, counter, label, operation.address, label });
}

/// A word flag for a w value, compared at full width like every inline
/// glue branch.
fn wordFlag(comptime E: type, self: *E, value: usize) Error!usize {
    const wide = self.temp();
    try self.print(" %v{d} =l extuw %v{d}\n", .{ wide, value });
    return nonzero(E, self, wide);
}

/// A word flag for a full-width l value. QBE's jnz reads only the low word,
/// so a pointer or a high mark bit (arena, shared, pinned) is compared with
/// zero at full width before branching.
fn nonzero(comptime E: type, self: *E, value: usize) Error!usize {
    const flag = self.temp();
    try self.print(" %v{d} =w cnel %v{d}, 0\n", .{ flag, value });
    return flag;
}

/// A comment naming the operation, so IL readers and tests can find every
/// glue site whether its fast path is inline or a call.
fn marker(comptime E: type, self: *E, operation: glue.Operation) Error!void {
    try self.print(" # RC-GLUE-1 {s}\n", .{@tagName(operation)});
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
