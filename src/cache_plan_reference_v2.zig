//! Independent incremental admission oracle: iterative Tarjan and per-test BFS.
const std = @import("std");
const wire = @import("cache_plan_protocol_v2.zig");
const v1 = @import("cache_plan_protocol.zig");
const Frame = struct { node: u32, edge: usize = 0 };
const Tarjan = struct { visited: []u32, low: []u32, active: []bool, stack: std.ArrayList(u32) = .empty, groups: []u32, next: u32 = 0, work: *wire.Work };

fn budget(work: wire.Work) wire.Error!void {
    if (work.index_nodes + work.index_edges + work.affected_nodes + work.closure_nodes + work.closure_edges > wire.max_work) return error.ComponentProtocol;
}

/// Derive current SCCs independently of the component's Kosaraju implementation.
pub fn groups(a: std.mem.Allocator, graph: v1.Graph, work: *wire.Work) wire.Error![]const u32 {
    const count = graph.digests.len;
    var state: Tarjan = .{ .visited = try a.alloc(u32, count), .low = try a.alloc(u32, count), .active = try a.alloc(bool, count), .groups = try a.alloc(u32, count), .work = work };
    @memset(state.visited, std.math.maxInt(u32));
    @memset(state.active, false);
    var frames: std.ArrayList(Frame) = .empty;
    for (0..count) |start| {
        if (state.visited[start] != std.math.maxInt(u32)) continue;
        try enter(a, &state, &frames, @intCast(start));
        while (frames.items.len > 0) {
            const position = frames.items.len - 1;
            const node = frames.items[position].node;
            const edge = frames.items[position].edge;
            if (edge < graph.callees[node].len) {
                frames.items[position].edge += 1;
                const target = graph.callees[node][edge];
                state.work.index_edges += 1;
                try budget(work.*);
                if (state.visited[target] == std.math.maxInt(u32)) {
                    try enter(a, &state, &frames, target);
                } else if (state.active[target]) state.low[node] = @min(state.low[node], state.visited[target]);
                continue;
            }
            _ = frames.pop();
            if (state.low[node] == state.visited[node]) {
                const end = state.stack.items.len;
                var begin = end;
                var representative = node;
                while (begin > 0) {
                    begin -= 1;
                    const member = state.stack.items[begin];
                    representative = @min(representative, member);
                    state.active[member] = false;
                    if (member == node) break;
                }
                for (state.stack.items[begin..end]) |member| state.groups[member] = representative;
                state.stack.shrinkRetainingCapacity(begin);
            }
            if (frames.items.len > 0) {
                const parent = frames.items[frames.items.len - 1].node;
                state.low[parent] = @min(state.low[parent], state.low[node]);
            }
        }
    }
    return state.groups;
}

fn enter(a: std.mem.Allocator, state: *Tarjan, frames: *std.ArrayList(Frame), node: u32) wire.Error!void {
    state.visited[node] = state.next;
    state.low[node] = state.next;
    state.next += 1;
    state.active[node] = true;
    try state.stack.append(a, node);
    try frames.append(a, .{ .node = node });
    state.work.index_nodes += 1;
    try budget(state.work.*);
}

/// Admit retained keys only after backward propagation through the current graph.
pub fn plan(a: std.mem.Allocator, input: wire.Incremental) wire.Error!wire.IncrementalResults {
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    try wire.validate(scratch, input);
    var work: wire.Work = .{};
    const reverse = try wire.transpose(scratch, input.graph);
    const membership = try groups(scratch, input.graph, &work);
    const dirty = try scratch.alloc(bool, membership.len);
    @memset(dirty, false);
    var pending: std.ArrayList(u32) = .empty;
    for (input.changed) |node| {
        dirty[node] = true;
        try pending.append(scratch, node);
    }
    var next: usize = 0;
    while (next < pending.items.len) : (next += 1) {
        const node = pending.items[next];
        work.affected_nodes += 1;
        for (reverse[node]) |source| {
            work.index_edges += 1;
            try budget(work);
            if (dirty[source]) continue;
            dirty[source] = true;
            try pending.append(scratch, source);
        }
    }
    const batches = try scratch.alloc([]const u32, input.roots.len);
    const reused = try scratch.alloc(bool, batches.len);
    const seen = try scratch.alloc(u32, membership.len);
    @memset(seen, 0);
    for (batches, reused, input.roots, input.candidates, 1..) |*batch, *reuse, roots, candidate, epoch_value| {
        reuse.* = candidate;
        for (roots) |root| if (dirty[root]) {
            reuse.* = false;
        };
        batch.* = &.{};
        if (reuse.*) {
            work.reused_tests += 1;
            continue;
        }
        work.planned_tests += 1;
        const epoch: u32 = @intCast(epoch_value);
        pending.clearRetainingCapacity();
        for (roots) |root| {
            if (seen[root] == epoch) continue;
            seen[root] = epoch;
            try pending.append(scratch, root);
        }
        var reached: std.ArrayList(u32) = .empty;
        next = 0;
        while (next < pending.items.len) : (next += 1) {
            work.closure_nodes += 1;
            try budget(work);
            for (input.graph.callees[pending.items[next]]) |target| {
                work.closure_edges += 1;
                try budget(work);
                if (seen[target] == epoch) continue;
                seen[target] = epoch;
                try pending.append(scratch, target);
                try reached.append(scratch, target);
            }
        }
        std.mem.sort(u32, reached.items, input.graph.digests, before);
        batch.* = reached.items;
    }
    var output_size: usize = 128 + membership.len * 8 + batches.len * 8;
    for (reverse) |row| output_size += row.len * 4;
    for (batches) |row| output_size += row.len * 4;
    if (output_size > wire.reply_limit) return error.ComponentProtocol;
    return .{ .arena = arena, .batches = batches, .reused = reused, .indexes = .{ .topology = input.topology, .reverse = reverse, .groups = membership }, .work = work };
}

fn before(digests: []const wire.Digest, left: u32, right: u32) bool {
    return switch (std.mem.order(u8, &digests[left], &digests[right])) {
        .lt => true,
        .gt => false,
        .eq => left < right,
    };
}
