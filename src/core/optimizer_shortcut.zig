//! A compact previous-build index bypasses identity prepasses without changing
//! the intermediate bodies that a dirty caller sees. Mutating prepasses retain
//! the ordered stage-cache path; changed callees invalidate their callers.
const std = @import("std");
const facts = @import("facts.zig");
const cache = @import("optimization_cache.zig");

/// Inputs and final artifact of a function whose earlier checkpoints were identity.
pub const Entry = struct {
    raw: ?[32]u8 = null,
    stable: bool = false,
    summary: ?cache.Summary = null,
    parameters: []const ?facts.Interval = &.{},
    final: ?[32]u8 = null,
};

/// One build's candidate mask and compact records, separate from restored IR.
pub const Index = struct {
    context: *cache.Context,
    key: [32]u8,
    entries: []Entry,
    green: []bool,
    parents: []const std.ArrayList(u32),

    /// Prepare build-arena-owned records and reverse calls. Failed preparation
    /// leaves partial allocations on that arena, reclaimed with the owning build.
    pub fn prepare(a: std.mem.Allocator, context: *cache.Context, mode: u8) std.mem.Allocator.Error!?Index {
        const layout = context.layoutDigest() orelse return null;
        const key = context.store.key("optimizer-shortcut-v1", &.{ &layout, &.{mode} });
        const previous = try context.store.loadValue(a, key, []Entry);
        const module = context.source.module;
        const count = module.functions.items.len;
        const entries = try a.alloc(Entry, count);
        const green = try a.alloc(bool, count);
        @memset(green, false);
        const parents = try a.alloc(std.ArrayList(u32), count);
        @memset(parents, .empty);
        var queue: std.ArrayList(u32) = .empty;
        for (module.functions.items, entries, green, 0..) |function, *entry, *reusable, index| {
            const raw = try context.bodyDigest(@intCast(index));
            entry.* = .{ .raw = raw };
            if (previous) |prior| if (prior.len == count) {
                const old = prior[index];
                if (old.raw != null and raw != null and std.mem.eql(u8, &old.raw.?, &raw.?)) {
                    entry.* = old;
                    reusable.* = old.stable and old.final != null and old.summary != null and old.summary.?.valid(module);
                }
            };
            // External declarations have no mutable body or exploratory summary.
            if (function.signature.linkage != .internal) reusable.* = true;
            if (!reusable.*) try queue.append(a, @intCast(index));
            for (function.insts.items) |inst| {
                const target: usize = switch (inst.op) {
                    .call => inst.a.index(),
                    .func_ref => @intCast(inst.data),
                    else => continue,
                };
                if (target >= count) continue;
                try parents[target].append(a, @intCast(index));
            }
        }
        try invalidateCycles(a, parents, green, &queue);
        try invalidateCallers(a, parents, green, &queue);
        return .{ .context = context, .key = key, .entries = entries, .green = green, .parents = parents };
    }

    /// Incoming caller intervals must still match before the parameter-dependent round.
    pub fn parameters(self: *Index, a: std.mem.Allocator, values: []const []const ?facts.Interval) std.mem.Allocator.Error!void {
        var queue: std.ArrayList(u32) = .empty;
        for (self.green, self.entries, values, 0..) |*green, entry, current, index| {
            if (!green.* or equalRanges(entry.parameters, current)) continue;
            green.* = false;
            try queue.append(a, @intCast(index));
        }
        // New bounds may make a previously identity callee inline during the
        // parameter round. Its callers must visit that checkpoint in normal order.
        try invalidateCallers(a, self.parents, self.green, &queue);
    }

    /// Keep exploratory contributions after the per-function scratch is reclaimed.
    pub fn summary(self: *Index, a: std.mem.Allocator, function: usize, value: cache.Summary) std.mem.Allocator.Error!void {
        const calls = try a.dupe(cache.Call, value.calls);
        for (calls) |*call| call.ranges = try a.dupe(?facts.Interval, call.ranges);
        self.entries[function].summary = .{ .returned = value.returned, .calls = calls };
    }

    /// Record the final key only if every earlier mutation checkpoint was identity.
    pub fn final(self: *Index, a: std.mem.Allocator, function: usize, values: []const ?facts.Interval, key: ?[32]u8, events: [2]u32) std.mem.Allocator.Error!void {
        const entry = &self.entries[function];
        const current = try self.context.bodyDigest(@intCast(function));
        entry.stable = events[0] == 0 and events[1] == 0 and entry.raw != null and current != null and std.mem.eql(u8, &entry.raw.?, &current.?);
        entry.parameters = try a.dupe(?facts.Interval, values);
        entry.final = key;
    }

    /// Atomically replace the advisory index; absent final artifacts still miss normally.
    pub fn save(self: *const Index) std.mem.Allocator.Error!void {
        try self.context.store.storeValue(self.key, []Entry, self.entries);
    }
};

fn equalRanges(left: []const ?facts.Interval, right: []const ?facts.Interval) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn invalidateCallers(a: std.mem.Allocator, parents: []const std.ArrayList(u32), green: []bool, queue: *std.ArrayList(u32)) std.mem.Allocator.Error!void {
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        for (parents[queue.items[cursor]].items) |caller| {
            if (!green[caller]) continue;
            green[caller] = false;
            try queue.append(a, caller);
        }
    }
}

fn invalidateCycles(a: std.mem.Allocator, parents: []const std.ArrayList(u32), green: []bool, queue: *std.ArrayList(u32)) std.mem.Allocator.Error!void {
    const colors = try a.alloc(enum { new, open, done }, parents.len);
    @memset(colors, .new);
    var stack: std.ArrayList(struct { function: u32, next: usize = 0 }) = .empty;
    for (0..parents.len) |root| {
        if (colors[root] != .new) continue;
        colors[root] = .open;
        try stack.append(a, .{ .function = @intCast(root) });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const edges = parents[top.function].items;
            if (top.next == edges.len) {
                colors[top.function] = .done;
                _ = stack.pop();
                continue;
            }
            const target = edges[top.next];
            top.next += 1;
            if (colors[target] == .done) continue;
            if (colors[target] == .new) {
                colors[target] = .open;
                try stack.append(a, .{ .function = target });
                continue;
            }
            // Exploratory recursion breaks cycles at DFS entry. A changed upstream
            // caller can move that entry even while the recursive raw bodies match.
            var inside = false;
            for (stack.items) |frame| {
                if (frame.function == target) inside = true;
                if (!inside or !green[frame.function]) continue;
                green[frame.function] = false;
                try queue.append(a, frame.function);
            }
        }
    }
}
