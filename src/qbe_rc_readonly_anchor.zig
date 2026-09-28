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
const plain = @import("rc_plain_updates.zig");
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

/// Store an anchored value wider than one word into its anchored local by
/// its bits, with no token; a one-word value takes the borrowed store of
/// `qbe_rc_read_loans.zig`. Returns false for any other store.
pub fn store(comptime E: type, self: *E, local: usize, operand: usize) Error!bool {
    const ty = self.function.scope.locals[local].ty;
    if (self.isScalar(ty) or !anchoredLocal(E, self, local) or local < self.function.signature.parameter_count) return false;
    const source = try self.load("s", operand);
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
        .buffer_operation => |operation| switch (operation.kind) {
            .read => list(E, self, @backingInt(operation.owner)) and
                !semantics.isLiveView(self.program.records, operation.output) and view.local(E, self, @backingInt(operation.owner)),
            // RC-ANCHORED-RANGE-KEY-1: a described `str` slice leaves its
            // receiver text itself in the operand, so it is anchored exactly
            // when that receiver is.
            .slice => self.range_keys.role(pc) == .slice and view.local(E, self, @backingInt(operation.owner)),
            else => false,
        },
        .value_copy => pc != 0 and !self.isBranchTarget(pc) and !copies(E, self, pc) and
            pushed(E, self, view, pc - 1, remaining - 1),
        .call => |target| @TypeOf(view) == Emitted and borrowedCall(E, self, view, pc, target, remaining - 1),
        else => false,
    };
}

/// RC-BORROW-MATCH-1: a direct call whose callee returns a value borrowed
/// from one argument (its borrowed-entry certificate) yields an anchored
/// value when that argument is anchored.
fn borrowedCall(comptime E: type, self: *E, view: anytype, pc: usize, target: typed.FunctionId, remaining: usize) bool {
    const state = self.cow.?.rc orelse return false;
    if (state.readonly) return false;
    const callee = self.program.functions[@backingInt(target)];
    const proof = @import("rc_calls.zig").borrowedIn(self.allocator, &state.catalog, self.program.functions, callee, @import("runtime_mode.zig").identity()) catch return false;
    const certificate = proof orelse return false;
    const count = callee.signature.parameter_count;
    const stack = self.states[pc] orelse return false;
    if (certificate.parameter >= count or stack.len < count) return false;
    const pusher = argumentPusher(E, self, pc, stack.len - count + certificate.parameter) orelse return false;
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
fn candidate(comptime E: type, self: *E, bindings: []const input.Binding, catalog: *shapes.Catalog, roots: []const bool, index: usize) Error!bool {
    if (index < self.function.signature.parameter_count or bindings[index].anchor != null) return false;
    if (@backingInt(bindings[index].storage) != index) return false;
    const ty = self.function.scope.locals[index].ty;
    if (!try counted(catalog, ty) or semantics.isLiveView(self.program.records, ty)) return false;
    if (self.byReference(index) or self.callerStorage(index)) return false;
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
    return kind == .read or kind == .length or kind == .slice;
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
        if (writes(E, self, &state.catalog, at, root_local)) return false;
        switch (code[at].op) {
            .jump, .jump_if_false, .switch_variant, .try_result, .begin_arena, .end_arena => return false,
            else => {},
        }
        if (consumed) return true;
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
