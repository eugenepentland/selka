//! Target scalar instruction selection; arithmetic checks remain explicit in QBE.
const binary_instruction = " %v{d} =l {s} %v{d}, %v{d}\n";
const immediate_instruction = " %v{d} =l {s} %v{d}, {d}\n";
const and_instruction = " %v{d} =l and %v{d}, %v{d}\n";
const or_instruction = " %v{d} =l or %v{d}, %v{d}\n";
const xor_instruction = " %v{d} =l xor %v{d}, %v{d}\n";
const neg_instruction = " %v{d} =l neg %v{d}\n";
const signed_negative = " %v{d} =l csltl %v{d}, 0\n";
const low_word_mask = " %v{d} =l and %v{d}, 4294967295\n";
const high_word_shift = " %v{d} =l shr %v{d}, 32\n";
/// Operands and destination of one lowered scalar instruction.
const Operands = struct { left: usize, right: usize, result: usize };
const typed = @import("typed.zig");
/// Direct instruction and the interpretation of its result.
pub const Operation = struct { instruction: []const u8, comparison: bool = false, wrapping: bool = false };
/// Select operations whose full semantics need no runtime call.
pub fn select(op: typed.BinaryOp, signed: bool) ?Operation {
    return switch (op) {
        .eq => .{ .instruction = "ceql", .comparison = true },
        .ne => .{ .instruction = "cnel", .comparison = true },
        .lt => .{ .instruction = if (signed) "csltl" else "cultl", .comparison = true },
        .le => .{ .instruction = if (signed) "cslel" else "culel", .comparison = true },
        .gt => .{ .instruction = if (signed) "csgtl" else "cugtl", .comparison = true },
        .ge => .{ .instruction = if (signed) "csgel" else "cugel", .comparison = true },
        .bit_and => .{ .instruction = "and", .wrapping = true },
        .bit_or => .{ .instruction = "or", .wrapping = true },
        .bit_xor => .{ .instruction = "xor", .wrapping = true },
        .wrapping_add => .{ .instruction = "add", .wrapping = true },
        .wrapping_sub => .{ .instruction = "sub", .wrapping = true },
        .wrapping_mul => .{ .instruction = "mul", .wrapping = true },
        else => null,
    };
}

/// The mathematical range of an integer type, as a 128-bit pair.
fn extremes(info: typed.Type.Integer) struct { min: i128, max: i128 } {
    const span: i128 = @as(i128, 1) << @intCast(info.bits);
    return if (info.signed)
        .{ .min = -(span >> 1), .max = (span >> 1) - 1 }
    else
        .{ .min = 0, .max = span - 1 };
}

/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind operation lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Lower one checked integer cast. A conversion whose source range fits
        /// the target is a copy; every other pair is one or two range compares
        /// whose cold path raises the trap `myl_qbe_int_cast` used to.
        pub fn cast(self: *E, from: typed.Type.Integer, to: typed.Type.Integer, height: usize) Error!void {
            const operand = try self.load("s", height - 1);
            const source = extremes(from);
            const target = extremes(to);
            if (source.min >= target.min and source.max <= target.max) {
                try self.store(height - 1, operand);
                return;
            }
            var overflow: ?usize = null;
            if (source.min < target.min) {
                const low = self.temp();
                try self.print(" %v{d} =l csltl %v{d}, {d}\n", .{ low, operand, @as(i64, @intCast(target.min)) });
                overflow = low;
            }
            if (source.max > target.max) {
                const high = self.temp();
                try self.print(immediate_instruction, .{ high, if (from.signed) "csgtl" else "cugtl", operand, @as(u64, @intCast(target.max)) });
                if (overflow) |low| {
                    const combined = self.temp();
                    try self.print(or_instruction, .{ combined, low, high });
                    overflow = combined;
                } else overflow = high;
            }
            const label = self.temp();
            try self.print(" jnz %v{d}, @cast_overflow{d}, @cast_ok{d}\n@cast_overflow{d}\n call $myl_qbe_fail_cast(l %ctx, l %v{d}, l {d})\n jmp @failure\n@cast_ok{d}\n", .{ overflow.?, label, label, label, operand, to.bits, label });
            try self.store(height - 1, operand);
        }
        /// Lower scalar arithmetic with explicit overflow and canonical binary64 results.
        pub fn binary(self: *E, op: typed.BinaryOp, ty: typed.Type, height: usize) Error!void {
            const right = try self.load("s", height - 1);
            const left = try self.load("s", height - 2);
            const id = self.temp();
            const info = ty.integer() orelse return error.InternalError;
            if (select(op, info.signed)) |direct| {
                try self.print(binary_instruction, .{ id, direct.instruction, left, right });
                if (direct.wrapping and info.bits < 64) {
                    const shifted = self.temp();
                    const normalized = self.temp();
                    try self.print(" %v{d} =l shl %v{d}, {d}\n", .{ shifted, id, 64 - info.bits });
                    try self.print(immediate_instruction, .{ normalized, if (info.signed) "sar" else "shr", shifted, 64 - info.bits });
                    try self.store(height - 2, normalized);
                    return;
                }
            } else if (op == .add or op == .sub) {
                try checkedAddSub(E, self, op, info.signed, info.bits, .{ .left = left, .right = right, .result = id });
            } else if (op == .mul) {
                try checkedMul(E, self, op, info, .{ .left = left, .right = right, .result = id });
            } else if (op == .div or op == .rem or op == .floor_div or op == .floor_rem) {
                try checkedDivRem(E, self, op, info, .{ .left = left, .right = right, .result = id });
            } else if (op == .shift_left or op == .shift_right) {
                try checkedShift(E, self, op, info, .{ .left = left, .right = right, .result = id });
            } else if (@backingInt(op) >= @backingInt(typed.BinaryOp.f64_add)) {
                try floatBinary(self, op, .{ .left = left, .right = right, .result = id });
            } else try self.print(" %v{d} =l call $myl_qbe_int_binary(l %ctx, l {d}, l {d}, l {d}, l %v{d}, l %v{d})\n", .{ id, @backingInt(op), @intFromBool(info.signed), info.bits, left, right });
            try self.store(height - 2, id);
        }
        /// Lower checked unary negation for one integer width. The hot path is a
        /// single negate plus the width's only failing value; the cold path calls
        /// the runtime helper so the trap detail stays `(neg: left …, width …)`.
        pub fn neg(self: *E, info: typed.Type.Integer, height: usize) Error!void {
            const operand = try self.load("s", height - 1);
            const result = self.temp();
            const flag = self.temp();
            try self.print(neg_instruction, .{ result, operand });
            const minimum: i64 = if (info.signed) @intCast(-(@as(i128, 1) << @intCast(info.bits - 1))) else 0;
            try self.print(immediate_instruction, .{ flag, if (info.signed) "ceql" else "cnel", operand, minimum });
            try self.print(" jnz %v{d}, @neg_overflow{d}, @neg_checked{d}\n@neg_overflow{d}\n", .{ flag, result, result, result });
            try self.print(" call $myl_qbe_int_neg(l %ctx, l {d}, l {d}, l %v{d})\n jmp @failure\n@neg_checked{d}\n", .{ @intFromBool(info.signed), info.bits, operand, result });
            try self.store(height - 1, result);
        }
        fn floatBinary(self: *E, op: typed.BinaryOp, values: struct { left: usize, right: usize, result: usize }) Error!void {
            const left = self.temp();
            const right = self.temp();
            try self.print(" %v{d} =d cast %v{d}\n %v{d} =d cast %v{d}\n", .{ left, values.left, right, values.right });
            const instruction: []const u8 = switch (op) {
                .f64_add => "add",
                .f64_sub => "sub",
                .f64_mul => "mul",
                .f64_div => "div",
                .f64_eq => "ceqd",
                .f64_lt => "cltd",
                .f64_le => "cled",
                else => return error.InternalError,
            };
            if (op == .f64_eq or op == .f64_lt or op == .f64_le) {
                try self.print(binary_instruction, .{ values.result, instruction, left, right });
            } else {
                const value = self.temp();
                const nan = self.temp();
                const raw = self.temp();
                try self.print(" %v{d} =d {s} %v{d}, %v{d}\n", .{ value, instruction, left, right });
                try self.print(" %v{d} =l cuod %v{d}, %v{d}\n jnz %v{d}, @nan{d}, @finite{d}\n", .{ nan, value, value, nan, value, value });
                try self.print("@nan{d}\n jmp @float{d}\n@finite{d}\n %v{d} =l cast %v{d}\n jmp @float{d}\n", .{ value, value, value, raw, value, value });
                try self.print("@float{d}\n %v{d} =l phi @nan{d} 9221120237041090560, @finite{d} %v{d}\n", .{ value, values.result, value, value, raw });
            }
        }
    };
}

const Bound = struct { limit: i64, upward: bool };
/// Solve the overflow bound for `left <op> fixed`. Adding a non-negative fixed
/// operand can only exceed the maximum, so the useful test is against
/// `max - fixed`; subtracting one can only fall below the minimum. Every bound
/// is derived in 128 bits, so no operand value wraps while computing it.
fn overflowBound(op: typed.BinaryOp, fixed: i64) Bound {
    const span: i128 = @as(i128, 1) << 63;
    const upward = (op == .add) == (fixed > 0);
    const base: i128 = if (upward) span - 1 else -span;
    const limit = if (op == .add) base - fixed else base + fixed;
    return .{ .limit = @intCast(limit), .upward = upward };
}
/// Emit the overflow test for a 64-bit signed `add`/`sub` whose right operand is
/// the literal `literal`. With one operand fixed, exactly one value of the other
/// can carry the result out of range, so the general three-instruction sign test
/// collapses to one comparison; the cold path is the shared `overflowTrap`, so
/// the sticky trap and its operand detail are unchanged.
fn constantAddSub(comptime E: type, self: *E, op: typed.BinaryOp, literal: i64, values: Operands) Error!void {
    const bound = overflowBound(op, literal);
    const flag = self.temp();
    try self.print(immediate_instruction, .{ flag, if (bound.upward) "csgtl" else "csltl", values.left, bound.limit });
    try overflowTrap(E, self, op, values, 64, flag);
}

fn checkedAddSub(comptime E: type, self: *E, op: typed.BinaryOp, signed: bool, bits: u16, values: Operands) Error!void {
    const left = values.left;
    const right = values.right;
    const result = values.result;
    try self.print(binary_instruction, .{ result, if (op == .add) "add" else "sub", left, right });
    if (bits == 64 and signed) if (self.pushedLiteral(self.pc)) |literal| {
        try constantAddSub(E, self, op, literal, values);
        return;
    };
    const overflow = self.temp();
    if (bits < 64) {
        const low = self.temp();
        const high = self.temp();
        const minimum: i64 = if (signed) -(@as(i64, 1) << @intCast(bits - 1)) else 0;
        const maximum: u64 = (@as(u64, 1) << @intCast(bits - @intFromBool(signed))) - 1;
        try self.print(" %v{d} =l csltl %v{d}, {d}\n %v{d} =l csgtl %v{d}, {d}\n %v{d} =l or %v{d}, %v{d}\n", .{ low, result, minimum, high, result, maximum, overflow, low, high });
    } else if (signed) {
        const x = self.temp();
        const y = self.temp();
        const both = self.temp();
        try self.print(xor_instruction, .{ x, left, if (op == .add) result else right });
        try self.print(xor_instruction, .{ y, if (op == .add) right else left, result });
        try self.print(" %v{d} =l and %v{d}, %v{d}\n %v{d} =l csltl %v{d}, 0\n", .{ both, x, y, overflow, both });
    } else {
        try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ overflow, if (op == .add) result else left, if (op == .add) left else right });
    }
    try self.print(" jnz %v{d}, @overflow{d}, @checked{d}\n@overflow{d}\n", .{ overflow, result, result, result });
    // Capture the already-evaluated operands and width for the sticky trap detail.
    try self.print(" call $myl_qbe_fail_overflow_op(l %ctx, l {d}, l %v{d}, l %v{d}, l {d})\n jmp @failure\n@checked{d}\n", .{ @backingInt(op), left, right, bits, result });
}

/// Emit the cold branch that reports one checked-operation overflow.
fn overflowTrap(comptime E: type, self: *E, op: typed.BinaryOp, values: Operands, bits: u16, flag: usize) Error!void {
    try self.print(" jnz %v{d}, @overflow{d}, @checked{d}\n@overflow{d}\n", .{ flag, values.result, values.result, values.result });
    try self.print(" call $myl_qbe_fail_overflow_op(l %ctx, l {d}, l %v{d}, l %v{d}, l {d})\n jmp @failure\n@checked{d}\n", .{ @backingInt(op), values.left, values.right, bits, values.result });
}
/// Compare a 64-bit result against the width's mathematical range.
fn rangeCheck(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: Operands) Error!void {
    const high = self.temp();
    const maximum: u64 = (@as(u64, 1) << @intCast(info.bits - @intFromBool(info.signed))) - 1;
    try self.print(immediate_instruction, .{ high, if (info.signed) "csgtl" else "cugtl", values.result, maximum });
    var flag = high;
    if (info.signed) {
        const low = self.temp();
        const minimum: i64 = @intCast(-(@as(i128, 1) << @intCast(info.bits - 1)));
        try self.print(immediate_instruction, .{ low, "csltl", values.result, minimum });
        const both = self.temp();
        try self.print(or_instruction, .{ both, low, high });
        flag = both;
    }
    try overflowTrap(E, self, op, values, info.bits, flag);
}
/// The unsigned high 64 bits of a 64x64 product, from four 32-bit limbs.
fn unsignedHigh(comptime E: type, self: *E, left: usize, right: usize) Error!usize {
    const low_left = self.temp();
    const high_left = self.temp();
    const low_right = self.temp();
    const high_right = self.temp();
    try self.print(low_word_mask, .{ low_left, left });
    try self.print(high_word_shift, .{ high_left, left });
    try self.print(low_word_mask, .{ low_right, right });
    try self.print(high_word_shift, .{ high_right, right });
    const base = self.temp();
    try self.print(binary_instruction, .{ base, "mul", low_left, low_right });
    const carry = self.temp();
    try self.print(high_word_shift, .{ carry, base });
    const cross = self.temp();
    try self.print(binary_instruction, .{ cross, "mul", high_left, low_right });
    const middle = self.temp();
    try self.print(binary_instruction, .{ middle, "add", cross, carry });
    const low_middle = self.temp();
    try self.print(low_word_mask, .{ low_middle, middle });
    const high_middle = self.temp();
    try self.print(high_word_shift, .{ high_middle, middle });
    const other = self.temp();
    try self.print(binary_instruction, .{ other, "mul", low_left, high_right });
    const sum = self.temp();
    try self.print(binary_instruction, .{ sum, "add", other, low_middle });
    const second_carry = self.temp();
    try self.print(high_word_shift, .{ second_carry, sum });
    const top = self.temp();
    try self.print(binary_instruction, .{ top, "mul", high_left, high_right });
    const partial = self.temp();
    try self.print(binary_instruction, .{ partial, "add", top, high_middle });
    const high = self.temp();
    try self.print(binary_instruction, .{ high, "add", partial, second_carry });
    return high;
}
/// Lower checked multiplication; only 64-bit needs a true 128-bit test.
fn checkedMul(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: Operands) Error!void {
    try self.print(binary_instruction, .{ values.result, "mul", values.left, values.right });
    if (info.bits < 64) return rangeCheck(E, self, op, info, values);
    const high = try unsignedHigh(E, self, values.left, values.right);
    if (!info.signed) {
        const flag = self.temp();
        try self.print(immediate_instruction, .{ flag, "cnel", high, 0 });
        return overflowTrap(E, self, op, values, info.bits, flag);
    }
    const left_negative = self.temp();
    const right_negative = self.temp();
    const left_mask = self.temp();
    const right_mask = self.temp();
    const left_term = self.temp();
    const right_term = self.temp();
    const adjusted = self.temp();
    const sign = self.temp();
    const flag = self.temp();
    try self.print(signed_negative, .{ left_negative, values.left });
    try self.print(signed_negative, .{ right_negative, values.right });
    try self.print(neg_instruction, .{ left_mask, left_negative });
    try self.print(neg_instruction, .{ right_mask, right_negative });
    try self.print(and_instruction, .{ left_term, values.right, left_mask });
    try self.print(and_instruction, .{ right_term, values.left, right_mask });
    try self.print(binary_instruction, .{ adjusted, "sub", high, left_term });
    try self.print(binary_instruction, .{ adjusted, "sub", adjusted, right_term });
    try self.print(" %v{d} =l sar %v{d}, 63\n", .{ sign, values.result });
    try self.print(binary_instruction, .{ flag, "cnel", adjusted, sign });
    try overflowTrap(E, self, op, values, info.bits, flag);
}
/// Lower truncating or flooring division and remainder with exact traps.
fn checkedDivRem(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: Operands) Error!void {
    const zero = self.temp();
    try self.print(" %v{d} =l ceql %v{d}, 0\n", .{ zero, values.right });
    try self.print(" jnz %v{d}, @division{d}, @nonzero{d}\n@division{d}\n", .{ zero, values.result, values.result, values.result });
    try self.print(" call $myl_qbe_fail_division(l %ctx, l {d}, l %v{d}, l %v{d})\n jmp @failure\n@nonzero{d}\n", .{ @backingInt(op), values.left, values.right, values.result });
    const quotient = op == .div or op == .floor_div;
    const floored = op == .floor_div or op == .floor_rem;
    var divisor = values.right;
    if (info.signed) {
        const minimum: i64 = @intCast(-(@as(i128, 1) << @intCast(info.bits - 1)));
        const left_min = self.temp();
        const right_neg = self.temp();
        const guard = self.temp();
        try self.print(immediate_instruction, .{ left_min, "ceql", values.left, minimum });
        try self.print(" %v{d} =l ceql %v{d}, -1\n", .{ right_neg, values.right });
        try self.print(and_instruction, .{ guard, left_min, right_neg });
        if (quotient) {
            try overflowTrap(E, self, op, values, info.bits, guard);
        } else {
            // `MIN % -1` is zero but faults x86 division, so swap in one.
            const mask = self.temp();
            const swapped = self.temp();
            try self.print(neg_instruction, .{ mask, guard });
            try self.print(" %v{d} =l xor %v{d}, 1\n", .{ swapped, values.right });
            try self.print(and_instruction, .{ swapped, swapped, mask });
            const safe = self.temp();
            try self.print(xor_instruction, .{ safe, values.right, swapped });
            divisor = safe;
        }
    }
    if (quotient) try self.print(binary_instruction, .{ values.result, if (info.signed) "div" else "udiv", values.left, values.right });
    if (op != .div) {
        const remainder = if (quotient) self.temp() else values.result;
        try self.print(binary_instruction, .{ remainder, if (info.signed) "rem" else "urem", values.left, divisor });
        if (floored and info.signed) {
            const nonzero = self.temp();
            const difference = self.temp();
            const differ = self.temp();
            const condition = self.temp();
            const borrow = self.temp();
            try self.print(" %v{d} =l cnel %v{d}, 0\n", .{ nonzero, remainder });
            try self.print(xor_instruction, .{ difference, remainder, divisor });
            try self.print(signed_negative, .{ differ, difference });
            try self.print(and_instruction, .{ condition, nonzero, differ });
            try self.print(neg_instruction, .{ borrow, condition });
            if (quotient) {
                try self.print(binary_instruction, .{ values.result, "sub", values.result, condition });
            } else {
                const delta = self.temp();
                try self.print(and_instruction, .{ delta, divisor, borrow });
                try self.print(binary_instruction, .{ values.result, "add", values.result, delta });
            }
        }
    }
}
/// Lower checked shifts; an out-of-range count is the only trap.
fn checkedShift(comptime E: type, self: *E, op: typed.BinaryOp, info: typed.Type.Integer, values: Operands) Error!void {
    const too_large = self.temp();
    try self.print(immediate_instruction, .{ too_large, if (info.signed) "csgel" else "cugel", values.right, info.bits });
    var invalid = too_large;
    if (info.signed) {
        const negative = self.temp();
        const both = self.temp();
        try self.print(signed_negative, .{ negative, values.right });
        try self.print(or_instruction, .{ both, too_large, negative });
        invalid = both;
    }
    try self.print(" jnz %v{d}, @shift_invalid{d}, @shift_valid{d}\n@shift_invalid{d}\n", .{ invalid, values.result, values.result, values.result });
    try self.print(" call $myl_qbe_int_binary(l %ctx, l {d}, l {d}, l {d}, l %v{d}, l %v{d})\n jmp @failure\n@shift_valid{d}\n", .{ @backingInt(op), @intFromBool(info.signed), info.bits, values.left, values.right, values.result });
    const instruction: []const u8 = if (op == .shift_left) "shl" else if (info.signed) "sar" else "shr";
    try self.print(binary_instruction, .{ values.result, instruction, values.left, values.right });
    if (op == .shift_left and info.bits < 64) {
        const masked = self.temp();
        const shifted = self.temp();
        const mask: u64 = (@as(u64, 1) << @intCast(info.bits)) - 1;
        try self.print(immediate_instruction, .{ masked, "and", values.result, mask });
        try self.print(" %v{d} =l shl %v{d}, {d}\n", .{ shifted, masked, 64 - info.bits });
        try self.print(immediate_instruction, .{ values.result, if (info.signed) "sar" else "shr", shifted, 64 - info.bits });
    }
}
