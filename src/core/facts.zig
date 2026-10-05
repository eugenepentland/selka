//! Facts over the Core IR (docs/design/new-core-ir.md §5), release builds only.
//!
//! One pass per function computes, to a fixed point over the reachable CFG:
//! - an integer interval for every value, refined per block by the branch
//!   edges that dominate it (`x < y` on the taken edge of `if x < y`);
//! - which branch edges can execute (a comparison the intervals decide folds);
//! - list facts: a list filled by a counted loop from 0 to `n` with one push
//!   per iteration has length `max(n, 0)` and elements in the hull of the
//!   pushed values, and after it exists `n` is at most `max_list_length`;
//! - reductions: `acc = phi(init, acc + s)` in a counted loop stays within
//!   `init + trips * s`.
//! Then `mark` turns every check the facts rule out into `proven`, folds
//! decided comparisons to constants, and keeps the per-value ranges for the
//! emitter's `!range` metadata. Nothing here assumes more than the two
//! constants below, which are the stated assumptions of the S0 design.
const std = @import("std");
const ir = @import("ir.zig");

/// A list holds at most this many elements: elements of at least one byte in the
/// target's user address space (2^47 on x86-64 Linux, L4; see `target.zig`).
pub const max_list_length: i128 = @import("target.zig").current.maxListLength();

/// A closed integer interval, exact in `i128`.
pub const Interval = struct {
    lo: i128,
    hi: i128,

    /// The interval holding exactly `value`.
    pub fn point(value: i128) Interval {
        return .{ .lo = value, .hi = value };
    }
    /// The smallest interval holding both.
    pub fn hull(a: Interval, b: Interval) Interval {
        return .{ .lo = @min(a.lo, b.lo), .hi = @max(a.hi, b.hi) };
    }
    /// The values both hold (may be empty: `lo > hi`).
    pub fn meet(a: Interval, b: Interval) Interval {
        return .{ .lo = @max(a.lo, b.lo), .hi = @min(a.hi, b.hi) };
    }
    /// Whether every value of `self` lies in `other`.
    pub fn within(self: Interval, other: Interval) bool {
        return self.lo >= other.lo and self.hi <= other.hi;
    }
};

/// A closed interval of finite doubles; a value that may be NaN or infinite has none.
pub const FloatInterval = struct {
    lo: f64,
    hi: f64,

    fn finite(lo: f64, hi: f64) ?FloatInterval {
        if (!std.math.isFinite(lo) or !std.math.isFinite(hi)) return null;
        return .{ .lo = lo, .hi = hi };
    }
    /// One ulp of outward rounding per operation keeps every IEEE result inside.
    fn outward(lo: f64, hi: f64) ?FloatInterval {
        return finite(std.math.nextAfter(f64, lo, -std.math.inf(f64)), std.math.nextAfter(f64, hi, std.math.inf(f64)));
    }
    fn hull(a: FloatInterval, b: FloatInterval) FloatInterval {
        return .{ .lo = @min(a.lo, b.lo), .hi = @max(a.hi, b.hi) };
    }
};

/// The float interval of `float(i)` for an integer interval (exact up to 2^53).
fn fromInt(range: Interval) ?FloatInterval {
    const lo: f64 = @floatFromInt(range.lo);
    const hi: f64 = @floatFromInt(range.hi);
    const exact = @max(@abs(range.lo), @abs(range.hi)) <= (1 << 53);
    return if (exact) FloatInterval.finite(lo, hi) else FloatInterval.outward(lo, hi);
}

/// The integer interval of `int(f)` (truncation), when no member leaves `i64`.
fn toInt(range: FloatInterval) ?Interval {
    if (!(range.lo > -9223372036854775808.0) or !(range.hi < 9223372036854775808.0)) return null;
    return .{ .lo = @intFromFloat(@trunc(range.lo)), .hi = @intFromFloat(@trunc(range.hi)) };
}

fn floatArithmetic(op: ir.Op, x: FloatInterval, y: FloatInterval) ?FloatInterval {
    return switch (op) {
        .fadd => FloatInterval.outward(x.lo + y.lo, x.hi + y.hi),
        .fsub => FloatInterval.outward(x.lo - y.hi, x.hi - y.lo),
        .fmul => blk: {
            const p = [4]f64{ x.lo * y.lo, x.lo * y.hi, x.hi * y.lo, x.hi * y.hi };
            break :blk FloatInterval.outward(@min(@min(p[0], p[1]), @min(p[2], p[3])), @max(@max(p[0], p[1]), @max(p[2], p[3])));
        },
        .fdiv => blk: {
            if (y.lo <= 0 and y.hi >= 0) break :blk null;
            const q = [4]f64{ x.lo / y.lo, x.lo / y.hi, x.hi / y.lo, x.hi / y.hi };
            break :blk FloatInterval.outward(@min(@min(q[0], q[1]), @min(q[2], q[3])), @max(@max(q[0], q[1]), @max(q[2], q[3])));
        },
        else => null,
    };
}

/// Every value a type can hold, or null for a non-integer type.
pub fn typeRange(ty: ir.Type) ?Interval {
    if (ty == .bool) return .{ .lo = 0, .hi = 1 };
    const info = ty.integer() orelse return null;
    if (info.signed) return .{ .lo = -(@as(i128, 1) << @intCast(info.bits - 1)), .hi = (@as(i128, 1) << @intCast(info.bits - 1)) - 1 };
    return .{ .lo = 0, .hi = (@as(i128, 1) << @intCast(info.bits)) - 1 };
}

/// What a list value is known to hold.
pub const ListFact = struct {
    /// The list's length is `max(length, 0)` for this value.
    length: ir.Ref = .none,
    elements: ?Interval = null,
};

/// `value <= len(list)` (`<` when `strict`) for a list parameter. A parameter is one
/// list for the whole call and lists are immutable values, so the relation holds
/// wherever the value does, in every iteration of every loop.
pub const LengthBound = struct {
    /// The list parameter, or `.none` when no bound is known.
    list: ir.Ref = .none,
    strict: bool = false,

    /// What both bounds guarantee.
    pub fn meet(x: LengthBound, y: LengthBound) LengthBound {
        if (x.list != y.list or x.list == .none) return .{};
        return .{ .list = x.list, .strict = x.strict and y.strict };
    }
    /// The more informative of two bounds that both hold.
    fn best(x: LengthBound, y: LengthBound) LengthBound {
        if (y.list == .none) return x;
        if (x.list == .none or (y.strict and !x.strict)) return y;
        return x;
    }
};

/// The facts of one function.
pub const Facts = struct {
    /// Per instruction: its interval (integers and booleans), null when unknown or unreachable.
    ranges: []?Interval,
    lists: []ListFact,
    /// Per instruction: the interval of a float value, null when unknown (it may be NaN or infinite).
    floats: []?FloatInterval,
    /// Per block: whether any execution reaches it.
    reachable: []bool,
    /// How many checks `mark` proved, for reports and tests.
    proven: u32 = 0,
    /// The counted loops found (for the vector lowering).
    counted: []const Counted = &.{},
    /// Per instruction: the list parameter whose length bounds the value; null when
    /// none was computed (unreachable, or only constants at most 0 flow in).
    bounds: []?LengthBound = &.{},
};

/// Dominators, reverse postorder and the block of every instruction.
const Shape = struct {
    rpo: []ir.BlockId,
    idom: []?ir.BlockId,
    block_of: []?ir.BlockId,
    /// Position of each block in `rpo` (unreachable from the entry: maxInt).
    order: []u32,
};

fn shape(arena: std.mem.Allocator, f: *const ir.Function) !Shape {
    const count = f.blocks.items.len;
    const block_of = try arena.alloc(?ir.BlockId, f.insts.items.len);
    @memset(block_of, null);
    for (f.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
        block_of[ref.index()] = @fromBackingInt(@intCast(b));
    };
    // Reverse postorder from the entry by an explicit DFS.
    const visited = try arena.alloc(bool, count);
    @memset(visited, false);
    var post: std.ArrayList(ir.BlockId) = .empty;
    var stack: std.ArrayList(struct { block: ir.BlockId, next: u8 }) = .empty;
    try stack.append(arena, .{ .block = @fromBackingInt(@intCast(0)), .next = 0 });
    visited[0] = true;
    while (stack.items.len != 0) {
        const top = &stack.items[stack.items.len - 1];
        const successors = successorsOf(f, top.block);
        if (top.next < successors.len) {
            const next = successors.buffer[top.next];
            top.next += 1;
            if (!visited[next.index()]) {
                visited[next.index()] = true;
                try stack.append(arena, .{ .block = next, .next = 0 });
            }
        } else {
            try post.append(arena, top.block);
            _ = stack.pop();
        }
    }
    std.mem.reverse(ir.BlockId, post.items);
    const order = try arena.alloc(u32, count);
    @memset(order, std.math.maxInt(u32));
    for (post.items, 0..) |block, i| order[block.index()] = @intCast(i);
    // Cooper, Harvey and Kennedy's iterative dominators.
    const idom = try arena.alloc(?ir.BlockId, count);
    @memset(idom, null);
    idom[0] = @fromBackingInt(@intCast(0));
    var changed = true;
    while (changed) {
        changed = false;
        for (post.items[1..]) |block| {
            var chosen: ?ir.BlockId = null;
            for (f.blocks.items[block.index()].preds.items) |pred| {
                if (idom[pred.index()] == null) continue;
                chosen = if (chosen) |other| intersect(idom, order, pred, other) else pred;
            }
            if (chosen != null and idom[block.index()] != chosen) {
                idom[block.index()] = chosen;
                changed = true;
            }
        }
    }
    return .{ .rpo = post.items, .idom = idom, .block_of = block_of, .order = order };
}

fn intersect(idom: []?ir.BlockId, order: []u32, a: ir.BlockId, b: ir.BlockId) ir.BlockId {
    var x = a;
    var y = b;
    while (x != y) {
        while (order[x.index()] > order[y.index()]) x = idom[x.index()].?;
        while (order[y.index()] > order[x.index()]) y = idom[y.index()].?;
    }
    return x;
}

/// At most two successor blocks.
const Successors = struct {
    buffer: [2]ir.BlockId = undefined,
    len: u8 = 0,
};

fn successorsOf(f: *const ir.Function, block: ir.BlockId) Successors {
    var out: Successors = .{};
    const insts = f.blocks.items[block.index()].insts.items;
    if (insts.len == 0) return out;
    const last = f.inst(insts[insts.len - 1]);
    switch (last.op) {
        .jump => {
            out.buffer[0] = @fromBackingInt(@intCast(@as(u32, @intCast(last.data))));
            out.len = 1;
        },
        .branch => {
            const targets = ir.unpackTargets(last.data);
            out.buffer = .{ targets.then, targets.otherwise };
            out.len = 2;
        },
        else => {},
    }
    return out;
}

/// A counted loop: `counter = phi(start, counter + 1)` in the header, `counter < bound` its condition.
pub const Counted = struct { loop: ir.Loop, counter: ir.Ref, start: ir.Ref, bound: ir.Ref };

const Analysis = struct {
    arena: std.mem.Allocator,
    f: *ir.Function,
    shape: Shape,
    facts: Facts,
    counted: std.ArrayList(Counted) = .empty,
    /// Numeric upper bounds that hold in every block a given block dominates: (block, value, hi).
    caps: std.ArrayList(struct { block: ir.BlockId, value: ir.Ref, hi: i128 }) = .empty,
    sabotage: Sabotage = .none,

    fn inst(self: *Analysis, ref: ir.Ref) ir.Inst {
        return self.f.inst(self.f.resolve(ref));
    }

    fn base(self: *Analysis, raw: ir.Ref) ?Interval {
        const ref = self.f.resolve(raw);
        const i = self.f.inst(ref);
        return switch (i.op) {
            .iconst => if (typeRange(i.ty) != null) Interval.point(constantValue(i)) else null,
            .param, .undef, .call, .union_payload => typeRange(i.ty),
            else => self.facts.ranges[ref.index()],
        };
    }

    fn dominates(self: *Analysis, a: ir.BlockId, b: ir.BlockId) bool {
        var x: ?ir.BlockId = b;
        while (x) |current| {
            if (current == a) return true;
            if (current.index() == 0) return false;
            x = self.shape.idom[current.index()];
        }
        return false;
    }

    /// The edge into `block` when it has one predecessor ending in a branch on a comparison.
    fn edgeCondition(self: *Analysis, block: ir.BlockId) ?struct { cmp: ir.Inst, taken: bool } {
        const preds = self.f.blocks.items[block.index()].preds.items;
        if (preds.len != 1) return null;
        const insts = self.f.blocks.items[preds[0].index()].insts.items;
        const last = self.f.inst(insts[insts.len - 1]);
        if (last.op != .branch) return null;
        const targets = ir.unpackTargets(last.data);
        if (targets.then == targets.otherwise) return null;
        const condition = self.inst(last.a);
        if (condition.op != .cmp) return null;
        return .{ .cmp = condition, .taken = targets.then == block };
    }

    /// `ref`'s interval where `block` executes: its own interval narrowed by
    /// every dominating branch edge and every list-length cap that covers `block`.
    fn rangeAt(self: *Analysis, raw: ir.Ref, block: ir.BlockId) ?Interval {
        const ref = self.f.resolve(raw);
        var range = self.base(ref) orelse return null;
        for (self.caps.items) |cap| {
            if (cap.value == ref and self.dominates(cap.block, block)) range.hi = @min(range.hi, cap.hi);
        }
        var x: ?ir.BlockId = block;
        while (x) |current| {
            if (self.edgeCondition(current)) |edge| range = refine(self, range, ref, edge.cmp, edge.taken);
            if (current.index() == 0) break;
            x = self.shape.idom[current.index()];
        }
        return range;
    }

    /// Whether `x < y` holds wherever `block` executes, by a dominating branch edge.
    fn knownLess(self: *Analysis, x: ir.Ref, y: ir.Ref, block: ir.BlockId) bool {
        var b: ?ir.BlockId = block;
        while (b) |current| {
            if (self.edgeCondition(current)) |edge| {
                const left = self.f.resolve(edge.cmp.a);
                const right = self.f.resolve(edge.cmp.b);
                const predicate: ir.Predicate = @fromBackingInt(@intCast(edge.cmp.data));
                const same = left == x and right == y;
                const holds = if (edge.taken) predicate == .lt else predicate == .ge;
                if (same and holds) return true;
            }
            if (current.index() == 0) break;
            b = self.shape.idom[current.index()];
        }
        return false;
    }

    /// The single executable operand of a phi, if the others come from dead edges.
    fn liveOperand(self: *Analysis, ref: ir.Ref) ir.Ref {
        const resolved = self.f.resolve(ref);
        const i = self.f.inst(resolved);
        if (i.op != .phi) return resolved;
        const block = self.shape.block_of[resolved.index()] orelse return resolved;
        var only: ir.Ref = .none;
        for (self.f.operands(i.data), self.f.blocks.items[block.index()].preds.items) |operand, pred| {
            if (!self.edgeLive(pred, block)) continue;
            const value = self.f.resolve(operand);
            if (only != .none and only != value) return resolved;
            only = value;
        }
        return if (only == .none) resolved else only;
    }

    fn edgeLive(self: *Analysis, from: ir.BlockId, to: ir.BlockId) bool {
        if (!self.facts.reachable[from.index()]) return false;
        const insts = self.f.blocks.items[from.index()].insts.items;
        const last = self.f.inst(insts[insts.len - 1]);
        if (last.op != .branch) return true;
        const condition = self.base(last.a) orelse return true;
        const targets = ir.unpackTargets(last.data);
        if (condition.lo == 1 and condition.hi == 1) return targets.then == to;
        if (condition.lo == 0 and condition.hi == 0) return targets.otherwise == to;
        return true;
    }
};

fn constantValue(i: ir.Inst) i128 {
    if (i.ty == .bool) return @intFromBool(i.data != 0);
    const info = i.ty.integer().?;
    if (!info.signed and info.bits == 64) return i.data;
    return @as(i64, @bitCast(i.data));
}

fn refine(self: *Analysis, range: Interval, ref: ir.Ref, cmp: ir.Inst, taken: bool) Interval {
    const left = self.f.resolve(cmp.a);
    const right = self.f.resolve(cmp.b);
    if (left != ref and right != ref) return range;
    var predicate: ir.Predicate = @fromBackingInt(@intCast(cmp.data));
    if (!taken) predicate = switch (predicate) {
        .eq => .ne,
        .ne => .eq,
        .lt => .ge,
        .le => .gt,
        .gt => .le,
        .ge => .lt,
    };
    // Put `ref` on the left: `other < ref` is `ref > other`.
    const other = if (left == ref) right else left;
    if (left != ref) predicate = switch (predicate) {
        .lt => .gt,
        .le => .ge,
        .gt => .lt,
        .ge => .le,
        else => predicate,
    };
    const bound = self.base(other) orelse return range;
    var out = range;
    switch (predicate) {
        .lt => out.hi = @min(out.hi, bound.hi - 1),
        .le => out.hi = @min(out.hi, bound.hi),
        .gt => out.lo = @max(out.lo, bound.lo + 1),
        .ge => out.lo = @max(out.lo, bound.lo),
        .eq => out = out.meet(bound),
        .ne => {},
    }
    return out;
}

/// The fact pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// How the pass runs.
pub const Options = struct {
    /// Fold decided comparisons to constants. Verify builds keep them, so a block the
    /// facts call unreachable still exists and can assert that it never runs.
    fold: bool = true,
    /// Deliberately wrong rule for testing the verify mode and the fuzz.
    sabotage: Sabotage = .none,
};

/// The deliberately wrong rules (`--sabotage-facts`, `--sabotage-facts=widening`, `=length`).
pub const Sabotage = enum {
    none,
    /// `x % c` is taken to lie in `[0, c - 2]` instead of `[0, c - 1]`.
    remainder,
    /// Widening rounds a growing bound to the threshold on the wrong side (down for
    /// an upper bound, up for a lower one), so the widened interval may miss values.
    widening,
    /// `len(xs)` of a list parameter is taken to be strictly below `len(xs)`.
    length,
};

/// The bounds a widened interval may stop at before its type's own: 0, the
/// list-length bound 2^47 (NEW-CORE-FACTS-3) and 2^47 + 1. Indices and lengths
/// computed from list lengths settle there (`low = middle + 1` with `middle < len`).
pub const thresholds = [_]i128{ 0, max_list_length, max_list_length + 1 };

/// Threshold widening: each bound of `next` that leaves `old` moves out to the
/// nearest threshold that still holds it, or to the type's limit; a bound that
/// stays inside `old` keeps `old`'s. The result holds `old` and `next`, and every
/// bound it changes lands on one of finitely many values, so iteration stops.
pub fn widen(old: Interval, next: Interval, limits: Interval, sabotage: Sabotage) Interval {
    var out = old;
    if (next.lo < old.lo) out.lo = if (sabotage == .widening) thresholdAbove(next.lo, limits) else thresholdBelow(next.lo, limits);
    if (next.hi > old.hi) out.hi = if (sabotage == .widening) thresholdBelow(next.hi, limits) else thresholdAbove(next.hi, limits);
    return out;
}

/// The largest threshold at or below `value`, else the type's lower limit.
fn thresholdBelow(value: i128, limits: Interval) i128 {
    var out = limits.lo;
    for (thresholds) |t| {
        if (t <= value and t > out and t <= limits.hi) out = t;
    }
    return out;
}

/// The smallest threshold at or above `value`, else the type's upper limit.
fn thresholdAbove(value: i128, limits: Interval) i128 {
    var out = limits.hi;
    for (thresholds) |t| {
        if (t >= value and t < out and t >= limits.lo) out = t;
    }
    return out;
}

/// Recompute one instruction's interval (and float interval), widening a phi
/// that keeps changing to the next threshold (`widen`); returns whether anything changed.
/// Every cycle of SSA values passes through a phi, so widening phis alone ends the
/// iteration, and a value computed from them (`low + high`) keeps its exact transfer.
fn recompute(a: *Analysis, ref: ir.Ref, block: ir.BlockId, changes: []u8) bool {
    const f = a.f;
    var changed = false;
    // No value leaves its type, so neither does its interval (and i128 arithmetic stays exact).
    const limits = typeRange(f.inst(ref).ty);
    const next = if (transfer(a, ref, block)) |range| (if (limits) |l| range.meet(l) else range) else null;
    const old = a.facts.ranges[ref.index()];
    const moved = old != null and next != null and !std.meta.eql(old, next);
    const widened = if (moved and f.inst(ref).op == .phi) blk: {
        changes[ref.index()] +|= 1;
        if (changes[ref.index()] <= 8) break :blk next;
        const l = limits orelse break :blk null;
        break :blk widen(old.?, next.?, l, a.sabotage);
    } else next;
    if (!std.meta.eql(old, widened)) {
        a.facts.ranges[ref.index()] = widened;
        changed = true;
    }
    if (f.inst(ref).ty.integer() != null) {
        // A bound only weakens (pending, strict, non-strict, none), so this part terminates too.
        const old_bound = a.facts.bounds[ref.index()];
        const next_bound = lengthBound(a, ref, block);
        const merged = if (old_bound) |o| (if (next_bound) |n| o.meet(n) else o) else next_bound;
        if (!std.meta.eql(old_bound, merged)) {
            a.facts.bounds[ref.index()] = merged;
            changed = true;
        }
    }
    if (f.inst(ref).ty != .f64) return changed;
    const old_float = a.facts.floats[ref.index()];
    var next_float = transferFloat(a, ref, block);
    if (old_float != null and next_float != null and !std.meta.eql(old_float, next_float)) {
        changes[ref.index()] +|= 1;
        if (changes[ref.index()] > 8) next_float = null;
    }
    if (!std.meta.eql(old_float, next_float)) {
        a.facts.floats[ref.index()] = next_float;
        changed = true;
    }
    return changed;
}

/// Compute the facts of `f` and mark every check they rule out as `proven`.
pub fn analyze(arena: std.mem.Allocator, f: *ir.Function, options: Options) Error!Facts {
    var a: Analysis = .{
        .arena = arena,
        .sabotage = options.sabotage,
        .f = f,
        .shape = try shape(arena, f),
        .facts = .{
            .ranges = try arena.alloc(?Interval, f.insts.items.len),
            .lists = try arena.alloc(ListFact, f.insts.items.len),
            .floats = try arena.alloc(?FloatInterval, f.insts.items.len),
            .reachable = try arena.alloc(bool, f.blocks.items.len),
            .bounds = try arena.alloc(?LengthBound, f.insts.items.len),
        },
    };
    @memset(a.facts.bounds, null);
    @memset(a.facts.ranges, null);
    @memset(a.facts.floats, null);
    @memset(a.facts.lists, .{});
    try findCounted(&a);
    const changes = try arena.alloc(u8, f.insts.items.len);
    @memset(changes, 0);
    var round: usize = 0;
    var converged = false;
    // Reachability only grows (as in sparse conditional constant propagation):
    // an edge found executable stays so, which keeps the iteration monotone.
    @memset(a.facts.reachable, false);
    a.facts.reachable[0] = true;
    while (round < 64) : (round += 1) {
        var changed = false;
        for (a.shape.rpo) |block| {
            if (!a.facts.reachable[block.index()]) {
                for (f.blocks.items[block.index()].preds.items) |pred| {
                    if (a.edgeLive(pred, block)) a.facts.reachable[block.index()] = true;
                }
                if (a.facts.reachable[block.index()]) changed = true;
            }
            if (!a.facts.reachable[block.index()]) continue;
            for (f.blocks.items[block.index()].insts.items) |ref| {
                if (recompute(&a, ref, block, changes)) changed = true;
            }
        }
        if (try listFacts(&a)) changed = true;
        if (!changed) {
            converged = true;
            break;
        }
    }
    // Ranges short of a fixed point are not facts: prove nothing, and leave the
    // emitter no interval to turn into `!range`, `nuw` or a narrowed conversion.
    if (converged) mark(&a, options.fold) else {
        @memset(a.facts.ranges, null);
        @memset(a.facts.floats, null);
        @memset(a.facts.lists, .{});
        @memset(a.facts.bounds, null);
    }
    a.facts.counted = if (converged) a.counted.items else &.{};
    return a.facts;
}

/// Recognize counted loops from the builder's loop records.
fn findCounted(a: *Analysis) !void {
    for (a.f.loops.items) |loop| {
        const header = a.f.blocks.items[loop.header.index()];
        if (header.preds.items.len != 2) continue;
        const last = a.f.inst(header.insts.items[header.insts.items.len - 1]);
        if (last.op != .branch or ir.unpackTargets(last.data).then != loop.body) continue;
        const condition = a.inst(last.a);
        if (condition.op != .cmp or @as(ir.Predicate, @fromBackingInt(@intCast(condition.data))) != .lt) continue;
        const counter = a.f.resolve(condition.a);
        const phi = a.f.inst(counter);
        if (phi.op != .phi or a.shape.block_of[counter.index()] != loop.header) continue;
        const operands = a.f.operands(phi.data);
        const latch_index: usize = if (header.preds.items[0] == loop.latch) 0 else 1;
        if (header.preds.items[latch_index] != loop.latch) continue;
        const step = a.inst(operands[latch_index]);
        if (step.op != .add or a.f.resolve(step.a) != counter) continue;
        const one = a.inst(step.b);
        if (one.op != .iconst or one.data != 1) continue;
        try a.counted.append(a.arena, .{ .loop = loop, .counter = counter, .start = a.f.resolve(operands[1 - latch_index]), .bound = a.f.resolve(condition.b) });
    }
}

/// Whether every iteration of `loop` runs `target` exactly once: from the body,
/// each block has one live way on (a jump, or a branch the facts decided), the
/// chain reaches the latch, and nothing else enters the chain.
fn onStraightChain(a: *Analysis, loop: ir.Loop, target: ir.BlockId) bool {
    var block = loop.body;
    var found = false;
    var steps: usize = 0;
    while (steps <= a.f.blocks.items.len) : (steps += 1) {
        if (block == target) found = true;
        if (block == loop.latch) return found;
        const insts = a.f.blocks.items[block.index()].insts.items;
        const last = a.f.inst(insts[insts.len - 1]);
        var following: ?ir.BlockId = null;
        switch (last.op) {
            .jump => following = @fromBackingInt(@as(u32, @intCast(last.data))),
            .branch => {
                const targets = ir.unpackTargets(last.data);
                const then_live = a.edgeLive(block, targets.then);
                const else_live = a.edgeLive(block, targets.otherwise);
                if (then_live == else_live) return false;
                following = if (then_live) targets.then else targets.otherwise;
            },
            else => return false,
        }
        const next_block = following.?;
        for (a.f.blocks.items[next_block.index()].preds.items) |pred| {
            if (pred != block and a.edgeLive(pred, next_block)) return false;
        }
        block = next_block;
    }
    return false;
}

/// The trip-count bound of the counted loop whose header is `header`, if any.
fn tripBound(a: *Analysis, header: ir.BlockId) ?i128 {
    for (a.counted.items) |counted| {
        if (counted.loop.header != header) continue;
        const bound = a.rangeAt(counted.bound, header) orelse return null;
        const start = a.base(counted.start) orelse return null;
        return @max(bound.hi - start.lo, 0);
    }
    return null;
}

/// List lengths and element hulls from counted fill loops; returns whether anything changed.
fn listFacts(a: *Analysis) !bool {
    var changed = false;
    for (a.counted.items) |counted| {
        const header = a.f.blocks.items[counted.loop.header.index()];
        const latch_index: usize = if (header.preds.items[0] == counted.loop.latch) 0 else 1;
        const start = a.inst(counted.start);
        if (start.op != .iconst or start.data != 0) continue;
        for (header.insts.items) |ref| {
            const phi = a.f.inst(ref);
            if (phi.op != .phi or !phi.ty.isCompound()) continue;
            const operands = a.f.operands(phi.data);
            const entry = a.inst(operands[1 - latch_index]);
            const pushed_ref = a.f.resolve(operands[latch_index]);
            const pushed = a.f.inst(pushed_ref);
            if (entry.op != .list_new or pushed.op != .list_push or a.f.resolve(pushed.a) != ref) continue;
            // Exactly one push per iteration: the body runs as one straight chain of
            // blocks (branches the facts decided count as jumps) and the push is on it.
            const push_block = a.shape.block_of[pushed_ref.index()] orelse continue;
            if (!onStraightChain(a, counted.loop, push_block)) continue;
            const elements = a.rangeAt(pushed.b, push_block);
            const fact: ListFact = .{ .length = counted.bound, .elements = elements };
            if (!std.meta.eql(a.facts.lists[ref.index()], fact)) {
                a.facts.lists[ref.index()] = fact;
                changed = true;
            }
            var capped = false;
            for (a.caps.items) |cap| capped = capped or (cap.value == counted.bound and cap.block == counted.loop.exit);
            if (!capped) {
                try a.caps.append(a.arena, .{ .block = counted.loop.exit, .value = counted.bound, .hi = max_list_length });
                changed = true;
            }
        }
    }
    return changed;
}

fn transfer(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?Interval {
    const i = a.f.inst(ref);
    const full = typeRange(i.ty);
    return switch (i.op) {
        .phi => phiRange(a, ref, block),
        .add, .sub, .mul => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const y = a.rangeAt(i.b, block) orelse break :blk full;
            const exact = arithmetic(i.op, x, y);
            const limits = full orelse break :blk null;
            if (exact.within(limits)) break :blk exact;
            // A checked operation traps instead of leaving its type; a wrapping one can be anything.
            break :blk if (i.check == .none) limits else exact.meet(limits);
        },
        .floor_div, .div => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const d = a.rangeAt(i.b, block) orelse break :blk full;
            if (d.lo <= 0 or x.lo < 0) break :blk full;
            break :blk .{ .lo = @divFloor(x.lo, d.hi), .hi = @divFloor(x.hi, d.lo) };
        },
        .floor_rem => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const d = a.rangeAt(i.b, block) orelse break :blk full;
            if (d.lo <= 0) break :blk full;
            if (x.lo >= 0 and x.hi < d.lo) break :blk x;
            break :blk .{ .lo = 0, .hi = d.hi - if (a.sabotage == .remainder) @as(i128, 2) else 1 };
        },
        .rem => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const d = a.rangeAt(i.b, block) orelse break :blk full;
            if (d.lo <= 0 or x.lo < 0) break :blk full;
            break :blk .{ .lo = 0, .hi = @min(x.hi, d.hi - 1) };
        },
        .convert => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            break :blk x.meet(full.?);
        },
        .list_len, .str_len => .{ .lo = 0, .hi = max_list_length },
        .float_to_int => blk: {
            const converted = toInt(floatOf(a, i.a) orelse break :blk full) orelse break :blk full;
            break :blk converted.meet(full.?);
        },
        .list_get => blk: {
            const list = a.liveOperand(i.a);
            break :blk a.facts.lists[list.index()].elements orelse full;
        },
        .cmp => compare(a, i, block),
        .not => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            break :blk .{ .lo = 1 - x.hi, .hi = 1 - x.lo };
        },
        .iconst => if (full != null) Interval.point(constantValue(i)) else null,
        else => full,
    };
}

fn floatOf(a: *Analysis, raw: ir.Ref) ?FloatInterval {
    const ref = a.f.resolve(raw);
    const i = a.f.inst(ref);
    if (i.op == .fconst) {
        const value: f64 = @bitCast(i.data);
        return FloatInterval.finite(value, value);
    }
    return a.facts.floats[ref.index()];
}

fn transferFloat(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?FloatInterval {
    const i = a.f.inst(ref);
    return switch (i.op) {
        .fadd, .fsub, .fmul, .fdiv => floatArithmetic(i.op, floatOf(a, i.a) orelse return null, floatOf(a, i.b) orelse return null),
        .fneg => blk: {
            const x = floatOf(a, i.a) orelse break :blk null;
            break :blk .{ .lo = -x.hi, .hi = -x.lo };
        },
        .int_to_float => fromInt(a.rangeAt(i.a, block) orelse return null),
        .phi => blk: {
            var out: ?FloatInterval = null;
            for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
                if (!a.edgeLive(pred, block)) continue;
                const range = floatOf(a, operand) orelse break :blk null;
                out = if (out) |so_far| so_far.hull(range) else range;
            }
            break :blk out;
        },
        else => null,
    };
}

fn arithmetic(op: ir.Op, x: Interval, y: Interval) Interval {
    return switch (op) {
        .add => .{ .lo = x.lo + y.lo, .hi = x.hi + y.hi },
        .sub => .{ .lo = x.lo - y.hi, .hi = x.hi - y.lo },
        else => blk: {
            const p = [4]i128{ mulSat(x.lo, y.lo), mulSat(x.lo, y.hi), mulSat(x.hi, y.lo), mulSat(x.hi, y.hi) };
            break :blk .{ .lo = @min(@min(p[0], p[1]), @min(p[2], p[3])), .hi = @max(@max(p[0], p[1]), @max(p[2], p[3])) };
        },
    };
}

fn mulSat(x: i128, y: i128) i128 {
    return std.math.mul(i128, x, y) catch if ((x < 0) == (y < 0)) std.math.maxInt(i128) else std.math.minInt(i128);
}

fn phiRange(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?Interval {
    const i = a.f.inst(ref);
    _ = typeRange(i.ty) orelse return null;
    if (counterRange(a, ref, block)) |bounded| return bounded;
    if (reduction(a, ref, block)) |bounded| return bounded;
    var out: ?Interval = null;
    for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
        if (!a.edgeLive(pred, block)) continue;
        const range = a.rangeAt(operand, pred) orelse continue;
        out = if (out) |so_far| so_far.hull(range) else range;
    }
    return out;
}

/// A counted loop's counter steps by one from `start` while below `bound`, so in
/// the header it lies in `[lo(start), max(hi(start), hi(bound))]`.
fn counterRange(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?Interval {
    for (a.counted.items) |counted| {
        if (counted.loop.header != block or counted.counter != ref) continue;
        const start = a.base(counted.start) orelse return null;
        const bound = a.rangeAt(counted.bound, block) orelse return null;
        return .{ .lo = start.lo, .hi = @max(start.hi, bound.hi) };
    }
    return null;
}

/// `acc = phi(init, acc + s)` in a counted loop: `init + trips * s`, when `s` is non-negative.
fn reduction(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?Interval {
    for (a.counted.items) |counted| {
        if (counted.loop.header != block or counted.counter == ref) continue;
        const header = a.f.blocks.items[block.index()];
        const latch_index: usize = if (header.preds.items[0] == counted.loop.latch) 0 else 1;
        const operands = a.f.operands(a.f.inst(ref).data);
        const update = a.inst(operands[latch_index]);
        if (update.op != .add) return null;
        const step = if (a.f.resolve(update.a) == ref) update.b else if (a.f.resolve(update.b) == ref) update.a else return null;
        const where = a.shape.block_of[a.f.resolve(operands[latch_index]).index()] orelse return null;
        const s = a.rangeAt(step, where) orelse return null;
        const start = a.rangeAt(operands[1 - latch_index], header.preds.items[1 - latch_index]) orelse return null;
        const trips = tripBound(a, block) orelse return null;
        if (s.lo < 0) return null;
        return .{ .lo = start.lo, .hi = start.hi +| mulSat(trips, s.hi) };
    }
    return null;
}

/// The bound a value is known to have where it is used: constants, parameters and
/// values not analysed yet have none.
fn knownBound(a: *Analysis, raw: ir.Ref) LengthBound {
    const ref = a.f.resolve(raw);
    return switch (a.f.inst(ref).op) {
        .iconst, .param, .undef => .{},
        else => a.facts.bounds[ref.index()] orelse .{},
    };
}

/// The bound `x` has where `block` executes because a dominating branch edge says
/// `x < y` (strict, through `y`'s bound) or `x <= y` (`y`'s bound as it is).
fn lessBound(a: *Analysis, x: ir.Ref, block: ir.BlockId) LengthBound {
    var out: LengthBound = .{};
    var b: ?ir.BlockId = block;
    while (b) |current| {
        if (a.edgeCondition(current)) |edge| {
            var predicate: ir.Predicate = @fromBackingInt(@intCast(edge.cmp.data));
            if (!edge.taken) predicate = switch (predicate) {
                .lt => .ge,
                .le => .gt,
                .gt => .le,
                .ge => .lt,
                else => predicate,
            };
            const left = a.f.resolve(edge.cmp.a);
            const right = a.f.resolve(edge.cmp.b);
            // `x < y` or `y > x` (strict); `x <= y` or `y >= x` (as `y`'s bound).
            const other: ?ir.Ref = if (left == x and (predicate == .lt or predicate == .le)) right else if (right == x and (predicate == .gt or predicate == .ge)) left else null;
            if (other) |y| {
                const strict = predicate == .lt or predicate == .gt;
                const through = knownBound(a, y);
                if (through.list != .none) out = out.best(.{ .list = through.list, .strict = through.strict or strict });
            }
        }
        if (current.index() == 0) break;
        b = a.shape.idom[current.index()];
    }
    return out;
}

/// One step of the length-bound analysis: `len(xs)` of a list parameter, value-preserving
/// conversions, `x + c` (`c <= 0`), `x + 1` under `x < y`, `x // d` of a non-negative `x`,
/// the midpoint `(x + y) // 2` under `x < y` (strictly below `y`), and phis (every live
/// operand bounded by the same list; operands not analysed yet are assumed, as in SCCP).
fn lengthBound(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?LengthBound {
    const i = a.f.inst(ref);
    switch (i.op) {
        .phi => {
            var out: ?LengthBound = null;
            var zero = false;
            for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
                if (!a.edgeLive(pred, block)) continue;
                const value = a.f.resolve(operand);
                const op = a.f.inst(value);
                if (op.op == .iconst) {
                    if (constantValue(op) > 0) return .{};
                    zero = true;
                    continue;
                }
                if (op.op == .param or op.op == .undef) return .{};
                // Not analysed yet (a back edge in the first round): assumed, and checked when it is.
                const known = a.facts.bounds[value.index()] orelse continue;
                out = if (out) |so_far| so_far.meet(known) else known;
            }
            // A constant at most 0 is at most every length, but not below an empty list's.
            if (zero) return if (out) |so_far| .{ .list = so_far.list } else .{};
            return out;
        },
        .list_len => {
            const list = a.liveOperand(i.a);
            if (a.f.inst(list).op != .param) return .{};
            return .{ .list = list, .strict = a.sabotage == .length };
        },
        .convert => return if (i.check == .none) .{} else knownBound(a, i.a),
        .add, .sub => {
            if (i.check == .none) return .{};
            const constant = a.inst(i.b);
            const c: ?i128 = if (constant.op == .iconst) constantValue(constant) else null;
            const step = c orelse return .{};
            // `x + c` with `c <= 0` (or `x - c` with `c >= 0`) is at most `x`.
            if ((i.op == .add and step <= 0) or (i.op == .sub and step >= 0)) return knownBound(a, i.a);
            // `x + 1` with `x < len` is at most `len`.
            if (i.op == .add and step == 1) {
                const x = knownBound(a, i.a).best(lessBound(a, a.f.resolve(i.a), block));
                if (x.strict) return .{ .list = x.list };
            }
            return .{};
        },
        .floor_div, .div => {
            const divisor = a.inst(i.b);
            if (divisor.op != .iconst or constantValue(divisor) < 1) return .{};
            const dividend = a.rangeAt(i.a, block) orelse return .{};
            // A non-negative `x // d` is at most `x`.
            if (dividend.lo < 0) return .{};
            var out = knownBound(a, i.a);
            const sum = a.inst(i.a);
            if (constantValue(divisor) == 2 and sum.op == .add and sum.check != .none) {
                const x = a.f.resolve(sum.a);
                const y = a.f.resolve(sum.b);
                // `(x + y) // 2` is at most the larger operand, and below `y` when `x < y`.
                out = out.best(knownBound(a, x).meet(knownBound(a, y)));
                if (a.knownLess(x, y, block) and knownBound(a, y).list != .none) out = out.best(.{ .list = knownBound(a, y).list, .strict = true });
                if (a.knownLess(y, x, block) and knownBound(a, x).list != .none) out = out.best(.{ .list = knownBound(a, x).list, .strict = true });
            }
            return out;
        },
        else => return .{},
    }
}

fn compare(a: *Analysis, i: ir.Inst, block: ir.BlockId) ?Interval {
    const unknown: Interval = .{ .lo = 0, .hi = 1 };
    const x = a.rangeAt(i.a, block) orelse return unknown;
    const y = a.rangeAt(i.b, block) orelse return unknown;
    const decided: ?bool = switch (@as(ir.Predicate, @fromBackingInt(@intCast(i.data)))) {
        .lt => if (x.hi < y.lo) true else if (x.lo >= y.hi) false else null,
        .le => if (x.hi <= y.lo) true else if (x.lo > y.hi) false else null,
        .gt => if (x.lo > y.hi) true else if (x.hi <= y.lo) false else null,
        .ge => if (x.lo >= y.hi) true else if (x.hi < y.lo) false else null,
        .eq => if (x.lo == x.hi and y.lo == y.hi and x.lo == y.lo) true else if (x.hi < y.lo or y.hi < x.lo) false else null,
        .ne => if (x.hi < y.lo or y.hi < x.lo) true else if (x.lo == x.hi and y.lo == y.hi and x.lo == y.lo) false else null,
    };
    return if (decided) |value| Interval.point(@intFromBool(value)) else unknown;
}

/// Turn every check the facts rule out into `proven` and fold decided comparisons.
fn mark(a: *Analysis, fold: bool) void {
    for (a.f.blocks.items, 0..) |block, b| {
        if (!a.facts.reachable[b]) continue;
        const here: ir.BlockId = @fromBackingInt(@intCast(b));
        for (block.insts.items) |ref| {
            const i = &a.f.insts.items[ref.index()];
            if (i.op == .cmp and fold) {
                const range = a.facts.ranges[ref.index()] orelse continue;
                if (range.lo != range.hi) continue;
                i.* = .{ .op = .iconst, .ty = .bool, .data = @intCast(range.lo), .span = i.span };
                continue;
            }
            if (i.check != .exact) continue;
            if (provable(a, i.*, here)) {
                i.check = .proven;
                a.facts.proven += 1;
            }
        }
    }
}

fn provable(a: *Analysis, i: ir.Inst, block: ir.BlockId) bool {
    const limits = typeRange(i.ty) orelse return false;
    switch (i.op) {
        .add, .sub, .mul => {
            const x = a.rangeAt(i.a, block) orelse return false;
            const y = a.rangeAt(i.b, block) orelse return false;
            const exact = arithmetic(i.op, x, y);
            // `proven` emits `nsw`/`nuw`, so the operands must also respect the signedness flag.
            return exact.within(limits) and (limits.lo < 0 or (x.lo >= 0 and y.lo >= 0));
        },
        .neg => {
            const x = a.rangeAt(i.a, block) orelse return false;
            return x.lo > limits.lo;
        },
        .floor_div, .floor_rem, .div, .rem => {
            // `proven` division is `udiv`/`urem`: both operands non-negative, the divisor non-zero.
            const x = a.rangeAt(i.a, block) orelse return false;
            const d = a.rangeAt(i.b, block) orelse return false;
            return x.lo >= 0 and d.lo > 0;
        },
        .convert => {
            const x = a.rangeAt(i.a, block) orelse return false;
            return x.within(limits);
        },
        .float_to_int => {
            const x = floatOf(a, i.a) orelse return false;
            const converted = toInt(x) orelse return false;
            return converted.within(limits);
        },
        .list_get => {
            const index = a.liveOperand(i.b);
            const range = a.rangeAt(index, block) orelse return false;
            if (range.lo < 0) return false;
            const list = a.liveOperand(i.a);
            // `index < len(list)` for a list parameter: by the index's own bound, or by a
            // dominating `index < y` (or `index <= y` with `y` strictly bounded) and `y`'s bound.
            const bound = (a.facts.bounds[index.index()] orelse LengthBound{}).best(lessBound(a, index, block));
            if (bound.list == list and bound.strict) return true;
            const length = a.facts.lists[list.index()].length;
            if (length == .none) return false;
            return a.knownLess(index, length, block);
        },
        else => return false,
    }
}
