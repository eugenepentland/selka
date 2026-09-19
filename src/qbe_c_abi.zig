//! Adapt the language's scalar bit representation to QBE's native C ABI.
const typed = @import("typed.zig");
const contract = @import("c_abi.zig");
/// Failures producing a checked foreign-call wrapper.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
fn abi(ty: typed.Type, records: []const typed.Record) []const u8 {
    if (contract.isFloat(ty, records)) return "d";
    if (ty == .bool) return "ub";
    const info = ty.integer().?;
    return switch (info.bits) {
        8 => if (info.signed) "sb" else "ub",
        16 => if (info.signed) "sh" else "uh",
        32 => "w",
        64 => "l",
        else => unreachable,
    };
}
/// Emit one stable guest-callable wrapper; the external call has no guest context.
pub fn emit(self: anytype, name: []const u8) Error![]u8 {
    const f = self.function;
    const parameters = f.scope.locals[0..f.signature.parameter_count];
    const packed_args = try self.packedParameters(f);
    try self.print("export function l ${s}(l %ctx", .{name});
    if (packed_args) try self.print(", l %packed", .{}) else for (parameters, 0..) |_, i| try self.print(", l %a{d}", .{i});
    try self.print(") {{\n@entry\n", .{});
    for (parameters, 0..) |local, i| {
        if (packed_args) try self.print(" %slot{d} =l add %packed, {d}\n %a{d} =l loadl %slot{d}\n", .{ i, i * 8, i, i });
        if (contract.isFloat(local.ty, self.program.records)) try self.print(" %c{d} =d cast %a{d}\n", .{ i, i });
    }
    const result = f.signature.return_type;
    const float_result = contract.isFloat(result, self.program.records);
    if (result == .unit) try self.print(" call", .{}) else try self.print(" %result ={s} call", .{abi(result, self.program.records)});
    try self.print(" ${s}(", .{contract.symbol(f.name)});
    var emitted = false;
    for (parameters[1..], 1..) |local, i| {
        if (emitted) try self.print(", ", .{});
        emitted = true;
        try self.print("{s} %{s}{d}", .{ abi(local.ty, self.program.records), if (contract.isFloat(local.ty, self.program.records)) "c" else "a", i });
    }
    try self.print(")\n", .{});
    // QBE-FLOAT-ENV-1: a foreign call can change the process rounding mode or
    // leave the SSE/x87 control word altered, so re-verify the environment
    // before the result is used. `myl_qbe_float_check` records the sticky
    // `R_FLOAT_ENVIRONMENT` trap, which the guest's post-`.call` checkFailure
    // observes when this wrapper returns; the arithmetic itself is unchanged.
    try self.print(" call $myl_qbe_float_check(l %ctx)\n", .{});
    if (result == .unit) {
        try self.print(" ret 0\n", .{});
    } else if (float_result) {
        // Canonicalize foreign NaNs just like ordinary language float operations.
        try self.print(" %nan =w cned %result, %result\n jnz %nan, @nan, @value\n@nan\n ret {d}\n@value\n %bits =l cast %result\n ret %bits\n", .{@import("floats.zig").canonical_nan});
    } else if (result == .bool) {
        try self.print(" %truth =w cnew %result, 0\n %wide =l extuw %truth\n ret %wide\n", .{});
    } else if (result.integer().?.bits < 64) {
        const info = result.integer().?;
        const extension: []const u8 = switch (info.bits) {
            8 => if (info.signed) "extsb" else "extub",
            16 => if (info.signed) "extsh" else "extuh",
            32 => if (info.signed) "extsw" else "extuw",
            else => unreachable,
        };
        try self.print(" %wide =l {s} %result\n ret %wide\n", .{extension});
    } else try self.print(" ret %result\n", .{});
    try self.print("}}\n", .{});
    return self.output.toOwnedSlice();
}
