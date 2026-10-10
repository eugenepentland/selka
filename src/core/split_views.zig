//! Private split lists store offsets, retaining their source through each borrowed piece.
const std = @import("std");
const ir = @import("ir.zig");
const views = @import("fuse_slice_key.zig");

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
fn runtime(arena: std.mem.Allocator, module: *ir.Module, ty: ir.Type) std.mem.Allocator.Error!ir.Ref {
    for (module.functions.items, 0..) |f, at| {
        if (std.mem.eql(u8, f.name, "myl_core_str_split_offsets")) return @fromBackingInt(@intCast(at));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = "myl_core_str_split_offsets", .signature = .{ .params = &.{ .str, .str }, .ret = ty, .linkage = .runtime_c } });
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
    f.insts.items[ref.index()].a = try runtime(arena, module, ty);
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
