//! Split return payloads: a private destination pointer lets a fallible producer
//! fill an unused list slot without reserving, allocating, or committing early.
const std = @import("std");
const ir = @import("ir.zig");

/// The contiguous payload region of a returned union, optionally in field zero.
pub const Shape = struct { offset: u32, size: u32, ty: ir.Type };
/// A pushed payload and the direct call that produces its enclosing result.
pub const Push = struct { call: ir.Ref, payload: ir.Ref, list: ir.Ref };
/// One emitted alternative destination, also used by payload reads and the push.
pub const Destination = struct { pointer: []const u8, offset: u32 };
/// Per-function optional ABI shapes, excluding escaping and cross-unit targets.
pub fn shapes(arena: std.mem.Allocator, m: *const ir.Module) std.mem.Allocator.Error![]?Shape {
    const result = try arena.alloc(?Shape, m.functions.items.len);
    @memset(result, null);
    for (m.functions.items) |*f| for (f.insts.items) |inst| {
        const push = pushed(m, f, inst) orelse continue;
        const target = f.inst(push.call).a.index();
        result[target] = shape(m, m.functions.items[target].signature.ret);
    };
    var changed = true;
    while (changed) {
        changed = false;
        for (m.functions.items, result) |*f, outer| {
            const wanted = outer orelse continue;
            for (f.insts.items) |inst| {
                if (inst.op != .call) continue;
                const target = inst.a.index();
                if (result[target] != null) continue;
                const inner = shape(m, m.functions.items[target].signature.ret) orelse continue;
                if (inner.ty != wanted.ty) continue;
                result[target] = inner;
                changed = true;
            }
        }
    }
    for (m.functions.items) |f| for (f.insts.items) |inst| {
        if (inst.op == .func_ref) result[@intCast(inst.data)] = null;
    };
    for (m.functions.items, result) |f, *entry| {
        if (f.signature.linkage != .internal) entry.* = null;
    }
    result[m.entry] = null;
    return result;
}

fn shape(m: *const ir.Module, ret: ir.Type) ?Shape {
    var ty = ret;
    if (m.kind(ty) == .record) {
        const fields = m.compound(ty).record;
        if (fields.len == 0) return null;
        ty = fields[0];
    }
    if (m.kind(ty) != .@"union" or !m.passedInMemory(ty)) return null;
    var largest: ir.Type = .void;
    for (m.compound(ty).@"union") |case| {
        if (m.size(case) > m.size(largest)) largest = case;
    }
    if (!m.passedInMemory(largest)) return null;
    return .{ .offset = 8, .size = m.size(ty) - 8, .ty = largest };
}

/// Recognize a returned union payload immediately consumed by list push.
pub fn pushed(m: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?Push {
    if (inst.op != .list_push) return null;
    const payload = f.resolve(inst.b);
    const value = f.inst(payload);
    if (value.op != .union_payload or !m.passedInMemory(value.ty)) return null;
    var parent = f.resolve(value.a);
    if (f.inst(parent).op == .record_get and f.inst(parent).data == 0) parent = f.resolve(f.inst(parent).a);
    if (f.inst(parent).op != .call) return null;
    return .{ .call = parent, .payload = payload, .list = f.resolve(inst.a) };
}

/// The root call and byte offset of a chain of returned field/payload projections.
pub fn projection(m: *const ir.Module, f: *const ir.Function, raw: ir.Ref) ?struct { call: ir.Ref, offset: u32 } {
    var at = f.resolve(raw);
    var offset: u32 = 0;
    var budget: usize = 32;
    while (budget != 0) : (budget -= 1) {
        const inst = f.inst(at);
        switch (inst.op) {
            .call => return .{ .call = at, .offset = offset },
            .record_get => offset += m.fieldOffset(f.inst(f.resolve(inst.a)).ty, @intCast(inst.data)),
            .union_payload => offset += 8,
            else => return null,
        }
        at = f.resolve(inst.a);
    }
    return null;
}

/// A type may expose the candidate list to a callee; recursive or deep shapes refuse.
pub fn reaches(m: *const ir.Module, ty: ir.Type, list: ir.Type, budget: usize) bool {
    if (ty == list) return true;
    if (!ty.isCompound()) return false;
    if (budget == 0) return true;
    return switch (m.compound(ty)) {
        .record => |fields| blk: {
            for (fields) |field| if (reaches(m, field, list, budget - 1)) break :blk true;
            break :blk false;
        },
        .@"union" => |cases| blk: {
            for (cases) |case| if (reaches(m, case, list, budget - 1)) break :blk true;
            break :blk false;
        },
        .list => |elem| reaches(m, elem, list, budget - 1),
        .array => |array| reaches(m, array.elem, list, budget - 1),
        .box => |inner| reaches(m, inner, list, budget - 1),
        .dict => |dict| reaches(m, dict.key, list, budget - 1) or reaches(m, dict.value, list, budget - 1),
        .@"fn" => true,
    };
}

/// A separated caller result may only be inspected through field/tag/payload
/// projections. Whole-value retains, releases, stores, phis and arguments refuse.
pub fn projectedOnly(m: *const ir.Module, f: *const ir.Function, call: ir.Ref, offset: u32, returned: bool) bool {
    for (f.insts.items) |user| {
        if (user.op == .copy) continue;
        const operands = f.valueOperands(user);
        for (0..operands.len()) |i| {
            const operand = f.resolve(operands.get(i));
            const part = projection(m, f, operand) orelse continue;
            if (part.call != call or part.offset >= offset) continue;
            if (part.offset + m.size(f.inst(operand).ty) <= offset) continue;
            if (user.op == .ret and returned) continue;
            if (user.op != .record_get and user.op != .union_tag and user.op != .union_payload) return false;
        }
    }
    return true;
}
