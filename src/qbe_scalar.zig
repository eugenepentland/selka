//! Target scalar instruction selection; arithmetic checks remain explicit in QBE.
const binary_instruction = " %v{d} =l {s} %v{d}, %v{d}\n";
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

/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Bind operation lowering to the concrete backend emitter.
pub fn Lower(comptime E: type) type {
    return struct {
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
                    try self.print(" %v{d} =l {s} %v{d}, {d}\n", .{ normalized, if (info.signed) "sar" else "shr", shifted, 64 - info.bits });
                    try self.store(height - 2, normalized);
                    return;
                }
            } else if (op == .add or op == .sub) {
                try checkedAddSub(self, op, info.signed, info.bits, .{ .left = left, .right = right, .result = id });
            } else if (@backingInt(op) >= @backingInt(typed.BinaryOp.f64_add)) {
                try floatBinary(self, op, .{ .left = left, .right = right, .result = id });
            } else try self.print(" %v{d} =l call $myl_qbe_int_binary(l %ctx, l {d}, l {d}, l {d}, l %v{d}, l %v{d})\n", .{ id, @backingInt(op), @intFromBool(info.signed), info.bits, left, right });
            try self.store(height - 2, id);
        }
        fn floatBinary(self: *E, op: typed.BinaryOp, values: struct { left: usize, right: usize, result: usize }) Error!void {
            try self.print(" call $myl_qbe_float_check(l %ctx)\n", .{});
            try self.checkFailure("failure");
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
        fn checkedAddSub(self: *E, op: typed.BinaryOp, signed: bool, bits: u16, values: struct { left: usize, right: usize, result: usize }) Error!void {
            const left = values.left;
            const right = values.right;
            const result = values.result;
            try self.print(binary_instruction, .{ result, if (op == .add) "add" else "sub", left, right });
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
                try self.print(" %v{d} =l xor %v{d}, %v{d}\n", .{ x, left, if (op == .add) result else right });
                try self.print(" %v{d} =l xor %v{d}, %v{d}\n", .{ y, if (op == .add) right else left, result });
                try self.print(" %v{d} =l and %v{d}, %v{d}\n %v{d} =l csltl %v{d}, 0\n", .{ both, x, y, overflow, both });
            } else {
                try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ overflow, if (op == .add) result else left, if (op == .add) left else right });
            }
            try self.print(" jnz %v{d}, @overflow{d}, @checked{d}\n@overflow{d}\n", .{ overflow, result, result, result });
            // Capture the already-evaluated operands and width for the sticky trap detail.
            try self.print(" call $myl_qbe_fail_overflow_op(l %ctx, l {d}, l %v{d}, l %v{d}, l {d})\n jmp @failure\n@checked{d}\n", .{ @backingInt(op), left, right, bits, result });
        }
    };
}
