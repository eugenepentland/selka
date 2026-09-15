//! Shared finite runtime-schema validation and ownership/result contract propagation.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Checker = struct {
    allocator: std.mem.Allocator,
    records: []typed.Record,
    sink: *diagnostic.Sink,
    fn finishLayout(self: *Checker, record_index: usize, schema: typed.Record) Error!void {
        const records = self.records;
        var requires_handling = false;
        var can_store = schema.shape.resource == null;
        var move_only = schema.shape.resource != null;
        if (schema.shape.variants) |variants| {
            requires_handling = variants.fallible;
            for (variants.cases) |case| if (case.payload) |payload| {
                requires_handling = requires_handling or typed.requiresHandling(payload, records);
                can_store = can_store and typed.storable(payload, records);
                move_only = move_only or typed.moveOnly(payload, records);
            };
        } else if (schema.shape.array) |array| {
            requires_handling = array.length != 0 and typed.requiresHandling(array.element, records);
            can_store = can_store and (array.length == 0 or typed.storable(array.element, records));
            move_only = array.length != 0 and typed.moveOnly(array.element, records);
        } else if (!schema.managed) {
            for (schema.fields) |field| {
                requires_handling = requires_handling or typed.requiresHandling(field.ty, records);
                can_store = can_store and typed.storable(field.ty, records);
                move_only = move_only or typed.moveOnly(field.ty, records);
            }
        }
        records[record_index].contract.storable = can_store and !requires_handling;
        records[record_index].contract.move_only = move_only;
        records[record_index].contract.requires_handling = requires_handling;
    }
    fn validateLayouts(self: *Checker) Error!void {
        const allocator = self.allocator;
        const sink = self.sink;
        const records = self.records;
        // Iterative DFS rejects cycles without expanding records or recursing on the host.
        const State = enum { unseen, visiting, complete };
        const states = try allocator.alloc(State, records.len);
        defer allocator.free(states);
        @memset(states, .unseen);
        const Visit = struct { record: usize, next_field: usize = 0 };
        var work: std.ArrayList(Visit) = .empty;
        defer work.deinit(allocator);
        for (records, 0..) |_, root| {
            if (states[root] != .unseen) continue;
            states[root] = .visiting;
            try work.append(allocator, .{ .record = root });
            while (work.items.len != 0) {
                const last = work.items.len - 1;
                const visit = work.items[last];
                const schema = records[visit.record];
                const container = schema.shape.array != null or schema.shape.buffer != null;
                const edge_count = if (schema.managed) @as(usize, 0) else if (schema.shape.variants) |v| v.cases.len else if (container) @as(usize, 1) else schema.fields.len;
                if (visit.next_field == edge_count) {
                    try self.finishLayout(visit.record, schema);
                    states[visit.record] = .complete;
                    _ = work.pop();
                    continue;
                }
                work.items[last].next_field += 1;
                const field: typed.Field = if (schema.shape.variants) |v| .{
                    .name = v.cases[visit.next_field].name,
                    .ty = v.cases[visit.next_field].payload orelse continue,
                    .declaration = v.cases[visit.next_field].declaration,
                } else if (schema.shape.array) |a| .{
                    .name = "element",
                    .ty = a.element,
                    .declaration = schema.declaration,
                } else if (schema.shape.buffer) |element| .{
                    .name = "element",
                    .ty = element,
                    .declaration = schema.declaration,
                } else schema.fields[visit.next_field];
                if (!field.ty.isAggregate()) continue;
                const child = field.ty.recordIndex();
                if (states[child] == .visiting) return sink.fail("E_RECURSIVE_RECORD", field.declaration, "record fields must form a finite by-value layout; this field closes a cycle");
                if (states[child] == .unseen) {
                    states[child] = .visiting;
                    try work.append(allocator, .{ .record = child });
                }
            }
        }
    }
};
/// Check by-value dependencies and derive contracts for ordinary and specialized schemas.
pub fn validate(allocator: std.mem.Allocator, records: []typed.Record, sink: *diagnostic.Sink) Error!void {
    var checker: Checker = .{ .allocator = allocator, .records = records, .sink = sink };
    try checker.validateLayouts();
    // Managed edges do not affect value layout, but all their elements must be copyable.
    for (records) |schema| if (schema.isCollection()) {
        const element = schema.shape.buffer.?;
        if (!typed.storable(element, records) or typed.moveOnly(element, records)) return sink.fail("E_LIST_ELEMENT", schema.declaration, "managed list elements must be copyable values without resources or result obligations");
    };
    const capabilities = try dependencies(allocator, records, true);
    defer allocator.free(capabilities);
    for (records) |schema| if (schema.isCollection()) {
        if (carries(schema.shape.buffer.?, capabilities, true)) return sink.fail("E_LIST_CAPABILITY", schema.declaration, "managed list elements cannot contain allocator or provider capabilities");
    };
    try @import("cell_types.zig").validate(allocator, records, sink);
}

fn carries(ty: typed.Type, contains: []const bool, capability: bool) bool {
    if (capability and ty.capabilityIndex() != null) return true;
    return ty.isAggregate() and contains[ty.recordIndex()];
}
fn dependencies(allocator: std.mem.Allocator, records: []const typed.Record, capability: bool) std.mem.Allocator.Error![]bool {
    const flags = try allocator.alloc(bool, records.len);
    for (records, flags) |schema, *contains| contains.* = !capability and schema.managed;
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |schema, index| {
            if (flags[index]) continue;
            if (recordCarries(schema, flags, capability)) {
                flags[index] = true;
                changed = true;
            }
        }
    }
    return flags;
}
fn recordCarries(schema: typed.Record, flags: []const bool, capability: bool) bool {
    if (schema.shape.array) |array| if (carries(array.element, flags, capability)) return true;
    if (schema.shape.domain) |domain| if (carries(domain, flags, capability)) return true;
    if (schema.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (carries(payload, flags, capability)) return true;
    };
    for (schema.fields) |field| if (carries(field.ty, flags, capability)) return true;
    return false;
}

/// Compute transitive managed references through value fields without recursive traversal.
pub fn managedTypes(allocator: std.mem.Allocator, records: []const typed.Record) std.mem.Allocator.Error![]bool {
    return dependencies(allocator, records, false);
}
