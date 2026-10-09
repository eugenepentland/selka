//! Bounds checks an earlier check already made (lane F2, NEW-CORE-F2-INDEX-3).
//!
//! An access whose check passed (or that the facts proved) shows its index in range for
//! its list's length: a plain index in `[0, len)`, an index the program wrote and the
//! builder normalized from the end (`facts.normalizedRaw`) in `[-len, len)`. A later
//! access that it dominates, whose index has the same key and whose list has the same
//! length key (`index_keys`), cannot fail: a plain index after a plain one, a written one
//! after either. Both keys name SSA values, so between the two accesses neither value
//! changed (the dominating access's block lies on every path from their definitions to
//! the later access).
//!
//! The pass runs after ownership, which splits a whole-element write into a read and a
//! field write of the same element and copies a shared list before writing it; the
//! copy keeps the list's length.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const index_keys = @import("index_keys.zig");
const flags = @import("flags.zig");

/// What one access's check shows and needs: its index key, the length key of its list,
/// whether its check shows the index non-negative (a plain index's does; a written one may
/// count from the end), and whether a check covering it must show that.
const Shown = struct { index: index_keys.IndexKey, length: index_keys.Key, shows_sign: bool, needs_sign: bool };

/// Mark every list access a dominating access's check covers as `proven`; returns how many.
/// `sabotage` (`--sabotage-facts=index`) also takes a check to cover the next index up,
/// a deliberately wrong rule for testing the verify mode.
pub fn run(arena: std.mem.Allocator, f: *ir.Function, known: ?*const facts.Facts, sabotage: bool) std.mem.Allocator.Error!u32 {
    const shape = try facts.shape(arena, f);
    const keys = try index_keys.compute(arena, f, shape.rpo);
    // Children in the dominator tree, for a preorder walk that keeps a scoped list of checks.
    const children = try arena.alloc(std.ArrayList(ir.BlockId), f.blocks.items.len);
    for (children) |*list| list.* = .empty;
    for (shape.rpo) |block| {
        if (block.index() == 0) continue;
        const parent = shape.idom[block.index()] orelse continue;
        try children[parent.index()].append(arena, block);
    }
    var shown: std.ArrayList(Shown) = .empty;
    var proven: u32 = 0;
    var stack: std.ArrayList(struct { block: ir.BlockId, mark: usize, entered: bool }) = .empty;
    try stack.append(arena, .{ .block = @fromBackingInt(0), .mark = 0, .entered = false });
    while (stack.items.len != 0) {
        const top = &stack.items[stack.items.len - 1];
        if (top.entered) {
            shown.shrinkRetainingCapacity(top.mark);
            _ = stack.pop();
            continue;
        }
        top.entered = true;
        top.mark = shown.items.len;
        const block = top.block;
        for (f.blocks.items[block.index()].insts.items) |ref| {
            const access = accessOf(f, &shape, &keys, known, ref) orelse continue;
            const inst = &f.insts.items[ref.index()];
            if (inst.check == .exact and covered(shown.items, access, sabotage)) {
                inst.check = .proven;
                proven += 1;
            }
            try shown.append(arena, access);
        }
        for (children[block.index()].items) |child| try stack.append(arena, .{ .block = child, .mark = 0, .entered = false });
    }
    // Checks made on every edge into a loop header before an access that reads the header's
    // phi (NEW-CORE-F2-INDEX-5).
    const scope: Scope = .{ .f = f, .shape = &shape, .keys = &keys, .known = known, .sabotage = sabotage };
    for (shape.rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
        if (f.inst(ref).check != .exact) continue;
        const access = accessOf(f, &shape, &keys, known, ref) orelse continue;
        if (!scope.everyEdge(access, block)) continue;
        f.insts.items[ref.index()].check = .proven;
        proven += 1;
    };
    return proven;
}

/// What the edge rule reads.
const Scope = struct {
    f: *const ir.Function,
    shape: *const facts.Shape,
    keys: *const index_keys.Keys,
    known: ?*const facts.Facts,
    sabotage: bool,

    /// Whether an access whose list's length key and index key both name one phi `p` (a field of
    /// it, or `p` itself) is covered on every edge into `p`'s block, which dominates the access:
    /// on the edge from each predecessor, by a check made in that predecessor or a block
    /// dominating it, with the keys the phi's operand on that edge gives. Entering the block,
    /// the phi is that operand, and nothing defines it again before the access.
    fn everyEdge(self: Scope, access: Shown, block: ir.BlockId) bool {
        const phi = access.length.ref;
        if (phi == .none or access.index.base.ref != phi) return false;
        if (self.f.inst(phi).op != .phi) return false;
        const header = self.shape.block_of[phi.index()] orelse return false;
        if (!self.dominates(header, block)) return false;
        const preds = self.f.blocks.items[header.index()].preds.items;
        const operands = self.f.operands(self.f.inst(phi).data);
        if (preds.len == 0 or preds.len != operands.len) return false;
        for (preds, operands) |pred, operand| {
            var moved = access;
            moved.length = self.translate(access.length, operand, true);
            moved.index.base = self.translate(access.index.base, operand, false);
            if (!self.availableAt(pred, moved)) return false;
        }
        return true;
    }

    /// `key`, a field of the phi or the phi itself, with the phi replaced by `operand`: as a
    /// length key when `length`, else as a value key.
    fn translate(self: Scope, key: index_keys.Key, operand: ir.Ref, length: bool) index_keys.Key {
        if (key.field == 0) return if (length) self.keys.length(operand) else self.keys.value(operand);
        const field = self.keys.fieldOf(operand, key.field - 1);
        if (!length or field.field != 0) return field;
        return self.keys.length(field.ref);
    }

    /// Whether a check made in `pred` or a block dominating it covers `access`.
    fn availableAt(self: Scope, pred: ir.BlockId, access: Shown) bool {
        if (self.shape.order[pred.index()] == std.math.maxInt(u32)) return false;
        var current: ?ir.BlockId = pred;
        var steps: usize = 0;
        while (current) |block| : (steps += 1) {
            if (steps > self.f.blocks.items.len) return false;
            for (self.f.blocks.items[block.index()].insts.items) |ref| {
                const earlier = accessOf(self.f, self.shape, self.keys, self.known, ref) orelse continue;
                if (covered(&.{earlier}, access, self.sabotage)) return true;
            }
            if (block.index() == 0) return false;
            current = self.shape.idom[block.index()];
        }
        return false;
    }

    fn dominates(self: Scope, a: ir.BlockId, b: ir.BlockId) bool {
        var current: ?ir.BlockId = b;
        var steps: usize = 0;
        while (current) |block| : (steps += 1) {
            if (steps > self.f.blocks.items.len) return false;
            if (block == a) return true;
            if (block.index() == 0) return false;
            current = self.shape.idom[block.index()];
        }
        return false;
    }
};

/// What a list access's check shows, or null for any other instruction (and for the reads
/// a pop starts with, whose index is the list's own last). An index the facts put at or
/// above zero needs no covering check to show its sign.
fn accessOf(f: *const ir.Function, shape: *const facts.Shape, keys: *const index_keys.Keys, known: ?*const facts.Facts, ref: ir.Ref) ?Shown {
    const inst = f.inst(ref);
    switch (inst.op) {
        .list_get => if (inst.data == flags.pop_read or inst.data == flags.pop_index_read) return null,
        .list_get_field, .list_set, .list_set_field => {},
        else => return null,
    }
    if (inst.check == .none) return null;
    const index = f.resolve(inst.b);
    const written: ?ir.Ref = if (shape.block_of[index.index()]) |join| facts.normalizedRaw(f, join, index) else null;
    const signed = written == null and !nonNegative(f, known, index);
    return .{ .index = keys.index(written orelse index), .length = keys.length(inst.a), .shows_sign = written == null, .needs_sign = signed };
}

/// Whether the facts put `index` at or above zero (an index added after them has none).
fn nonNegative(f: *const ir.Function, known: ?*const facts.Facts, index: ir.Ref) bool {
    const table = known orelse return false;
    if (index.index() >= table.ranges.len) return false;
    const range = facts.valueRange(table, f, index) orelse return false;
    return range.lo >= 0;
}

/// Whether a check in `shown` covers `access`: one length key, one index key, and a check
/// that shows the sign when the access needs it.
fn covered(shown: []const Shown, access: Shown, sabotage: bool) bool {
    for (shown) |earlier| {
        if (!std.meta.eql(earlier.length, access.length) or !std.meta.eql(earlier.index.base, access.index.base)) continue;
        if (access.needs_sign and !earlier.shows_sign) continue;
        if (earlier.index.offset == access.index.offset) return true;
        if (sabotage and earlier.index.offset +| 1 == access.index.offset) return true;
    }
    return false;
}
