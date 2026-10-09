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
    return proven;
}

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
