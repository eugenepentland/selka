//! Slices used only as text-dictionary keys borrow their source (NEW-CORE-S1-VIEW-1).
//!
//! `d.get(s[i:j], …)`, `s[i:j] in d`, `d[s[i:j]]` and the fused get-then-set update all
//! probe with the slice and, on a miss, may insert it. When those are the slice's only
//! uses, the slice becomes a `str_slice_view` of `s`: the probe hashes and compares the
//! octets in place, and an insert materializes its own key (`str_from_view`) right before
//! it, keeping the probe it already has. The view lives in SSA only (`verify_ir`), and
//! ownership keeps `s` alive and unchanged for as long as any use of the view remains
//! (a borrowed part's uses keep its parent live, `own.zig`), so the view never dangles.
const std = @import("std");
const ir = @import("ir.zig");

/// Rewrite every qualifying slice of every internal function; returns how many changed.
pub fn run(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    for (module.functions.items) |*function| {
        if (function.signature.linkage != .internal) continue;
        changed += try rewriteFunction(arena, module, function);
    }
    return changed;
}

/// Rewrite the qualifying slices of one function; returns how many changed.
pub fn rewriteFunction(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const count = f.insts.items.len;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        if (inst.op != .str_slice or inst.ty != .str) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        if (!onlyKeys(f, module, ref)) continue;
        f.insts.items[index].op = .str_slice_view;
        f.insts.items[index].ty = .str_view;
        try materializeInsertions(arena, f, ref);
        changed += 1;
    }
    return changed;
}

/// Whether every use of `slice` is the key of a text-dictionary lookup or insert, with at
/// least one lookup. A forwarding copy stands for the slice itself.
fn onlyKeys(f: *const ir.Function, module: *const ir.Module, slice: ir.Ref) bool {
    var lookups: usize = 0;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != slice) continue;
            const lookup = inst.op == .dict_find and at == 1;
            const insertion = inst.op == .dict_insert and at == 2;
            if (!lookup and !insertion) return false;
            const ty = f.inst(f.resolve(inst.a)).ty;
            if (module.kind(ty) != .dict or module.compound(ty).dict.key != .str) return false;
            if (lookup) lookups += 1;
        }
    }
    return lookups != 0;
}

/// Retype the view's copies and give each insert a key materialized from the view.
fn materializeInsertions(arena: std.mem.Allocator, f: *ir.Function, view: ir.Ref) std.mem.Allocator.Error!void {
    const count = f.insts.items.len;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        if (inst.op == .copy and f.resolve(inst.a) == view) {
            f.insts.items[index].ty = .str_view;
            continue;
        }
        if (inst.op != .dict_insert or f.resolve(f.operands(inst.data)[0]) != view) continue;
        const value = f.operands(inst.data)[1];
        const key: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
        try f.insts.append(arena, .{ .op = .str_from_view, .ty = .str, .a = view, .span = inst.span });
        try before(arena, f, @fromBackingInt(@intCast(index)), key);
        const start: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(arena, &.{ key, value });
        f.insts.items[index].data = (ir.ExtraSlice{ .start = start, .len = 2 }).pack();
    }
}

fn before(arena: std.mem.Allocator, f: *ir.Function, ref: ir.Ref, added: ir.Ref) std.mem.Allocator.Error!void {
    for (f.blocks.items) |*block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| {
            try block.insts.insert(arena, at, added);
            return;
        }
    }
    // An instruction no block holds is dead: its key is never emitted either.
}
