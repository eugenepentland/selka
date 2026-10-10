//! Private split lists store offsets, retaining their source through each borrowed piece.
const std = @import("std");
const ir = @import("ir.zig");
const views = @import("fuse_slice_key.zig");
const facts = @import("facts.zig");

/// Replace nonescaping split lists with offset lists; escape sites materialize their piece.
pub fn run(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!void {
    const count = module.functions.items.len;
    for (0..count) |index| {
        var f = module.functions.items[index];
        if (f.signature.linkage != .internal) continue;
        const length = f.insts.items.len;
        for (0..length) |at| {
            const inst = f.insts.items[at];
            if (!eligible(&f, module, inst, @fromBackingInt(@intCast(at)))) continue;
            const source = f.operands(inst.data)[0];
            if (try views.updated(arena, &f, module, f.resolve(source))) continue;
            try rewrite(arena, &f, module, @fromBackingInt(@intCast(at)));
        }
        module.functions.items[index] = f;
    }
}

fn eligible(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst, ref: ir.Ref) bool {
    if (inst.op != .call or inst.a.index() >= module.functions.items.len) return false;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or target.signature.owned != 0 or target.signature.views != 0) return false;
    if (!std.mem.eql(u8, target.name, "myl_core_str_split") or !std.mem.eql(ir.Type, target.signature.params, &.{ .str, .str })) return false;
    if (module.kind(inst.ty) != .list or module.compound(inst.ty).list != .str) return false;
    for (f.insts.items) |user| {
        if (user.op == .copy) continue;
        const operands = f.valueOperands(user);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != ref) continue;
            if (at != 0 or (user.op != .list_len and user.op != .list_get)) return false;
        }
    }
    return true;
}

fn extra(arena: std.mem.Allocator, f: *ir.Function, args: []const ir.Ref) std.mem.Allocator.Error!u64 {
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(arena, args);
    return (ir.ExtraSlice{ .start = start, .len = @intCast(args.len) }).pack();
}
fn append(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, inst);
    return ref;
}
fn before(arena: std.mem.Allocator, f: *ir.Function, ref: ir.Ref, added: []const ir.Ref) std.mem.Allocator.Error!void {
    for (f.blocks.items) |*block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| {
            try block.insts.insertSlice(arena, at, added);
            return;
        }
    }
}
fn runtime(arena: std.mem.Allocator, module: *ir.Module, ty: ir.Type, limit: ?u64) std.mem.Allocator.Error!ir.Ref {
    const name = if (limit) |n| try std.fmt.allocPrint(arena, "myl_core_str_split_prefix_{d}", .{n}) else "myl_core_str_split_offsets";
    for (module.functions.items, 0..) |f, at| {
        if (std.mem.eql(u8, f.name, name)) return @fromBackingInt(@intCast(at));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = name, .signature = .{ .params = &.{ .str, .str }, .ret = ty, .linkage = .runtime_c } });
    return ref;
}
fn rewrite(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, ref: ir.Ref) std.mem.Allocator.Error!void {
    const source = f.operands(f.inst(ref).data)[0];
    var has_elements = false;
    for (f.insts.items) |inst| {
        if (inst.op == .list_get and f.resolve(inst.a) == ref) has_elements = true;
    }
    if (!has_elements) return countOnly(arena, f, module, ref);
    const pair = try module.intern(arena, .{ .record = &.{ .u64, .u64 } });
    const ty = try module.intern(arena, .{ .list = pair });
    f.insts.items[ref.index()].a = try runtime(arena, module, ty, try prefixLimit(arena, f, ref));
    f.insts.items[ref.index()].ty = ty;
    const count = f.insts.items.len;
    for (0..count) |at| {
        const inst = f.insts.items[at];
        if (inst.op == .copy and f.resolve(inst.a) == ref) f.insts.items[at].ty = ty;
        if (inst.op != .list_get or f.resolve(inst.a) != ref) continue;
        const element: ir.Ref = @fromBackingInt(@intCast(at));
        const readable = views.onlyReads(f, module, element);
        const offset = try append(arena, f, .{ .op = .list_get_field, .ty = .u64, .a = ref, .b = inst.b, .data = ir.FieldPath.init(&.{0}).?.pack(), .check = inst.check, .span = inst.span });
        const length = try append(arena, f, .{ .op = .list_get_field, .ty = .u64, .a = ref, .b = inst.b, .data = ir.FieldPath.init(&.{1}).?.pack(), .check = inst.check, .span = inst.span });
        try before(arena, f, element, &.{ offset, length });
        const view: ir.Inst = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = offset, .data = try extra(arena, f, &.{length}), .span = inst.span };
        if (readable) {
            f.insts.items[at] = view;
            try views.rewriteUses(arena, f, module, element);
        } else {
            const borrowed = try append(arena, f, view);
            try before(arena, f, element, &.{borrowed});
            f.insts.items[at] = .{ .op = .str_from_view, .ty = .str, .a = borrowed, .span = inst.span };
        }
    }
}

fn countOnly(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, ref: ir.Ref) std.mem.Allocator.Error!void {
    const helper: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = "myl_core_str_split_count", .signature = .{ .params = &.{ .str, .str }, .ret = .u64, .linkage = .runtime_c } });
    f.insts.items[ref.index()].a = helper;
    f.insts.items[ref.index()].ty = .u64;
    for (f.insts.items) |*inst| {
        if (inst.op == .copy and f.resolve(inst.a) == ref) inst.ty = .u64;
        if (inst.op == .list_len and f.resolve(inst.a) == ref) inst.* = .{ .op = .copy, .ty = .u64, .a = ref, .span = inst.span };
    }
}

fn prefixLimit(arena: std.mem.Allocator, f: *const ir.Function, ref: ir.Ref) !?u64 {
    const shape = try facts.shape(arena, f);
    var length: u64 = 0;
    for (f.insts.items, 0..) |inst, at| {
        if (inst.op != .list_get and inst.op != .list_len) continue;
        if (f.resolve(inst.a) != ref) continue;
        const block = shape.block_of[at] orelse continue;
        if (inst.op == .list_len) {
            if (!deadAdjustment(f, block)) return null;
            continue;
        }
        const index = f.resolve(inst.b);
        const join = shape.block_of[index.index()] orelse return null;
        const raw = facts.normalizedRaw(f, join, index) orelse index;
        const value = f.inst(raw);
        if (value.op != .iconst or value.data >= 8) return null;
        length = @max(length, value.data + 1);
    }
    return if (length == 0) null else length;
}
fn deadAdjustment(f: *const ir.Function, block: ir.BlockId) bool {
    const preds = f.blocks.items[block.index()].preds.items;
    if (preds.len != 1) return false;
    const insts = f.blocks.items[preds[0].index()].insts.items;
    if (insts.len == 0) return false;
    const branch = f.inst(insts[insts.len - 1]);
    if (branch.op != .branch or ir.unpackTargets(branch.data).then != block) return false;
    const condition = f.inst(f.resolve(branch.a));
    if (condition.op != .cmp or condition.data != @backingInt(ir.Predicate.lt)) return false;
    const left = f.inst(f.resolve(condition.a));
    const right = f.inst(f.resolve(condition.b));
    if (left.op != .iconst or left.ty != .i64 or left.data > std.math.maxInt(i64)) return false;
    return right.op == .iconst and right.data == 0;
}
