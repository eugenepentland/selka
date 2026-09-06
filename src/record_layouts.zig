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
        const sink = self.sink;
        var requires_handling = false;
        var move_only = schema.shape.buffer != null or schema.shape.resource != null or schema.shape.pool != null;
        if (schema.shape.variants) |variants| {
            requires_handling = variants.fallible;
            for (variants.cases) |case| if (case.payload) |payload| {
                requires_handling = requires_handling or typed.requiresHandling(payload, records);
                move_only = move_only or typed.moveOnly(payload, records);
            };
        } else if (schema.shape.array) |array| {
            requires_handling = array.length != 0 and typed.requiresHandling(array.element, records);
            move_only = array.length != 0 and typed.moveOnly(array.element, records);
        } else {
            for (schema.fields) |field| {
                requires_handling = requires_handling or typed.requiresHandling(field.ty, records);
                move_only = move_only or typed.moveOnly(field.ty, records);
            }
        }
        if (schema.shape.buffer) |element| {
            if (typed.moveOnly(element, records) or typed.requiresHandling(element, records)) return sink.fail(
                "E_BUFFER_ELEMENT",
                schema.declaration,
                "buffer elements must be ordinary copyable values without result obligations",
            );
        }
        if (schema.shape.pool) |pool| {
            if (typed.moveOnly(pool.element, records) or typed.requiresHandling(pool.element, records)) return sink.fail(
                "E_POOL_ELEMENT",
                schema.declaration,
                "pool elements must be ordinary copyable values without result obligations",
            );
        }
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
                const edge_count = if (schema.shape.variants) |v| v.cases.len else if (schema.shape.array != null or schema.shape.buffer != null or schema.shape.pool != null) @as(usize, 1) else schema.fields.len;
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
                } else if (schema.shape.pool) |pool| .{
                    .name = "element",
                    .ty = pool.element,
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
}
