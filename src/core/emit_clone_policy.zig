//! Private entry copies preserve real function identities and refuse direct recursion.
const std = @import("std");
const ir = @import("ir.zig");

const Edges = std.ArrayList(u32);
const Frame = struct { function: u32, next: usize = 0 };
const Graph = struct { calls: []Edges, callers: []Edges, addressed: []bool };

/// Return eligible bodies in the original bounded closure's first-use order.
/// A function value always designates its real owner; only direct calls may copy.
pub fn privateBodies(a: std.mem.Allocator, module: *const ir.Module, selected: []const u32) std.mem.Allocator.Error![]const u32 {
    if (selected.len == 0) return &.{};
    const graph = try callGraph(a, module);
    const order = try postorder(a, graph.calls);
    const components = try componentIds(a, graph.callers, order);
    const sizes = try a.alloc(u32, graph.calls.len);
    @memset(sizes, 0);
    for (components) |component| sizes[component] += 1;
    var result: Edges = .empty;
    for (selected) |index| {
        if (graph.addressed[index] or sizes[components[index]] != 1) continue;
        if (std.mem.indexOfScalar(u32, graph.calls[index].items, index) != null) continue;
        try result.append(a, index);
    }
    return result.toOwnedSlice(a);
}

fn callGraph(a: std.mem.Allocator, module: *const ir.Module) !Graph {
    const n = module.functions.items.len;
    const calls = try a.alloc(Edges, n);
    const callers = try a.alloc(Edges, n);
    const addressed = try a.alloc(bool, n);
    @memset(calls, .empty);
    @memset(callers, .empty);
    @memset(addressed, false);
    // Include unreachable references too: refusal is conservative and independent
    // of a particular unit's optimizer visibility or eventual native dead stripping.
    for (module.functions.items, 0..) |function, index| {
        for (function.insts.items) |inst| {
            if (inst.op == .func_ref) addressed[@intCast(inst.data)] = true;
            if (inst.op != .call) continue;
            const target: u32 = @intCast(inst.a.index());
            try calls[index].append(a, target);
            try callers[target].append(a, @intCast(index));
        }
    }
    return .{ .calls = calls, .callers = callers, .addressed = addressed };
}

fn postorder(a: std.mem.Allocator, calls: []const Edges) ![]const u32 {
    const visited = try a.alloc(bool, calls.len);
    @memset(visited, false);
    var pending: std.ArrayList(Frame) = .empty;
    var order: Edges = .empty;
    for (calls, 0..) |_, index| {
        if (visited[index]) continue;
        visited[index] = true;
        try pending.append(a, .{ .function = @intCast(index) });
        while (pending.items.len != 0) {
            const top = &pending.items[pending.items.len - 1];
            const edges = calls[top.function].items;
            if (top.next == edges.len) {
                try order.append(a, top.function);
                _ = pending.pop();
                continue;
            }
            const target = edges[top.next];
            top.next += 1;
            if (visited[target]) continue;
            visited[target] = true;
            try pending.append(a, .{ .function = target });
        }
    }
    return order.toOwnedSlice(a);
}

fn componentIds(a: std.mem.Allocator, callers: []const Edges, order: []const u32) ![]const u32 {
    const ids = try a.alloc(u32, callers.len);
    @memset(ids, std.math.maxInt(u32));
    var pending: Edges = .empty;
    var cursor = order.len;
    var component: u32 = 0;
    while (cursor != 0) {
        cursor -= 1;
        const root = order[cursor];
        if (ids[root] != std.math.maxInt(u32)) continue;
        ids[root] = component;
        try pending.append(a, root);
        while (pending.pop()) |index| {
            for (callers[index].items) |caller| {
                if (ids[caller] != std.math.maxInt(u32)) continue;
                ids[caller] = component;
                try pending.append(a, caller);
            }
        }
        component += 1;
    }
    return ids;
}
