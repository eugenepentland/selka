//! Scalar fields of records kept in SSA values (lane U1, NEW-CORE-U1-STATE-1).
//!
//! A record over four words lives in memory (`emit_homes.zig`), so every
//! `record_get` of one of its fields is a load, and a field that a loop writes and
//! reads back each iteration (the Lox VM's `frame.ip`, `rt.stack_top`) waits on the
//! store of the iteration before: LLVM cannot keep it in a register, since the
//! record's memory is also handed to calls on some paths of the loop.
//!
//! Records are values, so a read of field `f` of record `r` is the value last put
//! there: `record_set(r', f, v)` makes it `v`, `record_set(r', g, w)` with `g != f`
//! leaves it `r'`'s, `record_make` names it, and a phi of records has the phi of its
//! operands' fields. This pass replaces each read of a scalar field (an integer, a
//! float, a `bool` or a capability) of a record built that way by that value, with a
//! new phi of scalars wherever the record is a phi. An operand that is none of those
//! (a parameter, a call's result, an element read) has its field read right where it
//! is defined, where its memory holds it. Stores are unchanged: the record's memory
//! still holds every field for the calls, copies and returns that read it there.
//!
//! Runs after ownership, which counts nothing for scalars and whose rewrites
//! (`stores.zig`'s narrowed stores among them) see the reads it replaces.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// A value the pass made: a phi or read that holds field `field` of record `record`.
pub const Made = struct { ref: ir.Ref, record: ir.Ref, field: u64 };

/// What the pass did to one function: the reads it replaced and the values it made.
pub const Result = struct { replaced: u32 = 0, made: []const Made = &.{} };

/// Replace scalar field reads of `f` by the values they read.
pub fn run(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) Error!Result {
    var pass: Pass = .{ .arena = arena, .module = module, .f = f, .first_new = f.insts.items.len };
    var reads: std.ArrayList(ir.Ref) = .empty;
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .record_get and scalar(inst.ty) and module.kind(f.inst(f.resolve(inst.a)).ty) == .record) try reads.append(arena, ref);
        }
    }
    if (reads.items.len == 0) return .{};
    pass.block_of = try arena.alloc(u32, f.insts.items.len);
    @memset(pass.block_of, no_block);
    for (f.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
        pass.block_of[ref.index()] = @intCast(b);
    };
    const values = try arena.alloc(?ir.Ref, reads.items.len);
    for (reads.items, values) |ref, *value| {
        const read = f.inst(ref);
        value.* = try pass.field(f.resolve(read.a), read.data, read.ty);
    }
    // A phi is worth its register only when the loop or join writes the field on some
    // path: a field every path only passes through stays a read where it is used.
    const writes = try pass.writing();
    var used: std.AutoHashMapUnmanaged(u32, void) = .empty;
    var replaced: u32 = 0;
    for (reads.items, values) |ref, maybe| {
        const value = maybe orelse continue;
        if (pass.new.phi_index.get(@backingInt(value))) |i| if (!writes[i]) continue;
        const read = f.inst(ref);
        f.insts.items[ref.index()] = .{ .op = .copy, .ty = read.ty, .a = value, .span = read.span };
        try pass.use(&used, value);
        replaced += 1;
    }
    try pass.place(&used);
    var made: std.ArrayList(Made) = .empty;
    for (pass.new.list.items) |value| if (used.contains(@backingInt(value.ref))) try made.append(arena, value);
    return .{ .replaced = replaced, .made = made.items };
}

/// Give each value the pass made the interval the facts know for its record's field
/// (`Aggregates.fields`): the value is that field wherever it is defined. `known` must
/// already cover the new instructions.
pub fn ranges(known: *facts.Facts, made: []const Made) void {
    for (made) |value| {
        const fields = known.aggregates.fields[value.record.index()] orelse continue;
        if (value.field < fields.len) known.ranges[value.ref.index()] = fields[@intCast(value.field)];
    }
}

/// Types this pass keeps in SSA values: one register, no block to count.
fn scalar(ty: ir.Type) bool {
    return switch (ty) {
        .bool, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f64, .cap => true,
        else => false,
    };
}

const no_block = std.math.maxInt(u32);

/// One record's field, the key of the values the pass made for it.
const Key = struct { record: u32, field: u64 };

/// A read the pass adds: `ref` goes right after `after` (or first in the entry block
/// when `after` is a parameter, or after the phis of a phi's block).
const Added = struct { ref: ir.Ref, after: ir.Ref };

/// The values the pass made, and where they go.
const New = struct {
    /// Per record and field: the value that holds the field (a new phi, a read, or a
    /// value already there).
    made: std.AutoHashMapUnmanaged(Key, ir.Ref) = .empty,
    /// The phis and reads to put into blocks once every value is known.
    phis: std.ArrayList(Added) = .empty,
    reads: std.ArrayList(Added) = .empty,
    list: std.ArrayList(Made) = .empty,
    /// Per new phi: its position in `phis`.
    phi_index: std.AutoHashMapUnmanaged(u32, u32) = .empty,
};

const Pass = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *ir.Function,
    block_of: []u32 = &.{},
    /// The first instruction the pass makes: every later one is new.
    first_new: usize = 0,
    new: New = .{},

    /// The value field `index` of `record` holds, when the record was built or joined
    /// from values whose fields are known; null for a record that is none of those.
    fn field(self: *Pass, record: ir.Ref, index: u64, ty: ir.Type) Error!?ir.Ref {
        var current = record;
        // Updates of other fields leave this one as it was.
        while (true) {
            const inst = self.f.inst(current);
            switch (inst.op) {
                .record_set => {
                    if (inst.data == index) return self.f.resolve(inst.b);
                    current = self.f.resolve(inst.a);
                },
                .record_make => return self.f.resolve(self.f.operands(inst.data)[@intCast(index)]),
                .phi => {
                    const joined = try self.join(current, index, ty);
                    return joined;
                },
                else => return null,
            }
        }
    }

    /// The phi of field `index` over the operands of record phi `phi`.
    fn join(self: *Pass, phi: ir.Ref, index: u64, ty: ir.Type) Error!ir.Ref {
        const key: Key = .{ .record = @backingInt(phi), .field = index };
        if (self.new.made.get(key)) |known| return known;
        // Copied: the reads and phis made below append to `extra`, which may move.
        const operands = try self.arena.dupe(ir.Ref, self.f.operands(self.f.inst(phi).data));
        const out = try self.newInst(.{ .op = .phi, .ty = ty, .span = self.f.inst(phi).span });
        try self.new.made.put(self.arena, key, out);
        try self.new.list.append(self.arena, .{ .ref = out, .record = phi, .field = index });
        try self.new.phi_index.put(self.arena, @backingInt(out), @intCast(self.new.phis.items.len));
        try self.new.phis.append(self.arena, .{ .ref = out, .after = phi });
        const values = try self.arena.alloc(ir.Ref, operands.len);
        for (operands, values) |operand, *slot| {
            const source = self.f.resolve(operand);
            slot.* = try self.field(source, index, ty) orelse try self.readAt(source, index, ty);
        }
        const start: u32 = @intCast(self.f.extra.items.len);
        try self.f.extra.appendSlice(self.arena, values);
        self.f.insts.items[out.index()].data = (ir.ExtraSlice{ .start = start, .len = @intCast(values.len) }).pack();
        return out;
    }

    /// Field `index` of `record` read where `record` is defined (an `undef` record's is `undef`).
    fn readAt(self: *Pass, record: ir.Ref, index: u64, ty: ir.Type) Error!ir.Ref {
        const key: Key = .{ .record = @backingInt(record), .field = index };
        if (self.new.made.get(key)) |known| return known;
        const source = self.f.inst(record);
        const out = if (source.op == .undef)
            try self.newInst(.{ .op = .undef, .ty = ty })
        else
            try self.newInst(.{ .op = .record_get, .ty = ty, .a = record, .data = index, .span = source.span });
        try self.new.made.put(self.arena, key, out);
        if (source.op == .undef) return out;
        try self.new.list.append(self.arena, .{ .ref = out, .record = record, .field = index });
        try self.new.reads.append(self.arena, .{ .ref = out, .after = record });
        return out;
    }

    fn newInst(self: *Pass, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.f.insts.items.len));
        try self.f.insts.append(self.arena, inst);
        return ref;
    }

    /// Per new phi (in `phis` order): whether one of the values it may take was stored
    /// (by a `record_set` of the field or a `record_make`), not only read where a record
    /// was defined; through other new phis, to a fixed point.
    fn writing(self: *Pass) Error![]bool {
        const out = try self.arena.alloc(bool, self.new.phis.items.len);
        @memset(out, false);
        var changed = true;
        while (changed) {
            changed = false;
            for (self.new.phis.items, out) |added, *flag| {
                if (flag.*) continue;
                for (self.f.operands(self.f.inst(added.ref).data)) |operand| {
                    const stored = if (self.new.phi_index.get(@backingInt(operand))) |i| out[i] else !self.isMade(operand);
                    if (!stored) continue;
                    flag.* = true;
                    changed = true;
                    break;
                }
            }
        }
        return out;
    }

    /// Whether `ref` is a read or `undef` the pass made.
    fn isMade(self: *const Pass, ref: ir.Ref) bool {
        return ref.index() >= self.first_new;
    }

    /// Mark `value` and every new value it is built from as used.
    fn use(self: *Pass, used: *std.AutoHashMapUnmanaged(u32, void), value: ir.Ref) Error!void {
        var stack: std.ArrayList(ir.Ref) = .empty;
        try stack.append(self.arena, value);
        while (stack.pop()) |current| {
            if (!self.isMade(current)) continue;
            if ((try used.getOrPut(self.arena, @backingInt(current))).found_existing) continue;
            if (self.new.phi_index.contains(@backingInt(current))) {
                for (self.f.operands(self.f.inst(current).data)) |operand| try stack.append(self.arena, operand);
            }
        }
    }

    /// Put the used new phis at the top of their records' blocks and the used new reads
    /// right after their records' definitions.
    fn place(self: *Pass, used: *const std.AutoHashMapUnmanaged(u32, void)) Error!void {
        for (self.new.phis.items) |added| {
            if (!used.contains(@backingInt(added.ref))) continue;
            const block = &self.f.blocks.items[self.block_of[added.after.index()]];
            try block.insts.insert(self.arena, 0, added.ref);
        }
        for (self.new.reads.items) |added| {
            if (!used.contains(@backingInt(added.ref))) continue;
            const record = self.f.inst(added.after);
            const b = self.block_of[added.after.index()];
            if (record.op == .param or b == no_block) {
                try self.insertAfterPhis(0, added.ref);
                continue;
            }
            const block = &self.f.blocks.items[b];
            if (record.op == .phi) {
                try self.insertAfterPhis(b, added.ref);
                continue;
            }
            const at = std.mem.indexOfScalar(ir.Ref, block.insts.items, added.after).?;
            try block.insts.insert(self.arena, at + 1, added.ref);
        }
    }

    fn insertAfterPhis(self: *Pass, b: u32, ref: ir.Ref) Error!void {
        const block = &self.f.blocks.items[b];
        var at: usize = 0;
        while (at < block.insts.items.len) : (at += 1) {
            const op = self.f.inst(block.insts.items[at]).op;
            if (op != .phi and op != .copy) break;
        }
        try block.insts.insert(self.arena, at, ref);
    }
};
