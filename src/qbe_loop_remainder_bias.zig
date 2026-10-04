//! Optional LLVM floor-remainder instruction selection over the exact old guard.
const facts = @import("qbe_loop_facts.zig");
const arithmetic = @import("qbe_remainder_bias.zig");
const division = @import("qbe_constant_divisor.zig");
const typed = @import("typed.zig");

/// A privacy refusal conservatively replans once without any bias metadata.
/// The analysis arena owns abandoned plans; neither pass emits output.
pub fn plan(comptime E: type, self: *E, input: facts.Input) facts.Error!void {
    self.loop_plan = try facts.plan(self.allocator, input);
    var budget: usize = 262144;
    for (self.loop_plan.loops) |loop| for (loop.actions) |action| if (action.floor_remainder_bias) |bias| {
        if (privateLeaves(E, self, bias, &budget)) continue;
        var old = input;
        old.floor_remainder_bias = false;
        self.loop_plan = try facts.plan(self.allocator, old);
        return;
    };
}

/// Only private scalar leaves already bounded by the old guard are used.
pub fn privateLeaves(comptime E: type, self: *E, bias: facts.RemainderBias, budget: *usize) bool {
    if (self.function.scope.instructions.len > 4096 or self.loop_plan.nodes.len > 4096) return false;
    for (bias.leaves) |id| if (!@import("qbe_rc_append_version.zig").safeNode(E, self, id, 0, budget)) return false;
    return true;
}

/// Refuse before emitting anything unless both concrete operation and proof
/// agree. `add` has wrapping bit semantics; no signed-overflow flag is added.
pub fn lower(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: division.Values) division.Error!bool {
    // QBE retains its signed recipe, including temporary numbering. Biasing
    // changed allocation of shared stack slots in a measured larger function.
    if (self.scalar_policy != .llvm) return false;
    if (op != .floor_rem or !info.signed or info.bits != 64) return false;
    const action = self.loopAction() orelse return false;
    const proof = action.floor_remainder_bias orelse return false;
    const literal = division.literal(E, self) orelse return false;
    if (literal != proof.recipe.divisor) return false;
    const checked = arithmetic.plan(proof.recipe.bound, proof.recipe.divisor) orelse return false;
    if (checked.addend != proof.recipe.addend) return false;
    const shifted = self.temp();
    const bits: i64 = @bitCast(checked.addend);
    try self.print(" %v{d} =l add %v{d}, {d}\n", .{ shifted, values.left, bits });
    try self.print(" %v{d} =l urem %v{d}, %v{d}\n", .{ values.result, shifted, values.right });
    return true;
}
