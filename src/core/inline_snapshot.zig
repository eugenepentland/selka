//! Small snapshot wrappers expose an explicit copy to ordinary owner liveness.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// Only compiler-owned, same-type independent block copies are recognized.
pub fn source(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?ir.Ref {
    if (inst.op == .buffer_copy or inst.op == .list_copy) {
        // Only the written mark may ride on the copy: any other `data` is not a plain copy.
        if (inst.a == .none or inst.data & ~flags.written_copy != 0) return null;
        const input = f.resolve(inst.a);
        if (f.inst(input).ty != inst.ty) return null;
        if (inst.op == .buffer_copy) return if (inst.ty == .byte_buffer) input else null;
        if (module.kind(inst.ty) != .list or module.managed(module.compound(inst.ty).list)) return null;
        return input;
    }
    if (inst.op != .call) return null;
    if (inst.a.index() >= module.functions.items.len or !module.isBlock(inst.ty)) return null;
    const callee = module.functions.items[inst.a.index()];
    const sig = callee.signature;
    if (sig.linkage != .runtime_c or sig.ret != inst.ty or !sig.passing.eql(.{})) return null;
    if (sig.params.len != 1 or sig.params[0] != inst.ty) return null;
    const args = f.operands(inst.data);
    if (args.len != 1 or f.inst(f.resolve(args[0])).ty != inst.ty) return null;
    if (inst.ty == .str or inst.ty == .bytes) {
        if (!std.mem.eql(u8, callee.name, "myl_core_owned_octets_copy")) return null;
    } else {
        const prefix = @import("emit_values.zig").copy_prefix;
        // The name holds the copied type's key; the signature, checked above, says the type is `inst.ty`.
        if (!std.mem.startsWith(u8, callee.name, prefix) or !@import("stable_names.zig").isKeyList(callee.name[prefix.len..], 1)) return null;
    }
    return f.resolve(args[0]);
}

/// Clone at most one parameter copy and its aggregate shell; never general calls.
pub fn qualifies(module: *const ir.Module, f: *const ir.Function) bool {
    const sig = f.signature;
    if (sig.linkage != .internal or sig.params.len != 1) return false;
    if (!sig.passing.eql(.{}) or !module.managed(sig.ret)) return false;
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
