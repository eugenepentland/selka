//! Takes before views (plan C9.9, docs/design/ownership-certificates.md entry 29): the lowering of a `mut` place argument
//! such as `append(mut rows[i], 9)` first evaluates the place as an expression, which reads the slot as a borrowed view, and
//! then, once every argument is evaluated, takes the same slot to pass its owner. Nobody reads the view: it is a dead borrow
//! of a value defined later in the block (a forward take), which the ownership checkers carry a rule for.
//!
//! This pass drops such a view. The take repeats the view's read (same operation, container, index and check), so the view
//! adds nothing but an earlier place for the failure. It is dropped only when nothing observable lies between the view and
//! the take (`fuse.inert`: no write, call, print, allocation or trap), so every failure and every effect of the program still
//! happens in the order it did. A path through several levels (`rows[i][j]`) is dropped whole or not at all.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const fuse = @import("fuse.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

const no_position = std.math.maxInt(u32);

/// Where an instruction sits: its block and its place in the block's list.
const Place = struct { block: u32 = no_position, at: u32 = no_position };

/// What the pass reads of one function: where each instruction sits and how many instructions read each value.
const Census = struct { places: []Place, uses: []u32 };

/// Drop every view of `f` that a take of the same slot follows; returns how many it dropped.
pub fn run(arena: std.mem.Allocator, f: *ir.Function) Error!u32 {
    const census = try count(arena, f);
    var dropped: u32 = 0;
    for (0..f.blocks.items.len) |b| dropped += try drop(arena, f, census, @intCast(b));
    return dropped;
}

/// Where each instruction sits, and how many instructions of `f` read each value (through forwarding copies).
fn count(arena: std.mem.Allocator, f: *const ir.Function) Error!Census {
    const places = try arena.alloc(Place, f.insts.items.len);
    @memset(places, .{});
    const uses = try arena.alloc(u32, f.insts.items.len);
    @memset(uses, 0);
    for (f.blocks.items, 0..) |blk, b| for (blk.insts.items, 0..) |ref, at| {
        places[ref.index()] = .{ .block = @intCast(b), .at = @intCast(at) };
        const inst = f.inst(ref);
        if (inst.op == .phi) {
            for (f.operands(inst.data)) |operand| uses[f.resolve(operand).index()] += 1;
            continue;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |k| {
            const operand = operands.get(k);
            if (operand != .none) uses[f.resolve(operand).index()] += 1;
        }
    };
    return .{ .places = places, .uses = uses };
}

/// The reads that project a part out of a container.
fn projection(op: ir.Op) bool {
    return switch (op) {
        .list_get, .list_get_field, .array_get, .dict_entry_value, .record_get, .box_get, .union_payload => true,
        else => false,
    };
}

/// Whether `take` reads the slot of `view` out of `parent`: the same operation, type, check and index, the same `data` apart from
/// the take mark (`flags.place_read`), and a container that is `parent` or a read of the same slot as `parent`.
fn repeats(f: *const ir.Function, view: ir.Inst, take: ir.Inst, parent: ir.Ref) bool {
    if (!sameSlot(view, take) or f.resolve(view.b) != f.resolve(take.b)) return false;
    return same(f, parent, take.a, 8);
}

/// The two reads have the same operation, type, check and `data` (apart from the take mark).
fn sameSlot(x: ir.Inst, y: ir.Inst) bool {
    return x.op == y.op and x.ty == y.ty and x.check == y.check and (x.data & ~flags.place_read) == (y.data & ~flags.place_read);
}

/// The two values are one value, or reads of the same slot of the same value: a value is immutable, so a read of it twice gives
/// the same result however far apart the reads are.
fn same(f: *const ir.Function, x: ir.Ref, y: ir.Ref, depth: u32) bool {
    const left = f.resolve(x);
    const right = f.resolve(y);
    if (left == right) return true;
    if (depth == 0 or left == .none or right == .none) return false;
    const a = f.inst(left);
    const b = f.inst(right);
    if (!projection(a.op) or !sameSlot(a, b)) return false;
    if (f.resolve(a.b) != f.resolve(b.b)) return false;
    return same(f, a.a, b.a, depth - 1);
}

/// Drop the views of block `b` that its takes repeat.
fn drop(arena: std.mem.Allocator, f: *ir.Function, census: Census, b: u32) Error!u32 {
    const insts = f.blocks.items[b].insts.items;
    const doomed = try arena.alloc(bool, insts.len);
    @memset(doomed, false);
    var dropped: u32 = 0;
    for (insts, 0..) |leaf_ref, leaf_at| {
        const leaf = f.inst(leaf_ref);
        if (doomed[leaf_at] or !unread(leaf, census.uses[leaf_ref.index()], 0)) continue;
        const chain = try views(arena, f, census, b, leaf_at);
        const takes = try repeated(arena, f, insts, chain) orelse continue;
        for (chain, takes) |at, take_at| {
            doomed[at] = true;
            // The take fails where the view would have: it reports the view's place in the source.
            f.insts.items[insts[take_at].index()].span = f.inst(insts[at]).span;
        }
        dropped += @intCast(chain.len);
    }
    if (dropped == 0) return 0;
    var kept: std.ArrayList(ir.Ref) = .empty;
    for (insts, 0..) |ref, at| {
        if (!doomed[at]) {
            try kept.append(arena, ref);
            continue;
        }
        // The instruction stays in the table, retired the way inlining retires a call whose result it splits: a void copy of nothing.
        // Left as it was, a dropped `record_get` would keep reading a value that a later pass rewrites by walking the blocks.
        f.insts.items[ref.index()] = .{ .op = .copy, .ty = .void, .span = f.insts.items[ref.index()].span };
    }
    f.blocks.items[b].insts.clearRetainingCapacity();
    f.blocks.items[b].insts.appendSliceAssumeCapacity(kept.items);
    return dropped;
}

/// Whether `inst` is a view that `readers` instructions read and that is not a take.
fn unread(inst: ir.Inst, readers: u32, expected: u32) bool {
    return projection(inst.op) and inst.data & flags.place_read == 0 and readers == expected;
}

/// The chain of views that ends at the unread view at `leaf_at`, each read only by the next, as positions in the block
/// (outermost first).
fn views(arena: std.mem.Allocator, f: *const ir.Function, census: Census, b: u32, leaf_at: usize) Error![]const u32 {
    var chain: std.ArrayList(u32) = .empty;
    try chain.append(arena, @intCast(leaf_at));
    var current = f.inst(f.blocks.items[b].insts.items[leaf_at]);
    while (chain.items.len < 8) {
        const parent = f.resolve(current.a);
        if (parent == .none) break;
        const place = census.places[parent.index()];
        if (place.block != b or place.at >= chain.items[chain.items.len - 1]) break;
        const inst = f.inst(parent);
        if (!unread(inst, census.uses[parent.index()], 1)) break;
        try chain.append(arena, place.at);
        current = inst;
    }
    std.mem.reverse(u32, chain.items);
    return chain.items;
}

/// The positions of the takes that follow the chain of views and repeat it level by level, when nothing observable lies between
/// the first view and the last take; null otherwise.
fn repeated(arena: std.mem.Allocator, f: *const ir.Function, insts: []const ir.Ref, chain: []const u32) Error!?[]const u32 {
    const takes = try arena.alloc(u32, chain.len);
    var from: usize = chain[chain.len - 1] + 1;
    var parent: ir.Ref = f.inst(insts[chain[0]]).a;
    for (chain, takes) |view_at, *take_at| {
        const view = f.inst(insts[view_at]);
        const found = for (insts[from..], from..) |candidate, at| {
            const take = f.inst(candidate);
            if (projection(take.op) and repeats(f, view, take, parent)) break at;
        } else return null;
        take_at.* = @intCast(found);
        from = found + 1;
        parent = insts[found];
    }
    var at: usize = chain[0] + 1;
    while (at < takes[takes.len - 1]) : (at += 1) {
        if (std.mem.indexOfScalar(u32, chain, @intCast(at)) != null or std.mem.indexOfScalar(u32, takes, @intCast(at)) != null) continue;
        if (!fuse.inert(f.inst(insts[at]), true)) return null;
    }
    return takes;
}
