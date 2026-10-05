//! The explicit narrow-lane vector lowering of counted reductions (docs/design/new-core-ir.md §7),
//! ported from the WP-8 spike's `llvm_direct_vector.zig` onto the Core IR and its facts.
//!
//! A counted loop qualifies when, after the fact pass:
//! - its body is one straight chain of blocks (branches the facts decided are
//!   followed, their dead targets ignored) ending in the latch's counter step;
//! - its header carries only the counter and one accumulator `acc = phi(init, acc + s)`;
//! - every body instruction is a proven `+ - *`, a proven division or
//!   remainder by a positive constant, a proven read `xs[counter]` of a list
//!   defined before the loop, or a forwarding phi or copy;
//! - every per-element value is non-negative and fits 16 (or 32) bits, and the
//!   counter is used only as the index.
//! The lowering then runs `floor(trips / lanes) * lanes` elements as vectors
//! before the unchanged scalar loop, which starts after them with the partial
//! sum: the scalar loop is the tail. 16-bit lanes load `i64` storage with
//! `packusdw`, divide by constants with a multiply-high reciprocal checked over
//! the proven dividend range, and sum with `pmaddwd` into 32-bit lanes folded
//! into the 64-bit total before they can overflow. The order of lanes is not
//! preserved, which a sum of element-wise values does not observe.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// Planning and emission only allocate.
pub const Error = std.mem.Allocator.Error;

/// The loop-carried values of a qualifying loop.
pub const Carried = struct {
    counter: ir.Ref,
    start: ir.Ref,
    bound: ir.Ref,
    acc: ir.Ref,
    acc_init: ir.Ref,
    summand: ir.Ref,
};

/// A join phi of an if/else inside the body, computed as a lane `select`.
pub const Select = struct { phi: ir.Ref, condition: ir.Ref, then_value: ir.Ref, else_value: ir.Ref };

/// One loop the lowering vectorizes.
pub const Plan = struct {
    loop: ir.Loop,
    carried: Carried,
    /// The header's predecessor outside the loop.
    preheader: ir.BlockId,
    /// Body instructions in execution order (no terminators, no folded constants).
    /// Both arms of an if/else run on every lane; they are proven pure and trap-free.
    body: []const ir.Ref,
    selects: []const Select,
    /// Lane width in bits: 16 or 32.
    bits: u16,
};

/// One if/else of the body: its arms and the block they join in.
const Diamond = struct { then_block: ?ir.BlockId, else_block: ?ir.BlockId, join: ir.BlockId };

/// Recognize `if c: T else: E` (either arm may be empty) whose arms are single
/// blocks falling into one join reached from nowhere else.
fn diamond(f: *const ir.Function, block: ir.BlockId, then: ir.BlockId, otherwise: ir.BlockId) ?Diamond {
    const then_next = armTarget(f, block, then);
    const else_next = armTarget(f, block, otherwise);
    if (then_next != null and else_next != null and then_next.? == else_next.?) return .{ .then_block = then, .else_block = otherwise, .join = then_next.? };
    if (then_next != null and then_next.? == otherwise) return .{ .then_block = then, .else_block = null, .join = otherwise };
    if (else_next != null and else_next.? == then) return .{ .then_block = null, .else_block = otherwise, .join = then };
    return null;
}

/// The block an arm falls into: the arm has `from` as its only predecessor and ends in a jump.
fn armTarget(f: *const ir.Function, from: ir.BlockId, arm: ir.BlockId) ?ir.BlockId {
    const preds = f.blocks.items[arm.index()].preds.items;
    if (preds.len != 1 or preds[0] != from) return null;
    const insts = f.blocks.items[arm.index()].insts.items;
    const last = f.inst(insts[insts.len - 1]);
    if (last.op != .jump) return null;
    return @fromBackingInt(@as(u32, @intCast(last.data)));
}

/// Find every loop of `f` the lowering can take.
pub fn plan(arena: std.mem.Allocator, f: *const ir.Function, known: facts.Facts) Error![]Plan {
    var plans: std.ArrayList(Plan) = .empty;
    for (known.counted) |counted| {
        if (try planLoop(arena, f, known, counted)) |found| try plans.append(arena, found);
    }
    return plans.items;
}

/// Whether control can pass from `from` to `to` after the facts folded decided branches.
fn edgeTaken(f: *const ir.Function, known: facts.Facts, from: ir.BlockId, to: ir.BlockId) bool {
    if (!known.reachable[from.index()]) return false;
    const insts = f.blocks.items[from.index()].insts.items;
    const last = f.inst(insts[insts.len - 1]);
    if (last.op != .branch) return true;
    const targets = ir.unpackTargets(last.data);
    const condition = f.inst(f.resolve(last.a));
    if (condition.op != .iconst) return true;
    return if (condition.data != 0) targets.then == to else targets.otherwise == to;
}

/// The next block of a straight chain: the one successor control can take.
fn next(f: *const ir.Function, block: ir.BlockId) ?ir.BlockId {
    const insts = f.blocks.items[block.index()].insts.items;
    const last = f.inst(insts[insts.len - 1]);
    switch (last.op) {
        .jump => return @fromBackingInt(@intCast(@as(u32, @intCast(last.data)))),
        .branch => {
            const targets = ir.unpackTargets(last.data);
            const condition = f.inst(f.resolve(last.a));
            if (condition.op != .iconst) return null;
            return if (condition.data != 0) targets.then else targets.otherwise;
        },
        else => return null,
    }
}

/// A phi whose only live incoming edge is `from`: it forwards that operand.
fn forwarded(f: *const ir.Function, known: facts.Facts, block: ir.BlockId, phi: ir.Inst) ?ir.Ref {
    var only: ir.Ref = .none;
    for (f.operands(phi.data), f.blocks.items[block.index()].preds.items) |operand, pred| {
        if (!edgeTaken(f, known, pred, block)) continue;
        if (only != .none and f.resolve(only) != f.resolve(operand)) return null;
        only = operand;
    }
    return if (only == .none) null else f.resolve(only);
}

/// The header's single accumulator and its update, or null.
const Reduction = struct { acc: ir.Ref, update: ir.Ref, summand: ir.Ref, init: ir.Ref };

fn reductionOf(f: *const ir.Function, counted: facts.Counted, latch_index: usize) ?Reduction {
    const header = f.blocks.items[counted.loop.header.index()];
    // Header: the counter, one accumulator, the condition and its branch.
    var acc: ir.Ref = .none;
    for (header.insts.items) |ref| {
        const inst = f.inst(ref);
        switch (inst.op) {
            .phi => {
                if (ref == counted.counter) continue;
                if (acc != .none or inst.ty != .i64) return null;
                acc = ref;
            },
            .cmp, .branch, .copy => {},
            else => return null,
        }
    }
    if (acc == .none) return null;
    const operands = f.operands(f.inst(acc).data);
    const update_ref = f.resolve(operands[latch_index]);
    const update = f.inst(update_ref);
    if (update.op != .add or update.check != .proven) return null;
    const summand = if (f.resolve(update.a) == acc) f.resolve(update.b) else if (f.resolve(update.b) == acc) f.resolve(update.a) else return null;
    return .{ .acc = acc, .update = update_ref, .summand = summand, .init = f.resolve(operands[1 - latch_index]) };
}

/// The flattened body of a loop: its lane instructions, its selects, and which blocks it covers.
const Body = struct { refs: std.ArrayList(ir.Ref) = .empty, selects: std.ArrayList(Select) = .empty, in_loop: []bool };

/// Walk from the body block to the latch, flattening if/else diamonds; null when the shape does not fit.
fn walkBody(arena: std.mem.Allocator, f: *const ir.Function, known: facts.Facts, loop: ir.Loop, update: ir.Ref) Error!?Body {
    var body: Body = .{ .in_loop = try arena.alloc(bool, f.blocks.items.len) };
    @memset(body.in_loop, false);
    body.in_loop[loop.header.index()] = true;
    var block = loop.body;
    var steps: usize = 0;
    var join: ?Diamond = null;
    var join_condition: ir.Ref = .none;
    while (block != loop.latch) : (steps += 1) {
        if (steps > f.blocks.items.len) return null;
        body.in_loop[block.index()] = true;
        const joining = join != null and join.?.join == block;
        if (!try collect(arena, f, known, &body, .{ .block = block, .update = update, .join = if (joining) join else null, .condition = join_condition })) return null;
        if (joining) join = null;
        const insts = f.blocks.items[block.index()].insts.items;
        const last = f.inst(insts[insts.len - 1]);
        const decided = last.op != .branch or f.inst(f.resolve(last.a)).op == .iconst;
        if (!decided) {
            if (join != null) return null;
            const targets = ir.unpackTargets(last.data);
            const found = diamond(f, block, targets.then, targets.otherwise) orelse return null;
            if (!try collectArms(arena, f, &body, found, update)) return null;
            join = found;
            join_condition = f.resolve(last.a);
            block = found.join;
            continue;
        }
        const following = next(f, block) orelse return null;
        // Every other way into the next block must be dead.
        for (f.blocks.items[following.index()].preds.items) |pred| {
            if (pred != block and edgeTaken(f, known, pred, following)) return null;
        }
        block = following;
    }
    body.in_loop[loop.latch.index()] = true;
    return body;
}

/// Where `collect` reads one block from, and whether it joins an if/else.
const Visit = struct { block: ir.BlockId, update: ir.Ref, join: ?Diamond, condition: ir.Ref };

/// Add a block's lane instructions; its two-way phis become selects when it joins an if/else.
fn collect(arena: std.mem.Allocator, f: *const ir.Function, known: facts.Facts, body: *Body, visit: Visit) Error!bool {
    for (f.blocks.items[visit.block.index()].insts.items) |ref| {
        const inst = f.inst(ref);
        // The accumulator's own update is the reduction, not a lane value.
        if (inst.op.terminates() or inst.op == .copy or inst.op == .iconst or ref == visit.update) continue;
        if (inst.op == .phi and forwarded(f, known, visit.block, inst) == null) {
            const d = visit.join orelse return false;
            try body.selects.append(arena, try selectOf(f, d, visit.condition, visit.block, ref));
        }
        try body.refs.append(arena, ref);
    }
    return true;
}

/// Add both arms of an if/else, which every lane runs.
fn collectArms(arena: std.mem.Allocator, f: *const ir.Function, body: *Body, found: Diamond, update: ir.Ref) Error!bool {
    for ([_]?ir.BlockId{ found.then_block, found.else_block }) |maybe| {
        const arm = maybe orelse continue;
        body.in_loop[arm.index()] = true;
        for (f.blocks.items[arm.index()].insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op.terminates() or inst.op == .copy or inst.op == .iconst) continue;
            if (inst.op == .phi or ref == update) return false;
            try body.refs.append(arena, ref);
        }
    }
    return true;
}

/// Whether one body instruction is a lane operation the lowering can emit.
fn laneShaped(f: *const ir.Function, known: facts.Facts, body: *const Body, ref: ir.Ref, counter: ir.Ref) bool {
    const inst = f.inst(ref);
    const ok = switch (inst.op) {
        .phi, .cmp => true,
        .add, .sub, .mul => inst.check == .proven,
        .floor_div, .floor_rem, .div, .rem => inst.check == .proven and positiveConstant(f, inst.b) != null,
        .list_get => inst.check == .proven and (inst.ty == .i64 or inst.ty == .bool) and indexIsCounter(f, known, inst.b, counter) and !definedIn(f, body.in_loop, inst.a),
        else => false,
    };
    if (!ok or inst.op == .phi) return ok;
    if (inst.ty == .bool and !usedOnlyAsCondition(body.refs.items, body.selects.items, f, ref)) return false;
    if (inst.op == .list_get) return true;
    // The counter is only ever an index.
    return f.resolve(inst.a) != counter and f.resolve(inst.b) != counter;
}

/// The lane width every value of the body fits (16 or 32), or null.
fn laneWidth(f: *const ir.Function, known: facts.Facts, body: *const Body) ?u16 {
    var widest: u16 = 16;
    for (body.refs.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .phi) continue;
        widest = @max(widest, width(known.ranges[ref.index()]) orelse return null);
        if (inst.op == .list_get) continue;
        for ([_]ir.Ref{ inst.a, inst.b }) |operand| {
            if (operand == .none or definedIn(f, body.in_loop, operand)) continue;
            widest = @max(widest, width(rangeOf(f, known, operand)) orelse return null);
        }
    }
    for (body.selects.items) |select| {
        for ([_]ir.Ref{ select.then_value, select.else_value }) |operand| {
            if (operand == .none or definedIn(f, body.in_loop, operand)) continue;
            widest = @max(widest, width(rangeOf(f, known, operand)) orelse return null);
        }
    }
    return if (widest > 32) null else widest;
}

fn planLoop(arena: std.mem.Allocator, f: *const ir.Function, known: facts.Facts, counted: facts.Counted) Error!?Plan {
    const loop = counted.loop;
    const header = f.blocks.items[loop.header.index()];
    if (header.preds.items.len != 2) return null;
    // The vector part indexes from `start`; a negative start stays scalar.
    const start_range = rangeOf(f, known, counted.start) orelse return null;
    if (start_range.lo < 0) return null;
    const latch_index: usize = if (header.preds.items[0] == loop.latch) 0 else 1;
    const reduction = reductionOf(f, counted, latch_index) orelse return null;
    const body = (try walkBody(arena, f, known, loop, reduction.update)) orelse return null;
    if (f.blocks.items[loop.latch.index()].insts.items.len != 2) return null;
    for (body.refs.items) |ref| if (!laneShaped(f, known, &body, ref, counted.counter)) return null;
    if (!contains(body.refs.items, reduction.summand)) return null;
    const bits = laneWidth(f, known, &body) orelse return null;
    return .{
        .loop = loop,
        .carried = .{ .counter = counted.counter, .start = counted.start, .bound = counted.bound, .acc = reduction.acc, .acc_init = reduction.init, .summand = reduction.summand },
        .preheader = header.preds.items[1 - latch_index],
        .body = body.refs.items,
        .selects = body.selects.items,
        .bits = bits,
    };
}

/// The lane select a join phi becomes: the operand on the then edge where the condition holds.
fn selectOf(f: *const ir.Function, d: Diamond, condition: ir.Ref, join: ir.BlockId, phi_ref: ir.Ref) Error!Select {
    const phi = f.inst(phi_ref);
    var then_value: ir.Ref = .none;
    var else_value: ir.Ref = .none;
    for (f.operands(phi.data), f.blocks.items[join.index()].preds.items) |operand, pred| {
        const from_then = if (d.then_block) |arm| pred == arm else d.else_block != null and pred != d.else_block.?;
        if (from_then) then_value = f.resolve(operand) else else_value = f.resolve(operand);
    }
    return .{ .phi = phi_ref, .condition = condition, .then_value = then_value, .else_value = else_value };
}

fn contains(items: []const ir.Ref, wanted: ir.Ref) bool {
    for (items) |item| if (item == wanted) return true;
    return false;
}

/// A boolean lane (a mask) may only steer selects.
fn usedOnlyAsCondition(body: []const ir.Ref, selects: []const Select, f: *const ir.Function, ref: ir.Ref) bool {
    for (body) |item| {
        const inst = f.inst(item);
        if (inst.op == .phi) continue;
        if (f.resolve(inst.a) == ref or f.resolve(inst.b) == ref) return false;
    }
    for (selects) |select| {
        if (select.then_value == ref or select.else_value == ref) return false;
    }
    return true;
}

fn positiveConstant(f: *const ir.Function, raw: ir.Ref) ?u32 {
    const inst = f.inst(f.resolve(raw));
    if (inst.op != .iconst) return null;
    const value: i64 = @bitCast(inst.data);
    return if (value > 0 and value < 0x10000) @intCast(value) else null;
}

fn indexIsCounter(f: *const ir.Function, known: facts.Facts, raw: ir.Ref, counter: ir.Ref) bool {
    var ref = f.resolve(raw);
    var guard: usize = 0;
    while (guard < 8) : (guard += 1) {
        if (ref == counter) return true;
        const inst = f.inst(ref);
        if (inst.op != .phi) return false;
        var block: ?ir.BlockId = null;
        for (f.blocks.items, 0..) |candidate, b| {
            for (candidate.insts.items) |item| if (item == ref) {
                block = @fromBackingInt(@intCast(b));
            };
        }
        ref = forwarded(f, known, block orelse return false, inst) orelse return false;
    }
    return false;
}

/// Whether `raw` is computed inside the loop (a block marked in `in_loop`).
fn definedIn(f: *const ir.Function, in_loop: []const bool, raw: ir.Ref) bool {
    const ref = f.resolve(raw);
    for (f.blocks.items, 0..) |block, b| {
        if (!in_loop[b]) continue;
        for (block.insts.items) |item| if (item == ref) return true;
    }
    return false;
}

fn rangeOf(f: *const ir.Function, known: facts.Facts, raw: ir.Ref) ?facts.Interval {
    const ref = f.resolve(raw);
    const inst = f.inst(ref);
    if (inst.op == .iconst) {
        const value: i64 = @bitCast(inst.data);
        return facts.Interval.point(value);
    }
    return known.ranges[ref.index()];
}

/// The unsigned lane width (16, 32 or 64) a non-negative range needs.
fn width(maybe: ?facts.Interval) ?u16 {
    const range = maybe orelse return null;
    if (range.lo < 0) return null;
    if (range.hi < 0x10000) return 16;
    if (range.hi < 0x1_0000_0000) return 32;
    return 64;
}

/// The multiplier and shift that make `(x * multiplier) >> (16 + shift)` equal `x / divisor`.
pub const Reciprocal = struct { multiplier: u32, shift: u5 };

/// The smallest-shift reciprocal of `divisor` that is exact for every dividend
/// in `[lo, hi]` (both below 2^16) with a multiplier below 2^16, or null.
pub fn reciprocal(divisor: u32, lo: u32, hi: u32) ?Reciprocal {
    if (divisor == 0 or hi > 0xffff) return null;
    var shift: u5 = 0;
    while (shift < 16) : (shift += 1) {
        const scale: u64 = @as(u64, 1) << (16 + @as(u6, shift));
        const multiplier = (scale + divisor - 1) / divisor;
        if (multiplier >= 0x10000) break;
        var x: u64 = lo;
        const exact = while (x <= hi) : (x += 1) {
            if ((x * multiplier) >> (16 + @as(u6, shift)) != x / divisor) break false;
        } else true;
        if (exact) return .{ .multiplier = @intCast(multiplier), .shift = shift };
    }
    return null;
}

// ---- emission ---------------------------------------------------------------------

/// How the vector code names the scalar values it reads (the function emitter's operands).
pub const Scalars = struct {
    context: *anyopaque,
    name: *const fn (*anyopaque, ir.Ref) Error![]const u8,
};

/// What one emission needs: the plan, its unique number, the facts and how to name scalars.
pub const Emission = struct {
    plan: Plan,
    id: u32,
    known: facts.Facts,
    scalars: Scalars,
    /// The label the preheader's code currently ends in.
    from: []const u8,
};

/// The values the scalar loop starts from after the vector part.
pub const Resume = struct { label: []const u8, counter: []const u8, acc: []const u8 };

const Out = std.ArrayList(u8);

/// Emit the vector loop in front of the scalar one; the caller then jumps to the
/// header from `Resume.label`, with the header phis starting at `Resume`'s values.
pub fn emit(arena: std.mem.Allocator, out: *Out, f: *const ir.Function, e: Emission) Error!Resume {
    var w: Writer = .{ .arena = arena, .out = out, .f = f, .e = e };
    return w.run();
}

const Writer = struct {
    arena: std.mem.Allocator,
    out: *Out,
    f: *const ir.Function,
    e: Emission,

    fn put(self: *Writer, comptime format: []const u8, args: anytype) Error!void {
        try self.out.print(self.arena, format, args);
    }

    fn lanes(self: *Writer) u32 {
        return 256 / @as(u32, self.e.plan.bits);
    }

    fn vec(self: *Writer) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "<{d} x i{d}>", .{ self.lanes(), self.e.plan.bits });
    }

    fn scalar(self: *Writer, ref: ir.Ref) Error![]const u8 {
        return self.e.scalars.name(self.e.scalars.context, ref);
    }

    fn splatConstant(self: *Writer, value: i64) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "splat (i{d} {d})", .{ self.e.plan.bits, value });
    }

    /// The lane operand for a value: a lane vector inside the loop, a splat outside it.
    fn lane(self: *Writer, raw: ir.Ref) Error![]const u8 {
        const ref = self.resolveForward(raw);
        if (contains(self.e.plan.body, ref)) return std.fmt.allocPrint(self.arena, "%vl{d}.{d}", .{ self.e.id, ref.index() });
        const inst = self.f.inst(ref);
        if (inst.op == .iconst) return self.splatConstant(@bitCast(inst.data));
        return std.fmt.allocPrint(self.arena, "%vs{d}.{d}", .{ self.e.id, ref.index() });
    }

    fn resolveForward(self: *Writer, raw: ir.Ref) ir.Ref {
        var ref = self.f.resolve(raw);
        var guard: usize = 0;
        while (guard < 16) : (guard += 1) {
            const inst = self.f.inst(ref);
            if (inst.op != .phi or !contains(self.e.plan.body, ref)) return ref;
            const block = self.blockOf(ref) orelse return ref;
            ref = forwarded(self.f, self.e.known, block, inst) orelse return ref;
        }
        return ref;
    }

    fn blockOf(self: *Writer, ref: ir.Ref) ?ir.BlockId {
        for (self.f.blocks.items, 0..) |block, b| {
            for (block.insts.items) |item| if (item == ref) return @fromBackingInt(@intCast(b));
        }
        return null;
    }

    fn run(self: *Writer) Error!Resume {
        const p = self.e.plan;
        const n = self.e.id;
        const count = self.lanes();
        const v = try self.vec();
        const start = try self.scalar(p.carried.start);
        const bound = try self.scalar(p.carried.bound);
        const acc0 = try self.scalar(p.carried.acc_init);
        const from = self.e.from;
        // Trips, the vector part's length, and the element pointer at `start`.
        try self.put("  %vn{d} = sub i64 {s}, {s}\n  %vpos{d} = icmp sgt i64 %vn{d}, 0\n  %vt{d} = select i1 %vpos{d}, i64 %vn{d}, i64 0\n", .{ n, bound, start, n, n, n, n, n });
        try self.put("  %vnv{d} = and i64 %vt{d}, {d}\n  %vend{d} = add i64 {s}, %vnv{d}\n", .{ n, n, -@as(i64, count), n, start, n });
        // Invariant operands, splatted once.
        var splatted: std.ArrayList(ir.Ref) = .empty;
        var operands: std.ArrayList(ir.Ref) = .empty;
        for (p.body) |ref| {
            const inst = self.f.inst(ref);
            if (inst.op == .phi or inst.op == .list_get) continue;
            try operands.appendSlice(self.arena, &.{ inst.a, inst.b });
        }
        for (p.selects) |select| try operands.appendSlice(self.arena, &.{ select.then_value, select.else_value });
        {
            for (operands.items) |raw| {
                if (raw == .none) continue;
                const operand = self.resolveForward(raw);
                if (contains(p.body, operand) or self.f.inst(operand).op == .iconst or contains(splatted.items, operand)) continue;
                try splatted.append(self.arena, operand);
                try self.put("  %vs{d}.{d}.t = trunc i64 {s} to i{d}\n", .{ n, operand.index(), try self.scalar(operand), p.bits });
                try self.put("  %vs{d}.{d}.h = insertelement {s} poison, i{d} %vs{d}.{d}.t, i64 0\n", .{ n, operand.index(), v, p.bits, n, operand.index() });
                try self.put("  %vs{d}.{d} = shufflevector {s} %vs{d}.{d}.h, {s} poison, <{d} x i32> zeroinitializer\n", .{ n, operand.index(), v, n, operand.index(), v, count });
            }
        }
        var lists: std.ArrayList(ir.Ref) = .empty;
        for (p.body) |ref| {
            const inst = self.f.inst(ref);
            if (inst.op != .list_get) continue;
            const list = self.f.resolve(inst.a);
            if (contains(lists.items, list)) continue;
            try lists.append(self.arena, list);
            try self.put("  %vd{d}.{d} = getelementptr inbounds i8, ptr {s}, i64 32\n", .{ n, list.index(), try self.scalar(list) });
            try self.put("  %vp{d}.{d} = getelementptr inbounds {s}, ptr %vd{d}.{d}, i64 {s}\n", .{ n, list.index(), storage(inst.ty), n, list.index(), start });
        }
        try self.put("  %vhas{d} = icmp sgt i64 %vnv{d}, 0\n  br i1 %vhas{d}, label %vblock{d}, label %vexit{d}\n", .{ n, n, n, n, n });
        const summand_range = self.e.known.ranges[p.carried.summand.index()].?;
        const madd = p.bits == 16 and summand_range.hi <= 0x7fff;
        const block_elements = blockElements(summand_range.hi, count, madd);
        try self.put("vblock{d}:\n  %vb{d} = phi i64 [ 0, %{s} ], [ %vlim{d}, %vbend{d} ]\n  %vtot{d} = phi i64 [ {s}, %{s} ], [ %vtot2{d}, %vbend{d} ]\n", .{ n, n, from, n, n, n, acc0, from, n, n });
        try self.put("  %vcap{d} = add nuw i64 %vb{d}, {d}\n  %vover{d} = icmp ult i64 %vcap{d}, %vnv{d}\n", .{ n, n, block_elements, n, n, n });
        try self.put("  %vlim{d} = select i1 %vover{d}, i64 %vcap{d}, i64 %vnv{d}\n  br label %vloop{d}\n", .{ n, n, n, n, n });
        const accumulator = if (madd) "<8 x i32>" else try std.fmt.allocPrint(self.arena, "<{d} x i64>", .{count});
        try self.put("vloop{d}:\n  %vj{d} = phi i64 [ %vb{d}, %vblock{d} ], [ %vj2{d}, %vloop{d} ]\n  %vacc{d} = phi {s} [ zeroinitializer, %vblock{d} ], [ %vacc2{d}, %vloop{d} ]\n", .{ n, n, n, n, n, n, n, accumulator, n, n, n });
        for (p.body) |ref| try self.laneInstruction(ref);
        const reduced = try self.lane(p.carried.summand);
        if (madd) {
            try self.put("  %vpm{d} = call <8 x i32> @llvm.x86.avx2.pmadd.wd({s} {s}, {s} {s})\n  %vacc2{d} = add <8 x i32> %vacc{d}, %vpm{d}\n", .{ n, v, reduced, v, try self.splatConstant(1), n, n, n });
        } else {
            try self.put("  %vwz{d} = zext {s} {s} to {s}\n  %vacc2{d} = add {s} %vacc{d}, %vwz{d}\n", .{ n, v, reduced, accumulator, n, accumulator, n, n });
        }
        try self.put("  %vj2{d} = add nuw nsw i64 %vj{d}, {d}\n  %vmore{d} = icmp ult i64 %vj2{d}, %vlim{d}\n  br i1 %vmore{d}, label %vloop{d}, label %vbend{d}\n", .{ n, n, count, n, n, n, n, n, n });
        if (madd) {
            try self.put("vbend{d}:\n  %vr{d} = call i32 @llvm.vector.reduce.add.v8i32(<8 x i32> %vacc2{d})\n  %vr64{d} = zext i32 %vr{d} to i64\n", .{ n, n, n, n, n });
        } else {
            try self.put("vbend{d}:\n  %vr64{d} = call i64 @llvm.vector.reduce.add.v{d}i64({s} %vacc2{d})\n", .{ n, n, count, accumulator, n });
        }
        try self.put("  %vtot2{d} = add nuw nsw i64 %vtot{d}, %vr64{d}\n  %vbm{d} = icmp ult i64 %vlim{d}, %vnv{d}\n  br i1 %vbm{d}, label %vblock{d}, label %vexit{d}\n", .{ n, n, n, n, n, n, n, n, n });
        try self.put("vexit{d}:\n  %vc{d} = phi i64 [ {s}, %{s} ], [ %vend{d}, %vbend{d} ]\n  %va{d} = phi i64 [ {s}, %{s} ], [ %vtot2{d}, %vbend{d} ]\n", .{ n, n, start, from, n, n, n, acc0, from, n, n });
        return .{
            .label = try std.fmt.allocPrint(self.arena, "vexit{d}", .{n}),
            .counter = try std.fmt.allocPrint(self.arena, "%vc{d}", .{n}),
            .acc = try std.fmt.allocPrint(self.arena, "%va{d}", .{n}),
        };
    }

    fn laneInstruction(self: *Writer, ref: ir.Ref) Error!void {
        const inst = self.f.inst(ref);
        const n = self.e.id;
        const v = try self.vec();
        const name = try std.fmt.allocPrint(self.arena, "%vl{d}.{d}", .{ n, ref.index() });
        switch (inst.op) {
            .phi => for (self.e.plan.selects) |select| {
                if (select.phi != ref) continue;
                try self.put("  {s} = select <{d} x i1> {s}, {s} {s}, {s} {s}\n", .{ name, self.lanes(), try self.lane(select.condition), v, try self.lane(select.then_value), v, try self.lane(select.else_value) });
            },
            .cmp => {
                const predicate: ir.Predicate = @fromBackingInt(@intCast(inst.data));
                // Every lane value is non-negative, so unsigned comparison is the integer one.
                const spelled = switch (predicate) {
                    .eq => "eq",
                    .ne => "ne",
                    .lt => "ult",
                    .le => "ule",
                    .gt => "ugt",
                    .ge => "uge",
                };
                try self.put("  {s} = icmp {s} {s} {s}, {s}\n", .{ name, spelled, v, try self.lane(inst.a), try self.lane(inst.b) });
            },
            .list_get => if (inst.ty == .bool) try self.loadMask(name, self.f.resolve(inst.a)) else try self.load(name, self.f.resolve(inst.a)),
            .add, .sub, .mul => {
                const op = switch (inst.op) {
                    .add => "add",
                    .sub => "sub",
                    else => "mul",
                };
                try self.put("  {s} = {s} {s} {s}, {s}\n", .{ name, op, v, try self.lane(inst.a), try self.lane(inst.b) });
            },
            .floor_div, .floor_rem, .div, .rem => try self.division(name, inst),
            else => unreachable,
        }
    }

    /// Whether the i64 lists load with `packusdw`: every lane must then come from the
    /// same element permutation, so the plan decides once for all its loads.
    fn packedLoads(self: *Writer) bool {
        if (self.e.plan.bits != 16) return false;
        for (self.e.plan.body) |ref| {
            const inst = self.f.inst(ref);
            if (inst.op != .list_get or inst.ty != .i64) continue;
            const elements = self.e.known.lists[self.f.resolve(inst.a).index()].elements orelse return false;
            if (elements.lo < 0 or elements.hi > 0xffff) return false;
        }
        return true;
    }

    /// A `list[bool]` slice as a lane mask: one byte per element, non-zero is true. When
    /// the i64 lists load packed, the bytes are permuted the same way.
    fn loadMask(self: *Writer, name: []const u8, list: ir.Ref) Error!void {
        const n = self.e.id;
        try self.put("  {s}.p = getelementptr inbounds i8, ptr %vp{d}.{d}, i64 %vj{d}\n", .{ name, n, list.index(), n });
        try self.put("  {s}.b = load <{d} x i8>, ptr {s}.p, align 1\n", .{ name, self.lanes(), name });
        var bytes = try std.fmt.allocPrint(self.arena, "{s}.b", .{name});
        if (self.packedLoads()) {
            // Lane k of two packusdw rounds holds element packed_order[k].
            try self.put("  {s}.s = shufflevector <16 x i8> {s}, <16 x i8> poison, <16 x i32> <i32 0, i32 1, i32 4, i32 5, i32 8, i32 9, i32 12, i32 13, i32 2, i32 3, i32 6, i32 7, i32 10, i32 11, i32 14, i32 15>\n", .{ name, bytes });
            bytes = try std.fmt.allocPrint(self.arena, "{s}.s", .{name});
        }
        try self.put("  {s} = icmp ne <{d} x i8> {s}, zeroinitializer\n", .{ name, self.lanes(), bytes });
    }

    fn load(self: *Writer, name: []const u8, list: ir.Ref) Error!void {
        const n = self.e.id;
        const p = self.e.plan;
        const at = try std.fmt.allocPrint(self.arena, "{s}.p", .{name});
        try self.put("  {s} = getelementptr inbounds i64, ptr %vp{d}.{d}, i64 %vj{d}\n", .{ at, n, list.index(), n });
        _ = p;
        if (self.packedLoads()) {
            // Sixteen i64 elements below 2^16: each i64 is (value, 0) as two i32, so two
            // rounds of unsigned saturating packs give the sixteen values as u16 lanes.
            for (0..4) |part| {
                try self.put("  {s}.a{d} = getelementptr inbounds i64, ptr {s}, i64 {d}\n  {s}.w{d} = load <8 x i32>, ptr {s}.a{d}, align 8\n", .{ name, part, at, part * 4, name, part, name, part });
            }
            try self.put("  {s}.x = call <16 x i16> @llvm.x86.avx2.packusdw(<8 x i32> {s}.w0, <8 x i32> {s}.w1)\n", .{ name, name, name });
            try self.put("  {s}.y = call <16 x i16> @llvm.x86.avx2.packusdw(<8 x i32> {s}.w2, <8 x i32> {s}.w3)\n", .{ name, name, name });
            try self.put("  {s}.xi = bitcast <16 x i16> {s}.x to <8 x i32>\n  {s}.yi = bitcast <16 x i16> {s}.y to <8 x i32>\n", .{ name, name, name, name });
            try self.put("  {s} = call <16 x i16> @llvm.x86.avx2.packusdw(<8 x i32> {s}.xi, <8 x i32> {s}.yi)\n", .{ name, name, name });
            return;
        }
        try self.put("  {s}.l = load <{d} x i64>, ptr {s}, align 8\n  {s} = trunc <{d} x i64> {s}.l to {s}\n", .{ name, self.lanes(), at, name, self.lanes(), name, try self.vec() });
    }

    /// `x // c` and `x % c` for a positive constant `c` on non-negative lanes.
    fn division(self: *Writer, name: []const u8, inst: ir.Inst) Error!void {
        const v = try self.vec();
        const divisor = positiveConstant(self.f, inst.b).?;
        const x = try self.lane(inst.a);
        const remainder = inst.op == .floor_rem or inst.op == .rem;
        const quotient = if (remainder) try std.fmt.allocPrint(self.arena, "{s}.q", .{name}) else name;
        const dividend = rangeOf(self.f, self.e.known, inst.a).?;
        const found = if (self.e.plan.bits == 16) reciprocal(divisor, @intCast(dividend.lo), @intCast(dividend.hi)) else null;
        if (found) |r| {
            const multiplier = try self.splatConstant(@intCast(r.multiplier));
            if (r.shift == 0) {
                try self.put("  {s} = call {s} @llvm.x86.avx2.pmulhu.w({s} {s}, {s} {s})\n", .{ quotient, v, v, x, v, multiplier });
            } else {
                try self.put("  {s}.h = call {s} @llvm.x86.avx2.pmulhu.w({s} {s}, {s} {s})\n", .{ quotient, v, v, x, v, multiplier });
                try self.put("  {s} = lshr {s} {s}.h, {s}\n", .{ quotient, v, quotient, try self.splatConstant(r.shift) });
            }
        } else {
            try self.put("  {s} = udiv {s} {s}, {s}\n", .{ quotient, v, x, try self.splatConstant(divisor) });
        }
        if (remainder) try self.put("  {s}.m = mul {s} {s}, {s}\n  {s} = sub {s} {s}, {s}.m\n", .{ name, v, quotient, try self.splatConstant(divisor), name, v, x, name });
    }
};

/// The in-memory element type a list read loads.
fn storage(ty: ir.Type) []const u8 {
    return if (ty == .bool) "i8" else "i64";
}

/// How many elements one block covers: as many vector iterations as keep the
/// eight 32-bit lane accumulators' total below 2^32.
fn blockElements(summand_max: i128, lanes: u32, madd: bool) u64 {
    const unbounded: u64 = 1 << 40;
    if (!madd or summand_max <= 0) return unbounded;
    const per_iteration = @as(u64, @intCast(summand_max)) * 2 * 8;
    const iterations = (@as(u64, 1) << 32) / per_iteration - 1;
    return @min(unbounded, iterations * lanes);
}
