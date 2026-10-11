//! Candidates for passing an ordinary list argument with one owned reference.
//!
//! This is a profitability proof, not uniqueness: a leaf helper returns one input
//! list through copies, phis and list updates. Ownership insertion still tests
//! the count, retains live snapshots and handles repeated arguments. Neither the
//! source `mut` contract nor its result layout changes.
//!
//! The proof is local and may be retained with a dependency-validated body. The
//! caller must separately establish `closed`, exclude the entry point, and install
//! every selected `Signature.consumes` before inserting any ownership operations.
//! Final signatures retain that convention even when later transforms change the
//! body. A missing body has no proof unless its validated summary supplies one.
const std = @import("std");
const ir = @import("ir.zig");

/// Limit temporary storage and the number of instructions inspected per helper.
pub const max_instructions = 4096;

/// All callable values have an interned function type, including callbacks handed
/// to the runtime. Rejecting that catalog entry also covers unloaded warm bodies.
/// Direct internal functions are the only remaining users of the new convention.
pub fn closed(module: *const ir.Module) bool {
    for (module.compounds.items) |compound| if (compound == .@"fn") return false;
    return true;
}

/// Return a mask containing at most the one ordinary parameter whose list is
/// updated and returned. Opaque, recursive, mixed-root and oversized bodies keep
/// their borrowing convention. Allocation failures remain real errors.
pub fn candidates(scratch: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) std.mem.Allocator.Error!u64 {
    if (!eligible(module, function)) return 0;
    const seen = try scratch.alloc(bool, function.insts.items.len);
    defer scratch.free(seen);
    @memset(seen, false);
    var walk: Walk = .{ .scratch = scratch, .function = function, .seen = seen };
    defer walk.work.deinit(scratch);
    for (function.blocks.items, 0..) |block, index| {
        if (index != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op == .ret) try walk.queue(inst.a);
        }
    }
    while (walk.work.pop()) |ref| if (!try walk.visit(ref)) return 0;
    const parameter = walk.parameter orelse return 0;
    if (!walk.updated) return 0;
    return @as(u64, 1) << @intCast(parameter);
}

fn eligible(module: *const ir.Module, function: *const ir.Function) bool {
    const signature = function.signature;
    if (signature.linkage != .internal or signature.owned != 0) return false;
    if (function.blocks.items.len == 0 or function.insts.items.len > max_instructions) return false;
    if (signature.params.len > 64 or module.kind(signature.ret) != .list) return false;
    if (module.managed(module.compound(signature.ret).list)) return false;
    for (function.insts.items) |inst| switch (inst.op) {
        // No call graph assumption is needed for this initial leaf-only proof.
        // Explicit counting also identifies already-owned IR, where re-inference
        // must not choose a different convention from its persisted signature.
        .call, .call_indirect, .retain, .release, .is_unique => return false,
        else => {},
    };
    return true;
}

const Walk = struct {
    scratch: std.mem.Allocator,
    function: *const ir.Function,
    seen: []bool,
    work: std.ArrayList(ir.Ref) = .empty,
    parameter: ?u32 = null,
    updated: bool = false,

    fn queue(self: *Walk, raw: ir.Ref) std.mem.Allocator.Error!void {
        const ref = self.function.resolve(raw);
        if (ref == .none or self.seen[ref.index()]) return;
        self.seen[ref.index()] = true;
        try self.work.append(self.scratch, ref);
    }

    fn visit(self: *Walk, ref: ir.Ref) std.mem.Allocator.Error!bool {
        const f = self.function;
        const inst = f.inst(ref);
        if (inst.ty != f.signature.ret) return false;
        switch (inst.op) {
            .param => {
                if (inst.data >= f.signature.params.len or inst.data >= 64) return false;
                if (self.parameter) |parameter| if (parameter != inst.data) return false;
                self.parameter = @intCast(inst.data);
            },
            .phi => for (f.operands(inst.data)) |value| try self.queue(value),
            .list_push, .list_set, .list_set_field, .list_pop => {
                self.updated = true;
                try self.queue(inst.a);
            },
            else => return false,
        }
        return true;
    }
};
