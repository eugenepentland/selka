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
        labels: []const []const u8 = &.{},
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
                for (callback.labels, 0..) |label, position| {
                    if (label.len == 0) continue;
                    std.hash.autoHash(hasher, position);
                    std.hash.autoHash(hasher, label.len);
                    hasher.update(label);
                }
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
                    @import("callback_labels.zig").equalLabels(left.labels, right.labels) and
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
/// RECURSIVE-VALUES-1: a cycle every value of which holds another value of it.
const no_finite_value = "this recursive type has no finite value: every value of it holds another one; " ++
    "give the cycle a way out such as an `Option[...]` field, a payload-free union case or a `list[...]`";
/// The two boxing passes of RECURSIVE-VALUES-2, in the order they run.
const Pass = enum { union_payload, field };
/// Only storage dependencies form edges; phantom type arguments remain identities.
/// A `boxed` edge closes a recursive value type: the field or case stores a
/// pointer to an immutable managed box holding the value (RECURSIVE-VALUES-2).
pub const Edge = struct { target: Id, span: Span, boxed: bool = false };
/// Graph-owned layout identity with a separately discovered storage dependency list.
/// `inhabited` says the type has a finite value, which is what lets a cycle
/// through it be boxed instead of rejected (RECURSIVE-VALUES-1).
pub const Node = struct { key: Key, site: Span, edges: []Edge = &.{}, state: State = .unneeded, inhabited: bool = false };
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
                    .labels = try @import("callback_labels.zig").syntaxLabels(self.allocator, self.templates.context.src, callback.syntax),
                    .mutates = try ast.mutPositions(self.allocator, callback.syntax.parameter_modes.mut),
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
    /// Whether a named node's declaration is laid out through a pointer, so its
    /// fields are no by-value storage of the node itself.
    fn managedNode(self: *const Graph, node: Node) bool {
        return node.key.base == .named and self.templates.declarations.items[node.key.base.named].managed;
    }
    /// RECURSIVE-VALUES-1: the least fixpoint of "has a finite value" over the
    /// nodes this request expanded. A record or tuple needs every field, a union
    /// one case, an array its element unless it is empty; builtins, parameters
    /// and pointer-laid-out declarations always have one. Older nodes already
    /// carry their answer, and no older node reaches a newer one. Nodes are
    /// visited in reverse discovery order, which is roughly children first.
    fn inhabit(self: *Graph, first: usize) void {
        var changed = true;
        while (changed) {
            changed = false;
            var position = self.pending.items.len;
            while (position > first) {
                position -= 1;
                const id = self.pending.items[position].id;
                const node = self.nodes.items[@backingInt(id)];
                if (node.inhabited or !self.hasValue(node)) continue;
                self.nodes.items[@backingInt(id)].inhabited = true;
                changed = true;
            }
        }
    }
    fn hasValue(self: *const Graph, node: Node) bool {
        switch (node.key.base) {
            .named => |declaration_id| {
                const declaration = self.templates.declarations.items[declaration_id];
                if (declaration.managed) return true;
                switch (declaration.kind) {
                    .variants, .result, .enumeration => {
                        // A payload-free case has no edge and is a value by itself.
                        if (node.edges.len < declaration.fields.len) return true;
                        for (node.edges) |edge| if (self.nodes.items[@backingInt(edge.target)].inhabited) return true;
                        return false;
                    },
                    .record, .tuple => {},
                    .domain, .buffer, .resource => return true,
                }
            },
            .array => |array| if (array.length == 0 or array.length_parameter != null) return true,
            .tuple => {},
            .callback, .builtin, .length, .parameter => return true,
        }
        for (node.edges) |edge| if (!self.nodes.items[@backingInt(edge.target)].inhabited) return false;
        return true;
    }
    fn acyclic(self: *Graph, first: usize) Error!void {
        self.inhabit(first);
        try self.finite(first);
        try self.box(first);
    }
    /// Reject a cycle through a type with no finite value (RECURSIVE-VALUES-1).
    /// A cycle through a type that has one is a recursive value type, which
    /// `box` lays out instead.
    fn finite(self: *Graph, first: usize) Error!void {
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
                if (visit.next == node.edges.len or self.managedNode(node)) {
                    self.nodes.items[@backingInt(visit.id)].state = .complete;
                    _ = stack.pop();
                    continue;
                }
                stack.items[top].next += 1;
                const edge = node.edges[visit.next];
                const child = self.nodes.items[@backingInt(edge.target)];
                if (child.state == .visiting and child.inhabited) continue;
                if (child.state == .visiting) return self.sink.failRelated(diagnostic.recursive_record, edge.span, no_finite_value, .{ .span = child.site, .message = "this type contains itself" });
                if (child.state == .complete) continue;
                self.nodes.items[@backingInt(edge.target)].state = .visiting;
                try stack.append(self.allocator, .{ .id = edge.target });
            }
        }
    }
    /// RECURSIVE-VALUES-2: choose which edges of the newly expanded nodes store
    /// their value behind an immutable box. Inside every strongly connected set
    /// of by-value storage, first each union case payload that stays inside the
    /// set is boxed — one box per recursive case, and an `Option` of a boxed
    /// value is one nullable word — and then, for a cycle through no union at
    /// all, each record or tuple field that still closes one. The choice depends
    /// only on the declarations, never on the order they were discovered in.
    fn box(self: *Graph, first: usize) Error!void {
        const members = self.pending.items[first..];
        if (members.len == 0) return;
        const allocator = self.allocator;
        var local: std.AutoHashMapUnmanaged(usize, usize) = .empty;
        defer local.deinit(allocator);
        for (members, 0..) |member, position| try local.put(allocator, @backingInt(member.id), position);
        const component = try allocator.alloc(usize, members.len);
        defer allocator.free(component);
        try self.components(members, &local, component);
        // Most requests close no cycle at all, and then nothing is boxed.
        if (!self.cyclic(members, &local, component)) return;
        for ([_]Pass{ .union_payload, .field }) |pass| {
            for (members, 0..) |member, position| {
                const node = &self.nodes.items[@backingInt(member.id)];
                if (self.managedNode(node.*) or !self.boxable(node.*, pass)) continue;
                for (node.edges) |*edge| {
                    const target = local.get(@backingInt(edge.target)) orelse continue;
                    if (component[target] == component[position]) edge.boxed = true;
                }
            }
            try self.components(members, &local, component);
        }
        // Every inhabited cycle runs through a union case or a field (arrays
        // alone cannot close one), so the two passes leave none.
        if (self.cyclic(members, &local, component)) return error.InternalError;
    }
    /// Whether some unboxed by-value edge stays inside its component.
    fn cyclic(self: *const Graph, members: []const Pending, local: *const std.AutoHashMapUnmanaged(usize, usize), component: []const usize) bool {
        for (members, 0..) |member, position| {
            const node = self.nodes.items[@backingInt(member.id)];
            if (self.managedNode(node)) continue;
            for (node.edges) |edge| {
                if (edge.boxed) continue;
                const target = local.get(@backingInt(edge.target)) orelse continue;
                if (component[target] == component[position]) return true;
            }
        }
        return false;
    }
    /// Whether the boxing pass `pass` boxes the edges of `node`: a union's
    /// case payloads (an `Option` or `Result` is one), or a record's or
    /// tuple's fields. An array element is never boxed.
    fn boxable(self: *const Graph, node: Node, pass: Pass) bool {
        return switch (node.key.base) {
            .named => |declaration_id| switch (self.templates.declarations.items[declaration_id].kind) {
                .variants, .result => pass == .union_payload,
                .record => pass == .field,
                else => false,
            },
            .tuple => pass == .field,
            else => false,
        };
    }
    /// Tarjan's strongly connected components of the request's nodes over their
    /// unboxed by-value edges, iteratively, so a long declaration chain never
    /// recurses on the host stack. `component[i]` names member `i`'s set.
    fn components(self: *Graph, members: []const Pending, local: *const std.AutoHashMapUnmanaged(usize, usize), component: []usize) Error!void {
        const allocator = self.allocator;
        const unvisited = std.math.maxInt(usize);
        const order = try allocator.alloc(usize, members.len);
        defer allocator.free(order);
        const low = try allocator.alloc(usize, members.len);
        defer allocator.free(low);
        const on_stack = try allocator.alloc(bool, members.len);
        defer allocator.free(on_stack);
        @memset(order, unvisited);
        @memset(on_stack, false);
        var stack: std.ArrayList(usize) = .empty;
        defer stack.deinit(allocator);
        const Frame = struct { member: usize, next: usize = 0 };
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(allocator);
        var counter: usize = 0;
        var sets: usize = 0;
        for (0..members.len) |root| {
            if (order[root] != unvisited) continue;
            try frames.append(allocator, .{ .member = root });
            order[root] = counter;
            low[root] = counter;
            counter += 1;
            try stack.append(allocator, root);
            on_stack[root] = true;
            while (frames.items.len != 0) {
                const top = &frames.items[frames.items.len - 1];
                const node = self.nodes.items[@backingInt(members[top.member].id)];
                const edges: []const Edge = if (self.managedNode(node)) &.{} else node.edges;
                if (top.next < edges.len) {
                    const edge = edges[top.next];
                    top.next += 1;
                    if (edge.boxed) continue;
                    const target = local.get(@backingInt(edge.target)) orelse continue;
                    if (order[target] == unvisited) {
                        order[target] = counter;
                        low[target] = counter;
                        counter += 1;
                        try stack.append(allocator, target);
                        on_stack[target] = true;
                        try frames.append(allocator, .{ .member = target });
                    } else if (on_stack[target]) low[top.member] = @min(low[top.member], order[target]);
                    continue;
                }
                const finished = top.member;
                _ = frames.pop();
                if (frames.items.len != 0) {
                    const parent = frames.items[frames.items.len - 1].member;
                    low[parent] = @min(low[parent], low[finished]);
                }
                if (low[finished] != order[finished]) continue;
                while (stack.pop()) |member| {
                    on_stack[member] = false;
                    component[member] = sets;
                    if (member == finished) break;
                }
                sets += 1;
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
