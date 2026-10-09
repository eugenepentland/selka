//! Slices used only as a loop source (NEW-CORE-CE-LISTS-5): `for b in xs[i:j]` iterates
//! `xs` itself.
//!
//! The builder lowers a slice `xs[a:b]` as its clamped endpoints, `0 <= first <= len(xs)`
//! and `0 <= last <= len(xs)` (each a chain of guarded joins), then a loop that copies
//! `xs[k]` for `first <= k < last` into a fresh list, and `for y in slice` as a counted loop
//! over the copy: `j` from 0 while `j < len(slice)`, reading `slice[j]`. When the copy has no
//! other use and the source list cannot change while the loop runs (no update, call, store
//! or join takes it inside the loop), the loop counts `j` from `first` while `j < last` and
//! reads `xs[j]`, and the copy is never made: every element it reads is the one the copy
//! held, every read is in bounds as the copy's was, and `break`, `continue` and `return`
//! leave the loop as before. A slice that is still materialized gets room for exactly its
//! elements, so it never grows.
//!
//! Runs on the built Core IR, before the release passes, so the facts see the loop as it
//! now runs.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// What the pass changed in one function.
pub const Counts = struct { iterated: u32 = 0, sized: u32 = 0 };

/// Rewrite every slice of `f` used only as a loop source, and size the others exactly.
pub fn loops(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) Error!Counts {
    var counts: Counts = .{};
    var changed = true;
    while (changed) {
        changed = false;
        const graph = try Graph.of(arena, f);
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                if (f.inst(ref).op != .phi or module.kind(f.inst(ref).ty) != .list) continue;
                const copy = matchCopy(f, graph, @intCast(b), ref) orelse continue;
                if (!try bounded(arena, f, copy)) continue;
                if (try matchLoop(arena, f, graph, copy)) |consumer| {
                    try iterateSource(arena, f, copy, consumer);
                    counts.iterated += 1;
                    changed = true;
                    break;
                }
                // The builder's empty copy grows as it fills; give it its exact room once.
                const room = f.inst(f.resolve(f.inst(copy.fresh).a));
                if (room.op != .iconst or room.data != 0) continue;
                if (try sizeExactly(arena, f, graph, copy)) {
                    counts.sized += 1;
                    changed = true;
                    break;
                }
            }
            if (changed) break;
        }
    }
    return counts;
}

/// Every instruction's users and block, over the blocks that take part.
const Graph = struct {
    users: []std.ArrayList(ir.Ref),
    block_of: []u32,

    const none = std.math.maxInt(u32);

    fn of(arena: std.mem.Allocator, f: *const ir.Function) Error!Graph {
        const graph: Graph = .{ .users = try arena.alloc(std.ArrayList(ir.Ref), f.insts.items.len), .block_of = try arena.alloc(u32, f.insts.items.len) };
        @memset(graph.users, .empty);
        @memset(graph.block_of, none);
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                graph.block_of[ref.index()] = @intCast(b);
                const inst = f.inst(ref);
                if (inst.op == .copy) continue;
                if (inst.op == .phi) {
                    for (f.operands(inst.data)) |operand| try graph.users[f.resolve(operand).index()].append(arena, ref);
                    continue;
                }
                const operands = f.valueOperands(inst);
                for (0..operands.len()) |k| {
                    const used = f.resolve(operands.get(k));
                    if (used != .none) try graph.users[used.index()].append(arena, ref);
                }
            }
        }
        return graph;
    }

    fn only(self: Graph, ref: ir.Ref) ?ir.Ref {
        const list = self.users[ref.index()].items;
        return if (list.len == 1) list[0] else null;
    }
};

/// A slice's copy loop: `slice = phi(fresh, push(slice, xs[k]))` at `header`, `k` from
/// `first` while `k < last`.
const Copy = struct {
    header: u32,
    slice: ir.Ref,
    fresh: ir.Ref,
    source: ir.Ref,
    first: ir.Ref,
    end: ir.Ref,
    /// The loop's own pieces: index phi, condition, read, push, step, body and latch blocks.
    parts: Parts,
};

const Parts = struct { index: ir.Ref, condition: ir.Ref, read: ir.Ref, push: ir.Ref, step: ir.Ref, body: u32, latch: u32 };

/// The copy loop `slice` heads, or null when `slice` is anything else.
fn matchCopy(f: *const ir.Function, graph: Graph, header: u32, slice: ir.Ref) ?Copy {
    const block = f.blocks.items[header];
    if (block.preds.items.len != 2) return null;
    const incoming = f.operands(f.inst(slice).data);
    const fresh_at: usize = for (incoming, 0..) |operand, i| {
        if (f.inst(f.resolve(operand)).op == .list_new) break i;
    } else return null;
    const fresh = f.resolve(incoming[fresh_at]);
    if (f.inst(fresh).data != 0 or graph.only(fresh) != slice) return null;
    const push = f.resolve(incoming[1 - fresh_at]);
    const pushed = f.inst(push);
    if (pushed.op != .list_push or pushed.data != 0 or f.resolve(pushed.a) != slice or graph.only(push) != slice) return null;
    const read = f.resolve(pushed.b);
    const got = f.inst(read);
    if (got.op != .list_get or got.data != 0 or graph.only(read) != push) return null;
    const index = f.resolve(got.b);
    const counter = f.inst(index);
    if (counter.op != .phi or graph.block_of[index.index()] != header or counter.ty != .i64) return null;
    const steps = f.operands(counter.data);
    const step = f.resolve(steps[1 - fresh_at]);
    const first = f.resolve(steps[fresh_at]);
    if (!isIncrement(f, step, index) or graph.only(step) != index) return null;
    // The header holds the two phis, the condition and the branch, nothing else.
    var condition: ir.Ref = .none;
    var terminator: ?ir.Inst = null;
    for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (ref == slice or ref == index or inst.op == .copy) continue;
        if (inst.op == .branch) {
            terminator = inst;
            continue;
        }
        if (inst.op != .cmp or condition != .none) return null;
        condition = ref;
    }
    const branch = terminator orelse return null;
    if (condition == .none or f.resolve(branch.a) != condition or graph.only(condition) == null) return null;
    const compare = f.inst(condition);
    if (@as(ir.Predicate, @fromBackingInt(@intCast(compare.data))) != .lt or f.resolve(compare.a) != index) return null;
    const targets = ir.unpackTargets(branch.data);
    const body: u32 = @backingInt(targets.then);
    const latch: u32 = @backingInt(block.preds.items[1 - fresh_at]);
    const parts: Parts = .{ .index = index, .condition = condition, .read = read, .push = push, .step = step, .body = body, .latch = latch };
    if (!loopIsCopyOnly(f, graph, header, parts)) return null;
    // The index's other users are the read, the condition and the step.
    for (graph.users[index.index()].items) |user| {
        if (user != read and user != condition and user != step) return null;
    }
    const source = f.resolve(got.a);
    if (graph.block_of[source.index()] == header or graph.block_of[source.index()] == body or graph.block_of[source.index()] == latch) return null;
    return .{ .header = header, .slice = slice, .fresh = fresh, .source = source, .first = first, .end = f.resolve(compare.b), .parts = parts };
}

fn isIncrement(f: *const ir.Function, step: ir.Ref, index: ir.Ref) bool {
    const inst = f.inst(step);
    if (inst.op != .add or f.resolve(inst.a) != index) return false;
    const one = f.inst(f.resolve(inst.b));
    return one.op == .iconst and one.data == 1;
}

/// Whether the loop body is the read, the push and the step (and jumps), in a body block
/// and an optional latch block, entered only from the header.
fn loopIsCopyOnly(f: *const ir.Function, graph: Graph, header: u32, parts: Parts) bool {
    const blocks = [2]u32{ parts.body, parts.latch };
    for (blocks, 0..) |b, i| {
        if (i == 1 and parts.latch == parts.body) break;
        const block = f.blocks.items[b];
        const entered_from: u32 = if (i == 0) header else parts.body;
        if (block.preds.items.len != 1 or @backingInt(block.preds.items[0]) != entered_from) return false;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (ref == parts.read or ref == parts.push or ref == parts.step or inst.op == .copy) continue;
            if (inst.op != .jump) return false;
            const next: u32 = @intCast(inst.data);
            const expected: u32 = if (i == 0 and parts.latch != parts.body) parts.latch else header;
            if (next != expected) return false;
        }
    }
    _ = graph;
    return true;
}

/// Whether the copy's endpoints lie in `[0, len(source)]`, as the builder's clamping
/// leaves them, so every index the copy reads is in bounds.
fn bounded(arena: std.mem.Allocator, f: *const ir.Function, copy: Copy) Error!bool {
    const ranges: Ranges = .{ .arena = arena, .f = f, .source = copy.source };
    const first = try ranges.within(copy.first, 0);
    const end = try ranges.within(copy.end, 0);
    return first and end;
}

/// Structural interval facts about the builder's endpoint clamps.
const Ranges = struct {
    arena: std.mem.Allocator,
    f: *const ir.Function,
    source: ir.Ref,

    const depth_limit = 8;

    fn within(self: Ranges, value: ir.Ref, depth: u32) Error!bool {
        const low = try self.atLeastZero(value, depth);
        const high = try self.atMostLength(value, depth);
        return low and high;
    }

    /// `convert(list_len(source))`: the source's length as an `i64`.
    fn isLength(self: Ranges, raw: ir.Ref) bool {
        const inst = self.f.inst(self.f.resolve(raw));
        if (inst.op != .convert or inst.ty != .i64) return false;
        const len = self.f.inst(self.f.resolve(inst.a));
        return len.op == .list_len and self.f.resolve(len.a) == self.source;
    }

    fn atLeastZero(self: Ranges, raw: ir.Ref, depth: u32) Error!bool {
        const value = self.f.resolve(raw);
        const inst = self.f.inst(value);
        if (inst.op == .iconst) return @as(i64, @bitCast(inst.data)) >= 0;
        if (self.isLength(value)) return true;
        if (inst.op != .phi or depth > depth_limit) return false;
        if (self.guarded(value, .lt)) |guard| {
            // `x < 0 ? z : x`: `x` reaches the join only when it is not negative.
            if (try self.atLeastZero(guard.replacement, depth + 1)) return true;
        }
        for (self.f.operands(inst.data)) |operand| {
            if (!try self.atLeastZero(operand, depth + 1)) return false;
        }
        return true;
    }

    fn atMostLength(self: Ranges, raw: ir.Ref, depth: u32) Error!bool {
        const value = self.f.resolve(raw);
        const inst = self.f.inst(value);
        if (inst.op == .iconst) return @as(i64, @bitCast(inst.data)) <= 0;
        if (self.isLength(value)) return true;
        if (inst.op != .phi or depth > depth_limit) return false;
        if (self.guarded(value, .gt)) |guard| {
            // `x > len ? len : x`: `x` reaches the join only when it is at most the length.
            if (self.isLength(guard.bound) and try self.atMostLength(guard.replacement, depth + 1)) return true;
        }
        for (self.f.operands(inst.data)) |operand| {
            if (!try self.atMostLength(operand, depth + 1)) return false;
        }
        return true;
    }

    const Guard = struct { bound: ir.Ref, replacement: ir.Ref };

    /// A join `phi(x, r)` of a diamond whose head branches on `x <predicate> bound`: the
    /// branch's taken edge goes through a block of its own that yields `r`, the other
    /// edge brings `x` straight to the join.
    fn guarded(self: Ranges, phi: ir.Ref, predicate: ir.Predicate) ?Guard {
        const f = self.f;
        const join: u32 = blk: {
            for (f.blocks.items, 0..) |block, b| {
                if (std.mem.indexOfScalar(ir.Ref, block.insts.items, phi) != null) break :blk @intCast(b);
            }
            return null;
        };
        const preds = f.blocks.items[join].preds.items;
        const incoming = f.operands(f.inst(phi).data);
        if (preds.len != 2 or incoming.len != 2) return null;
        for (0..2) |side| {
            const head: u32 = @backingInt(preds[side]);
            const arm: u32 = @backingInt(preds[1 - side]);
            const arm_block = f.blocks.items[arm];
            if (arm_block.preds.items.len != 1 or @backingInt(arm_block.preds.items[0]) != head) continue;
            const head_insts = f.blocks.items[head].insts.items;
            if (head_insts.len == 0) continue;
            const branch = f.inst(head_insts[head_insts.len - 1]);
            if (branch.op != .branch) continue;
            const targets = ir.unpackTargets(branch.data);
            if (@backingInt(targets.then) != arm or @backingInt(targets.otherwise) != join) continue;
            const condition = f.inst(f.resolve(branch.a));
            if (condition.op != .cmp or @as(ir.Predicate, @fromBackingInt(@intCast(condition.data))) != predicate) continue;
            const kept = f.resolve(incoming[side]);
            if (f.resolve(condition.a) != kept) continue;
            if (predicate == .lt) {
                const zero = f.inst(f.resolve(condition.b));
                if (zero.op != .iconst or zero.data != 0) continue;
            }
            return .{ .bound = f.resolve(condition.b), .replacement = f.resolve(incoming[1 - side]) };
        }
        return null;
    }
};

/// The counted loop that reads the slice: `j` from 0 while `j < len(slice)`.
const Consumer = struct {
    index: ir.Ref,
    /// The position of the loop's entry edge among the header's predecessors.
    entry: usize,
    condition: ir.Ref,
    length: ir.Ref,
    wide: ir.Ref,
    reads: []const ir.Ref,
};

/// The loop that only reads `copy.slice` element by element, when the source cannot
/// change while it runs.
fn matchLoop(arena: std.mem.Allocator, f: *const ir.Function, graph: Graph, copy: Copy) Error!?Consumer {
    var length: ir.Ref = .none;
    var reads: std.ArrayList(ir.Ref) = .empty;
    for (graph.users[copy.slice.index()].items) |user| {
        if (user == copy.parts.push) continue;
        const inst = f.inst(user);
        switch (inst.op) {
            .list_len => {
                if (length != .none) return null;
                length = user;
            },
            .list_get, .list_get_field => {
                if (inst.op == .list_get and inst.data != 0) return null;
                if (f.resolve(inst.a) != copy.slice) return null;
                try reads.append(arena, user);
            },
            else => return null,
        }
    }
    if (length == .none or reads.items.len == 0) return null;
    const wide = graph.only(length) orelse return null;
    const widened = f.inst(wide);
    if (widened.op != .convert or widened.ty != .i64) return null;
    const condition = graph.only(wide) orelse return null;
    const compare = f.inst(condition);
    if (compare.op != .cmp or @as(ir.Predicate, @fromBackingInt(@intCast(compare.data))) != .lt or f.resolve(compare.b) != wide) return null;
    const index = f.resolve(compare.a);
    const counter = f.inst(index);
    const header = graph.block_of[index.index()];
    if (counter.op != .phi or counter.ty != .i64 or header == Graph.none) return null;
    const preds = f.blocks.items[header].preds.items;
    const incoming = f.operands(counter.data);
    if (preds.len != 2 or incoming.len != 2 or graph.block_of[condition.index()] != header) return null;
    // The entry edge brings 0, the latch the step.
    const entry: usize = for (incoming, 0..) |operand, i| {
        const start = f.inst(f.resolve(operand));
        if (start.op == .iconst and start.data == 0) break i;
    } else return null;
    const step = f.resolve(incoming[1 - entry]);
    if (!isIncrement(f, step, index) or graph.only(step) != index) return null;
    for (graph.users[index.index()].items) |user| {
        if (user == condition or user == step) continue;
        if (std.mem.indexOfScalar(ir.Ref, reads.items, user) == null) return null;
    }
    for (reads.items) |read| if (f.resolve(f.inst(read).b) != index) return null;
    const latch: u32 = @backingInt(preds[1 - entry]);
    const body = try loopBlocks(arena, f, header, latch);
    // Everything from the copy to the loop counts too: a change of the source there would
    // reach the loop's reads as well.
    const before = try loopBlocks(arena, f, copy.header, @backingInt(preds[entry]));
    const after = try reachedFrom(arena, f, copy.header);
    for (body, before, after) |*member, back, forward| member.* = member.* or (back and forward);
    if (!try sourceUnchanged(f, copy.source, body)) return null;
    return .{ .index = index, .entry = entry, .condition = condition, .length = length, .wide = wide, .reads = reads.items };
}

/// The blocks of the loop `header` heads whose back edge comes from `latch`: the header
/// and every block that reaches the latch without passing the header.
fn loopBlocks(arena: std.mem.Allocator, f: *const ir.Function, header: u32, latch: u32) Error![]bool {
    const member = try arena.alloc(bool, f.blocks.items.len);
    @memset(member, false);
    member[header] = true;
    var stack: std.ArrayList(u32) = .empty;
    if (!member[latch]) {
        member[latch] = true;
        try stack.append(arena, latch);
    }
    while (stack.pop()) |b| {
        for (f.blocks.items[b].preds.items) |pred_id| {
            const pred = @backingInt(pred_id);
            if (member[pred]) continue;
            member[pred] = true;
            try stack.append(arena, pred);
        }
    }
    return member;
}

// twin-drift-ok: own.blockReachable answers one target and stops at a definition;
// this one collects every block `start` reaches.
/// The blocks reachable from `start`.
fn reachedFrom(arena: std.mem.Allocator, f: *const ir.Function, start: u32) Error![]bool {
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    seen[start] = true;
    try stack.append(arena, start);
    while (stack.pop()) |b| {
        for (own.successors(f, b).slice()) |succ| {
            if (seen[succ]) continue;
            seen[succ] = true;
            try stack.append(arena, succ);
        }
    }
    return seen;
}

/// Whether nothing in the loop can change or take the source list: inside it, the source
/// is only measured and read (no update, store, call, return or join takes it).
fn sourceUnchanged(f: *const ir.Function, source: ir.Ref, body: []const bool) Error!bool {
    for (f.blocks.items, 0..) |block, b| {
        if (!body[b]) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            if (inst.op == .phi) {
                for (f.operands(inst.data)) |operand| if (f.resolve(operand) == source) return false;
                continue;
            }
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |k| {
                if (f.resolve(operands.get(k)) != source) continue;
                const reads = switch (inst.op) {
                    .list_len, .list_get, .list_get_field => k == 0,
                    else => false,
                };
                if (!reads) return false;
            }
        }
    }
    return true;
}

/// Count the consumer from `first` to `last` over the source and drop the copy loop.
fn iterateSource(arena: std.mem.Allocator, f: *ir.Function, copy: Copy, consumer: Consumer) Error!void {
    const counter = f.inst(consumer.index);
    const slice = ir.ExtraSlice.unpack(counter.data);
    f.extra.items[slice.start + consumer.entry] = copy.first;
    f.insts.items[consumer.condition.index()].b = copy.end;
    for (consumer.reads) |read| f.insts.items[read.index()].a = copy.source;
    try remove(arena, f, &.{ consumer.length, consumer.wide });
    // The copy loop: its header jumps straight to the exit; its body and latch go.
    const header = &f.blocks.items[copy.header];
    const terminator_ref = header.insts.items[header.insts.items.len - 1];
    const terminator = f.inst(terminator_ref);
    const exit = ir.unpackTargets(terminator.data).otherwise;
    f.insts.items[terminator_ref.index()] = .{ .op = .jump, .ty = .void, .data = @backingInt(exit), .span = terminator.span };
    const latch: ir.BlockId = @fromBackingInt(copy.parts.latch);
    var kept_preds: std.ArrayList(ir.BlockId) = .empty;
    for (header.preds.items) |pred| if (pred != latch) try kept_preds.append(arena, pred);
    header.preds = kept_preds;
    for ([_]u32{ copy.parts.body, copy.parts.latch }) |b| {
        f.blocks.items[b].insts = .empty;
        f.blocks.items[b].preds = .empty;
    }
    try remove(arena, f, &.{ copy.slice, copy.parts.index, copy.parts.condition, copy.fresh });
    var recorded: std.ArrayList(ir.Loop) = .empty;
    for (f.loops.items) |loop| if (@backingInt(loop.header) != copy.header) try recorded.append(arena, loop);
    f.loops = recorded;
}

/// Take `refs` out of whatever blocks hold them.
fn remove(arena: std.mem.Allocator, f: *ir.Function, refs: []const ir.Ref) Error!void {
    for (f.blocks.items) |*block| {
        var kept: std.ArrayList(ir.Ref) = .empty;
        var dropped = false;
        for (block.insts.items) |ref| {
            if (std.mem.indexOfScalar(ir.Ref, refs, ref) != null) {
                dropped = true;
                continue;
            }
            try kept.append(arena, ref);
        }
        if (dropped) block.insts = kept;
    }
}

/// Give the copy room for exactly its elements, `max(last - first, 0)`, when both
/// endpoints are defined ahead of its allocation.
fn sizeExactly(arena: std.mem.Allocator, f: *ir.Function, graph: Graph, copy: Copy) Error!bool {
    const home = graph.block_of[copy.fresh.index()];
    if (home == Graph.none) return false;
    for ([_]ir.Ref{ copy.first, copy.end }) |endpoint| {
        if (!try definedAhead(arena, f, graph, endpoint, copy.fresh)) return false;
    }
    const span = f.inst(copy.fresh).span;
    const difference = try newInst(arena, f, .{ .op = .sub, .ty = .i64, .a = copy.end, .b = copy.first, .span = span });
    const sign = try newInst(arena, f, .{ .op = .shift_right, .ty = .i64, .a = difference, .b = try constant(arena, f, .i64, 63), .span = span });
    const keep = try newInst(arena, f, .{ .op = .bit_xor, .ty = .i64, .a = sign, .b = try constant(arena, f, .i64, -1), .span = span });
    const count = try newInst(arena, f, .{ .op = .bit_and, .ty = .i64, .a = difference, .b = keep, .span = span });
    const capacity = try newInst(arena, f, .{ .op = .convert, .ty = .u64, .a = count, .span = span });
    const insts = &f.blocks.items[home].insts;
    const at = std.mem.indexOfScalar(ir.Ref, insts.items, copy.fresh).?;
    try insts.insertSlice(arena, at, &.{ difference, sign, keep, count, capacity });
    f.insts.items[copy.fresh.index()].a = capacity;
    return true;
}

/// Whether `value` is available where `user` runs: a constant or parameter, an earlier
/// instruction of the user's block, or one in a block every path to it passes.
fn definedAhead(arena: std.mem.Allocator, f: *const ir.Function, graph: Graph, value: ir.Ref, user: ir.Ref) Error!bool {
    if (f.inst(value).op.isConstant()) return true;
    const home = graph.block_of[value.index()];
    const target = graph.block_of[user.index()];
    if (home == Graph.none) return false;
    if (home == target) {
        const insts = f.blocks.items[home].insts.items;
        return std.mem.indexOfScalar(ir.Ref, insts, value).? < std.mem.indexOfScalar(ir.Ref, insts, user).?;
    }
    return own.dominatesBlock(arena, f, home, target);
}

fn newInst(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}

fn constant(arena: std.mem.Allocator, f: *ir.Function, ty: ir.Type, value: i64) Error!ir.Ref {
    return newInst(arena, f, .{ .op = .iconst, .ty = ty, .data = @bitCast(value) });
}
