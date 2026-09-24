//! Bounded symbolic layout expansion preserves arguments without representative runtime types.
const std = @import("std");
const ast = @import("ast.zig");
const templates = @import("nominal_templates.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const eGenericLimit = diagnostic.generic_limit;
const Span = source.Span;
/// Identity in the symbolic layout graph, independent of executable typed.Type IDs.
pub const Id = enum(usize) { _ };
/// Semantic identity category; parameters remain scoped to their declaring template.
pub const Base = union(enum) {
    callback: struct {
        effects: @import("effect_set.zig").Mask,
        mutates: []const u16 = &.{},
        return_origin: typed.ReturnOrigin = .unknown,
    },
    builtin: typed.Type,
    length: usize,
    parameter: struct { declaration: usize, index: usize },
    named: usize,
    array: struct { length: usize, key: ?Id, length_parameter: ?Id = null },
    /// An anonymous tuple identity; its element identities are the arguments.
    tuple: void,
};
/// Ordered semantic identity accepted by layout materialization.
pub const Key = struct { base: Base, arguments: []const Id };
const KeyContext = struct {
    fn hashBase(hasher: *std.hash.Wyhash, base: Base) void {
        switch (base) {
            .callback => |callback| {
                std.hash.autoHash(hasher, @as(u8, 0));
                std.hash.autoHash(hasher, callback.effects);
                std.hash.autoHash(hasher, callback.mutates.len);
                for (callback.mutates) |position| std.hash.autoHash(hasher, position);
                switch (callback.return_origin) {
                    .fresh => std.hash.autoHash(hasher, @as(u8, 0)),
                    .params => |positions| {
                        std.hash.autoHash(hasher, @as(u8, 1));
                        std.hash.autoHash(hasher, positions.len);
                        for (positions) |position| std.hash.autoHash(hasher, position);
                    },
                    .unknown => std.hash.autoHash(hasher, @as(u8, 2)),
                }
            },
            .builtin => |ty| {
                std.hash.autoHash(hasher, @as(u8, 1));
                std.hash.autoHash(hasher, ty);
            },
            .length => |length| {
                std.hash.autoHash(hasher, @as(u8, 2));
                std.hash.autoHash(hasher, length);
            },
            .parameter => |parameter| {
                std.hash.autoHash(hasher, @as(u8, 3));
                std.hash.autoHash(hasher, parameter);
            },
            .named => |declaration| {
                std.hash.autoHash(hasher, @as(u8, 4));
                std.hash.autoHash(hasher, declaration);
            },
            .array => |array| {
                std.hash.autoHash(hasher, @as(u8, 5));
                std.hash.autoHash(hasher, array);
            },
            .tuple => std.hash.autoHash(hasher, @as(u8, 6)),
        }
    }
    fn equalBase(a: Base, b: Base) bool {
        return switch (a) {
            .callback => |left| switch (b) {
                .callback => |right| left.effects == right.effects and
                    std.mem.eql(u16, left.mutates, right.mutates) and
                    typed.ReturnOrigin.eql(left.return_origin, right.return_origin),
                else => false,
            },
            .builtin => |left| b == .builtin and b.builtin == left,
            .length => |left| b == .length and b.length == left,
            .parameter => |left| b == .parameter and left.declaration == b.parameter.declaration and left.index == b.parameter.index,
            .named => |left| b == .named and b.named == left,
            .array => |left| b == .array and left.length == b.array.length and left.key == b.array.key and left.length_parameter == b.array.length_parameter,
            .tuple => b == .tuple,
        };
    }
    /// Hash declaration, parameter and ordered argument identities without pointer identity.
    pub fn hash(_: KeyContext, key: Key) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hashBase(&hasher, key.base);
        std.hash.autoHash(&hasher, key.arguments.len);
        for (key.arguments) |argument| std.hash.autoHash(&hasher, argument);
        return hasher.final();
    }
    /// Compare canonical identities, including nominal bases and scoped symbolic parameters.
    pub fn eql(_: KeyContext, a: Key, b: Key) bool {
        return equalBase(a.base, b.base) and std.mem.eql(Id, a.arguments, b.arguments);
    }
};
const Map = std.HashMapUnmanaged(Key, Id, KeyContext, std.hash_map.default_max_load_percentage);
const State = enum { unneeded, queued, ready, visiting, complete };
/// Only storage dependencies form edges; phantom type arguments remain identities.
pub const Edge = struct { target: Id, span: Span };
/// Graph-owned layout identity with a separately discovered storage dependency list.
pub const Node = struct { key: Key, site: Span, edges: []const Edge = &.{}, state: State = .unneeded };
/// NOMINAL-LAYOUT-BUDGET-1: one demand on the graph — a declaration's symbolic
/// root, or one concrete type the checker materializes — and what expanding it
/// has cost so far. Every limit is charged to the demand whose expansion first
/// discovered the node, so a program of any size gets the same bound per
/// declaration and the total work stays proportional to the source.
const Request = struct { site: Span, work: usize = 0, instances: usize = 0, arrays: usize = 0 };
/// A queued node and the request that discovered it, which pays for its expansion.
const Pending = struct { id: Id, request: usize };
const Budget = struct { depth: usize = 0, expanded: usize = 0, requests: std.ArrayList(Request) = .empty, current: usize = 0 };
/// The per-request ceilings (NOMINAL-LAYOUT-1).
const max_work = 100000;
const max_instances = 4096;
const max_arrays = 4096;
/// Layout evidence for all declarations, including templates with distinct symbolic parameters.
pub const Graph = struct {
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    templates: *const templates.Index,
    nodes: std.ArrayList(Node) = .empty,
    index: Map = .empty,
    pending: std.ArrayList(Pending) = .empty,
    budget: Budget = .{},

    /// Release graph-owned keys, edges and discovery storage; the template index and sink are borrowed.
    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |node| {
            self.allocator.free(node.key.arguments);
            self.allocator.free(node.edges);
        }
        self.nodes.deinit(self.allocator);
        self.index.deinit(self.allocator);
        self.pending.deinit(self.allocator);
        self.budget.requests.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator, .sink = self.sink, .templates = self.templates };
    }
    /// Open a new request at `site` and make it the one charged. A request made
    /// after collection starts with nothing pending, so the finished ones are
    /// dropped and the list stays one entry long.
    fn begin(self: *Graph, site: Span) Error!void {
        if (self.budget.expanded == self.pending.items.len) self.budget.requests.clearRetainingCapacity();
        try self.budget.requests.append(self.allocator, .{ .site = site });
        self.budget.current = self.budget.requests.items.len - 1;
    }
    /// Report a limit at the request that exceeded it, naming where its expansion stood.
    fn limit(self: *Graph, span: Span, comptime what: []const u8) Error {
        const site = self.budget.requests.items[self.budget.current].site;
        const message = "nominal layout expansion of this type exceeds " ++ what;
        if (site.start == span.start and site.end == span.end) return self.sink.fail(eGenericLimit, site, message);
        return self.sink.failRelated(eGenericLimit, site, message, .{ .span = span, .message = "the expansion reached this type" });
    }
    fn charge(self: *Graph, span: Span) Error!void {
        const request = &self.budget.requests.items[self.budget.current];
        if (request.work == max_work) return self.limit(span, "100000 checking operations");
        request.work += 1;
    }
    fn intern(self: *Graph, key: Key, span: Span) Error!Id {
        try self.charge(span);
        if (self.index.get(key)) |id| return id;
        const instance = key.base == .named and key.arguments.len != 0;
        const request = &self.budget.requests.items[self.budget.current];
        if (instance and request.instances == max_instances) return self.limit(span, "4096 type instances");
        if (key.base == .array and request.arrays == max_arrays) return self.limit(span, "4096 array shapes");
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.index.ensureUnusedCapacity(self.allocator, 1);
        const owned: Key = .{ .base = key.base, .arguments = try self.allocator.dupe(Id, key.arguments) };
        const id: Id = @fromBackingInt(self.nodes.items.len);
        self.nodes.appendAssumeCapacity(.{ .key = owned, .site = span });
        self.index.putAssumeCapacityNoClobber(owned, id);
        if (instance) request.instances += 1;
        if (key.base == .array) request.arrays += 1;
        return id;
    }
    fn need(self: *Graph, id: Id) Error!void {
        if (self.nodes.items[@backingInt(id)].state != .unneeded) return;
        try self.pending.append(self.allocator, .{ .id = id, .request = self.budget.current });
        self.nodes.items[@backingInt(id)].state = .queued;
    }
    fn resolve(self: *Graph, value: templates.Expression, arguments: []const Id, span: Span) Error!Id {
        try self.charge(span);
        if (self.budget.depth == 256) return self.sink.fail(eGenericLimit, span, "nominal layout expressions exceed 256 levels");
        self.budget.depth += 1;
        defer self.budget.depth -= 1;
        return switch (value) {
            .length => |length| self.intern(.{ .base = .{ .length = length }, .arguments = &.{} }, span),
            .callback => |callback| result: {
                var arguments_out: [17]Id = undefined;
                for (callback.arguments, 0..) |argument, i| arguments_out[i] = try self.resolve(argument, arguments, callback.syntax.span);
                break :result self.intern(.{ .base = .{ .callback = .{
                    .effects = callback.syntax.effect_bound.allowed,
                    .mutates = try ast.mutPositions(self.allocator, callback.syntax.mut_parameters),
                    .return_origin = .unknown,
                } }, .arguments = arguments_out[0..callback.arguments.len] }, callback.syntax.span);
            },
            .builtin => |ty| self.intern(.{ .base = .{ .builtin = ty }, .arguments = &.{} }, span),
            .parameter => |index| arguments[index],
            .named => |id| self.intern(.{
                .base = .{ .named = id },
                // A synthesized case-payload record stands for the enclosing
                // union's own arguments, so its fields substitute like the union's.
                .arguments = if (self.templates.isSynthetic(id)) arguments else &.{},
            }, span),
            .application => |application| application: {
                var resolved: [16]Id = undefined;
                for (application.arguments, 0..) |argument, i| resolved[i] = try self.resolve(argument, arguments, application.syntax.arguments[i]);
                if (self.templates.isTuple(application.declaration)) break :application self.intern(
                    .{ .base = .{ .tuple = {} }, .arguments = resolved[0..application.arguments.len] },
                    application.syntax.span,
                );
                break :application self.intern(.{ .base = .{ .named = application.declaration }, .arguments = resolved[0..application.arguments.len] }, application.syntax.span);
            },
            .array => |array| array: {
                const element = try self.resolve(array.element, arguments, array.syntax.element);
                const key = if (array.key) |key| try self.resolve(key, arguments, array.syntax.index.enum_type) else null;
                var deferred_length: ?Id = null;
                const length = if (array.length_parameter) |index| length: {
                    const argument = self.nodes.items[@backingInt(arguments[index])].key.base;
                    if (argument == .length) break :length argument.length;
                    if (argument != .parameter) return self.sink.fail(diagnostic.generic_length, array.syntax.span, "array length parameter requires a constant length argument");
                    deferred_length = arguments[index];
                    break :length 0;
                } else array.length orelse self.templates.declarations.items[self.nodes.items[@backingInt(key.?)].key.base.named].fields.len;
                break :array self.intern(.{ .base = .{ .array = .{ .length = length, .key = key, .length_parameter = deferred_length } }, .arguments = &.{element} }, array.syntax.span);
            },
        };
    }
    /// Intern a concrete source type and validate only newly demanded storage dependencies.
    pub fn materialize(self: *Graph, value: templates.Expression, span: Span) Error!Id {
        if (templates.depends(value)) return self.sink.fail("E_GENERIC_BODY_UNSUPPORTED", span, "nominal specialization requires resolved concrete type arguments");
        try self.begin(span);
        const first = self.pending.items.len;
        const id = try self.resolve(value, &.{}, span);
        try self.need(id);
        try self.expand();
        try self.acyclic(first);
        return id;
    }
    /// Demand an already-resolved key when function specialization supplies concrete arguments.
    pub fn materializeKey(self: *Graph, key: Key, span: Span) Error!Id {
        try self.begin(span);
        const first = self.pending.items.len;
        const id = try self.intern(key, span);
        try self.need(id);
        try self.expand();
        try self.acyclic(first);
        return id;
    }
    fn roots(self: *Graph) Error!void {
        for (self.templates.declarations.items, 0..) |declaration, id| {
            if (declaration.builtin_name != null) continue;
            try self.begin(declaration.name);
            var arguments: [16]Id = undefined;
            for (declaration.parameters, 0..) |parameter, i| arguments[i] = try self.intern(.{ .base = .{ .parameter = .{ .declaration = id, .index = i } }, .arguments = &.{} }, parameter.name);
            try self.need(try self.intern(.{ .base = .{ .named = id }, .arguments = arguments[0..declaration.parameters.len] }, declaration.name));
        }
    }
    fn expand(self: *Graph) Error!void {
        while (self.budget.expanded < self.pending.items.len) {
            const id = self.pending.items[self.budget.expanded].id;
            self.budget.current = self.pending.items[self.budget.expanded].request;
            const node = self.nodes.items[@backingInt(id)];
            var edges: std.ArrayList(Edge) = .empty;
            defer edges.deinit(self.allocator);
            switch (node.key.base) {
                .named => |declaration| {
                    for (self.templates.declarations.items[declaration].fields) |field| if (field.ty) |value| {
                        const child = try self.resolve(value, node.key.arguments, field.name);
                        try self.need(child);
                        try edges.append(self.allocator, .{ .target = child, .span = field.name });
                    };
                },
                .callback => for (node.key.arguments) |argument| {
                    try self.need(argument);
                    try edges.append(self.allocator, .{ .target = argument, .span = node.site });
                },
                .array => |array| {
                    if (array.key) |key| try self.need(key);
                    // Existing finite-type policy follows even zero-length array elements.
                    const element = node.key.arguments[0];
                    try self.need(element);
                    try edges.append(self.allocator, .{ .target = element, .span = node.site });
                },
                .tuple => for (node.key.arguments) |element| {
                    try self.need(element);
                    try edges.append(self.allocator, .{ .target = element, .span = node.site });
                },
                else => {},
            }
            self.nodes.items[@backingInt(id)].edges = try edges.toOwnedSlice(self.allocator);
            self.nodes.items[@backingInt(id)].state = .ready;
            self.budget.expanded += 1;
        }
    }
    fn acyclic(self: *Graph, first: usize) Error!void {
        const Visit = struct { id: Id, next: usize = 0 };
        var stack: std.ArrayList(Visit) = .empty;
        defer stack.deinit(self.allocator);
        for (self.pending.items[first..]) |queued| {
            const root = queued.id;
            if (self.nodes.items[@backingInt(root)].state == .complete) continue;
            self.nodes.items[@backingInt(root)].state = .visiting;
            try stack.append(self.allocator, .{ .id = root });
            while (stack.items.len != 0) {
                const top = stack.items.len - 1;
                const visit = stack.items[top];
                const node = self.nodes.items[@backingInt(visit.id)];
                if (visit.next == node.edges.len or (node.key.base == .named and self.templates.declarations.items[node.key.base.named].managed)) {
                    self.nodes.items[@backingInt(visit.id)].state = .complete;
                    _ = stack.pop();
                    continue;
                }
                stack.items[top].next += 1;
                const edge = node.edges[visit.next];
                const child = self.nodes.items[@backingInt(edge.target)];
                if (child.state == .visiting) return self.sink.failRelated(
                    "E_RECURSIVE_RECORD",
                    edge.span,
                    "type fields must form a finite by-value layout; this edge closes a cycle",
                    .{ .span = child.site, .message = "this layout is already being expanded" },
                );
                if (child.state == .complete) continue;
                self.nodes.items[@backingInt(edge.target)].state = .visiting;
                try stack.append(self.allocator, .{ .id = edge.target });
            }
        }
    }
};
/// Validate every declaration with symbolic arguments; keep phantom argument identities unexpanded.
/// This proves bounded finite storage dependencies, not executable concrete layouts or operations.
pub fn collect(allocator: std.mem.Allocator, index: *const templates.Index, sink: *diagnostic.Sink) Error!Graph {
    var graph: Graph = .{ .allocator = allocator, .templates = index, .sink = sink };
    errdefer graph.deinit();
    try graph.roots();
    try graph.expand();
    try graph.acyclic(0);
    return graph;
}
