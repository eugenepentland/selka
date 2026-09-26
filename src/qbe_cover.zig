//! Roots a borrowed temporary does not need (`QBE-BORROW-ROOT-1`).
//!
//! A safepoint publishes one root record per traced local live across it
//! (`QBE-ROOTLIVE-1`). Many of those locals only name a value some other
//! published local already reaches: the hidden receiver `%recv = xs` of an
//! `xs[...]` expression, the loop variable of `for row in rows`, the `x` of
//! `x = xs[i]`, `x = d[k]`, `x = obj.field` or `x = rec.items`. The ownership
//! analysis (`ownership.zig`) calls these *borrows*: the local was filled from
//! a part of another local, its *owner*. Under the tracing collector such a
//! local needs no root of its own at a safepoint where
//!
//!  1. every definition reaching the safepoint copied the value out of the
//!     owner — its whole value, an element, a dictionary entry, a field;
//!  2. on every path from such a definition through the safepoint itself, the
//!     owner is not rebound and nothing can take the value out of the object
//!     it was read from: no instruction of this frame overwrites or removes an
//!     element or field of an object of that object's type, and no callee is
//!     handed anything from which an object of that type is reachable (a
//!     function has no state but its arguments, so a callee that cannot reach
//!     such an object cannot change one);
//!  3. the owner itself is published at the safepoint, or is covered the same
//!     way by a published owner of its own.
//!
//! The collector never moves an object, so the owner's root reaches the
//! object, the object still holds the value, and the value is marked exactly
//! as its own root would have marked it. The root record, not the local, is
//! what disappears: the local still holds its value and every read is
//! unchanged, as are collection timing, traps and results.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const arena_lower = @import("qbe_arena.zig");
const ownership = @import("ownership.zig");
const moves = @import("qbe_moves.zig");

/// Failures raised while planning.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// The absent index.
pub const none = ownership.none;

/// Which locals a published owner covers, and where.
pub const Coverage = struct {
    /// Per local, the owner whose root covers it, or `none`.
    owners: []const u32 = &.{},
    /// Per local with an owner, per instruction, whether the cover holds at a
    /// safepoint there.
    holds: []const []const bool = &.{},

    /// The owner covering local `index` at a safepoint at `pc`, or null.
    pub fn owner(self: Coverage, pc: usize, index: usize) ?usize {
        if (index >= self.owners.len or self.owners[index] == none) return null;
        const at = self.holds[index];
        if (pc >= at.len or !at[pc]) return null;
        return self.owners[index];
    }
};

/// What a borrowed local was read out of: its owner's whole value, a part of
/// a heap object of type `object`, or a part of the owner's own frame slot.
const Read = struct { owner: u32, kind: Kind, object: typed.Type };
const Kind = enum(u8) { whole, heap, frame };

/// Bind the planner to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Find every local a published owner covers, and where.
        pub fn plan(self: *E) Error!Coverage {
            return planCoverage(E, self);
        }
    };
}

fn planCoverage(comptime E: type, self: *E) Error!Coverage {
    const f = self.function;
    const analysis = self.ownership orelse return .{};
    if (arena_lower.opens(f)) return .{};
    const a = self.allocator;
    const owners = try a.alloc(u32, f.scope.locals.len);
    @memset(owners, none);
    const holds = try a.alloc([]const bool, f.scope.locals.len);
    @memset(holds, &.{});
    for (f.scope.locals, 0..) |local, index| {
        if (index < f.signature.parameter_count or self.byReference(index)) continue;
        const value = try self.layout(local.ty);
        if (!value.trace or value.drop) continue;
        if (!self.isScalar(local.ty)) continue;
        const read = try commonRead(E, self, analysis, index) orelse continue;
        if (read.owner == index or self.borrowsElement(read.owner)) continue;
        if (!(try self.layout(f.scope.locals[read.owner].ty)).trace) continue;
        owners[index] = read.owner;
        holds[index] = try clean(E, self, .{ .local = index, .read = read });
    }
    return .{ .owners = owners, .holds = holds };
}

/// The one owner every write of local `index` reads its value out of, when
/// every write is a store reached by falling through from such a read.
fn commonRead(comptime E: type, self: *E, analysis: ownership.Analysis, index: usize) Error!?Read {
    const f = self.function;
    const code = f.scope.instructions;
    var found: ?Read = null;
    for (code, 0..) |instruction, pc| {
        if (!moves.writesLocal(f, pc, index)) continue;
        if (instruction.op != .store_local or pc == 0 or self.states[pc] == null or self.isBranchTarget(pc)) return null;
        const read = try readAt(E, self, analysis, pc - 1) orelse return null;
        if (found) |known| {
            if (known.owner != read.owner or known.kind != read.kind or known.object != read.object) return null;
        }
        found = read;
    }
    return found;
}

/// What the instruction at `pc` reads out of which local, when its result is
/// a value that local (or an object it holds) keeps.
fn readAt(comptime E: type, self: *E, analysis: ownership.Analysis, pc: usize) Error!?Read {
    const f = self.function;
    const stack = analysis.operands[pc] orelse return null;
    switch (f.scope.instructions[pc].op) {
        .load_local => |slot| return .{ .owner = @intCast(@backingInt(slot)), .kind = .whole, .object = .unit },
        .buffer_operation => |operation| {
            switch (operation.kind) {
                .read, .key_at, .value_at => {},
                else => return null,
            }
            const owner: u32 = @intCast(@backingInt(operation.owner));
            const ty = f.scope.locals[owner].ty;
            if (!keeps(self.program, ty)) return null;
            return .{ .owner = owner, .kind = .heap, .object = ty };
        },
        .get_field, .get_index => {
            const depth: usize = if (f.scope.instructions[pc].op == .get_field) 1 else 2;
            if (stack.len < depth) return null;
            const base = stack[stack.len - depth];
            if (base.origin != .local or base.part != .whole or base.read == none) return null;
            // The object read must still be the one the owner holds.
            for (base.read + 1..pc) |between| if (moves.writesLocal(f, between, base.local)) return null;
            const ty = f.scope.locals[base.local].ty;
            if (!ty.isAggregate()) return null;
            const schema = self.program.records[ty.recordIndex()];
            if (!schema.managed) return .{ .owner = base.local, .kind = .frame, .object = ty };
            if (!keeps(self.program, ty)) return null;
            return .{ .owner = base.local, .kind = .heap, .object = ty };
        },
        else => return null,
    }
}

/// Whether reading an element or field of a managed `ty` hands back a value
/// the object keeps: anything but a string, whose element reads build a new
/// string.
fn keeps(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const schema = program.records[ty.recordIndex()];
    if (!schema.managed) return false;
    return schema.collection.kind != .string and schema.collection.kind != .bytes;
}

/// One candidate: the borrowed local and what it reads.
const Candidate = struct { local: usize, read: Read };

/// The state of the cover on entry to an instruction.
const State = enum(u8) { unreached, clean, dirty };

/// Per instruction, whether the cover holds at a safepoint there: every path
/// into it last defined the local from its owner, nothing since has disturbed
/// the owner or its object, and the instruction itself does not.
fn clean(comptime E: type, self: *E, candidate: Candidate) Error![]const bool {
    const code = self.function.scope.instructions;
    const a = self.allocator;
    const entry = try a.alloc(State, code.len);
    defer a.free(entry);
    @memset(entry, .unreached);
    if (code.len == 0) return &.{};
    entry[0] = .dirty;
    const dirties = try a.alloc(bool, code.len);
    defer a.free(dirties);
    for (dirties, 0..) |*flag, pc| flag.* = try disturbs(E, self, candidate, pc);
    var changed = true;
    while (changed) {
        changed = false;
        for (code, 0..) |instruction, pc| {
            if (self.states[pc] == null or entry[pc] == .unreached) continue;
            const out = exit(self.function, candidate.local, pc, entry[pc], dirties[pc]);
            var buffer: [2]usize = undefined;
            for (successors(instruction.op, pc, &buffer)) |next| changed = merge(entry, next, out) or changed;
            if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
                changed = merge(entry, arm.target, out) or changed;
            };
        }
    }
    const holds = try a.alloc(bool, code.len);
    for (holds, 0..) |*flag, pc| flag.* = entry[pc] == .clean and !dirties[pc];
    return holds;
}

fn exit(f: bytecode.Function, local: usize, pc: usize, state: State, dirty: bool) State {
    if (moves.writesLocal(f, pc, local)) return if (f.scope.instructions[pc].op == .store_local) .clean else .dirty;
    return if (dirty) .dirty else state;
}

fn merge(entry: []State, target: usize, state: State) bool {
    if (target >= entry.len) return false;
    const next: State = switch (entry[target]) {
        .unreached => state,
        .clean => if (state == .dirty) .dirty else .clean,
        .dirty => .dirty,
    };
    if (next == entry[target]) return false;
    entry[target] = next;
    return true;
}

/// The fall-through and branch successors of one instruction; a
/// `switch_variant`'s arms are read by the caller.
fn successors(op: @FieldType(bytecode.Instruction, "op"), pc: usize, buffer: *[2]usize) []const usize {
    switch (op) {
        .jump => |target| {
            buffer[0] = target;
            return buffer[0..1];
        },
        .jump_if_false => |target| {
            buffer[0] = target;
            buffer[1] = pc + 1;
            return buffer[0..2];
        },
        .try_result => |propagate| {
            buffer[0] = propagate.error_target;
            buffer[1] = pc + 1;
            return buffer[0..2];
        },
        .ret, .switch_variant => return buffer[0..0],
        else => {
            buffer[0] = pc + 1;
            return buffer[0..1];
        },
    }
}

/// Whether the instruction at `pc` can rebind the owner or take the value out
/// of the object (or frame slot) it was read from.
fn disturbs(comptime E: type, self: *E, candidate: Candidate, pc: usize) Error!bool {
    const f = self.function;
    const owner = candidate.read.owner;
    if (moves.writesLocal(f, pc, owner)) return true;
    // COW-UNIQUE-1: a check redirecting the owner, or a copy written back
    // into an object, can leave the value reachable from this local alone.
    if (self.cow) |state| if (state.plan.disturbs(owner, pc, candidate.read.kind == .heap)) return true;
    // A constructor, `replace` or update forwarded into the owner writes its
    // slot the instruction before the store does.
    if (pc + 1 < f.scope.instructions.len and moves.writesLocal(f, pc + 1, owner)) return true;
    switch (self.moves.update(pc)) {
        .slot => |target| if (target == owner) return true,
        else => {},
    }
    return switch (candidate.read.kind) {
        .whole, .frame => false,
        .heap => removes(E, self, candidate.read.object, f.scope.instructions[pc].op),
    };
}

/// Whether an instruction can overwrite or remove an element or field of an
/// object of type `object`, directly or through a callee.
fn removes(comptime E: type, self: *E, object: typed.Type, op: @FieldType(bytecode.Instruction, "op")) Error!bool {
    const program = self.program;
    return switch (op) {
        .buffer_operation => |operation| {
            if (self.function.scope.locals[@backingInt(operation.owner)].ty != object) return false;
            return switch (operation.kind) {
                .write, .pop, .pop_at, .remove, .clear, .take, .truncate, .resize, .update, .pop_key, .pop_default, .set_discard, .sort_keyed => true,
                else => false,
            };
        },
        .replace_index => |access| access.ty == object,
        .update_record => |update| update.ty == object,
        .call => |callee| callReaches(program, callee, object),
        .invoke => |callback| anyReaches(program, program.records[callback.recordIndex()].contract.callback.?.parameters, object),
        .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource, .host_resource => true,
        .file_access, .file_method, .external_read, .stream_write => true,
        else => false,
    };
}

/// Whether a callee is handed anything from which an object of type
/// `object` is reachable: one of its parameter types reaches that type.
fn callReaches(program: bytecode.Program, callee: typed.FunctionId, object: typed.Type) bool {
    const function = program.functions[@backingInt(callee)];
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count]) |parameter| if (reaches(program, parameter.ty, object)) return true;
    return false;
}

fn anyReaches(program: bytecode.Program, parameters: []const typed.Type, object: typed.Type) bool {
    for (parameters) |parameter| if (reaches(program, parameter, object)) return true;
    return false;
}

/// Whether a value of type `from` can reference an object of type `to`,
/// directly or through fields, elements, keys and payloads. A function value
/// names a top-level function and holds nothing. The walk visits each record
/// type at most once; a type graph deeper than it can track answers yes.
pub fn reaches(program: bytecode.Program, from: typed.Type, to: typed.Type) bool {
    var pending: [64]typed.Type = undefined;
    var seen: [64]typed.Type = undefined;
    var pending_len: usize = 1;
    var seen_len: usize = 0;
    pending[0] = from;
    while (pending_len > 0) {
        pending_len -= 1;
        const ty = pending[pending_len];
        if (ty == to) return true;
        if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) continue;
        if (std.mem.indexOfScalar(typed.Type, seen[0..seen_len], ty) != null) continue;
        if (seen_len == seen.len) return true;
        seen[seen_len] = ty;
        seen_len += 1;
        const schema = program.records[ty.recordIndex()];
        if (schema.contract.callback != null) continue;
        var next: [4]?typed.Type = .{ schema.collection.key, schema.shape.buffer, schema.shape.domain, if (schema.shape.array) |array| array.element else null };
        for (&next) |candidate| if (candidate) |inner| {
            if (pending_len == pending.len) return true;
            pending[pending_len] = inner;
            pending_len += 1;
        };
        if (schema.shape.variants) |variants| for (variants.cases) |case| if (case.payload) |payload| {
            if (pending_len == pending.len) return true;
            pending[pending_len] = payload;
            pending_len += 1;
        };
        for (schema.fields) |field| {
            if (pending_len == pending.len) return true;
            pending[pending_len] = field.ty;
            pending_len += 1;
        }
    }
    return false;
}
