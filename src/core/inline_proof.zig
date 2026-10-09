//! A checked leaf may lose its source frame only when its checks cannot fail.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// Whether copying this body needs a proof that no runtime trap is possible.
pub fn needsProof(function: *const ir.Function) bool {
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        if (function.inst(ref).check == .exact) return true;
    };
    return false;
}

/// Use existing facts on a private instruction copy; neither real function changes.
pub fn trapFree(a: std.mem.Allocator, caller: *const ir.Function, call: ir.Inst, callee: *const ir.Function, known: facts.Facts) std.mem.Allocator.Error!bool {
    const arguments = caller.operands(call.data);
    const parameters = try a.alloc(?facts.Interval, arguments.len);
    for (arguments, parameters) |argument, *range| {
        const ref = caller.resolve(argument);
        range.* = facts.valueRange(&known, caller, ref);
        if (range.* == null) range.* = facts.typeRange(caller.inst(ref).ty);
    }
    var trial = callee.*;
    trial.insts = .empty;
    try trial.insts.appendSlice(a, callee.insts.items);
    const result = try facts.analyze(a, &trial, .{ .fold = false, .params = parameters });
    for (trial.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = trial.inst(ref);
        if (inst.check != .exact) continue;
        if (!divisionSafe(&trial, inst, result)) return false;
    };
    return true;
}

fn divisionSafe(function: *const ir.Function, inst: ir.Inst, known: facts.Facts) bool {
    switch (inst.op) {
        .div, .rem, .floor_div, .floor_rem => {},
        else => return false,
    }
    const divisor = facts.valueRange(&known, function, inst.b) orelse return false;
    if (divisor.lo <= 0 and divisor.hi >= 0) return false;
    const limits = facts.typeRange(inst.ty) orelse return false;
    if (limits.lo >= 0 or divisor.lo > -1 or divisor.hi < -1) return true;
    const dividend = facts.valueRange(&known, function, inst.a) orelse return false;
    // Signed floor division can be safe without the non-negative operands
    // required by facts' `proven` flag (which selects unsigned LLVM division).
    return dividend.lo > limits.lo;
}
