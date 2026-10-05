//! Uniqueness before in-place list updates (docs/design/new-core-ir.md §6).
//!
//! `list_push` appends in place, and the runtime may free the old block when it
//! grows, so its operand must be the only live reference to that block. Lists are
//! values: `copy = xs; copy.append(v)` must leave `xs` (here a parameter, whose
//! block the caller still holds) unchanged. Until the S1 ownership pass (one count,
//! borrows, last-use moves) replaces it, this pass inserts a `list_copy` in front
//! of every push whose operand is not provably unique:
//! - its storage was created in this function (`list_new`, `list_push`,
//!   `list_copy`, or phis of those), and
//! - no value that may share that storage is used after the push, on any path
//!   that does not first define that value again.
//! Parameters, call results and anything else are never unique here.
const std = @import("std");
const ir = @import("ir.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// Whether `op` updates its list operand's block in place: a push, an element
/// write or a pop (until the S1 ownership pass, every in-place update is treated as a push).
fn inPlace(op: ir.Op) bool {
    return op == .list_push or op == .list_set or op == .list_pop;
}

/// Insert a `list_copy` before every in-place list update (`list_push`, `list_set`,
/// `list_pop`) whose operand may be shared; returns how many it inserted.
pub fn copyShared(arena: std.mem.Allocator, f: *ir.Function) Error!u32 {
    var inserted: u32 = 0;
    for (0..f.blocks.items.len) |b| {
        var position: usize = 0;
        while (position < f.blocks.items[b].insts.items.len) : (position += 1) {
            const ref = f.blocks.items[b].insts.items[position];
            const push = f.inst(ref);
            if (!inPlace(push.op)) continue;
            const block: ir.BlockId = @fromBackingInt(@intCast(b));
            if (try unique(arena, f, f.resolve(push.a), .{ .block = block, .position = position, .push = ref })) continue;
            const copy: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
            try f.insts.append(arena, .{ .op = .list_copy, .ty = push.ty, .a = push.a, .span = push.span });
            try f.blocks.items[b].insts.insert(arena, position, copy);
            f.insts.items[ref.index()].a = copy;
            position += 1;
            inserted += 1;
        }
    }
    return inserted;
}

/// Where a push sits.
const Site = struct { block: ir.BlockId, position: usize, push: ir.Ref };

/// Whether the push at `site` may update `value`'s storage in place.
fn unique(arena: std.mem.Allocator, f: *const ir.Function, value: ir.Ref, site: Site) Error!bool {
    // Every value the operand may share storage with: itself and, through phis, its sources.
    var sharing: std.ArrayList(ir.Ref) = .empty;
    try sharing.append(arena, value);
    var next: usize = 0;
    while (next < sharing.items.len) : (next += 1) {
        const current = f.inst(sharing.items[next]);
        switch (current.op) {
            .list_new, .list_copy => {},
            // Its own storage is its operand's (consumed by that update), already a new instance here.
            .list_push, .list_set, .list_pop => {},
            .phi => for (f.operands(current.data)) |operand| {
                const source = f.resolve(operand);
                if (std.mem.indexOfScalar(ir.Ref, sharing.items, source) == null) try sharing.append(arena, source);
            },
            else => return false,
        }
    }
    for (sharing.items) |shared| {
        // The push's own result is a new instance: every later use reads it, not the consumed one.
        if (shared == site.push) continue;
        if (try liveAfter(arena, f, shared, site)) return false;
    }
    return true;
}

/// Whether `value` is used after the push at `site` on a path that does not pass its definition again.
fn liveAfter(arena: std.mem.Allocator, f: *const ir.Function, value: ir.Ref, site: Site) Error!bool {
    const count = f.blocks.items.len;
    const definition = blockOf(f, value);
    // Later instructions of the push's own block.
    for (f.blocks.items[site.block.index()].insts.items[site.position + 1 ..]) |ref| {
        if (uses(f, f.inst(ref), value)) return true;
    }
    if (try usedOnEdgeFrom(f, site.block, value)) return true;
    // Blocks reachable from the push's block without re-entering the definition's block.
    const seen = try arena.alloc(bool, count);
    @memset(seen, false);
    var stack: std.ArrayList(ir.BlockId) = .empty;
    try pushSuccessors(arena, f, site.block, definition, seen, &stack);
    while (stack.pop()) |block| {
        for (f.blocks.items[block.index()].insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .phi and uses(f, inst, value)) return true;
        }
        if (try usedOnEdgeFrom(f, block, value)) return true;
        try pushSuccessors(arena, f, block, definition, seen, &stack);
    }
    return false;
}

fn pushSuccessors(arena: std.mem.Allocator, f: *const ir.Function, block: ir.BlockId, definition: ?ir.BlockId, seen: []bool, stack: *std.ArrayList(ir.BlockId)) Error!void {
    const insts = f.blocks.items[block.index()].insts.items;
    if (insts.len == 0) return;
    const last = f.inst(insts[insts.len - 1]);
    var targets: [2]ir.BlockId = undefined;
    var len: usize = 0;
    switch (last.op) {
        .jump => {
            targets[0] = @fromBackingInt(@intCast(@as(u32, @truncate(last.data))));
            len = 1;
        },
        .branch => {
            const pair = ir.unpackTargets(last.data);
            targets = .{ pair.then, pair.otherwise };
            len = 2;
        },
        else => {},
    }
    for (targets[0..len]) |target| {
        if (seen[target.index()] or target == definition) continue;
        seen[target.index()] = true;
        try stack.append(arena, target);
    }
}

/// Whether a phi in a successor of `block` takes `value` on the edge from `block`.
fn usedOnEdgeFrom(f: *const ir.Function, block: ir.BlockId, value: ir.Ref) Error!bool {
    for (f.blocks.items) |successor| {
        for (successor.preds.items, 0..) |pred, i| {
            if (pred != block) continue;
            for (successor.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .phi) continue;
                if (f.resolve(f.operands(inst.data)[i]) == value) return true;
            }
        }
    }
    return false;
}

/// Whether `inst` (not a phi) reads `value`.
fn uses(f: *const ir.Function, inst: ir.Inst, value: ir.Ref) bool {
    if (inst.op == .phi) return false;
    const operands = f.valueOperands(inst);
    for (0..operands.len()) |i| if (f.resolve(operands.get(i)) == value) return true;
    return false;
}

/// The block that defines `value`, or null for a value outside every block (a parameter).
fn blockOf(f: *const ir.Function, value: ir.Ref) ?ir.BlockId {
    for (f.blocks.items, 0..) |block, b| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, value) != null) return @fromBackingInt(@intCast(b));
    }
    return null;
}
