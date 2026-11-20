//! A repeated checked operation on every incoming phi edge proves the header
//! operation safe, without imposing a global interval on mutable record fields.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const keys_mod = @import("index_keys.zig");

const Expression = struct { op: ir.Op, base: keys_mod.Key, amount: u64 };

/// Prove signed constant additions/subtractions already checked on every edge.
pub fn run(a: std.mem.Allocator, f: *ir.Function) std.mem.Allocator.Error!u32 {
    const shape = try facts.shape(a, f);
    const keys = try keys_mod.compute(a, f, shape.rpo);
    const context: Context = .{ .f = f, .shape = &shape, .keys = &keys };
    var proven: u32 = 0;
    for (shape.rpo) |block| for (f.blocks.items[block.index()].insts.items) |ref| {
        if (f.inst(ref).check != .exact) continue;
        const expression = context.expression(ref) orelse continue;
        if (!context.everyEdge(expression, block)) continue;
        f.insts.items[ref.index()].check = .proven;
        proven += 1;
    };
    return proven;
}

const Context = struct {
    f: *const ir.Function,
    shape: *const facts.Shape,
    keys: *const keys_mod.Keys,

    fn expression(self: Context, ref: ir.Ref) ?Expression {
        const inst = self.f.inst(ref);
        if (inst.ty != .i64 or (inst.op != .add and inst.op != .sub) or inst.check == .none) return null;
        const right = self.f.inst(self.f.resolve(inst.b));
        if (right.op != .iconst or right.ty != .i64) return null;
        return .{ .op = inst.op, .base = self.keys.value(inst.a), .amount = right.data };
    }

    fn everyEdge(self: Context, wanted: Expression, block: ir.BlockId) bool {
        const phi = wanted.base.ref;
        if (phi == .none or self.f.inst(phi).op != .phi) return false;
        const header = self.shape.block_of[phi.index()] orelse return false;
        if (!self.dominates(header, block)) return false;
        const preds = self.f.blocks.items[header.index()].preds.items;
        const operands = self.f.operands(self.f.inst(phi).data);
        if (preds.len == 0 or preds.len != operands.len) return false;
        for (preds, operands) |pred, operand| {
            var translated = wanted;
            translated.base = if (wanted.base.field == 0) self.keys.value(operand) else self.keys.fieldOf(operand, wanted.base.field - 1);
            if (!self.available(pred, translated)) return false;
        }
        return true;
    }

    fn available(self: Context, pred: ir.BlockId, wanted: Expression) bool {
        if (self.shape.order[pred.index()] == std.math.maxInt(u32)) return false;
        if (wanted.base.field == 0 and self.f.inst(wanted.base.ref).op == .iconst) {
            const value: i64 = @bitCast(self.f.inst(wanted.base.ref).data);
            const amount: i64 = @bitCast(wanted.amount);
            _ = (if (wanted.op == .add) std.math.add(i64, value, amount) else std.math.sub(i64, value, amount)) catch return false;
            return true;
        }
        var current: ?ir.BlockId = pred;
        var left = self.f.blocks.items.len;
        while (current) |block| {
            if (left == 0) return false;
            left -= 1;
            for (self.f.blocks.items[block.index()].insts.items) |ref| {
                const earlier = self.expression(ref) orelse continue;
                if (std.meta.eql(earlier, wanted)) return true;
            }
            if (block.index() == 0) return false;
            current = self.shape.idom[block.index()];
        }
        return false;
    }

    // twin-drift-ok: borrow_fields.before compares original instruction positions;
    // this check deliberately admits the whole phi block for the edge induction.
    fn dominates(self: Context, from: ir.BlockId, to: ir.BlockId) bool {
        var current: ?ir.BlockId = to;
        var left = self.f.blocks.items.len;
        while (current) |block| {
            if (block == from) return true;
            if (left == 0 or block.index() == 0) return false;
            left -= 1;
            current = self.shape.idom[block.index()];
        }
        return false;
    }
};
