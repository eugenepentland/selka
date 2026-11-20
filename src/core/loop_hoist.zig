//! Loop-invariant checked access (lane D4, route (a)): a proof, per natural loop, that a
//! list's element count and a record field's pointer do not change while the loop runs, and
//! the plan the emitter follows: each cached value is loaded once, in the loop's preheader.
//!
//! A bounds check reads its list's element count from the list header on every iteration, and
//! a read of a list field reloads the field's pointer from the record. When the loop provably
//! keeps both unchanged, the emitter loads them in the preheader and every check and read in the
//! body uses the loaded value. The checks still run each iteration, against the cached count, so
//! a failing program traps at the same iteration with the same message. A value the proof cannot
//! show unchanged is not cached (when in doubt, don't cache).
//!
//! The proof. A value is a root when its storage belongs to it alone, and the loop can change that
//! storage only through the value's own lineage:
//!   L1 (roots): a list is a root when it is a parameter, a fresh list or a call result; a record is
//!       a root when it is a parameter or a fresh record. A list field of a root record is a field
//!       root (`Root.field`). Everything else has no root.
//!   L2 (lineage): a copy, a phi whose operands share one root, a list element write (`list_set`,
//!       `list_set_field`) and a record field write (`record_set`) carry their operand's root, so
//!       they are members of that root. An element write keeps the list's length, so a member keeps
//!       its root's length. A record write changes one field, and a field-root member keeps its
//!       field's length only when the field is written back from that same field (below).
//!   L3 (uses): inside the loop, a member is used only by reads (`record_get`, `list_get` without
//!       pop flags, `list_get_field`, `list_len`, `list_view_of`, `list_slice_view`), by lineage (L2)
//!       as the operand that is written or copied, by a phi of the same root, or by `ret`. Any other
//!       use taints the member's root: no caching for it, nor for anything rooted at it. A member
//!       stored as the value of a list element write, or of a record field, taints its root unless
//!       the write is the same field's write-back (L4).
//!   L4 (field writes): a `record_set` of field k of a root record in the loop either stores a value
//!       of the same field's root (a write-back that keeps the list's length) or taints field k. Any
//!       such write also marks field k written, so its pointer is not cached.
//!   L5 (entry): a root defined outside the loop dominates the loop's preheader, so its value, and
//!       a read of its field at the preheader, are the values the loop starts from. Only roots
//!       defined outside the loop are cached. The loop-carried values are members, not roots.
//! A list's header (its element count) changes only through the operations L3 refuses (append,
//! pop, sort, drop, a call that takes the list mutably), so under L3 the count is the root's count
//! at loop entry. A field's pointer changes only through a write to that field (L4), so an unwritten
//! field's pointer is the entry pointer.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// A record field of a root record value: field `index` of `record`.
pub const Field = struct { record: ir.Ref, index: u32 };

/// The root a value belongs to: the list or record value `value` itself, or a list field.
pub const Root = union(enum) {
    value: ir.Ref,
    field: Field,
};

/// What one cached value is.
pub const What = union(enum) {
    /// The element count of the list value `list`, an outer value.
    length: ir.Ref,
    /// The element count of the list in field `field`, of an outer record value.
    field_length: Field,
    /// Field `field` (a list, a scalar) of an outer record value, as it stands at loop entry.
    field: Field,
};

/// One value the emitter loads in `preheader`, before that block's terminator.
pub const Entry = struct {
    preheader: u32,
    name: []const u8,
    what: What,
};

/// The emitter's plan: the loads, and the names a read or check uses in place of its own load.
pub const Plan = struct {
    /// Every cached value, in the order the emitter loads them.
    entries: []const Entry = &.{},
    /// Per instruction: the cached value a `record_get` takes its place with, or null.
    fields: []const ?[]const u8 = &.{},
    /// Per instruction: the cached element count a list access checks against, or null.
    lengths: []const ?[]const u8 = &.{},
};

/// Per value during root inference: not known yet, a root, or no single root.
const Slot = union(enum) {
    unknown,
    root: Root,
    conflict,
};

/// Plan the cached values of every loop with a preheader whose header is not in `skip`.
/// Pure in the function: the emitter computes the same plan from the same IR.
pub fn plan(arena: std.mem.Allocator, m: *const ir.Module, f: *const ir.Function, skip: []const u32) std.mem.Allocator.Error!Plan {
    if (f.loops.items.len == 0) return .{};
    const shape = try facts.shape(arena, f);
    const roots = try rootsOf(arena, m, f);
    var builder: Builder = .{
        .arena = arena,
        .m = m,
        .f = f,
        .shape = shape,
        .roots = roots,
        .out = .{ .fields = try arena.alloc(?[]const u8, f.insts.items.len), .lengths = try arena.alloc(?[]const u8, f.insts.items.len) },
        .marks = .{ .bad_base = try arena.alloc(bool, f.insts.items.len) },
    };
    @memset(builder.out.fields, null);
    @memset(builder.out.lengths, null);
    // Innermost loops first: an access takes the first loop that caches it, and that loop's
    // preheader dominates every outer one's, so an inner plan is the one the body reads.
    var candidates: std.ArrayList(Candidate) = .empty;
    for (f.loops.items) |loop| {
        if (std.mem.indexOfScalar(u32, skip, @intCast(loop.header.index())) != null) continue;
        if (try builder.naturalLoop(loop.header)) |candidate| try candidates.append(arena, candidate);
    }
    std.mem.sort(Candidate, candidates.items, {}, Candidate.smaller);
    for (candidates.items) |candidate| try builder.analyze(candidate);
    return .{ .entries = builder.out.entries.items, .fields = builder.out.fields, .lengths = builder.out.lengths };
}

/// A natural loop whose preheader exists: its header, its blocks and its preheader.
const Candidate = struct {
    header: ir.BlockId,
    blocks: []bool,
    count: u32,
    preheader: u32,

    fn smaller(_: void, a: Candidate, b: Candidate) bool {
        return a.count < b.count;
    }
};

/// A key: what a set or a cache holds, of which value (and in which preheader, for a cache).
const Key = struct { kind: u8, base: u32, index: u32, preheader: u32 };

/// Key kinds: a field's identity (for the taint and write sets), and the three cached values.
const key_field: u8 = 0;
const key_length_value: u8 = 1;
const key_length_field: u8 = 2;
const key_field_value: u8 = 3;

/// The identity of a field of a root record, for the taint and write sets.
fn fieldKey(field: Field) Key {
    return .{ .kind = key_field, .base = @intCast(field.record.index()), .index = field.index, .preheader = 0 };
}

/// What the analysis decided, for the emitter: the cached values and the names that read them.
const Output = struct {
    /// Per instruction: the cached value a `record_get` takes its place with, or null.
    fields: []?[]const u8,
    /// Per instruction: the cached element count a list access checks against, or null.
    lengths: []?[]const u8,
    entries: std.ArrayList(Entry) = .empty,
    /// The cache of each value per preheader: one name however many reads share it.
    keys: std.AutoHashMapUnmanaged(Key, []const u8) = .empty,
    counter: u32 = 0,
};

/// What the proof has marked for the loop being analyzed.
const Marks = struct {
    /// Per instruction: a root whose members are used in a way the proof refuses (per loop).
    bad_base: []bool,
    /// Field roots refused by a use or a write (per loop).
    bad_fields: std.AutoHashMapUnmanaged(Key, void) = .empty,
    /// Record fields written in the loop (per loop).
    written: std.AutoHashMapUnmanaged(Key, void) = .empty,
};

/// The loop analysis state, shared by the loops of one function.
const Builder = struct {
    arena: std.mem.Allocator,
    m: *const ir.Module,
    f: *const ir.Function,
    shape: facts.Shape,
    roots: []?Root,
    out: Output,
    marks: Marks,

    /// The natural loop of `header`, if its back edges are dominated by it and it has one preheader.
    fn naturalLoop(self: *Builder, header: ir.BlockId) std.mem.Allocator.Error!?Candidate {
        const h = header.index();
        const blocks = try self.arena.alloc(bool, self.f.blocks.items.len);
        @memset(blocks, false);
        blocks[h] = true;
        var stack: std.ArrayList(u32) = .empty;
        var count: u32 = 1;
        // Walk back from every back edge (a predecessor the header dominates) to the header.
        for (self.f.blocks.items[h].preds.items) |pred| {
            if (!self.dominates(h, pred.index())) continue;
            if (!blocks[pred.index()]) {
                blocks[pred.index()] = true;
                count += 1;
                try stack.append(self.arena, @intCast(pred.index()));
            }
        }
        while (stack.pop()) |block| {
            for (self.f.blocks.items[block].preds.items) |pred| {
                if (blocks[pred.index()]) continue;
                // An entry into the loop that the header does not dominate: not a natural loop.
                if (!self.dominates(h, pred.index())) return null;
                blocks[pred.index()] = true;
                count += 1;
                try stack.append(self.arena, @intCast(pred.index()));
            }
        }
        var preheader: ?u32 = null;
        for (self.f.blocks.items[h].preds.items) |pred| {
            if (blocks[pred.index()]) continue;
            if (preheader != null) return null;
            preheader = @intCast(pred.index());
        }
        const pre = preheader orelse return null;
        // The preheader enters the header by an unconditional jump, so its code runs on the way in.
        const insts = self.f.blocks.items[pre].insts.items;
        if (insts.len == 0) return null;
        const last = self.f.inst(insts[insts.len - 1]);
        if (last.op != .jump or last.data != h) return null;
        return .{ .header = header, .blocks = blocks, .count = count, .preheader = pre };
    }

    /// Whether block `a` dominates block `b` (the idom chain of `b` reaches `a`).
    fn dominates(self: *const Builder, a: usize, b: usize) bool {
        var at: usize = b;
        while (true) {
            if (at == a) return true;
            const parent = self.shape.idom[at] orelse return false;
            if (parent.index() == at) return false;
            at = parent.index();
        }
    }

    /// Whether instruction `ref` is in the loop (its block is).
    fn inLoop(self: *const Builder, blocks: []const bool, ref: ir.Ref) bool {
        const block = self.shape.block_of[ref.index()] orelse return false;
        return blocks[block.index()];
    }

    /// Analyze one loop: its taints, its writes, then the values to cache.
    fn analyze(self: *Builder, loop: Candidate) std.mem.Allocator.Error!void {
        @memset(self.marks.bad_base, false);
        self.marks.bad_fields.clearRetainingCapacity();
        self.marks.written.clearRetainingCapacity();
        const blocks = loop.blocks;
        // Pass 1: every use of a member inside the loop.
        for (self.f.blocks.items, 0..) |block, b| {
            if (!blocks[b]) continue;
            for (block.insts.items) |ref| try self.checkUses(blocks, ref);
        }
        // Pass 2: the field writes (L4), whatever is stored.
        for (self.f.blocks.items, 0..) |block, b| {
            if (!blocks[b]) continue;
            for (block.insts.items) |ref| try self.checkWrite(blocks, ref);
        }
        // Pass 3: what to cache.
        for (self.f.blocks.items, 0..) |block, b| {
            if (!blocks[b]) continue;
            for (block.insts.items) |ref| try self.candidate(blocks, loop.preheader, ref);
        }
    }

    /// Taint the root of a member a use refuses.
    fn taint(self: *Builder, root: Root) std.mem.Allocator.Error!void {
        switch (root) {
            .value => |value| self.marks.bad_base[value.index()] = true,
            .field => |field| try self.marks.bad_fields.put(self.arena, fieldKey(field), {}),
        }
    }

    /// Whether `ref` (a managed list or record) has a root, and that root is `root`.
    fn rootIs(self: *const Builder, ref: ir.Ref, root: Root) bool {
        const resolved = self.f.resolve(ref);
        if (resolved == .none) return false;
        const found = self.roots[resolved.index()] orelse return false;
        return sameRoot(found, root);
    }

    /// Check every operand of `ref` against L3, when `ref` is inside the loop.
    fn checkUses(self: *Builder, blocks: []const bool, ref: ir.Ref) std.mem.Allocator.Error!void {
        if (!self.inLoop(blocks, ref)) return;
        const inst = self.f.inst(ref);
        switch (inst.op) {
            .param, .iconst, .phi, .call, .print, .record_make, .jump => {},
            else => {
                if (inst.a != .none) try self.checkUse(ref, inst, inst.a, .a);
                if (inst.b != .none) try self.checkUse(ref, inst, inst.b, .b);
            },
        }
        for (self.f.valueOperands(inst).extra) |operand| try self.checkUse(ref, inst, operand, .extra);
    }

    const Position = enum { a, b, extra };

    /// One operand of `user` against L3 and L4.
    fn checkUse(self: *Builder, user_ref: ir.Ref, user: ir.Inst, operand: ir.Ref, position: Position) std.mem.Allocator.Error!void {
        const resolved = self.f.resolve(operand);
        if (resolved == .none) return;
        const root = self.roots[resolved.index()] orelse return;
        if (!allowed(user, position)) return self.taint(root);
        if (user.op == .phi and !sameRootOrNone(self.roots[user_ref.index()], root)) return self.taint(root);
        // An element write that replaces a field's list consumes it; the field is written.
        if ((user.op == .list_set or user.op == .list_set_field) and position == .a) {
            if (root == .field) try self.marks.written.put(self.arena, fieldKey(root.field), {});
        }
        // A field write stores a value whose root must be this field (L4): otherwise it taints.
        if (user.op == .record_set and position == .b) {
            const base = self.roots[self.f.resolve(user.a).index()] orelse return self.taint(root);
            if (base != .value or !isListField(self.m, self.f, base.value, user.data)) return self.taint(root);
            if (!self.rootIs(operand, .{ .field = .{ .record = base.value, .index = @intCast(user.data) } })) return self.taint(root);
        }
    }

    /// L4 for every `record_set` in the loop: its field is written, and a list field's new value
    /// must be the same field's root, or the field is tainted.
    fn checkWrite(self: *Builder, blocks: []const bool, ref: ir.Ref) std.mem.Allocator.Error!void {
        if (!self.inLoop(blocks, ref)) return;
        const inst = self.f.inst(ref);
        if (inst.op != .record_set) return;
        const base = self.roots[self.f.resolve(inst.a).index()] orelse return;
        if (base != .value) return;
        const record = base.value;
        const field: Field = .{ .record = record, .index = @intCast(inst.data) };
        try self.marks.written.put(self.arena, fieldKey(field), {});
        if (!isListField(self.m, self.f, record, inst.data)) return;
        if (!self.rootIs(inst.b, .{ .field = field })) try self.marks.bad_fields.put(self.arena, fieldKey(field), {});
    }

    /// Cache what `ref` reads, when the proof allows it.
    fn candidate(self: *Builder, blocks: []const bool, preheader: u32, ref: ir.Ref) std.mem.Allocator.Error!void {
        if (!self.inLoop(blocks, ref)) return;
        const inst = self.f.inst(ref);
        switch (inst.op) {
            .list_get, .list_get_field, .list_set, .list_set_field => {
                if (inst.check != .exact) return;
                if (inst.op == .list_get and inst.data != 0) return;
                if (self.out.lengths[ref.index()] != null) return;
                const list = self.f.resolve(inst.a);
                if (list == .none or self.m.kind(self.f.inst(list).ty) != .list) return;
                const root = self.roots[list.index()] orelse return;
                switch (root) {
                    .value => |value| {
                        if (self.isOuter(blocks, value) and !self.marks.bad_base[value.index()]) {
                            self.out.lengths[ref.index()] = try self.lengthOf(preheader, .{ .length = value }, key_length_value, value.index(), 0);
                        }
                    },
                    .field => |field| {
                        // The count is the one the list has on entering the loop, read from the record that enters it.
                        if (self.marks.bad_base[field.record.index()] or self.badField(field)) return;
                        const entry = self.listEntry(blocks, list, field.index) orelse return;
                        switch (entry) {
                            .value => |value| self.out.lengths[ref.index()] = try self.lengthOf(preheader, .{ .length = value }, key_length_value, value.index(), 0),
                            .field => |source| self.out.lengths[ref.index()] = try self.lengthOf(preheader, .{ .field_length = source }, key_length_field, source.record.index(), source.index),
                        }
                    },
                }
            },
            .record_get => {
                if (self.out.fields[ref.index()] != null) return;
                if (!cacheableField(self.m, inst.ty)) return;
                const record = self.f.resolve(inst.a);
                if (record == .none) return;
                const root = self.roots[record.index()] orelse return;
                if (root != .value) return;
                const base = root.value;
                if (!self.isOuter(blocks, base) or self.marks.bad_base[base.index()]) return;
                const structural: Field = .{ .record = base, .index = @intCast(inst.data) };
                if (self.badField(structural) or self.marks.written.contains(fieldKey(structural))) return;
                // The value is read from the record that enters the loop, not from the root: writes made
                // before the loop (appends, a replaced field) change the field after the root was built.
                const source = self.entrySource(blocks, inst.a, @intCast(inst.data)) orelse return;
                self.out.fields[ref.index()] = try self.fieldOf(preheader, .{ .record = source, .index = @intCast(inst.data) });
            },
            else => {},
        }
    }

    /// The outer record value whose field `index` is the loop's field on entry: the lineage of record value
    /// `raw` walked back through the loop's writes of other fields to the one value entering the loop.
    /// Null when the lineage has no single entry, or the field is written on the way (L5, `entry` rule).
    fn entrySource(self: *const Builder, blocks: []const bool, raw: ir.Ref, index: u32) ?ir.Ref {
        var at = self.f.resolve(raw);
        var steps: u32 = 0;
        while (steps < self.f.insts.items.len) : (steps += 1) {
            if (at == .none) return null;
            if (self.isOuter(blocks, at)) return at;
            const inst = self.f.inst(at);
            switch (inst.op) {
                .record_set => {
                    if (inst.data == index) return null;
                    at = self.f.resolve(inst.a);
                },
                .phi => at = self.singleEntry(blocks, inst) orelse return null,
                else => return null,
            }
        }
        return null;
    }

    /// The list that enters the loop for list `list` of field `index`'s root: an outer list value (its
    /// current value is the loop's), or field `index` of the outer record that enters the loop.
    fn listEntry(self: *const Builder, blocks: []const bool, list: ir.Ref, index: u32) ?Root {
        var at = self.f.resolve(list);
        var steps: u32 = 0;
        while (steps < self.f.insts.items.len) : (steps += 1) {
            if (at == .none) return null;
            if (self.isOuter(blocks, at)) return .{ .value = at };
            const inst = self.f.inst(at);
            switch (inst.op) {
                .list_set, .list_set_field => at = self.f.resolve(inst.a),
                .record_get => {
                    if (inst.data != index) return null;
                    const source = self.entrySource(blocks, inst.a, index) orelse return null;
                    return .{ .field = .{ .record = source, .index = index } };
                },
                .phi => at = self.singleEntry(blocks, inst) orelse return null,
                else => return null,
            }
        }
        return null;
    }

    /// The one operand of loop phi `inst` that enters from outside the loop (null if there is not exactly one).
    fn singleEntry(self: *const Builder, blocks: []const bool, inst: ir.Inst) ?ir.Ref {
        var entry: ?ir.Ref = null;
        for (self.f.operands(inst.data)) |operand| {
            const resolved = self.f.resolve(operand);
            if (resolved == .none or !self.isOuter(blocks, resolved)) continue;
            if (entry) |found| if (found != resolved) return null;
            entry = resolved;
        }
        return entry;
    }

    fn badField(self: *const Builder, field: Field) bool {
        return self.marks.bad_fields.contains(fieldKey(field));
    }

    /// Whether `ref` is defined outside the loop (so it dominates the preheader).
    fn isOuter(self: *const Builder, blocks: []const bool, ref: ir.Ref) bool {
        // Parameters and constants belong to no block: they are defined outside every loop.
        const block = self.shape.block_of[ref.index()] orelse return self.f.inst(ref).op.isConstant();
        return !blocks[block.index()];
    }

    /// The cached length of a root, shared by every access of the loop that reads it.
    fn lengthOf(self: *Builder, preheader: u32, what: What, kind: u8, base: usize, index: u32) std.mem.Allocator.Error![]const u8 {
        const key: Key = .{ .kind = kind, .base = @intCast(base), .index = index, .preheader = preheader };
        if (self.out.keys.get(key)) |name| return name;
        const name = try std.fmt.allocPrint(self.arena, "%hoist.len{d}", .{self.out.counter});
        self.out.counter += 1;
        try self.out.entries.append(self.arena, .{ .preheader = preheader, .name = name, .what = what });
        try self.out.keys.put(self.arena, key, name);
        return name;
    }

    /// The cached value of a field of a root record, shared by the reads of the loop.
    fn fieldOf(self: *Builder, preheader: u32, field: Field) std.mem.Allocator.Error![]const u8 {
        const key: Key = .{ .kind = key_field_value, .base = @intCast(field.record.index()), .index = field.index, .preheader = preheader };
        if (self.out.keys.get(key)) |name| return name;
        const name = try std.fmt.allocPrint(self.arena, "%hoist.field{d}", .{self.out.counter});
        self.out.counter += 1;
        try self.out.entries.append(self.arena, .{ .preheader = preheader, .name = name, .what = .{ .field = field } });
        try self.out.keys.put(self.arena, key, name);
        return name;
    }
};

/// Whether an operation may use a member in position `position` under L3.
fn allowed(user: ir.Inst, position: Builder.Position) bool {
    return switch (user.op) {
        .record_get => position == .a,
        .list_get => position == .a and user.data == 0,
        .list_get_field, .list_len, .list_view_of, .list_slice_view, .copy, .ret => position == .a,
        .list_set, .list_set_field => position == .a,
        .record_set => position == .a or position == .b,
        .phi => position == .extra,
        else => false,
    };
}

/// Whether field `index` of the record value `record` is a list (its pointer is a root's field).
fn isListField(m: *const ir.Module, f: *const ir.Function, record: ir.Ref, index: u64) bool {
    const resolved = f.resolve(record);
    if (resolved == .none) return false;
    const fields = m.compound(f.inst(resolved).ty).record;
    return index < fields.len and m.kind(fields[index]) == .list;
}

/// A field a loop may cache: a list, or a scalar (`int`, `float`, `bool`).
fn cacheableField(m: *const ir.Module, ty: ir.Type) bool {
    if (ty.integer() != null or ty == .f64 or ty == .f32 or ty == .bool) return true;
    return m.kind(ty) == .list;
}

fn sameRoot(a: Root, b: Root) bool {
    return switch (a) {
        .value => |value| b == .value and b.value == value,
        .field => |field| b == .field and b.field.record == field.record and b.field.index == field.index,
    };
}

fn sameRootOrNone(found: ?Root, root: Root) bool {
    const value = found orelse return false;
    return sameRoot(value, root);
}

/// Each managed value's root (L1, L2), by a fixed point over the function's values.
fn rootsOf(arena: std.mem.Allocator, m: *const ir.Module, f: *const ir.Function) std.mem.Allocator.Error![]?Root {
    const slots = try arena.alloc(Slot, f.insts.items.len);
    @memset(slots, .unknown);
    var changed = true;
    while (changed) {
        changed = false;
        for (f.insts.items, 0..) |inst, index| {
            if (!managed(m, inst.ty)) continue;
            const next = derive(m, f, slots, inst, @intCast(index));
            const merged = merge(slots[index], next);
            if (!sameSlot(slots[index], merged)) {
                slots[index] = merged;
                changed = true;
            }
        }
    }
    const roots = try arena.alloc(?Root, f.insts.items.len);
    for (slots, 0..) |slot, index| roots[index] = switch (slot) {
        .root => |root| root,
        else => null,
    };
    return roots;
}

/// Whether a value is a list or a record (the managed kinds the proof follows).
fn managed(m: *const ir.Module, ty: ir.Type) bool {
    const k = m.kind(ty) orelse return false;
    return k == .list or k == .record;
}

/// The slot of `ref`'s value (a copy's is its operand's).
fn slotOf(f: *const ir.Function, slots: []const Slot, ref: ir.Ref) Slot {
    const resolved = f.resolve(ref);
    if (resolved == .none) return .conflict;
    return slots[resolved.index()];
}

/// One value's slot from its operation and its operands' slots.
fn derive(m: *const ir.Module, f: *const ir.Function, slots: []const Slot, inst: ir.Inst, index: u32) Slot {
    const self_ref: ir.Ref = @fromBackingInt(@intCast(index));
    return switch (inst.op) {
        .param, .list_new, .list_copy, .record_make => .{ .root = .{ .value = self_ref } },
        .call => if (m.kind(inst.ty) == .list) .{ .root = .{ .value = self_ref } } else .conflict,
        .copy, .list_set, .list_set_field, .record_set => slotOf(f, slots, inst.a),
        .record_get => blk: {
            if (m.kind(inst.ty) != .list) break :blk .conflict;
            const base = slotOf(f, slots, inst.a);
            switch (base) {
                .unknown => break :blk .unknown,
                .conflict => break :blk .conflict,
                .root => |root| {
                    if (root != .value) break :blk .conflict;
                    break :blk .{ .root = .{ .field = .{ .record = root.value, .index = @intCast(inst.data) } } };
                },
            }
        },
        .phi => blk: {
            var result: Slot = .unknown;
            for (f.operands(inst.data)) |operand| result = merge(result, slotOf(f, slots, operand));
            break :blk result;
        },
        else => .conflict,
    };
}

/// The meet of two slots: unknown is neutral, and two different roots are a conflict.
fn merge(old: Slot, new: Slot) Slot {
    if (old == .unknown) return new;
    if (new == .unknown) return old;
    if (old == .conflict or new == .conflict) return .conflict;
    return if (sameRoot(old.root, new.root)) old else .conflict;
}

fn sameSlot(a: Slot, b: Slot) bool {
    return switch (a) {
        .unknown => b == .unknown,
        .conflict => b == .conflict,
        .root => |root| b == .root and sameRoot(root, b.root),
    };
}
