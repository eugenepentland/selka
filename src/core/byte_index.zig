//! Canonical byte indices expose existing facts and vector shapes without new IR.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// Only the exact compiler-owned byte adapter has normalization semantics.
pub fn adapter(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .u64 or inst.a.index() >= module.functions.items.len) return false;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .u64) return false;
    if (signature.params.len != 2 or signature.params[1] != .i64) return false;
    if (signature.params[0] != .bytes and signature.params[0] != .byte_buffer) return false;
    if ((signature.owned | signature.views | signature.consumes) != 0) return false;
    return std.mem.eql(u8, callee.name, "myl_core_bytes_index_offset");
}

// This stays separate: the exported owned adapter also drives pointer-based LLVM emission.
fn spanAdapter(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .u64 or inst.a.index() >= module.functions.items.len) return false;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .u64) return false;
    if (signature.owned != 0 or signature.consumes != 0 or signature.views != 1) return false;
    if (!std.mem.eql(ir.Type, signature.params, &.{ .str, .i64 })) return false;
    return std.mem.eql(u8, callee.name, "myl_core_span_bytes_index_offset");
}

/// A nonnegative source index is already normalized. Forward it only when every
/// consumer reads its receiver's byte element; that operand accepts either sign.
/// Returning or otherwise consuming the adapter's u64 result keeps its ABI.
pub fn forward(module: *const ir.Module, function: *ir.Function, known: *const facts.Facts) u32 {
    var changed: u32 = 0;
    var candidates: u32 = 0;
    for (function.insts.items, 0..) |inst, index| {
        const span = spanAdapter(module, inst);
        if (!span and !adapter(module, inst)) continue;
        if (span) {
            if (function.insts.items.len > 4096 or candidates == 32) continue;
            candidates += 1;
        }
        const operands = function.operands(inst.data);
        if (operands.len != 2) continue;
        const receiver = function.resolve(operands[0]);
        const receiver_type = function.inst(receiver).ty;
        if (span) {
            if (!module.zero_rc or receiver_type != .str_view) continue;
        } else if (receiver_type != module.functions.items[inst.a.index()].signature.params[0]) continue;
        const raw = function.resolve(operands[1]);
        if (span and function.inst(raw).ty != .i64) continue;
        const range = facts.valueRange(known, function, raw) orelse continue;
        if (range.lo < 0) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        if (!indexOnly(function, ref, receiver)) continue;
        function.insts.items[index] = .{ .op = .copy, .ty = function.inst(raw).ty, .a = raw, .span = inst.span };
        changed += 1;
    }
    return changed;
}

fn indexOnly(function: *const ir.Function, ref: ir.Ref, receiver: ir.Ref) bool {
    var used = false;
    for (function.insts.items) |inst| {
        const operands = function.valueOperands(inst);
        for (0..operands.len()) |index| {
            if (function.resolve(operands.get(index)) != ref) continue;
            if (inst.op != .list_get or inst.ty != .u8 or inst.data != 0) return false;
            if (function.resolve(inst.b) != ref or function.resolve(inst.a) != receiver) return false;
            used = true;
        }
    }
    return used;
}
