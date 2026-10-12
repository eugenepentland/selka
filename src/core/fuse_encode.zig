//! Local read-only encodings borrow octets; escaping encodings remain independent owners.
const std = @import("std");
const ir = @import("ir.zig");
const slices = @import("fuse_slice_key.zig");

/// Borrow complete local octet read sets, recording runtime declarations for the cache.
pub fn runRecording(a: std.mem.Allocator, module: *ir.Module, requests: ?[]std.ArrayList(u32)) std.mem.Allocator.Error!u32 {
    if (!module.zero_rc or !offsetAvailable(module)) return 0;
    var changed: u32 = 0;
    const count = module.functions.items.len;
    for (0..count) |fi| {
        var f = module.functions.items[fi];
        if (f.signature.linkage != .internal) continue;
        const n = f.insts.items.len;
        // Bound complete-use and source-stability scans independently of source size.
        if (n > 4096) continue;
        var candidates: u32 = 0;
        for (0..n) |i| {
            const inst = f.insts.items[i];
            if (!named(module, inst, "myl_core_text_encode") or inst.ty != .bytes) continue;
            if (candidates == 32) break;
            candidates += 1;
            const args = f.operands(inst.data);
            if (args.len != 1 or f.inst(f.resolve(args[0])).ty != .str or
                !std.mem.eql(ir.Type, module.functions.items[inst.a.index()].signature.params, &.{.str})) continue;
            const source = args[0];
            const ref: ir.Ref = @fromBackingInt(@intCast(i));
            if (!reads(module, &f, ref) or try slices.updated(a, &f, module, f.resolve(source))) continue;
            const zero = try append(a, &f, .{ .op = .iconst, .ty = .u64 });
            const len = try append(a, &f, .{ .op = .str_len, .ty = .u64, .a = source, .span = inst.span });
            try before(a, &f, ref, &.{ zero, len });
            const extra: u32 = @intCast(f.extra.items.len);
            try f.extra.append(a, len);
            f.insts.items[i] = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = zero, .data = (ir.ExtraSlice{ .start = extra, .len = 1 }).pack(), .span = inst.span };
            for (0..n) |j| {
                const use = f.insts.items[j];
                if (use.op == .copy and f.resolve(use.a) == ref) f.insts.items[j].ty = .str_view;
                if (use.op == .list_len and f.resolve(use.a) == ref) f.insts.items[j].op = .str_len;
                if (named(module, use, "myl_core_bytes_index_offset") and f.resolve(f.operands(use.data)[0]) == ref) {
                    const callee = try offsetCallee(a, module);
                    f.insts.items[j].a = callee;
                    try recordRequest(a, requests, fi, callee);
                }
            }
            changed += 1;
        }
        module.functions.items[fi] = f;
    }
    return changed;
}

fn named(module: *const ir.Module, inst: ir.Inst, name: []const u8) bool {
    if (inst.op != .call or inst.a.index() >= module.functions.items.len) return false;
    const callee = module.functions.items[inst.a.index()];
    const sig = callee.signature;
    if (sig.linkage != .runtime_c or sig.owned != 0 or sig.views != 0 or sig.consumes != 0) return false;
    if (!std.mem.eql(u8, callee.name, name)) return false;
    if (std.mem.eql(u8, name, "myl_core_text_encode")) return sig.ret == .bytes and std.mem.eql(ir.Type, sig.params, &.{.str});
    return sig.ret == .u64 and std.mem.eql(ir.Type, sig.params, &.{ .bytes, .i64 });
}

fn reads(module: *const ir.Module, f: *const ir.Function, ref: ir.Ref) bool {
    var found = false;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != ref) continue;
            found = true;
            if (at == 0 and (inst.op == .list_len or (inst.op == .list_get and inst.ty == .u8))) continue;
            if (at == 0 and named(module, inst, "myl_core_bytes_index_offset") and f.operands(inst.data).len == 2) continue;
            return false;
        }
    }
    return found;
}

fn offsetCallee(a: std.mem.Allocator, module: *ir.Module) !ir.Ref {
    const symbol = "myl_core_span_bytes_index_offset";
    for (module.functions.items, 0..) |f, i| {
        const sig = f.signature;
        if (!std.mem.eql(u8, f.name, symbol)) continue;
        if (sig.views != 1 or sig.owned != 0 or sig.consumes != 0) continue;
        if (sig.ret != .u64 or sig.linkage != .runtime_c or !std.mem.eql(ir.Type, sig.params, &.{ .str, .i64 })) continue;
        return @fromBackingInt(@intCast(i));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(a, .{ .name = symbol, .signature = .{ .params = &.{ .str, .i64 }, .ret = .u64, .linkage = .runtime_c, .views = 1 } });
    return ref;
}
fn append(a: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) !ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(a, inst);
    return ref;
}
fn before(a: std.mem.Allocator, f: *ir.Function, ref: ir.Ref, added: []const ir.Ref) !void {
    for (f.blocks.items) |*b| if (std.mem.indexOfScalar(ir.Ref, b.insts.items, ref)) |at| {
        try b.insts.insertSlice(a, at, added);
        return;
    };
}

fn recordRequest(a: std.mem.Allocator, requests: ?[]std.ArrayList(u32), fi: usize, callee: ir.Ref) !void {
    const all = requests orelse return;
    if (fi < all.len) try all[fi].append(a, @intCast(callee.index()));
}

fn offsetAvailable(module: *const ir.Module) bool {
    for (module.functions.items) |f| {
        if (!std.mem.eql(u8, f.name, "myl_core_span_bytes_index_offset")) continue;
        const sig = f.signature;
        if (sig.views != 1 or sig.owned != 0 or sig.consumes != 0) return false;
        if (sig.ret != .u64 or sig.linkage != .runtime_c or !std.mem.eql(ir.Type, sig.params, &.{ .str, .i64 })) return false;
    }
    return true;
}
