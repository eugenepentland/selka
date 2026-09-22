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

/// Failures raised while deciding which locals name their value in place.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Bind the borrow analysis to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Mark every local that may hold an address instead of its value.
        /// `flags` is the emitter's per-local by-reference table, already
        /// carrying the parameters and match bindings claimed before this runs;
        /// a slot another rule claimed is left alone.
        pub fn claim(self: *E, flags: []bool) Error!void {
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
};

/// One claim in flight: the emitter's flag table, the pc of the instruction
/// that produced the address, and what that address names.
const Candidate = struct { flags: []bool, pc: usize, source: Source };

fn claimLocals(comptime E: type, self: *E, flags: []bool) Error!void {
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
        .get_index => |ty| return elementSource(E, self, ty),
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
    if (slot >= candidate.flags.len or candidate.flags[slot]) return;
    // A parameter's slot is written by the prologue as well, so this store is
    // never its only write.
    if (slot < f.signature.parameter_count) return;
    if (f.scope.locals[slot].ty != candidate.source.ty) return;
    if (self.isScalar(candidate.source.ty)) return;
    const value = try self.layout(candidate.source.ty);
    // A value that owns something would have to be released through this slot,
    // and a zero-length aggregate keeps the scratch that stops QBE folding a
    // null-like address into the load.
    if (value.drop or value.size == 0) return;
    // A borrowed element that holds managed references would be pushed as a
    // root at every later safepoint, long after the borrow died, and the
    // receiver's backing can be reallocated or swept by then. The frame's own
    // result buffer cannot, so only a borrow of it may trace.
    if (value.trace and !candidate.source.stable) return;
    for (code, 0..) |_, at| if (at != at_store and writesLocalAt(f, at, slot)) return;
    if (!candidate.source.stable and !try inertWhileLive(E, self, at_store, slot)) return;
    candidate.flags[slot] = true;
}

/// Whether every instruction that can run while local `slot` holds a borrowed
/// address is inert.
///
/// The borrow starts at the store and ends where the address can no longer be
/// dereferenced: on each path, at the last read of the slot, and after that
/// read at the point where the operand it pushed leaves the operand stack. An
/// instruction is in the live range when it is reachable from the store without
/// the store running again *and* either a read of the slot is reachable from
/// it or it still runs with that read's operand live.
fn inertWhileLive(comptime E: type, self: *E, at_store: usize, slot: usize) Error!bool {
    const code = self.function.scope.instructions;
    const reachable = try self.allocator.alloc(bool, code.len);
    defer self.allocator.free(reachable);
    const live = try self.allocator.alloc(bool, code.len);
    defer self.allocator.free(live);
    @memset(reachable, false);
    @memset(live, false);
    markReachable(E, self, at_store, reachable);
    markReaching(E, self, slot, reachable, live);
    try markOperandLive(E, self, slot, reachable, live);
    const returns = try epilogueKeepsBorrows(E, self);
    for (code, 0..) |instruction, pc| {
        if (!live[pc] or pc == at_store) continue;
        if (!try inert(E, self, instruction.op, returns)) return false;
    }
    return true;
}

/// Mark every instruction control can reach from `from`, never re-entering
/// `from` itself: the store that created the borrow ends the previous one.
fn markReachable(comptime E: type, self: *E, from: usize, reachable: []bool) void {
    var changed = true;
    while (changed) {
        changed = false;
        for (self.function.scope.instructions, 0..) |instruction, pc| {
            if (pc != from and !reachable[pc]) continue;
            changed = reachSuccessors(E, self, .{ .op = instruction.op, .pc = pc, .marks = reachable, .stop = from }) or changed;
        }
    }
}

/// One successor-marking step: the instruction, where it sits, the table to
/// mark and the pc marking must never re-enter.
const Step = struct { op: @FieldType(bytecode.Instruction, "op"), pc: usize, marks: []bool, stop: usize };

/// Mark every instruction control can enter from this one, and answer whether
/// that changed the table. The relation is the one the bytecode validator walks
/// stack heights along: a `switch_variant` leaves only through its arms, a
/// `ret` leaves nowhere, and every other instruction but an unconditional
/// `jump` also falls through.
fn reachSuccessors(comptime E: type, self: *E, step: Step) bool {
    var changed = false;
    switch (step.op) {
        .jump => |target| changed = reach(E, self, step, target),
        .jump_if_false => |target| {
            changed = reach(E, self, step, target) or changed;
            changed = reach(E, self, step, step.pc + 1) or changed;
        },
        .try_result => |propagate| {
            changed = reach(E, self, step, propagate.error_target) or changed;
            changed = reach(E, self, step, step.pc + 1) or changed;
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            changed = reach(E, self, step, arm.target) or changed;
        },
        .ret => {},
        else => changed = reach(E, self, step, step.pc + 1),
    }
    return changed;
}

fn reach(comptime E: type, self: *E, step: Step, target: usize) bool {
    if (target >= step.marks.len or target == step.stop) return false;
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
/// A read pushes the address at operand slot `h`, the stack height before it,
/// so the address is certainly gone once the height falls to `h` or below. The
/// run is therefore every instruction reachable from a read whose own height
/// still stands above that slot, which is where a `ret` that returns the
/// borrow, and a call the address was handed to as an argument, both sit. Where
/// two reads overlap, the lower floor wins, which only widens the run.
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
    }
    if (!seeded) return;
    var changed = true;
    while (changed) {
        changed = false;
        for (code, 0..) |instruction, pc| {
            if (floor[pc] == 0) continue;
            changed = spreadOperand(E, self, .{ .op = instruction.op, .pc = pc, .marks = live, .stop = floor[pc] }, floor) or changed;
        }
    }
    for (floor, 0..) |held, pc| if (held != 0) {
        live[pc] = true;
    };
}

/// Carry one operand floor to every successor whose own stack still stands
/// above it. A lower floor replaces a higher one, so the run only grows.
fn spreadOperand(comptime E: type, self: *E, step: Step, floor: []usize) bool {
    var changed = false;
    switch (step.op) {
        .jump => |target| changed = carry(E, self, step, target, floor),
        .jump_if_false => |target| {
            changed = carry(E, self, step, target, floor) or changed;
            changed = carry(E, self, step, step.pc + 1, floor) or changed;
        },
        .try_result => |propagate| {
            changed = carry(E, self, step, propagate.error_target, floor) or changed;
            changed = carry(E, self, step, step.pc + 1, floor) or changed;
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            changed = carry(E, self, step, arm.target, floor) or changed;
        },
        .ret => {},
        else => changed = carry(E, self, step, step.pc + 1, floor),
    }
    return changed;
}

fn carry(comptime E: type, self: *E, step: Step, target: usize, floor: []usize) bool {
    if (target >= floor.len) return false;
    if (floor[target] != 0 and floor[target] <= step.stop) return false;
    const state = self.states[target] orelse return false;
    if (state.len < step.stop) return false;
    floor[target] = step.stop;
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
fn inert(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), returns: bool) Error!bool {
    return switch (op) {
        .load_local,
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
        .get_field,
        .array_length,
        .binary_integer,
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
        // The result leaves through a copy the epilogue makes, so the borrow
        // must still name live storage when the epilogue runs.
        .ret => returns,
        // A whole-value store can drop the value it replaces, which is a
        // release the run must not contain; a drop-free destination cannot.
        .store_local => |target| !(try self.layout(self.function.scope.locals[@backingInt(target)].ty)).drop,
        // Another element read of a list or byte string is the inline load this
        // same rule lowers: it allocates nothing and writes nothing. A string
        // or dictionary read calls the runtime, so it is not on this list.
        .get_index => |ty| try readsInline(E, self, ty),
        .buffer_operation => |operation| switch (operation.kind) {
            .length, .capacity => true,
            .read => try readsInline(E, self, self.function.scope.locals[@backingInt(operation.owner)].ty),
            else => false,
        },
        else => false,
    };
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
        .store_local, .move_local, .drop_local => |target| @backingInt(target) == index,
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
        .load_local, .move_local => |target| @backingInt(target) == slot,
        .buffer_operation => |operation| @backingInt(operation.owner) == slot,
        else => false,
    };
}
