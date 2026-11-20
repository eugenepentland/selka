// netlist_union_find: union by size with path halving over 2M pins and 3M random
// connections, CSR adjacency, then 16 BFS runs over one reused distance array and
// queue (SUITE.md section 13).
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

/// One xorshift step; returns the new state.
fn xorshift(input: u64) u64 {
    var x = input;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return x;
}

/// The shared checksum step: `(c * 31 + v) mod 1000000007`, for non-negative `v`.
fn mix(c: u64, v: u64) u64 {
    return (c * 31 + v) % 1000000007;
}

/// The root of `start`'s set, halving the path as it climbs.
fn find(parent: []usize, start: usize) usize {
    var x = start;
    while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
    }
    return x;
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const pins: usize = @intCast(common.opaqueN(1000000));
    const conns: usize = @intCast(common.opaqueN(1000000));
    var state: u64 = 88172645463325252;
    const conn_a = try gpa.alloc(usize, conns);
    defer gpa.free(conn_a);
    const conn_b = try gpa.alloc(usize, conns);
    defer gpa.free(conn_b);
    for (0..conns) |e| {
        state = xorshift(state);
        conn_a[e] = @intCast((state >> 33) % pins);
        state = xorshift(state);
        conn_b[e] = @intCast((state >> 33) % pins);
    }

    const parent = try gpa.alloc(usize, pins);
    defer gpa.free(parent);
    const size = try gpa.alloc(usize, pins);
    defer gpa.free(size);
    for (0..pins) |x| {
        parent[x] = x;
        size[x] = 1;
    }
    for (0..conns) |e| {
        var ra = find(parent, conn_a[e]);
        var rb = find(parent, conn_b[e]);
        if (ra == rb) continue;
        if (size[ra] < size[rb]) std.mem.swap(usize, &ra, &rb);
        parent[rb] = ra;
        size[ra] = size[ra] + size[rb];
    }
    var nets: u64 = 0;
    var largest: u64 = 0;
    var roots_mix: u64 = 0;
    for (0..pins) |x| {
        if (parent[x] != x) continue;
        nets += 1;
        largest = @max(largest, size[x]);
        roots_mix = mix(roots_mix, size[x]);
    }

    const degree = try gpa.alloc(usize, pins);
    defer gpa.free(degree);
    @memset(degree, 0);
    for (0..conns) |e| {
        degree[conn_a[e]] += 1;
        degree[conn_b[e]] += 1;
    }
    const offset = try gpa.alloc(usize, pins + 1);
    defer gpa.free(offset);
    offset[0] = 0;
    for (0..pins) |x| offset[x + 1] = offset[x] + degree[x];
    const cursor = try gpa.alloc(usize, pins);
    defer gpa.free(cursor);
    @memcpy(cursor, offset[0..pins]);
    const adj = try gpa.alloc(usize, 2 * conns);
    defer gpa.free(adj);
    for (0..conns) |e| {
        const a = conn_a[e];
        const b = conn_b[e];
        adj[cursor[a]] = b;
        cursor[a] += 1;
        adj[cursor[b]] = a;
        cursor[b] += 1;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "pins {d} connections {d} nets {d} largest {d} roots_mix {d}\n", .{ pins, conns, nets, largest, roots_mix });

    const dist = try gpa.alloc(i64, pins);
    defer gpa.free(dist);
    const queue = try gpa.alloc(usize, pins);
    defer gpa.free(queue);
    var distances_mix: u64 = 0;
    for (0..16) |_| {
        state = xorshift(state);
        const source: usize = @intCast((state >> 33) % pins);
        @memset(dist, -1);
        dist[source] = 0;
        queue[0] = source;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) {
            const u = queue[head];
            head += 1;
            const next = dist[u] + 1;
            for (adj[offset[u]..offset[u + 1]]) |v| {
                if (dist[v] < 0) {
                    dist[v] = next;
                    queue[tail] = v;
                    tail += 1;
                }
            }
        }
        var depth: i64 = 0;
        for (dist) |d| depth = @max(depth, d);
        try out.print(gpa, "source {d} reached {d} depth {d}\n", .{ source, tail, depth });
        for (dist) |d| distances_mix = mix(distances_mix, @intCast(d + 1));
    }
    try out.print(gpa, "distances_mix {d}\n", .{distances_mix});
    common_c.writeStdout(out.items);
}
