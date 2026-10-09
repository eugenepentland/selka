//! Trip-count guards (docs/design/new-core-ir.md §5, runtime guards).
//!
//! A counted reduction `acc += s` with `s >= 0` is proven safe only when its trip
//! count is bounded well enough: `hi(acc0) + trips * hi(s) <= i64 max`. When the
//! static bound (the 2^47 list-length rule) is not enough, the loop is versioned:
//!
//! ```
//! preheader → guard: if bound < K + 1 → clone (checks proven under trips ≤ K)
//!                    else             → original (unchanged, exact checks)
//! ```
//!
//! with `K = (i64 max - hi(acc0)) / hi(s)`. The clone's header is dominated by the
//! guard's taken edge, so the next fact pass refines `bound <= K` there and proves
//! the reduction. Values the loop defines and later code reads are merged by new
//! phis in the exit block, which both copies reach. Only counted loops from 0
//! whose exit is reached from inside the loop alone are versioned.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const origins = @import("inline_origins.zig");
const index_keys = @import("index_keys.zig");
const flags = @import("flags.zig");

/// Versioning only allocates.
pub const Error = std.mem.Allocator.Error;

/// Version every reduction loop of `f` whose sum the facts could prove only under
/// a trip bound; returns how many loops were versioned. Run the fact pass again after.
pub fn versionReductions(arena: std.mem.Allocator, f: *ir.Function, known: facts.Facts, provenance: origins.Context) Error!u32 {
    var count: u32 = 0;
    for (known.counted) |counted| {
        const limit = tripLimit(f, known, counted) orelse continue;
        if (!try flat(arena, f, counted.loop)) continue;
        if (try version(arena, f, counted, limit, provenance)) count += 1;
    }
    return count;
}

/// Whether `loop`'s body makes no call and holds no other loop. Only such a body gains
/// from the clone: it saves one check per trip, which matters when LLVM can then
/// vectorize or unroll a small body, and nothing around a call or an inner loop, where
/// the duplicated code only changes LLVM's choices (a binary search called from a
/// versioned loop lost its conditional moves and ran 3.7 times slower).
fn flat(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop) Error!bool {
    const inside = try members(arena, f, loop);
    for (f.loops.items) |other| {
        if (other.header != loop.header and inside[other.header.index()]) return false;
    }
    for (inside, 0..) |member, b| {
        if (!member) continue;
        for (f.blocks.items[b].insts.items) |ref| switch (f.inst(ref).op) {
            .call, .call_indirect => return false,
            else => {},
        };
    }
    return true;
}

/// The largest trip count for which every reduction of the loop is safe, when
/// some reduction is not proven already; null when versioning cannot help.
fn tripLimit(f: *const ir.Function, known: facts.Facts, counted: facts.Counted) ?i128 {
    const start = f.inst(f.resolve(counted.start));
    if (start.op != .iconst or start.data != 0) return null;
    const header = f.blocks.items[counted.loop.header.index()];
    if (header.preds.items.len != 2) return null;
    const latch_index: usize = if (header.preds.items[0] == counted.loop.latch) 0 else 1;
    var limit: ?i128 = null;
    for (header.insts.items) |ref| {
        const phi = f.inst(ref);
        if (phi.op != .phi or ref == counted.counter or phi.ty != .i64) continue;
        const operands = f.operands(phi.data);
        const update = f.inst(f.resolve(operands[latch_index]));
        if (update.op != .add or update.check != .exact) continue;
        const step = if (f.resolve(update.a) == ref) update.b else if (f.resolve(update.b) == ref) update.a else continue;
        const s = rangeOf(f, known, step) orelse return null;
        const init = rangeOf(f, known, operands[1 - latch_index]) orelse return null;
        if (s.lo < 0 or s.hi <= 0 or init.lo < 0) return null;
        const room = @as(i128, std.math.maxInt(i64)) - init.hi;
        if (room <= 0) return null;
        // One trip of slack: the facts bound the accumulator phi by its value after the
        // last trip, and the body adds one more summand to that bound.
        const bound = @divFloor(room, s.hi) - 1;
        limit = if (limit) |other| @min(other, bound) else bound;
    }
    const found = limit orelse return null;
    return if (found >= 1) @min(found, @as(i128, 1) << 62) else null;
}

fn rangeOf(f: *const ir.Function, known: facts.Facts, raw: ir.Ref) ?facts.Interval {
    const ref = f.resolve(raw);
    const inst = f.inst(ref);
    if (inst.op == .iconst) return facts.Interval.point(@as(i64, @bitCast(inst.data)));
    // An earlier copy in this pass may have added values the facts have not seen.
    if (ref.index() >= known.ranges.len) return null;
    return known.ranges[ref.index()];
}

/// The blocks of a loop: everything reachable from its body without passing its header or exit.
fn members(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop) Error![]bool {
    const inside = try arena.alloc(bool, f.blocks.items.len);
    @memset(inside, false);
    inside[loop.header.index()] = true;
    var pending: std.ArrayList(ir.BlockId) = .empty;
    try pending.append(arena, loop.body);
    while (pending.pop()) |block| {
        if (inside[block.index()] or block == loop.exit) continue;
        inside[block.index()] = true;
        const insts = f.blocks.items[block.index()].insts.items;
        const last = f.inst(insts[insts.len - 1]);
        switch (last.op) {
            .jump => try pending.append(arena, @fromBackingInt(@intCast(@as(u32, @intCast(last.data))))),
            .branch => {
                const targets = ir.unpackTargets(last.data);
                try pending.append(arena, targets.then);
                try pending.append(arena, targets.otherwise);
            },
            else => {},
        }
    }
    return inside;
}

fn appendInst(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}

fn packOperands(arena: std.mem.Allocator, f: *ir.Function, refs: []const ir.Ref) Error!u64 {
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(arena, refs);
    return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
}

/// The loop's preheader: the header's predecessor outside the loop, ending in a jump to it.
fn preheaderOf(f: *const ir.Function, loop: ir.Loop) ?ir.BlockId {
    const preds = f.blocks.items[loop.header.index()].preds.items;
    const index: usize = if (preds[0] == loop.latch) 1 else 0;
    const block = preds[index];
    const insts = f.blocks.items[block.index()].insts.items;
    if (f.inst(insts[insts.len - 1]).op != .jump) return null;
    return block;
}

fn version(arena: std.mem.Allocator, f: *ir.Function, counted: facts.Counted, limit: i128, provenance: origins.Context) Error!bool {
    const span = f.inst(f.blocks.items[counted.loop.header.index()].insts.items[0]).span;
    const cap = try appendInst(arena, f, .{ .op = .iconst, .ty = .i64, .data = @bitCast(@as(i64, @intCast(limit + 1))) });
    const condition = try appendInst(arena, f, .{ .op = .cmp, .ty = .bool, .a = f.resolve(counted.bound), .b = cap, .data = @backingInt(ir.Predicate.lt), .span = span });
    const anchor = f.blocks.items[counted.loop.header.index()].insts.items[0];
    const copies = try duplicate(arena, f, counted.loop, .{ .insts = &.{condition}, .condition = condition }, provenance, provenance.at(@intCast(counted.loop.header.index()), anchor));
    return copies != null;
}

/// The guard a loop copy is entered by: `insts`, appended instructions the guard block
/// holds in order, and `condition`, the one of them the guard branches on.
const Guard = struct { insts: []const ir.Ref, condition: ir.Ref };

/// Clone `loop` behind a guard block that evaluates `condition` and enters the clone
/// when it holds, the original otherwise. Returns the maps from original to clone,
/// or null (nothing changed) when the loop's shape does not allow it.
fn duplicate(arena: std.mem.Allocator, f: *ir.Function, loop: ir.Loop, guard_insts: Guard, provenance: origins.Context, frame: ?u32) Error!?Copies {
    const preheader = preheaderOf(f, loop) orelse return null;
    const inside = try members(arena, f, loop);
    // The exit may also be entered by earlier copies of this loop; it must be entered from it.
    var exits = false;
    for (f.blocks.items[loop.exit.index()].preds.items) |pred| exits = exits or inside[pred.index()];
    if (!exits) return null;
    const original_blocks = f.blocks.items.len;
    // Map loop blocks and instructions to their clones.
    const block_map = try arena.alloc(?ir.BlockId, original_blocks);
    @memset(block_map, null);
    for (0..original_blocks) |b| {
        if (!inside[b]) continue;
        block_map[b] = @fromBackingInt(@intCast(f.blocks.items.len));
        try f.blocks.append(arena, .{});
        try provenance.copyBlock(arena, @intCast(b), @intCast(block_map[b].?.index()));
    }
    const inst_map = try arena.alloc(ir.Ref, f.insts.items.len);
    @memset(inst_map, .none);
    for (0..original_blocks) |b| {
        if (!inside[b]) continue;
        for (f.blocks.items[b].insts.items) |ref| {
            inst_map[ref.index()] = try appendInst(arena, f, f.inst(ref));
            try provenance.copyInstruction(arena, ref, inst_map[ref.index()]);
        }
    }
    const mapRef = struct {
        fn of(function: *const ir.Function, map: []const ir.Ref, raw: ir.Ref) ir.Ref {
            if (raw == .none) return .none;
            const ref = function.resolve(raw);
            return if (ref.index() < map.len and map[ref.index()] != .none) map[ref.index()] else ref;
        }
    }.of;
    const mapBlock = struct {
        fn of(map: []const ?ir.BlockId, block: ir.BlockId) ir.BlockId {
            return if (block.index() < map.len) map[block.index()] orelse block else block;
        }
    }.of;
    // The guard block, between the preheader and the two copies, and the clone's own
    // preheader: one block whose single predecessor is the guard, so the guard's
    // taken edge dominates the clone and the facts refine the bound there.
    const guard: ir.BlockId = @fromBackingInt(@intCast(f.blocks.items.len));
    try f.blocks.append(arena, .{});
    const entry: ir.BlockId = @fromBackingInt(@intCast(f.blocks.items.len));
    try f.blocks.append(arena, .{});
    // The original keeps a preheader of its own too, ending in a jump, so it can be duplicated again.
    const stay: ir.BlockId = @fromBackingInt(@intCast(f.blocks.items.len));
    try f.blocks.append(arena, .{});
    for ([_]ir.BlockId{ guard, entry, stay }) |added| try provenance.setBlock(arena, @intCast(added.index()), frame);
    const header_span = f.inst(f.blocks.items[loop.header.index()].insts.items[0]).span;
    // Rewrite the clones' operands, targets and predecessors.
    for (0..original_blocks) |b| {
        const clone = block_map[b] orelse continue;
        var insts: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items[b].insts.items) |ref| {
            const new = inst_map[ref.index()];
            var inst = f.insts.items[new.index()];
            inst.a = if (inst.op == .call) inst.a else mapRef(f, inst_map, inst.a);
            inst.b = mapRef(f, inst_map, inst.b);
            if (inst.op.hasExtra()) {
                var operands: std.ArrayList(ir.Ref) = .empty;
                for (f.operands(inst.data)) |operand| try operands.append(arena, mapRef(f, inst_map, operand));
                inst.data = try packOperands(arena, f, operands.items);
            }
            switch (inst.op) {
                .jump => inst.data = @backingInt(mapBlock(block_map, @fromBackingInt(@intCast(@as(u32, @intCast(inst.data)))))),
                .branch => {
                    const targets = ir.unpackTargets(inst.data);
                    inst.data = ir.packTargets(mapBlock(block_map, targets.then), mapBlock(block_map, targets.otherwise));
                },
                else => {},
            }
            f.insts.items[new.index()] = inst;
            try insts.append(arena, new);
        }
        f.blocks.items[clone.index()].insts = insts;
        var preds: std.ArrayList(ir.BlockId) = .empty;
        for (f.blocks.items[b].preds.items) |pred| try preds.append(arena, if (pred == preheader) entry else mapBlock(block_map, pred));
        f.blocks.items[clone.index()].preds = preds;
    }
    // The original header is now entered through `stay`; the preheader jumps to the guard.
    for (f.blocks.items[loop.header.index()].preds.items) |*pred| {
        if (pred.* == preheader) pred.* = stay;
    }
    const pre_insts = f.blocks.items[preheader.index()].insts.items;
    f.insts.items[pre_insts[pre_insts.len - 1].index()].data = @backingInt(guard);
    const clone_header = block_map[loop.header.index()].?;
    const branch = try appendInst(arena, f, .{ .op = .branch, .ty = .void, .a = guard_insts.condition, .data = ir.packTargets(entry, stay), .span = header_span });
    try f.blocks.items[guard.index()].insts.appendSlice(arena, guard_insts.insts);
    try f.blocks.items[guard.index()].insts.append(arena, branch);
    try f.blocks.items[guard.index()].preds.append(arena, preheader);
    const enter = try appendInst(arena, f, .{ .op = .jump, .ty = .void, .data = @backingInt(clone_header), .span = header_span });
    try f.blocks.items[entry.index()].insts.append(arena, enter);
    try f.blocks.items[entry.index()].preds.append(arena, guard);
    const resume_original = try appendInst(arena, f, .{ .op = .jump, .ty = .void, .data = @backingInt(loop.header), .span = header_span });
    try f.blocks.items[stay.index()].insts.append(arena, resume_original);
    try f.blocks.items[stay.index()].preds.append(arena, guard);
    const copies: Copies = .{ .loop = loop, .inside = inside, .block_map = block_map, .inst_map = inst_map, .original_blocks = original_blocks };
    try mergeExit(arena, f, copies);
    try f.loops.append(arena, .{ .id = loop.id, .header = clone_header, .body = block_map[loop.body.index()].?, .latch = block_map[loop.latch.index()].?, .exit = loop.exit });
    return copies;
}

/// How many loop copies unswitching may add to one function.
const unswitch_budget = 16;

/// Loop unswitching: a branch inside an innermost loop whose condition compares
/// only values defined outside the loop (or constants) is decided once, before the
/// loop, by a guard; the clone takes the branch's then-side, the original its
/// else-side, each as a constant the fact pass folds. The compute benchmark's
/// per-element `if kind == …` dispatch becomes one straight loop per kind.
/// Returns how many loops were added.
pub fn unswitch(arena: std.mem.Allocator, f: *ir.Function, provenance: origins.Context) Error!u32 {
    var added: u32 = 0;
    var index: usize = 0;
    while (index < f.loops.items.len and added < unswitch_budget) : (index += 1) {
        while (added < unswitch_budget) {
            const loop = f.loops.items[index];
            if (try containsLoop(arena, f, loop)) break;
            const branch = (try invariantBranch(arena, f, loop)) orelse break;
            const condition = f.resolve(f.inst(branch).a);
            const cmp = f.inst(condition);
            const frame = provenance.at(blockOf(f, condition) orelse @intCast(loop.header.index()), condition);
            const copy_condition = try appendInst(arena, f, cmp);
            const copies = (try duplicate(arena, f, loop, .{ .insts = &.{copy_condition}, .condition = copy_condition }, provenance, frame)) orelse break;
            const yes = try appendInst(arena, f, .{ .op = .iconst, .ty = .bool, .data = 1 });
            const no = try appendInst(arena, f, .{ .op = .iconst, .ty = .bool, .data = 0 });
            f.insts.items[copies.inst_map[branch.index()].index()].a = yes;
            f.insts.items[branch.index()].a = no;
            added += 1;
        }
    }
    return added;
}

fn blockOf(f: *const ir.Function, ref: ir.Ref) ?u32 {
    for (f.blocks.items, 0..) |block, b| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref) != null) return @intCast(b);
    }
    return null;
}

/// Whether another recorded loop's header lies inside `loop` (it is not innermost).
fn containsLoop(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop) Error!bool {
    const inside = try members(arena, f, loop);
    for (f.loops.items) |other| {
        if (other.header != loop.header and inside[other.header.index()]) return true;
    }
    return false;
}

/// The first branch on a loop-invariant comparison in a block of `loop` that control
/// can still reach (constant branches are followed).
fn invariantBranch(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop) Error!?ir.Ref {
    const inside = try members(arena, f, loop);
    const defined = try arena.alloc(bool, f.insts.items.len);
    @memset(defined, false);
    for (f.blocks.items, 0..) |block, b| {
        if (!inside[b]) continue;
        for (block.insts.items) |ref| defined[ref.index()] = true;
    }
    const live = try arena.alloc(bool, f.blocks.items.len);
    @memset(live, false);
    var pending: std.ArrayList(ir.BlockId) = .empty;
    try pending.append(arena, loop.body);
    while (pending.pop()) |block| {
        if (live[block.index()] or !inside[block.index()] or block == loop.header) continue;
        live[block.index()] = true;
        const insts = f.blocks.items[block.index()].insts.items;
        const last = f.inst(insts[insts.len - 1]);
        switch (last.op) {
            .jump => try pending.append(arena, @fromBackingInt(@as(u32, @intCast(last.data)))),
            .branch => {
                const targets = ir.unpackTargets(last.data);
                const condition = f.inst(f.resolve(last.a));
                if (condition.op == .iconst) {
                    try pending.append(arena, if (condition.data != 0) targets.then else targets.otherwise);
                    continue;
                }
                const invariant = condition.op == .cmp and !isDefined(f, defined, condition.a) and !isDefined(f, defined, condition.b);
                if (invariant) return insts[insts.len - 1];
                try pending.append(arena, targets.then);
                try pending.append(arena, targets.otherwise);
            },
            else => {},
        }
    }
    return null;
}

fn isDefined(f: *const ir.Function, defined: []const bool, raw: ir.Ref) bool {
    const ref = f.resolve(raw);
    return ref.index() < defined.len and defined[ref.index()];
}

/// What `mergeExit` needs to know about one versioned loop.
const Copies = struct {
    loop: ir.Loop,
    inside: []const bool,
    block_map: []const ?ir.BlockId,
    inst_map: []const ir.Ref,
    original_blocks: usize,
};

/// Give the exit block the clone's edges and merge every value the loop defines that later code reads.
fn mergeExit(arena: std.mem.Allocator, f: *ir.Function, c: Copies) Error!void {
    const exit = c.loop.exit;
    const old_preds = try arena.dupe(ir.BlockId, f.blocks.items[exit.index()].preds.items);
    for (old_preds) |pred| {
        if (c.block_map[pred.index()]) |copy| try f.blocks.items[exit.index()].preds.append(arena, copy);
    }
    // Existing exit phis take the mapped operand on each new edge (edges from the loop only).
    for (f.blocks.items[exit.index()].insts.items) |ref| {
        const inst = f.insts.items[ref.index()];
        if (inst.op != .phi) continue;
        var operands: std.ArrayList(ir.Ref) = .empty;
        try operands.appendSlice(arena, f.operands(inst.data));
        for (f.operands(inst.data), old_preds) |operand, pred| {
            if (c.block_map[pred.index()] != null) try operands.append(arena, mapped(f, c.inst_map, operand));
        }
        f.insts.items[ref.index()].data = try packOperands(arena, f, operands.items);
    }
    // Values defined inside the original loop and read outside both copies.
    const inside_inst = try arena.alloc(bool, c.inst_map.len);
    @memset(inside_inst, false);
    for (0..c.original_blocks) |b| {
        if (!c.inside[b]) continue;
        for (f.blocks.items[b].insts.items) |ref| inside_inst[ref.index()] = true;
    }
    const merged = try arena.alloc(ir.Ref, c.inst_map.len);
    @memset(merged, .none);
    const uses: Uses = .{ .inside = inside_inst, .merged = merged };
    const block_count = f.blocks.items.len;
    for (0..block_count) |b| {
        const in_copy = (b < c.original_blocks and c.inside[b]) or b >= c.original_blocks;
        if (in_copy) continue;
        // `use` may add exit phis (growing the instruction, extra and block lists),
        // so work from a copy of the block's list and write back by index.
        const refs = try arena.dupe(ir.Ref, f.blocks.items[b].insts.items);
        for (refs) |ref| {
            const before = f.insts.items[ref.index()];
            const a = try use(arena, f, c, uses, before.a, before.op == .call);
            const second = try use(arena, f, c, uses, before.b, false);
            f.insts.items[ref.index()].a = a;
            f.insts.items[ref.index()].b = second;
            if (before.op == .phi and b == exit.index()) continue;
            if (before.op.hasExtra()) {
                const slice = ir.ExtraSlice.unpack(before.data);
                for (slice.start..slice.start + slice.len) |k| {
                    const value = try use(arena, f, c, uses, f.extra.items[k], false);
                    f.extra.items[k] = value;
                }
            }
        }
    }
}

fn mapped(f: *const ir.Function, map: []const ir.Ref, raw: ir.Ref) ir.Ref {
    if (raw == .none) return .none;
    const ref = f.resolve(raw);
    return if (ref.index() < map.len and map[ref.index()] != .none) map[ref.index()] else ref;
}

const Uses = struct { inside: []const bool, merged: []ir.Ref };

/// The value a use outside the loop reads: a loop-defined value becomes its exit phi.
fn use(arena: std.mem.Allocator, f: *ir.Function, c: Copies, uses: Uses, raw: ir.Ref, is_callee: bool) Error!ir.Ref {
    if (raw == .none or is_callee) return raw;
    const ref = f.resolve(raw);
    if (ref.index() >= uses.inside.len or !uses.inside[ref.index()]) return raw;
    if (uses.merged[ref.index()] != .none) return uses.merged[ref.index()];
    const exit = c.loop.exit;
    var operands: std.ArrayList(ir.Ref) = .empty;
    // Edges from an earlier copy of the loop never reach here: their uses were merged by
    // that copy's own exit phis, which are what later code reads.
    for (f.blocks.items[exit.index()].preds.items) |pred| {
        const from_clone = pred.index() >= c.original_blocks;
        try operands.append(arena, if (from_clone) c.inst_map[ref.index()] else ref);
    }
    const phi = try appendInst(arena, f, .{ .op = .phi, .ty = f.inst(ref).ty, .data = try packOperands(arena, f, operands.items) });
    try f.blocks.items[exit.index()].insts.insert(arena, 0, phi);
    uses.merged[ref.index()] = phi;
    return phi;
}

/// The most instructions a loop may hold to be versioned for its bounds checks: a clone of
/// a small body pays where LLVM can then unroll or vectorize it (NEW-CORE-FSX-VERSION-1).
const bounds_body_limit = 256;

/// Integers a bounds guard adds or subtracts lie in `[-limit, limit]`, so its sums are exact.
const bounds_value_limit: i128 = 1 << 60;

/// Bounds versioning (NEW-CORE-F2-VERSION-1): a counted loop `i = S, S + 1, …` while
/// `i < N`, whose small flat body checks list accesses at `I + i`, `i - I` or `I - i`, with
/// `I`, `S`, `N` and each list's length fixed for the whole loop, is cloned behind one guard
/// before it. The guard tests that every such index lies in `[0, len)` for every trip; the
/// clone runs with those checks proven (and a written index's normalization from the end
/// folded away), the original, unchanged, otherwise. Returns how many loops were versioned.
pub fn versionBounds(arena: std.mem.Allocator, f: *ir.Function, known: facts.Facts, options: BoundsOptions) Error!u32 {
    var count: u32 = 0;
    const loops = try arena.dupe(facts.Counted, known.counted);
    for (loops) |counted| {
        if (!try flat(arena, f, counted.loop)) continue;
        const plan = (try boundsPlan(arena, f, known, counted)) orelse continue;
        if (try versionPlan(arena, f, counted, plan, options)) count += 1;
    }
    return count;
}

/// Where cloned blocks come from, and the deliberately wrong rule for testing the verify
/// mode (`--sabotage-facts=version`: each guard admits one index past the end).
pub const BoundsOptions = struct { provenance: origins.Context, sabotage: bool = false };

/// How an access's index moves with the counter `i`: `I + i` (or `i` alone), `i - I`, `I - i`.
const IndexForm = enum { plus, counter_minus, minus_counter };

/// One access a bounds guard covers: the access, its index's form and invariant `I`
/// (`.none` for `i` alone), its list's length key, and the branch that normalizes a
/// written index from the end (`.none` when the index is not written).
const Covered = struct { access: ir.Ref, form: IndexForm, invariant: ir.Ref, length: index_keys.Key, normalize: ir.Ref, list_type: ir.Type };

/// The accesses of `counted`'s loop a guard can cover, or null when there are none or the
/// loop does not qualify.
fn boundsPlan(arena: std.mem.Allocator, f: *ir.Function, known: facts.Facts, counted: facts.Counted) Error!?Plan {
    const inside = try members(arena, f, counted.loop);
    var size: usize = 0;
    const defined = try arena.alloc(bool, f.insts.items.len);
    @memset(defined, false);
    for (inside, 0..) |member, b| if (member) for (f.blocks.items[b].insts.items) |ref| {
        defined[ref.index()] = true;
        size += 1;
    };
    if (size > bounds_body_limit) return null;
    const counter = f.resolve(counted.counter);
    const bound = f.resolve(counted.bound);
    const start = f.resolve(counted.start);
    if (f.inst(counter).ty != .i64 or f.inst(bound).ty != .i64 or f.inst(start).ty != .i64) return null;
    if (defined[bound.index()] or defined[start.index()]) return null;
    // Only loops that carry and leave nothing but scalars: a copy that carries a list or a record
    // out of the loop gives ownership joins to reason through (a function of such copies took
    // minutes to compile), and the loops that gain are reductions and searches.
    if (!scalarOnly(f, defined, counted.loop)) return null;
    // A trip count computed afresh in each pass of an enclosing loop (fannkuch's flips) is
    // data, often a few trips, which the guard's cost outweighs; a bound fixed for every
    // enclosing loop is the problem's size.
    if (try insideEnclosing(arena, f, counted.loop, bound)) return null;
    const shape = try facts.shape(arena, f);
    const keys = try index_keys.compute(arena, f, shape.rpo);
    var out: std.ArrayList(Covered) = .empty;
    for (inside, 0..) |member, b| if (member) for (f.blocks.items[b].insts.items) |ref| {
        const inst = f.inst(ref);
        switch (inst.op) {
            .list_get => if (inst.data == flags.pop_read or inst.data == flags.pop_index_read) continue,
            .list_get_field, .list_set, .list_set_field => {},
            else => continue,
        }
        if (inst.check != .exact) continue;
        const index = f.resolve(inst.b);
        const written: ?ir.Ref = if (shape.block_of[index.index()]) |join| facts.normalizedRaw(f, join, index) else null;
        var normalize: ir.Ref = .none;
        if (written != null) {
            normalize = normalizeBranch(f, shape, index) orelse continue;
            const test_block = shape.block_of[normalize.index()] orelse continue;
            if (!inside[test_block.index()]) continue;
        }
        // A normalization the facts folded away (the index is at least 0) is its written index.
        const seen = keys.value(written orelse index);
        if (seen.field != 0) continue;
        const form = indexForm(f, counter, seen.ref) orelse continue;
        if (form.invariant != .none and !hoistable(f, defined, form.invariant, 4)) continue;
        // The guard measures the list the loop is entered with, which it holds anyway: an
        // older value of the same length would live longer and could cost a copy on write.
        const entry = entryList(f, defined, counted.loop, inst.a) orelse continue;
        if (!std.meta.eql(keys.length(entry), keys.length(inst.a))) continue;
        try out.append(arena, .{ .access = ref, .form = form.form, .invariant = form.invariant, .length = .{ .ref = entry }, .normalize = normalize, .list_type = f.inst(entry).ty });
    };
    return if (out.items.len == 0) null else .{ .covered = out.items, .defined = defined, .known = known };
}

/// What a bounds guard covers: the accesses, the loop's own values, and the facts.
const Plan = struct { covered: []const Covered, defined: []const bool, known: facts.Facts };

/// The list value `raw` derives from as the loop is entered: itself when defined outside the
/// loop, else through element writes, copies and sorts back to the loop header phi, whose
/// operand from outside the loop it is. Null for any other derivation.
fn entryList(f: *const ir.Function, defined: []const bool, loop: ir.Loop, raw: ir.Ref) ?ir.Ref {
    var ref = f.resolve(raw);
    var steps: usize = 0;
    while (steps < 64) : (steps += 1) {
        if (ref.index() >= defined.len or !defined[ref.index()]) return ref;
        const inst = f.inst(ref);
        switch (inst.op) {
            .list_set, .list_set_field, .list_copy, .list_sort => ref = f.resolve(inst.a),
            .phi => {
                const header = f.blocks.items[loop.header.index()];
                if (std.mem.indexOfScalar(ir.Ref, header.insts.items, ref) == null) return null;
                const operands = f.operands(inst.data);
                if (operands.len != header.preds.items.len) return null;
                const outside = for (header.preds.items, 0..) |pred, k| {
                    if (pred != loop.latch) break k;
                } else return null;
                ref = f.resolve(operands[outside]);
            },
            else => return null,
        }
    }
    return null;
}

/// Whether every value `loop`'s header carries, and every value the loop defines that code
/// after it reads, is an integer, a float or a boolean.
fn scalarOnly(f: *const ir.Function, defined: []const bool, loop: ir.Loop) bool {
    for (f.blocks.items[loop.header.index()].insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .phi and !scalar(inst.ty)) return false;
    }
    for (f.blocks.items, 0..) |block, b| {
        if (b < defined.len and isLoopBlock(f, defined, b)) continue;
        for (block.insts.items) |ref| {
            const operands = f.valueOperands(f.inst(ref));
            for (0..operands.len()) |k| {
                const used = f.resolve(operands.get(k));
                if (used == .none or used.index() >= defined.len or !defined[used.index()]) continue;
                if (!scalar(f.inst(used).ty)) return false;
            }
        }
    }
    return true;
}

/// Whether block `b` holds an instruction of the loop (`defined` marks the loop's instructions).
fn isLoopBlock(f: *const ir.Function, defined: []const bool, b: usize) bool {
    const insts = f.blocks.items[b].insts.items;
    return insts.len != 0 and insts[0].index() < defined.len and defined[insts[0].index()];
}

fn scalar(ty: ir.Type) bool {
    return ty == .bool or ty == .f64 or ty.integer() != null;
}

/// Whether `raw` is defined inside a loop that encloses `loop`.
fn insideEnclosing(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop, raw: ir.Ref) Error!bool {
    const ref = f.resolve(raw);
    const shape = try facts.shape(arena, f);
    const home = shape.block_of[ref.index()] orelse return false;
    for (f.loops.items) |outer| {
        if (outer.header == loop.header) continue;
        const inside = try members(arena, f, outer);
        if (inside[loop.header.index()] and inside[home.index()]) return true;
    }
    return false;
}

/// Whether `raw` is fixed for the whole loop and can be computed before it: defined outside
/// the loop, or (within `depth` steps) an addition, subtraction or multiplication that cannot
/// trap (proven or unchecked) of such values.
fn hoistable(f: *const ir.Function, defined: []const bool, raw: ir.Ref, depth: u8) bool {
    const ref = f.resolve(raw);
    if (ref.index() >= defined.len or !defined[ref.index()]) return true;
    if (depth == 0) return false;
    const inst = f.inst(ref);
    const pure = inst.op == .add or inst.op == .sub or inst.op == .mul;
    if (!pure or inst.check == .exact or inst.ty != .i64) return false;
    return hoistable(f, defined, inst.a, depth - 1) and hoistable(f, defined, inst.b, depth - 1);
}

/// Whether the facts put an integer value well inside `i64` (`bounds_value_limit`).
fn small(f: *const ir.Function, known: facts.Facts, raw: ir.Ref) bool {
    const range = rangeOf(f, known, raw) orelse return false;
    return range.lo >= -bounds_value_limit and range.hi <= bounds_value_limit;
}

/// The branch that tests a written index `raw < 0` for the normalization phi `phi`.
fn normalizeBranch(f: *const ir.Function, shape: facts.Shape, phi: ir.Ref) ?ir.Ref {
    const join = shape.block_of[phi.index()] orelse return null;
    for (f.blocks.items[join.index()].preds.items) |pred| {
        const insts = f.blocks.items[pred.index()].insts.items;
        const last = insts[insts.len - 1];
        if (f.inst(last).op != .branch) continue;
        if (f.inst(f.resolve(f.inst(last).a)).op == .cmp) return last;
    }
    return null;
}

/// How `raw` moves with `counter`: the counter itself, a checked or proven sum or
/// difference of it and one other value, or null.
fn indexForm(f: *const ir.Function, counter: ir.Ref, raw: ir.Ref) ?struct { form: IndexForm, invariant: ir.Ref } {
    const ref = f.resolve(raw);
    if (ref == counter) return .{ .form = .plus, .invariant = .none };
    const inst = f.inst(ref);
    if ((inst.op != .add and inst.op != .sub) or inst.check == .none or inst.ty != .i64) return null;
    const a = f.resolve(inst.a);
    const b = f.resolve(inst.b);
    if (inst.op == .add) {
        if (a == counter and b != counter) return .{ .form = .plus, .invariant = b };
        if (b == counter and a != counter) return .{ .form = .plus, .invariant = a };
        return null;
    }
    if (a == counter and b != counter) return .{ .form = .counter_minus, .invariant = b };
    if (b == counter and a != counter) return .{ .form = .minus_counter, .invariant = a };
    return null;
}

/// Build the guard for `plan`, clone the loop behind it, and prove the covered accesses in the clone.
fn versionPlan(arena: std.mem.Allocator, f: *ir.Function, counted: facts.Counted, plan: Plan, options: BoundsOptions) Error!bool {
    const provenance = options.provenance;
    const span = f.inst(f.blocks.items[counted.loop.header.index()].insts.items[0]).span;
    var guard: GuardBuilder = .{ .arena = arena, .f = f, .span = span, .defined = plan.defined };
    const start = f.resolve(counted.start);
    const bound = f.resolve(counted.bound);
    const zero = try guard.constant(0);
    const one = try guard.constant(1);
    // The guard's sums are exact when every value it adds lies within the limit; a value the
    // facts do not bound so is tested at run time, and the guard fails if it lies outside.
    for ([_]ir.Ref{ start, bound }) |value| try guard.bounded(plan.known, value);
    for (plan.covered) |covered| {
        if (covered.invariant != .none) try guard.bounded(plan.known, covered.invariant);
    }
    for (plan.covered) |covered| {
        const len = try guard.length(covered.length, covered.list_type);
        // The least and the greatest index over the trips `start <= i <= bound - 1`.
        const least, const most_plus_one = switch (covered.form) {
            .plus => if (covered.invariant == .none) .{ start, bound } else .{ try guard.arith(.add, covered.invariant, start), try guard.arith(.add, covered.invariant, bound) },
            .counter_minus => .{ try guard.arith(.sub, start, covered.invariant), try guard.arith(.sub, bound, covered.invariant) },
            .minus_counter => .{ try guard.arith(.add, try guard.arith(.sub, covered.invariant, bound), one), try guard.arith(.add, try guard.arith(.sub, covered.invariant, start), one) },
        };
        try guard.require(.ge, least, zero);
        try guard.require(.le, most_plus_one, if (options.sabotage) try guard.arith(.add, len, one) else len);
    }
    const condition = guard.condition orelse return false;
    const anchor = f.blocks.items[counted.loop.header.index()].insts.items[0];
    const copies = (try duplicate(arena, f, counted.loop, .{ .insts = guard.insts.items, .condition = condition }, provenance, provenance.at(@intCast(counted.loop.header.index()), anchor))) orelse return false;
    const no = try appendInst(arena, f, .{ .op = .iconst, .ty = .bool, .data = 0 });
    for (plan.covered) |covered| {
        f.insts.items[copies.inst_map[covered.access.index()].index()].check = .proven;
        // In the clone every covered index is at least 0: its normalization from the end never runs.
        if (covered.normalize != .none) f.insts.items[copies.inst_map[covered.normalize.index()].index()].a = no;
    }
    return true;
}

/// The instructions of a bounds guard, appended to the function in order; `condition` is
/// the conjunction so far.
const GuardBuilder = struct {
    arena: std.mem.Allocator,
    f: *ir.Function,
    span: u32,
    /// The loop's own instructions: an invariant defined there is recomputed in the guard.
    defined: []const bool,
    insts: std.ArrayList(ir.Ref) = .empty,
    condition: ?ir.Ref = null,

    fn add(self: *GuardBuilder, inst: ir.Inst) Error!ir.Ref {
        var placed = inst;
        placed.span = self.span;
        const ref = try appendInst(self.arena, self.f, placed);
        try self.insts.append(self.arena, ref);
        return ref;
    }

    fn constant(self: *GuardBuilder, value: i64) Error!ir.Ref {
        return appendInst(self.arena, self.f, .{ .op = .iconst, .ty = .i64, .data = @bitCast(value) });
    }

    /// `a op b`, unchecked: exact whenever the guard's limit tests pass, and only then read.
    fn arith(self: *GuardBuilder, op: ir.Op, a: ir.Ref, b: ir.Ref) Error!ir.Ref {
        return self.add(.{ .op = op, .ty = .i64, .a = try self.hoist(a), .b = try self.hoist(b) });
    }

    /// `raw` where the guard runs: itself when defined outside the loop, else its computation
    /// (`hoistable`) repeated in the guard, unchecked.
    fn hoist(self: *GuardBuilder, raw: ir.Ref) Error!ir.Ref {
        const ref = self.f.resolve(raw);
        if (ref.index() >= self.defined.len or !self.defined[ref.index()]) return ref;
        const inst = self.f.inst(ref);
        return self.add(.{ .op = inst.op, .ty = inst.ty, .a = try self.hoist(inst.a), .b = try self.hoist(inst.b) });
    }

    /// Require `value` within `bounds_value_limit` unless the facts already put it there.
    fn bounded(self: *GuardBuilder, known: facts.Facts, value: ir.Ref) Error!void {
        if (small(self.f, known, value)) return;
        const at = try self.hoist(value);
        try self.require(.ge, at, try self.constant(@intCast(-bounds_value_limit)));
        try self.require(.le, at, try self.constant(@intCast(bounds_value_limit)));
    }

    /// The length, as `i64`, of the lists with length key `key`, of type `list_type`.
    fn length(self: *GuardBuilder, key: index_keys.Key, list_type: ir.Type) Error!ir.Ref {
        const list = if (key.field == 0) key.ref else try self.add(.{ .op = .record_get, .ty = list_type, .a = key.ref, .data = key.field - 1 });
        const raw = try self.add(.{ .op = .list_len, .ty = .u64, .a = list });
        return self.add(.{ .op = .convert, .ty = .i64, .a = raw, .check = .proven });
    }

    /// And `a predicate b` into the condition.
    fn require(self: *GuardBuilder, predicate: ir.Predicate, a: ir.Ref, b: ir.Ref) Error!void {
        const test_ref = try self.add(.{ .op = .cmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(predicate) });
        self.condition = if (self.condition) |so_far| try self.add(.{ .op = .bit_and, .ty = .bool, .a = so_far, .b = test_ref }) else test_ref;
    }
};
