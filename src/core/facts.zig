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
const index_keys = @import("index_keys.zig");

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
    /// The list's length lies in this interval: a new list is empty, a push adds one, a pop
    /// removes one, a write or copy keeps it. A fact about the value, like every list fact.
    len: ?Interval = null,
    /// The fact was computed (a list operation's result, or a phi joined at least once): a phi joining a
    /// loop-carried list skips an operand that is not settled yet instead of reading it as unknown.
    settled: bool = false,
    /// `length` and `elements` come from a counted fill loop's pattern (`listFacts`), not from joining operands.
    pattern: bool = false,
    /// Every child list has max(child_length, 0) elements. Only immutable
    /// parameters/constants qualify; a varying loop-bound ref cannot name it.
    child_length: ir.Ref = .none,
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

/// The live-entry length and inserted scalar hulls of an immutable dictionary value.
pub const DictFact = struct {
    len: ?Interval = null,
    keys: ?Interval = null,
    values: ?Interval = null,
    /// A loop phi may join only predecessors whose transfer has settled.
    settled: bool = false,
};

/// What is known about lists and records, per instruction.
pub const Aggregates = struct {
    lists: []ListFact,
    /// Dictionary facts never cross calls or apply to mutable place aliases.
    dicts: []DictFact,
    /// The interval of each field of a record value (integers and booleans; other fields have
    /// none), through `record_make`, `record_set` and phis. Null when unknown.
    fields: []?[]const ?Interval,
};

/// The facts of one function.
pub const Facts = struct {
    /// Per instruction: its interval (integers and booleans), null when unknown or unreachable.
    ranges: []?Interval,
    aggregates: Aggregates,
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

    /// Retain the final tables after a temporary analysis arena is reclaimed.
    pub fn clone(self: Facts, arena: std.mem.Allocator) Error!Facts {
        var out = self;
        out.ranges = try arena.dupe(?Interval, self.ranges);
        out.aggregates.lists = try arena.dupe(ListFact, self.aggregates.lists);
        out.aggregates.dicts = try arena.dupe(DictFact, self.aggregates.dicts);
        out.aggregates.fields = try arena.dupe(?[]const ?Interval, self.aggregates.fields);
        for (out.aggregates.fields) |*slot| {
            if (slot.*) |fields| slot.* = try arena.dupe(?Interval, fields);
        }
        out.floats = try arena.dupe(?FloatInterval, self.floats);
        out.reachable = try arena.dupe(bool, self.reachable);
        out.bounds = try arena.dupe(?LengthBound, self.bounds);
        out.counted = try arena.dupe(Counted, self.counted);
        return out;
    }
};

/// Dominators, reverse postorder and the block of every instruction.
pub const Shape = struct {
    rpo: []ir.BlockId,
    idom: []?ir.BlockId,
    block_of: []?ir.BlockId,
    /// Position of each block in `rpo` (unreachable from the entry: maxInt).
    order: []u32,
};

/// Dominators and reverse postorder used by fact and probe passes.
pub fn shape(arena: std.mem.Allocator, f: *const ir.Function) std.mem.Allocator.Error!Shape {
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

/// The index the program wrote when `phi`, in block `join`, is the builder's Python
/// normalization of it (NEW-CORE-F2-WRAP-1): a phi of two predecessors whose operand from
/// `test` is `raw`, where `test` ends in `branch raw < 0, adjust, join` and `adjust`, entered
/// only from `test`, jumps to `join`. On every path where `raw >= 0` the phi is `raw` itself,
/// whatever `adjust` computes. Null for any other value, and once the facts folded the test.
pub fn normalizedRaw(f: *const ir.Function, join: ir.BlockId, phi: ir.Ref) ?ir.Ref {
    const inst = f.inst(f.resolve(phi));
    if (inst.op != .phi or inst.ty != .i64) return null;
    const operands = f.operands(inst.data);
    const preds = f.blocks.items[join.index()].preds.items;
    if (operands.len != 2 or preds.len != 2) return null;
    for (0..2) |k| {
        const raw = f.resolve(operands[k]);
        const test_block = f.blocks.items[preds[k].index()];
        const adjust = preds[1 - k];
        const adjust_block = f.blocks.items[adjust.index()];
        if (test_block.insts.items.len == 0 or adjust_block.insts.items.len == 0) continue;
        if (adjust_block.preds.items.len != 1 or adjust_block.preds.items[0] != preds[k]) continue;
        const leave = f.inst(adjust_block.insts.items[adjust_block.insts.items.len - 1]);
        if (leave.op != .jump or leave.data != @backingInt(join)) continue;
        const last = f.inst(test_block.insts.items[test_block.insts.items.len - 1]);
        if (last.op != .branch) continue;
        const targets = ir.unpackTargets(last.data);
        if (targets.then != adjust or targets.otherwise != join) continue;
        const condition = f.inst(f.resolve(last.a));
        if (condition.op != .cmp or @as(ir.Predicate, @fromBackingInt(@intCast(condition.data))) != .lt) continue;
        if (f.resolve(condition.a) != raw) continue;
        const zero = f.inst(f.resolve(condition.b));
        if (zero.op != .iconst or zero.data != 0 or f.inst(raw).ty != .i64) continue;
        return raw;
    }
    return null;
}

/// A counted loop: `counter = phi(start, counter + 1)` in the header, `counter < bound` its condition.
pub const Counted = struct { loop: ir.Loop, counter: ir.Ref, start: ir.Ref, bound: ir.Ref };

const Analysis = struct {
    storage: struct {
        /// Work storage; no allocation from this allocator escapes `analyze`.
        scratch: std.mem.Allocator,
        results: std.mem.Allocator,
        field_work: std.ArrayList(?Interval) = .empty,
    },
    f: *ir.Function,
    shape: Shape,
    facts: Facts,
    counted: std.ArrayList(Counted) = .empty,
    /// Numeric upper bounds that hold in every block a given block dominates: (block, value, hi).
    caps: std.ArrayList(struct { block: ir.BlockId, value: ir.Ref, hi: i128 }) = .empty,
    sabotage: Sabotage = .none,
    /// Per module function, the interval its calls return (`Options.returns`).
    returns: []const ?Interval = &.{},
    /// The round of the fixed-point iteration being run (the first is 0).
    round: usize = 0,
    /// Per list phi, how many times its element hull or common length changed (widened past eight).
    element_changes: []u8 = &.{},
    /// Value, index and list length identities (`index_keys`, NEW-CORE-F2-INDEX-2).
    keys: ?index_keys.Keys = null,
    /// Whole-program field intervals (`Options.fields`).
    fields: FieldIntervals = .{},

    fn inst(self: *Analysis, ref: ir.Ref) ir.Inst {
        return self.f.inst(self.f.resolve(ref));
    }

    fn base(self: *Analysis, raw: ir.Ref) ?Interval {
        const ref = self.f.resolve(raw);
        const i = self.f.inst(ref);
        return switch (i.op) {
            .iconst => if (typeRange(i.ty) != null) Interval.point(constantValue(i)) else null,
            .param => self.facts.ranges[ref.index()] orelse typeRange(i.ty),
            .undef, .union_payload => typeRange(i.ty),
            .call => self.facts.ranges[ref.index()] orelse typeRange(i.ty),
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
    if (left != ref and right != ref) return refineSquare(self, range, ref, cmp, taken);
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

/// Whether `raw` is `x * x` for `x` = `ref`, computed exactly: a checked product traps
/// instead of wrapping, and a proven one cannot leave its type.
fn squareOf(self: *Analysis, raw: ir.Ref, ref: ir.Ref) bool {
    const product = self.inst(raw);
    return product.op == .mul and product.check != .none and self.f.resolve(product.a) == ref and self.f.resolve(product.b) == ref;
}

/// `x * x <= y`, `x * x < y` or `x * x == y` on an edge bounds `|x|` by the integer square
/// root of `y`'s top (NEW-CORE-F1-OVERFLOW-2): `while i * i <= n` keeps `i` small.
fn refineSquare(self: *Analysis, range: Interval, ref: ir.Ref, cmp: ir.Inst, taken: bool) Interval {
    const on_left = squareOf(self, cmp.a, ref);
    if (!on_left and !squareOf(self, cmp.b, ref)) return range;
    var predicate: ir.Predicate = @fromBackingInt(@intCast(cmp.data));
    if (!taken) predicate = switch (predicate) {
        .eq => .ne,
        .ne => .eq,
        .lt => .ge,
        .le => .gt,
        .gt => .le,
        .ge => .lt,
    };
    // Put the square on the left: `y >= x * x` is `x * x <= y`.
    if (!on_left) predicate = switch (predicate) {
        .lt => .gt,
        .le => .ge,
        .gt => .lt,
        .ge => .le,
        else => predicate,
    };
    const bound = self.base(if (on_left) cmp.b else cmp.a) orelse return range;
    const top: i128 = switch (predicate) {
        .lt => bound.hi - 1,
        .le, .eq => bound.hi,
        else => return range,
    };
    if (top < 0) return range;
    var root: i128 = std.math.sqrt(@as(u128, @intCast(top)));
    if (self.sabotage == .overflow and root > 0) root -= 1;
    return range.meet(.{ .lo = -root, .hi = root });
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
    /// Per parameter position, the interval every caller's argument lies in
    /// (`passes.parameterRanges`); null or missing is the parameter type's range.
    params: []const ?Interval = &.{},
    /// Per module function, the interval every call of it returns (`returnRange`,
    /// NEW-CORE-F1-OVERFLOW-3); null or missing is the return type's range.
    returns: []const ?Interval = &.{},
    /// Turn the checks the facts rule out into `proven` and fold decided
    /// comparisons; false computes the facts without changing the function.
    mark: bool = true,
    /// Whole-program integer field intervals (`fields.zig`, NEW-CORE-F2-FIELD-1).
    fields: FieldIntervals = .{},
};

/// Whole-program intervals of integer and boolean record fields (`fields.zig`,
/// NEW-CORE-F2-FIELD-1): per record type, by compound index, per field, the hull of every
/// value any write in the module stores there; null where unknown.
pub const FieldIntervals = struct {
    module: ?*const ir.Module = null,
    types: []const ?[]const ?Interval = &.{},

    /// The interval of field `field` of every record of type `ty`, when known.
    pub fn get(self: FieldIntervals, ty: ir.Type, field: u64) ?Interval {
        const fields = self.table(ty) orelse return null;
        if (field >= fields.len) return null;
        return fields[@intCast(field)];
    }

    /// The intervals of every field of every record of type `ty`, when it has any.
    pub fn table(self: FieldIntervals, ty: ir.Type) ?[]const ?Interval {
        if (!ty.isCompound()) return null;
        const index = @backingInt(ty) - ir.Type.first_compound;
        if (index >= self.types.len) return null;
        return self.types[index];
    }

    /// The interval of the value at `path` inside an element of type `element`, when the
    /// path ends in a field of a record.
    pub fn atPath(self: FieldIntervals, element: ir.Type, path: ir.FieldPath) ?Interval {
        const module = self.module orelse return null;
        const last = pathField(module, element, path) orelse return null;
        return self.get(last.record, last.field);
    }
};

/// The record type and field the last step of `path` inside an `element` value selects,
/// or null when the last step is not a record field (a union tag or payload, an array element).
pub fn pathField(module: *const ir.Module, element: ir.Type, path: ir.FieldPath) ?struct { record: ir.Type, field: u32 } {
    var current = element;
    const steps = path.slice();
    for (steps, 0..) |step, k| {
        const kind = module.kind(current) orelse return null;
        switch (kind) {
            .record => {
                const fields = module.compound(current).record;
                if (step >= fields.len) return null;
                if (k + 1 == steps.len) return .{ .record = current, .field = step };
                current = fields[step];
            },
            .array => current = module.compound(current).array.elem,
            .@"union" => {
                const cases = module.compound(current).@"union";
                if (step == 0 or step - 1 >= cases.len) return null;
                current = cases[step - 1];
            },
            else => return null,
        }
    }
    return null;
}

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
    /// The overflow facts' rules (NEW-CORE-F1-OVERFLOW-1..3) are each off by one on the
    /// inside: a counter's per-iteration growth is one less, `x * x <= y` bounds `x` by
    /// one less than its square root, and a callee's return interval loses its top.
    overflow,
    /// A passed bounds check is taken to cover the next index up too (`index_checks`).
    index,
    /// A record field's whole-program interval loses its top (`fields.zig`).
    field,
    /// A bounds versioning guard admits one index past the end (`version.zig`).
    version,
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
    if (recomputeAggregates(a, ref, block, changes)) changed = true;
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

/// The interval `raw` lies in by `known`, the facts of `f`: a constant's point, a
/// computed value's interval, or the type's range; null when not an integer or unknown.
pub fn valueRange(known: *const Facts, f: *const ir.Function, raw: ir.Ref) ?Interval {
    const ref = f.resolve(raw);
    const i = f.inst(ref);
    if (i.op == .iconst) return if (typeRange(i.ty) != null) Interval.point(constantValue(i)) else null;
    if (ref.index() < known.ranges.len) {
        if (known.ranges[ref.index()]) |range| return range;
    }
    return null;
}

/// Compute the facts of `f` and mark every check they rule out as `proven`.
pub fn analyze(arena: std.mem.Allocator, f: *ir.Function, options: Options) Error!Facts {
    return analyzeWithScratch(arena, arena, f, options);
}

/// Compute facts on `arena`, using independently reclaimable work storage.
/// The caller may reset `scratch` immediately after this returns.
pub fn analyzeWithScratch(arena: std.mem.Allocator, scratch: std.mem.Allocator, f: *ir.Function, options: Options) Error!Facts {
    var a: Analysis = .{
        .storage = .{ .scratch = scratch, .results = arena },
        .sabotage = options.sabotage,
        .returns = options.returns,
        .fields = options.fields,
        .f = f,
        .shape = try shape(scratch, f),
        .facts = .{
            .ranges = try arena.alloc(?Interval, f.insts.items.len),
            .aggregates = .{
                .lists = try arena.alloc(ListFact, f.insts.items.len),
                .dicts = try arena.alloc(DictFact, f.insts.items.len),
                .fields = try arena.alloc(?[]const ?Interval, f.insts.items.len),
            },
            .floats = try arena.alloc(?FloatInterval, f.insts.items.len),
            .reachable = try arena.alloc(bool, f.blocks.items.len),
            .bounds = try arena.alloc(?LengthBound, f.insts.items.len),
        },
    };
    @memset(a.facts.aggregates.fields, null);
    @memset(a.facts.bounds, null);
    @memset(a.facts.ranges, null);
    @memset(a.facts.floats, null);
    @memset(a.facts.aggregates.lists, .{});
    @memset(a.facts.aggregates.dicts, .{});
    // Caller-derived parameter intervals seed the parameters; `base` reads them.
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .param and inst.data < options.params.len) a.facts.ranges[index] = options.params[@intCast(inst.data)];
    }
    try findCounted(&a);
    a.keys = try index_keys.compute(scratch, f, a.shape.rpo);
    const changes = try scratch.alloc(u8, f.insts.items.len);
    @memset(changes, 0);
    a.element_changes = try scratch.alloc(u8, f.insts.items.len);
    @memset(a.element_changes, 0);
    var round: usize = 0;
    var converged = false;
    // Reachability only grows (as in sparse conditional constant propagation):
    // an edge found executable stays so, which keeps the iteration monotone.
    @memset(a.facts.reachable, false);
    a.facts.reachable[0] = true;
    while (round < 64) : (round += 1) {
        a.round = round;
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
    if (converged) {
        if (options.mark) mark(&a, options.fold);
    } else {
        // Reachability short of a fixed point may miss blocks: every block counts as reachable.
        @memset(a.facts.reachable, true);
        @memset(a.facts.ranges, null);
        @memset(a.facts.floats, null);
        @memset(a.facts.aggregates.lists, .{});
        @memset(a.facts.aggregates.dicts, .{});
        @memset(a.facts.bounds, null);
        @memset(a.facts.aggregates.fields, null);
    }
    a.facts.counted = if (converged) try arena.dupe(Counted, a.counted.items) else &.{};
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
        try a.counted.append(a.storage.scratch, .{ .loop = loop, .counter = counter, .start = a.f.resolve(operands[1 - latch_index]), .bound = a.f.resolve(condition.b) });
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
            var fact: ListFact = .{ .length = counted.bound, .elements = elements, .pattern = true, .child_length = childLength(a, pushed.b, push_block) };
            fact.len = a.facts.aggregates.lists[ref.index()].len;
            fact.settled = a.facts.aggregates.lists[ref.index()].settled;
            if (!std.meta.eql(a.facts.aggregates.lists[ref.index()], fact)) {
                a.facts.aggregates.lists[ref.index()] = fact;
                changed = true;
            }
            var capped = false;
            for (a.caps.items) |cap| capped = capped or (cap.value == counted.bound and cap.block == counted.loop.exit);
            if (!capped) {
                try a.caps.append(a.storage.scratch, .{ .block = counted.loop.exit, .value = counted.bound, .hi = max_list_length });
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
        .saturating_add => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const y = a.rangeAt(i.b, block) orelse break :blk full;
            const limits = full orelse break :blk null;
            break :blk .{ .lo = std.math.clamp(x.lo + y.lo, limits.lo, limits.hi), .hi = std.math.clamp(x.hi + y.hi, limits.lo, limits.hi) };
        },
        .shift_right => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const count = a.rangeAt(i.b, block) orelse break :blk full;
            const info = i.ty.integer() orelse break :blk full;
            if (count.lo < 0 or count.hi >= info.bits) break :blk full;
            const lo: u7 = @intCast(count.lo);
            const hi: u7 = @intCast(count.hi);
            break :blk .{ .lo = @min(x.lo >> lo, x.lo >> hi), .hi = @max(x.hi >> lo, x.hi >> hi) };
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
        .bit_xor => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            const y = a.rangeAt(i.b, block) orelse break :blk full;
            if (x.lo < 0 or y.lo < 0) break :blk full;
            const high: u128 = @intCast(@max(x.hi, y.hi));
            const bits: u8 = @intCast(128 - @clz(high));
            const bound: i128 = if (bits == 0) 0 else @intCast((@as(u128, 1) << @intCast(bits)) - 1);
            break :blk (Interval{ .lo = 0, .hi = bound }).meet(full.?);
        },
        .convert => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            // Unchecked conversion can truncate or reinterpret signed bits. Intersection
            // describes checked conversion, but cannot describe a wrapping bit pattern.
            if (i.check == .none and !x.within(full.?)) break :blk full;
            break :blk x.meet(full.?);
        },
        .list_len => blk: {
            const known = a.facts.aggregates.lists[a.liveOperand(i.a).index()].len orelse break :blk .{ .lo = 0, .hi = max_list_length };
            break :blk known.meet(.{ .lo = 0, .hi = max_list_length });
        },
        .dict_len => a.facts.aggregates.dicts[a.liveOperand(i.a).index()].len orelse .{ .lo = 0, .hi = max_list_length },
        .dict_entries => .{ .lo = 0, .hi = max_list_length },
        .dict_entry_key => a.facts.aggregates.dicts[a.liveOperand(i.a).index()].keys orelse full,
        .dict_entry_value => a.facts.aggregates.dicts[a.liveOperand(i.a).index()].values orelse full,
        .str_len => .{ .lo = 0, .hi = max_list_length },
        .record_get => blk: {
            // This function's own view of the record, and every record of its type's (NEW-CORE-F2-FIELD-1).
            const global = a.fields.get(a.inst(i.a).ty, i.data);
            const table = fieldsOf(a, i.a) orelse &.{};
            const local: ?Interval = if (i.data < table.len) table[@intCast(i.data)] else null;
            var field = local orelse global orelse break :blk full;
            if (local != null and global != null) {
                const both = field.meet(global.?);
                if (both.lo <= both.hi) field = both;
            }
            break :blk if (full) |limits| field.meet(limits) else field;
        },
        .list_get_field => blk: {
            const list_type = a.inst(i.a).ty;
            const module = a.fields.module orelse break :blk full;
            if (module.kind(list_type) != .list) break :blk full;
            const field = a.fields.atPath(module.compound(list_type).list, ir.FieldPath.unpack(i.data & ~@import("flags.zig").place_read)) orelse break :blk full;
            break :blk if (full) |limits| field.meet(limits) else field;
        },
        .float_to_int => blk: {
            const converted = toInt(floatOf(a, i.a) orelse break :blk full) orelse break :blk full;
            break :blk converted.meet(full.?);
        },
        .list_get, .array_get => blk: {
            const list = a.liveOperand(i.a);
            break :blk a.facts.aggregates.lists[list.index()].elements orelse full;
        },
        .cmp => compare(a, i, block),
        .not => blk: {
            const x = a.rangeAt(i.a, block) orelse break :blk full;
            break :blk .{ .lo = 1 - x.hi, .hi = 1 - x.lo };
        },
        .iconst => if (full != null) Interval.point(constantValue(i)) else null,
        .call => callRange(a, i) orelse full,
        else => full,
    };
}

/// A direct call's result lies in its callee's return interval (NEW-CORE-F1-OVERFLOW-3).
fn callRange(a: *Analysis, i: ir.Inst) ?Interval {
    const callee = i.a.index();
    if (callee >= a.returns.len) return null;
    const range = a.returns[callee] orelse return null;
    const limits = typeRange(i.ty) orelse return null;
    return range.meet(limits);
}

/// The interval of every value `f` returns (NEW-CORE-F1-OVERFLOW-3): the hull of each
/// reachable `ret` operand's interval where it returns, or null for a non-integer result
/// or one without an interval. Computed with `f`'s own parameters unknown (and its
/// callees' return intervals), it holds for every call, whatever the arguments.
pub fn returnRange(known: *const Facts, f: *const ir.Function, sabotage: Sabotage) ?Interval {
    if (typeRange(f.signature.ret) == null) return null;
    var out: ?Interval = null;
    for (f.blocks.items, 0..) |block, b| {
        if (b >= known.reachable.len or !known.reachable[b]) continue;
        if (block.insts.items.len == 0) continue;
        const last = f.inst(block.insts.items[block.insts.items.len - 1]);
        if (last.op != .ret) continue;
        const range = valueRange(known, f, last.a) orelse return null;
        out = if (out) |so_far| so_far.hull(range) else range;
    }
    if (sabotage == .overflow) if (out) |range| {
        if (range.hi > range.lo) return .{ .lo = range.lo, .hi = range.hi - 1 };
    };
    return out;
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

/// The field intervals of record value `raw`, when known: this function's own, else every
/// record of its type's (`FieldIntervals`, NEW-CORE-F2-FIELD-1), so a record a parameter,
/// call or element read brings in starts from them and its updates and joins keep them.
fn fieldsOf(a: *Analysis, raw: ir.Ref) ?[]const ?Interval {
    const ref = a.f.resolve(raw);
    if (a.facts.aggregates.fields[ref.index()]) |own| return own;
    return a.fields.table(a.f.inst(ref).ty);
}

/// The interval of an integer or boolean operand, null for any other type.
fn scalarRange(a: *Analysis, operand: ir.Ref, block: ir.BlockId) ?Interval {
    if (typeRange(a.inst(operand).ty) == null) return null;
    return a.rangeAt(operand, block);
}

fn sameFields(x: ?[]const ?Interval, y: ?[]const ?Interval) bool {
    const left = x orelse return y == null;
    const right = y orelse return false;
    if (left.len != right.len) return false;
    for (left, right) |p, q| if (!std.meta.eql(p, q)) return false;
    return true;
}

fn hullOf(x: ?Interval, y: ?Interval) ?Interval {
    const p = x orelse return null;
    const q = y orelse return null;
    return p.hull(q);
}

/// The field intervals a record instruction's value has: `record_make` takes its operands'
/// intervals, `record_set` replaces one field of its base's, and a phi joins its live operands'.
fn recordFields(a: *Analysis, ref: ir.Ref, block: ir.BlockId) !?[]const ?Interval {
    const i = a.f.inst(ref);
    switch (i.op) {
        .record_make => {
            const operands = a.f.operands(i.data);
            try a.storage.field_work.resize(a.storage.scratch, operands.len);
            const out = a.storage.field_work.items;
            for (operands, out) |operand, *field| field.* = scalarRange(a, operand, block);
            return out;
        },
        .record_set => {
            const base = fieldsOf(a, i.a) orelse return null;
            if (i.data >= base.len) return null;
            try a.storage.field_work.resize(a.storage.scratch, base.len);
            const out = a.storage.field_work.items;
            @memcpy(out, base);
            out[@intCast(i.data)] = scalarRange(a, i.b, block);
            return out;
        },
        .phi => {
            var joined: ?[]?Interval = null;
            for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
                if (!a.edgeLive(pred, block)) continue;
                const table = fieldsOf(a, operand) orelse return null;
                if (joined) |out| {
                    if (out.len != table.len) return null;
                    for (out, table) |*field, other| field.* = hullOf(field.*, other);
                } else {
                    try a.storage.field_work.resize(a.storage.scratch, table.len);
                    @memcpy(a.storage.field_work.items, table);
                    joined = a.storage.field_work.items;
                }
            }
            return joined;
        },
        else => return null,
    }
}

/// The list fact an instruction gives its result, from its operand's.
fn listFact(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ListFact {
    const i = a.f.inst(ref);
    const none: ListFact = .{};
    switch (i.op) {
        .record_make => {
            const module = a.fields.module orelse return none;
            if (module.kind(i.ty) != .array) return none;
            const operands = a.f.operands(i.data);
            var hull: ?Interval = null;
            for (operands, 0..) |operand, index| {
                const value = scalarRange(a, operand, block);
                hull = if (index == 0) value else hullOf(hull, value);
            }
            return .{ .len = Interval.point(@intCast(operands.len)), .elements = hull, .settled = true };
        },
        .list_new => return .{ .len = Interval.point(0), .settled = true },
        .list_copy => {
            var copied = a.facts.aggregates.lists[a.f.resolve(i.a).index()];
            copied.settled = !pendingList(a, i.a);
            return copied;
        },
        .list_get => return .{ .length = a.facts.aggregates.lists[a.f.resolve(i.a).index()].child_length, .settled = !pendingList(a, i.a) },
        .list_push => {
            const old = a.facts.aggregates.lists[a.f.resolve(i.a).index()];
            const value = scalarRange(a, i.b, block);
            var out: ListFact = .{ .settled = !pendingList(a, i.a) };
            if (old.len) |len| out.len = .{ .lo = len.lo + 1, .hi = @min(len.hi + 1, max_list_length) };
            // An empty list holds only the pushed value; any other list the hull of its elements and it.
            if (old.len) |len| {
                if (len.lo == 0 and len.hi == 0) out.elements = value;
            }
            if (out.elements == null) out.elements = if (old.elements) |held| (if (value) |v| held.hull(v) else null) else null;
            const child = childLength(a, i.b, block);
            out.child_length = if (emptyList(old) or old.child_length == child) child else .none;
            return out;
        },
        .list_pop => {
            const old = a.facts.aggregates.lists[a.f.resolve(i.a).index()];
            var out: ListFact = .{ .elements = old.elements, .settled = !pendingList(a, i.a), .child_length = old.child_length };
            if (old.len) |len| out.len = .{ .lo = @max(len.lo - 1, 0), .hi = @max(len.hi - 1, 0) };
            return out;
        },
        .list_set, .array_set => {
            const old = a.facts.aggregates.lists[a.f.resolve(i.a).index()];
            const value = scalarRange(a, a.f.operands(i.data)[0], block);
            var out: ListFact = .{ .length = old.length, .len = old.len, .settled = !pendingList(a, i.a) };
            if (old.child_length == childLength(a, a.f.operands(i.data)[0], block)) out.child_length = old.child_length;
            if (old.elements) |held| out.elements = if (value) |v| held.hull(v) else null;
            return out;
        },
        else => return none,
    }
}

fn emptyList(fact: ListFact) bool {
    const len = fact.len orelse return false;
    return len.lo == 0 and len.hi == 0;
}

fn childLength(a: *Analysis, raw: ir.Ref, block: ir.BlockId) ir.Ref {
    var ref = a.f.resolve(raw);
    const length = a.facts.aggregates.lists[ref.index()].length;
    if (length == .none) return .none;
    // A fill phi has its final length only after its exit. Copies capture the
    // length where they are made, even when inserted into a parent after exit.
    var captured_at = block;
    while (a.f.inst(ref).op == .list_copy or a.f.inst(ref).op == .list_set) {
        captured_at = a.shape.block_of[ref.index()] orelse return .none;
        ref = a.f.resolve(a.f.inst(ref).a);
    }
    if (a.facts.aggregates.lists[ref.index()].length != length) return .none;
    if (a.f.inst(ref).op == .phi and !completedFill(a, ref, captured_at)) return .none;
    const producer = a.inst(length);
    return if (producer.op == .param or producer.op == .iconst) length else .none;
}

fn completedFill(a: *Analysis, ref: ir.Ref, block: ir.BlockId) bool {
    if (!a.facts.aggregates.lists[ref.index()].pattern) return false;
    const header = a.shape.block_of[ref.index()] orelse return false;
    for (a.counted.items) |counted| {
        if (counted.loop.header == header) return a.dominates(counted.loop.exit, block);
    }
    return false;
}

/// Record field intervals and list lengths, element hulls: recompute them for `ref`, widening
/// what keeps changing. Returns whether anything changed.
fn recomputeAggregates(a: *Analysis, ref: ir.Ref, block: ir.BlockId, changes: []u8) bool {
    const i = a.f.inst(ref);
    var changed = false;
    switch (i.op) {
        .record_make, .record_set, .phi => {
            const old = a.facts.aggregates.fields[ref.index()];
            var next = recordFields(a, ref, block) catch return false;
            if (old != null and next != null and !sameFields(old, next)) {
                changes[ref.index()] +|= 1;
                // A field that keeps changing joins the unknown.
                if (changes[ref.index()] > 8) {
                    const widened = @constCast(next.?);
                    for (widened, old.?) |*field, before| {
                        if (!std.meta.eql(field.*, before)) field.* = null;
                    }
                    next = widened;
                }
            }
            if (!sameFields(old, next)) {
                // Keep one stable result table per record instead of retaining
                // another allocation on every fixed-point round. Transfers use a
                // separate buffer, so a self-referential phi still reads the old table.
                a.facts.aggregates.fields[ref.index()] = if (next) |table| blk: {
                    if (old) |previous| if (previous.len == table.len) {
                        @memcpy(@constCast(previous), table);
                        break :blk previous;
                    };
                    break :blk a.storage.results.dupe(?Interval, table) catch return false;
                } else null;
                changed = true;
            }
        },
        else => {},
    }
    switch (i.op) {
        .record_make, .array_set, .list_new, .list_copy, .list_push, .list_pop, .list_set, .list_get => {
            const next = listFact(a, ref, block);
            if (!std.meta.eql(a.facts.aggregates.lists[ref.index()], next)) {
                a.facts.aggregates.lists[ref.index()] = next;
                changed = true;
            }
        },
        .phi => if (joinLengths(a, ref, block, changes)) {
            changed = true;
        },
        else => {},
    }
    if (recomputeDict(a, ref, block, changes)) changed = true;
    return changed;
}

/// Dictionary lengths and hulls follow only immutable SSA values.
fn recomputeDict(a: *Analysis, ref: ir.Ref, block: ir.BlockId, changes: []u8) bool {
    const i = a.f.inst(ref);
    const old = a.facts.aggregates.dicts[ref.index()];
    var next: DictFact = .{};
    switch (i.op) {
        .dict_new, .dict_clear => next = .{ .len = Interval.point(0), .settled = true },
        .dict_copy => {
            next = a.facts.aggregates.dicts[a.f.resolve(i.a).index()];
            next.settled = !pendingDict(a, i.a);
        },
        .dict_insert, .dict_remove, .dict_set_value => {
            next = a.facts.aggregates.dicts[a.f.resolve(i.a).index()];
            next.settled = !pendingDict(a, i.a);
            if (i.op == .dict_insert) {
                const operands = a.f.operands(i.data);
                const key = scalarRange(a, operands[0], block);
                const value = if (operands[1] == .none) null else scalarRange(a, operands[1], block);
                const empty = if (next.len) |len| len.hi == 0 else false;
                next.keys = if (empty) key else hullOf(next.keys, key);
                next.values = if (empty) value else hullOf(next.values, value);
                const probe = a.rangeAt(i.b, block);
                if (next.len) |len| next.len = .{ .lo = len.lo + @as(i128, @intFromBool(probe != null and probe.?.hi < 0)), .hi = @min(len.hi + 1, max_list_length) };
            } else if (i.op == .dict_remove) {
                if (next.len) |len| next.len = .{ .lo = @max(0, len.lo - 1), .hi = @max(0, len.hi - 1) };
            } else next.values = hullOf(next.values, scalarRange(a, a.f.operands(i.data)[0], block));
        },
        .phi => {
            var seen = false;
            for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
                if (!a.edgeLive(pred, block)) continue;
                const source = a.f.resolve(operand);
                const held = a.facts.aggregates.dicts[source.index()];
                if (pendingDict(a, source)) continue;
                if (!seen) next = held else {
                    const empty_before = if (next.len) |len| len.hi == 0 else false;
                    const empty_other = if (held.len) |len| len.hi == 0 else false;
                    next.len = hullOf(next.len, held.len);
                    if (empty_before) {
                        next.keys = held.keys;
                        next.values = held.values;
                    } else if (!empty_other) {
                        next.keys = hullOf(next.keys, held.keys);
                        next.values = hullOf(next.values, held.values);
                    }
                }
                seen = true;
            }
            if (!seen) return false;
            next.settled = true;
            if (old.settled and !std.meta.eql(old.len, next.len)) {
                changes[ref.index()] +|= 1;
                if (changes[ref.index()] > 8 and next.len != null) next.len = .{ .lo = 0, .hi = max_list_length };
            }
            const hull_changed = !std.meta.eql(old.keys, next.keys) or !std.meta.eql(old.values, next.values);
            if (old.settled and hull_changed) {
                a.element_changes[ref.index()] +|= 1;
                if (a.element_changes[ref.index()] > 8) {
                    next.keys = null;
                    next.values = null;
                }
            }
        },
        else => return false,
    }
    if (std.meta.eql(old, next)) return false;
    a.facts.aggregates.dicts[ref.index()] = next;
    return true;
}

/// A dictionary producer still waiting for transfer is pending; an unknown
/// call or parameter already contributes unknown facts to its consumers.
fn pendingDict(a: *Analysis, operand: ir.Ref) bool {
    const ref = a.f.resolve(operand);
    return switch (a.f.inst(ref).op) {
        .dict_new, .dict_clear, .dict_copy, .dict_insert, .dict_remove, .dict_set_value, .phi => !a.facts.aggregates.dicts[ref.index()].settled,
        else => false,
    };
}

/// Whether `operand`'s list fact is still to be computed: it is a list operation or a phi the
/// pass has not reached (a loop's back edge), which a phi must not read as unknown.
fn pendingList(a: *Analysis, operand: ir.Ref) bool {
    const ref = a.f.resolve(operand);
    return switch (a.f.inst(ref).op) {
        .array_set, .list_new, .list_copy, .list_push, .list_pop, .list_set, .list_get, .phi => !a.facts.aggregates.lists[ref.index()].settled,
        else => false,
    };
}

/// A phi of lists has the hull of its settled live operands' lengths and elements, and their common
/// `length` when they agree (a phi of anything else has none). An operand not settled yet, the back
/// edge of a loop, is skipped: the first round holds the entry's facts, which later rounds can only
/// weaken, and a fact that keeps changing is widened to unknown.
fn joinLengths(a: *Analysis, ref: ir.Ref, block: ir.BlockId, changes: []u8) bool {
    const i = a.f.inst(ref);
    if (!i.ty.isCompound()) return false;
    // A counted loop's list phi gets its pattern facts at the end of the first round; until then
    // it and what derives from it stay unsettled, so nothing reads them as unknown.
    if (a.round == 0) for (a.counted.items) |counted| {
        if (counted.loop.header == block) return false;
    };
    var joined: ?Interval = null;
    var hull: ?Interval = null;
    var length: ir.Ref = .none;
    var seen = false;
    var lengths_known = true;
    var elements_known = true;
    var child_length: ?ir.Ref = null;
    for (a.f.operands(i.data), a.f.blocks.items[block.index()].preds.items) |operand, pred| {
        if (!a.edgeLive(pred, block)) continue;
        if (pendingList(a, operand)) continue;
        const fact = a.facts.aggregates.lists[a.f.resolve(operand).index()];
        if (fact.len) |len| joined = if (joined) |so_far| so_far.hull(len) else len else lengths_known = false;
        if (fact.elements) |held| hull = if (hull) |so_far| so_far.hull(held) else held else elements_known = false;
        if (!emptyList(fact)) {
            if (child_length) |held| {
                if (held != fact.child_length) child_length = .none;
            } else child_length = fact.child_length;
        }
        if (!seen) length = fact.length else if (length != fact.length) length = .none;
        seen = true;
    }
    if (!seen) return false;
    if (!lengths_known) joined = null;
    if (!elements_known) hull = null;
    var next = a.facts.aggregates.lists[ref.index()];
    const old = next;
    next.len = joined;
    next.settled = true;
    next.child_length = child_length orelse .none;
    // A counted fill loop's phi keeps what its pattern proved (`listFacts`).
    if (!old.pattern) {
        next.elements = hull;
        next.length = length;
    }
    // The length widens to every length when it keeps growing; the hull and the common length
    // are counted apart, so a loop that only grows its list keeps what it knows of the elements.
    if (old.settled and !std.meta.eql(old.len, next.len)) {
        changes[ref.index()] +|= 1;
        if (changes[ref.index()] > 8 and joined != null) next.len = .{ .lo = 0, .hi = max_list_length };
    }
    const hull_moved = !std.meta.eql(old.elements, next.elements) or old.length != next.length;
    if (old.settled and !old.pattern and hull_moved) {
        a.element_changes[ref.index()] +|= 1;
        if (a.element_changes[ref.index()] > 8) {
            next.elements = null;
            next.length = .none;
        }
    }
    if (std.meta.eql(old, next)) return false;
    a.facts.aggregates.lists[ref.index()] = next;
    return true;
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

/// `acc = phi(init, next)` in a counted loop, where each iteration moves `acc` by an
/// amount in `[lo, hi]` (`growth`): after at most `trips` iterations it lies in
/// `[init.lo + min(0, trips * lo), init.hi + max(0, trips * hi)]` (NEW-CORE-F1-OVERFLOW-1).
/// The growth may be conditional (`if data[i] == 109: count += 1`) and may pass through
/// an inner counted loop (`count += pass_index` then the inner loop's own counter).
fn reduction(a: *Analysis, ref: ir.Ref, block: ir.BlockId) ?Interval {
    for (a.counted.items) |counted| {
        if (counted.loop.header != block or counted.counter == ref) continue;
        const header = a.f.blocks.items[block.index()];
        const latch_index: usize = if (header.preds.items[0] == counted.loop.latch) 0 else 1;
        const operands = a.f.operands(a.f.inst(ref).data);
        var budget: u32 = growth_budget;
        var step = growth(a, ref, operands[latch_index], &budget) orelse return null;
        if (a.sabotage == .overflow) step.hi -= 1;
        const start = a.rangeAt(operands[1 - latch_index], header.preds.items[1 - latch_index]) orelse return null;
        const trips = tripBound(a, block) orelse return null;
        return grown(start, step, trips);
    }
    return null;
}

/// How many values one `reduction` may look through before it gives up.
const growth_budget: u32 = 64;

/// `start` after at most `trips` steps, each in `step`.
fn grown(start: Interval, step: Interval, trips: i128) Interval {
    return .{ .lo = start.lo +| @min(0, mulSat(trips, step.lo)), .hi = start.hi +| @max(0, mulSat(trips, step.hi)) };
}

/// How far value `raw` lies from `acc` in the same iteration, as an interval of `raw - acc`,
/// or null when `raw` is not `acc` moved by checked additions and subtractions, joins of
/// such values, and inner counted loops that move it.
fn growth(a: *Analysis, acc: ir.Ref, raw: ir.Ref, budget: *u32) ?Interval {
    if (budget.* == 0) return null;
    budget.* -= 1;
    const ref = a.f.resolve(raw);
    if (ref == acc) return Interval.point(0);
    const i = a.f.inst(ref);
    const where = a.shape.block_of[ref.index()] orelse return null;
    switch (i.op) {
        .add, .sub => {
            // A wrapping operation may wrap: only checked or proven ones move by their operand.
            if (i.check == .none) return null;
            if (growth(a, acc, i.a, budget)) |x| {
                const y = a.rangeAt(i.b, where) orelse return null;
                if (i.op == .add) return .{ .lo = x.lo +| y.lo, .hi = x.hi +| y.hi };
                return .{ .lo = x.lo -| y.hi, .hi = x.hi -| y.lo };
            }
            if (i.op == .sub) return null;
            const y = growth(a, acc, i.b, budget) orelse return null;
            const x = a.rangeAt(i.a, where) orelse return null;
            return .{ .lo = x.lo +| y.lo, .hi = x.hi +| y.hi };
        },
        .phi => {
            for (a.f.loops.items) |loop| {
                if (loop.header == where) return innerGrowth(a, acc, ref, where, budget);
            }
            var out: ?Interval = null;
            for (a.f.operands(i.data), a.f.blocks.items[where.index()].preds.items) |operand, pred| {
                if (!a.edgeLive(pred, where)) continue;
                const moved = growth(a, acc, operand, budget) orelse return null;
                out = if (out) |so_far| so_far.hull(moved) else moved;
            }
            return out;
        },
        else => return null,
    }
}

/// The growth of a phi in the header of an inner counted loop: its entry value's growth,
/// plus at most the inner loop's trips of its own per-iteration growth.
fn innerGrowth(a: *Analysis, acc: ir.Ref, phi: ir.Ref, header_block: ir.BlockId, budget: *u32) ?Interval {
    for (a.counted.items) |inner| {
        if (inner.loop.header != header_block) continue;
        const header = a.f.blocks.items[header_block.index()];
        const latch_index: usize = if (header.preds.items[0] == inner.loop.latch) 0 else 1;
        const operands = a.f.operands(a.f.inst(phi).data);
        const entry = growth(a, acc, operands[1 - latch_index], budget) orelse return null;
        const step = growth(a, phi, operands[latch_index], budget) orelse return null;
        const trips = tripBound(a, header_block) orelse return null;
        return grown(entry, step, trips);
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
            if (a.f.inst(list).op != .param and a.f.inst(list).ty != .bytes) return .{};
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

/// Whether a bounds or empty-list check of a list access cannot fail.
fn provableAccess(a: *Analysis, i: ir.Inst, block: ir.BlockId) bool {
    switch (i.op) {
        .list_get, .list_get_field, .list_set => {
            const index = a.liveOperand(i.b);
            const range = a.rangeAt(index, block) orelse return false;
            if (range.lo < 0) return false;
            const list = a.liveOperand(i.a);
            // The list is known to be longer than every index.
            if (a.facts.aggregates.lists[list.index()].len) |len| {
                if (range.hi < len.lo) return true;
            }
            // `index < len(list)` for a list parameter: by the index's own bound, or by a
            // dominating `index < y` (or `index <= y` with `y` strictly bounded) and `y`'s bound.
            const bound = (a.facts.bounds[index.index()] orelse LengthBound{}).best(lessBound(a, index, block));
            if (bound.list == list and bound.strict) return true;
            // A dominating `index < len(other)` for a list of the same length (NEW-CORE-F2-INDEX-2).
            if (belowLength(a, index, list, block)) return true;
            const length = a.facts.aggregates.lists[list.index()].length;
            if (length == .none) return false;
            // A fill loop's length holds only once the loop has exited (NEW-CORE-F2-INDEX-1).
            if (!lengthHolds(a, list, block)) return false;
            // The list has `max(length, 0)` elements, so an index below `length`'s least value is in it.
            if (a.rangeAt(length, block)) |least| {
                if (range.hi < least.lo) return true;
            }
            if (a.knownLess(index, length, block)) return true;
            // `x % n` is below a positive `n`, and `n` is the list's length.
            const producer = a.inst(index);
            const divisor = a.rangeAt(length, block) orelse return false;
            if (a.f.resolve(producer.b) != a.f.resolve(length) or divisor.lo < 1) return false;
            if (producer.op == .floor_rem) return true;
            const dividend = a.rangeAt(producer.a, block) orelse return false;
            return producer.op == .rem and dividend.lo >= 0;
        },
        .list_pop => {
            // A pop of a list known to hold an element cannot fail.
            const len = a.facts.aggregates.lists[a.liveOperand(i.a).index()].len orelse return false;
            return len.lo >= 1;
        },
        else => return false,
    }
}

/// Whether a dominating branch edge says `index < len(other)` (or `len(other) > index`), for
/// a list `other` with the length of `list` and an index equal to `index` (`index_keys`).
fn belowLength(a: *Analysis, index: ir.Ref, list: ir.Ref, block: ir.BlockId) bool {
    const keys = a.keys orelse return false;
    const wanted = keys.index(index);
    const length = keys.length(list);
    var b: ?ir.BlockId = block;
    while (b) |current| {
        if (a.edgeCondition(current)) |edge| {
            var predicate: ir.Predicate = @fromBackingInt(@intCast(edge.cmp.data));
            if (!edge.taken) predicate = switch (predicate) {
                .lt => .ge,
                .le => .gt,
                .gt => .le,
                .ge => .lt,
                .eq => .ne,
                .ne => .eq,
            };
            const pair: ?[2]ir.Ref = switch (predicate) {
                .lt => .{ edge.cmp.a, edge.cmp.b },
                .gt => .{ edge.cmp.b, edge.cmp.a },
                else => null,
            };
            if (pair) |operands| {
                if (lengthOf(a, operands[1])) |measured| {
                    if (std.meta.eql(keys.length(measured), length) and std.meta.eql(keys.index(operands[0]), wanted)) return true;
                }
            }
        }
        if (current.index() == 0) break;
        b = a.shape.idom[current.index()];
    }
    return false;
}

/// The list whose `len` value `raw` is, through value-preserving conversions.
fn lengthOf(a: *Analysis, raw: ir.Ref) ?ir.Ref {
    var ref = a.f.resolve(raw);
    var steps: usize = 0;
    while (steps < 4) : (steps += 1) {
        const inst = a.f.inst(ref);
        switch (inst.op) {
            .list_len => return a.f.resolve(inst.a),
            // A checked conversion traps instead of changing the value; `len` always fits `i64`.
            .convert => {
                if (inst.check == .none and inst.ty != .i64) return null;
                ref = a.f.resolve(inst.a);
            },
            else => return null,
        }
    }
    return null;
}

/// Whether the `length` fact of `list` holds where `block` runs (NEW-CORE-F2-INDEX-1): every
/// counted fill loop the fact comes from had exited where the value was made. Inside its
/// fill loop the list has as many elements as iterations so far, fewer than the fill bound.
/// A copy or write keeps the length its operand had where it ran; a phi takes each operand
/// as it was at the end of that operand's predecessor.
fn lengthHolds(a: *Analysis, list: ir.Ref, block: ir.BlockId) bool {
    const Pending = struct { ref: ir.Ref, at: ir.BlockId };
    var stack: [64]Pending = undefined;
    var depth: usize = 1;
    var seen: [64]ir.Ref = undefined;
    var seen_count: usize = 0;
    stack[0] = .{ .ref = a.f.resolve(list), .at = block };
    while (depth != 0) {
        depth -= 1;
        const item = stack[depth];
        const ref = a.f.resolve(item.ref);
        const fact = a.facts.aggregates.lists[ref.index()];
        if (fact.length == .none) continue;
        if (fact.pattern) {
            const header = a.shape.block_of[ref.index()] orelse return false;
            const exit = for (a.counted.items) |counted| {
                if (counted.loop.header == header) break counted.loop.exit;
            } else return false;
            if (!a.dominates(exit, item.at)) return false;
            continue;
        }
        // Anything but a fill phi holds or fails the same way wherever it is asked about.
        if (std.mem.indexOfScalar(ir.Ref, seen[0..seen_count], ref) != null) continue;
        if (seen_count == seen.len) return false;
        seen[seen_count] = ref;
        seen_count += 1;
        const inst = a.f.inst(ref);
        const here = a.shape.block_of[ref.index()] orelse return false;
        switch (inst.op) {
            .list_copy, .list_set => {
                if (depth == stack.len) return false;
                stack[depth] = .{ .ref = inst.a, .at = here };
                depth += 1;
            },
            .phi => for (a.f.operands(inst.data), a.f.blocks.items[here.index()].preds.items) |operand, pred| {
                if (depth == stack.len) return false;
                stack[depth] = .{ .ref = operand, .at = pred };
                depth += 1;
            },
            // A child's length is `completedFill`'s; nothing else carries a length.
            else => {},
        }
    }
    return true;
}

fn provable(a: *Analysis, i: ir.Inst, block: ir.BlockId) bool {
    switch (i.op) {
        .array_get, .array_set => {
            const module = a.fields.module orelse return false;
            const range = a.rangeAt(i.b, block) orelse return false;
            return range.lo >= 0 and range.hi < module.compound(a.inst(i.a).ty).array.n;
        },
        .list_get, .list_get_field, .list_set, .list_pop => return provableAccess(a, i, block),
        else => {},
    }
    const limits = typeRange(i.ty) orelse return false;
    switch (i.op) {
        .add, .sub, .mul => {
            const x = a.rangeAt(i.a, block) orelse return false;
            const y = a.rangeAt(i.b, block) orelse return false;
            const exact = arithmetic(i.op, x, y);
            // `proven` emits `nsw`/`nuw`, so the operands must also respect the signedness flag.
            return exact.within(limits) and (limits.lo < 0 or (x.lo >= 0 and y.lo >= 0));
        },
        .shift_left, .shift_right => {
            const count = a.rangeAt(i.b, block) orelse return false;
            return count.lo >= 0 and count.hi < i.ty.integer().?.bits;
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
        else => return false,
    }
}
