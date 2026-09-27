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
        for (stack, 0..) |ty, index| if (!scalar(ty) and !result.bytes.borrowed(pc, index)) return null;
        if (!quiet(E, self, pc, &budget)) return null;
        const op = code[pc].op;
        if (op == .buffer_operation) {
            const access = op.buffer_operation;
            if (access.kind != .read and access.kind != .length and access.kind != .iteration_check) return null;
            const owner = @backingInt(access.owner);
            if (!concrete(E, self, owner) or !scalar(access.output)) return null;
            if (!addOwner(&result, owner)) return null;
            read = read or access.kind == .read;
        } else if (!result.bytes.operation(pc) and !allowed(E, self, op)) return null;
    }
    return if (read) result else null;
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

/// A copied body may call only cold trap helpers; even old pure drop calls refuse.
/// Bound generated-text scanning independently of the source-instruction budget.
pub const quietCopy = @import("qbe_rc_closed_text.zig").quietCopy;

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
    return element != .unit and scalar(element);
}

fn quiet(comptime E: type, self: *E, pc: usize, budget: *usize) bool {
    const state = self.cow.?;
    if (self.function.scope.instructions[pc].inline_origin != null) return false;
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
            break :blk !self.byReference(index) and !self.callerStorage(index) and scalar(self.function.scope.locals[index].ty);
        },
        .push_integer => |value| scalar(value.ty),
        .cast_integer, .neg_integer, .acknowledge, .wrap_domain, .unwrap_domain => |ty| scalar(ty),
        .binary_integer => |binary| scalar(binary.ty),
        .push_i64, .push_bool, .push_unit, .pop, .jump, .jump_if_false, .cmp_i64, .cmp_bool, .not_bool, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked, .assert_true => true,
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
