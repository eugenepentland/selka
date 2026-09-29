//! A private payload field may return to its original slot without sharing
//! when a mut-list parameter already guarantees a unique, pinned parent.
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");
const values = @import("value_semantics.zig");
const Context = model.Context;
const Op = sources.Op;
const li = model.li;

const Index = struct { source: u32, start: usize };
const Arm = struct { owner: u32, index: Index, payload: u32, start: usize };
const Field = struct { arm: Arm, target: u32, copy: usize };
/// One proved same-slot return, for the physical certificate that moves the
/// element's payload into its binding (`RC-ELEMENT-TAKE-1`): the dispatch
/// reading the element, its payload binding, the extraction's copy site and
/// the final element write.
pub const Return = struct { dispatch: usize, payload: u32, copy: usize, write: usize };

/// Elide only the field transfer inside a closed same-slot replacement. The
/// first parent read has no older local borrow, and the ordinary mut-list
/// call protocol detaches the outer list before extraction;
/// arbitrary list locals and record-held lists retain their normal copies.
pub fn elide(ctx: *const Context, copies: []bool) void {
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (instruction.op != .switch_variant or pc == 0) continue;
        for (instruction.op.switch_variant.arms) |arm| {
            const slot = arm.slot orelse continue;
            const found = readArm(ctx, pc, li(slot), arm.target) orelse continue;
            const field = fieldCopy(ctx, found, copies, true) orelse continue;
            if (committed(ctx, field) != null) copies[field.copy] = false;
        }
    }
}

/// Every same-slot return this proof established, recognized again in a
/// finished analysis whose `copies` already elided the extraction's copy.
pub fn proven(ctx: *const Context, copies: []const bool) model.Error![]const Return {
    var found: @import("std").ArrayList(Return) = .empty;
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (instruction.op != .switch_variant or pc == 0) continue;
        for (instruction.op.switch_variant.arms) |arm| {
            const slot = arm.slot orelse continue;
            const read = readArm(ctx, pc, li(slot), arm.target) orelse continue;
            const field = fieldCopy(ctx, read, copies, false) orelse continue;
            const write = committed(ctx, field) orelse continue;
            try found.append(ctx.allocator, .{ .dispatch = pc, .payload = read.payload, .copy = field.copy, .write = write });
        }
    }
    return found.toOwnedSlice(ctx.allocator);
}

fn readArm(ctx: *const Context, pc: usize, payload: u32, start: usize) ?Arm {
    const code = ctx.instructions();
    const read = code[pc - 1].op;
    if (pc < 2 or read != .buffer_operation or read.buffer_operation.kind != .read) return null;
    const parent = li(read.buffer_operation.owner);
    const index = normalizedIndex(ctx, pc - 2, parent) orelse return null;
    if (index.start < 2 or ctx.flow.targets[pc - 1]) return null;
    if (ctx.flow.targets[index.start - 1] or ctx.flow.targets[index.start]) return null;
    const load = code[index.start - 2].op;
    if (load != .load_local or !localIs(code[index.start - 1].op, .store_local, parent)) return null;
    const owner = li(load.load_local);
    if (!firstUse(ctx, owner, index.start - 2)) return null;
    if (!model.uniqueParameter(ctx.code.function, owner)) return null;
    if (!ctx.temporary(parent) or ctx.defs.count[parent] != 1) return null;
    if (ctx.role(owner) != .mut_param or ctx.record(ctx.locals.list[owner].ty).collection.kind != .list) return null;
    if (!values.enabled()) for (0..ctx.locals.params) |other| {
        if (other != owner and ctx.role(@intCast(other)) == .mut_param) return null;
    };
    if (start + 2 >= code.len or ctx.flow.targets[pc]) return null;
    if (!onlyArmEntry(ctx, pc, start)) return null;
    if (!localIs(code[start].op, .load_local, payload)) return null;
    if (code[start + 1].op != .value_copy or code[start + 1].op.value_copy.site != .payload) return null;
    if (!localIs(code[start + 2].op, .store_local, payload)) return null;
    if (ctx.flow.targets[start + 1] or ctx.flow.targets[start + 2]) return null;
    const ty = ctx.locals.list[payload].ty;
    if (!ty.isAggregate()) return null;
    if (values.containsLiveView(ctx.code.program.records, ty)) return null;
    if (ctx.record(ty).managed or !ctx.record(ty).isRecord()) return null;
    return .{ .owner = owner, .index = index, .payload = payload, .start = start + 3 };
}

// Match bindings can retain unmarked borrows without a parent alias link.
// Requiring the first use of this parameter rules out all earlier captures,
// including outer match/iteration payloads. A loop cannot revisit this read.
fn firstUse(ctx: *const Context, owner: u32, start: usize) bool {
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (pc < start) {
            if (localOf(instruction.op)) |slot| if (ctx.descends(slot, owner)) return false;
            continue;
        }
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(instruction.op, &buffer)) |target| if (target <= start) return false;
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (arm.target <= start) return false;
        };
    }
    return true;
}

fn localOf(op: Op) ?u32 {
    return switch (op) {
        .load_local, .ref_local, .move_local, .store_local, .drop_local => |slot| li(slot),
        .buffer_operation => |operation| li(operation.owner),
        else => null,
    };
}

// The selected switch alone may enter the payload-copy prologue.
fn onlyArmEntry(ctx: *const Context, dispatch: usize, target: usize) bool {
    if (target == 0) return false;
    if (target - 1 != dispatch and ctx.reachable(target - 1)) {
        if (sources.fallsThrough(ctx.instructions()[target - 1].op)) return false;
    }
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (pc == dispatch) continue;
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(instruction.op, &buffer)) |edge| if (edge == target) return false;
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (arm.target == target) return false;
        };
    }
    return true;
}

// Recognize lowering's checked signed-index normalization. Equal source
// locals and an unchanged list length imply the same element for negatives too.
fn normalizedIndex(ctx: *const Context, end: usize, parent: u32) ?Index {
    const code = ctx.instructions();
    if (end < 11 or end >= code.len) return null;
    if (code[end].op != .load_local) return null;
    const slot = li(code[end].op.load_local);
    if (!ctx.temporary(slot)) return null;
    const ops = code[end - 10 ..][0..11];
    if (!localIs(ops[0].op, .store_local, slot) or !localIs(ops[1].op, .load_local, slot)) return null;
    if (ops[2].op != .push_i64 or ops[2].op.push_i64 != 0) return null;
    if (ops[3].op != .cmp_i64 or ops[3].op.cmp_i64 != .lt) return null;
    if (ops[4].op != .jump_if_false or ops[4].op.jump_if_false != end) return null;
    if (ops[5].op != .buffer_operation) return null;
    if (ops[5].op.buffer_operation.kind != .length or li(ops[5].op.buffer_operation.owner) != parent) return null;
    if (ops[6].op != .cast_integer or !localIs(ops[7].op, .load_local, slot)) return null;
    if (ops[8].op != .add_i64_checked or !localIs(ops[9].op, .store_local, slot)) return null;
    var start = end - 11;
    if (code[start].op == .unwrap_domain) {
        if (start == 0) return null;
        start -= 1;
    }
    if (code[start].op != .load_local) return null;
    for (start + 1..end) |at| if (ctx.flow.targets[at]) return null;
    // The normalization's own branch is the only permitted entry at its join.
    for (code, 0..) |instruction, at| {
        if (at == end - 6) continue;
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(instruction.op, &buffer)) |target| if (target == end) return null;
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (arm.target == end) return null;
        };
    }
    return .{ .source = li(code[start].op.load_local), .start = start };
}

// Before extraction the payload may supply scalar/immutable fields only.
// A second mutable projection could be an unmarked alias of the chosen field.
fn fieldCopy(ctx: *const Context, arm: Arm, copies: []const bool, copied: bool) ?Field {
    const code = ctx.instructions();
    if (copies[arm.start - 2]) return null;
    var pc = arm.start;
    while (pc + 3 < code.len) : (pc += 3) {
        if (!localIs(code[pc].op, .load_local, arm.payload) or code[pc + 1].op != .get_field) return null;
        const field = code[pc + 1].op.get_field;
        const ty = ctx.record(ctx.locals.list[arm.payload].ty).fields[field].ty;
        if (values.needsCopy(ctx.code.program.records, ty)) {
            if (code[pc + 2].op != .value_copy or copies[pc + 2] != copied) return null;
            if (code[pc + 2].op.value_copy.site != .assign or code[pc + 3].op != .store_local) return null;
            const target = li(code[pc + 3].op.store_local);
            if (ctx.role(target) != .owned or ctx.defs.count[target] != 1) return null;
            for (pc..pc + 4) |at| if (ctx.flow.targets[at]) return null;
            return .{ .arm = arm, .target = target, .copy = pc + 2 };
        }
        if (code[pc + 2].op != .store_local or ty.isAggregate()) return null;
        const scalar = li(code[pc + 2].op.store_local);
        if (scalar == arm.index.source or ctx.defs.count[scalar] != 1) return null;
        for (pc..pc + 3) |at| if (ctx.flow.targets[at]) return null;
    }
    return null;
}

// The final element write that commits the return, or null.
fn committed(ctx: *const Context, field: Field) ?usize {
    const code = ctx.instructions();
    for (field.copy + 2..code.len) |pc| {
        if (writeback(ctx, field, pc)) |end| {
            if (ctx.live.after(end, field.target) or ctx.live.after(end, field.arm.payload)) return null;
            return if (@import("ownership_field_return.zig").closedFlow(ctx, field.arm.start, end)) end else null;
        }
        if (!ctx.reachable(pc) or observes(ctx, code[pc].op, field)) return null;
    }
    return null;
}

fn observes(ctx: *const Context, op: Op, field: Field) bool {
    const slot = localOf(op) orelse return false;
    if (ctx.descends(slot, field.arm.owner) or ctx.descends(slot, field.arm.payload)) return true;
    if (slot != field.arm.index.source) return false;
    return op != .load_local;
}

// The final write reloads precisely the mut parameter and original signed
// index. No other operation, observer or alternate entry is hidden here.
fn writeback(ctx: *const Context, field: Field, start: usize) ?usize {
    const code = ctx.instructions();
    if (start + 16 >= code.len or !localIs(code[start].op, .load_local, field.arm.owner)) return null;
    if (code[start + 1].op != .store_local) return null;
    const parent = li(code[start + 1].op.store_local);
    if (!ctx.temporary(parent) or ctx.defs.count[parent] != 1) return null;
    var end = start + 13;
    if (code[start + 3].op == .unwrap_domain) end += 1;
    if (end + 3 >= code.len) return null;
    const index = normalizedIndex(ctx, end, parent) orelse return null;
    if (index.start != start + 2 or index.source != field.arm.index.source) return null;
    if (code[end + 1].op != .load_local or code[end + 2].op != .value_copy) return null;
    if (code[end + 2].op.value_copy.site != .store) return null;
    const write = code[end + 3].op;
    if (write != .buffer_operation or write.buffer_operation.kind != .write) return null;
    if (li(write.buffer_operation.owner) != parent) return null;
    for (start + 1..end + 4) |pc| if (pc != end and ctx.flow.targets[pc]) return null;
    return end + 3;
}

fn localIs(op: Op, comptime tag: @import("std").meta.Tag(Op), index: u32) bool {
    return op == tag and li(@field(op, @tagName(tag))) == index;
}
