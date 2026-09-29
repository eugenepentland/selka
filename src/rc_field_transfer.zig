//! Closed direct-field ownership movement, independent of semantic copy bits.
//!
//! `wb = owner.f; mutate(mut wb); owner.f = wb` moves `owner.f`'s token into
//! `wb` when nothing can observe the emptied field before the store-back, so
//! the mutation finds one owner instead of cloning a shared payload.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const sources = @import("ownership_sources.zig");
const semantics = @import("value_semantics.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// An initialized inline record field that may be temporarily empty: a field
/// of writable caller-owned storage or of a frame-owned local's own slot.
pub const Source = struct { local: usize, field: usize, ty: typed.Type };
/// Exact extraction and unconditional return positions for one physical owner.
pub const Certificate = struct {
    source: Source,
    target: usize,
    projection: usize,
    store: usize,
    writeback: usize,
    commit: usize,
    /// False for RC-DEAD-FIELD-MOVE-1: the source is never read again, so the
    /// field is not stored back; `writeback` and `commit` then equal `store`.
    returns: bool = true,

    /// Whether the lowering of the instruction at `pc` belongs to this
    /// certificate: the extraction's projection, copy and target store, or
    /// any step of the complete store-back sequence.
    pub fn intercepts(self: Certificate, pc: usize) bool {
        return (pc >= self.projection and pc <= self.store) or (pc >= self.writeback and pc <= self.commit);
    }
};
/// Proof refusal is ordinary lowering; malformed native layouts are compiler errors.
pub const Error = error{ InternalError, OutOfMemory };

/// Certify bounded closed intervals with no way to observe the empty field.
/// Semantic SHARE decisions alone never authorize physical ownership movement.
pub fn build(comptime E: type, self: *E, catalog: *shapes.Catalog) Error![]const Certificate {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.policy.c_abi or self.function.policy.host != null) return &.{};
    var found: std.ArrayList(Certificate) = .empty;
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .get_field or self.states[pc] == null) continue;
        if (code.len > remaining) break;
        remaining -= code.len;
        const complete = try closed(E, self, pc, catalog) orelse try dead(E, self, pc, catalog) orelse continue;
        if (found.items.len != 0 and found.items[found.items.len - 1].commit >= pc - 1) continue;
        try found.append(self.allocator, complete);
    }
    return found.toOwnedSlice(self.allocator);
}

fn closed(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?Certificate {
    const proof = try extraction(E, self, pc, catalog) orelse return null;
    const end = try returned(E, self, proof, catalog) orelse return null;
    var complete = proof;
    complete.writeback = end;
    complete.commit = end + 10;
    return complete;
}

/// RC-DEAD-FIELD-MOVE-1: `t = s.f`, where value semantics already proved the
/// copy a move and the frame-owned inline record `s` is never read again,
/// moves the field's tokens into `t` instead of copying them, so a mutation of
/// `t` finds one owner rather than cloning. `s` keeps its other fields and its
/// later drop finds the moved field empty. Only a local whose every
/// definition leaves its own storage in its slot qualifies (a match binding
/// does: its arm copies the payload in); whether it holds an ordinary owner
/// is tested when the move runs, and anything else still copies.
fn dead(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?Certificate {
    const proof = try deadExtraction(E, self, pc, catalog) orelse return null;
    return if (try deadSource(E, self, proof, catalog)) proof else null;
}

// `load_local s; get_field f; value_copy assign; store_local t` whose copy
// value semantics elided, between a frame-owned inline record and a named
// owned target that both keep their values in their own slots.
fn deadExtraction(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?Certificate {
    const code = self.function.scope.instructions;
    const analysis = self.ownership orelse return null;
    if (pc == 0 or pc + 2 >= code.len or pc + 1 >= analysis.copies.len) return null;
    if (code[pc - 1].op != .load_local or code[pc + 1].op != .value_copy or code[pc + 2].op != .store_local) return null;
    const copy = code[pc + 1].op.value_copy;
    if (copy.site != .assign or analysis.copies[pc + 1]) return null;
    const source = @backingInt(code[pc - 1].op.load_local);
    const target = @backingInt(code[pc + 2].op.store_local);
    const locals = self.function.scope.locals;
    const parameters = self.function.signature.parameter_count;
    if (source < parameters or target < parameters or source == target or locals[target].usage.temporary) return null;
    if (analysis.roles[source] != .owned or analysis.roles[target] != .owned) return null;
    if (self.byReference(source) or self.callerStorage(source) or self.moves.resolve(source) != source) return null;
    if (self.borrowsElement(source) or self.byReference(target) or self.callerStorage(target)) return null;
    const places = self.cow.?.plan;
    if (places.place(target) != null or places.place(source) != null) return null;
    const owner_ty = locals[source].ty;
    if (!owner_ty.isAggregate()) return null;
    const owner = self.program.records[owner_ty.recordIndex()];
    if (!owner.isRecord() or owner.managed or (try shape(catalog, owner_ty)).unique_drop) return null;
    const ty = locals[target].ty;
    const field = code[pc].op.get_field;
    if (field >= owner.fields.len or owner.fields[field].ty != ty or copy.ty != ty) return null;
    if (!try movable(E, self, ty, catalog)) return null;
    return .{ .source = .{ .local = source, .field = field, .ty = ty }, .target = target, .projection = pc, .store = pc + 2, .writeback = pc + 2, .commit = pc + 2, .returns = false };
}

// No later instruction reads the source before overwriting it, nothing can
// reach its slot by reference, and no other local that may hold, borrow or
// name it is live; the extraction itself is straight, quiet and unscoped.
fn deadSource(comptime E: type, self: *E, proof: Certificate, catalog: *shapes.Catalog) Error!bool {
    const code = self.function.scope.instructions;
    const pc = proof.projection;
    const source = proof.source.local;
    for (self.function.scope.locals) |local| if (semantics.containsLiveView(self.program.records, local.ty)) return false;
    if ((self.states[pc - 1] orelse return false).len != 0) return false;
    for (pc..pc + 3) |at| if (!straight(E, self, at) or !quiet(E, self, at)) return false;
    for (pc - 1..pc + 3) |at| if (captured(E, self, at)) return false;
    if (self.live.?.after(pc - 1, source)) return false;
    for (code) |instruction| switch (instruction.op) {
        .ref_local => |id| if (@backingInt(id) == source) return false,
        else => {},
    };
    const derived = try derivedLocals(E, self, proof.source);
    defer self.allocator.free(derived);
    for (derived, 0..) |linked, index| {
        if (!linked or index == source or index == proof.target) continue;
        if (self.live.?.before(pc - 1, index) and !try harmless(E, self, index, catalog)) return false;
    }
    return true;
}

fn extraction(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?Certificate {
    const code = self.function.scope.instructions;
    if (pc == 0 or pc + 2 >= code.len) return null;
    if (code[pc - 1].op != .load_local or code[pc + 1].op != .value_copy or code[pc + 2].op != .store_local) return null;
    if (code[pc + 1].op.value_copy.site != .assign) return null;
    const source = @backingInt(code[pc - 1].op.load_local);
    const target = @backingInt(code[pc + 2].op.store_local);
    if (self.moves.resolve(source) != source) return null;
    const locals = self.function.scope.locals;
    if (!self.callerStorage(source) and !ownedHome(E, self, source)) return null;
    if (target < self.function.signature.parameter_count or locals[target].usage.temporary) return null;
    if (self.byReference(target) or self.callerStorage(target) or source == target) return null;
    if (self.cow.?.plan.place(target) != null) return null;
    const owner_ty = locals[source].ty;
    const owner = self.program.records[owner_ty.recordIndex()];
    if (!owner.isRecord() or owner.managed or (try shape(catalog, owner_ty)).unique_drop) return null;
    if (semantics.containsLiveView(self.program.records, owner_ty)) return null;
    const ty = locals[target].ty;
    const field = code[pc].op.get_field;
    if (field >= owner.fields.len or owner.fields[field].ty != ty) return null;
    if (!try movable(E, self, ty, catalog)) return null;
    // A second writable parameter may name the same caller storage. Read-only
    // parameters are values: a call passes a copy wherever one could share
    // storage with a `mut` argument (`VALUE-SEMANTICS-2` argument copies).
    for (0..self.function.signature.parameter_count) |index| {
        if (index != source and @import("ownership_model.zig").writesParameter(self.function, index)) return null;
    }
    // A live view elsewhere in the frame could observe a payload the moved
    // owner then changes in place instead of detaching.
    for (locals) |local| if (semantics.containsLiveView(self.program.records, local.ty)) return null;
    for (pc..pc + 3) |at| if (!straight(E, self, at)) return null;
    if ((self.states[pc - 1] orelse return null).len != 0) return null;
    const analysis = self.ownership orelse return null;
    if (analysis.roles[target] != .owned or code[pc + 1].op.value_copy.ty != ty) return null;
    return .{ .source = .{ .local = source, .field = field, .ty = ty }, .target = target, .projection = pc, .store = pc + 2, .writeback = 0, .commit = 0 };
}

// A frame-owned named local whose own slot holds its value inline. Match
// payload bindings and address-holding slots may name another value's storage.
fn ownedHome(comptime E: type, self: *E, source: usize) bool {
    const local = self.function.scope.locals[source];
    if (source < self.function.signature.parameter_count or local.usage.temporary) return false;
    if (self.byReference(source)) return false;
    const analysis = self.ownership orelse return false;
    if (source >= analysis.roles.len or analysis.roles[source] != .owned) return false;
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |slot| if (@backingInt(slot) == source) return false;
        },
        else => {},
    };
    return true;
}

// Zeroed bytes are every RC value's empty cleanup representation. Unique
// finalizers, prohibited copies and live views keep their existing paths.
// A value carried in the operand word itself must be one managed pointer.
fn movable(comptime E: type, self: *E, ty: typed.Type, catalog: *shapes.Catalog) Error!bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (record.isCollection() and record.collection.box) return false;
    if (semantics.containsLiveView(self.program.records, ty)) return false;
    const value = try shape(catalog, ty);
    if (!value.counted or value.unique_drop) return false;
    const layout = catalog.native.layout(ty) catch return error.InternalError;
    if (layout.drop or layout.copy == .prohibited or layout.size == 0) return false;
    if (self.isScalar(ty) and layout.size != 8) return false;
    return @import("rc_field_authority.zig").movable(catalog, ty);
}

fn returned(comptime E: type, self: *E, proof: Certificate, catalog: *shapes.Catalog) Error!?usize {
    const code = self.function.scope.instructions;
    const derived = try derivedLocals(E, self, proof.source);
    defer self.allocator.free(derived);
    // No value that may still hold, borrow or name the source's storage
    // survives into the interval: its reads would see the empty field or an
    // in-place change the copy would have hidden.
    for (derived, 0..) |linked, index| {
        if (!linked or index == proof.source.local or index == proof.target) continue;
        if (self.live.?.before(proof.projection - 1, index) and !try harmless(E, self, index, catalog)) return null;
    }
    for (proof.store + 1..code.len) |pc| {
        if (writeback(E, self, proof, pc)) {
            if (!@import("ownership_field_return.zig").closedInterval(code, proof.store + 1, pc)) return null;
            for (proof.projection - 1..pc + 11) |at| if (captured(E, self, at)) return null;
            for (proof.projection..proof.store + 1) |at| if (!quiet(E, self, at)) return null;
            for (pc..pc + 11) |at| if (!quiet(E, self, at)) return null;
            return pc;
        }
        if (self.states[pc] == null or !try permitted(E, self, proof, derived, pc, catalog)) return null;
    }
    return null;
}

fn straight(comptime E: type, self: *E, pc: usize) bool {
    if (self.states[pc] == null or self.isBranchTarget(pc)) return false;
    const op = self.function.scope.instructions[pc].op;
    var buffer: [2]usize = undefined;
    return sources.fallsThrough(op) and sources.branchTargets(op, &buffer).len == 0 and op != .switch_variant;
}

// A pending receiver scope would hold a payload across the interval.
fn captured(comptime E: type, self: *E, pc: usize) bool {
    const captures = self.cow.?.captures;
    if (pc >= captures.len) return false;
    const none = @import("cow_plan.zig").none;
    return captures[pc].begin != none or captures[pc].active != none;
}

// The lowering of the extraction and store-back sequences is replaced
// wholesale, so no copy-on-write check, fill, share or loop entry may be
// planned on them.
fn quiet(comptime E: type, self: *E, pc: usize) bool {
    const plan = self.cow.?.plan;
    const site = plan.at(pc);
    if (site.unique.len != 0 or site.unique_field != null or site.fill or site.capture) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0 or plan.entry(pc).len != 0) return false;
    return switch (self.function.scope.instructions[pc].op) {
        .store_local, .load_local => |id| plan.place(@backingInt(id)) == null,
        else => true,
    };
}

// Every interval instruction leaves the source alone, reads a distinct sibling
// field, or uses the target and values independent of the source.
fn permitted(comptime E: type, self: *E, proof: Certificate, derived: []const bool, pc: usize, catalog: *shapes.Catalog) Error!bool {
    const code = self.function.scope.instructions;
    const use: Use = .{ .proof = proof, .derived = derived, .catalog = catalog };
    return switch (code[pc].op) {
        .begin_arena, .end_arena, .ret, .try_result, .invoke => false,
        .call => |id| direct(self.program.functions[@backingInt(id)]),
        .load_local => |id| if (@backingInt(id) == proof.source.local) sibling(E, self, proof, pc) else use.independent(E, self, @backingInt(id)),
        .move_local, .drop_local => |id| @backingInt(id) != proof.target and try use.independent(E, self, @backingInt(id)),
        .ref_local, .store_local => |id| use.independent(E, self, @backingInt(id)),
        .buffer_operation => |operation| use.independent(E, self, @backingInt(operation.owner)),
        .resource_io => |operation| use.independent(E, self, @backingInt(operation.owner)),
        .file_method => |method| use.independent(E, self, @backingInt(method.owner)),
        .switch_variant => |dispatch| {
            for (dispatch.arms) |arm| if (arm.slot) |slot| {
                if (!try use.independent(E, self, @backingInt(slot))) return false;
            };
            return true;
        },
        else => true,
    };
}

// A guest callee sees only its operands, and none of them names the empty
// field. Host and C-ABI entries stay outside the certificate.
fn direct(callee: bytecode.Function) bool {
    return !callee.policy.c_abi and callee.policy.host == null;
}

const Use = struct {
    proof: Certificate,
    derived: []const bool,
    catalog: *shapes.Catalog,

    fn independent(use: Use, comptime E: type, self: *E, local: usize) Error!bool {
        if (local == use.proof.target) return true;
        if (local == use.proof.source.local) return false;
        return !use.derived[local] or try harmless(E, self, local, use.catalog);
    }
};

// `owner.g` with g distinct from the moved field reads storage the move left
// intact; the ordinary projection lends or copies it as before.
fn sibling(comptime E: type, self: *E, proof: Certificate, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (pc + 1 >= code.len or self.isBranchTarget(pc + 1)) return false;
    const next = code[pc + 1].op;
    return next == .get_field and next.get_field != proof.source.field;
}

// Plain bits in the local's own slot cannot name or share a counted payload.
fn harmless(comptime E: type, self: *E, local: usize, catalog: *shapes.Catalog) Error!bool {
    if (self.byReference(local) or self.moves.aliased(local)) return false;
    return plain(catalog, self.function.scope.locals[local].ty);
}

// Locals that may name, borrow or lend from the moved field: the source's
// alias chains and any local stored from the source (other than through a
// distinct sibling field), from such a local, or from an unknown origin,
// without an intervening value copy. A value copy publishes an independent
// RC owner, and an object a sibling field shares with the moved field carries
// an owner token for each edge, so moving one token cannot make it unique.
fn derivedLocals(comptime E: type, self: *E, source: Source) Error![]bool {
    const locals = self.function.scope.locals;
    const code = self.function.scope.instructions;
    const analysis = self.ownership.?;
    const marks = try self.allocator.alloc(bool, locals.len);
    @memset(marks, false);
    marks[source.local] = true;
    const siblings = try siblingOnly(E, self, source);
    defer self.allocator.free(siblings);
    var changed = true;
    var rounds: usize = 0;
    while (changed and rounds <= locals.len) : (rounds += 1) {
        changed = false;
        for (marks, 0..) |*linked, index| {
            if (linked.* or siblings[index] or index >= analysis.roles.len) continue;
            const role = analysis.roles[index];
            const parent = analysis.parents[index];
            const aliased = (role == .borrowed or role == .path) and parent < marks.len and marks[parent];
            if (aliased or marks[self.moves.resolve(index)]) {
                linked.* = true;
                changed = true;
            }
        }
        for (code, 0..) |instruction, pc| {
            const stack = analysis.operands[pc] orelse continue;
            if (stack.len == 0 or !fromMarked(marks, stack[stack.len - 1]) or siblingPart(E, self, source, stack[stack.len - 1])) continue;
            switch (instruction.op) {
                .store_local => |id| {
                    if (pc != 0 and code[pc - 1].op == .value_copy) continue;
                    changed = mark(marks, @backingInt(id)) or changed;
                },
                .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| {
                    changed = mark(marks, @backingInt(slot)) or changed;
                },
                else => {},
            }
        }
    }
    return marks;
}

// Locals every definition of which projects a distinct sibling field of the
// source: their alias parent is the source, but not the moved field.
fn siblingOnly(comptime E: type, self: *E, source: Source) Error![]bool {
    const code = self.function.scope.instructions;
    const analysis = self.ownership.?;
    const defined = try self.allocator.alloc(u8, self.function.scope.locals.len);
    defer self.allocator.free(defined);
    @memset(defined, 0);
    const other = 1;
    const sibling_field = 2;
    for (code, 0..) |instruction, pc| {
        const stack = analysis.operands[pc] orelse continue;
        const kind: u8 = if (stack.len != 0 and siblingPart(E, self, source, stack[stack.len - 1])) sibling_field else other;
        switch (instruction.op) {
            .store_local => |id| defined[@backingInt(id)] |= kind,
            .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| {
                defined[@backingInt(slot)] |= kind;
            },
            else => {},
        }
    }
    const result = try self.allocator.alloc(bool, defined.len);
    for (defined, result) |bits, *only| only.* = bits == sibling_field;
    return result;
}

fn mark(marks: []bool, local: usize) bool {
    if (local >= marks.len or marks[local]) return false;
    marks[local] = true;
    return true;
}

fn fromMarked(marks: []const bool, operand: sources.Source) bool {
    return switch (operand.origin) {
        .fresh => false,
        .unknown => true,
        .local => operand.local >= marks.len or marks[operand.local],
    };
}

// A part the source's load projects through a distinct field.
fn siblingPart(comptime E: type, self: *E, source: Source, operand: sources.Source) bool {
    const code = self.function.scope.instructions;
    if (operand.origin != .local or operand.local != source.local or operand.part != .field or operand.read + 1 >= code.len) return false;
    if (code[operand.read].op != .load_local) return false;
    const next = code[operand.read + 1].op;
    return next == .get_field and next.get_field != source.field;
}

fn writeback(comptime E: type, self: *E, proof: Certificate, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (pc + 10 >= code.len) return false;
    const ops = code[pc..][0..11];
    if (!localIs(ops[0].op, .load_local, proof.target) or ops[1].op != .store_local) return false;
    const value = @backingInt(ops[1].op.store_local);
    if (!localIs(ops[2].op, .load_local, proof.source.local) or ops[3].op != .store_local) return false;
    const parent = @backingInt(ops[3].op.store_local);
    const locals = self.function.scope.locals;
    if (!locals[value].usage.temporary or !locals[parent].usage.temporary) return false;
    if (value == parent) return false;
    if (value == proof.source.local or value == proof.target or parent == proof.source.local or parent == proof.target) return false;
    if (!localIs(ops[4].op, .load_local, proof.source.local) or !localIs(ops[5].op, .store_local, parent)) return false;
    if (!localIs(ops[6].op, .load_local, parent) or !localIs(ops[7].op, .load_local, value)) return false;
    if (ops[8].op != .value_copy or ops[8].op.value_copy.site != .store or ops[9].op != .update_record) return false;
    const update = ops[9].op.update_record;
    if (update.ty != locals[proof.source.local].ty or update.indices.len != 1 or update.indices[0] != proof.source.field) return false;
    if (!localIs(ops[10].op, .store_local, proof.source.local)) return false;
    // The first load may be the closed region's join; every later step is
    // straight, and the region check refuses any outside entry.
    if (self.states[pc] == null) return false;
    for (pc + 1..pc + 11) |at| if (!straight(E, self, at)) return false;
    for ([_]usize{ proof.target, value, parent }) |local| if (self.live.?.after(pc + 10, local)) return false;
    return true;
}

fn localIs(op: Op, comptime tag: std.meta.Tag(Op), index: usize) bool {
    return op == tag and @backingInt(@field(op, @tagName(tag))) == index;
}

fn shape(catalog: *shapes.Catalog, ty: typed.Type) Error!shapes.Shape {
    return catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

// Plain numeric aggregates hold no counted payload or address; callable,
// capability and handle bits are not plain. Workspace and work are bounded.
fn plain(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    var pending: [64]typed.Type = undefined;
    pending[0] = ty;
    var count: usize = 1;
    var remaining: usize = 1024;
    while (count != 0) {
        if (remaining == 0) return false;
        remaining -= 1;
        count -= 1;
        const current = pending[count];
        const layout = catalog.native.layout(current) catch return error.InternalError;
        if (layout.drop or layout.copy == .prohibited) return false;
        switch (layout.kind) {
            .scalar => if (!current.isInteger() and current != .bool and current != .unit) return false,
            .record, .variant, .domain, .array => {
                if (layout.fields.len > pending.len - count) return false;
                for (layout.fields) |field| {
                    pending[count] = field.ty;
                    count += 1;
                }
            },
            else => return false,
        }
    }
    return true;
}
