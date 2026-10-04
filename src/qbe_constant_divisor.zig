//! Exact constant division using unsigned multiply-high and bounded shifts.
const std = @import("std");
const typed = @import("typed.zig");

/// A 64-bit unsigned divisor's multiply/shift recipe. Powers of two need no multiply.
pub const Plan = struct { multiplier: u64, shift: u6, add: bool, power: bool };

/// Derive floor(n / divisor) for every u64 numerator using 128-bit compile-time math.
pub fn plan(divisor: u64) ?Plan {
    if (divisor == 0) return null;
    const shift: u6 = @intCast(63 - @clz(divisor));
    if (std.math.isPowerOfTwo(divisor)) return .{ .multiplier = 0, .shift = shift, .add = false, .power = true };
    const numerator = @as(u128, 1) << (64 + @as(u7, shift));
    var multiplier = numerator / divisor;
    const remainder: u64 = @intCast(numerator % divisor);
    const add = divisor - remainder >= @as(u64, 1) << shift;
    if (add) {
        multiplier *= 2;
        if (@as(u128, remainder) * 2 >= divisor) multiplier += 1;
    }
    return .{ .multiplier = @truncate(multiplier + 1), .shift = shift, .add = add, .power = false };
}

/// Execute the recipe as a reference for exhaustive and boundary proof tests.
pub fn quotient(recipe: Plan, numerator: u64) u64 {
    if (recipe.power) return numerator >> recipe.shift;
    const high: u64 = @intCast((@as(u128, numerator) * recipe.multiplier) >> 64);
    const corrected = if (recipe.add) ((numerator - high) >> 1) + high else high;
    return corrected >> recipe.shift;
}

/// Emission failures shared with scalar lowering.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Already evaluated operands and destination of a binary operation.
pub const Values = struct { left: usize, right: usize, result: usize };

/// Replace a literal-divisor operation, retaining zero and signed quotient traps.
pub fn lower(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: Values) Error!bool {
    const fixed = literal(E, self) orelse return false;
    if (fixed == 0) return false;
    const signed_fixed: i64 = if (info.signed) std.math.cast(i64, fixed) orelse return false else 0;
    const magnitude: u64 = if (info.signed) @intCast(if (fixed < 0) -fixed else fixed) else std.math.cast(u64, fixed) orelse return false;
    const recipe = plan(magnitude) orelse return false;
    const divides = op == .div or op == .floor_div;
    const flooring = op == .floor_div or op == .floor_rem;
    if (info.signed and signed_fixed == -1) {
        if (!divides) {
            try self.print(" %v{d} =l copy 0\n", .{values.result});
            return true;
        }
        const minimum: i64 = @intCast(-(@as(i128, 1) << @intCast(info.bits - 1)));
        const flag = self.temp();
        try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @overflow{d}, @checked{d}\n@overflow{d}\n", .{ flag, values.left, minimum, flag, values.result, values.result, values.result });
        try self.print(" call $myl_qbe_fail_overflow_op(l %ctx, l {d}, l %v{d}, l %v{d}, l {d})\n jmp @failure\n@checked{d}\n", .{ @backingInt(op), values.left, values.right, info.bits, values.result });
        try self.print(" %v{d} =l neg %v{d}\n", .{ values.result, values.left });
        return true;
    }
    // A positive power-of-two floor operation is exact directly on signed bits.
    const direct_power = !info.signed or (flooring and signed_fixed > 0);
    if (recipe.power and direct_power) {
        try self.print(" %v{d} =l {s} %v{d}, {d}\n", .{ values.result, if (divides) (if (info.signed) "sar" else "shr") else "and", values.left, if (divides) @as(u64, recipe.shift) else magnitude - 1 });
        return true;
    }
    var dividend = values.left;
    var mask: ?usize = null;
    if (info.signed) {
        const sign = self.temp();
        const flipped = self.temp();
        dividend = self.temp();
        try self.print(" %v{d} =l sar %v{d}, 63\n %v{d} =l xor %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ sign, values.left, flipped, values.left, sign, dividend, flipped, sign });
        mask = sign;
        if (signed_fixed < 0) {
            mask = self.temp();
            try self.print(" %v{d} =l xor %v{d}, -1\n", .{ mask.?, sign });
        }
    }
    const unsigned = try emitQuotient(E, self, recipe, dividend);
    var result = unsigned;
    if (mask) |sign| {
        const flipped = self.temp();
        result = self.temp();
        try self.print(" %v{d} =l xor %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ flipped, unsigned, sign, result, flipped, sign });
    }
    if (!divides or (flooring and info.signed)) {
        const product = self.temp();
        const remainder = self.temp();
        try self.print(" %v{d} =l mul %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ product, result, values.right, remainder, values.left, product });
        if (!divides) result = remainder;
        if (flooring and info.signed) {
            const nonzero = self.temp();
            const condition = self.temp();
            try self.print(" %v{d} =l cnel %v{d}, 0\n %v{d} =l and %v{d}, %v{d}\n", .{ nonzero, remainder, condition, nonzero, mask.? });
            if (divides) {
                try self.print(" %v{d} =l sub %v{d}, %v{d}\n", .{ values.result, result, condition });
            } else {
                const borrow = self.temp();
                const delta = self.temp();
                try self.print(" %v{d} =l neg %v{d}\n %v{d} =l and %v{d}, %v{d}\n %v{d} =l add %v{d}, %v{d}\n", .{ borrow, condition, delta, values.right, borrow, values.result, result, delta });
            }
            return true;
        }
    }
    try self.print(" %v{d} =l copy %v{d}\n", .{ values.result, result });
    return true;
}

/// A concrete operand literal, without evaluating or moving any instruction.
pub fn literal(comptime E: type, self: *E) ?i128 {
    const pc = self.pc;
    if (pc == 0 or pc >= self.states.len or self.isBranchTarget(pc)) return null;
    const here = self.states[pc] orelse return null;
    const previous = self.states[pc - 1] orelse return null;
    if (here.len != previous.len + 1) return null;
    return switch (self.function.scope.instructions[pc - 1].op) {
        .push_i64 => |value| value,
        .push_integer => |value| if (value.ty.isInteger()) value.value else null,
        else => null,
    };
}

fn emitQuotient(comptime E: type, self: *E, recipe: Plan, dividend: usize) Error!usize {
    const high = self.temp();
    if (recipe.power) {
        try self.print(" %v{d} =l shr %v{d}, {d}\n", .{ high, dividend, recipe.shift });
        return high;
    }
    try self.print(" %v{d} =l umulh %v{d}, {d}\n", .{ high, dividend, recipe.multiplier });
    var value = high;
    if (recipe.add) {
        const distance = self.temp();
        const half = self.temp();
        value = self.temp();
        try self.print(" %v{d} =l sub %v{d}, %v{d}\n %v{d} =l shr %v{d}, 1\n %v{d} =l add %v{d}, %v{d}\n", .{ distance, dividend, high, half, distance, value, half, high });
    }
    const result = self.temp();
    try self.print(" %v{d} =l shr %v{d}, {d}\n", .{ result, value, recipe.shift });
    return result;
}
