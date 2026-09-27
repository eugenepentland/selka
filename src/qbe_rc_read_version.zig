//! Read-only list storage stays stable under an existing guarded O or H token.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const facts = @import("qbe_loop_facts.zig");
const bytes = @import("qbe_rc_byte_version.zig");
/// A fixed bounded owner set; proof construction allocates no scratch arrays.
pub const Certificate = struct { owners: [8]usize = undefined, count: usize = 0, bytes: bytes.Certificate = .{} };
/// Errors shared by journal metadata and guarded loop emission.
pub const Error = frame.Error;

/// Admit only a previously planned read-only loop with no physical token effects.
pub fn certify(comptime E: type, self: *E, head: usize, back: usize) ?Certificate {
    const rc = frame.get(E, self) orelse return null;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or back < head or back >= code.len or back - head > facts.max_body) return null;
    if (rc.readonly or rc.contract.result == .borrowed or self.function.scope.locals.len > 256) return null;
    if (self.states[head] == null or self.states[head].?.len != 0) return null;
    var result: Certificate = .{};
    var read = false;
    var budget: usize = 262144;
    for (head..back + 1) |pc| {
        if (!charge(&budget, 1)) return null;
        if (code[pc].op != .get_index) continue;
        const found = bytes.find(E, self, pc, head, &budget) orelse return null;
        if (result.bytes.count == result.bytes.reads.len or !addOwner(&result, found.owner)) return null;
        result.bytes.reads[result.bytes.count] = found;
        result.bytes.count += 1;
        read = true;
    }
    for (head..back + 1) |pc| {
        const stack = self.states[pc] orelse return null;
        if (!charge(&budget, stack.len + rc.plan.locals.edges.len + rc.plan.records.transfers.len + rc.plan.records.writes.len)) return null;
        const captured = captureAt(E, self, pc) orelse captureAt(E, self, pc -| 1);
        for (stack, 0..) |ty, index| {
            if (plainWord(E, self, ty) or result.bytes.borrowed(pc, index)) continue;
            if (!capturedList(E, self, captured, pc != head and index + 1 == stack.len, ty)) return null;
        }
        if (!quiet(E, self, pc, &budget)) return null;
        const op = code[pc].op;
        if (op == .buffer_operation) {
            const access = op.buffer_operation;
            if (access.kind != .read and access.kind != .length and access.kind != .iteration_check) return null;
            if (!plainWord(E, self, access.output)) return null;
            switch (anchor(E, self, @backingInt(access.owner), head, back, &budget) orelse return null) {
                .journal => |owner| if (!addOwner(&result, owner)) return null,
                .caller => {},
            }
            read = read or access.kind == .read;
        } else if (captured == null) {
            if (!result.bytes.operation(pc) and !allowed(E, self, op)) return null;
        }
    }
    return if (read) result else null;
}

/// The list a capture pair holds on top of the stack between its two steps.
fn capturedList(comptime E: type, self: *E, captured: ?usize, top: bool, ty: typed.Type) bool {
    const target = captured orelse return false;
    return top and ty == self.function.scope.locals[target].ty;
}

/// What keeps a read list's storage alive across the loop: an initialized O
/// or H journal token the guard tests, or the caller, for an unwritten
/// read-only parameter (RC-READ-LIST-VERSION-2).
const Anchor = union(enum) { journal: usize, caller };

/// Resolve a buffer owner to its anchor. A compiler temporary every store of
/// which is an adjacent capture `load_local P; store_local T` of one list P
/// the loop never writes reads exactly P's list, so it takes P's anchor.
fn anchor(comptime E: type, self: *E, owner: usize, head: usize, back: usize, budget: *usize) ?Anchor {
    if (callerAnchored(E, self, owner)) return .caller;
    if (concrete(E, self, owner)) return .{ .journal = owner };
    const locals = self.function.scope.locals;
    if (owner >= locals.len or owner < self.function.signature.parameter_count or !locals[owner].usage.temporary) return null;
    if (self.byReference(owner) or self.callerStorage(owner) or !plainList(E, self, locals[owner].ty)) return null;
    const code = self.function.scope.instructions;
    if (!charge(budget, code.len)) return null;
    var source: ?usize = null;
    for (code, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == owner) {
            const from = captureSource(E, self, pc) orelse return null;
            if (source != null and source.? != from) return null;
            source = from;
        },
        .move_local, .ref_local, .drop_local => |id| if (@backingInt(id) == owner) return null,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |slot| if (@backingInt(slot) == owner) return null;
        },
        else => {},
    };
    const from = source orelse return null;
    for (code[head .. back + 1]) |instruction| switch (instruction.op) {
        .store_local, .move_local, .ref_local, .drop_local => |id| if (@backingInt(id) == from) return null,
        else => {},
    };
    if (callerAnchored(E, self, from)) return .caller;
    if (concrete(E, self, from)) return .{ .journal = from };
    return null;
}

/// The list local an adjacent capture at `pc` (a `store_local`) reads.
fn captureSource(comptime E: type, self: *E, pc: usize) ?usize {
    const code = self.function.scope.instructions;
    if (pc == 0 or self.isBranchTarget(pc) or code[pc - 1].op != .load_local) return null;
    const from = @backingInt(code[pc - 1].op.load_local);
    const locals = self.function.scope.locals;
    if (from >= locals.len or locals[from].ty != locals[@backingInt(code[pc].op.store_local)].ty) return null;
    if (self.byReference(from)) return null;
    return from;
}

/// The capture target when `pc` loads a plain list that the next instruction
/// stores into a temporary with no other kind of definition.
fn captureAt(comptime E: type, self: *E, pc: usize) ?usize {
    const code = self.function.scope.instructions;
    if (pc + 1 >= code.len or code[pc].op != .load_local or code[pc + 1].op != .store_local) return null;
    const target = @backingInt(code[pc + 1].op.store_local);
    if (captureSource(E, self, pc + 1) == null) return null;
    const local = self.function.scope.locals[target];
    if (target < self.function.signature.parameter_count or !local.usage.temporary) return null;
    if (!plainList(E, self, local.ty)) return null;
    if (self.byReference(target) or self.callerStorage(target)) return null;
    return target;
}

/// A read-only list parameter the function never rebinds: the caller owns it
/// for the whole activation, and a quiet loop can neither release nor resize it.
fn callerAnchored(comptime E: type, self: *E, local: usize) bool {
    if (local >= self.function.signature.parameter_count or self.byReference(local) or self.callerStorage(local)) return false;
    if (@import("ownership_model.zig").writesParameter(self.function, local)) return false;
    if (!plainList(E, self, self.function.scope.locals[local].ty)) return false;
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .store_local, .move_local, .ref_local, .drop_local => |id| if (@backingInt(id) == local) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |slot| if (@backingInt(slot) == local) return false;
        },
        else => {},
    };
    return true;
}

/// A one-word value that owns nothing: an integer, `bool`, unit or a plain
/// domain such as `float`.
fn plainWord(comptime E: type, self: *E, ty: typed.Type) bool {
    if (scalar(ty)) return true;
    if (!self.isScalar(ty)) return false;
    const shape = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !shape.counted and !shape.unique_drop;
}

/// A non-box list whose elements are plain words.
fn plainList(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    const element = record.shape.buffer orelse return false;
    return element != .unit and plainWord(E, self, element);
}

/// Test only initialized metadata before the existing range/payload guards.
/// False means original-loop fallback, never an ownership operation or trap.
pub fn guard(comptime E: type, self: *E, proof: Certificate, head: usize) Error!void {
    try self.print(" # RC-READ-LIST-VERSION-1 head {d}\n", .{head});
    for (proof.owners[0..proof.count]) |owner| {
        const live = self.temp();
        const role = self.temp();
        const ordinary = self.temp();
        const held = self.temp();
        const ready = self.temp();
        const label = self.temp();
        try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w loaduw %v{d}\n", .{
            live, try frame.guard(E, self, owner), role, try frame.entryField(E, self, owner, 24),
        });
        try self.print(" %v{d} =w ceqw %v{d}, 2\n", .{ ordinary, role });
        if (proof.bytes.owns(owner)) {
            try self.print(" %v{d} =w copy %v{d}\n", .{ ready, ordinary });
        } else {
            try self.print(" %v{d} =w ceqw %v{d}, 8\n %v{d} =w or %v{d}, %v{d}\n", .{ held, role, ready, ordinary, held });
        }
        try self.print(" %v{d} =w and %v{d}, %v{d}\n jnz %v{d}, @rcreadloop{d}, @oi{d}\n@rcreadloop{d}\n", .{
            ready, ready, live, ready, label, head, label,
        });
    }
    try bytes.guard(E, self, proof.bytes, head);
}

/// A copied body may call only cold trap helpers and the heap-free scalar
/// float and integer helpers; even old pure drop calls refuse. Bound
/// generated-text scanning independently of the source-instruction budget.
pub fn quietCopy(text: []const u8) bool {
    if (text.len > 1024 * 1024) return false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "call %") != null) return false;
        const at = std.mem.indexOf(u8, line, "call $") orelse continue;
        const callee = line[at + "call $".len ..];
        if (std.mem.startsWith(u8, callee, "myl_qbe_fail_")) continue;
        if (std.mem.startsWith(u8, callee, "myl_qbe_float_unary(") or std.mem.startsWith(u8, callee, "myl_qbe_float_check(")) continue;
        if (std.mem.startsWith(u8, callee, "myl_qbe_int_")) continue;
        return false;
    }
    return true;
}

fn concrete(comptime E: type, self: *E, owner: usize) bool {
    if (owner >= self.function.scope.locals.len or self.byReference(owner) or self.callerStorage(owner)) return false;
    const state = self.cow.?;
    if (state.plan.place(owner) != null or self.moves.resolve(owner) != owner) return false;
    // A hidden iterator can retain semantic ancestry while its RC store owns
    // a distinct H journal and physical %lN word. Reads use that exact word.
    if (state.plan.aliases[owner] != cow.none and !cow.iterationOwner(self.function, owner)) return false;
    const rc = state.rc.?;
    if ((rc.plan.journal.slot(owner) catch return false) == null) return false;
    const ty = self.function.scope.locals[owner].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    const element = record.shape.buffer orelse return false;
    return element != .unit and plainWord(E, self, element);
}

fn quiet(comptime E: type, self: *E, pc: usize, budget: *usize) bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (site.unique.len != 0 or site.unique_field != null or site.capture or site.fill) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    if (@import("qbe_rc_dictionary_effects.zig").intercepted(E, self, pc)) return false;
    // Match edges.after: only fallthrough store releases are emitted today.
    // quietCopy independently refuses every actual cleanup call in the copy.
    for (state.rc.?.plan.locals.edges) |edge| {
        if (edge.from != pc or edge.to != pc + 1) continue;
        for (edge.releases) |release| {
            // releasesAt also follows possible physical receiver anchors.
            const locals = self.function.scope.locals.len;
            if (!charge(budget, locals * locals + state.rc.?.plan.locals.edges.len)) return false;
            if (@import("qbe_rc_edges.zig").releasesAt(E, self, pc, @backingInt(release.storage)) catch true) return false;
        }
    }
    return true;
}

fn scalar(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}

fn allowed(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) bool {
    return switch (op) {
        .load_local, .store_local => |id| blk: {
            const index = @backingInt(id);
            break :blk !self.byReference(index) and !self.callerStorage(index) and plainWord(E, self, self.function.scope.locals[index].ty);
        },
        .push_integer => |value| plainWord(E, self, value.ty),
        .cast_integer, .neg_integer, .acknowledge, .wrap_domain, .unwrap_domain => |ty| plainWord(E, self, ty),
        .binary_integer => |binary| plainWord(E, self, binary.ty),
        .cmp_domain => |comparison| plainWord(E, self, comparison.ty),
        .push_i64, .push_bool, .push_unit, .pop, .jump, .jump_if_false, .cmp_i64, .cmp_bool, .not_bool => true,
        .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked => true,
        .assert_true, .unary_float => true,
        else => false,
    };
}

fn charge(budget: *usize, cost: usize) bool {
    return bytes.charge(budget, cost);
}

fn addOwner(proof: *Certificate, owner: usize) bool {
    if (std.mem.indexOfScalar(usize, proof.owners[0..proof.count], owner) != null) return true;
    if (proof.count == proof.owners.len) return false;
    proof.owners[proof.count] = owner;
    proof.count += 1;
    return true;
}
