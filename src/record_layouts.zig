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
            // A boxed payload is a shared managed reference, like a list element;
            // `boxedContents` holds its value to the list rules.
            for (variants.cases) |case| if (case.payload) |payload| if (!case.boxed) {
                requires_handling = requires_handling or typed.requiresHandling(payload, records);
                can_store = can_store and typed.storable(payload, records);
                move_only = move_only or typed.moveOnly(payload, records);
            };
        } else if (schema.shape.array) |array| {
            requires_handling = array.length != 0 and typed.requiresHandling(array.element, records);
            can_store = can_store and (array.length == 0 or typed.storable(array.element, records));
            move_only = array.length != 0 and typed.moveOnly(array.element, records);
        } else if (!schema.managed) {
            for (schema.fields) |field| if (!field.boxed) {
                requires_handling = requires_handling or typed.requiresHandling(field.ty, records);
                can_store = can_store and typed.storable(field.ty, records);
                move_only = move_only or typed.moveOnly(field.ty, records);
            };
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
                    .boxed = v.cases[visit.next_field].boxed,
                } else if (schema.shape.array) |a| .{
                    .name = "element",
                    .ty = a.element,
                    .declaration = schema.declaration,
                } else if (schema.shape.buffer) |element| .{
                    .name = "element",
                    .ty = element,
                    .declaration = schema.declaration,
                } else schema.fields[visit.next_field];
                // A boxed edge is a pointer, so it adds nothing to the layout.
                if (!field.ty.isAggregate() or field.boxed) continue;
                const child = field.ty.recordIndex();
                if (states[child] == .visiting) return sink.fail(diagnostic.recursive_record, field.declaration, "record fields must form a finite by-value layout; this field closes a cycle");
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
    const capabilities = try dependencies(allocator, records, .capability);
    defer allocator.free(capabilities);
    for (records) |schema| if (schema.isCollection()) {
        if (carries(schema.shape.buffer.?, capabilities, .capability)) return sink.fail("E_LIST_CAPABILITY", schema.declaration, "managed list elements cannot contain allocator or provider capabilities");
    };
    const files = try dependencies(allocator, records, .file);
    defer allocator.free(files);
    try boxedContents(records, capabilities, files, sink);
    try @import("cell_types.zig").validate(allocator, records, sink);
}

/// RECURSIVE-VALUES-2: a boxed value is shared by every copy of its holder,
/// exactly as a list element is, so it obeys the list element rules: no owned
/// resource, no pending result obligation and no capability.
fn boxedContents(records: []const typed.Record, capabilities: []const bool, files: []const bool, sink: *diagnostic.Sink) Error!void {
    for (records) |schema| {
        if (schema.shape.variants) |variants| for (variants.cases) |case| {
            if (case.boxed) try boxedContent(records, capabilities, files, case.payload.?, case.declaration, sink);
        };
        for (schema.fields) |field| if (field.boxed) try boxedContent(records, capabilities, files, field.ty, field.declaration, sink);
    }
}
fn boxedContent(records: []const typed.Record, capabilities: []const bool, files: []const bool, ty: typed.Type, declaration: @import("source.zig").Span, sink: *diagnostic.Sink) Error!void {
    const owns_resource = typed.moveOnly(ty, records) or carries(ty, files, .file);
    if (!typed.storable(ty, records) or owns_resource or typed.requiresHandling(ty, records))
        return sink.fail(diagnostic.recursive_record, declaration, "a recursive value type is shared through immutable boxes, so it cannot hold an owned resource or an unhandled result");
    if (carries(ty, capabilities, .capability))
        return sink.fail(diagnostic.recursive_record, declaration, "a recursive value type is shared through immutable boxes, so it cannot hold a capability");
}
const Dependency = enum { managed, capability, file };
fn carries(ty: typed.Type, contains: []const bool, kind: Dependency) bool {
    if (kind == .capability and ty.capabilityIndex() != null) return true;
    if (kind == .file and ty.isFile()) return true;
    return ty.isAggregate() and contains[ty.recordIndex()];
}
fn dependencies(allocator: std.mem.Allocator, records: []const typed.Record, kind: Dependency) std.mem.Allocator.Error![]bool {
    const flags = try allocator.alloc(bool, records.len);
    for (records, flags) |schema, *contains| contains.* = kind == .managed and schema.managed;
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |schema, index| {
            if (flags[index]) continue;
            if (recordCarries(schema, flags, kind)) {
                flags[index] = true;
                changed = true;
            }
        }
    }
    return flags;
}
fn recordCarries(schema: typed.Record, flags: []const bool, kind: Dependency) bool {
    // File ownership belongs to inline storage. A managed reference keeps its
    // own separate layout and must not turn its holder into a resource body.
    if (kind == .file and schema.managed) return false;
    if (schema.shape.array) |array| if (kind != .file or array.length != 0) {
        if (carries(array.element, flags, kind)) return true;
    };
    if (schema.shape.domain) |domain| if (carries(domain, flags, kind)) return true;
    // A boxed field or case holds a managed reference itself (RECURSIVE-VALUES-2).
    if (schema.shape.variants) |variants| for (variants.cases) |case| {
        if (case.boxed and kind == .managed) return true;
        if (case.payload) |payload| if (carries(payload, flags, kind)) return true;
    };
    for (schema.fields) |field| {
        if (field.boxed and kind == .managed) return true;
        if (carries(field.ty, flags, kind)) return true;
    }
    return false;
}

/// The schema of a tuple type, or null for any other type. A tuple's element
/// types are its fields in positional order, which is what keeps every consumer
/// reading one marker instead of a spelling.
pub fn tupleRecord(records: []const typed.Record, ty: typed.Type) ?typed.Record {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const schema = records[ty.recordIndex()];
    return if (schema.shape.tuple) schema else null;
}
