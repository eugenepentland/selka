//! Small CFG helper inlining, including scalar projections of mut return records.
const std = @import("std");
const ir = @import("ir.zig");
const origins = @import("inline_origins.zig");

/// A loop helper qualifies only within bounded expansion and without further calls.
pub fn qualifies(f: *const ir.Function) bool {
    if (f.signature.linkage != .internal or f.signature.ret == .void) return false;
    if (f.blocks.items.len < 2 or f.blocks.items.len > 20) return false;
    var size: usize = 0;
    var returns: usize = 0;
    var reads: usize = 0;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        size += 1;
        if (f.signature.owned == 0 and !projectionOp(f.inst(ref).op)) return false;
        if (f.inst(ref).op == .list_get) reads += 1;
        switch (f.inst(ref).op) {
            .call, .call_indirect, .print, .err_trace => return false,
            .ret => returns += 1,
            else => {},
        }
    };
    if (f.signature.owned == 0) return returns == 1 and reads == 1 and size <= 24 and f.loops.items.len == 0;
    return returns != 0 and size <= 100;
}

// Checked stack peeks are small read-only CFGs. Splicing preserves each check
// and its inline ancestry, including a trap in the negative-index arm.
fn projectionOp(op: ir.Op) bool {
    return switch (op) {
        .param, .iconst, .copy, .record_get, .list_len, .list_get, .add, .sub, .cmp, .convert, .phi, .branch, .jump, .ret => true,
        else => false,
    };
}

/// Split one call site and clone the callee's complete control flow into its caller.
pub fn splice(arena: std.mem.Allocator, caller: *ir.Function, callee: *const ir.Function, block: usize, at: usize, clone: *origins.Clone) std.mem.Allocator.Error!void {
    const call = caller.blocks.items[block].insts.items[at];
    const original = caller.inst(call);
    const arguments = try arena.dupe(ir.Ref, caller.operands(original.data));
    const projections = try projected(arena, caller, callee, call);
    const tail: ir.BlockId = @fromBackingInt(@intCast(caller.blocks.items.len));
    var continuation: ir.Block = .{};
    try continuation.insts.appendSlice(arena, caller.blocks.items[block].insts.items[at..]);
    caller.blocks.items[block].insts.shrinkRetainingCapacity(at);
    try caller.blocks.append(arena, continuation);
    const context = clone.table.context(clone.caller);
    try context.setBlock(arena, @intCast(tail.index()), clone.table.block(clone.caller, @intCast(block)));
    const head: ir.BlockId = @fromBackingInt(@intCast(block));
    for (caller.blocks.items) |*successor| for (successor.preds.items) |*pred| {
        if (pred.* == head) pred.* = tail;
    };
    for (caller.loops.items) |*loop| if (loop.latch == head) {
        loop.latch = tail;
    };
    const base: u32 = @intCast(caller.blocks.items.len);
    for (callee.blocks.items) |_| try caller.blocks.append(arena, .{});
    const map = try arena.alloc(ir.Ref, callee.insts.items.len);
    for (callee.insts.items, 0..) |inst, index| {
        map[index] = if (inst.op == .param) arguments[@intCast(inst.data)] else try append(arena, caller, inst);
    }
    var returns: std.ArrayList(ir.Ref) = .empty;
    for (callee.blocks.items, 0..) |source, index| {
        try clone.block(arena, @intCast(index), base + @as(u32, @intCast(index)));
        const destination = &caller.blocks.items[base + index];
        if (index == 0) try destination.preds.append(arena, head);
        for (source.preds.items) |pred| try destination.preds.append(arena, moved(base, pred));
        for (source.insts.items) |ref| {
            var inst = callee.inst(ref);
            if (inst.op == .ret) {
                try returns.append(arena, inst.a);
                try caller.blocks.items[tail.index()].preds.append(arena, @fromBackingInt(@intCast(base + index)));
                inst = .{ .op = .jump, .ty = .void, .data = @backingInt(tail), .span = inst.span };
            } else {
                inst.a = remap(callee, map, inst.a);
                inst.b = remap(callee, map, inst.b);
                if (inst.op.hasExtra()) inst.data = try extra(arena, caller, callee, map, callee.operands(inst.data));
                if (inst.op == .jump) inst.data += base;
                if (inst.op == .branch) {
                    const targets = ir.unpackTargets(inst.data);
                    inst.data = ir.packTargets(moved(base, targets.then), moved(base, targets.otherwise));
                }
                if (projections.len != 0 and inst.op == .record_make and returned(callee, ref)) inst = .{ .op = .copy, .ty = .void };
            }
            caller.insts.items[map[ref.index()].index()] = inst;
            try clone.instruction(arena, @intCast(index), ref, map[ref.index()], false);
            try destination.insts.append(arena, map[ref.index()]);
        }
    }
    _ = try inBlock(arena, caller, head, .{ .op = .jump, .ty = .void, .data = base, .span = original.span });
    try finishResult(arena, .{ .caller = caller, .callee = callee, .call = call, .returns = returns.items, .map = map, .projections = projections }, tail);
    var loop_id: usize = 0;
    for (caller.loops.items) |loop| loop_id = @max(loop_id, loop.id + 1);
    for (callee.loops.items) |loop| {
        try caller.loops.append(arena, .{ .id = loop_id, .header = moved(base, loop.header), .body = moved(base, loop.body), .latch = moved(base, loop.latch), .exit = moved(base, loop.exit) });
        loop_id += 1;
    }
}

const Result = struct { caller: *ir.Function, callee: *const ir.Function, call: ir.Ref, returns: []const ir.Ref, map: []const ir.Ref, projections: []const ir.Ref };

fn finishResult(arena: std.mem.Allocator, result: Result, tail: ir.BlockId) std.mem.Allocator.Error!void {
    const original = result.caller.inst(result.call);
    if (result.projections.len == 0) {
        result.caller.insts.items[result.call.index()] = .{
            .op = if (result.returns.len == 1) .copy else .phi,
            .ty = original.ty,
            .a = if (result.returns.len == 1) remap(result.callee, result.map, result.returns[0]) else .none,
            .data = if (result.returns.len == 1) 0 else try extra(arena, result.caller, result.callee, result.map, result.returns),
            .span = original.span,
        };
    } else {
        var components: std.ArrayList(ir.Ref) = .empty;
        const first = result.callee.inst(result.callee.resolve(result.returns[0]));
        for (result.callee.operands(first.data), 0..) |component, index| {
            var values: std.ArrayList(ir.Ref) = .empty;
            for (result.returns) |returned_value| {
                const record = result.callee.inst(result.callee.resolve(returned_value));
                try values.append(arena, result.callee.operands(record.data)[index]);
            }
            const ty = result.callee.inst(result.callee.resolve(component)).ty;
            const projected_value = if (values.items.len == 1) remap(result.callee, result.map, values.items[0]) else try append(arena, result.caller, .{
                .op = .phi,
                .ty = ty,
                .data = try extra(arena, result.caller, result.callee, result.map, values.items),
                .span = original.span,
            });
            if (values.items.len != 1) try result.caller.blocks.items[tail.index()].insts.insert(arena, components.items.len, projected_value);
            try components.append(arena, projected_value);
        }
        for (result.projections) |ref| {
            const old = result.caller.inst(ref);
            result.caller.insts.items[ref.index()] = .{ .op = .copy, .ty = old.ty, .a = components.items[@intCast(old.data)], .span = old.span };
        }
        result.caller.insts.items[result.call.index()] = .{ .op = .copy, .ty = .void };
    }
}

fn projected(arena: std.mem.Allocator, caller: *const ir.Function, callee: *const ir.Function, call: ir.Ref) std.mem.Allocator.Error![]const ir.Ref {
    var fields: ?usize = null;
    for (callee.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = callee.inst(ref);
        if (inst.op != .ret) continue;
        const result = callee.resolve(inst.a);
        const record = callee.inst(result);
        if (record.op != .record_make) return &.{};
        const count = callee.operands(record.data).len;
        if (fields != null and fields.? != count) return &.{};
        fields = count;
        for (callee.insts.items) |user| {
            const operands = callee.valueOperands(user);
            for (0..operands.len()) |k| if (callee.resolve(operands.get(k)) == result and user.op != .ret) {
                return &.{};
            };
        }
    };
    var uses: std.ArrayList(ir.Ref) = .empty;
    for (caller.insts.items, 0..) |inst, index| {
        const operands = caller.valueOperands(inst);
        for (0..operands.len()) |k| if (caller.resolve(operands.get(k)) == call) {
            if (inst.op != .record_get or inst.data >= (fields orelse return &.{})) return &.{};
            try uses.append(arena, @fromBackingInt(@intCast(index)));
        };
    }
    return uses.items;
}

fn returned(callee: *const ir.Function, ref: ir.Ref) bool {
    for (callee.insts.items) |inst| if (inst.op == .ret and callee.resolve(inst.a) == ref) {
        return true;
    };
    return false;
}

fn moved(base: u32, block: ir.BlockId) ir.BlockId {
    return @fromBackingInt(base + @backingInt(block));
}

fn remap(callee: *const ir.Function, map: []const ir.Ref, ref: ir.Ref) ir.Ref {
    return if (ref == .none) .none else map[callee.resolve(ref).index()];
}

fn extra(arena: std.mem.Allocator, caller: *ir.Function, callee: *const ir.Function, map: []const ir.Ref, values: []const ir.Ref) std.mem.Allocator.Error!u64 {
    const start: u32 = @intCast(caller.extra.items.len);
    for (values) |value| try caller.extra.append(arena, remap(callee, map, value));
    return (ir.ExtraSlice{ .start = start, .len = @intCast(values.len) }).pack();
}

fn append(arena: std.mem.Allocator, function: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(arena, inst);
    return ref;
}

fn inBlock(arena: std.mem.Allocator, function: *ir.Function, block: ir.BlockId, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref = try append(arena, function, inst);
    try function.blocks.items[block.index()].insts.append(arena, ref);
    return ref;
}
