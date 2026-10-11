//! Bounded all-path lexical dominance for scoped file handles in typed DAGs.
const std = @import("std");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const Range = @import("semantic_copy.zig").Range;
/// Allocation failure or a handle outside its unique lexical scope.
pub const Error = error{ ComponentProtocol, OutOfMemory };
const absent = std.math.maxInt(usize);
const Edge = struct { target: usize, next: usize, enters: bool = false };
const State = struct { heads: []usize, incoming: []usize, context: []usize, parents: []usize, owners: []usize };
const Build = struct {
    allocator: std.mem.Allocator,
    owned: Range,
    state: State,
    edges: std.ArrayList(Edge) = .empty,
    row: usize = 0,
    nodes: []const typed.Node,
    fn edge(self: *Build, target: usize, enters: bool) Error!void {
        if (target >= self.state.heads.len or self.edges.items.len == 4194304) return error.ComponentProtocol;
        try self.edges.append(self.allocator, .{ .target = target, .next = self.state.heads[self.row], .enters = enters });
        self.state.heads[self.row] = self.edges.items.len - 1;
        self.state.incoming[target] += 1;
    }
    fn fields(self: *Build, comptime T: type, item: T) Error!void {
        @setEvalBranchQuota(200000);
        if (T == typed.NodeId) {
            const id = @backingInt(item);
            if (id < self.owned.nodes.start or id >= self.owned.nodes.end) return error.ComponentProtocol;
            if (self.nodes[id].ty.isFile()) return error.ComponentProtocol;
            return self.edge(id - self.owned.nodes.start, false);
        }
        if (T == typed.StatementId) {
            const id = @backingInt(item);
            if (id < self.owned.statements.start or id >= self.owned.statements.end) return error.ComponentProtocol;
            return self.edge(self.owned.nodes.end - self.owned.nodes.start + id - self.owned.statements.start, false);
        }
        switch (@typeInfo(T)) {
            .optional => |info| if (item) |present| try self.fields(info.child, present),
            .pointer => |info| if (info.size == .slice and info.child != u8) {
                for (item) |child| try self.fields(info.child, child);
            },
            .array => |info| for (item) |child| try self.fields(info.child, child),
            .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| try self.fields(Field, @field(item, name)),
            .@"union" => |info| inline for (info.field_names, info.field_types) |name, Field| {
                if (std.mem.eql(u8, @tagName(item), name)) try self.fields(Field, @field(item, name));
            },
            else => {},
        }
    }
};
fn ancestor(parents: []const usize, outer: usize, inner: usize) bool {
    var current = inner;
    while (current != 0) {
        if (current == outer) return true;
        current = parents[current];
    }
    return outer == 0;
}
fn common(parents: []const usize, left: usize, right: usize) usize {
    var result = left;
    while (!ancestor(parents, result, right)) result = parents[result];
    return result;
}
const Binding = struct { statement: @import("ast.zig").Statement, owner: usize };
const Bindings = std.AutoHashMapUnmanaged(@import("source.zig").Span, Binding);
/// Every file method must be dominated on every graph path by its binding's with body.
pub fn batch(a: std.mem.Allocator, input: value.Input, tables: value.Batch) Error!void {
    var bindings = try rawBindings(a, input);
    defer bindings.deinit(a);
    for (tables.functions, 0..) |_, id| try function(a, input, tables, id, bindings);
}
fn function(a: std.mem.Allocator, input: value.Input, tables: value.Batch, id: usize, bindings: Bindings) Error!void {
    const owned = tables.ranges[id];
    const locals = tables.functions[id].scope.locals;
    const nodes = owned.nodes.end - owned.nodes.start;
    const count = nodes + owned.statements.end - owned.statements.start + 1;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const storage = arena.allocator();
    const state: State = .{
        .heads = try storage.alloc(usize, count),
        .incoming = try storage.alloc(usize, count),
        .context = try storage.alloc(usize, count),
        .parents = try storage.alloc(usize, count + 1),
        .owners = try storage.alloc(usize, locals.len),
    };
    @memset(state.heads, absent);
    @memset(state.incoming, 0);
    @memset(state.context, absent);
    @memset(state.parents, 0);
    @memset(state.owners, absent);
    var build: Build = .{ .allocator = storage, .owned = owned, .state = state, .nodes = tables.nodes };
    for (tables.nodes[owned.nodes.start..owned.nodes.end], 0..) |node, row| {
        build.row = row;
        try build.fields(typed.Node, node);
    }
    for (tables.statements[owned.statements.start..owned.statements.end], 0..) |statement, row| {
        build.row = nodes + row;
        if (statement.data != .with_scope) {
            try build.fields(typed.Statement, statement);
            continue;
        }
        try binding(input, tables, locals, statement, bindings, id);
        const scope = statement.data.with_scope;
        const slot = @backingInt(scope.slot);
        if (state.owners[slot] != absent) return error.ComponentProtocol;
        state.owners[slot] = build.row + 1;
        const resource = @backingInt(scope.resource.?);
        if (resource < owned.nodes.start or resource >= owned.nodes.end) return error.ComponentProtocol;
        try build.edge(resource - owned.nodes.start, false);
        const body = @backingInt(scope.body);
        if (body < owned.statements.start or body >= owned.statements.end) return error.ComponentProtocol;
        try build.edge(nodes + body - owned.statements.start, true);
    }
    build.row = count - 1;
    try build.fields(typed.Function, tables.functions[id]);
    for (locals, state.owners) |local, owner| {
        if (local.ownership.scoped_file != (owner != absent)) return error.ComponentProtocol;
    }
    try walk(storage, tables, owned, build);
}
fn binding(input: value.Input, tables: value.Batch, locals: []const typed.Local, statement: typed.Statement, bindings: Bindings, owner: usize) Error!void {
    const scope = statement.data.with_scope;
    const slot = @backingInt(scope.slot);
    if (slot >= locals.len) return error.ComponentProtocol;
    const local = locals[slot];
    const resource = scope.resource orelse return error.ComponentProtocol;
    if (@backingInt(resource) >= tables.nodes.len or @backingInt(scope.body) >= tables.statements.len) return error.ComponentProtocol;
    if (!local.ty.isFile() or local.ty != tables.nodes[@backingInt(resource)].ty) return error.ComponentProtocol;
    if (local.mutable or !local.ownership.scoped_file) return error.ComponentProtocol;
    if (local.origin != .local or local.usage.reads == 0 or local.usage.temporary) return error.ComponentProtocol;
    if (statement.terminates != tables.statements[@backingInt(scope.body)].terminates) return error.ComponentProtocol;
    const joined = bindings.get(statement.span) orelse return error.ComponentProtocol;
    if (joined.owner != owner) return error.ComponentProtocol;
    const raw = joined.statement;
    const name = raw.data.with_scope.name orelse return error.ComponentProtocol;
    if (!std.meta.eql(local.declaration, name)) return error.ComponentProtocol;
    if (!std.mem.eql(u8, local.name, input.context.source[name.start..name.end])) return error.ComponentProtocol;
    const raw_resource = raw.data.with_scope.resource orelse return error.ComponentProtocol;
    const raw_span = input.program.nodes.items[@backingInt(raw_resource)].span;
    if (!std.meta.eql(tables.nodes[@backingInt(resource)].span, raw_span)) return error.ComponentProtocol;
}
fn walk(a: std.mem.Allocator, tables: value.Batch, owned: Range, build: Build) Error!void {
    const state = build.state;
    const nodes = owned.nodes.end - owned.nodes.start;
    var ready: std.ArrayList(usize) = .empty;
    for (state.incoming, 0..) |incoming, row| if (incoming == 0) {
        state.context[row] = 0;
        try ready.append(a, row);
    };
    var cursor: usize = 0;
    while (cursor < ready.items.len) : (cursor += 1) {
        const row = ready.items[cursor];
        const context = state.context[row];
        if (row < nodes) {
            const node = tables.nodes[owned.nodes.start + row];
            if (node.data == .file_method) {
                const owner = @backingInt(node.data.file_method.owner);
                if (owner >= state.owners.len or state.owners[owner] == absent) return error.ComponentProtocol;
                if (!ancestor(state.parents, state.owners[owner], context)) return error.ComponentProtocol;
            }
        } else if (row < state.heads.len - 1 and tables.statements[owned.statements.start + row - nodes].data == .with_scope) {
            state.parents[row + 1] = context;
            var depth: usize = 1;
            var parent = context;
            while (parent != 0) : (depth += 1) parent = state.parents[parent];
            if (depth > 256) return error.ComponentProtocol;
        }
        var link = state.heads[row];
        while (link != absent) {
            const edge = build.edges.items[link];
            const incoming = if (edge.enters) row + 1 else context;
            const old = state.context[edge.target];
            state.context[edge.target] = if (old == absent) incoming else common(state.parents, old, incoming);
            state.incoming[edge.target] -= 1;
            if (state.incoming[edge.target] == 0) try ready.append(a, edge.target);
            link = edge.next;
        }
    }
    if (cursor != state.heads.len) return error.ComponentProtocol;
}

fn rawBindings(a: std.mem.Allocator, input: value.Input) Error!Bindings {
    const ast = @import("ast.zig");
    var bindings: Bindings = .empty;
    errdefer bindings.deinit(a);
    const owners = try a.alloc(usize, input.program.statements.items.len);
    defer a.free(owners);
    @memset(owners, absent);
    var pending: std.ArrayList(ast.StatementId) = .empty;
    defer pending.deinit(a);
    var visits: usize = 0;
    for (input.program.functions, 0..) |raw, id| {
        try pending.append(a, raw.body);
        while (pending.pop()) |at| {
            if (visits == 4194304) return error.ComponentProtocol;
            visits += 1;
            const index = @backingInt(at);
            if (index >= owners.len) return error.ComponentProtocol;
            if (owners[index] != absent) {
                if (owners[index] != id) return error.ComponentProtocol;
                continue;
            }
            owners[index] = id;
            const statement = input.program.statements.items[index];
            if (statement.data == .with_scope) {
                const entry = try bindings.getOrPut(a, statement.span);
                if (entry.found_existing) return error.ComponentProtocol;
                entry.value_ptr.* = .{ .statement = statement, .owner = id };
            }
            try ast.appendNested(a, &pending, statement);
            if (pending.items.len > 4194304 - visits) return error.ComponentProtocol;
        }
    }
    return bindings;
}
