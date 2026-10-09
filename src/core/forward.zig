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
    var pass: Pass = .{ .arena = arena, .module = module, .f = f };
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
    var replaced: u32 = 0;
    for (reads.items) |ref| {
        const read = f.inst(ref);
        const value = try pass.field(f.resolve(read.a), read.data, read.ty) orelse continue;
        f.insts.items[ref.index()] = .{ .op = .copy, .ty = read.ty, .a = value, .span = read.span };
        replaced += 1;
    }
    try pass.place();
    return .{ .replaced = replaced, .made = pass.made_list.items };
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

const Pass = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *ir.Function,
    block_of: []u32 = &.{},
    /// Per record and field: the value that holds the field (a new phi, a read, or a
    /// value already there).
    made: std.AutoHashMapUnmanaged(Key, ir.Ref) = .empty,
    /// The phis and reads to put into blocks once every value is known.
    phis: std.ArrayList(Added) = .empty,
    reads: std.ArrayList(Added) = .empty,
    made_list: std.ArrayList(Made) = .empty,

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
        if (self.made.get(key)) |known| return known;
        // Copied: the reads and phis made below append to `extra`, which may move.
        const operands = try self.arena.dupe(ir.Ref, self.f.operands(self.f.inst(phi).data));
        const out = try self.newInst(.{ .op = .phi, .ty = ty, .span = self.f.inst(phi).span });
        try self.made.put(self.arena, key, out);
        try self.made_list.append(self.arena, .{ .ref = out, .record = phi, .field = index });
        try self.phis.append(self.arena, .{ .ref = out, .after = phi });
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
        if (self.made.get(key)) |known| return known;
        const source = self.f.inst(record);
        const out = if (source.op == .undef)
            try self.newInst(.{ .op = .undef, .ty = ty })
        else
            try self.newInst(.{ .op = .record_get, .ty = ty, .a = record, .data = index, .span = source.span });
        try self.made.put(self.arena, key, out);
        if (source.op == .undef) return out;
        try self.made_list.append(self.arena, .{ .ref = out, .record = record, .field = index });
        try self.reads.append(self.arena, .{ .ref = out, .after = record });
        return out;
    }

    fn newInst(self: *Pass, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.f.insts.items.len));
        try self.f.insts.append(self.arena, inst);
        return ref;
    }

    /// Put the new phis at the top of their records' blocks and the new reads right after
    /// their records' definitions.
    fn place(self: *Pass) Error!void {
        for (self.phis.items) |added| {
            const block = &self.f.blocks.items[self.block_of[added.after.index()]];
            try block.insts.insert(self.arena, 0, added.ref);
        }
        for (self.reads.items) |added| {
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
