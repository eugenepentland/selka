//! Which values the bounds-check rules may treat as one (lane F2, NEW-CORE-F2-INDEX-2).
//!
//! A value's key sees through forwarding copies and through record fields: a field read
//! of a record this function built or updated is the value stored there, and two reads of
//! one field of one record value are one value. An index key adds a constant moved by
//! checked or proven arithmetic (`x - 1` and `x - 1 - 0` share one). A list's length key
//! sees through the operations that keep a list's length (an element write, an element
//! field write, a copy, a sort) and through phis whose operands all keep one length.
//!
//! Keys never look through a phi of scalars or records, so two values with one key are
//! one value wherever both are defined, and two lists with one length key have one
//! length there: every key names an SSA value (or a field of one), whose definition
//! dominates every value keyed by it, so the last definition of the key before any point
//! is the one the keyed values were computed from.
const std = @import("std");
const ir = @import("ir.zig");

/// A value: instruction `ref` itself (`field == 0`), or field `field - 1` of record value `ref`.
pub const Key = struct {
    ref: ir.Ref,
    field: u32 = 0,

    fn of(ref: ir.Ref) Key {
        return .{ .ref = ref };
    }
};

/// An index: the value of `base` plus `offset`.
pub const IndexKey = struct { base: Key, offset: i64 = 0 };

/// A list length key not computed yet (a phi waiting for its operands).
const pending: Key = .{ .ref = .none, .field = std.math.maxInt(u32) };

/// The keys of one function.
pub const Keys = struct {
    f: *const ir.Function,
    /// Per instruction: the length key of a list value (its own key for any other value).
    lengths: []Key,
    /// Per instruction: its value key (a field read's is the field's, `field`).
    values: []Key,
    /// Per block: whether an execution can reach it, honouring branches on constants.
    live: []bool,

    /// The key of the value `raw` stands for.
    pub fn value(self: *const Keys, raw: ir.Ref) Key {
        const ref = self.f.resolve(raw);
        if (ref == .none) return Key.of(raw);
        return self.values[ref.index()];
    }

    /// A phi whose operands are one value or the phi itself is that value: the value's
    /// definition dominates the phi, and no path from the phi to its uses passes it again.
    /// An operand on an edge no execution takes (a branch on a constant) does not count.
    fn trivial(self: *const Keys, block: ir.BlockId, phi: ir.Ref) Key {
        const own = Key.of(phi);
        var only: ?Key = null;
        const preds = self.f.blocks.items[block.index()].preds.items;
        for (self.f.operands(self.f.inst(phi).data), 0..) |operand, k| {
            if (k < preds.len and (!self.live[preds[k].index()] or deadEdge(self.f, preds[k], block))) continue;
            const key = self.value(operand);
            if (std.meta.eql(key, own)) continue;
            if (only) |other| {
                if (!std.meta.eql(other, key)) return own;
            } else only = key;
        }
        return only orelse own;
    }

    /// The key of field `slot` of record value `record`: through `record_set`s of other
    /// fields to the `record_set` or `record_make` that stored it, else the field itself.
    fn field(self: *const Keys, record: ir.Ref, slot: u32) Key {
        var current = self.f.resolve(record);
        var steps: usize = 0;
        while (steps < 4096) : (steps += 1) {
            const inst = self.f.inst(current);
            switch (inst.op) {
                .record_set => {
                    if (inst.data == slot) return self.value(inst.b);
                    current = self.f.resolve(inst.a);
                },
                .record_make => return self.value(self.f.operands(inst.data)[slot]),
                else => break,
            }
        }
        return .{ .ref = current, .field = slot + 1 };
    }

    /// The key of index `raw`: its value less any constant checked or proven additions and
    /// subtractions moved it by (no wrap: a checked one traps first, a proven one cannot).
    pub fn index(self: *const Keys, raw: ir.Ref) IndexKey {
        var out: IndexKey = .{ .base = self.value(raw) };
        var steps: usize = 0;
        while (steps < 64) : (steps += 1) {
            if (out.base.field != 0) break;
            const inst = self.f.inst(out.base.ref);
            if ((inst.op != .add and inst.op != .sub) or inst.check == .none or inst.ty != .i64) break;
            const right = constant(self.f, inst.b);
            const left = if (inst.op == .add) constant(self.f, inst.a) else null;
            const step = right orelse left orelse break;
            const moved = if (inst.op == .add) std.math.add(i64, out.offset, step) else std.math.sub(i64, out.offset, step);
            out.offset = moved catch break;
            out.base = self.value(if (right != null) inst.a else inst.b);
        }
        return out;
    }

    /// The length key of list value `raw`.
    pub fn length(self: *const Keys, raw: ir.Ref) Key {
        const ref = self.f.resolve(raw);
        if (ref == .none) return Key.of(raw);
        return self.lengths[ref.index()];
    }
};

/// Whether no execution takes the edge `from` → `to`: `from` branches on a constant the
/// other way (the fact pass folds decided comparisons to constants).
fn deadEdge(f: *const ir.Function, from: ir.BlockId, to: ir.BlockId) bool {
    const insts = f.blocks.items[from.index()].insts.items;
    if (insts.len == 0) return false;
    const last = f.inst(insts[insts.len - 1]);
    if (last.op != .branch) return false;
    const targets = ir.unpackTargets(last.data);
    if (targets.then == targets.otherwise) return false;
    const condition = f.inst(f.resolve(last.a));
    if (condition.op != .iconst) return false;
    return if (condition.data != 0) targets.then != to else targets.otherwise != to;
}

/// The blocks an execution can reach from the entry, taking no edge `deadEdge` rules out.
fn liveBlocks(arena: std.mem.Allocator, f: *const ir.Function) std.mem.Allocator.Error![]bool {
    const live = try arena.alloc(bool, f.blocks.items.len);
    @memset(live, false);
    if (live.len == 0) return live;
    var stack: std.ArrayList(ir.BlockId) = .empty;
    live[0] = true;
    try stack.append(arena, @fromBackingInt(0));
    while (stack.pop()) |block| {
        const insts = f.blocks.items[block.index()].insts.items;
        if (insts.len == 0) continue;
        const last = f.inst(insts[insts.len - 1]);
        var next: [2]ir.BlockId = undefined;
        var count: usize = 0;
        switch (last.op) {
            .jump => {
                next[0] = @fromBackingInt(@as(u32, @intCast(last.data)));
                count = 1;
            },
            .branch => {
                const targets = ir.unpackTargets(last.data);
                next = .{ targets.then, targets.otherwise };
                count = 2;
            },
            else => {},
        }
        for (next[0..count]) |target| {
            if (live[target.index()] or deadEdge(f, block, target)) continue;
            live[target.index()] = true;
            try stack.append(arena, target);
        }
    }
    return live;
}

fn constant(f: *const ir.Function, raw: ir.Ref) ?i64 {
    const inst = f.inst(f.resolve(raw));
    if (inst.op != .iconst or inst.ty != .i64) return null;
    return @bitCast(inst.data);
}

/// Whether an operation's result has the length of its first operand.
fn keepsLength(op: ir.Op) bool {
    return switch (op) {
        .list_set, .list_set_field, .list_copy, .list_sort => true,
        else => false,
    };
}

/// Compute the keys of `f`, whose reachable blocks `rpo` lists in reverse postorder.
pub fn compute(arena: std.mem.Allocator, f: *const ir.Function, rpo: []const ir.BlockId) std.mem.Allocator.Error!Keys {
    var keys: Keys = .{ .f = f, .lengths = try arena.alloc(Key, f.insts.items.len), .values = try arena.alloc(Key, f.insts.items.len), .live = try liveBlocks(arena, f) };
    for (keys.lengths, keys.values, 0..) |*slot, *own, i| {
        slot.* = Key.of(@fromBackingInt(@intCast(i)));
        own.* = slot.*;
    }
    // Operands come before their uses in reverse postorder, phis aside, and a field read
    // never looks through a phi.
    for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .record_get) keys.values[ref.index()] = keys.field(inst.a, @intCast(inst.data));
        if (inst.op == .phi) keys.values[ref.index()] = keys.trivial(block, ref);
    };
    for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
        if (f.inst(ref).op == .phi) keys.lengths[ref.index()] = pending;
    };
    // Phis move only from pending to a key to their own key, but a single-operand phi may
    // follow its operand from one key to another; a pass that does not settle gives up.
    var rounds: usize = 0;
    var settled = false;
    while (rounds < 64 and !settled) : (rounds += 1) {
        settled = true;
        for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
            const next = lengthOf(&keys, ref);
            if (!std.meta.eql(next, keys.lengths[ref.index()])) {
                keys.lengths[ref.index()] = next;
                settled = false;
            }
        };
    }
    for (keys.lengths, 0..) |*slot, i| {
        if (!settled or std.meta.eql(slot.*, pending)) slot.* = Key.of(@fromBackingInt(@intCast(i)));
    }
    // A phi keeps a key only when every operand has it, so a key never rests on an operand
    // that stayed pending (a phi nothing enters) or on a round that did not settle.
    var changed = true;
    while (changed) {
        changed = false;
        for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
            const inst = f.inst(ref);
            const own = Key.of(ref);
            if (std.meta.eql(keys.lengths[ref.index()], own)) continue;
            const agrees = switch (inst.op) {
                .phi => for (f.operands(inst.data)) |operand| {
                    if (!std.meta.eql(keys.length(operand), keys.lengths[ref.index()])) break false;
                } else true,
                else => std.meta.eql(lengthOf(&keys, ref), keys.lengths[ref.index()]),
            };
            if (!agrees) {
                keys.lengths[ref.index()] = own;
                changed = true;
            }
        };
    }
    return keys;
}

/// One step of the length keys: a length-keeping operation takes its operand's key, a field
/// read the key of the value it reads, a phi the one key its operands agree on.
fn lengthOf(keys: *const Keys, ref: ir.Ref) Key {
    const f = keys.f;
    const inst = f.inst(ref);
    const own = Key.of(ref);
    if (keepsLength(inst.op)) return keys.length(inst.a);
    switch (inst.op) {
        .record_get => {
            const read = keys.value(ref);
            if (read.field == 0 and read.ref != ref) return keys.length(read.ref);
            return read;
        },
        .copy => return if (f.resolve(ref) == ref) own else keys.length(inst.a),
        .phi => {
            if (std.meta.eql(keys.lengths[ref.index()], own)) return own;
            var chosen: ?Key = null;
            for (f.operands(inst.data)) |operand| {
                const key = keys.length(operand);
                if (std.meta.eql(key, pending)) continue;
                if (chosen) |other| {
                    if (!std.meta.eql(other, key)) return own;
                } else chosen = key;
            }
            return chosen orelse pending;
        },
        else => return own,
    }
}
