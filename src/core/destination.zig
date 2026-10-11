//! Expose a small fresh list constructor to its caller's storage decision.
//!
//! This is a bounded CFG inline policy, not a destination-passing ABI. Cloning
//! preserves checks and their source ancestry; the later ownership pass must
//! still prove the complete caller-side list web safe before using stack storage.
//! A returned, stored or snapshotted result therefore keeps its heap lifetime.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const promote = @import("promote.zig");

/// Limit construction cloning separately from the existing helper inline policy.
pub const max_caller_instructions: usize = 256;

/// The result is a fresh bounded unmanaged list and cloning is small enough to
/// expose its construction. Scratch facts never escape and no instruction changes.
pub fn qualifies(scratch: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) std.mem.Allocator.Error!bool {
    const shape = candidate(module, function) orelse return false;
    var trial = function.*;
    const known = try facts.analyze(scratch, &trial, .{ .fold = false, .mark = false });
    const capacity = returnedCapacity(function, &known, shape) orelse return false;
    const stride = @max(1, module.size(module.compound(function.signature.ret).list));
    return capacity <= promote.max_stack_bytes / stride;
}

const Shape = struct { fresh: ir.Ref, returned: ir.Ref };

fn candidate(module: *const ir.Module, function: *const ir.Function) ?Shape {
    if (function.signature.linkage != .internal or function.signature.owned != 0) return null;
    if (module.kind(function.signature.ret) != .list) return null;
    if (module.managed(module.compound(function.signature.ret).list)) return null;
    if (function.blocks.items.len == 0 or function.blocks.items.len > 20 or function.insts.items.len > 128) return null;
    // This first policy does not move constructors that borrow managed inputs.
    // In particular, an input alias can never be mistaken for a fresh result.
    for (function.signature.params) |ty| if (module.managed(ty)) return null;
    var fresh: ir.Ref = .none;
    var returned: ir.Ref = .none;
    var size: usize = 0;
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        size += 1;
        if (size > 100) return null;
        const inst = function.inst(ref);
        if (!constructorOp(inst.op)) return null;
        if (module.managed(inst.ty) and inst.ty != function.signature.ret) return null;
        switch (inst.op) {
            .list_new => {
                if (fresh != .none or inst.ty != function.signature.ret or inst.data != 0) return null;
                fresh = ref;
            },
            .ret => {
                if (returned != .none or inst.a == .none) return null;
                returned = function.resolve(inst.a);
            },
            else => {},
        }
    };
    if (fresh == .none or returned == .none) return null;
    return .{ .fresh = fresh, .returned = returned };
}

fn constructorOp(op: ir.Op) bool {
    return switch (op) {
        .param,
        .iconst,
        .fconst,
        .copy,
        .phi,
        .add,
        .sub,
        .mul,
        .div,
        .rem,
        .floor_div,
        .floor_rem,
        .neg,
        .bit_and,
        .bit_or,
        .bit_xor,
        .not,
        .cmp,
        .fadd,
        .fsub,
        .fmul,
        .fdiv,
        .fneg,
        .fcmp,
        .int_to_float,
        .float_to_int,
        .convert,
        .list_new,
        .list_len,
        .list_get,
        .list_get_field,
        .list_push,
        .record_make,
        .record_get,
        .record_set,
        .array_get,
        .jump,
        .branch,
        .ret,
        => true,
        else => false,
    };
}

/// Match the same two fill shapes as stack promotion. Caller uses are checked
/// only after cloning; this proof establishes freshness and a useful size bound.
fn returnedCapacity(function: *const ir.Function, known: *const facts.Facts, shape: Shape) ?u64 {
    var current = shape.returned;
    var capacity: u64 = 0;
    for (0..function.insts.items.len) |_| {
        if (current == shape.fresh) return capacity;
        const inst = function.inst(current);
        if (inst.op == .list_push) {
            capacity += 1;
            current = function.resolve(inst.a);
            continue;
        }
        // Promotion supports a single fill loop beginning at the empty list,
        // with no subsequent appends. Its phi must return this fresh instance.
        if (inst.op != .phi or capacity != 0) return null;
        const operands = function.operands(inst.data);
        if (operands.len != 2) return null;
        const first = function.resolve(operands[0]);
        const second = function.resolve(operands[1]);
        const back = if (first == shape.fresh) second else if (second == shape.fresh) first else return null;
        const push = function.inst(back);
        if (push.op != .list_push or function.resolve(push.a) != current) return null;
        const list = known.aggregates.lists[current.index()];
        if (!list.pattern or list.length == .none) return null;
        const bound = facts.valueRange(known, function, list.length) orelse return null;
        if (bound.hi > std.math.maxInt(u32)) return null;
        return @intCast(@max(0, bound.hi));
    }
    return null;
}
