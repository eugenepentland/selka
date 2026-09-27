//! Exact evaluated dictionary writes without a redundant receiver pin scope.
const std = @import("std");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const model = @import("rc_dictionary_tail.zig");
const Certificate = model.Certificate;
/// Optional proof refusals keep ordinary emission; allocation errors propagate.
pub const Error = error{ InternalError, OutOfMemory };

/// Run after physical COW planning and alternate-entry selection are final.
/// The budget charges candidate code, not every nested primitive proof visit.
pub fn finalize(comptime E: type, self: *E) Error!void {
    const state = self.cow.?.rc orelse return;
    state.plan.dictionary_tails = &.{};
    if (!state.active or state.readonly or state.contract.result == .borrowed) return;
    const code = self.function.scope.instructions;
    if (code.len > 4096) return;
    var budget: usize = 262144;
    var found: std.ArrayList(Certificate) = .empty;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .buffer_operation or instruction.op.buffer_operation.kind != .write or pc < 4) continue;
        const proof = tail(E, self, pc - 4) orelse continue;
        if (code.len > budget) break;
        budget -= code.len;
        if (!writers(E, self, proof) or !quiet(E, self, proof)) continue;
        try found.append(self.allocator, proof);
    }
    state.plan.dictionary_tails = try found.toOwnedSlice(self.allocator);
}

/// Capture and terminal use share one whole-lifetime proof, including backedges.
pub fn receiver(comptime E: type, self: *E, local: usize) bool {
    const state = self.cow.?.rc orelse return false;
    for (state.plan.dictionary_tails) |proof| if (proof.receiver == local) return true;
    return false;
}

/// Only the original receiver store may omit its second uniqueness operation.
pub fn store(comptime E: type, self: *E, local: usize) bool {
    const state = self.cow.?.rc orelse return false;
    for (state.plan.dictionary_tails) |proof| if (proof.receiver == local and self.pc == proof.start + 1) return true;
    return false;
}

fn tail(comptime E: type, self: *E, start: usize) ?Certificate {
    const code = self.function.scope.instructions;
    const ops = code[start..][0..5];
    if (ops[0].op != .load_local or ops[1].op != .store_local or ops[2].op != .load_local or ops[3].op != .load_local) return null;
    const proof: Certificate = .{
        .start = start,
        .root = @backingInt(ops[0].op.load_local),
        .receiver = @backingInt(ops[1].op.store_local),
        .key = @backingInt(ops[2].op.load_local),
        .value = @backingInt(ops[3].op.load_local),
    };
    const operation = ops[4].op.buffer_operation;
    if (@backingInt(operation.owner) != proof.receiver or operation.output != .unit) return null;
    const locals = self.function.scope.locals;
    const ty = locals[proof.root].ty;
    if (locals[proof.receiver].ty != ty or !ty.isAggregate()) return null;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .dictionary or record.collection.box) return null;
    if (record.collection.key != locals[proof.key].ty or record.shape.buffer != locals[proof.value].ty) return null;
    if (!scalar(E, self, locals[proof.value].ty)) return null;
    if (!scalar(E, self, locals[proof.key].ty) and !textKey(E, self, locals[proof.key].ty)) return null;
    if (!ordinary(E, self, proof.root, .local) or !keyOwner(E, self, proof.key)) return null;
    if (referenced(E, self, proof.value)) return null;
    if (@import("qbe_rc_holds.zig").mayHold(E, self, ty) or
        @import("qbe_rc_holds.zig").mayHold(E, self, locals[proof.key].ty)) return null;
    if (proof.receiver < self.function.signature.parameter_count or !locals[proof.receiver].usage.temporary) return null;
    if (referenced(E, self, proof.receiver) or cow.iterationOwner(self.function, proof.receiver)) return null;
    const plan = self.cow.?.plan;
    if (plan.place(proof.receiver) != null or plan.aliases[proof.receiver] != proof.root) return null;
    const heights = [_]usize{ 0, 1, 0, 1, 2 };
    for (ops, heights, start..) |instruction, height, pc| {
        const inputs = self.states[pc] orelse return null;
        if (inputs.len != height or instruction.inline_origin != null) return null;
        if (pc != start and self.isBranchTarget(pc)) return null;
    }
    if (!self.live.?.before(start + 4, proof.root)) return null;
    if (self.live.?.after(start + 4, proof.receiver)) return null;
    return proof;
}

fn ordinary(comptime E: type, self: *E, index: usize, origin: typed.LocalOrigin) bool {
    const local = self.function.scope.locals[index];
    if (index < self.function.signature.parameter_count or local.usage.temporary or local.origin != origin) return false;
    if (referenced(E, self, index)) return false;
    const plan = self.cow.?.plan;
    if (plan.place(index) != null or plan.aliases[index] != cow.none) return false;
    const entry = self.cow.?.rc.?.plan.locals.entry[index];
    return @backingInt(entry.storage) == index and (entry.ownership == .empty or entry.ownership == .plain);
}
// A semantic collection_copy hint does not change the named local's physical
// publication: this exact list read is loaned, then its ordinary STORE_LOCAL
// acquires O and clears the input loan. No pattern/iterator/temp store qualifies.
fn keyOwner(comptime E: type, self: *E, index: usize) bool {
    const local = self.function.scope.locals[index];
    if (local.origin != .collection_copy) return ordinary(E, self, index, .local);
    if (!textKey(E, self, local.ty) or !ordinary(E, self, index, .collection_copy)) return false;
    const code = self.function.scope.instructions;
    var found = false;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .store_local or @backingInt(instruction.op.store_local) != index) continue;
        if (found or pc == 0 or self.isBranchTarget(pc)) return false;
        found = true;
        const previous = code[pc - 1].op;
        if (previous != .buffer_operation or previous.buffer_operation.kind != .read) return false;
        const operation = previous.buffer_operation;
        const parent = self.function.scope.locals[@backingInt(operation.owner)].ty;
        if (!parent.isAggregate() or operation.output != local.ty) return false;
        const record = self.program.records[parent.recordIndex()];
        if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
        if (record.shape.buffer != local.ty) return false;
    }
    return found;
}

fn referenced(comptime E: type, self: *E, index: usize) bool {
    return self.byReference(index) or self.callerStorage(index) or self.moves.resolve(index) != index;
}
fn textKey(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .string and !record.collection.box;
}
fn scalar(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isInteger() and ty != .bool) return false;
    const shape = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !shape.counted and !shape.unique_drop and (self.layout(ty) catch return false).size != 0;
}

// Root/key stores are canonical O publication. The capture has one raw store,
// no other read/writer, and no hidden clone installation. Its guard starts zero
// and stays zero through the terminal write, so every backedge repeats zero.
fn writers(comptime E: type, self: *E, proof: Certificate) bool {
    if (!model.writers(self.function.scope.instructions, proof)) return false;
    const plan = self.cow.?.plan;
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == proof.receiver or unique.alias == proof.receiver) return false;
        if (site.unique_field) |place| if (place.parent == proof.receiver) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == proof.receiver) return false;
    for (plan.aliases) |parent| if (parent == proof.receiver) return false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (place.parent == proof.receiver) return false;
        if (place.box) |box| if (box.owner == proof.receiver) return false;
    };
    return true;
}

// The only effect admitted before the write is exactly the existing first
// root check. Raw loads neither publish nor clean up; backing cannot relocate
// until the original terminal runtime call, whose arguments are private slots.
fn quiet(comptime E: type, self: *E, proof: Certificate) bool {
    const state = self.cow.?;
    const plan = state.plan;
    for (proof.start..proof.start + 5) |pc| {
        const site = plan.at(pc);
        if (site.capture or site.fill or site.unique_field != null) return false;
        if (site.shares.len != 0 or site.read_captures.len != 0 or plan.entry(pc).len != 0) return false;
        if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
        if (pc == proof.start) {
            if (site.unique.len != 1 or site.unique[0].local != proof.root or site.unique[0].alias != cow.none) return false;
        } else if (site.unique.len != 0) return false;
        for (state.rc.?.plan.locals.edges) |edge| {
            if (edge.from != pc or edge.to != pc + 1) continue;
            for (edge.releases) |release| {
                const at = @backingInt(release.storage);
                if (@import("qbe_rc_edges.zig").releasesAt(E, self, pc, at) catch true) return false;
            }
        }
        for (state.rc.?.plan.field_transfers) |transfer| if (transfer.projection == pc or transfer.commit == pc) return false;
    }
    return true;
}
