//! Whole-program record field intervals (lane F2, NEW-CORE-F2-FIELD-1).
//!
//! Records are values: a record's field holds what the write that made the record put
//! there, and the only writes are the module's own `record_make` (each field), `record_set`
//! (one field, a `mut` callee's included) and `list_set_field` (a field inside a list
//! element, in place). Moving a record into or out of a list, dictionary, box, union,
//! array, phi, call or return copies it whole and writes no field. So the hull of every
//! value those writes store into field `i` of records of type `R` bounds every read of it,
//! provided every record of type `R` was made by the module: a type is closed only when no
//! runtime or extern function takes or returns a value containing it, the entry function's
//! parameters do not contain it, and no operation outside the copying ones above produces
//! a value containing it. A field of an open record is open too.
//!
//! The intervals come from facts computed with the previous intervals (the type ranges at
//! first), so each round's hull holds for every record whatever the previous round knew:
//! the sequence only narrows, and every round is sound on its own.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// The fields' intervals from the writes of `module` under `known` (per function, null
/// where not analysed), for the record types `closed` marks (by compound index).
/// `sabotage` (`--sabotage-facts=field`) drops each interval's top, a deliberately wrong
/// rule for testing the verify mode.
pub fn hulls(arena: std.mem.Allocator, module: *const ir.Module, known: []const ?facts.Facts, closed: []const bool, sabotage: bool) std.mem.Allocator.Error!facts.FieldIntervals {
    const count = module.compounds.items.len;
    const tables = try arena.alloc(?[]?facts.Interval, count);
    // A field nothing writes stays unknown: no interval is claimed for a record never made.
    const written = try arena.alloc(?[]bool, count);
    for (tables, written, 0..) |*table, *seen, index| {
        table.* = null;
        seen.* = null;
        if (!closed[index]) continue;
        const fields = switch (module.compounds.items[index]) {
            .record => |fields| fields,
            else => continue,
        };
        table.* = try arena.alloc(?facts.Interval, fields.len);
        seen.* = try arena.alloc(bool, fields.len);
        for (fields, table.*.?, seen.*.?) |field, *slot, *flag| {
            slot.* = facts.typeRange(field);
            flag.* = false;
        }
    }
    var writes: Writes = .{ .module = module, .tables = tables, .written = written };
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const facts_of = if (index < known.len) known[index] else null;
        for (function.blocks.items, 0..) |block, b| {
            if (facts_of) |table| if (b < table.reachable.len and !table.reachable[b]) continue;
            for (block.insts.items) |ref| writes.note(function, if (facts_of) |*table| table else null, function.inst(ref));
        }
    }
    const out = try arena.alloc(?[]const ?facts.Interval, count);
    for (out, tables, written) |*slot, table, seen| {
        const fields = table orelse {
            slot.* = null;
            continue;
        };
        for (fields, seen.?) |*field, flag| {
            if (!flag) field.* = null;
            if (field.*) |*range| {
                if (sabotage and range.hi > range.lo) range.hi -= 1;
            }
        }
        slot.* = fields;
    }
    return .{ .module = module, .types = out };
}

/// One reachable write, including an unknown interval when a write is unbounded.
pub const Write = struct { record: ir.Type, field: u32, range: ?facts.Interval };
/// Body-independent evidence retained from an exploratory fact round.
pub const Contribution = struct {
    writes: []const Write,
    opens: []const ir.Type,
    references: []const u32,

    /// Reject evidence with invalid physical types, fields, intervals or function IDs.
    pub fn valid(self: Contribution, module: *const ir.Module) bool {
        for (self.writes) |write| {
            if (!write.record.isCompound()) return false;
            const index = @backingInt(write.record) - ir.Type.first_compound;
            if (index >= module.compounds.items.len) return false;
            const compound = module.compounds.items[index];
            if (compound != .record or write.field >= compound.record.len) return false;
            if (write.range) |range| if (range.lo > range.hi) return false;
        }
        for (self.opens) |ty| {
            if (!ty.isCompound()) return false;
            if (@backingInt(ty) - ir.Type.first_compound >= module.compounds.items.len) return false;
        }
        for (self.references) |target| if (target >= module.functions.items.len) return false;
        return true;
    }
};

fn addWrite(arena: std.mem.Allocator, writes: *std.ArrayList(Write), record: ir.Type, field: usize, range: ?facts.Interval) std.mem.Allocator.Error!void {
    if (!record.isCompound()) return;
    try writes.append(arena, .{ .record = record, .field = @intCast(field), .range = range });
}

/// Capture sparse writes and producer/escape evidence while this phase's body is live.
pub fn contribution(arena: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function, known: *const facts.Facts) std.mem.Allocator.Error!Contribution {
    var writes: std.ArrayList(Write) = .empty;
    for (function.blocks.items, 0..) |block, index| {
        if (!known.reachable[index]) continue;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            switch (inst.op) {
                .record_make => for (function.operands(inst.data), 0..) |operand, field| {
                    try addWrite(arena, &writes, inst.ty, field, rangeOf(function, known, operand));
                },
                .record_set => try addWrite(arena, &writes, inst.ty, @intCast(inst.data), rangeOf(function, known, inst.b)),
                .list_set_field => {
                    const operands = function.operands(inst.data);
                    if (operands.len != 2) continue;
                    const path_value = function.inst(function.resolve(operands[1]));
                    if (path_value.op != .iconst or module.kind(inst.ty) != .list) continue;
                    const target = facts.pathField(module, module.compound(inst.ty).list, ir.FieldPath.unpack(path_value.data)) orelse continue;
                    try addWrite(arena, &writes, target.record, target.field, rangeOf(function, known, operands[0]));
                },
                else => {},
            }
        }
    }
    var opens: std.ArrayList(ir.Type) = .empty;
    var references: std.ArrayList(u32) = .empty;
    for (function.insts.items) |inst| {
        if (inst.ty.isCompound() and !copies(inst.op) and std.mem.indexOfScalar(ir.Type, opens.items, inst.ty) == null) try opens.append(arena, inst.ty);
        if (inst.op == .func_ref) {
            const target: u32 = @intCast(inst.data);
            if (std.mem.indexOfScalar(u32, references.items, target) == null) try references.append(arena, target);
        }
    }
    return .{ .writes = writes.items, .opens = opens.items, .references = references.items };
}

/// Apply the same closure and write hull rules to deferred sparse contributions.
pub fn fromContributions(arena: std.mem.Allocator, module: *const ir.Module, contributions: []const ?Contribution, sabotage: bool) std.mem.Allocator.Error!facts.FieldIntervals {
    const count = module.compounds.items.len;
    const closed = try arena.alloc(bool, count);
    @memset(closed, true);
    const seen = try arena.alloc(bool, count);
    @memset(seen, false);
    var marks: Marks = .{ .module = module, .closed = closed, .seen = seen };
    const escapes = try arena.alloc(bool, module.functions.items.len);
    @memset(escapes, false);
    for (contributions) |optional| if (optional) |value| {
        for (value.opens) |ty| marks.open(ty);
        for (value.references) |target| if (target < escapes.len) {
            escapes[target] = true;
        };
    };
    for (module.functions.items, 0..) |function, index| {
        const outside = function.signature.linkage != .internal;
        if (outside or index == module.entry or escapes[index]) {
            for (function.signature.params) |param| marks.open(param);
            if (outside) marks.open(function.signature.ret);
        }
    }
    const tables = try arena.alloc(?[]?facts.Interval, count);
    const written = try arena.alloc(?[]bool, count);
    for (module.compounds.items, closed, tables, written) |compound, is_closed, *table, *flags| {
        table.* = null;
        flags.* = null;
        if (!is_closed or compound != .record) continue;
        table.* = try arena.alloc(?facts.Interval, compound.record.len);
        flags.* = try arena.alloc(bool, compound.record.len);
        for (compound.record, table.*.?) |ty, *slot| slot.* = facts.typeRange(ty);
        @memset(flags.*.?, false);
    }
    var writes: Writes = .{ .module = module, .tables = tables, .written = written };
    for (contributions) |optional| if (optional) |value| {
        for (value.writes) |write| writes.add(write.record, write.field, write.range);
    };
    const out = try arena.alloc(?[]const ?facts.Interval, count);
    for (out, tables, written) |*slot, table, flags| {
        slot.* = table;
        if (table) |ranges| for (ranges, flags.?) |*range, supplied| {
            if (!supplied) range.* = null;
            if (sabotage) if (range.*) |*interval| {
                if (interval.hi > interval.lo) interval.hi -= 1;
            };
        };
    }
    return .{ .module = module, .types = out };
}

/// The hulls being built: per record type, per field, the hull so far (null once a write
/// with no interval reaches it) and whether any write reached it.
const Writes = struct {
    module: *const ir.Module,
    tables: []?[]?facts.Interval,
    written: []?[]bool,

    fn note(self: *Writes, f: *const ir.Function, known: ?*const facts.Facts, inst: ir.Inst) void {
        switch (inst.op) {
            .record_make => {
                for (f.operands(inst.data), 0..) |operand, k| self.add(inst.ty, k, rangeOf(f, known, operand));
            },
            .record_set => self.add(inst.ty, @intCast(inst.data), rangeOf(f, known, inst.b)),
            .list_set_field => {
                const operands = f.operands(inst.data);
                if (operands.len != 2) return;
                const path_value = f.inst(f.resolve(operands[1]));
                if (path_value.op != .iconst) return;
                if (self.module.kind(inst.ty) != .list) return;
                const target = facts.pathField(self.module, self.module.compound(inst.ty).list, ir.FieldPath.unpack(path_value.data)) orelse return;
                self.add(target.record, target.field, rangeOf(f, known, operands[0]));
            },
            else => {},
        }
    }

    fn add(self: *Writes, record: ir.Type, field: usize, range: ?facts.Interval) void {
        if (!record.isCompound()) return;
        const index = @backingInt(record) - ir.Type.first_compound;
        if (index >= self.tables.len) return;
        const table = self.tables[index] orelse return;
        const seen = self.written[index].?;
        if (field >= table.len) return;
        const so_far = table[field] orelse return;
        const value = range orelse {
            seen[field] = true;
            table[field] = null;
            return;
        };
        table[field] = if (seen[field]) so_far.hull(value) else value;
        seen[field] = true;
    }
};

/// The interval of an integer or boolean value where it is defined (null for any other).
fn rangeOf(f: *const ir.Function, known: ?*const facts.Facts, raw: ir.Ref) ?facts.Interval {
    const ref = f.resolve(raw);
    const inst = f.inst(ref);
    const full = facts.typeRange(inst.ty) orelse return null;
    const table = known orelse return full;
    if (ref.index() >= table.ranges.len) return full;
    return facts.valueRange(table, f, ref) orelse full;
}

/// Per compound type, by index: whether every record of it is made by the module.
pub fn closedTypes(arena: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error![]bool {
    const count = module.compounds.items.len;
    const closed = try arena.alloc(bool, count);
    @memset(closed, true);
    const seen = try arena.alloc(bool, count);
    @memset(seen, false);
    var marks: Marks = .{ .module = module, .closed = closed, .seen = seen };
    // A function value may be called from outside the module (a registered callback).
    const escapes = try arena.alloc(bool, module.functions.items.len);
    @memset(escapes, false);
    for (module.functions.items) |function| for (function.insts.items) |inst| {
        if (inst.op == .func_ref and inst.data < escapes.len) escapes[@intCast(inst.data)] = true;
    };
    // Values the runtime, extern code or the host made, and operations that make values
    // other than by copying records the module made.
    for (module.functions.items, 0..) |function, index| {
        const outside = function.signature.linkage != .internal;
        if (outside or index == module.entry or escapes[index]) {
            for (function.signature.params) |param| marks.open(param);
            if (outside) marks.open(function.signature.ret);
        }
        if (outside) continue;
        for (function.insts.items) |inst| {
            if (!copies(inst.op)) marks.open(inst.ty);
        }
    }
    // `Marks.open` walks into an open record's fields: a record inside it was made where it was.
    return closed;
}

/// Whether an operation's result holds only records the module made, copied whole.
fn copies(op: ir.Op) bool {
    return switch (op) {
        .param, .undef, .copy, .phi, .func_ref, .call, .call_indirect => true,
        .record_make, .record_set, .record_get => true,
        .list_new, .list_get, .list_get_field, .list_push, .list_copy, .list_set, .list_pop, .list_set_field, .list_sort => true,
        .union_make, .union_payload, .box_make, .box_get, .array_get, .array_set => true,
        .dict_new, .dict_entry_key, .dict_entry_value, .dict_set_value, .dict_insert, .dict_remove, .dict_copy, .dict_clear => true,
        else => false,
    };
}

/// The record types found open so far, and the compound types already walked.
const Marks = struct {
    module: *const ir.Module,
    closed: []bool,
    seen: []bool,

    /// Mark every record type a value of `ty` may contain as open.
    fn open(self: *Marks, ty: ir.Type) void {
        if (!ty.isCompound()) return;
        const index = @backingInt(ty) - ir.Type.first_compound;
        if (index >= self.seen.len or self.seen[index]) return;
        self.seen[index] = true;
        switch (self.module.compound(ty)) {
            .list => |element| self.open(element),
            .record => |fields| {
                self.closed[index] = false;
                for (fields) |field| self.open(field);
            },
            .@"union" => |cases| for (cases) |case| self.open(case),
            .box => |inner| self.open(inner),
            .dict => |dict| {
                self.open(dict.key);
                self.open(dict.value);
            },
            .array => |array| self.open(array.elem),
            .@"fn" => {},
        }
    }
};
