//! D9 acyclicity: recursive stored type components may not contain live views.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
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
/// Iterative Tarjan traversal over the batch `records[first..]`, with node numbers
/// relative to `first`. Uses O(batch) storage and visits each stored edge once.
/// Neither source depth nor a cyclic type consumes native stack depth. An edge into
/// a settled record is left out: settled records reach no batch record, so it
/// cannot close a cycle through the batch.
fn components(allocator: std.mem.Allocator, records: []const typed.Record, first: usize) ![]Node {
    const count = records.len - first;
    const nodes = try allocator.alloc(Node, count);
    errdefer allocator.free(nodes);
    @memset(nodes, .{});
    const frames = try allocator.alloc(Frame, count);
    defer allocator.free(frames);
    const members = try allocator.alloc(usize, count);
    defer allocator.free(members);
    var next: usize = 0;
    var used: usize = 0;
    for (0..count) |root| {
        if (nodes[root].index != none) continue;
        nodes[root] = .{ .index = next, .low = next, .active = true };
        next += 1;
        members[used] = root;
        used += 1;
        var depth: usize = 1;
        frames[0] = .{ .node = root };
        while (depth != 0) {
            const current = frames[depth - 1].node;
            const schema = records[first + current];
            if (frames[depth - 1].next < edgeCount(schema)) {
                const position = frames[depth - 1].next;
                frames[depth - 1].next += 1;
                const child_type = edge(schema, position) orelse continue;
                if (!child_type.isAggregate()) continue;
                const child_record = child_type.recordIndex();
                if (child_record >= records.len) return error.InternalError;
                if (child_record < first) continue;
                const child = child_record - first;
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
/// The declaration to report for the live view at batch node `view`: the first
/// batch field that stores it, else the first named record of its component. Every
/// record of a component that contains a batch record is itself in the batch.
fn location(records: []const typed.Record, first: usize, nodes: []const Node, view: usize) Span {
    const component = nodes[view].component;
    for (records[first..], nodes) |schema, node| {
        if (node.component != component) continue;
        for (schema.fields) |field| {
            if (field.ty == records[first + view].id and field.declaration.end > field.declaration.start) return field.declaration;
        }
    }
    for (records[first..], nodes) |schema, node| {
        if (node.component == component and schema.declaration.end > schema.declaration.start)
            return schema.declaration;
    }
    return records[first + view].declaration;
}
/// Reject only components containing a real builtin view-to-dictionary edge.
/// Names and generic type arguments alone are not storage or view identity.
/// Checks the records added since the last check, `records[first..]`. A settled
/// record reaches only settled records, so a cycle through a newly added record
/// lies among the added records. A batch with no live view has no such cycle and
/// is not searched. Returns the number of records searched (0 without a live view),
/// so a test can see that a check touches only its batch.
pub fn validateFrom(allocator: std.mem.Allocator, records: []const typed.Record, first: usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    var any = false;
    for (records[first..]) |schema| if (schema.shape.builtin == .live_view) {
        any = true;
        break;
    };
    if (!any) return 0;
    const nodes = try components(allocator, records, first);
    defer allocator.free(nodes);
    for (records[first..], 0..) |schema, index| {
        if (schema.shape.builtin != .live_view) continue;
        if (schema.fields.len != 1 or !schema.fields[0].ty.isAggregate()) return error.InternalError;
        const target = schema.fields[0].ty.recordIndex();
        // A settled target cannot reach this view, so it is in another component.
        if (target < first) continue;
        if (nodes[index].component == nodes[target - first].component)
            return sink.failOwnership(
                .{ .code = "E_LIVE_VIEW_CYCLE", .rule = .V6 },
                location(records, first, nodes, index),
                "recursive stored values cannot contain a live dictionary view cycle; store list(view) snapshots or pool ids instead",
            );
    }
    return records.len - first;
}
