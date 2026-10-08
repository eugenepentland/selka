//! D9 acyclicity: recursive stored type components may not contain live views.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const Span = @import("source.zig").Span;
const none = std.math.maxInt(usize);
const Node = struct { index: usize = none, low: usize = none, component: usize = none, active: bool = false };
const Frame = struct { node: usize, next: usize = 0 };

/// Stored runtime edges, including managed collection elements and immutable
/// boxes. A zero-length array stores no element; callbacks carry no captures.
fn edgeCount(schema: typed.Record) usize {
    if (schema.contract.callback != null) return 0;
    return schema.fields.len +
        (if (schema.shape.variants) |v| v.cases.len else @as(usize, 0)) +
        @intFromBool(schema.shape.domain != null) +
        @intFromBool(if (schema.shape.array) |a| a.length != 0 else false) +
        @intFromBool(schema.shape.buffer != null) + @intFromBool(schema.collection.key != null);
}
fn edge(schema: typed.Record, position: usize) ?typed.Type {
    var at = position;
    if (at < schema.fields.len) return schema.fields[at].ty;
    at -= schema.fields.len;
    if (schema.shape.variants) |v| {
        if (at < v.cases.len) return v.cases[at].payload;
        at -= v.cases.len;
    }
    if (schema.shape.domain) |domain| {
        if (at == 0) return domain;
        at -= 1;
    }
    if (schema.shape.array) |array| if (array.length != 0) {
        if (at == 0) return array.element;
        at -= 1;
    };
    if (schema.shape.buffer) |element| {
        if (at == 0) return element;
        at -= 1;
    }
    return if (at == 0) schema.collection.key else null;
}
/// Iterative Tarjan traversal uses O(types) storage and visits each stored edge
/// once. Neither source depth nor a cyclic type consumes native stack depth.
fn components(allocator: std.mem.Allocator, records: []const typed.Record) ![]Node {
    const nodes = try allocator.alloc(Node, records.len);
    errdefer allocator.free(nodes);
    @memset(nodes, .{});
    const frames = try allocator.alloc(Frame, records.len);
    defer allocator.free(frames);
    const members = try allocator.alloc(usize, records.len);
    defer allocator.free(members);
    var next: usize = 0;
    var used: usize = 0;
    for (records, 0..) |_, root| {
        if (nodes[root].index != none) continue;
        nodes[root] = .{ .index = next, .low = next, .active = true };
        next += 1;
        members[used] = root;
        used += 1;
        var depth: usize = 1;
        frames[0] = .{ .node = root };
        while (depth != 0) {
            const current = frames[depth - 1].node;
            const schema = records[current];
            if (frames[depth - 1].next < edgeCount(schema)) {
                const position = frames[depth - 1].next;
                frames[depth - 1].next += 1;
                const child_type = edge(schema, position) orelse continue;
                if (!child_type.isAggregate()) continue;
                const child = child_type.recordIndex();
                if (child >= nodes.len) return error.InternalError;
                if (nodes[child].index == none) {
                    nodes[child] = .{ .index = next, .low = next, .active = true };
                    next += 1;
                    members[used] = child;
                    used += 1;
                    frames[depth] = .{ .node = child };
                    depth += 1;
                } else if (nodes[child].active) nodes[current].low = @min(nodes[current].low, nodes[child].index);
                continue;
            }
            if (nodes[current].low == nodes[current].index) {
                while (true) {
                    used -= 1;
                    const member = members[used];
                    nodes[member].active = false;
                    nodes[member].component = current;
                    if (member == current) break;
                }
            }
            depth -= 1;
            if (depth != 0) {
                const parent = frames[depth - 1].node;
                nodes[parent].low = @min(nodes[parent].low, nodes[current].low);
            }
        }
    }
    return nodes;
}
fn location(records: []const typed.Record, nodes: []const Node, view: usize) Span {
    for (records, 0..) |schema, index| {
        if (nodes[index].component != nodes[view].component) continue;
        for (schema.fields) |field| {
            if (field.ty == records[view].id and field.declaration.end > field.declaration.start) return field.declaration;
        }
    }
    for (records, 0..) |schema, index| {
        if (nodes[index].component == nodes[view].component and schema.declaration.end > schema.declaration.start)
            return schema.declaration;
    }
    return records[view].declaration;
}
/// Reject only components containing a real builtin view-to-dictionary edge.
/// Names and generic type arguments alone are not storage or view identity.
pub fn validate(allocator: std.mem.Allocator, catalog: Catalog, sink: *diagnostic.Sink) diagnostic.Error!void {
    var any = false;
    for (catalog.records) |schema| if (schema.shape.builtin == .live_view) {
        any = true;
        break;
    };
    if (!any) return;
    const nodes = try components(allocator, catalog.records);
    defer allocator.free(nodes);
    for (catalog.records, 0..) |schema, index| {
        if (schema.shape.builtin != .live_view) continue;
        if (schema.fields.len != 1 or !schema.fields[0].ty.isAggregate()) return error.InternalError;
        const target = schema.fields[0].ty.recordIndex();
        if (nodes[index].component == nodes[target].component)
            return sink.fail("E_LIVE_VIEW_CYCLE", location(catalog.records, nodes, index), "recursive stored values cannot contain a live dictionary view cycle; store list(view) snapshots or pool ids instead");
    }
}
