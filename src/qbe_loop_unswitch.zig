//! Bounded invariant literal dispatch outside a fully checked native loop.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const targets = @import("ownership_sources.zig");
const text = @import("qbe_loop_unswitch_text.zig");
const model = @import("qbe_loop_unswitch_model.zig");
const max_locals = 2048;
const max_code = 8192;
const max_loop = 4096;
const max_work = 1048576;
/// No partial literal selection: larger dispatches retain their original loop.
pub const max_values = model.max_values;
/// Fixed bounded condition storage; recognition allocates no scratch arrays.
pub const max_conditions = model.max_conditions;

/// One pure scalar comparison feeding an original conditional jump.
pub const Condition = model.Condition;
/// Every comparison of the chosen invariant local in the loop.
pub const Conditions = model.Conditions;
/// The complete set of equality literals admitted by one dispatch.
pub const Values = model.Values;
/// Bytecode authority for a single-entry loop and its immutable scalar local.
pub const Certificate = model.Certificate;

/// Specialize only an unaccounted checked build, before call-site instrumentation.
pub fn finish(comptime E: type, self: *E, input: []u8) text.Error![]u8 {
    if (self.step_checks or self.frame_checks or !self.checks) return input;
    const code = self.function.scope.instructions;
    if (code.len > max_code or self.function.scope.locals.len > max_locals) return input;
    var budget: usize = max_work;
    var best: ?Certificate = null;
    for (code, 0..) |instruction, back| {
        if (!charge(&budget, 1)) return input;
        if (instruction.op != .jump or instruction.op.jump >= back) continue;
        const candidate = certify(E, self, instruction.op.jump, back, &budget) orelse continue;
        if (best == null or candidate.conditions.len > best.?.conditions.len) best = candidate;
    }
    return if (best) |proof| text.rewrite(self.allocator, input, proof) else input;
}

/// Admit a counted single-entry region with an unwritten, unaliased i64 selector.
pub fn certify(comptime E: type, self: *E, head: usize, back: usize, budget: *usize) ?Certificate {
    const code = self.function.scope.instructions;
    const locals = self.function.scope.locals;
    if (back >= code.len or head + 4 >= back or back - head > max_loop) return null;
    if (locals.len > max_locals or !charge(budget, code.len + (back - head) * 4)) return null;
    if (!counted(code, head, back) or !empty(self.states, head)) return null;
    const bounds: Bounds = .{ .head = head, .back = back };
    for (code, 0..) |instruction, pc| {
        if (pc >= head and pc <= back) continue;
        if (instruction.op == .switch_variant and !charge(budget, instruction.op.switch_variant.arms.len)) return null;
        if (!targets.targetsSatisfy(instruction.op, pc, bounds, entered)) return null;
    }
    var written: [max_locals]bool = @splat(false);
    for (code[head .. back + 1]) |instruction| switch (instruction.op) {
        .store_local, .move_local, .ref_local, .drop_local => |id| written[@backingInt(id)] = true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (!charge(budget, 1)) return null;
            if (arm.slot) |slot| written[@backingInt(slot)] = true;
        },
        else => {},
    };
    var counts: [max_locals]u16 = @splat(0);
    var chosen: ?usize = null;
    for (head + 4..back - 2) |pc| {
        const match = comparison(code, pc) orelse continue;
        if (match.condition.predicate != .eq or written[match.slot]) continue;
        if (!empty(self.states, pc) or locals[match.slot].ty != .i64) continue;
        if (self.byReference(match.slot) or self.callerStorage(match.slot) or self.moves.aliased(match.slot)) continue;
        counts[match.slot] += 1;
        if (chosen == null or counts[match.slot] > counts[chosen.?]) chosen = match.slot;
    }
    const slot = chosen orelse return null;
    // A reference outside the region could let a call mutate the selector.
    if (referenced(code, slot)) return null;
    var result: Certificate = .{ .head = head, .back = back, .slot = slot, .conditions = .{}, .values = .{} };
    for (head + 4..back - 2) |pc| {
        const match = comparison(code, pc) orelse continue;
        if (match.slot != slot or !empty(self.states, pc)) continue;
        if (result.conditions.len == max_conditions) return null;
        result.conditions.items[result.conditions.len] = match.condition;
        result.conditions.len += 1;
        if (match.condition.predicate != .eq) continue;
        if (std.mem.indexOfScalar(i64, result.values.items[0..result.values.len], match.condition.value) != null) continue;
        if (result.values.len == max_values) return null;
        result.values.items[result.values.len] = match.condition.value;
        result.values.len += 1;
    }
    return if (result.values.len != 0) result else null;
}

const Match = struct { slot: usize, condition: Condition };
fn referenced(code: []const bytecode.Instruction, slot: usize) bool {
    for (code) |instruction| if (instruction.op == .ref_local and @backingInt(instruction.op.ref_local) == slot) return true;
    return false;
}
fn comparison(code: []const bytecode.Instruction, pc: usize) ?Match {
    if (pc + 3 >= code.len or code[pc].op != .load_local or code[pc + 1].op != .push_i64) return null;
    if (code[pc + 2].op != .cmp_i64 or code[pc + 3].op != .jump_if_false) return null;
    return .{ .slot = @backingInt(code[pc].op.load_local), .condition = .{
        .pc = pc + 3,
        .value = code[pc + 1].op.push_i64,
        .predicate = code[pc + 2].op.cmp_i64,
        .target = code[pc + 3].op.jump_if_false,
    } };
}
fn counted(code: []const bytecode.Instruction, head: usize, back: usize) bool {
    if (code[head].op != .load_local or code[head + 2].op != .cmp_i64) return false;
    const predicate = code[head + 2].op.cmp_i64;
    if (predicate != .lt and predicate != .le) return false;
    if (code[head + 1].op != .load_local and code[head + 1].op != .push_i64) return false;
    return code[head + 3].op == .jump_if_false and code[head + 3].op.jump_if_false == back + 1;
}
const Bounds = struct { head: usize, back: usize };
fn entered(_: usize, to: usize, bounds: Bounds) bool {
    return to <= bounds.head or to > bounds.back;
}
fn empty(states: []const ?[]const typed.Type, pc: usize) bool {
    if (pc >= states.len) return false;
    const stack = states[pc] orelse return false;
    return stack.len == 0;
}
fn charge(budget: *usize, cost: usize) bool {
    if (cost > budget.*) return false;
    budget.* -= cost;
    return true;
}
