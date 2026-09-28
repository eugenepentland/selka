//! Which ordinary locals may hold the address of a value that lives elsewhere.
//!
//! `QBE-AGGREF-1` gave a read-only aggregate *parameter* the caller's address
//! instead of a copy. The same reasoning reaches a local a single instruction
//! fills from storage this frame can name: the loop variable of `for x in xs`,
//! the `x` of `x = xs[i]`, and the `x` of `x = f(...)` for a record-returning
//! `f`. The slot then holds one word and every read of `x` reaches the value
//! where it already is, so the whole-record copy the store used to make — and
//! the per-pc aggregate scratch it came out of — disappear.
//!
//! Two kinds of storage can be named, and they need different proofs.
//!
//! *Stable* storage is the frame's own: the buffer a record-returning call
//! leaves its result in. QBE allocates one return pad per call site in the
//! caller's entry block, and the LLVM adapter reserves one `alloca` per call
//! instruction the same way, so the buffer lives as long as the frame and is
//! rewritten only when that same call site runs again — which re-runs the store
//! first. Nothing else in the function can reach it, so no live-range proof is
//! needed at all.
//!
//! *Borrowed* storage is a managed list's backing. The collector never moves an
//! object, so the address stays good while the receiver is reachable and its
//! storage is neither reallocated nor overwritten. That holds only over a run
//! of instructions which can neither call, allocate, release nor mutate, so the
//! borrow is claimed only when every instruction that can run while it is live
//! is inert — and "live" is answered over the real control-flow graph, not over
//! a straight-line window.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const arena_lower = @import("qbe_arena.zig");
const runtime = @import("runtime_mode.zig");

/// Failures raised while deciding which locals name their value in place.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// What a local's slot holds.
///
/// `value` — the value itself, or an address into storage that stays valid and
/// stays this local's value for as long as the local lives: a caller's argument,
/// a payload inside a scrutinee, a call's own result buffer. The collector reads
/// such a slot as a root exactly as it reads a by-value one.
///
/// `element` — an address into a managed list's backing storage, valid only
/// across the inert run the borrow was proved over. The collector never reads
/// it: nothing can collect inside that run, and outside it the local is dead,
/// so rooting it would only risk tracing storage that has since been
/// reallocated or swept.
pub const Borrow = enum { none, value, element };

/// Bind the borrow analysis to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Mark every local that may hold an address instead of its value.
        /// `flags` is the emitter's per-local by-reference table, already
        /// carrying the parameters and match bindings claimed before this runs;
        /// a slot another rule claimed is left alone.
        pub fn claim(self: *E, flags: []Borrow) Error!void {
            return claimLocals(E, self, flags);
        }
    };
}

/// Where a candidate borrow's address comes from and what it names.
const Source = struct {
    /// The type of the value the address names.
    ty: typed.Type,
    /// Whether the storage is this frame's own — a call's result buffer — so
    /// nothing outside the producing instruction can invalidate it.
    stable: bool,
    /// RC-ELEMENT-BORROW-3: an element of a never-written read-only list
    /// parameter, which the caller keeps alive and unchanged for the whole
    /// activation, so the address needs no inert live range and the element
    /// may own references (the slot is bound as borrowed, never an owner).
    anchored: bool = false,
};

/// One claim in flight: the emitter's flag table, the pc of the instruction
/// that produced the address, and what that address names.
const Candidate = struct { flags: []Borrow, pc: usize, source: Source };

fn claimLocals(comptime E: type, self: *E, flags: []Borrow) Error!void {
    for (self.function.scope.instructions, 0..) |_, pc| {
        const source = try addressSource(E, self, pc) orelse continue;
        try claimOne(E, self, .{ .flags = flags, .pc = pc, .source = source });
    }
}

/// The address the instruction at `pc` leaves on the operand stack, when it is
/// one a local may hold instead of a copy.
///
/// A record-returning call leaves its result in the frame's own buffer, and so
/// does an uninterrupted chain of field reads taken straight off one: a field
/// of that record is a region inside the same buffer. An element read leaves
/// the receiver's backing storage, which is borrowed rather than owned.
fn addressSource(comptime E: type, self: *E, pc: usize) Error!?Source {
    const code = self.function.scope.instructions;
    if (runtime.enabled()) return rcElementSource(E, self, code[pc].op);
    switch (code[pc].op) {
        .call => |callee| {
            const ty = self.program.functions[@backingInt(callee)].signature.return_type;
            if (!ty.isAggregate()) return null;
            return .{ .ty = ty, .stable = true };
        },
        .get_field => |index| {
            const base = try projectedBase(E, self, pc) orelse return null;
            return .{ .ty = (try self.field(base.ty, index)).ty, .stable = base.stable };
        },
        .get_index => |access| return elementSource(E, self, access.ty),
        .buffer_operation => |operation| {
            if (operation.kind != .read) return null;
            return elementSource(E, self, self.function.scope.locals[@backingInt(operation.owner)].ty);
        },
        else => return null,
    }
}

/// The record a field read at `pc` projects, when the read is the immediate
/// uninterrupted continuation of an address-producing instruction. A branch
/// into the field read would admit another producer, so it is declined.
fn projectedBase(comptime E: type, self: *E, pc: usize) Error!?Source {
    if (pc == 0 or pc >= self.branch_targets.len or self.branch_targets[pc]) return null;
    const base = try addressSource(E, self, pc - 1) orelse return null;
    if (!base.stable) return null;
    if (!base.ty.isAggregate()) return null;
    if (self.program.records[base.ty.recordIndex()].isManagedRecord()) return null;
    return base;
}

/// RC-ELEMENT-BORROW-1: under RC only a list element read through a local
/// whose storage no release can reach while the frame runs may lend its
/// address: a hidden iteration source (its hold spans the loop), a list
/// parameter the function never rebinds (the caller owns it), or a
/// temporary every store of which is an adjacent capture of one of those.
/// The element must own nothing, so the slot needs no ownership of its own.
fn rcElementSource(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) Error!?Source {
    if (op != .buffer_operation or op.buffer_operation.kind != .read) return null;
    const owner = @backingInt(op.buffer_operation.owner);
    if (!anchoredList(E, self, owner, 1)) return null;
    const source = try elementSource(E, self, self.function.scope.locals[owner].ty) orelse return null;
    const value = try self.layout(source.ty);
    if (value.trace or value.drop) {
        // RC-ELEMENT-BORROW-3: an owning element may lend its address only
        // out of a read-only parameter. The RC plan must also bind the slot
        // as borrowed from that parameter (RC-READONLY-ANCHOR-1), or the
        // claim is withdrawn before any ownership is planned (qbe_rc_state.zig).
        if (!readOnlyList(E, self, owner, 1)) return null;
        return .{ .ty = source.ty, .stable = false, .anchored = true };
    }
    return source;
}

/// Whether list local `local` is a parameter the function never writes and
/// never mutates in place, or a temporary every store of which is an
/// adjacent capture of one. A hidden iteration source is not: its hold ends
/// with its loop, and the anchor analysis never binds through it.
fn readOnlyList(comptime E: type, self: *E, local: usize, depth: usize) bool {
    const f = self.function;
    if (local >= f.scope.locals.len) return false;
    if (local < f.signature.parameter_count) {
        if (@import("ownership_model.zig").writesParameter(f, local)) return false;
        for (f.scope.instructions, 0..) |_, at| if (writesLocalAt(f, at, local)) return false;
        return true;
    }
    if (depth == 0 or @import("cow_plan.zig").iterationOwner(f, local)) return false;
    var source: ?usize = null;
    for (f.scope.instructions, 0..) |_, at| if (writesLocalAt(f, at, local)) {
        const code = f.scope.instructions;
        if (code[at].op != .store_local or at == 0 or code[at - 1].op != .load_local or branchTarget(E, self, at)) return false;
        const from = @backingInt(code[at - 1].op.load_local);
        if (source != null and source.? != from) return false;
        source = from;
    };
    const from = source orelse return false;
    return f.scope.locals[from].ty == f.scope.locals[local].ty and readOnlyList(E, self, from, depth - 1);
}

fn anchoredList(comptime E: type, self: *E, local: usize, depth: usize) bool {
    const f = self.function;
    if (local >= f.scope.locals.len) return false;
    if (@import("cow_plan.zig").iterationOwner(f, local)) return true;
    var source: ?usize = null;
    for (f.scope.instructions, 0..) |_, at| if (writesLocalAt(f, at, local)) {
        if (local < f.signature.parameter_count or depth == 0) return false;
        const code = f.scope.instructions;
        if (code[at].op != .store_local or at == 0 or code[at - 1].op != .load_local or branchTarget(E, self, at)) return false;
        const from = @backingInt(code[at - 1].op.load_local);
        if (source != null and source.? != from) return false;
        source = from;
    };
    if (source) |from| return f.scope.locals[from].ty == f.scope.locals[local].ty and anchoredList(E, self, from, depth - 1);
    return local < f.signature.parameter_count;
}

/// The element type a managed list's element read names in place. Only a list
/// and a byte string read their element straight out of backing storage; a
/// string or a dictionary read goes through a runtime call whose result is not
/// an address into the receiver.
fn elementSource(comptime E: type, self: *E, receiver: typed.Type) Error!?Source {
    if (!receiver.isAggregate()) return null;
    const schema = self.program.records[receiver.recordIndex()];
    if (!schema.managed) return null;
    if (schema.collection.kind != .list and schema.collection.kind != .bytes) return null;
    const element = schema.shape.buffer orelse return null;
    return .{ .ty = element, .stable = false };
}

/// Claim the local the address-producing instruction at `candidate.pc` fills,
/// when every condition the address-holding form needs holds.
///
/// The slot holds either an address or a value for the whole function, never
/// one and then the other, so a local written more than once is claimed only
/// when *every* write is an address of the same type and the same stability.
/// A compiler temporary the front end reuses for two element reads in a row —
/// `xs[i].f = ...` followed by `xs[i].g = ...` — is exactly that shape, and
/// each write then carries its own live-range proof, over a range the other
/// writes end.
fn claimOne(comptime E: type, self: *E, candidate: Candidate) Error!void {
    const f = self.function;
    const code = f.scope.instructions;
    const at_store = candidate.pc + 1;
    if (at_store >= code.len or at_store >= self.states.len) return;
    if (self.states[at_store] == null or branchTarget(E, self, at_store)) return;
    const slot = switch (code[at_store].op) {
        .store_local => |target| @backingInt(target),
        else => return,
    };
    if (slot >= candidate.flags.len or candidate.flags[slot] != .none) return;
    // A parameter's slot is written by the prologue as well, so that write is
    // never one of the addresses this rule accounts for.
    if (slot < f.signature.parameter_count) return;
    if (f.scope.locals[slot].ty != candidate.source.ty) return;
    if (self.isScalar(candidate.source.ty)) return;
    // A nested COW write through a recursive box implicitly reads its parent
    // at the temporary's store. That use can outlive this analysis's explicit
    // get_field run, so the parent must live in stable local storage rather
    // than as an unrooted address into a list element.
    if (self.cow != null and @import("value_semantics.zig").enabled() and !candidate.source.stable) {
        if (containsBox(self.program, candidate.source.ty, 0)) return;
    }
    const value = try self.layout(candidate.source.ty);
    // A value that owns something would have to be released through this slot,
    // and a zero-length aggregate keeps the scratch that stops QBE folding a
    // null-like address into the load. An anchored owning element
    // (RC-ELEMENT-BORROW-3) is bound as borrowed, so nothing releases it.
    if ((value.drop and !candidate.source.anchored) or value.size == 0) return;
    // Closing an arena scope scans every local declared before it through its
    // slot. A borrowed element's slot is meaningful only inside its own inert
    // run, so a frame that can reach that scan keeps the copy.
    if (!candidate.source.stable and arena_lower.releasesOnReturn(self.arenas, f)) return;
    const writes = try collectWrites(E, self, slot);
    defer self.allocator.free(writes);
    for (writes) |at| if (at == 0 or !try writesAddress(E, self, .{ .flags = candidate.flags, .pc = at - 1, .source = candidate.source })) return;
    if (!candidate.source.stable and !candidate.source.anchored) {
        for (writes) |at| if (!try inertWhileLive(E, self, .{ .store = at, .slot = slot, .writes = writes })) return;
    }
    candidate.flags[slot] = if (candidate.source.stable) .value else .element;
}

fn containsBox(program: bytecode.Program, ty: typed.Type, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const schema = program.records[ty.recordIndex()];
    if (schema.collection.box) return true;
    if (schema.managed or depth == 128) return depth == 128;
    if (schema.shape.array) |array| return array.length != 0 and containsBox(program, array.element, depth + 1);
    if (schema.shape.domain) |base| return containsBox(program, base, depth + 1);
    if (schema.shape.variants) |variants| for (variants.cases) |case| if (case.payload) |payload| {
        if (containsBox(program, payload, depth + 1)) return true;
    };
    for (schema.fields) |field| if (containsBox(program, field.ty, depth + 1)) return true;
    return false;
}

/// Every instruction that writes local `slot`, in program order.
fn collectWrites(comptime E: type, self: *E, slot: usize) Error![]usize {
    var writes: std.ArrayList(usize) = .empty;
    for (self.function.scope.instructions, 0..) |_, at| {
        if (writesLocalAt(self.function, at, slot)) try writes.append(self.allocator, at);
    }
    return writes.toOwnedSlice(self.allocator);
}

/// Whether the write at `candidate.pc + 1` stores an address of the
/// candidate's own type and stability, reached by falling through from the
/// instruction that produced it.
fn writesAddress(comptime E: type, self: *E, candidate: Candidate) Error!bool {
    const code = self.function.scope.instructions;
    const at_store = candidate.pc + 1;
    if (candidate.pc >= code.len or at_store >= code.len or at_store >= self.states.len) return false;
    if (self.states[candidate.pc] == null or self.states[at_store] == null) return false;
    if (branchTarget(E, self, at_store)) return false;
    if (code[at_store].op != .store_local) return false;
    const source = try addressSource(E, self, candidate.pc) orelse return false;
    return source.ty == candidate.source.ty and source.stable == candidate.source.stable and source.anchored == candidate.source.anchored;
}

/// One borrow's live range: the write that creates it, the local it fills and
/// every write of that local, each of which ends a range.
const Range = struct { store: usize, slot: usize, writes: []const usize };

/// Whether every instruction that can run while local `slot` holds a borrowed
/// address is inert.
///
/// The borrow starts at the store and ends where the address can no longer be
/// dereferenced: on each path, at the last read of the slot, and after that
/// read at the point where the operand it pushed leaves the operand stack. An
/// instruction is in the live range when it is reachable from the store without
/// the store running again *and* either a read of the slot is reachable from
/// it or it still runs with that read's operand live.
fn inertWhileLive(comptime E: type, self: *E, range: Range) Error!bool {
    const code = self.function.scope.instructions;
    const reachable = try self.allocator.alloc(bool, code.len);
    defer self.allocator.free(reachable);
    const live = try self.allocator.alloc(bool, code.len);
    defer self.allocator.free(live);
    @memset(reachable, false);
    @memset(live, false);
    markReachable(E, self, range, reachable);
    markReaching(E, self, range.slot, reachable, live);
    try markOperandLive(E, self, range.slot, reachable, live);
    const returns = try epilogueKeepsBorrows(E, self);
    for (code, 0..) |instruction, pc| {
        if (!live[pc] or pc == range.store) continue;
        if (!try inert(E, self, pc, instruction.op, returns)) return false;
    }
    return true;
}

/// Mark every instruction control can reach from this range's own write, never
/// entering a write of the same local: each one ends this borrow and starts
/// another.
fn markReachable(comptime E: type, self: *E, range: Range, reachable: []bool) void {
    var changed = true;
    while (changed) {
        changed = false;
        for (self.function.scope.instructions, 0..) |instruction, pc| {
            if (pc != range.store and !reachable[pc]) continue;
            changed = reachSuccessors(E, self, .{ .op = instruction.op, .pc = pc, .marks = reachable, .stop = 0 }, range.writes) or changed;
        }
    }
}

/// One successor-marking step: the instruction, where it sits, the table to
/// mark and — for the operand pass — the stack height at and below which the
/// operand it carries is gone.
const Step = struct { op: @FieldType(bytecode.Instruction, "op"), pc: usize, marks: []bool, stop: usize };

/// Mark every instruction control can enter from this one, and answer whether
/// that changed the table. The relation is the one the bytecode validator walks
/// stack heights along: a `switch_variant` leaves only through its arms, a
/// `ret` leaves nowhere, and every other instruction but an unconditional
/// `jump` also falls through.
fn reachSuccessors(comptime E: type, self: *E, step: Step, kills: []const usize) bool {
    var changed = false;
    switch (step.op) {
        .jump => |target| changed = reach(E, self, step, target, kills),
        .jump_if_false => |target| {
            changed = reach(E, self, step, target, kills) or changed;
            changed = reach(E, self, step, step.pc + 1, kills) or changed;
        },
        .try_result => |propagate| {
            changed = reach(E, self, step, propagate.error_target, kills) or changed;
            changed = reach(E, self, step, step.pc + 1, kills) or changed;
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            changed = reach(E, self, step, arm.target, kills) or changed;
        },
        .ret => {},
        else => changed = reach(E, self, step, step.pc + 1, kills),
    }
    return changed;
}

fn reach(comptime E: type, self: *E, step: Step, target: usize, kills: []const usize) bool {
    if (target >= step.marks.len) return false;
    for (kills) |at| if (at == target) return false;
    if (self.states[target] == null or step.marks[target]) return false;
    step.marks[target] = true;
    return true;
}

/// Mark every reachable instruction from which a read of `slot` is reachable,
/// the read itself included.
fn markReaching(comptime E: type, self: *E, slot: usize, reachable: []const bool, live: []bool) void {
    var changed = true;
    while (changed) {
        changed = false;
        for (self.function.scope.instructions, 0..) |instruction, pc| {
            if (!reachable[pc] or live[pc]) continue;
            if (!readsLocal(instruction.op, slot) and !successorLive(instruction.op, pc, live)) continue;
            live[pc] = true;
            changed = true;
        }
    }
}

/// Whether control leaving the instruction at `pc` can enter one already known
/// to keep the borrow live.
fn successorLive(op: @FieldType(bytecode.Instruction, "op"), pc: usize, live: []const bool) bool {
    return switch (op) {
        .jump => |target| marked(target, live),
        .jump_if_false => |target| marked(target, live) or marked(pc + 1, live),
        .try_result => |propagate| marked(propagate.error_target, live) or marked(pc + 1, live),
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (marked(arm.target, live)) break true;
        } else false,
        .ret => false,
        else => marked(pc + 1, live),
    };
}

fn marked(target: usize, live: []const bool) bool {
    return target < live.len and live[target];
}

/// Extend the live range past each read by the run over which the operand that
/// read pushed can still be dereferenced.
///
/// A read pushes the address at operand slot `k`, the stack height before it,
/// and that slot is its own until something writes it. An instruction that
/// produces a result writes it one below its own resulting height, so one that
/// leaves the stack exactly `k + 1` high has overwritten slot `k`; one that
/// leaves it lower removed the slot outright, whatever it was. An instruction
/// that only pops — a branch, a store, a `pop` — writes nothing, so it ends the
/// run only by taking the stack below `k + 1`. Propagation stops accordingly,
/// while the read itself, which creates the operand at exactly `k + 1`, always
/// reaches its own successors.
///
/// That run is where a `ret` returning the borrow and a call the address was
/// handed to as an argument both sit, and it ends at the field read or record
/// update that consumed the address. Where two reads overlap, the lower floor
/// wins, which only widens the run.
fn markOperandLive(comptime E: type, self: *E, slot: usize, reachable: []const bool, live: []bool) Error!void {
    const code = self.function.scope.instructions;
    const floor = try self.allocator.alloc(usize, code.len);
    defer self.allocator.free(floor);
    @memset(floor, 0);
    var seeded = false;
    for (code, 0..) |instruction, pc| {
        if (!reachable[pc] or !readsLocal(instruction.op, slot)) continue;
        const state = self.states[pc] orelse continue;
        floor[pc] = state.len + 1;
        seeded = true;
        _ = spreadOperand(E, self, .{ .op = instruction.op, .pc = pc, .marks = live, .stop = floor[pc] }, floor, floor[pc]);
    }
    if (!seeded) return;
    var changed = true;
    while (changed) {
        changed = false;
        for (code, 0..) |instruction, pc| {
            if (floor[pc] == 0) continue;
            const minimum = floor[pc] + @intFromBool(producesResult(instruction.op));
            changed = spreadOperand(E, self, .{ .op = instruction.op, .pc = pc, .marks = live, .stop = floor[pc] }, floor, minimum) or changed;
        }
    }
    for (floor, 0..) |held, pc| if (held != 0) {
        live[pc] = true;
    };
}

/// Carry one operand floor to every successor whose own stack still stands at
/// `minimum` or above. A lower floor replaces a higher one, so the run only
/// grows.
fn spreadOperand(comptime E: type, self: *E, step: Step, floor: []usize, minimum: usize) bool {
    var changed = false;
    switch (step.op) {
        .jump => |target| changed = carry(E, self, .{ .step = step, .target = target, .floor = floor, .minimum = minimum }),
        .jump_if_false => |target| {
            changed = carry(E, self, .{ .step = step, .target = target, .floor = floor, .minimum = minimum }) or changed;
            changed = carry(E, self, .{ .step = step, .target = step.pc + 1, .floor = floor, .minimum = minimum }) or changed;
        },
        .try_result => |propagate| {
            changed = carry(E, self, .{ .step = step, .target = propagate.error_target, .floor = floor, .minimum = minimum }) or changed;
            changed = carry(E, self, .{ .step = step, .target = step.pc + 1, .floor = floor, .minimum = minimum }) or changed;
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            changed = carry(E, self, .{ .step = step, .target = arm.target, .floor = floor, .minimum = minimum }) or changed;
        },
        .ret => {},
        else => changed = carry(E, self, .{ .step = step, .target = step.pc + 1, .floor = floor, .minimum = minimum }),
    }
    return changed;
}

/// Whether an instruction leaves a result of its own on the operand stack, at
/// the slot one below its resulting height. Only such an instruction can
/// overwrite the slot a borrow's address sits in; one that merely pops — a
/// branch, a store, a drop, a `pop`, a return — leaves every slot below its
/// own operands alone. The default is `false`, which keeps an operand live
/// longer, so an opcode added later only widens the run. `try_result` and
/// `switch_variant` are `false` on purpose: they also write slots their
/// resulting height does not name, and neither is inert, so a range that
/// reaches one declines anyway.
fn producesResult(op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .load_local,
        .move_local,
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
        .get_field,
        .get_index,
        .update_record,
        .make_record,
        .make_variant,
        .replace_index,
        .array_length,
        .binary_integer,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_integer,
        .neg_i64_checked,
        .cmp_i64,
        .cmp_bool,
        .cmp_enum,
        .cmp_domain,
        .not_bool,
        .wrap_domain,
        .unwrap_domain,
        .cast_integer,
        .call,
        .invoke,
        .buffer_operation,
        .function_value,
        => true,
        else => false,
    };
}

/// One operand-floor carry: the step it leaves, where it lands, the floor table
/// and the height the landing instruction must still stand at.
const Carry = struct { step: Step, target: usize, floor: []usize, minimum: usize };

fn carry(comptime E: type, self: *E, move: Carry) bool {
    if (move.target >= move.floor.len) return false;
    if (move.floor[move.target] != 0 and move.floor[move.target] <= move.step.stop) return false;
    const state = self.states[move.target] orelse return false;
    if (state.len < move.minimum) return false;
    move.floor[move.target] = move.step.stop;
    return true;
}

/// Whether returning from this function leaves a borrowed address usable: the
/// epilogue copies the result out after it releases what the frame owns, so a
/// frame that drops a local or closes an arena scope could free the storage
/// first.
fn epilogueKeepsBorrows(comptime E: type, self: *E) Error!bool {
    if (arena_lower.releasesOnReturn(self.arenas, self.function)) return false;
    for (self.function.scope.locals) |local| if ((try self.layout(local.ty)).drop) return false;
    return true;
}

/// Whether an instruction inside a borrow's live range can neither call,
/// allocate, release nor mutate — the only ways an address into a list's
/// backing storage can stop naming the element it was checked for. Everything
/// outside this set declines the address-holding form, so an opcode added later
/// only costs the copy it already paid.
fn inert(comptime E: type, self: *E, pc: usize, op: @FieldType(bytecode.Instruction, "op"), returns: bool) Error!bool {
    if (runtime.enabled() and !try rcInert(E, self, pc, op)) return false;
    return switch (op) {
        .load_local,
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
        .array_length,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .neg_integer,
        .neg_i64_checked,
        .cmp_i64,
        .cmp_bool,
        .cmp_enum,
        .cmp_domain,
        .not_bool,
        .wrap_domain,
        .unwrap_domain,
        .pop,
        .acknowledge,
        .assert_true,
        // Control flow moves no value and touches no storage.
        .jump,
        .jump_if_false,
        => true,
        .get_field => !self.boxProjectionAt(pc, op),
        // The result leaves through a copy the epilogue makes, so the borrow
        // must still name live storage when the epilogue runs.
        .ret => returns,
        // Scalar arithmetic and comparison allocate nothing; the same opcode
        // over a managed type is string concatenation or a content comparison,
        // which calls the runtime and can collect.
        .binary_integer => |operation| !operation.ty.isAggregate(),
        // A cast to an integer type only range-checks and traps, like the
        // checked arithmetic above; it is how a runtime index's negative-index
        // normalization converts the receiver length. A cast to text builds a
        // string, which allocates (`QBE-ELEMREF-3`).
        .cast_integer => |target| target.integer() != null,
        .call => |callee| try blindCall(E, self, callee),
        // A whole-value store can drop the value it replaces, which is a
        // release the run must not contain; a drop-free destination cannot.
        .store_local => |target| !(try self.layout(self.function.scope.locals[@backingInt(target)].ty)).drop,
        // Building or updating a plain record writes this pc's own scratch, or
        // a destination `constructorDestination` proved no reachable
        // instruction reads — never the receiver's backing. A managed record
        // is a heap cell the update writes through, and a collection literal
        // allocates, so both stay off the list.
        .make_variant => true,
        .make_record => |record| !self.program.records[record.ty.recordIndex()].isCollection() and
            !self.program.records[record.ty.recordIndex()].isManagedRecord(),
        .update_record => |record| !self.program.records[record.ty.recordIndex()].isManagedRecord(),
        // Another element read of a list or byte string is the inline load this
        // same rule lowers: it allocates nothing and writes nothing. A string
        // or dictionary read calls the runtime, so it is not on this list.
        // A `replace` on a fixed array writes a local or this pc's scratch; on
        // a managed list it writes the receiver's own backing.
        .get_index => |access| try readsInline(E, self, access.ty),
        .replace_index => |access| access.ty.isAggregate() and !self.program.records[access.ty.recordIndex()].managed,
        .buffer_operation => |operation| switch (operation.kind) {
            .length, .capacity => true,
            .read => try readsInline(E, self, self.function.scope.locals[@backingInt(operation.owner)].ty),
            else => false,
        },
        else => false,
    };
}

/// RC-ELEMENT-BORROW-1: under RC a release can free storage, so the run may
/// not return (the epilogue drops), store, pop or build anything that owns,
/// read an owning element, or call for an owning result.
fn rcInert(comptime E: type, self: *E, pc: usize, op: @FieldType(bytecode.Instruction, "op")) Error!bool {
    const locals = self.function.scope.locals;
    const ty: typed.Type = switch (op) {
        .ret => return false,
        .store_local => |target| locals[@backingInt(target)].ty,
        .make_record => |record| record.ty,
        .update_record => |record| record.ty,
        .make_variant => |variant| variant.ty,
        .call => |callee| self.program.functions[@backingInt(callee)].signature.return_type,
        .pop, .get_field => blk: {
            const stack = self.states[pc] orelse return false;
            if (stack.len == 0) return false;
            break :blk stack[stack.len - 1];
        },
        .buffer_operation => |operation| if (operation.kind == .read) operation.output else return true,
        .get_index => |access| blk: {
            if (!access.ty.isAggregate()) return true;
            break :blk self.program.records[access.ty.recordIndex()].shape.buffer orelse return true;
        },
        else => return true,
    };
    const value = try self.layout(ty);
    return !value.trace and !value.drop;
}

/// Whether a direct call can neither collect nor name the receiver, so a borrow
/// may stay live across it (`QBE-ELEMREF-4`).
///
/// The backing storage stops naming the checked element only if something
/// grows, overwrites, shrinks or frees it. A callee the allocation analysis
/// proved cannot allocate — directly, through any callee, or through a function
/// value — can neither start a collection nor grow a list. It could still write
/// an element or shrink a list it holds, but to hold one it must be handed a
/// reference: the language has no mutable globals (a module constant is an
/// immutable scalar literal), no closures, and a function value names a
/// top-level function with no state. So a callee none of whose parameter types
/// traces a reference starts with no heap object in reach, cannot allocate one,
/// and therefore cannot name the receiver or anything in it. The borrowed
/// element itself may be one of the arguments: its type then traces nothing
/// either, and a parameter the callee writes is copied into its own frame at
/// entry, so it only ever reads the element.
///
/// A `mut` parameter is the one way a callee writes storage its caller names
/// without a reference: a `mut [N]T` of scalars traces nothing. So a callee
/// with any mutation footprint, or one that writes any aggregate parameter at
/// all, declines as well.
///
/// In the first emission pass the allocation analysis is not known yet and
/// every call declines, which only keeps the copy that pass's text is measured
/// with.
fn blindCall(comptime E: type, self: *E, callee: typed.FunctionId) Error!bool {
    const id = @backingInt(callee);
    if (id >= self.pure.len or !self.pure[id]) return false;
    const function = self.program.functions[id];
    if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return false;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |parameter, index| {
        if ((try self.layout(parameter.ty)).trace) return false;
        if (self.isScalar(parameter.ty)) continue;
        for (0..function.scope.instructions.len) |at| if (writesLocalAt(function, at, index)) return false;
    }
    return true;
}

/// Whether reading one element of this receiver is an inline load rather than a
/// runtime call: a managed list or byte string, or a fixed array.
fn readsInline(comptime E: type, self: *E, receiver: typed.Type) Error!bool {
    if (!receiver.isAggregate()) return false;
    const schema = self.program.records[receiver.recordIndex()];
    if (!schema.managed) return schema.shape.array != null;
    if (schema.collection.kind != .list and schema.collection.kind != .bytes) return false;
    return (try self.layout(schema.shape.buffer orelse return false)).size != 0;
}

fn branchTarget(comptime E: type, self: *E, pc: usize) bool {
    return pc < self.branch_targets.len and self.branch_targets[pc];
}

/// Whether the instruction at `pc` writes local `index`: a whole-value store, a
/// move, an explicit drop, or a match arm's payload binding into it.
fn writesLocalAt(f: bytecode.Function, pc: usize, index: usize) bool {
    return switch (f.scope.instructions[pc].op) {
        .store_local, .move_local, .drop_local, .ref_local => |target| @backingInt(target) == index,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |target| if (@backingInt(target) == index) break true;
        } else false,
        else => false,
    };
}

/// Whether one instruction reads local `slot` into an operand. A whole-value
/// store is not a read: the address it consumes was produced elsewhere.
fn readsLocal(op: @FieldType(bytecode.Instruction, "op"), slot: usize) bool {
    return switch (op) {
        .load_local, .move_local, .ref_local => |target| @backingInt(target) == slot,
        .buffer_operation => |operation| @backingInt(operation.owner) == slot,
        else => false,
    };
}
