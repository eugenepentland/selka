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

/// New-family trials and type walks have fixed ceilings, including refusals.
pub const mutation_trial_limit = 32;
pub const scalar_type_visit_limit = 32;

fn closedScalar(module: *const ir.Module, ty: ir.Type, remaining: *usize) bool {
    if (remaining.* == 0) return false;
    remaining.* -= 1;
    if (scalar(ty) or ty == .void) return true;
    if (!ty.isCompound()) return false;
    const fields = switch (module.compound(ty)) {
        .record => |record| record,
        .@"union" => |cases| cases,
        else => return false,
    };
    if (fields.len > remaining.*) return false;
    for (fields) |field| if (!closedScalar(module, field, remaining)) return false;
    return true;
}

/// Only a closed two-field value/scalar-writeback tuple crosses this path.
fn mutationFields(module: *const ir.Module, f: *const ir.Function) ?[]const ir.Type {
    const sig = f.signature;
    if (!module.zero_rc or sig.linkage != .internal or sig.params.len > 8) return null;
    if (sig.consumes != 0 or sig.views != 0 or @popCount(sig.owned) != 1) return null;
    const at: usize = @intCast(@ctz(sig.owned));
    if (at >= sig.params.len or sig.params[at].integer() == null) return null;
    if (!sig.ret.isCompound() or module.kind(sig.ret) != .record) return null;
    const fields = module.compound(sig.ret).record;
    if (fields.len != 2 or fields[0] == .void or fields[1] != sig.params[at]) return null;
    var remaining: usize = scalar_type_visit_limit;
    if (!closedScalar(module, sig.ret, &remaining) or module.words(sig.ret) > 3) return null;
    return fields;
}

/// Cheap bounded signature screening does not demand an unrelated callee body.
pub fn mutationSignature(module: *const ir.Module, f: *const ir.Function) bool {
    return mutationFields(module, f) != null;
}

// twin-drift-ok: Read-only borrowed queries exclude constructor allocation and storage operations.
fn queryOp(op: ir.Op) bool {
    return switch (op) {
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
        .record_get,
        .union_tag,
        .union_payload,
        .list_len,
        .list_get,
        .list_get_field,
        .branch,
        .jump,
        .@"unreachable",
        .ret,
        => true,
        else => false,
    };
}

/// A local, call-free checked query may borrow storage but cannot publish an owner.
fn checkedQuery(module: *const ir.Module, f: *const ir.Function) bool {
    const sig = f.signature;
    if (sig.linkage != .internal or (sig.owned | sig.consumes | sig.views) != 0) return false;
    if (sig.params.len > 8) return false;
    if (f.blocks.items.len == 0 or f.blocks.items.len > 32) return false;
    if (f.insts.items.len > 96 or f.loops.items.len != 0) return false;
    var remaining: usize = scalar_type_visit_limit;
    if (sig.ret == .void or !closedScalar(module, sig.ret, &remaining)) return false;
    var reads: usize = 0;
    var returns: usize = 0;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .record_make or inst.op == .union_make) {
            var value_budget: usize = scalar_type_visit_limit;
            if (!closedScalar(module, inst.ty, &value_budget)) return false;
        } else if (!queryOp(inst.op)) return false;
        if (inst.op == .list_get or inst.op == .list_get_field) reads += 1;
        if (inst.op == .ret) returns += 1;
    };
    return reads != 0 and returns != 0;
}

/// Structural recognition is independent of whether the single query qualifies.
/// The outer ceiling matches existing generic helper limits, not clone eligibility.
pub fn mutationShell(module: *const ir.Module, f: *const ir.Function) bool {
    _ = mutationFields(module, f) orelse return false;
    if (f.blocks.items.len == 0 or f.blocks.items.len > 20 or f.insts.items.len > 100 or f.loops.items.len != 0) return false;
    var calls: usize = 0;
    var reads: usize = 0;
    var returns: usize = 0;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        switch (inst.op) {
            .record_make, .union_make => {
                var remaining: usize = scalar_type_visit_limit;
                if (!closedScalar(module, inst.ty, &remaining)) return false;
            },
            .call => {
                if (inst.a.index() >= module.functions.items.len) return false;
                const callee = &module.functions.items[inst.a.index()];
                if (callee == f or callee.signature.linkage != .internal) return false;
                calls += 1;
                if (calls > 1) return false;
            },
            .ret => {
                if (inst.a == .none) return false;
                const result = f.inst(f.resolve(inst.a));
                if (result.op != .record_make or result.ty != f.signature.ret or f.operands(result.data).len != 2) return false;
                returns += 1;
            },
            else => if (!queryOp(inst.op)) return false,
        }
        if (inst.op == .list_get or inst.op == .list_get_field) reads += 1;
    };
    return returns != 0 and (calls == 1 or reads != 0);
}

/// The sole query target of a recognized shell, without looking at query eligibility.
pub fn mutationQuery(module: *const ir.Module, f: *const ir.Function) ?u32 {
    if (!mutationShell(module, f)) return null;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .call) return @intCast(inst.a.index());
    };
    return null;
}

/// Keep clone eligibility at the small wrapper limit, including call-free readers.
pub fn mutationFamily(module: *const ir.Module, f: *const ir.Function) bool {
    if (!mutationShell(module, f)) return false;
    if (f.blocks.items.len > 16 or f.insts.items.len > 80) return false;
    if (mutationQuery(module, f)) |target| return checkedQuery(module, &module.functions.items[target]);
    return true;
}

/// No fallback to whole aggregate cloning: every original result use is a projection.
pub fn mutationCall(caller: *const ir.Function, callee: *const ir.Function, call: ir.Ref) bool {
    var used = false;
    for (caller.insts.items) |inst| {
        const operands = caller.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (caller.resolve(operands.get(at)) != caller.resolve(call)) continue;
            if (inst.op != .record_get or at != 0 or inst.data >= 2) return false;
            used = true;
        }
    }
    for (callee.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = callee.inst(ref);
        if (inst.op != .ret) continue;
        const result = callee.resolve(inst.a);
        for (callee.insts.items) |user| {
            const operands = callee.valueOperands(user);
            for (0..operands.len()) |at| {
                if (callee.resolve(operands.get(at)) == result and user.op != .ret) return false;
            }
        }
    };
    return used;
}
