//! Bounded scalar readers expose local views to existing CFG cloning and cleanup.
const std = @import("std");
const ir = @import("ir.zig");
const views = @import("fuse_slice_key.zig");

fn scalar(ty: ir.Type) bool {
    return ty.integer() != null or ty == .bool or ty == .f64;
}

fn offsetReader(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.a.index() >= module.functions.items.len) return false;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    return signature.linkage == .runtime_c and signature.ret == .u64 and
        signature.owned == 0 and signature.consumes == 0 and signature.views == 1 and
        std.mem.eql(ir.Type, signature.params, &.{ .str, .i64 }) and
        std.mem.eql(u8, callee.name, "myl_core_span_bytes_index_offset");
}

/// Checked read-only scalar helpers qualify under fixed per-body limits; calls retain checks.
pub fn qualifies(module: *const ir.Module, f: *const ir.Function) bool {
    if (!module.zero_rc) return false;
    const signature = f.signature;
    if (signature.linkage != .internal or !scalar(signature.ret)) return false;
    if ((signature.owned | signature.consumes | signature.views) != 0 or signature.params.len > 8) return false;
    if (f.blocks.items.len < 2 or f.blocks.items.len > 16 or f.insts.items.len > 80 or f.loops.items.len > 2) return false;
    var reads: usize = 0;
    var returns: usize = 0;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        switch (inst.op) {
            .param,
            .iconst,
            .fconst,
            .str_const,
            .undef,
            .copy,
            .phi,
            .cmp,
            .fcmp,
            .convert,
            .int_to_float,
            .float_to_int,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .floor_div,
            .floor_rem,
            .neg,
            .fadd,
            .fsub,
            .fmul,
            .fdiv,
            .fneg,
            .not,
            .bit_and,
            .bit_or,
            .bit_xor,
            .branch,
            .jump,
            .@"unreachable",
            => {},
            .list_len, .str_len, .str_view_of => reads += 1,
            .list_get => {
                // Octet and scalar lists need no child owners or storage transfer.
                if (!scalar(inst.ty)) return false;
                reads += 1;
            },
            .call => {
                if (!offsetReader(module, inst) or f.operands(inst.data).len != 2) return false;
                reads += 1;
            },
            .ret => {
                if (inst.a == .none or !scalar(f.inst(f.resolve(inst.a)).ty)) return false;
                returns += 1;
            },
            else => return false,
        }
    };
    return reads != 0 and returns != 0;
}

fn localReads(f: *const ir.Function, value: ir.Ref) bool {
    var read = false;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != value) continue;
            if (at != 0 or (inst.op != .str_len and inst.op != .str_view_of)) return false;
            read = true;
        }
    }
    return read;
}

/// Remove token materialization after inlining exposes only local length/view readers.
/// This edits existing instructions only, so cache catalogs and ancestry remain intact.
pub fn cleanup(a: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    if (!module.zero_rc or f.insts.items.len > 4096) return 0;
    var candidates: u32 = 0;
    var changed: u32 = 0;
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op != .str_from_view) continue;
        if (candidates == 32) break;
        candidates += 1;
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        if (!localReads(f, ref) or try views.updated(a, f, module, f.resolve(inst.a))) continue;
        f.insts.items[index] = .{ .op = .copy, .ty = .str_view, .a = inst.a, .span = inst.span };
        for (f.insts.items) |*forward| {
            if (forward.op == .copy and f.resolve(forward.a) == f.resolve(inst.a)) forward.ty = .str_view;
        }
        changed += 1;
    }
    return changed;
}
