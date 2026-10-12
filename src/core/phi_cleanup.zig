//! Exact redundant-phi cleanup before ownership assigns distinct value homes.
//!
//! A strongly connected component of phis with one external incoming value is
//! that value. All incoming edges count, including currently unreachable edges.
//! No field, length, constant or equal-content equivalence establishes identity.
const std = @import("std");
const ir = @import("ir.zig");

/// Structural work counters; each phi edge is visited twice, independently of depth.
pub const Stats = struct { phis: usize = 0, edges: usize = 0, copies: usize = 0, rewritten: usize = 0 };
const unseen = std.math.maxInt(u32);
const Frame = struct { node: ir.Ref, edge: usize = 0 };

/// Rewrite only exact phi aliases, retaining instruction identities and source spans.
/// Analysis storage is reclaimed before returning; malformed copy cycles are left alone.
pub fn run(backing: std.mem.Allocator, function: *ir.Function) std.mem.Allocator.Error!Stats {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var stats: Stats = .{};
    const copies = try resolveCopies(a, function, &stats) orelse return .{};
    const count = function.insts.items.len;
    var state: State = .{
        .a = a,
        .f = function,
        .copies = copies,
        .stats = stats,
        .representative = try a.dupe(ir.Ref, copies),
        .order = try a.alloc(u32, count),
        .low = try a.alloc(u32, count),
        .on_stack = try a.alloc(bool, count),
        .component_id = try a.alloc(u32, count),
    };
    @memset(state.order, unseen);
    @memset(state.on_stack, false);
    @memset(state.component_id, unseen);
    for (function.insts.items, 0..) |instruction, index| {
        if (instruction.op != .phi or state.order[index] != unseen) continue;
        try state.visit(@fromBackingInt(@as(u32, @intCast(index))));
    }
    return state.stats;
}

/// Resolve each forwarding copy once, without calling an unbounded chain walk per edge.
fn resolveCopies(a: std.mem.Allocator, f: *const ir.Function, stats: *Stats) std.mem.Allocator.Error!?[]ir.Ref {
    const result = try a.alloc(ir.Ref, f.insts.items.len);
    const colors = try a.alloc(u2, result.len);
    @memset(colors, 0);
    var path: std.ArrayList(ir.Ref) = .empty;
    for (f.insts.items, 0..) |_, index| {
        if (colors[index] == 2) continue;
        path.clearRetainingCapacity();
        var current: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        while (current != .none and colors[current.index()] != 2) {
            if (colors[current.index()] == 1) return null;
            colors[current.index()] = 1;
            try path.append(a, current);
            const inst = f.inst(current);
            if (inst.op != .copy) break;
            stats.copies += 1;
            current = inst.a;
        }
        const target = if (current != .none and colors[current.index()] == 2) result[current.index()] else current;
        for (path.items) |ref| {
            result[ref.index()] = target;
            colors[ref.index()] = 2;
        }
    }
    return result;
}

const State = struct {
    a: std.mem.Allocator,
    f: *ir.Function,
    copies: []const ir.Ref,
    representative: []ir.Ref,
    order: []u32,
    low: []u32,
    on_stack: []bool,
    component_id: []u32,
    next_order: u32 = 0,
    next_component: u32 = 0,
    stack: std.ArrayList(ir.Ref) = .empty,
    work: std.ArrayList(Frame) = .empty,
    component: std.ArrayList(ir.Ref) = .empty,
    stats: Stats,

    fn enter(self: *State, ref: ir.Ref) std.mem.Allocator.Error!void {
        self.order[ref.index()] = self.next_order;
        self.low[ref.index()] = self.next_order;
        self.next_order += 1;
        self.stats.phis += 1;
        self.on_stack[ref.index()] = true;
        try self.stack.append(self.a, ref);
        try self.work.append(self.a, .{ .node = ref });
    }

    /// Iterative Tarjan traversal; operand components settle before their users.
    fn visit(self: *State, root: ir.Ref) std.mem.Allocator.Error!void {
        try self.enter(root);
        while (self.work.items.len != 0) {
            const top = &self.work.items[self.work.items.len - 1];
            const node = top.node;
            const operands = self.f.operands(self.f.inst(node).data);
            if (top.edge < operands.len) {
                const raw = operands[top.edge];
                top.edge += 1;
                self.stats.edges += 1;
                const target = if (raw == .none) ir.Ref.none else self.copies[raw.index()];
                if (target == .none or self.f.inst(target).op != .phi) continue;
                if (self.order[target.index()] == unseen) {
                    try self.enter(target);
                } else if (self.on_stack[target.index()]) {
                    self.low[node.index()] = @min(self.low[node.index()], self.order[target.index()]);
                }
                continue;
            }
            _ = self.work.pop();
            if (self.work.items.len != 0) {
                const parent = self.work.items[self.work.items.len - 1].node;
                self.low[parent.index()] = @min(self.low[parent.index()], self.low[node.index()]);
            }
            if (self.low[node.index()] != self.order[node.index()]) continue;
            self.component.clearRetainingCapacity();
            while (self.stack.pop()) |member| {
                self.on_stack[member.index()] = false;
                self.component_id[member.index()] = self.next_component;
                try self.component.append(self.a, member);
                if (member == node) break;
            }
            self.settle();
            self.next_component += 1;
        }
    }

    fn settle(self: *State) void {
        var only: ir.Ref = .none;
        var ambiguous = false;
        for (self.component.items) |member| {
            for (self.f.operands(self.f.inst(member).data)) |raw| {
                self.stats.edges += 1;
                const target = if (raw == .none) ir.Ref.none else self.copies[raw.index()];
                if (target == .none) {
                    ambiguous = true;
                    continue;
                }
                if (self.component_id[target.index()] == self.next_component) continue;
                const value = self.representative[target.index()];
                if (value == .none or self.f.inst(value).ty != self.f.inst(member).ty) {
                    ambiguous = true;
                } else if (only == .none) {
                    only = value;
                } else if (only != value) ambiguous = true;
            }
        }
        if (ambiguous or only == .none) return;
        for (self.component.items) |member| {
            self.representative[member.index()] = only;
            const inst = &self.f.insts.items[member.index()];
            inst.op = .copy;
            inst.a = only;
            inst.b = .none;
            inst.data = 0;
            self.stats.rewritten += 1;
        }
    }
};
