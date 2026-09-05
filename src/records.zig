//! Nominal record schemas and finite by-value layout checking.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;

pub const Catalog = struct {
    records: []typed.Record,
    names: std.StringHashMapUnmanaged(typed.Type),
    field_names: []std.StringHashMapUnmanaged(usize),

    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        return self.names.get(name) orelse sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    pub fn record(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (!ty.isRecord()) return sink.fail("E_TYPE", span, "operation requires a record value");
        return self.records[ty.recordIndex()];
    }
    pub fn field(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        _ = try self.record(ty, name, sink);
        return self.field_names[ty.recordIndex()].get(src.text(name)) orelse sink.fail("E_UNKNOWN_FIELD", name, "field does not exist on this record type");
    }
};

/// All storage is owned by the compilation arena.
pub fn collect(allocator: std.mem.Allocator, src: Source, declarations: []const ast.Record, sink: *diagnostic.Sink) Error!Catalog {
    var catalog: Catalog = .{ .records = try allocator.alloc(typed.Record, declarations.len), .names = .empty, .field_names = try allocator.alloc(std.StringHashMapUnmanaged(usize), declarations.len) };
    @memset(catalog.field_names, .empty);
    for (declarations, 0..) |declaration, i| {
        const name = src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "record type is already declared", .{ .span = declarations[previous.recordIndex()].name, .message = "previous record declaration" });
        try catalog.names.put(allocator, name, @fromBackingInt(i + typed.Type.record_base));
    }
    for (declarations, catalog.records, 0..) |declaration, *out, i| {
        const fields = try allocator.alloc(typed.Field, declaration.fields.len);
        for (declaration.fields, fields, 0..) |field, *resolved, j| {
            const name = src.text(field.name);
            if (catalog.field_names[i].get(name)) |previous| return sink.failRelated("E_DUPLICATE_FIELD", field.name, "field is already declared", .{ .span = fields[previous].declaration, .message = "previous field declaration" });
            try catalog.field_names[i].put(allocator, name, j);
            resolved.* = .{ .name = name, .declaration = field.name, .ty = try catalog.resolve(src, field.ty, sink) };
        }
        out.* = .{ .id = @fromBackingInt(i + typed.Type.record_base), .name = src.text(declaration.name), .declaration = declaration.name, .fields = fields };
    }
    // Iterative DFS rejects cycles without expanding records or recursing on the host.
    const State = enum { unseen, visiting, complete };
    const states = try allocator.alloc(State, declarations.len);
    defer allocator.free(states);
    @memset(states, .unseen);
    const Visit = struct { record: usize, next_field: usize = 0 };
    var work: std.ArrayList(Visit) = .empty;
    defer work.deinit(allocator);
    for (catalog.records, 0..) |_, root| {
        if (states[root] != .unseen) continue;
        states[root] = .visiting;
        try work.append(allocator, .{ .record = root });
        while (work.items.len != 0) {
            const last = work.items.len - 1;
            const visit = work.items[last];
            const fields = catalog.records[visit.record].fields;
            if (visit.next_field == fields.len) {
                states[visit.record] = .complete;
                _ = work.pop();
                continue;
            }
            work.items[last].next_field += 1;
            const field = fields[visit.next_field];
            if (!field.ty.isRecord()) continue;
            const child = field.ty.recordIndex();
            if (states[child] == .visiting) return sink.fail("E_RECURSIVE_RECORD", field.declaration, "record fields must form a finite by-value layout; this field closes a cycle");
            if (states[child] == .unseen) {
                states[child] = .visiting;
                try work.append(allocator, .{ .record = child });
            }
        }
    }
    return catalog;
}
