//! UTF-8 cursors and scalar-use fusion over immutable string SSA values.
const std = @import("std");
const ir = @import("ir.zig");

/// Convert scalar-index loops over an unchanged receiver into byte-offset loops.
pub fn cursors(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    for (f.loops.items) |loop| {
        const preds = f.blocks.items[loop.header.index()].preds.items;
        if (preds.len != 2) continue;
        var counter: ir.Ref = .none;
        var start_slot: usize = 0;
        for (f.blocks.items[loop.header.index()].insts.items) |ref| {
            const phi = f.inst(ref);
            if (phi.op != .phi or phi.ty.integer() == null) continue;
            const args = f.operands(phi.data);
            if (args.len != 2) continue;
            for (args, 0..) |arg, i| {
                const initial = f.inst(f.resolve(arg));
                const next = f.inst(f.resolve(args[1 - i]));
                if (initial.op != .iconst or initial.data != 0 or next.op != .add) continue;
                const left = f.resolve(next.a);
                const right = f.inst(f.resolve(next.b));
                if (left == ref and right.op == .iconst and right.data == 1 and preds[1 - i] == loop.latch) {
                    counter = ref;
                    start_slot = i;
                }
            }
        }
        if (counter == .none) continue;
        const original_len = f.insts.items.len;
        var source: ir.Ref = .none;
        for (f.insts.items[0..original_len]) |inst| {
            if (!offsetCall(module, inst)) continue;
            const args = f.operands(inst.data);
            if (f.resolve(args[1]) != counter) continue;
            const text = f.resolve(args[0]);
            const definition = f.inst(text);
            if (definition.ty != .str or (definition.op != .param and definition.op != .str_const)) continue;
            source = text;
            break;
        }
        if (source == .none) continue;
        const zero = try append(arena, f, .{ .op = .iconst, .ty = .u64 });
        const offset = try append(arena, f, .{ .op = .phi, .ty = .u64 });
        const width = try append(arena, f, .{ .op = .str_width, .ty = .u64, .a = source, .b = offset });
        const next = try append(arena, f, .{ .op = .add, .ty = .u64, .a = offset, .b = width });
        const extra: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(arena, if (start_slot == 0) &.{ zero, next } else &.{ next, zero });
        f.insts.items[offset.index()].data = (ir.ExtraSlice{ .start = extra, .len = 2 }).pack();
        var insertion: usize = 0;
        const header = &f.blocks.items[loop.header.index()].insts;
        while (insertion < header.items.len and f.inst(header.items[insertion]).op == .phi) insertion += 1;
        try header.insert(arena, insertion, offset);
        const latch = &f.blocks.items[loop.latch.index()].insts;
        try latch.insertSlice(arena, latch.items.len - 1, &.{ width, next });
        for (f.insts.items[0..original_len]) |*inst| {
            if (!offsetCall(module, inst.*)) continue;
            const args = f.operands(inst.data);
            if (f.resolve(args[0]) == source and f.resolve(args[1]) == counter) {
                inst.* = .{ .op = .copy, .ty = .u64, .a = offset };
                changed += 1;
            }
        }
    }
    changed += try scalarUses(arena, module, f);
    return changed;
}

fn offsetCall(module: *ir.Module, inst: ir.Inst) bool {
    return inst.op == .call and inst.a.index() < module.functions.items.len and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_str_offset");
}

fn append(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}

/// Eliminate a temporary scalar string when its only observable use appends that scalar.
fn scalarUses(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    _ = module;
    var changed: u32 = 0;
    const original_len = f.insts.items.len;
    for (0..original_len) |index| {
        const inst = f.insts.items[index];
        if (inst.op != .str_append) continue;
        const ref = f.resolve(inst.b);
        const character = f.inst(ref);
        if (character.op != .str_char or uses(f, ref) != 1 or f.resolve(inst.a) == f.resolve(character.a)) continue;
        const extra: u32 = @intCast(f.extra.items.len);
        try f.extra.append(arena, character.b);
        f.insts.items[index] = .{ .op = .str_append_char, .ty = .str, .a = inst.a, .b = character.a, .data = (ir.ExtraSlice{ .start = extra, .len = 1 }).pack(), .check = character.check, .span = character.span };
        f.insts.items[ref.index()] = .{ .op = .undef, .ty = .str };
        changed += 1;
    }
    return changed;
}

fn uses(f: *const ir.Function, ref: ir.Ref) u32 {
    var count: u32 = 0;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |index| if (f.resolve(operands.get(index)) == ref) {
            count += 1;
        };
    }
    return count;
}
