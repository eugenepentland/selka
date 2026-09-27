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
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const input = @import("rc_input.zig");
const model = @import("rc_model.zig");
const shapes = @import("rc_shape.zig");
const cow = @import("cow_plan.zig");
const semantics = @import("value_semantics.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Analysis failures shared with the RC emitter.
pub const Error = error{ InternalError, OutOfMemory, WriteFailed, SourceError };

/// The deepest read chain one value looks back through.
const depth_limit = 16;
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
    if (code.len > 4096 or count > 1024) return;
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
    for (anchored, 0..) |*flag, index| flag.* = roots[index] or try candidate(E, self, bindings, catalog, index);
    var changed = true;
    var budget: usize = analysis_budget;
    while (changed) {
        changed = false;
        for (anchored, 0..) |*flag, index| {
            if (!flag.* or roots[index]) continue;
            if (budget < code.len) return;
            budget -= code.len;
            if (definitions(E, self, Working{ .anchored = anchored }, index)) continue;
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
    if (local < state.contract.parameters.len) return root(E, self, local);
    const ownership = state.plan.locals.entry[local].ownership;
    if (ownership != .borrowed or ownership.borrowed != .storage) return false;
    const anchor = @backingInt(ownership.borrowed.storage);
    return anchor < state.contract.parameters.len and root(E, self, anchor);
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
    fn local(self: Working, comptime E: type, emitter: *E, index: usize) bool {
        _ = emitter;
        return index < self.anchored.len and self.anchored[index];
    }
};
// The emission-time view reads the finished plan.
const Emitted = struct {
    fn local(_: Emitted, comptime E: type, emitter: *E, index: usize) bool {
        return anchoredLocal(E, emitter, index);
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
        .buffer_operation => |operation| operation.kind == .read and list(E, self, @backingInt(operation.owner)) and
            !semantics.isLiveView(self.program.records, operation.output) and view.local(E, self, @backingInt(operation.owner)),
        .value_copy => pc != 0 and !self.isBranchTarget(pc) and !copies(E, self, pc) and
            pushed(E, self, view, pc - 1, remaining - 1),
        else => false,
    };
}

// Whether every definition stores an anchored value: a pointer-sized store or
// an arm binding out of an anchored scrutinee. An elided self copy is none.
fn definitions(comptime E: type, self: *E, view: Working, local: usize) bool {
    const code = self.function.scope.instructions;
    var seen = false;
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local => |id| {
                if (@backingInt(id) != local or selfStore(E, self, pc, local)) continue;
                if (!self.isScalar(self.function.scope.locals[local].ty)) return false;
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
        if (pc == 0 or self.isBranchTarget(pc)) return false;
        if (!pushed(E, self, view, pc - 1, depth_limit)) return false;
        seen = true;
    }
    return seen;
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
fn candidate(comptime E: type, self: *E, bindings: []const input.Binding, catalog: *shapes.Catalog, index: usize) Error!bool {
    if (index < self.function.signature.parameter_count or bindings[index].anchor != null) return false;
    if (@backingInt(bindings[index].storage) != index) return false;
    const ty = self.function.scope.locals[index].ty;
    if (!try counted(catalog, ty) or semantics.isLiveView(self.program.records, ty)) return false;
    if (self.byReference(index) or self.callerStorage(index)) return false;
    const plan = self.cow.?.plan;
    if (plan.place(index) != null or (index < plan.aliases.len and plan.aliases[index] != cow.none)) return false;
    for (plan.places) |maybe| if (maybe) |found| {
        if (found.parent == index) return false;
        if (found.box) |box| if (box.owner == index) return false;
    };
    for (plan.aliases) |parent| if (parent == index) return false;
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == index or unique.alias == index) return false;
        if (site.unique_field) |found| if (found.parent == index) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == index) return false;
    if (cow.iterationOwner(self.function, index)) return false;
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .ref_local, .move_local => |id| if (@backingInt(id) == index) return false,
        .buffer_operation => |operation| if (@backingInt(operation.owner) == index and operation.kind != .read and operation.kind != .length) return false,
        else => {},
    };
    return true;
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
/// and used only for its length and plain element reads is borrowed from
/// that parameter's storage when no instruction in its live range writes the
/// parameter: no store, move, reference (`mut` argument) or place write
/// rooted in it, and no arena boundary. The caller owns the parameter, so a
/// call that does not receive it can neither replace nor release the list.
pub fn bindIntervals(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog, contract: model.CallContract) Error!void {
    const code = self.function.scope.instructions;
    const count = self.function.scope.locals.len;
    if (code.len > 4096 or count > 1024) return;
    var budget: usize = analysis_budget;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .store_local or pc == 0 or self.states[pc] == null) continue;
        const local = @backingInt(instruction.op.store_local);
        const root_local = chainRoot(E, self, pc - 1) orelse continue;
        if (root_local >= contract.parameters.len or contract.parameters[root_local] != .caller_storage) continue;
        // Each candidate scans the function a few times.
        if (budget < 4 * code.len) return;
        budget -= 4 * code.len;
        if (!try counted(catalog, self.function.scope.locals[root_local].ty)) continue;
        if (!try candidate(E, self, bindings, catalog, local) or !list(E, self, local)) continue;
        if (!try intervalUses(E, self, catalog, local, pc)) continue;
        if (!intervalQuiet(E, self, local, root_local)) continue;
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

// The one store fills the temporary; every other use reads its length or a
// plain element that owns nothing.
fn intervalUses(comptime E: type, self: *E, catalog: *shapes.Catalog, local: usize, store: usize) Error!bool {
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local, .load_local => |id| if (@backingInt(id) == local and pc != store) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == local) return false;
        },
        .buffer_operation => |operation| if (@backingInt(operation.owner) == local) {
            if (operation.kind == .length) continue;
            if (operation.kind != .read) return false;
            const shape = catalog.get(operation.output) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
            if (shape.counted or shape.unique_drop) return false;
        },
        else => {},
    };
    return true;
}

// No instruction while the temporary is live writes the root or crosses an
// arena boundary.
fn intervalQuiet(comptime E: type, self: *E, local: usize, root_local: usize) bool {
    const plan = self.cow.?.plan;
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (!self.live.?.before(pc, local) and !self.live.?.after(pc, local)) continue;
        if (instruction.op == .begin_arena or instruction.op == .end_arena) return false;
        if (writes(plan, instruction.op, pc, root_local)) return false;
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
    const pushed_depth = (self.states[pc] orelse return false).len - 1;
    const plan = self.cow.?.plan;
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
        const consumed = if (after) |stack| stack.len <= pushed_depth else true;
        if (writes(plan, code[at].op, at, root_local)) return false;
        switch (code[at].op) {
            .jump, .jump_if_false, .switch_variant, .try_result, .begin_arena, .end_arena => return false,
            else => {},
        }
        if (consumed) return true;
    }
    return false;
}

// Whether the instruction at `pc` can write the root's storage.
fn writes(plan: cow.Plan, op: Op, pc: usize, root_local: usize) bool {
    switch (op) {
        .store_local, .ref_local, .move_local => |id| if (@backingInt(id) == root_local) return true,
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
