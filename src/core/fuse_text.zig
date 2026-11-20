//! UTF-8 cursors and scalar-use fusion over immutable string SSA values.
const std = @import("std");
const ir = @import("ir.zig");
const scalar = @import("fuse_text_scalar.zig");
const flags = @import("flags.zig");

/// Borrow dictionary keys in private whitespace-split loops before ownership.
pub fn whitespace(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!void {
    try @import("fuse_text_split.zig").run(arena, module);
}

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
            const call = cursorCall(module, f, inst) orelse continue;
            if (f.resolve(call.index) != counter) continue;
            const text = f.resolve(call.text);
            const definition = f.inst(text);
            // A block parameter or constant, or a plain `str` parameter's view (C9 S1): the same octets either way.
            const plain = definition.ty == .str and (definition.op == .param or definition.op == .str_const);
            const view = definition.ty == .str_view and definition.op == .param;
            if (!plain and !view) continue;
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
            const call = cursorCall(module, f, inst.*) orelse continue;
            if (f.resolve(call.text) == source and f.resolve(call.index) == counter) {
                inst.* = .{ .op = .copy, .ty = .u64, .a = offset };
                changed += 1;
            }
        }
    }
    changed += try scalar.run(arena, module, f);
    return changed;
}

/// The text and the index of a checked offset read: `myl_core_str_offset(text, index)`, or the owner-explicit
/// `myl_core_xc_index(owner, text, index)` that a plain `str` parameter's view takes (C9 S1).
const Cursor = struct { text: ir.Ref, index: ir.Ref };

fn cursorCall(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?Cursor {
    if (inst.op != .call or inst.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[inst.a.index()];
    const args = f.operands(inst.data);
    if (flags.textOffset(callee.signature, callee.name) == .normalized) return .{ .text = args[0], .index = args[1] };
    if (std.mem.eql(u8, callee.name, "myl_core_xc_index") and args.len == 3 and callee.signature.ret == .u64) return .{ .text = args[1], .index = args[2] };
    return null;
}

fn append(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}
