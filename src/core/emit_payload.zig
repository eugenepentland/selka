//! Split return payloads: a private destination pointer lets a fallible producer
//! fill an unused list slot without reserving, allocating, or committing early.
const std = @import("std");
const ir = @import("ir.zig");

/// The contiguous payload region of a returned union, optionally in field zero.
pub const Shape = struct { offset: u32, size: u32, ty: ir.Type };
/// Identical detached types preserve size and alignment as well as byte location.
pub fn compatible(parent: Shape, child: Shape, child_offset: u32) bool {
    return child_offset + child.offset == parent.offset and child.size == parent.size and child.ty == parent.ty;
}
/// A pushed payload and the direct call that produces its enclosing result.
pub const Push = struct { call: ir.Ref, payload: ir.Ref, list: ir.Ref };
/// One emitted alternative destination, also used by payload reads and the push.
pub const Destination = struct { pointer: []const u8, offset: u32, size: u32 };
/// A split value read: its ordinary base, redirected region and current offset.
pub const Read = struct { base: []const u8, destination: Destination, offset: u32 = 0 };
/// Per-function optional ABI shapes, excluding escaping and cross-unit targets.
pub fn shapes(arena: std.mem.Allocator, m: *const ir.Module) std.mem.Allocator.Error![]?Shape {
    const result = try arena.alloc(?Shape, m.functions.items.len);
    @memset(result, null);
    for (m.functions.items) |*f| for (f.insts.items) |inst| {
        const push = pushed(m, f, inst) orelse continue;
        const target = f.inst(push.call).a.index();
        result[target] = shape(m, m.functions.items[target].signature.ret, f.inst(push.payload).ty);
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
                const inner = shape(m, m.functions.items[target].signature.ret, wanted.ty) orelse continue;
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
    if (m.entry < result.len) result[m.entry] = null;
    return result;
}

fn shape(m: *const ir.Module, ret: ir.Type, payload: ir.Type) ?Shape {
    var ty = ret;
    if (m.kind(ty) == .record) {
        const fields = m.compound(ty).record;
        if (fields.len == 0) return null;
        ty = fields[0];
    }
    if (m.kind(ty) != .@"union" or !m.passedInMemory(ty)) return null;
    for (m.compound(ty).@"union") |case| {
        if (case == payload) return .{ .offset = 8, .size = m.size(payload), .ty = payload };
    }
    return null;
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
/// projections or ownership operations that understand split locations. Whole-value
/// stores, phis and arguments refuse.
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
            if (user.op == .retain or user.op == .release) continue;
            if (user.op != .record_get and user.op != .union_tag and user.op != .union_payload) return false;
        }
    }
    return true;
}

/// Lending ends before any later list mutation that can precede a result read.
/// Reaching the producer again starts a new SSA value and stops the old lifetime.
pub fn safeLifetime(arena: std.mem.Allocator, m: *const ir.Module, f: *const ir.Function, push: Push, list: ir.Type) std.mem.Allocator.Error!bool {
    var graph = try Paths.init(arena, f);
    const reads = try arena.alloc(bool, f.insts.items.len);
    for (f.insts.items, reads) |inst, *read| read.* = readsResult(m, f, inst, push.call);
    const after = try arena.alloc(bool, f.insts.items.len);
    graph.visit(push.call, push.call);
    @memcpy(after, graph.seen);
    for (f.insts.items, 0..) |inst, index| {
        if (!after[index] or !mayMutate(m, f, inst, push, list)) continue;
        graph.visit(@fromBackingInt(@as(u32, @intCast(index))), push.call);
        for (graph.seen, reads) |reachable, read| if (reachable and read) return false;
    }
    return true;
}

fn readsResult(m: *const ir.Module, f: *const ir.Function, inst: ir.Inst, call: ir.Ref) bool {
    if (inst.op == .copy) return false;
    const operands = f.valueOperands(inst);
    for (0..operands.len()) |i| {
        const part = projection(m, f, operands.get(i)) orelse continue;
        if (part.call == call) return true;
    }
    return false;
}

fn mayMutate(m: *const ir.Module, f: *const ir.Function, inst: ir.Inst, push: Push, list: ir.Type) bool {
    if (inst.op == .list_push and f.resolve(inst.b) == push.payload) return false;
    switch (inst.op) {
        .list_push, .list_set, .list_set_field, .list_pop, .list_sort, .record_set, .array_set, .dict_insert, .dict_remove, .dict_set_value, .dict_clear, .release => return reaches(m, f.inst(f.resolve(inst.a)).ty, list, 12),
        .call, .call_indirect => {
            for (f.operands(inst.data)) |arg| if (reaches(m, f.inst(f.resolve(arg)).ty, list, 12)) return true;
            return inst.op == .call_indirect;
        },
        else => return false,
    }
}

const Paths = struct {
    next: [][2]ir.Ref,
    seen: []bool,
    queue: []ir.Ref,

    fn init(arena: std.mem.Allocator, f: *const ir.Function) std.mem.Allocator.Error!Paths {
        const n = f.insts.items.len;
        const next = try arena.alloc([2]ir.Ref, n);
        errdefer arena.free(next);
        const seen = try arena.alloc(bool, n);
        errdefer arena.free(seen);
        @memset(next, .{ .none, .none });
        for (f.blocks.items) |block| {
            const refs = block.insts.items;
            for (refs, 0..) |ref, index| {
                const inst = f.inst(ref);
                if (index + 1 < refs.len) next[ref.index()][0] = refs[index + 1];
                if (inst.op == .jump or inst.op == .branch) next[ref.index()][0] = f.blocks.items[@as(u32, @truncate(inst.data))].insts.items[0];
                if (inst.op == .branch) next[ref.index()][1] = f.blocks.items[@as(u32, @truncate(inst.data >> 32))].insts.items[0];
            }
        }
        return .{ .next = next, .seen = seen, .queue = try arena.alloc(ir.Ref, n) };
    }

    fn visit(self: *Paths, start: ir.Ref, stop: ir.Ref) void {
        @memset(self.seen, false);
        var read: usize = 0;
        var used: usize = 0;
        self.append(start, stop, &used);
        while (read < used) : (read += 1) self.append(self.queue[read], stop, &used);
    }

    fn append(self: *Paths, ref: ir.Ref, stop: ir.Ref, used: *usize) void {
        for (self.next[ref.index()]) |next| {
            if (next == .none or next == stop) continue;
            if (self.seen[next.index()]) continue;
            self.seen[next.index()] = true;
            self.queue[used.*] = next;
            used.* += 1;
        }
    }
};
