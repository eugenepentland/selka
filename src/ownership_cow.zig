//! Copy-on-write placement for the ownership analysis (`OWNERSHIP-ANALYSIS-1`):
//! where a uniqueness check would run before a managed payload is written in
//! place, and which of those checks a loop cannot invalidate, so they run once
//! on the loop's entry edges instead of once per iteration.
//!
//! Ported from the E2b prototype's hoisting (`exp/e2b-rc-runtime:
//! src/qbe_rc_hoist.zig`) and the events its simulation recorded, without the
//! reference counts: an *event* is what an instruction does with a value that
//! shares a root's payload. A root stays unique through a loop that never
//! rebinds it, never stores a value sharing its payload anywhere that outlives
//! the instruction, and never lends it to a call that might keep it; its
//! elements stay unique and in place when, beyond that, nothing in the loop
//! restructures the root or copies element references out of it.
const std = @import("std");
const typed = @import("typed.zig");
const model = @import("ownership_model.zig");
const sources = @import("ownership_sources.zig");

const Context = model.Context;
const Error = model.Error;
const Op = model.Op;
const Source = sources.Source;
const li = model.li;
const none = model.none;

/// What an instruction did with a value sharing one root's payload.
const EventKind = enum(u8) { retain, call, mut_call, escape };
/// One recorded event.
const Event = struct { pc: u32, root: u32, kind: EventKind };
/// A natural loop of the structured instruction stream: its header and the
/// pc of the jump back to it.
const Loop = struct { head: usize, back: usize };

/// The placement in progress: recorded events, the loops, and per
/// instruction the loop header its root or element check moved to.
const Placement = struct {
    ctx: *Context,
    events: std.ArrayList(Event) = .empty,
    loops: []const Loop = &.{},
    /// Per instruction, the header a root uniqueness check here moved to.
    root_hoist: []u32,
    /// Per instruction, the header an element uniqueness check here moved to.
    element_hoist: []u32,
};

/// Place every copy-on-write check of the context's function, hoisted where
/// a loop cannot invalidate it.
pub fn place(ctx: *Context) Error![]const model.Cow {
    const a = ctx.allocator;
    const n = ctx.instructions().len;
    var placement: Placement = .{ .ctx = ctx, .root_hoist = try a.alloc(u32, n), .element_hoist = try a.alloc(u32, n) };
    @memset(placement.root_hoist, none);
    @memset(placement.element_hoist, none);
    for (0..n) |pc| try record(&placement, pc);
    placement.loops = try loops(ctx);
    if (placement.loops.len != 0) try hoist(&placement);
    return sites(&placement);
}

/// Whether an operand shares a payload rather than carrying its own: a value
/// read from a local that is not its last read, or a part of one.
fn borrowedOperand(ctx: *const Context, operand: Source, ty: typed.Type) bool {
    if (operand.origin != .local or !ctx.managedType(ty)) return false;
    if (operand.part != .whole) return true;
    return movedRead(ctx, operand) == null;
}

/// The local a read moves out of: a `move_local`, or the last read of an
/// owned local.
fn movedRead(ctx: *const Context, operand: Source) ?u32 {
    if (operand.read == none) return null;
    return movedAt(ctx, operand.read);
}

/// The local the instruction at `pc` moves out of, or null.
pub fn movedAt(ctx: *const Context, pc: usize) ?u32 {
    return switch (ctx.instructions()[pc].op) {
        .move_local => |slot| li(slot),
        .load_local => |slot| if (ctx.role(li(slot)) == .owned and !ctx.live.after(pc, li(slot))) li(slot) else null,
        else => null,
    };
}

fn note(placement: *Placement, pc: usize, root: u32, kind: EventKind) Error!void {
    try placement.events.append(placement.ctx.allocator, .{ .pc = @intCast(pc), .root = root, .kind = kind });
}

/// Record every event of the instruction at `pc`.
fn record(placement: *Placement, pc: usize) Error!void {
    const ctx = placement.ctx;
    const stack = ctx.flow.at[pc] orelse return;
    const types = ctx.code.states[pc].?;
    const op = ctx.instructions()[pc].op;
    const pops = ctx.flow.pops[pc];
    const base = stack.len - pops;
    try protect(placement, pc, stack, types);
    for (stack[base..], types[base..], 0..) |operand, ty, i| {
        if (!borrowedOperand(ctx, operand, ty)) continue;
        const root = ctx.rootOf(operand.local);
        if (consumes(ctx, op, .{ .index = i, .pops = pops })) try note(placement, pc, root, .retain);
        try operandEvent(placement, pc, operand, root);
    }
    try ownerEvent(placement, pc, op);
    try crossing(placement, pc, stack[0..base], types[0..base]);
    try dyingUnder(placement, pc, stack);
}

/// A result that shares the payload of an owned local whose last use this
/// instruction is keeps a reference of its own.
fn dyingUnder(placement: *Placement, pc: usize, stack: []const Source) Error!void {
    const ctx = placement.ctx;
    const op = ctx.instructions()[pc].op;
    if (!sources.pushes(op) or pc + 1 >= ctx.code.states.len) return;
    const after = ctx.code.states[pc + 1] orelse return;
    if (after.len == 0) return;
    const pushed = sources.pushedSource(ctx.code.program, ctx.code.function, pc, stack);
    if (!borrowedOperand(ctx, pushed, after[after.len - 1])) return;
    const root = ctx.rootOf(pushed.local);
    if (dies(ctx, pc, root)) try note(placement, pc, root, .retain);
}

/// A write of a root, or a load moving a root's value out, while an operand
/// still shares that root's payload: the operand must keep its own reference.
fn protect(placement: *Placement, pc: usize, stack: []const Source, types: []const typed.Type) Error!void {
    const ctx = placement.ctx;
    const base = stack.len - ctx.flow.pops[pc];
    const moved = movedAt(ctx, pc);
    for (stack, types, 0..) |operand, ty, j| {
        if (!borrowedOperand(ctx, operand, ty)) continue;
        const root = ctx.rootOf(operand.local);
        const written = ctx.writesTree(pc, root, null) and !consumedAlias(ctx, pc, j == base) and !receiverOperand(ctx, pc, operand);
        if (written or moved == root) try note(placement, pc, root, .retain);
    }
}

/// Whether the operand is the value a store into an alias local takes.
fn consumedAlias(ctx: *const Context, pc: usize, bottom: bool) bool {
    return switch (ctx.instructions()[pc].op) {
        .store_local => |slot| bottom and ctx.alias(li(slot)),
        else => false,
    };
}

/// Whether an operand is a writing operation's own receiver, loaded after
/// being made unique by the load that pushed it.
fn receiverOperand(ctx: *const Context, pc: usize, operand: Source) bool {
    const operation = switch (ctx.instructions()[pc].op) {
        .buffer_operation => |value| value,
        else => return false,
    };
    if (!model.writesReceiver(operation.kind) or operand.read == none or operand.part != .whole) return false;
    if (!ctx.marks.unique_load[operand.read]) return false;
    return operand.local == li(operation.owner);
}

/// One popped operand's position among the instruction's operands.
const Position = struct { index: usize, pops: usize };

/// Whether the instruction keeps its popped operand at `position` beyond its
/// own execution — stores it, returns it or builds it into a value — rather
/// than only reading it.
fn consumes(ctx: *const Context, op: Op, position: Position) bool {
    const last = position.index + 1 == position.pops;
    return switch (op) {
        .store_local => |slot| !ctx.alias(li(slot)),
        .ret, .make_record, .update_record, .make_variant, .switch_variant, .try_result, .replace_index => true,
        .buffer_operation => |operation| switch (operation.kind) {
            .append => true,
            .insert => last,
            .write => if (dictionary(ctx, li(operation.owner))) position.index != 0 else last,
            else => false,
        },
        else => false,
    };
}

fn dictionary(ctx: *const Context, owner: u32) bool {
    const ty = ctx.locals.list[owner].ty;
    return ty.isAggregate() and ctx.record(ty).collection.kind == .dictionary;
}

/// A call lends its argument (and may keep it); a `mut` argument is written in
/// place; an arithmetic, cast or bulk operation lets element references escape.
fn operandEvent(placement: *Placement, pc: usize, operand: Source, root: u32) Error!void {
    const ctx = placement.ctx;
    switch (ctx.instructions()[pc].op) {
        .call => {
            const mutating = operand.read != none and ctx.marks.unique_load[operand.read];
            try note(placement, pc, root, if (mutating) .mut_call else .call);
        },
        .invoke => try note(placement, pc, root, .call),
        .binary_integer, .cast_integer => try note(placement, pc, root, .escape),
        .buffer_operation => |operation| switch (operation.kind) {
            .extend, .sort_keyed, .update => try note(placement, pc, root, .escape),
            else => {},
        },
        else => {},
    }
}

/// An operation whose receiver's element references may end up in another
/// container.
fn ownerEvent(placement: *Placement, pc: usize, op: Op) Error!void {
    const operation = switch (op) {
        .buffer_operation => |value| value,
        else => return,
    };
    switch (operation.kind) {
        .copy, .slice, .slice_step, .keys, .values, .items, .to_list, .extend, .sort_keyed, .pop, .pop_at => {
            try note(placement, pc, placement.ctx.rootOf(li(operation.owner)), .escape);
        },
        else => {},
    }
}

/// An operand still sharing a payload when control branches, or when a local
/// dies under it, keeps a reference of its own across the edge.
fn crossing(placement: *Placement, pc: usize, below: []const Source, types: []const typed.Type) Error!void {
    const ctx = placement.ctx;
    const op = ctx.instructions()[pc].op;
    const branch = switch (op) {
        .jump, .jump_if_false, .switch_variant, .try_result => true,
        else => false,
    };
    const next = pc + 1;
    const joins = next < ctx.flow.targets.len and ctx.flow.targets[next] and sources.fallsThrough(op);
    for (below, types) |operand, ty| {
        if (!borrowedOperand(ctx, operand, ty)) continue;
        const root = ctx.rootOf(operand.local);
        if (branch or joins or dies(ctx, pc, root)) try note(placement, pc, root, .retain);
    }
}

/// Whether owned local `local` is last used at `pc`.
fn dies(ctx: *const Context, pc: usize, local: u32) bool {
    if (ctx.role(local) != .owned or ctx.live.after(pc, local)) return false;
    return ctx.live.before(pc, local);
}

/// Every loop no edge enters except at its header, widest first.
fn loops(ctx: *Context) Error![]const Loop {
    var found: std.ArrayList(Loop) = .empty;
    for (ctx.instructions(), 0..) |instruction, back| {
        if (!ctx.reachable(back)) continue;
        const head = switch (instruction.op) {
            .jump => |target| target,
            else => continue,
        };
        if (head > back or enteredInside(ctx, head, back)) continue;
        try found.append(ctx.allocator, .{ .head = head, .back = back });
    }
    const items = try found.toOwnedSlice(ctx.allocator);
    std.mem.sort(Loop, items, {}, wider);
    return items;
}

fn wider(_: void, x: Loop, y: Loop) bool {
    return x.back - x.head > y.back - y.head;
}

fn enteredInside(ctx: *const Context, head: usize, back: usize) bool {
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (!ctx.reachable(pc) or (pc >= head and pc <= back)) continue;
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(instruction.op, &buffer)) |target| if (target > head and target <= back) return true;
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (arm.target > head and arm.target <= back) return true;
        };
        if (sources.fallsThrough(instruction.op) and pc + 1 > head and pc + 1 <= back) return true;
    }
    return false;
}

fn inLoop(loop: Loop, pc: usize) bool {
    return pc >= loop.head and pc <= loop.back;
}

fn hasEvent(placement: *const Placement, loop: Loop, root: u32, kinds: []const EventKind) bool {
    for (placement.events.items) |event| {
        if (event.root != root or !inLoop(loop, event.pc)) continue;
        for (kinds) |kind| if (event.kind == kind) return true;
    }
    return false;
}

/// Whether a unique `root` stays unique through every iteration of `loop`.
fn rootHoistable(placement: *const Placement, root: u32, loop: Loop) bool {
    const ctx = placement.ctx;
    if (ctx.role(root) != .owned) return false;
    for (loop.head..loop.back + 1) |pc| {
        if (!ctx.reachable(pc)) continue;
        switch (ctx.instructions()[pc].op) {
            .store_local, .move_local, .drop_local => |slot| if (li(slot) == root) return false,
            else => {},
        }
    }
    return !hasEvent(placement, loop, root, &.{ .retain, .call });
}

/// Whether `root`'s elements, once unique, stay unique and in place through
/// every iteration of `loop`.
fn elementsHoistable(placement: *const Placement, root: u32, loop: Loop) bool {
    const ctx = placement.ctx;
    if (!callerUnique(ctx, root) and !rootHoistable(placement, root, loop)) return false;
    if (hasEvent(placement, loop, root, &.{ .retain, .call, .mut_call, .escape })) return false;
    if (!payloadElements(ctx, root)) return false;
    for (loop.head..loop.back + 1) |pc| {
        if (!ctx.reachable(pc)) continue;
        switch (ctx.instructions()[pc].op) {
            .buffer_operation => |operation| {
                const owner = li(operation.owner);
                const restructures = model.writesReceiver(operation.kind) and ctx.levelZero(owner);
                if (restructures and ctx.rootOf(owner) == root) return false;
            },
            else => {},
        }
    }
    return true;
}

/// Whether local `root` is a list whose elements are managed references.
fn payloadElements(ctx: *const Context, root: u32) bool {
    const ty = ctx.locals.list[root].ty;
    if (!ty.isAggregate()) return false;
    const schema = ctx.record(ty);
    if (!schema.managed or schema.collection.kind != .list) return false;
    const element = schema.shape.buffer orelse return false;
    return element.isAggregate() and ctx.record(element).managed;
}

/// Move every uniqueness check a loop cannot invalidate to the loop's entry.
fn hoist(placement: *Placement) Error!void {
    const ctx = placement.ctx;
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (!ctx.reachable(pc)) continue;
        switch (instruction.op) {
            .buffer_operation => |operation| hoistBuffer(placement, pc, li(operation.owner), model.writesReceiver(operation.kind)),
            .load_local => |slot| if (ctx.marks.unique_load[pc] and ctx.role(li(slot)) == .owned) {
                hoistRoot(placement, pc, li(slot));
            },
            else => {},
        }
    }
}

fn hoistBuffer(placement: *Placement, pc: usize, owner: u32, writes: bool) void {
    const ctx = placement.ctx;
    const owned_site = ctx.locals.managed[owner] and ctx.role(owner) == .owned;
    if (ctx.marks.path_read[pc] and ctx.levelZero(owner)) {
        const root = ctx.rootOf(owner);
        if (outermost(placement, pc, root, true)) |loop| {
            placement.element_hoist[pc] = @intCast(loop.head);
            ctx.marks.plain_read[pc] = true;
        }
    }
    if (owned_site and (writes or ctx.marks.path_read[pc])) hoistRoot(placement, pc, owner);
}

fn hoistRoot(placement: *Placement, pc: usize, root: u32) void {
    const loop = outermost(placement, pc, root, false) orelse return;
    placement.root_hoist[pc] = @intCast(loop.head);
    placement.ctx.marks.suppressed[pc] = true;
}

fn outermost(placement: *const Placement, pc: usize, root: u32, elements: bool) ?Loop {
    for (placement.loops) |loop| {
        if (!inLoop(loop, pc)) continue;
        const ok = if (elements) elementsHoistable(placement, root, loop) else rootHoistable(placement, root, loop);
        if (ok) return loop;
    }
    return null;
}

/// List every check as placed: at a write of an owned collection, at a load
/// handing an owned local to a `mut` parameter or making a path's root unique,
/// and at an element read beginning a write through a temporary.
fn sites(placement: *Placement) Error![]const model.Cow {
    const ctx = placement.ctx;
    var found: std.ArrayList(model.Cow) = .empty;
    for (ctx.instructions(), 0..) |instruction, pc| {
        if (!ctx.reachable(pc)) continue;
        const here: u32 = @intCast(pc);
        switch (instruction.op) {
            .buffer_operation => |operation| {
                const owner = li(operation.owner);
                if (!ctx.locals.managed[owner]) continue;
                if (model.writesReceiver(operation.kind)) switch (ctx.role(owner)) {
                    .path => {},
                    .mut_param => try found.append(ctx.allocator, .{ .pc = here, .local = owner, .via = owner, .elements = false, .needed = !callerUnique(ctx, owner) }),
                    else => try found.append(ctx.allocator, .{ .pc = here, .local = owner, .via = owner, .elements = false, .needed = true, .hoisted = placement.root_hoist[pc] }),
                } else if (ctx.marks.path_read[pc] and rootNeedsCheck(ctx, owner)) {
                    try found.append(ctx.allocator, .{ .pc = here, .local = owner, .via = owner, .elements = false, .needed = true, .hoisted = placement.root_hoist[pc] });
                }
                if (ctx.marks.path_read[pc]) try found.append(ctx.allocator, .{ .pc = here, .local = ctx.rootOf(owner), .via = owner, .elements = true, .needed = true, .hoisted = placement.element_hoist[pc] });
            },
            .load_local => |slot| if (ctx.marks.unique_load[pc]) {
                const local = li(slot);
                const needed = !callerUnique(ctx, local);
                try found.append(ctx.allocator, .{ .pc = here, .local = ctx.rootOf(local), .via = local, .elements = false, .needed = needed, .hoisted = placement.root_hoist[pc] });
            },
            else => {},
        }
    }
    return found.toOwnedSlice(ctx.allocator);
}

fn callerUnique(ctx: *const Context, local: u32) bool {
    return ctx.role(local) == .mut_param and model.uniqueParameter(ctx.code.function, local);
}

fn rootNeedsCheck(ctx: *const Context, local: u32) bool {
    return ctx.role(local) == .owned or (ctx.role(local) == .mut_param and !callerUnique(ctx, local));
}
