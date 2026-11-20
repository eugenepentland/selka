//! The single-edit faults of the ownership fault-injection suite (docs/design/ownership-certificates.md §5, plan C2.3 and C4):
//! given the structured form of one function, every way of breaking it with one edit that the validator must refuse. The
//! edits are made on the form, so each mutant is a certificate of a schedule the compiler could have made and did not.
//! `validate_ownership_faults_test.zig` runs them against the validator; `selka mutate-certificates` writes them as
//! certificate files, which the gate action `ownership-proof` runs through the Lean checker as well.
const std = @import("std");
const form = @import("ownership_function.zig");

const Allocator = std.mem.Allocator;

/// The functions `mutate` makes from one function.
pub const Mutants = std.ArrayList(form.Function);

/// The classes of fault: the plan's eight, then the slot faults that only the take protocol can state, then the faults of task
/// loans (design §10).
pub const Class = enum {
    delete_drop,
    duplicate_drop,
    drop_above_use,
    consume_borrowed_parameter,
    destroy_owner_of_live_view,
    consume_borrowed_argument,
    return_outside_from,
    stack_escape,
    take_from_borrowed,
    drop_container_with_open_take,
    second_take_of_pending_slot,
    take_under_loan,
    drop_lender_before_join,
    take_lent_slot_before_join,
    use_group_after_join,
    abandon_used_owner,
    abandon_outside_region,
    abandon_group,
    call_loses_argument,
    call_result_flipped,
    call_names_no_callee,
    construct_reads_dropped_owner,
    view_unmarked,
};

// ---- reading the form --------------------------------------------------------------------------------

fn stateOf(f: form.Function, v: u32) ?form.State {
    for (f.pre) |inst| if (inst.value == v) return inst.result.state;
    for (f.blocks) |block| {
        for (block.phis) |phi| if (phi.value == v) return phi.result.state;
        for (block.insts) |inst| if (inst.value == v) return inst.result.state;
    }
    return null;
}

fn contains(values: []const u32, v: u32) bool {
    return std.mem.indexOfScalar(u32, values, v) != null;
}

fn isParam(f: form.Function, v: u32) bool {
    for (f.params) |param| if (param.value == v) return true;
    return false;
}

/// A value number no line of `f` uses.
fn freshValue(f: form.Function) u32 {
    var top: u32 = 0;
    for (f.pre) |inst| top = @max(top, (inst.value orelse 0) + 1);
    for (f.blocks) |block| {
        for (block.phis) |phi| top = @max(top, phi.value + 1);
        for (block.insts) |inst| top = @max(top, (inst.value orelse 0) + 1);
    }
    return top;
}

fn isTake(inst: form.Inst) bool {
    return inst.class == .project and inst.result.state == .owned and inst.extras.slot != null and inst.reads.len != 0;
}

fn dropOf(v: u32, a: Allocator) Allocator.Error!form.Inst {
    const consumed = try a.alloc(u32, 1);
    consumed[0] = v;
    return .{ .value = null, .op = .drop, .class = .drop, .reads = &.{}, .consumes = consumed, .result = .{ .state = .none } };
}

// ---- editing the form --------------------------------------------------------------------------------

/// `f` with the instructions of block `at` replaced.
fn withInsts(a: Allocator, f: form.Function, at: usize, insts: []const form.Inst) Allocator.Error!form.Function {
    const blocks = try a.dupe(form.Block, f.blocks);
    blocks[at].insts = insts;
    var edited = f;
    edited.blocks = blocks;
    return edited;
}

fn inserted(a: Allocator, insts: []const form.Inst, at: usize, inst: form.Inst) Allocator.Error![]const form.Inst {
    const out = try a.alloc(form.Inst, insts.len + 1);
    @memcpy(out[0..at], insts[0..at]);
    out[at] = inst;
    @memcpy(out[at + 1 ..], insts[at..]);
    return out;
}

fn removed(a: Allocator, insts: []const form.Inst, at: usize) Allocator.Error![]const form.Inst {
    const out = try a.alloc(form.Inst, insts.len - 1);
    @memcpy(out[0..at], insts[0..at]);
    @memcpy(out[at..], insts[at + 1 ..]);
    return out;
}

/// `f` with one instruction replaced.
fn withInst(a: Allocator, f: form.Function, block: usize, at: usize, inst: form.Inst) Allocator.Error!form.Function {
    const insts = try a.dupe(form.Inst, f.blocks[block].insts);
    insts[at] = inst;
    return withInsts(a, f, block, insts);
}

// ---- the classes -------------------------------------------------------------------------------------

/// A drop of an owned value is the end of its obligation: without it the value is never destroyed.
fn deleteDrop(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .drop or stateOf(f, inst.consumes[0]) != .owned) continue;
        try out.append(a, try withInsts(a, f, b, try removed(a, block.insts, i)));
    };
}

/// A second drop of the same owner destroys it twice.
fn duplicateDrop(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .drop or stateOf(f, inst.consumes[0]) != .owned) continue;
        try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, inst)));
    };
}

/// The index of the last instruction before `end` in `insts` that reads `v`, if any.
fn lastRead(insts: []const form.Inst, end: usize, v: u32) ?usize {
    var found: ?usize = null;
    for (insts[0..end], 0..) |inst, j| if (contains(inst.reads, v)) {
        found = j;
    };
    return found;
}

/// A drop moved above a read of its value: the read then uses the value after it was destroyed.
fn dropAboveUse(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .drop or stateOf(f, inst.consumes[0]) != .owned) continue;
        const above = lastRead(block.insts, i, inst.consumes[0]) orelse continue;
        const without = try removed(a, block.insts, i);
        try out.append(a, try withInsts(a, f, b, try inserted(a, without, above, inst)));
    };
}

/// A borrowed parameter consumed by the callee: the caller still owns what it lent.
fn consumeBorrowedParameter(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.params) |param| {
        if (param.state != .borrowed) continue;
        try out.append(a, try withInsts(a, f, 0, try inserted(a, f.blocks[0].insts, 0, try dropOf(param.value, a))));
    }
}

fn hasLaterRead(insts: []const form.Inst, from: usize, v: u32) bool {
    for (insts[from..]) |inst| if (contains(inst.reads, v)) return true;
    return false;
}

/// An owner destroyed while a view of it is still read afterwards.
fn destroyOwnerOfLiveView(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        const view = inst.value orelse continue;
        if (inst.result.state != .borrowed or inst.result.parents.len != 1) continue;
        const owner = switch (inst.result.parents[0]) {
            .value => |o| o,
            .caller => continue,
        };
        if (stateOf(f, owner) != .owned or !hasLaterRead(block.insts, i + 1, view)) continue;
        try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, try dropOf(owner, a))));
    };
}

/// A borrowed argument passed as if it were moved into the call.
fn consumeBorrowedArgument(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .call) continue;
        for (inst.reads) |arg| {
            if (stateOf(f, arg) != .borrowed or contains(inst.consumes, arg)) continue;
            var edited = inst;
            edited.reads = try withoutValue(a, inst.reads, arg);
            edited.consumes = try withValue(a, inst.consumes, arg);
            try out.append(a, try withInst(a, f, b, i, edited));
        }
    };
}

fn withoutValue(a: Allocator, values: []const u32, v: u32) Allocator.Error![]const u32 {
    var kept: std.ArrayList(u32) = .empty;
    for (values) |value| if (value != v) try kept.append(a, value);
    return kept.items;
}

fn withValue(a: Allocator, values: []const u32, v: u32) Allocator.Error![]const u32 {
    const out = try a.alloc(u32, values.len + 1);
    @memcpy(out[0..values.len], values);
    out[values.len] = v;
    return out;
}

/// A borrowed result that names no source, or an owned result that returns a borrowed parameter.
fn returnOutsideFrom(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    if (f.returns.kind == .borrowed and f.returns.from.len != 0) {
        var edited = f;
        edited.returns.from = &.{};
        try out.append(a, edited);
    }
    if (f.returns.kind != .owned) return;
    for (f.params) |param| {
        if (param.state != .borrowed) continue;
        for (f.blocks, 0..) |block, b| {
            if (block.term != .ret or block.term.ret == null) continue;
            const blocks = try a.dupe(form.Block, f.blocks);
            blocks[b].term = .{ .ret = param.value };
            var edited = f;
            edited.blocks = blocks;
            try out.append(a, edited);
        }
    }
}

/// How a value of the chain `start` is used outside the chain: the chain follows updates that consume it first.
const Escape = struct { chain: []const u32, escapes: bool, clean: bool };

/// Follow the updates of the fresh owner `start`, and say whether every use of the chain is a read, an update, a return or a
/// call that consumes it, and whether at least one use is a return or a consuming call.
fn escapeOf(a: Allocator, f: form.Function, start: u32) Allocator.Error!Escape {
    var chain: std.ArrayList(u32) = .empty;
    try chain.append(a, start);
    var result: Escape = .{ .chain = &.{}, .escapes = false, .clean = true };
    var at: usize = 0;
    while (at < chain.items.len) : (at += 1) {
        const v = chain.items[at];
        for (f.blocks) |block| {
            for (block.phis) |phi| for (phi.edges) |edge| {
                if (edge.value == v) result.clean = false;
            };
            for (block.insts) |inst| {
                if (!contains(inst.consumes, v)) continue;
                if (inst.class == .update and inst.consumes[0] == v and inst.value != null and inst.result.state == .owned) {
                    try chain.append(a, inst.value.?);
                } else if (inst.class == .call) {
                    result.escapes = true;
                } else result.clean = false;
            }
            if (block.term == .ret and block.term.ret == v) result.escapes = true;
        }
    }
    result.chain = chain.items;
    return result;
}

/// The same instruction with the state of its result changed.
fn restated(inst: form.Inst, state: form.State) form.Inst {
    var edited = inst;
    edited.result.state = state;
    return edited;
}

/// A list the stack pass placed in the frame, and that the function then returns or hands to a call that takes it.
fn stackEscape(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks) |block| for (block.insts) |inst| {
        const start = inst.value orelse continue;
        if (inst.class != .fresh or inst.result.state != .owned) continue;
        const escape = try escapeOf(a, f, start);
        if (!escape.escapes or !escape.clean) continue;
        var edited = f;
        const blocks = try a.dupe(form.Block, f.blocks);
        for (blocks) |*each| {
            const insts = try a.dupe(form.Inst, each.insts);
            for (insts) |*line| {
                if (line.value != null and contains(escape.chain, line.value.?)) line.* = restated(line.*, .stack);
            }
            each.insts = insts;
        }
        edited.blocks = blocks;
        try out.append(a, edited);
    };
}

/// A take from a container the caller only lent: the parameter becomes borrowed, so the take moves out of storage the
/// function does not own.
fn takeFromBorrowed(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks) |block| for (block.insts) |inst| {
        if (!isTake(inst) or !isParam(f, inst.reads[0])) continue;
        const container = inst.reads[0];
        if (stateOf(f, container) != .owned) continue;
        const params = try a.dupe(form.Param, f.params);
        const pre = try a.dupe(form.Inst, f.pre);
        for (params, 0..) |*param, position| {
            if (param.value != container) continue;
            param.state = .borrowed;
            for (pre) |*line| {
                if (line.value != container) continue;
                const parents = try a.alloc(form.Parent, 1);
                parents[0] = .{ .caller = @intCast(position) };
                line.result = .{ .state = .borrowed, .parents = parents };
            }
        }
        var edited = f;
        edited.params = params;
        edited.pre = pre;
        try out.append(a, edited);
    };
}

/// The container destroyed while one of its slots is out: the taken value would be released with it, and again later.
fn dropContainerWithOpenTake(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (!isTake(inst) or stateOf(f, inst.reads[0]) != .owned) continue;
        try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, try dropOf(inst.reads[0], a))));
    };
}

/// A slot taken again before anything refilled it.
fn secondTakeOfPendingSlot(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    const fresh = freshValue(f);
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (!isTake(inst) or inst.value == null) continue;
        var again = inst;
        again.value = fresh;
        try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, again)));
    };
}

/// A slot taken while a borrow of it is still read afterwards: the take moves the content out, and the borrow then points
/// into a value somebody else owns.
fn takeUnderLoan(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    const fresh = freshValue(f);
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        const view = inst.value orelse continue;
        const key = inst.extras.slot orelse continue;
        if (inst.class != .project or inst.result.state != .borrowed or inst.result.parents.len != 1 or inst.reads.len == 0) continue;
        if (!std.meta.eql(inst.result.parents[0], form.Parent{ .value = inst.reads[0] }) or stateOf(f, inst.reads[0]) != .owned) continue;
        if (!hasLaterRead(block.insts, i + 1, view)) continue;
        var take = inst;
        take.value = fresh;
        take.result = .{ .state = .owned };
        take.extras = .{ .slot = key };
        const with_take = try inserted(a, block.insts, i + 1, take);
        try out.append(a, try withInsts(a, f, b, try inserted(a, with_take, i + 2, try dropOf(fresh, a))));
    };
}

/// The instruction that defines value `v`, if some instruction of a block does.
fn definition(f: form.Function, v: u32) ?form.Inst {
    for (f.blocks) |block| for (block.insts) |inst| if (inst.value == v) return inst;
    return null;
}

/// An owner destroyed right after it was lent to a group: the tasks of the group may still read it.
fn dropLenderBeforeJoin(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.extras.loans.lent == null or stateOf(f, inst.reads[0]) != .owned) continue;
        try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, try dropOf(inst.reads[0], a))));
    };
}

/// A slot taken right after a view of it was lent to a group: the tasks may still read the view of a slot that is not the
/// container's any more.
fn takeLentSlotBeforeJoin(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    const fresh = freshValue(f);
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.extras.loans.lent == null) continue;
        const view = definition(f, inst.reads[0]) orelse continue;
        const key = view.extras.slot orelse continue;
        if (view.class != .project or view.result.state != .borrowed or view.result.parents.len != 1 or view.reads.len == 0) continue;
        if (!std.meta.eql(view.result.parents[0], form.Parent{ .value = view.reads[0] }) or stateOf(f, view.reads[0]) != .owned) continue;
        var take = view;
        take.value = fresh;
        take.result = .{ .state = .owned };
        take.extras = .{ .slot = key };
        const with_take = try inserted(a, block.insts, i + 1, take);
        try out.append(a, try withInsts(a, f, b, try inserted(a, with_take, i + 2, try dropOf(fresh, a))));
    };
}

/// Whether some lend names `v` as its group.
fn isGroup(f: form.Function, v: u32) bool {
    for (f.blocks) |block| for (block.insts) |inst| if (inst.extras.loans.lent == v) return true;
    return false;
}

/// A group used after the call that joined it: a call that read the group before is repeated after the join (or the join
/// itself, when nothing else reads the group).
fn useGroupAfterJoin(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    const fresh = freshValue(f);
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .call or inst.result.state != .none) continue;
        for (inst.consumes) |group| {
            if (!isGroup(f, group)) continue;
            var again = inst;
            for (f.blocks) |other| for (other.insts) |reader| {
                if (reader.class == .call and contains(reader.reads, group) and !contains(reader.consumes, group)) again = reader;
            };
            if (again.value != null) again.value = fresh;
            try out.append(a, try withInsts(a, f, b, try inserted(a, block.insts, i + 1, again)));
        }
    };
}

/// `f` with `value` added to the owners block `at` abandons on the edge from `from`; null when it is listed already.
fn withAbandon(a: Allocator, f: form.Function, at: usize, from: u32, value: u32) Allocator.Error!?form.Function {
    const blocks = try a.dupe(form.Block, f.blocks);
    var lists: std.ArrayList(form.Abandon) = .empty;
    var placed = false;
    for (blocks[at].abandons) |gone| {
        if (gone.from != from) {
            try lists.append(a, gone);
            continue;
        }
        if (contains(gone.values, value)) return null;
        placed = true;
        const grown = try a.alloc(u32, gone.values.len + 1);
        @memcpy(grown[0..gone.values.len], gone.values);
        grown[gone.values.len] = value;
        std.mem.sort(u32, grown, {}, std.sort.asc(u32));
        try lists.append(a, .{ .from = from, .values = grown });
    }
    if (!placed) {
        const single = try a.alloc(u32, 1);
        single[0] = value;
        try lists.append(a, .{ .from = from, .values = single });
    }
    blocks[at].abandons = lists.items;
    var edited = f;
    edited.blocks = blocks;
    return edited;
}

/// Whether block `block` defines value `v` (by an instruction or a phi).
fn definesIn(block: form.Block, v: u32) bool {
    for (block.phis) |phi| if (phi.value == v) return true;
    for (block.insts) |inst| if (inst.value == v) return true;
    return false;
}

/// An owner a trap block uses, abandoned on the edge into it: the use then reads or consumes a value that is not live.
fn abandonUsedOwner(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| {
        if (block.term != .unreachable_path) continue;
        for (block.insts) |inst| for ([_][]const u32{ inst.reads, inst.consumes }) |operands| for (operands) |v| {
            if (stateOf(f, v) != .owned or definesIn(block, v)) continue;
            for (block.preds) |pred| if (try withAbandon(a, f, b, pred, v)) |edited| try out.append(a, edited);
        };
    }
}

/// The first owned value an instruction of `f` defines.
fn firstOwned(f: form.Function) ?u32 {
    for (f.blocks) |block| for (block.insts) |inst| {
        if (inst.value != null and inst.result.state == .owned) return inst.value;
    };
    return null;
}

/// An owner abandoned on an edge into a block the function can leave by a return: nothing ends the run there.
fn abandonOutsideRegion(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    const v = firstOwned(f) orelse return;
    for (f.blocks, 0..) |block, b| {
        if (block.term != .ret) continue;
        for (block.preds) |pred| if (try withAbandon(a, f, b, pred, v)) |edited| try out.append(a, edited);
    }
}

/// A group abandoned on an edge into a trap block: its tasks would keep reading the lent cells after the loans were forgotten.
fn abandonGroup(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks) |lender| for (lender.insts) |lend| {
        const group = lend.extras.loans.lent orelse continue;
        for (f.blocks, 0..) |block, b| {
            if (block.term != .unreachable_path) continue;
            for (block.preds) |pred| if (try withAbandon(a, f, b, pred, group)) |edited| try out.append(a, edited);
        }
    };
}

/// A call that reads one value fewer than its callee's parameters: the operands are not the parameters any more.
fn callLosesArgument(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .call or inst.reads.len == 0) continue;
        var edited = inst;
        edited.reads = inst.reads[0 .. inst.reads.len - 1];
        try out.append(a, try withInst(a, f, b, i, edited));
    };
}

/// A callee table entry that says the callee returns something else than its calls take: an owner where the calls get a scalar,
/// a scalar where they get an owner or a borrow.
fn callResultFlipped(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.callees, 0..) |callee, i| {
        if (callee.kind != .program and callee.kind != .indirect) continue;
        const table = try a.dupe(form.Callee, f.callees);
        table[i].result = if (callee.result == .owned) .scalar else .owned;
        var edited = f;
        edited.callees = table;
        try out.append(a, edited);
    }
}

/// A call line that does not say which callee it calls.
fn callNamesNoCallee(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .call) continue;
        var edited = inst;
        edited.extras.call.callee = null;
        try out.append(a, try withInst(a, f, b, i, edited));
    };
}

/// A constructor with an owned or emptied result that reads a borrow of an owner it consumed before (lane VAL, the plan of
/// FX6): the owner is borrowed instead (`%n = borrow %c`), the constructor reads the borrow, and the owner is dropped right
/// after. The aggregate then destroys, or a take out of it hands out as an owner, storage the drop frees too. Only the
/// construct-read rule (J6) refuses it: no other judgment sees where the storage of a borrow a constructor reads goes.
fn constructReadsDroppedOwner(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .construct or inst.extras.loans.lent != null) continue;
        if (inst.result.state != .owned and inst.result.state != .emptied) continue;
        for (inst.consumes) |owner| {
            if (stateOf(f, owner) != .owned) continue;
            const view = freshValue(f);
            const parents = try a.alloc(form.Parent, 1);
            parents[0] = .{ .value = owner };
            const reads = try a.alloc(u32, 1);
            reads[0] = owner;
            const borrow: form.Inst = .{ .value = view, .op = .borrow, .class = .borrow, .reads = reads, .consumes = &.{}, .result = .{ .state = .borrowed, .parents = parents } };
            var edited = inst;
            edited.consumes = try withoutValue(a, inst.consumes, owner);
            edited.reads = try withValue(a, inst.reads, view);
            const insts = try a.alloc(form.Inst, block.insts.len + 2);
            @memcpy(insts[0..i], block.insts[0..i]);
            insts[i] = borrow;
            insts[i + 1] = edited;
            insts[i + 2] = try dropOf(owner, a);
            @memcpy(insts[i + 3 ..], block.insts[i + 1 ..]);
            try out.append(a, try withInsts(a, f, b, insts));
        }
    };
}

/// The parents the line that defines `v` gives it, or none.
fn parentsOf(f: form.Function, v: u32) []const form.Parent {
    for (f.pre) |inst| if (inst.value == v) return inst.result.parents;
    for (f.blocks) |block| {
        for (block.phis) |phi| if (phi.value == v) return phi.result.parents;
        for (block.insts) |inst| if (inst.value == v) return inst.result.parents;
    }
    return &.{};
}

/// An owned constructor that holds a borrowed operand as a loan, with the operand no longer marked a view (format v2): the
/// plan of an aggregate that holds a borrowed `str`, list or record its destruction would destroy. Only the view part of the
/// construct-read rule (condition 2) refuses it. Made only for a view none of whose parents the constructor consumes, so
/// that condition 1 does not accept it instead.
fn viewUnmarked(a: Allocator, f: form.Function, out: *Mutants) Allocator.Error!void {
    for (f.blocks, 0..) |block, b| for (block.insts, 0..) |inst, i| {
        if (inst.class != .construct or inst.result.state != .owned) continue;
        for (inst.extras.loans.views) |view| {
            var inside = false;
            for (parentsOf(f, view)) |parent| switch (parent) {
                .value => |p| inside = inside or contains(inst.consumes, p),
                .caller => {},
            };
            if (inside) continue;
            var edited = inst;
            edited.extras.loans.views = try withoutValue(a, inst.extras.loans.views, view);
            try out.append(a, try withInst(a, f, b, i, edited));
        }
    };
}

/// Every mutant of `f` in `class`, appended to `out`: each is a certificate of a schedule the compiler could have made and did not.
pub fn mutate(a: Allocator, class: Class, f: form.Function, out: *Mutants) Allocator.Error!void {
    switch (class) {
        .delete_drop => try deleteDrop(a, f, out),
        .duplicate_drop => try duplicateDrop(a, f, out),
        .drop_above_use => try dropAboveUse(a, f, out),
        .consume_borrowed_parameter => try consumeBorrowedParameter(a, f, out),
        .destroy_owner_of_live_view => try destroyOwnerOfLiveView(a, f, out),
        .consume_borrowed_argument => try consumeBorrowedArgument(a, f, out),
        .return_outside_from => try returnOutsideFrom(a, f, out),
        .stack_escape => try stackEscape(a, f, out),
        .take_from_borrowed => try takeFromBorrowed(a, f, out),
        .drop_container_with_open_take => try dropContainerWithOpenTake(a, f, out),
        .second_take_of_pending_slot => try secondTakeOfPendingSlot(a, f, out),
        .take_under_loan => try takeUnderLoan(a, f, out),
        .drop_lender_before_join => try dropLenderBeforeJoin(a, f, out),
        .take_lent_slot_before_join => try takeLentSlotBeforeJoin(a, f, out),
        .use_group_after_join => try useGroupAfterJoin(a, f, out),
        .abandon_used_owner => try abandonUsedOwner(a, f, out),
        .abandon_outside_region => try abandonOutsideRegion(a, f, out),
        .abandon_group => try abandonGroup(a, f, out),
        .call_loses_argument => try callLosesArgument(a, f, out),
        .call_result_flipped => try callResultFlipped(a, f, out),
        .call_names_no_callee => try callNamesNoCallee(a, f, out),
        .construct_reads_dropped_owner => try constructReadsDroppedOwner(a, f, out),
        .view_unmarked => try viewUnmarked(a, f, out),
    }
}
