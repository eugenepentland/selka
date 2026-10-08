//! Function signatures, target folding and sort-key layout for S2-F.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("mylang").typed;

/// Map a callback contract to the same by-value mut ABI as a direct function.
pub fn mapCallable(context: anytype, callback: typed.Callable, span: u32) error{ OutOfMemory, Unsupported }!ir.Type {
    var params: std.ArrayList(ir.Type) = .empty;
    var parts: std.ArrayList(ir.Type) = .empty;
    const declared = try context.mapType(callback.return_type, span);
    if (declared != .void) try parts.append(context.allocator, declared);
    var owned: u64 = 0;
    for (callback.parameters, 0..) |parameter, position| {
        const mapped = try context.mapType(parameter, span);
        const mutated = std.mem.indexOfScalar(u16, callback.mutates, @intCast(position)) != null;
        if (mutated) {
            try parts.append(context.allocator, mapped);
            if (mapped != .void) {
                if (params.items.len >= 64) return context.refuse("owned callback parameter position", span);
                owned |= @as(u64, 1) << @as(u6, @intCast(params.items.len));
            }
        }
        if (mapped != .void) try params.append(context.allocator, mapped);
    }
    const ret = if (callback.mutates.len == 0) declared else if (parts.items.len == 1) parts.items[0] else try context.module.intern(context.allocator, .{ .record = parts.items });
    return context.module.intern(context.allocator, .{ .@"fn" = .{ .params = params.items, .ret = ret, .owned = owned } });
}

/// Fold an indirect call whose resolved target is a function constant.
pub fn directTarget(function: *const ir.Function, call: *ir.Inst) void {
    if (call.op != .call_indirect) return;
    const target = function.inst(function.resolve(call.a));
    if (target.op != .func_ref) return;
    call.op = .call;
    call.a = @fromBackingInt(@as(u32, @intCast(target.data)));
}

/// The element kind and width used by the adaptive stable-sort runtime.
pub fn sortKind(module: ir.Module, element: ir.Type) ?u64 {
    if (element == .str) return 3 | (8 << 8);
    if (element == .bytes) return 4 | (8 << 8);
    if (element == .f64) return 2 | (8 << 8);
    if (element == .bool) return 1 | (1 << 8);
    const info = element.integer() orelse return null;
    return @as(u64, @intFromBool(!info.signed)) | (@as(u64, module.size(element)) << 8);
}

/// Packed field kinds and offsets expected by the keyed-sort runtime.
pub const KeyShape = struct { shape: u64, offsets: u64 };

/// Describe a scalar or a flat tuple key without exposing runtime storage in IR.
pub fn keyShape(module: ir.Module, ty: ir.Type) ?KeyShape {
    const fields = if (module.kind(ty) == .record) module.compound(ty).record else &.{ty};
    if (fields.len == 0 or fields.len > 8) return null;
    var result: KeyShape = .{ .shape = @intCast(fields.len), .offsets = 0 };
    for (fields, 0..) |field, i| {
        const kind = sortKind(module, field) orelse return null;
        const size = module.size(field);
        const width: u64 = switch (size) {
            8 => 0,
            4 => 1,
            2 => 2,
            1 => 3,
            else => return null,
        };
        const code: u64 = if (field == .bytes) 7 else (kind & 255) | (width << 2);
        const offset = if (module.kind(ty) == .record) module.fieldOffset(ty, i) else 0;
        if (offset > 255) return null;
        result.shape |= code << @as(u6, @intCast(4 + 4 * i));
        result.offsets |= @as(u64, offset) << @as(u6, @intCast(8 * i));
    }
    return result;
}

/// Expose a two-target function choice as ordinary control flow, so S0 loop
/// unswitching and leaf inlining can specialize the calls without pointer facts.
pub fn specialize(arena: std.mem.Allocator, function: *ir.Function) std.mem.Allocator.Error!u32 {
    var count: u32 = 0;
    var block_index: usize = 0;
    while (block_index < function.blocks.items.len) : (block_index += 1) {
        var at: usize = 0;
        while (at < function.blocks.items[block_index].insts.items.len) : (at += 1) {
            const ref = function.blocks.items[block_index].insts.items[at];
            var call = function.inst(ref);
            if (call.op != .call_indirect) continue;
            directTarget(function, &call);
            if (call.op == .call) {
                function.insts.items[ref.index()] = call;
                continue;
            }
            if (call.ty == .void) continue;
            const choice = targetChoice(function, call.a) orelse continue;
            try splitCall(arena, function, .{ .block = @fromBackingInt(@as(u32, @intCast(block_index))), .at = at, .ref = ref, .call = call }, choice);
            count += 1;
            break;
        }
    }
    return count;
}

const Choice = struct { condition: ir.Ref, yes: u32, no: u32 };
const CallSite = struct { block: ir.BlockId, at: usize, ref: ir.Ref, call: ir.Inst };

fn targetChoice(function: *const ir.Function, target: ir.Ref) ?Choice {
    const resolved = function.resolve(target);
    const phi = function.inst(resolved);
    if (phi.op != .phi) return null;
    const values = function.operands(phi.data);
    if (values.len != 2) return null;
    const first = function.inst(function.resolve(values[0]));
    const second = function.inst(function.resolve(values[1]));
    if (first.op != .func_ref or second.op != .func_ref) return null;
    for (function.blocks.items) |block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, resolved) == null or block.preds.items.len != 2) continue;
        const a = block.preds.items[0];
        const b = block.preds.items[1];
        const left = function.blocks.items[a.index()];
        const right = function.blocks.items[b.index()];
        if (left.preds.items.len != 1 or right.preds.items.len != 1 or left.preds.items[0] != right.preds.items[0]) return null;
        const parent = function.blocks.items[left.preds.items[0].index()];
        const branch = function.inst(parent.insts.items[parent.insts.items.len - 1]);
        if (branch.op != .branch) return null;
        const targets = ir.unpackTargets(branch.data);
        if (targets.then == a and targets.otherwise == b) return .{ .condition = branch.a, .yes = @intCast(first.data), .no = @intCast(second.data) };
        if (targets.then == b and targets.otherwise == a) return .{ .condition = branch.a, .yes = @intCast(second.data), .no = @intCast(first.data) };
        return null;
    }
    return null;
}

fn addInst(arena: std.mem.Allocator, function: *ir.Function, block: ir.BlockId, inst: ir.Inst) !ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(function.insts.items.len)));
    try function.insts.append(arena, inst);
    try function.blocks.items[block.index()].insts.append(arena, ref);
    return ref;
}

fn splitCall(arena: std.mem.Allocator, function: *ir.Function, site: CallSite, choice: Choice) !void {
    const yes: ir.BlockId = @fromBackingInt(@as(u32, @intCast(function.blocks.items.len)));
    const no: ir.BlockId = @fromBackingInt(@as(u32, @intCast(function.blocks.items.len + 1)));
    const join: ir.BlockId = @fromBackingInt(@as(u32, @intCast(function.blocks.items.len + 2)));
    const tail = try arena.dupe(ir.Ref, function.blocks.items[site.block.index()].insts.items[site.at + 1 ..]);
    try function.blocks.appendNTimes(arena, .{}, 3);
    function.blocks.items[site.block.index()].insts.shrinkRetainingCapacity(site.at);
    try function.blocks.items[yes.index()].preds.append(arena, site.block);
    try function.blocks.items[no.index()].preds.append(arena, site.block);
    try function.blocks.items[join.index()].preds.appendSlice(arena, &.{ yes, no });
    _ = try addInst(arena, function, site.block, .{ .op = .branch, .ty = .void, .a = choice.condition, .data = ir.packTargets(yes, no), .span = site.call.span });
    var direct = site.call;
    direct.op = .call;
    direct.a = @fromBackingInt(choice.yes);
    const yes_value = try addInst(arena, function, yes, direct);
    direct.a = @fromBackingInt(choice.no);
    const no_value = try addInst(arena, function, no, direct);
    _ = try addInst(arena, function, yes, .{ .op = .jump, .ty = .void, .data = @backingInt(join) });
    _ = try addInst(arena, function, no, .{ .op = .jump, .ty = .void, .data = @backingInt(join) });
    if (site.call.ty != .void) {
        const start: u32 = @intCast(function.extra.items.len);
        try function.extra.appendSlice(arena, &.{ yes_value, no_value });
        function.insts.items[site.ref.index()] = .{ .op = .phi, .ty = site.call.ty, .data = (ir.ExtraSlice{ .start = start, .len = 2 }).pack(), .span = site.call.span };
        try function.blocks.items[join.index()].insts.append(arena, site.ref);
    }
    try function.blocks.items[join.index()].insts.appendSlice(arena, tail);
    for (function.blocks.items, 0..) |*block, b| {
        if (b == yes.index() or b == no.index() or b == join.index()) continue;
        for (block.preds.items) |*pred| if (pred.* == site.block) {
            pred.* = join;
        };
    }
    for (function.loops.items) |*loop| if (loop.latch == site.block) {
        loop.latch = join;
    };
}
