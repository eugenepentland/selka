//! Monotone arena dependencies survive abstract branches, loops and overwritten bindings.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;
const Node = struct { depth: usize, edge: ?usize = null, queued: bool = false };
const Edge = struct { target: usize, next: ?usize };
/// Destination lifetime is either a lexical scope or an owned container's allocator.
pub const Limit = union(enum) { depth: usize, node: usize };
const Constraint = struct { value: usize, limit: Limit, span: Span };
/// Function-local graph; scoped names may disappear while their dependencies remain.
pub const Graph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    constraints: std.ArrayList(Constraint) = .empty,
    /// Release all graph storage after checking one abstract function.
    pub fn deinit(self: *Graph) void {
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.constraints.deinit(self.allocator);
    }
    /// Create a stable dependency identity, optionally seeded by an arena scope.
    pub fn add(self: *Graph, depth: usize) std.mem.Allocator.Error!usize {
        const id = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{ .depth = depth });
        return id;
    }
    /// Propagate the source lifetime dependency into a destination value.
    pub fn flow(self: *Graph, source: usize, target: usize) std.mem.Allocator.Error!void {
        if (source == target) return;
        try self.edges.append(self.allocator, .{ .target = target, .next = self.nodes.items[source].edge });
        self.nodes.items[source].edge = self.edges.items.len - 1;
    }
    /// Defer an escape check until assignments and helper effects reach a fixed point.
    pub fn require(self: *Graph, value: usize, limit: Limit, span: Span) std.mem.Allocator.Error!void {
        try self.constraints.append(self.allocator, .{ .value = value, .limit = limit, .span = span });
    }
    /// Propagate each changed origin through a bounded worklist and check every escape.
    pub fn check(self: *Graph, sink: *diagnostic.Sink) diagnostic.Error!void {
        var pending = try std.ArrayList(usize).initCapacity(self.allocator, self.nodes.items.len);
        defer pending.deinit(self.allocator);
        for (self.nodes.items, 0..) |*node, id| if (node.depth != 0) {
            node.queued = true;
            pending.appendAssumeCapacity(id);
        };
        while (pending.pop()) |id| {
            self.nodes.items[id].queued = false;
            var edge = self.nodes.items[id].edge;
            while (edge) |index| {
                const link = self.edges.items[index];
                const target = &self.nodes.items[link.target];
                if (target.depth < self.nodes.items[id].depth) {
                    target.depth = self.nodes.items[id].depth;
                    if (!target.queued) {
                        target.queued = true;
                        pending.appendAssumeCapacity(link.target);
                    }
                }
                edge = link.next;
            }
        }
        for (self.constraints.items) |constraint| {
            const limit = switch (constraint.limit) {
                .depth => |depth| depth,
                .node => |id| self.nodes.items[id].depth,
            };
            try @import("region_check.zig").requireLimit(self.nodes.items[constraint.value].depth, limit, constraint.span, sink);
        }
    }
};
