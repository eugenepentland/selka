//! RC-READONLY-ANCHOR-1: values read out of a read-only parameter need no token.
//!
//! A read-only argument is lent for the whole call: the caller keeps it, and
//! everything its owned edges reach, alive and unchanged until the call
//! returns, and snapshots it when the same place is also passed `mut`. So a
//! field read, a list element read or a match payload bound out of such a
//! parameter (or out of a temporary that holds one) stays valid for the
//! activation without a loan or an owner of its own. Temporaries holding such
//! values are bound as borrowed from the parameter's storage; the reads that
//! produce them publish no token and the match arms bind their payloads in
//! place. Every consumer that needs an owner (a return, a store into another
//! local, a constructor, a real value copy) copies from the borrowed bits as
//! it does for any operand without a token.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const input = @import("rc_input.zig");
const model = @import("rc_model.zig");
const shapes = @import("rc_shape.zig");
const cow = @import("cow_plan.zig");
const semantics = @import("value_semantics.zig");
const plain = @import("rc_plain_updates.zig");
const operand_sources = @import("ownership_sources.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Analysis failures shared with the RC emitter.
pub const Error = error{ InternalError, OutOfMemory, WriteFailed, SourceError };

/// The deepest read chain one value looks back through.
const depth_limit = 16;
/// The largest body and local table the anchor analyses consider.
const code_limit = 16384;
const local_limit = 4096;
/// Instruction visits one function's anchor analysis may spend before it
/// stops and keeps ordinary ownership for what it has not proved.
const analysis_budget: usize = 1 << 22;

/// Bind every temporary whose definitions all store a value anchored in a
/// never-written read-only parameter as borrowed from that parameter's
/// storage. Parameters are never released by their callee, so any anchored
/// parameter serves as the physical anchor; the first one is used.
pub fn bind(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog, contract: model.CallContract) Error!void {
    const code = self.function.scope.instructions;
    const count = self.function.scope.locals.len;
    if (code.len > code_limit or count > local_limit) return;
    const roots = try self.allocator.alloc(bool, count);
    defer self.allocator.free(roots);
    @memset(roots, false);
    var first: ?usize = null;
    for (0..@min(count, contract.parameters.len)) |index| {
        if (contract.parameters[index] != .read or !try counted(catalog, self.function.scope.locals[index].ty)) continue;
        if (written(self.function, index)) continue;
        roots[index] = true;
        if (first == null) first = index;
    }
    const anchor = first orelse return;
    // Optimistic start: every candidate is anchored until a definition says otherwise.
    const anchored = try self.allocator.alloc(bool, count);
    defer self.allocator.free(anchored);
    for (anchored, 0..) |*flag, index| flag.* = roots[index] or try candidate(E, self, bindings, catalog, roots, index);
    var changed = true;
    var budget: usize = analysis_budget;
    // RC-BORROW-CALL-ANCHOR-1: callee certificates, computed once per callee.
    const certificates = try self.allocator.alloc(u32, self.program.functions.len);
    defer self.allocator.free(certificates);
    @memset(certificates, unknown_certificate);
    const working: Working = .{ .anchored = anchored, .catalog = catalog, .certificates = certificates };
    while (changed) {
        changed = false;
        for (anchored, 0..) |*flag, index| {
            if (!flag.* or roots[index]) continue;
            if (budget < code.len) return;
            budget -= code.len;
            if (definitions(E, self, working, index)) continue;
            flag.* = false;
            changed = true;
        }
    }
    for (anchored, 0..) |flag, index| if (flag and !roots[index]) {
        bindings[index].anchor = .{ .storage = bindings[anchor].storage };
    };
}

/// Whether a local holds a value anchored in a never-written read-only
/// parameter: the parameter itself, or a temporary bound to its storage.
pub fn anchoredLocal(comptime E: type, self: *E, local: usize) bool {
    const state = self.cow.?.rc orelse return false;
    if (local >= self.function.scope.locals.len) return false;
    // RC-INTERVAL-ANCHOR-2: a local bound to a list root while it is quiet.
    const interval = intervalRootOf(E, self, local);
    if (interval != cow.none and interval != local) return true;
    if (local < state.contract.parameters.len) return root(E, self, local);
    const ownership = state.plan.locals.entry[local].ownership;
    if (ownership != .borrowed or ownership.borrowed != .storage) return false;
    const anchor = @backingInt(ownership.borrowed.storage);
    return anchor < state.contract.parameters.len and root(E, self, anchor);
}

/// Store an anchored value wider than one word into its anchored local by
/// its bits, with no token; a one-word value takes the borrowed store of
/// `qbe_rc_read_loans.zig`. Returns false for any other store.
pub fn store(comptime E: type, self: *E, local: usize, operand: usize) Error!bool {
    const ty = self.function.scope.locals[local].ty;
    if (self.isScalar(ty) or !anchoredLocal(E, self, local) or local < self.function.signature.parameter_count) return false;
    const source = try self.load("s", operand);
    // RC-ELEMENT-BORROW-3: an element-borrowed slot keeps the element's
    // address, which stays valid while the caller keeps the parameter.
    if (self.borrowsElement(local)) {
        try self.print(" # RC-ELEMENT-BORROW-3 local {d}\n storel %v{d}, %l{d}\n", .{ local, source, local });
        return true;
    }
    const size = (self.layout(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError).size;
    try self.print(" # RC-READONLY-ANCHOR-1 local {d}\n blit %v{d}, %l{d}, {d}\n", .{ local, source, local, size });
    return true;
}

/// Whether the value instruction `pc` pushes is anchored, as emitted.
pub fn value(comptime E: type, self: *E, pc: usize) bool {
    return pushed(E, self, Emitted{}, pc, depth_limit);
}

/// Whether a match arm at `pc` binds `slot` in place from an anchored scrutinee.
pub fn payload(comptime E: type, self: *E, pc: usize, slot: usize) bool {
    if (pc == 0 or self.isBranchTarget(pc)) return false;
    return anchoredLocal(E, self, slot) and value(E, self, pc - 1);
}

fn root(comptime E: type, self: *E, local: usize) bool {
    const state = self.cow.?.rc.?;
    if (state.contract.parameters[local] != .read) return false;
    const shape = state.catalog.get(self.function.scope.locals[local].ty) catch return false;
    return shape.counted and !written(self.function, local);
}

// The analysis-time view: roots and the candidates still anchored.
const Working = struct {
    anchored: []const bool,
    catalog: *shapes.Catalog,
    /// Per function, the parameter its borrowed result is anchored in,
    /// `no_certificate`, or `unknown_certificate` until asked.
    certificates: []u32,
    fn local(self: Working, comptime E: type, emitter: *E, index: usize) bool {
        _ = emitter;
        return index < self.anchored.len and self.anchored[index];
    }
    fn parameter(self: Working, comptime E: type, emitter: *E, callee: bytecode.Function) ?u32 {
        const id = @backingInt(callee.id);
        if (id >= self.certificates.len) return null;
        if (self.certificates[id] == unknown_certificate) {
            const proof = @import("rc_calls.zig").borrowedIn(emitter.allocator, self.catalog, emitter.program.functions, callee, @import("runtime_mode.zig").identity()) catch null;
            self.certificates[id] = if (proof) |found| found.parameter else no_certificate;
        }
        return if (self.certificates[id] == no_certificate) null else self.certificates[id];
    }
};
const unknown_certificate = std.math.maxInt(u32);
const no_certificate = std.math.maxInt(u32) - 1;
// The emission-time view reads the finished plan.
const Emitted = struct {
    fn local(_: Emitted, comptime E: type, emitter: *E, index: usize) bool {
        return anchoredLocal(E, emitter, index) or intervalRootOf(E, emitter, index) == index;
    }
    fn parameter(_: Emitted, comptime E: type, emitter: *E, callee: bytecode.Function) ?u32 {
        const state = emitter.cow.?.rc orelse return null;
        if (state.readonly) return null;
        const proof = @import("rc_calls.zig").borrowedIn(emitter.allocator, &state.catalog, emitter.program.functions, callee, @import("runtime_mode.zig").identity()) catch return null;
        return if (proof) |found| found.parameter else null;
    }
};

fn pushed(comptime E: type, self: *E, view: anytype, pc: usize, remaining: usize) bool {
    const code = self.function.scope.instructions;
    if (remaining == 0 or pc >= code.len) return false;
    const stack = self.states[pc] orelse return false;
    return switch (code[pc].op) {
        .load_local => |id| view.local(E, self, @backingInt(id)),
        .get_field => pc != 0 and !self.isBranchTarget(pc) and stack.len != 0 and
            plainRecord(E, self, stack[stack.len - 1]) and pushed(E, self, view, pc - 1, remaining - 1),
        .buffer_operation => |operation| switch (operation.kind) {
            .read => list(E, self, @backingInt(operation.owner)) and
                !semantics.isLiveView(self.program.records, operation.output) and view.local(E, self, @backingInt(operation.owner)),
            // RC-ANCHORED-RANGE-KEY-1: a described `str` slice leaves its
            // receiver text itself in the operand, so it is anchored exactly
            // when that receiver is.
            .slice, .text_tail => self.range_keys.role(pc) == .slice and view.local(E, self, @backingInt(operation.owner)),
            else => false,
        },
        .value_copy => pc != 0 and !self.isBranchTarget(pc) and !copies(E, self, pc) and
            pushed(E, self, view, pc - 1, remaining - 1),
        .call => |target| borrowedCall(E, self, view, pc, target, remaining - 1),
        else => false,
    };
}

/// RC-BORROW-MATCH-1: a direct call whose callee returns a value borrowed
/// from one argument (its borrowed-entry certificate) yields an anchored
/// value when that argument is anchored. RC-BORROW-CALL-ANCHOR-1: binding
/// asks the same question, so a local filled by such a call is bound too.
fn borrowedCall(comptime E: type, self: *E, view: anytype, pc: usize, target: typed.FunctionId, remaining: usize) bool {
    const callee = self.program.functions[@backingInt(target)];
    const parameter = view.parameter(E, self, callee) orelse return false;
    const count = callee.signature.parameter_count;
    const stack = self.states[pc] orelse return false;
    if (parameter >= count or stack.len < count) return false;
    const pusher = argumentPusher(E, self, pc, stack.len - count + parameter) orelse return false;
    return pushed(E, self, view, pusher, remaining);
}

// The instruction that pushed stack index `index` as seen at `pc`, when no
// instruction in between could have replaced it.
fn argumentPusher(comptime E: type, self: *E, pc: usize, index: usize) ?usize {
    const code = self.function.scope.instructions;
    var at = pc;
    var remaining: usize = 64;
    while (at != 0 and remaining != 0) : (remaining -= 1) {
        const previous = at - 1;
        if (self.isBranchTarget(at)) return null;
        const before = self.states[previous] orelse return null;
        const after = self.states[at] orelse return null;
        if (before.len == index and after.len == index + 1) return previous;
        // An instruction pushes at most one value, so one that leaves two
        // values above `index`'s floor never consumed it.
        if (after.len < index + 2 or before.len < index + 1) return null;
        // With `index` on top, only a plain push leaves it in place.
        if (before.len == index + 1) switch (code[previous].op) {
            .load_local, .push_i64, .push_integer, .push_bool, .push_unit => {},
            else => return null,
        };
        at = previous;
    }
    return null;
}

// Whether every definition stores an anchored value: a store (a wider value
// is copied in by its bits, `store` below) or an arm binding out of an
// anchored scrutinee. An elided self copy is none.
fn definitions(comptime E: type, self: *E, view: Working, local: usize) bool {
    const code = self.function.scope.instructions;
    var seen = false;
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local => |id| {
                if (@backingInt(id) != local or selfStore(E, self, pc, local)) continue;
            },
            .switch_variant => |dispatch| {
                var binds = false;
                for (dispatch.arms) |arm| if (arm.slot) |id| {
                    if (@backingInt(id) == local) binds = true;
                };
                if (!binds) continue;
            },
            else => continue,
        }
        if (pc == 0) return false;
        const adjacent = !self.isBranchTarget(pc) and pushed(E, self, view, pc - 1, depth_limit);
        if (!adjacent and !carriedStore(E, self, view, pc)) return false;
        seen = true;
    }
    return seen;
}

// RC-READONLY-ANCHOR-2: a store whose operand was read earlier — the first of
// an inlined call's arguments, stored after the ones pushed above it — takes
// an anchored value when that read is of an anchored local, carried to the
// store as `RC-INTERVAL-ANCHOR-2` carries a list read.
fn carriedStore(comptime E: type, self: *E, view: Working, pc: usize) bool {
    if (self.function.scope.instructions[pc].op != .store_local) return false;
    const analysis = self.ownership orelse return false;
    const stack = self.states[pc] orelse return false;
    if (stack.len == 0) return false;
    const lists: Lists = .{ .quiet = &.{}, .members = @constCast(view.anchored), .roots = &.{}, .operands = analysis.operands, .root = cow.none };
    return readChain(E, self, lists, pc, stack.len - 1);
}

// Whether the ownership analysis keeps the `value_copy` at `pc` a real copy
// (the rule `qbe_value_copy.zig` lowers by; importing it here would cycle).
fn copies(comptime E: type, self: *E, pc: usize) bool {
    const analysis = self.ownership orelse return true;
    return pc >= analysis.copies.len or analysis.copies[pc];
}

// `load_local x; value_copy payload; store_local x` with the copy elided.
fn selfStore(comptime E: type, self: *E, pc: usize, local: usize) bool {
    const code = self.function.scope.instructions;
    if (pc < 2 or pc >= code.len or code[pc].op != .store_local) return false;
    if (code[pc - 2].op != .load_local or @backingInt(code[pc - 2].op.load_local) != local) return false;
    if (code[pc - 1].op != .value_copy or code[pc - 1].op.value_copy.site != .payload) return false;
    return !self.isBranchTarget(pc - 1) and !self.isBranchTarget(pc) and !copies(E, self, pc - 1);
}

// A temporary whose storage no other operation can write or own.
fn candidate(comptime E: type, self: *E, bindings: []const input.Binding, catalog: *shapes.Catalog, roots: []const bool, index: usize) Error!bool {
    if (index < self.function.signature.parameter_count or bindings[index].anchor != null) return false;
    if (@backingInt(bindings[index].storage) != index) return false;
    const ty = self.function.scope.locals[index].ty;
    if (!try counted(catalog, ty) or semantics.isLiveView(self.program.records, ty)) return false;
    // An element-borrowed local (RC-ELEMENT-BORROW-3) holds an address, which
    // this binding is what makes sound; every other address slot is refused.
    if ((self.byReference(index) and !self.borrowsElement(index)) or self.callerStorage(index)) return false;
    if (planned(self.cow.?.plan, roots, index)) return false;
    if (cow.iterationOwner(self.function, index)) return false;
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .ref_local, .move_local => |id| if (@backingInt(id) == index) return false,
        .buffer_operation => |operation| if (@backingInt(operation.owner) == index and !readOnly(operation.kind)) return false,
        else => {},
    };
    return true;
}

// Operations that only read their receiver: an element read, its length, or a
// slice (a new value, or a described range over the receiver's own text).
fn readOnly(kind: @FieldType(@FieldType(Op, "buffer_operation"), "kind")) bool {
    return kind == .read or kind == .length or kind == .slice or kind == .text_tail;
}

// Whether the copy-on-write plan can write or detach `index`: a place, a
// place's parent or box owner, an alias parent, a uniqueness or loop-entry
// target. A copy recorded as an alias of a read-only root is only read.
fn planned(plan: cow.Plan, roots: []const bool, index: usize) bool {
    if (plan.place(index) != null) return true;
    if (index < plan.aliases.len and plan.aliases[index] != cow.none) {
        const parent = plan.aliases[index];
        if (parent >= roots.len or !roots[parent]) return true;
    }
    for (plan.places) |maybe| if (maybe) |found| {
        if (found.parent == index) return true;
        if (found.box) |box| if (box.owner == index) return true;
    };
    for (plan.aliases) |parent| if (parent == index) return true;
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == index or unique.alias == index) return true;
        if (site.unique_field) |found| if (found.parent == index) return true;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == index) return true;
    return false;
}

// Stores, moves, references and pattern bindings all write a local's storage.
fn written(function: bytecode.Function, index: usize) bool {
    for (function.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .ref_local, .move_local => |id| if (@backingInt(id) == index) return true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == index) return true;
        },
        else => {},
    };
    return false;
}

fn counted(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    const shape = catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    return shape.counted and !shape.unique_drop;
}

// A value record read in place: not a class body, collection or box.
fn plainRecord(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.isRecord() and !record.managed and !record.isCollection();
}

fn list(comptime E: type, self: *E, local: usize) bool {
    const ty = self.function.scope.locals[local].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .list and !record.collection.box;
}

/// RC-INTERVAL-ANCHOR-1: a list temporary filled straight from a field chain
/// of a `mut` record parameter (`load_local r; get_field...; store_local t`)
/// and used only for its length and element reads is borrowed from
/// that parameter's storage when no instruction in its live range writes the
/// parameter: no store, move, reference (`mut` argument) or place write
/// rooted in it, and no arena boundary. The caller owns the parameter, so a
/// call that does not receive it can neither replace nor release the list.
pub fn bindIntervals(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog, contract: model.CallContract) Error!void {
    const code = self.function.scope.instructions;
    const count = self.function.scope.locals.len;
    if (code.len > code_limit or count > local_limit) return;
    var budget: usize = analysis_budget;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .store_local or pc == 0 or self.states[pc] == null) continue;
        const local = @backingInt(instruction.op.store_local);
        const root_local = chainRoot(E, self, pc - 1) orelse continue;
        if (root_local >= contract.parameters.len or contract.parameters[root_local] != .caller_storage) continue;
        if (aliasable(E, self, contract, root_local)) continue;
        // Each candidate scans the function a few times.
        if (budget < 4 * code.len) return;
        budget -= 4 * code.len;
        if (!try counted(catalog, self.function.scope.locals[root_local].ty)) continue;
        if (!try candidate(E, self, bindings, catalog, &.{}, local) or !list(E, self, local)) continue;
        if (!try intervalUses(E, self, catalog, local, pc)) continue;
        if (!intervalQuiet(E, self, catalog, local, root_local)) continue;
        bindings[local].anchor = .{ .storage = bindings[root_local].storage };
    }
}

/// Whether the `get_field` at `pc` belongs to the field chain that fills an
/// interval-anchored temporary, so it publishes no token.
pub fn intervalChain(comptime E: type, self: *E, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (code[pc].op != .get_field) return false;
    var at = pc + 1;
    while (at < code.len and code[at].op == .get_field) : (at += 1) {
        if (self.isBranchTarget(at)) return false;
    }
    if (at >= code.len or code[at].op != .store_local or self.isBranchTarget(at)) return false;
    const local = @backingInt(code[at].op.store_local);
    const state = self.cow.?.rc orelse return false;
    const ownership = state.plan.locals.entry[local].ownership;
    if (ownership != .borrowed or ownership.borrowed != .storage) return false;
    const root_local = chainRoot(E, self, at - 1) orelse return false;
    if (@backingInt(ownership.borrowed.storage) != root_local) return false;
    return root_local < state.contract.parameters.len and state.contract.parameters[root_local] == .caller_storage;
}

// The local a `load_local r; get_field...` chain ending at `pc` starts from.
fn chainRoot(comptime E: type, self: *E, pc: usize) ?usize {
    const code = self.function.scope.instructions;
    var at = pc;
    var steps: usize = 0;
    while (code[at].op == .get_field) : (steps += 1) {
        if (at == 0 or steps == depth_limit or self.isBranchTarget(at)) return null;
        const stack = self.states[at] orelse return null;
        if (stack.len == 0 or !plainRecord(E, self, stack[stack.len - 1])) return null;
        at -= 1;
    }
    if (steps == 0 or code[at].op != .load_local) return null;
    return @backingInt(code[at].op.load_local);
}

// The one store fills the temporary; every other use reads its length or an
// element.
fn intervalUses(comptime E: type, self: *E, catalog: *shapes.Catalog, local: usize, fill: usize) Error!bool {
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local, .load_local => |id| if (@backingInt(id) == local and pc != fill) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == local) return false;
        },
        .buffer_operation => |operation| if (@backingInt(operation.owner) == local) {
            if (operation.kind == .length) continue;
            if (operation.kind != .read) return false;
            // A counted element takes its own loan as it is read, before
            // anything else runs, so only unique resources are refused.
            const shape = catalog.get(operation.output) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
            if (shape.unique_drop) return false;
        },
        else => {},
    };
    return true;
}

// No instruction while the temporary is live writes the root or crosses an
// arena boundary.
fn intervalQuiet(comptime E: type, self: *E, catalog: *shapes.Catalog, local: usize, root_local: usize) bool {
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (!self.live.?.before(pc, local) and !self.live.?.after(pc, local)) continue;
        if (instruction.op == .begin_arena or instruction.op == .end_arena) return false;
        if (writes(E, self, catalog, pc, root_local)) return false;
    }
    return true;
}

// Whether a place or alias chain starting at `local` reaches `root_local`.
fn rooted(plan: cow.Plan, local: usize, root_local: usize) bool {
    var at = local;
    var remaining = plan.aliases.len + plan.places.len + 1;
    while (remaining != 0) : (remaining -= 1) {
        if (at == root_local) return true;
        if (plan.place(at)) |place| {
            at = place.parent;
        } else if (at < plan.aliases.len and plan.aliases[at] != cow.none) {
            at = plan.aliases[at];
        } else return false;
    }
    return true;
}

/// RC-OPERAND-ANCHOR-1: a field read out of a `mut` record parameter
/// (`load_local r; get_field...`) publishes no loan when straight-line code
/// consumes it before anything could write the parameter: no store, move,
/// reference (`mut` argument), binding or place write rooted in it, no arena
/// boundary and no branch between the read and its consumer. A consumer
/// that needs an owner copies from the bits; a call that receives the value
/// borrows it while the caller keeps the parameter unchanged.
pub fn operandInterval(comptime E: type, self: *E, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (code[pc].op != .get_field) return false;
    const state = self.cow.?.rc orelse return false;
    const root_local = chainRoot(E, self, pc) orelse return false;
    if (root_local >= state.contract.parameters.len or state.contract.parameters[root_local] != .caller_storage) return false;
    if (aliasable(E, self, state.contract, root_local)) return false;
    const pushed_depth = (self.states[pc] orelse return false).len - 1;
    var at = pc + 1;
    var remaining: usize = 256;
    while (at < code.len and remaining != 0) : ({
        at += 1;
        remaining -= 1;
    }) {
        if (self.isBranchTarget(at)) return false;
        const before = self.states[at] orelse return false;
        if (before.len <= pushed_depth) return false;
        const after = if (at + 1 < self.states.len) self.states[at + 1] else null;
        var consumed = if (after) |stack| stack.len <= pushed_depth else true;
        // A direct call consumes its arguments and pushes a new result.
        if (code[at].op == .call) {
            const count = self.program.functions[@backingInt(code[at].op.call)].signature.parameter_count;
            if (before.len - pushed_depth <= count) consumed = true;
        }
        // RC-OPERAND-ANCHOR-2: a length read replaces the value on top with
        // its scalar length, consuming it at the same stack height.
        if (code[at].op == .array_length and before.len == pushed_depth + 1) consumed = true;
        if (writes(E, self, &state.catalog, at, root_local)) return false;
        switch (code[at].op) {
            .jump, .jump_if_false, .switch_variant, .try_result, .begin_arena, .end_arena => return false,
            else => {},
        }
        if (consumed) return true;
    }
    return false;
}

/// RC-INTERVAL-ANCHOR-3: were two `mut` arguments to name one caller value, or
/// one to sit inside the other (`f(mut r, mut r)`, `f(mut r, mut r.items)`,
/// `f(mut xs, mut xs[0])`), a write through another writable parameter whose
/// type equals, holds or is held by the root's could replace or release what
/// a read out of the root borrowed, so such a root anchors nothing
/// (RC-INTERVAL-ANCHOR-4 adds the containment cases). MUT-EXCLUSIVE-1 now
/// rejects those calls; this refusal stays as defense in depth.
fn aliasable(comptime E: type, self: *E, contract: model.CallContract, root_local: usize) bool {
    const ty = self.function.scope.locals[root_local].ty;
    for (contract.parameters, 0..) |mode, index| {
        if (index == root_local or (mode != .caller_storage and mode != .mutable_payload)) continue;
        const other = self.function.scope.locals[index].ty;
        if (holds(E, self, other, ty) or holds(E, self, ty, other)) return true;
    }
    return false;
}

// Whether a value of type `outer` can hold one of type `inner`, itself
// included: through fields, collection elements, fixed arrays, variant
// payloads or a domain's base. A walk that outgrows its budget answers yes.
fn holds(comptime E: type, self: *E, outer: typed.Type, inner: typed.Type) bool {
    var pending: [256]typed.Type = undefined;
    var seen: [256]typed.Type = undefined;
    var count: usize = 1;
    var visited: usize = 0;
    pending[0] = outer;
    while (count != 0) {
        count -= 1;
        const current = pending[count];
        if (current == inner) return true;
        if (for (seen[0..visited]) |previous| {
            if (previous == current) break true;
        } else false) continue;
        if (visited == seen.len) return true;
        seen[visited] = current;
        visited += 1;
        if (!current.isAggregate()) continue;
        const record = self.program.records[current.recordIndex()];
        var children: [4]?typed.Type = .{ record.shape.buffer, record.shape.domain, if (record.shape.array) |array| array.element else null, null };
        for (&children) |*child| if (child.*) |ty| {
            if (count == pending.len) return true;
            pending[count] = ty;
            count += 1;
        };
        if (record.shape.variants) |variants| for (variants.cases) |case| if (case.payload) |ty| {
            if (count == pending.len) return true;
            pending[count] = ty;
            count += 1;
        };
        for (record.fields) |field| {
            if (count == pending.len) return true;
            pending[count] = field.ty;
            count += 1;
        }
    }
    return false;
}

// Whether the instruction at `pc` can write the root's storage. Storing back
// an update of count-free fields of the root, or passing it `mut` to a call
// that only does that, changes no counted field (RC-PLAIN-UPDATE-CALL-1).
fn writes(comptime E: type, self: *E, catalog: *shapes.Catalog, pc: usize, root_local: usize) bool {
    const plan = self.cow.?.plan;
    const op = self.function.scope.instructions[pc].op;
    const program: plain.Program = .{ .catalog = catalog, .functions = self.program.functions };
    switch (op) {
        .store_local => |id| if (@backingInt(id) == root_local and !plain.plainStore(program, self.function, pc)) return true,
        .ref_local => |id| if (@backingInt(id) == root_local and !plain.plainCall(program, self.function, pc)) return true,
        .move_local => |id| if (@backingInt(id) == root_local) return true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == root_local) return true;
        },
        else => {},
    }
    const site = plan.at(pc);
    for (site.unique) |unique| {
        if (rooted(plan, unique.local, root_local)) return true;
        if (unique.alias != cow.none and rooted(plan, unique.alias, root_local)) return true;
    }
    if (site.unique_field) |place| if (rooted(plan, place.parent, root_local)) return true;
    if (site.fill and op == .store_local and rooted(plan, @backingInt(op.store_local), root_local)) return true;
    return false;
}

/// RC-INTERVAL-ANCHOR-2: a list the frame can write — a `mut` list parameter
/// or a named list local — still anchors the values read out of it while no
/// instruction writes it. Bind every local whose definitions all store a
/// value read (through element reads of it or of such a local, plain field
/// reads and elided copies) out of one such root, when no instruction that
/// can write the root runs while the local is live (and a named root stays
/// live with it), as borrowed from the root's storage. The root is written by a store, move, drop, reference or
/// arm binding of it, a mutating operation or copy-on-write check on a local
/// rooted in it, a call handed a `mut` reference into it, an arena boundary,
/// and — for a named local, which the frame releases — a return or a last
/// read that may hand its list to a new owner. A root is
/// also refused outright when any instruction that writes it can run with a
/// value read out of it, or of unknown origin, on the operand stack, so every
/// read out of an accepted root, and out of its bound locals, publishes no
/// token. Answers the per-local table: the root for a bound local, the root
/// itself for an accepted root, `cow.none` elsewhere.
pub fn bindLists(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog, contract: model.CallContract) Error![]const u32 {
    const code = self.function.scope.instructions;
    const count = self.function.scope.locals.len;
    const table = try self.allocator.alloc(u32, count);
    @memset(table, cow.none);
    if (code.len > code_limit or count > local_limit) return table;
    const analysis = self.ownership orelse return table;
    const lists: Lists = .{
        .quiet = try self.allocator.alloc(bool, code.len),
        .members = try self.allocator.alloc(bool, count),
        .roots = try self.allocator.alloc(bool, count),
        .operands = analysis.operands,
    };
    defer {
        self.allocator.free(lists.quiet);
        self.allocator.free(lists.members);
        self.allocator.free(lists.roots);
    }
    var budget: usize = analysis_budget;
    for (0..count) |root_local| {
        if (table[root_local] != cow.none or !try intervalRoot(E, self, bindings, catalog, contract, root_local)) continue;
        if (budget < 4 * code.len) break;
        budget -= 4 * code.len;
        var scope = lists;
        scope.root = root_local;
        @memset(lists.roots, false);
        lists.roots[root_local] = true;
        for (lists.quiet, 0..) |*flag, pc| flag.* = !listWrite(E, self, catalog, pc, root_local);
        for (lists.members, 0..) |*flag, index| {
            flag.* = index != root_local and table[index] == cow.none and !text(E, self, self.function.scope.locals[index].ty) and
                try candidate(E, self, bindings, catalog, lists.roots, index);
        }
        if (!try settleMembers(E, self, scope, &budget)) continue;
        if (!try viewsQuiet(E, self, catalog, scope)) continue;
        table[root_local] = @intCast(root_local);
        for (lists.members, 0..) |flag, index| if (flag) {
            table[index] = @intCast(root_local);
            bindings[index].anchor = .{ .storage = bindings[root_local].storage };
        };
    }
    return table;
}

/// One interval root's working tables: where it is quiet, which candidates
/// are still bound, the roots `candidate` may alias and the operand sources.
const Lists = struct {
    quiet: []bool,
    members: []bool,
    roots: []bool,
    operands: []const ?[]const @import("ownership.zig").Source,
    root: usize = 0,
};

// Drop members until every one's definitions are read out of the root or a
// member and none is live where the root can be written.
fn settleMembers(comptime E: type, self: *E, lists: Lists, budget: *usize) Error!bool {
    const code = self.function.scope.instructions;
    var changed = true;
    while (changed) {
        changed = false;
        for (lists.members, 0..) |*flag, index| {
            if (!flag.*) continue;
            if (budget.* < 2 * code.len) return false;
            budget.* -= 2 * code.len;
            if (quietLive(E, self, lists, index) and memberDefinitions(E, self, lists, index)) continue;
            flag.* = false;
            changed = true;
        }
    }
    return true;
}

fn intervalRoot(comptime E: type, self: *E, bindings: []const input.Binding, catalog: *shapes.Catalog, contract: model.CallContract, index: usize) Error!bool {
    const local = self.function.scope.locals[index];
    if (!list(E, self, index) or !try counted(catalog, local.ty)) return false;
    // A text list is left to the dictionary key certificate (RC-DICTIONARY-KEY-1),
    // which lends its elements to a dictionary tail on its own terms.
    if (text(E, self, self.program.records[local.ty.recordIndex()].shape.buffer orelse return false)) return false;
    if (bindings[index].anchor != null or @backingInt(bindings[index].storage) != index) return false;
    if (self.byReference(index) or self.callerStorage(index)) return false;
    // RC-INTERVAL-ANCHOR-4: a `mut` list another writable parameter may name,
    // or hold, or sit inside, is written by that parameter too.
    if (index < self.function.signature.parameter_count) return index < contract.parameters.len and
        contract.parameters[index] == .mutable_payload and !aliasable(E, self, contract, index);
    if (local.usage.temporary or cow.iterationOwner(self.function, index)) return false;
    const plan = self.cow.?.plan;
    if (plan.place(index) != null) return false;
    return index >= plan.aliases.len or plan.aliases[index] == cow.none;
}

fn text(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.managed and record.collection.kind == .string;
}

// Whether the instruction at `pc` can write the list `root_local` holds.
fn listWrite(comptime E: type, self: *E, catalog: *shapes.Catalog, pc: usize, root_local: usize) bool {
    if (self.states[pc] == null) return false;
    const plan = self.cow.?.plan;
    switch (self.function.scope.instructions[pc].op) {
        .begin_arena, .end_arena => return true,
        .ret, .try_result => if (root_local >= self.function.signature.parameter_count) return true,
        .store_local, .move_local, .drop_local => |id| if (@backingInt(id) == root_local) return true,
        // A last read of a named root may hand its list to a new owner, which
        // could then write it.
        .load_local => |id| if (@backingInt(id) == root_local and root_local >= self.function.signature.parameter_count and moved(E, self, pc)) return true,
        .ref_local => |id| if (rootedIn(E, self, @backingInt(id), root_local)) return true,
        .buffer_operation => |operation| if (rootedIn(E, self, @backingInt(operation.owner), root_local) and
            (operation.kind.mutates() or @import("ownership_model.zig").writesReceiver(operation.kind))) return true,
        .call, .invoke => if (mutableArgument(E, self, pc, root_local)) return true,
        else => {},
    }
    for (plan.entry(pc)) |check| if (rootedIn(E, self, check.local, root_local)) return true;
    return writes(E, self, catalog, pc, root_local);
}

fn moved(comptime E: type, self: *E, pc: usize) bool {
    const analysis = self.ownership orelse return true;
    return pc >= analysis.moves.len or analysis.moves[pc];
}

// A local whose value is, or is read out of, `root_local`'s list: a place or
// alias chain reaching it, or a temporary whose one store captures it.
fn rootedIn(comptime E: type, self: *E, local: usize, root_local: usize) bool {
    var at = local;
    var remaining: usize = depth_limit;
    while (remaining != 0) : (remaining -= 1) {
        if (at == root_local or rooted(self.cow.?.plan, at, root_local)) return true;
        at = captured(E, self, at) orelse return false;
    }
    return true;
}

// The local a temporary's single `load_local x; store_local t` captures.
fn captured(comptime E: type, self: *E, local: usize) ?usize {
    const code = self.function.scope.instructions;
    if (local >= self.function.scope.locals.len or !self.function.scope.locals[local].usage.temporary) return null;
    var source: ?usize = null;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == local) {
            if (pc == 0 or code[pc - 1].op != .load_local or source != null) return null;
            source = @backingInt(code[pc - 1].op.load_local);
        },
        .move_local, .ref_local => |id| if (@backingInt(id) == local) return null,
        else => {},
    };
    return source;
}

// Whether a call at `pc` can write `root_local`'s list: it is handed a `mut`
// reference into it, the callee mutates the parameter an argument rooted in
// it fills (a list crosses as its payload), or a callback receives one.
fn mutableArgument(comptime E: type, self: *E, pc: usize, root_local: usize) bool {
    const analysis = self.ownership orelse return true;
    const stack = if (pc < analysis.operands.len) analysis.operands[pc] orelse return true else return true;
    const code = self.function.scope.instructions;
    const writes_all = code[pc].op == .invoke;
    const count = operand_sources.popsOf(self.program, code[pc].op);
    if (count > stack.len) return true;
    const base = stack.len - count;
    for (stack, 0..) |source, slot| {
        if (source.origin != .local or source.read == cow.none or source.read >= code.len) continue;
        if (!rootedIn(E, self, source.local, root_local)) continue;
        if (code[source.read].op == .ref_local or (slot >= base and (writes_all or mutatedParameter(E, self, code[pc].op, slot - base)))) return true;
    }
    return false;
}

fn mutatedParameter(comptime E: type, self: *E, op: Op, position: usize) bool {
    const target = switch (op) {
        .call => |id| id,
        else => return true,
    };
    return @import("ownership_model.zig").writesParameter(self.program.functions[@backingInt(target)], position);
}

// No write of the root runs while `local` is live, and a named root outlives
// it: once the root is dead its lowering may hand its token to a capture.
fn quietLive(comptime E: type, self: *E, lists: Lists, local: usize) bool {
    const live = self.live orelse return false;
    const named = lists.root >= self.function.signature.parameter_count;
    for (lists.quiet, 0..) |quiet, pc| {
        const before = live.before(pc, local);
        const after = live.after(pc, local);
        if (!quiet and (before or after)) return false;
        if (!named) continue;
        const outlived_before = !before or live.before(pc, lists.root);
        const outlived_after = !after or live.after(pc, lists.root);
        if (!outlived_before or !outlived_after) return false;
    }
    return true;
}

// Every store into `local` takes a value read out of the root or a member;
// pattern bindings are not bound.
fn memberDefinitions(comptime E: type, self: *E, lists: Lists, local: usize) bool {
    const code = self.function.scope.instructions;
    var seen = false;
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local => |id| {
                if (@backingInt(id) != local or selfStore(E, self, pc, local)) continue;
                const stack = self.states[pc].?;
                if (stack.len == 0 or !readChain(E, self, lists, pc, stack.len - 1)) return false;
                seen = true;
            },
            .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                if (arm.slot) |id| if (@backingInt(id) == local) return false;
            },
            else => {},
        }
    }
    return seen;
}

// Whether operand `index` on entry to `consumer` is a value read out of the
// root or a member, carried there only by plain field reads, elided copies
// and domain wraps, on a forward region no branch enters from outside.
fn readChain(comptime E: type, self: *E, lists: Lists, consumer: usize, index: usize) bool {
    const code = self.function.scope.instructions;
    const stack = if (consumer < lists.operands.len) lists.operands[consumer] orelse return false else return false;
    if (index >= stack.len) return false;
    const source = stack[index];
    if (source.origin != .local or source.read == cow.none or source.read >= consumer) return false;
    const read = source.read;
    const owner = source.local;
    if (owner != lists.root and !(owner < lists.members.len and lists.members[owner])) return false;
    switch (code[read].op) {
        .load_local => |id| if (@backingInt(id) != owner) return false,
        .buffer_operation => |operation| {
            if (operation.kind != .read or @backingInt(operation.owner) != owner or !list(E, self, owner)) return false;
            if (semantics.isLiveView(self.program.records, operation.output)) return false;
        },
        else => return false,
    }
    const at_read = self.states[read] orelse return false;
    if (at_read.len - operand_sources.popsOf(self.program, code[read].op) != index) return false;
    return carried(E, self, read, consumer, index);
}

// No branch enters (read, consumer] from outside or leaves it backwards, and
// every instruction in between that writes operand `index` only projects it.
fn carried(comptime E: type, self: *E, read: usize, consumer: usize, index: usize) bool {
    const code = self.function.scope.instructions;
    for (code, 0..) |instruction, pc| {
        const inside = pc > read and pc < consumer;
        var buffer: [2]usize = undefined;
        for (operand_sources.branchTargets(instruction.op, &buffer)) |target| if (!regionEdge(inside, pc, target, .{ read, consumer })) return false;
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (!regionEdge(inside, pc, arm.target, .{ read, consumer })) return false;
        };
    }
    for (read + 1..consumer) |pc| {
        const before = self.states[pc] orelse continue;
        const op = code[pc].op;
        const pops = operand_sources.popsOf(self.program, op);
        if (pops > before.len) return false;
        const floor = before.len - pops;
        if (floor > index) continue;
        if (!operand_sources.pushes(op) or floor != index or before.len != index + 1) return false;
        switch (op) {
            .get_field => if (!plainRecord(E, self, before[index])) return false,
            .value_copy => if (copies(E, self, pc)) return false,
            .wrap_domain, .unwrap_domain => {},
            else => return false,
        }
    }
    return true;
}

// A branch inside the region only goes forward; one outside never enters it.
fn regionEdge(inside: bool, pc: usize, target: usize, region: [2]usize) bool {
    if (inside) return target > pc;
    return target <= region[0] or target > region[1];
}

// No instruction that can write the root runs with a value read out of it,
// or of a member, or of unknown origin, on its operand stack.
fn viewsQuiet(comptime E: type, self: *E, catalog: *shapes.Catalog, lists: Lists) Error!bool {
    for (lists.quiet, 0..) |quiet, pc| {
        if (quiet) continue;
        const types = self.states[pc] orelse continue;
        const stack = if (pc < lists.operands.len) lists.operands[pc] orelse return false else return false;
        if (stack.len != types.len) return false;
        for (stack, types) |source, ty| {
            if (!try counted(catalog, ty)) continue;
            switch (source.origin) {
                .fresh => {},
                .unknown => return false,
                .local => {
                    if (source.local == lists.root and source.part != .whole) return false;
                    if (source.local < lists.members.len and lists.members[source.local]) return false;
                },
            }
        }
    }
    return true;
}

/// RC-INTERVAL-ANCHOR-2: the root `local` is bound to by `bindLists`, or
/// `cow.none`. A root itself answers its own index.
fn intervalRootOf(comptime E: type, self: *E, local: usize) u32 {
    const state = self.cow.?.rc orelse return cow.none;
    const table = state.plan.records.intervals;
    return if (local < table.len) table[local] else cow.none;
}
