//! A bounds-tested positive index can bypass the canonical negative normalizer.
const bytecode = @import("bytecode.zig");
const managed = @import("qbe_managed.zig");
const cow_plan = @import("cow_plan.zig");
const Error = managed.Error;
const Op = @FieldType(bytecode.Instruction, "op");

/// The exact eleven-instruction normalizer and its following plain list read.
pub const Certificate = managed.PositiveIndex;

/// Prepend a checked read; every failed guard falls into the unchanged body.
/// Step-counted and versioned loops keep their original instruction sequence.
pub fn emit(comptime E: type, self: *E, start: usize) Error!void {
    if (!self.checks or self.step_checks) return;
    if (self.version != null or self.original != null) return;
    const proof = try certify(E, self, start) orelse return;
    const saved = self.pc;
    defer self.pc = saved;
    self.pc = proof.read;
    const stack = self.states[proof.read] orelse return error.InternalError;
    try self.print(" # QBE-POSITIVE-INDEX-1 start {d} read {d}\n", .{ start, proof.read });
    try managed.Lower(E).positiveRead(self, proof, stack);
    // Run the original read's result protocol even though a plain result owns
    // nothing. This preserves operand-slot clearing when another pc owns it.
    try @import("qbe_rc_ops.zig").after(E, self, self.function.scope.instructions[proof.read].op, stack);
    try self.print(" jmp @{s}{d}\n", .{ self.labelPrefix(proof.read + 1), proof.read + 1 });
}

fn certify(comptime E: type, self: *E, start: usize) Error!?Certificate {
    const code = self.function.scope.instructions;
    const proof = normalizer(code, start) orelse return null;
    const index = proof.index;
    const local = self.function.scope.locals[index];
    if (local.ty != .i64 or !local.usage.temporary) return null;
    if (self.byReference(index) or self.callerStorage(index)) return null;
    if (!try plainRead(E, self, proof)) return null;
    const prefix = self.states[start] orelse return null;
    const at_read = self.states[proof.read] orelse return null;
    if (at_read.len != prefix.len + 1 or at_read[at_read.len - 1] != .i64) return null;
    for (prefix, at_read[0..prefix.len]) |before, after| {
        const value = try self.layout(before);
        if (before != after or value.drop or value.trace) return null;
    }
    // No entry may skip the initialization or meet a fast-path read midway.
    for (start + 1..start + 11) |pc| {
        if (self.states[pc] == null) return null;
        if (pc != start + 9 and self.isBranchTarget(pc)) return null;
        if (!try quiet(E, self, pc)) return null;
    }
    if (!try quiet(E, self, start) or extraEntry(code, start)) return null;
    return proof;
}

fn normalizer(code: []const bytecode.Instruction, start: usize) ?Certificate {
    if (start + 11 >= code.len) return null;
    const proof = normalizerPrefix(code, start) orelse return null;
    if (code[start + 10].op != .buffer_operation) return null;
    const read = code[start + 10].op.buffer_operation;
    if (read.kind != .read or @backingInt(read.owner) != proof.owner) return null;
    return proof;
}

/// The canonical sign test and checked negative adjustment, ending at the
/// original index-load join. Its consuming operation is checked by the caller.
pub fn normalizerPrefix(code: []const bytecode.Instruction, start: usize) ?Certificate {
    if (start + 9 >= code.len or code[start].op != .load_local) return null;
    const index = @backingInt(code[start].op.load_local);
    if (code[start + 1].op != .push_i64 or code[start + 1].op.push_i64 != 0) return null;
    if (code[start + 2].op != .cmp_i64 or code[start + 2].op.cmp_i64 != .lt) return null;
    if (code[start + 3].op != .jump_if_false or code[start + 3].op.jump_if_false != start + 9) return null;
    if (code[start + 4].op != .buffer_operation) return null;
    const length = code[start + 4].op.buffer_operation;
    if (length.kind != .length or length.output != .u64) return null;
    if (code[start + 5].op != .cast_integer or code[start + 5].op.cast_integer != .i64) return null;
    if (!loads(code[start + 6].op, index) or code[start + 7].op != .add_i64_checked) return null;
    if (code[start + 8].op != .store_local or @backingInt(code[start + 8].op.store_local) != index) return null;
    if (!loads(code[start + 9].op, index)) return null;
    return .{ .start = start, .read = start + 10, .owner = @backingInt(length.owner), .index = index };
}

fn plainRead(comptime E: type, self: *E, proof: Certificate) Error!bool {
    const owner = proof.owner;
    const receiver = self.function.scope.locals[owner].ty;
    if (!receiver.isAggregate() or self.byReference(owner) or self.callerStorage(owner)) return false;
    const record = self.program.records[receiver.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    const element = record.shape.buffer orelse return false;
    const layout = try self.layout(element);
    // A native list's checked capacity * stride fits size_t. For strides >= 2,
    // its length cannot reach 2^63, so an unsigned-below guard also proves that
    // this signed source index is positive. Byte and zero-sized lists refuse.
    if (self.function.scope.instructions[proof.read].op.buffer_operation.output != element) return false;
    if (layout.drop or layout.trace or layout.size < 2) return false;
    return !@import("value_semantics.zig").containsLiveView(self.program.records, element);
}

/// The canonical join permits only its normalizer's own conditional edge.
pub fn extraEntry(code: []const bytecode.Instruction, start: usize) bool {
    for (code, 0..) |instruction, pc| {
        var buffer: [2]usize = undefined;
        for (@import("ownership_sources.zig").branchTargets(instruction.op, &buffer)) |target| {
            if (target == start + 9 and pc != start + 3) return true;
        }
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (arm.target == start + 9) return true;
        };
    }
    return false;
}

fn loads(op: Op, index: usize) bool {
    return op == .load_local and @backingInt(op.load_local) == index;
}

/// Skipped instructions may have no pending place, COW work or local release.
pub fn quiet(comptime E: type, self: *E, pc: usize) Error!bool {
    const cow = self.cow orelse return true;
    const site = cow.plan.at(pc);
    if (site.capture or site.fill or site.shares.len != 0) return false;
    if (site.read_captures.len != 0 or site.unique.len != 0 or site.unique_field != null) return false;
    if (cow.plan.entry(pc).len != 0) return false;
    if (cow.captures[pc].begin != cow_plan.none or cow.captures[pc].active != cow_plan.none) return false;
    const state = cow.rc orelse return true;
    for (state.plan.locals.edges) |edge| {
        if (edge.from != pc) continue;
        for (edge.releases) |release| {
            if (try @import("qbe_rc_edges.zig").releasesAt(E, self, pc, @backingInt(release.storage))) return false;
        }
    }
    return true;
}
