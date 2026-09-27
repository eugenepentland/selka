//! Exact immutable-byte reads keep a dynamically empty operand guard empty.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
const cow = @import("cow_plan.zig");
/// One adjacent raw owner load, scalar index load and checked byte read.
pub const Read = struct { pc: usize, owner: usize, operand: usize };
/// Fixed-size emission facts; no scratch allocation or journal layout change.
pub const Certificate = struct {
    reads: [8]Read = undefined,
    count: usize = 0,

    /// Only the two states following a certified raw load contain managed bits.
    pub fn borrowed(self: Certificate, pc: usize, operand: usize) bool {
        for (self.reads[0..self.count]) |read| {
            if ((pc == read.pc - 1 or pc == read.pc) and operand == read.operand) return true;
        }
        return false;
    }
    /// The certificate admits only these exact load and index instructions.
    pub fn operation(self: Certificate, pc: usize) bool {
        for (self.reads[0..self.count]) |read| if (pc == read.pc - 2 or pc == read.pc) return true;
        return false;
    }
    /// Byte homes require O, unlike existing list iteration's O-or-H guard.
    pub fn owns(self: Certificate, owner: usize) bool {
        for (self.reads[0..self.count]) |read| if (read.owner == owner) return true;
        return false;
    }
};

/// Charge source/state/branch visits before inspecting an exact three-op read.
pub fn find(comptime E: type, self: *E, pc: usize, head: usize, budget: *usize) ?Read {
    const code = self.function.scope.instructions;
    if (pc < head + 2 or pc + 1 >= code.len or code[pc].op != .get_index) return null;
    const first = code[pc - 2].op;
    const index = code[pc - 1].op;
    if (first != .load_local or index != .load_local) return null;
    if (!charge(budget, 2 * self.function.scope.locals.len + 4)) return null;
    const owner = @backingInt(first.load_local);
    const local_index = @backingInt(index.load_local);
    if (!home(E, self, owner, budget) or self.byReference(local_index) or self.callerStorage(local_index)) return null;
    const ty = self.function.scope.locals[owner].ty;
    if (code[pc].op.get_index.ty != ty or self.function.scope.locals[local_index].ty != .i64) return null;
    const before = self.states[pc - 2] orelse return null;
    const loaded = self.states[pc - 1] orelse return null;
    const input = self.states[pc] orelse return null;
    const after = self.states[pc + 1] orelse return null;
    if (!charge(budget, before.len + loaded.len + input.len + after.len)) return null;
    const operand = before.len;
    if (loaded.len != operand + 1 or input.len != operand + 2 or after.len != operand + 1) return null;
    for (before) |value| if (!scalar(value)) return null;
    if (!std.mem.eql(typed.Type, before, loaded[0..operand])) return null;
    if (!std.mem.eql(typed.Type, before, input[0..operand])) return null;
    if (!std.mem.eql(typed.Type, before, after[0..operand])) return null;
    if (loaded[operand] != ty or input[operand] != ty or input[operand + 1] != .i64 or after[operand] != .u8) return null;
    const rc = self.cow.?.rc.?;
    if ((rc.plan.journal.slot(self.function.scope.locals.len + operand) catch return null) == null) return null;
    if (!suffixEntry(code, pc, budget)) return null;
    return .{ .pc = pc, .owner = owner, .operand = operand };
}

fn home(comptime E: type, self: *E, owner: usize, budget: *usize) bool {
    if (owner >= self.function.scope.locals.len or self.byReference(owner) or self.callerStorage(owner)) return false;
    const state = self.cow.?;
    if (state.plan.place(owner) != null or state.plan.aliases[owner] != cow.none or self.moves.resolve(owner) != owner) return false;
    const ty = self.function.scope.locals[owner].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!typed.isByteString(record) or record.shape.buffer != .u8) return false;
    if (!chargeHolds(self.function, ty, budget)) return false;
    if (@import("qbe_rc_holds.zig").mayHold(E, self, ty)) return false;
    return (state.rc.?.plan.journal.slot(owner) catch return false) != null;
}

/// Every kind of explicit successor must leave the suffix to fallthrough alone.
pub fn suffixEntry(code: []const bytecode.Instruction, pc: usize, budget: *usize) bool {
    for (code, 0..) |instruction, from| {
        if (!charge(budget, 1)) return false;
        if (instruction.op == .switch_variant and !charge(budget, instruction.op.switch_variant.arms.len)) return false;
        if (!@import("ownership_sources.zig").targetsSatisfy(instruction.op, from, pc, outsideSuffix)) return false;
    }
    return true;
}
fn outsideSuffix(_: usize, target: usize, pc: usize) bool {
    return target != pc and (pc == 0 or target != pc - 1);
}

/// Precharge mayHold's local scan and each possible full iteration-owner scan.
/// Matching named locals are deliberately charged too, an upper bound.
pub fn chargeHolds(function: bytecode.Function, ty: typed.Type, budget: *usize) bool {
    if (!charge(budget, function.scope.locals.len)) return false;
    for (function.scope.locals) |local| {
        if (local.ty == ty and !charge(budget, function.scope.instructions.len)) return false;
    }
    return true;
}
fn scalar(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}
/// Shared bounded work accounting, also used by the enclosing loop proof.
pub fn charge(budget: *usize, cost: usize) bool {
    if (cost > budget.*) return false;
    budget.* -= cost;
    return true;
}

/// Check actual metadata without clearing it; failure keeps the original loop.
pub fn guard(comptime E: type, self: *E, proof: Certificate, head: usize) frame.Error!void {
    if (proof.count == 0) return;
    try self.print(" # RC-READ-BYTES-VERSION-1 head {d}\n", .{head});
    for (proof.reads[0..proof.count], 0..) |read, i| {
        var repeated = false;
        for (proof.reads[0..i]) |prior| repeated = repeated or prior.operand == read.operand;
        if (repeated) continue;
        const live = self.temp();
        const empty = self.temp();
        const address = try frame.guard(E, self, self.function.scope.locals.len + read.operand);
        try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w ceqw %v{d}, 0\n jnz %v{d}, @rcbyteempty{d}, @oi{d}\n@rcbyteempty{d}\n", .{
            live, address, empty, live, empty, empty, head, empty,
        });
    }
}

/// Only an exact read in the guarded fast copy may omit its known-empty drop.
pub fn emptyOperand(comptime E: type, self: *E, operand: usize) bool {
    const active = self.version orelse return false;
    const proof = active.read orelse return false;
    for (proof.bytes.reads[0..proof.bytes.count]) |read| if (read.pc == self.pc and read.operand == operand) return true;
    return false;
}
