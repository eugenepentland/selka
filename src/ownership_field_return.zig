//! Elide collection sharing around a record field's temporary mutation when
//! the original field cannot be observed before its unconditional store-back
//! (`COW-FIELD-RETURN-1`). Unknown shapes retain ordinary copy-on-write.
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");

const Context = model.Context;
const Op = sources.Op;
const li = model.li;
const Transfer = struct { source: u32, target: u32, field: usize, copy: usize };

/// Remove both copy sites for a proven unconditional field return. A borrowed
/// source, an observation, an exit, or a surviving temporary keeps the copies.
pub fn elide(ctx: *const Context, owners: []const bool, copies: []bool) void {
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (instruction.op != .value_copy or !copies[pc]) continue;
        const transfer = extraction(ctx, owners, pc) orelse continue;
        const returned = returnSite(ctx, transfer) orelse continue;
        copies[pc] = false;
        copies[returned] = false;
    }
}

fn extraction(ctx: *const Context, owners: []const bool, pc: usize) ?Transfer {
    const code = ctx.instructions();
    if (pc < 2 or pc + 1 >= code.len or code[pc].op.value_copy.site != .assign) return null;
    if (code[pc - 2].op != .load_local or code[pc - 1].op != .get_field or code[pc + 1].op != .store_local) return null;
    const source = li(code[pc - 2].op.load_local);
    const target = li(code[pc + 1].op.store_local);
    const ty = ctx.locals.list[source].ty;
    if (!ty.isAggregate()) return null;
    if (ctx.record(ty).managed or !ctx.record(ty).isRecord()) return null;
    if (ctx.role(source) != .mut_param and !owners[source]) return null;
    if (ctx.role(source) == .mut_param and otherMutableParameter(ctx, source)) return null;
    if (!owners[target] or source == target) return null;
    for (pc - 1..pc + 2) |at| if (!straight(ctx, at)) return null;
    return .{ .source = source, .target = target, .field = code[pc - 1].op.get_field, .copy = pc };
}

fn otherMutableParameter(ctx: *const Context, source: u32) bool {
    // Two `mut` parameters may name the same caller variable. A read through
    // the second parameter can therefore observe the first one's field.
    for (0..ctx.locals.params) |index| {
        if (index != source and ctx.role(@intCast(index)) == .mut_param) return true;
    }
    return false;
}

fn returnSite(ctx: *const Context, transfer: Transfer) ?usize {
    const code = ctx.instructions();
    for (transfer.copy + 2..code.len) |pc| {
        if (writeback(ctx, transfer, pc)) return if (closedFlow(ctx, transfer.copy + 2, pc)) pc + 8 else null;
        if (!ctx.reachable(pc)) return null;
        if (observes(ctx, pc, transfer)) return null;
    }
    return null;
}

// Branches, loops and match arms may rejoin before the store-back. Every
// edge must stay inside this region or enter its final store-back; no outside
// edge may enter after extraction, including at the store-back itself.
fn closedFlow(ctx: *const Context, start: usize, end: usize) bool {
    for (ctx.instructions(), 0..) |instruction, pc| {
        const inside = pc >= start and pc < end;
        const op = instruction.op;
        if (inside) {
            if (!sources.fallsThrough(op) and op != .jump and op != .switch_variant) return false;
            if (op == .try_result) return false;
        }
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(op, &buffer)) |target| {
            if (!closedEdge(inside, target, start, end)) return false;
        }
        if (op == .switch_variant) for (op.switch_variant.arms) |arm| {
            if (!closedEdge(inside, arm.target, start, end)) return false;
        };
    }
    return true;
}

fn closedEdge(inside: bool, target: usize, start: usize, end: usize) bool {
    const enters = target >= start and target <= end;
    return inside == enters;
}

fn straight(ctx: *const Context, pc: usize) bool {
    const op = ctx.instructions()[pc].op;
    var buffer: [2]usize = undefined;
    return ctx.reachable(pc) and !ctx.flow.targets[pc] and sources.fallsThrough(op) and sources.branchTargets(op, &buffer).len == 0;
}

fn observes(ctx: *const Context, pc: usize, transfer: Transfer) bool {
    const code = ctx.instructions();
    const op = code[pc].op;
    if (localIs(op, .load_local, transfer.source) and pc + 1 < code.len) {
        const next = code[pc + 1].op;
        if (next == .get_field and next.get_field != transfer.field) return false;
    }
    const local = switch (op) {
        .load_local, .ref_local, .move_local, .store_local, .drop_local => |slot| li(slot),
        .buffer_operation => |operation| li(operation.owner),
        else => return false,
    };
    if (sibling(ctx, local, transfer, 0)) switch (op) {
        .load_local => return false,
        .store_local => if (ctx.defs.pc[local] == pc) return false,
        .buffer_operation => |operation| if (!model.writesReceiver(operation.kind)) return false,
        else => {},
    };
    return ctx.rootOf(local) == transfer.source;
}

// Trace a single-definition path temporary back to the owner's other field.
// A sibling is an independent value even when it once shared a payload with
// this field; its own copy-on-write marks remain intact.
fn sibling(ctx: *const Context, local: u32, transfer: Transfer, depth: usize) bool {
    if (local == transfer.source or depth >= ctx.locals.list.len) return false;
    if (!ctx.alias(local) or ctx.defs.count[local] != 1) return false;
    const stack = ctx.flow.at[ctx.defs.pc[local]] orelse return false;
    if (stack.len == 0) return false;
    const source = stack[stack.len - 1];
    if (source.origin != .local) return false;
    if (source.local != transfer.source) return sibling(ctx, source.local, transfer, depth + 1);
    const code = ctx.instructions();
    if (source.read >= code.len or source.read + 1 >= code.len) return false;
    const projection = code[source.read + 1].op;
    return localIs(code[source.read].op, .load_local, transfer.source) and projection == .get_field and projection.get_field != transfer.field;
}

// Lowering preserves the RHS and parent in private temporaries before updating
// a record field. Recognize the whole sequence, including its final store, so
// a partially matched update can never remove a copy.
fn writeback(ctx: *const Context, transfer: Transfer, pc: usize) bool {
    const code = ctx.instructions();
    if (pc + 10 >= code.len) return false;
    const ops = code[pc..][0..11];
    if (!localIs(ops[0].op, .load_local, transfer.target) or ops[1].op != .store_local) return false;
    const value = li(ops[1].op.store_local);
    if (!localIs(ops[2].op, .load_local, transfer.source) or ops[3].op != .store_local) return false;
    const parent = li(ops[3].op.store_local);
    if (!privateTemporaries(ctx, transfer, value, parent)) return false;
    if (!localIs(ops[4].op, .load_local, transfer.source) or !localIs(ops[5].op, .store_local, parent)) return false;
    if (!localIs(ops[6].op, .load_local, parent) or !localIs(ops[7].op, .load_local, value)) return false;
    if (ops[8].op != .value_copy or ops[8].op.value_copy.site != .store or ops[9].op != .update_record) return false;
    const update = ops[9].op.update_record;
    if (update.ty != ctx.locals.list[transfer.source].ty or update.indices.len != 1 or update.indices[0] != transfer.field) return false;
    if (!localIs(ops[10].op, .store_local, transfer.source)) return false;
    // The first load may be the region's join. closedFlow verifies that every
    // branch entering it comes from after this extraction.
    if (!ctx.reachable(pc)) return false;
    for (pc + 1..pc + 11) |at| if (!straight(ctx, at)) return false;
    return !ctx.live.after(pc + 10, transfer.target) and !ctx.live.after(pc + 10, value) and !ctx.live.after(pc + 10, parent);
}

fn privateTemporaries(ctx: *const Context, transfer: Transfer, value: u32, parent: u32) bool {
    return ctx.temporary(value) and ctx.temporary(parent) and value != parent and
        value != transfer.source and value != transfer.target and parent != transfer.source and parent != transfer.target;
}

fn localIs(op: Op, comptime tag: @import("std").meta.Tag(Op), index: u32) bool {
    return op == tag and li(@field(op, @tagName(tag))) == index;
}
