//! Small snapshot wrappers expose an explicit copy to ordinary owner liveness.
const std = @import("std");
const ir = @import("ir.zig");

/// Only compiler-owned, same-type independent block copies are recognized.
pub fn source(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?ir.Ref {
    if (!module.zero_rc or inst.op != .call) return null;
    if (inst.a.index() >= module.functions.items.len or !module.isBlock(inst.ty)) return null;
    const callee = module.functions.items[inst.a.index()];
    const sig = callee.signature;
    if (sig.linkage != .runtime_c or sig.ret != inst.ty or (sig.owned | sig.consumes | sig.views) != 0) return null;
    if (sig.params.len != 1 or sig.params[0] != inst.ty) return null;
    const args = f.operands(inst.data);
    if (args.len != 1 or f.inst(f.resolve(args[0])).ty != inst.ty) return null;
    if (inst.ty == .str or inst.ty == .bytes) {
        if (!std.mem.eql(u8, callee.name, "myl_core_owned_octets_copy")) return null;
    } else {
        const prefix = @import("emit_values.zig").copy_prefix;
        if (!std.mem.startsWith(u8, callee.name, prefix)) return null;
        const id = std.fmt.parseInt(u32, callee.name[prefix.len..], 10) catch return null;
        if (id != @backingInt(inst.ty)) return null;
    }
    return f.resolve(args[0]);
}

/// Clone at most one parameter copy and its aggregate shell; never general calls.
pub fn qualifies(module: *const ir.Module, f: *const ir.Function) bool {
    const sig = f.signature;
    if (!module.zero_rc or sig.linkage != .internal or sig.params.len != 1) return false;
    if ((sig.owned | sig.consumes | sig.views) != 0 or !module.managed(sig.ret)) return false;
    if (f.blocks.items.len != 1 or f.insts.items.len > 8 or f.loops.items.len != 0) return false;
    var copies: usize = 0;
    var returns: usize = 0;
    for (f.blocks.items[0].insts.items) |ref| {
        const inst = f.inst(ref);
        switch (inst.op) {
            .param, .copy, .union_make, .record_make => {},
            .call => {
                const argument = source(module, f, inst) orelse return false;
                if (f.inst(argument).op != .param) return false;
                copies += 1;
            },
            .ret => returns += 1,
            else => return false,
        }
    }
    return copies == 1 and returns == 1;
}
