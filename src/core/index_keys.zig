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

    /// The key of field `slot` of record value `record` (`field`).
    pub fn fieldOf(self: *const Keys, record: ir.Ref, slot: u32) Key {
        return self.field(record, slot);
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
    try lengthKeys(arena, &keys, rpo);
    // A phi keeps a key only when every operand has it, and every other value only when its
    // own step gives it: whatever the search above found, no key rests on anything else.
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
    switch (inst.op) {
        .phi => {
            var chosen: ?Key = null;
            for (f.operands(inst.data)) |operand| {
                const key = keys.length(operand);
                if (chosen) |other| {
                    if (!std.meta.eql(other, key)) return own;
                } else chosen = key;
            }
            return chosen orelse own;
        },
        else => {
            const source = lengthSource(keys, ref) orelse return own;
            return switch (source) {
                .value => |value| keys.length(value),
                .key => |key| key,
            };
        },
    }
}

/// Where a value other than a phi takes its length from: the value it keeps the length of,
/// a field key, or nothing (its own key).
const Source = union(enum) { value: ir.Ref, key: Key };

fn lengthSource(keys: *const Keys, ref: ir.Ref) ?Source {
    const f = keys.f;
    const inst = f.inst(ref);
    if (keepsLength(inst.op)) return .{ .value = f.resolve(inst.a) };
    switch (inst.op) {
        .record_get => {
            const read = keys.value(ref);
            if (read.field == 0 and read.ref != ref) return .{ .value = read.ref };
            return .{ .key = read };
        },
        .copy => return if (f.resolve(ref) == ref) null else .{ .value = f.resolve(ref) },
        else => return null,
    }
}

/// The length keys of every value the blocks `rpo` lists define, by strongly connected
/// components of the "has the length of" graph (a phi to its operands, a length-keeping
/// operation to its operand), operands' components first: a component whose edges out all
/// reach one key takes it (a loop that only writes elements keeps its list's key), and any
/// other gives each member its own.
fn lengthKeys(arena: std.mem.Allocator, keys: *Keys, rpo: []const ir.BlockId) std.mem.Allocator.Error!void {
    const f = keys.f;
    const count = f.insts.items.len;
    const in_block = try arena.alloc(bool, count);
    @memset(in_block, false);
    for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
        in_block[ref.index()] = true;
    };
    // Tarjan's algorithm, iteratively.
    const unvisited = std.math.maxInt(u32);
    const order = try arena.alloc(u32, count);
    const low = try arena.alloc(u32, count);
    const on_stack = try arena.alloc(bool, count);
    @memset(order, unvisited);
    @memset(on_stack, false);
    var next_order: u32 = 0;
    var stack: std.ArrayList(u32) = .empty;
    const Frame = struct { node: u32, edge: usize };
    var work: std.ArrayList(Frame) = .empty;
    var component: std.ArrayList(u32) = .empty;
    for (rpo) |block| for (f.blocks.items[block.index()].insts.items) |root| {
        if (order[root.index()] != unvisited) continue;
        try work.append(arena, .{ .node = @intCast(root.index()), .edge = 0 });
        order[root.index()] = next_order;
        low[root.index()] = next_order;
        next_order += 1;
        try stack.append(arena, @intCast(root.index()));
        on_stack[root.index()] = true;
        while (work.items.len != 0) {
            const top = &work.items[work.items.len - 1];
            const node = top.node;
            if (edgeOf(keys, @fromBackingInt(node), top.edge)) |target| {
                top.edge += 1;
                const t = target.index();
                if (t >= count or !in_block[t]) continue;
                if (order[t] == unvisited) {
                    order[t] = next_order;
                    low[t] = next_order;
                    next_order += 1;
                    try stack.append(arena, @intCast(t));
                    on_stack[t] = true;
                    try work.append(arena, .{ .node = @intCast(t), .edge = 0 });
                } else if (on_stack[t]) low[node] = @min(low[node], order[t]);
                continue;
            }
            _ = work.pop();
            if (work.items.len != 0) {
                const parent = work.items[work.items.len - 1].node;
                low[parent] = @min(low[parent], low[node]);
            }
            if (low[node] != order[node]) continue;
            component.clearRetainingCapacity();
            while (stack.pop()) |member| {
                on_stack[member] = false;
                try component.append(arena, member);
                if (member == node) break;
            }
            settleComponent(keys, component.items);
        }
    };
}

/// The `edge`-th "has the length of" edge of `node`, or null past its last.
fn edgeOf(keys: *const Keys, node: ir.Ref, edge: usize) ?ir.Ref {
    const f = keys.f;
    const inst = f.inst(node);
    if (inst.op == .phi) {
        const operands = f.operands(inst.data);
        return if (edge < operands.len) f.resolve(operands[edge]) else null;
    }
    if (edge != 0) return null;
    const source = lengthSource(keys, node) orelse return null;
    return switch (source) {
        .value => |value| value,
        .key => null,
    };
}

/// Give one finished component its keys: the one key its edges out reach, or each member its own.
fn settleComponent(keys: *Keys, members: []const u32) void {
    if (members.len == 1) {
        const ref: ir.Ref = @fromBackingInt(members[0]);
        keys.lengths[members[0]] = lengthOf(keys, ref);
        // A phi of itself and one other value has that value's key.
        if (keys.f.inst(ref).op == .phi) keys.lengths[members[0]] = outsideKey(keys, members) orelse Key.of(ref);
        return;
    }
    const key = outsideKey(keys, members);
    for (members) |member| keys.lengths[member] = key orelse Key.of(@fromBackingInt(member));
}

/// The one key every edge leaving `members` reaches (a member that is a root leaves with its
/// own source), or null when they disagree or there are none.
fn outsideKey(keys: *const Keys, members: []const u32) ?Key {
    var chosen: Agreement = .{};
    for (members) |member| {
        const ref: ir.Ref = @fromBackingInt(member);
        if (keys.f.inst(ref).op != .phi) {
            const source = lengthSource(keys, ref) orelse return null;
            if (source == .key and !chosen.add(source.key)) return null;
        }
        var edge: usize = 0;
        while (edgeOf(keys, ref, edge)) |target| : (edge += 1) {
            if (std.mem.indexOfScalar(u32, members, @intCast(target.index())) != null) continue;
            if (!chosen.add(keys.length(target))) return null;
        }
    }
    return chosen.key;
}

/// The one key seen so far, if any.
const Agreement = struct {
    key: ?Key = null,

    /// Take `key`; false when it differs from the one seen before.
    fn add(self: *Agreement, key: Key) bool {
        if (self.key) |other| return std.meta.eql(other, key);
        self.key = key;
        return true;
    }
};
