//! Nominal records/domains, structural arrays, and finite by-value layout checking.
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
    array_types: std.AutoHashMapUnmanaged(usize, typed.Type) = .empty,
    field_names: []std.StringHashMapUnmanaged(usize),

    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (self.array_types.get(span.start)) |ty| return ty;
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        return self.names.get(name) orelse sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    pub fn record(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a record value");
        const schema = self.records[ty.recordIndex()];
        if (!schema.isRecord()) return sink.fail("E_TYPE", span, "operation requires a record value");
        return schema;
    }
    pub fn array(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Array {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a fixed array value");
        return self.records[ty.recordIndex()].array orelse sink.fail("E_TYPE", span, "operation requires a fixed array value");
    }
    pub fn domain(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a nominal scalar domain");
        return self.records[ty.recordIndex()].domain orelse sink.fail("E_TYPE", span, "operation requires a nominal scalar domain");
    }
    pub fn variants(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Variants {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires an enum or tagged union");
        return self.records[ty.recordIndex()].variants orelse sink.fail("E_TYPE", span, "operation requires an enum or tagged union");
    }
    pub fn variant(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        _ = try self.variants(ty, name, sink);
        return self.field_names[ty.recordIndex()].get(src.text(name)) orelse sink.fail("E_UNKNOWN_VARIANT", name, "variant is not declared on this type");
    }
    pub fn field(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        _ = try self.record(ty, name, sink);
        return self.field_names[ty.recordIndex()].get(src.text(name)) orelse sink.fail("E_UNKNOWN_FIELD", name, "field does not exist on this record type");
    }
};

/// All storage is owned by the compilation arena.
pub fn collect(allocator: std.mem.Allocator, src: Source, declarations: []const ast.Record, domains: []const ast.Domain, variant_types: []const ast.Variants, arrays: []const ast.ArrayType, sink: *diagnostic.Sink) Error!Catalog {
    const storage = try allocator.alloc(typed.Record, declarations.len + domains.len + variant_types.len + arrays.len);
    var catalog: Catalog = .{ .records = storage[0 .. declarations.len + domains.len + variant_types.len], .names = .empty, .field_names = try allocator.alloc(std.StringHashMapUnmanaged(usize), declarations.len + domains.len + variant_types.len) };
    @memset(catalog.field_names, .empty);
    for (declarations, 0..) |declaration, i| {
        const name = src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "record type is already declared", .{ .span = declarations[previous.recordIndex()].name, .message = "previous record declaration" });
        const id: typed.Type = @fromBackingInt(i + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[i] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
    }
    for (domains, 0..) |declaration, offset| {
        const name = src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "previous type declaration" });
        const index = declarations.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
    }
    for (variant_types, 0..) |declaration, offset| {
        const name = src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "conflicting type declaration" });
        if (declaration.cases.len == 0) return sink.fail("E_EMPTY_VARIANTS", declaration.name, "closed enum and union types require at least one variant");
        const index = declarations.len + domains.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
    }
    var interned: std.AutoHashMapUnmanaged(typed.Array, typed.Type) = .empty;
    for (arrays) |syntax| {
        const digits = src.text(syntax.length);
        for (digits) |c| if (!std.ascii.isDigit(c)) return sink.fail("E_ARRAY_LENGTH", syntax.length, "array length must be an unsuffixed decimal integer");
        const length = std.fmt.parseInt(usize, digits, 10) catch return sink.fail("E_ARRAY_LENGTH", syntax.length, "array length exceeds the host index range");
        // A value buffer must fit addressable storage; no element metadata is expanded here.
        if (length > std.math.maxInt(usize) / @sizeOf(typed.Value)) return sink.fail("E_ARRAY_LENGTH", syntax.length, "array value storage exceeds the host address range");
        const element = try catalog.resolve(src, syntax.element, sink);
        const key: typed.Array = .{ .element = element, .length = length };
        const entry = try interned.getOrPut(allocator, key);
        if (!entry.found_existing) {
            const index = catalog.records.len;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            const name = try std.fmt.allocPrint(allocator, "[{d}]{s}", .{ length, typed.typeName(element, catalog.records) });
            storage[index] = .{ .id = id, .name = name, .declaration = syntax.span, .fields = &.{}, .array = key };
            catalog.records = storage[0 .. index + 1];
            entry.value_ptr.* = id;
        }
        try catalog.array_types.put(allocator, syntax.span.start, entry.value_ptr.*);
    }
    for (declarations, catalog.records[0..declarations.len], 0..) |declaration, *out, i| {
        const fields = try allocator.alloc(typed.Field, declaration.fields.len);
        for (declaration.fields, fields, 0..) |field, *resolved, j| {
            const name = src.text(field.name);
            if (catalog.field_names[i].get(name)) |previous| return sink.failRelated("E_DUPLICATE_FIELD", field.name, "field is already declared", .{ .span = fields[previous].declaration, .message = "previous field declaration" });
            try catalog.field_names[i].put(allocator, name, j);
            resolved.* = .{ .name = name, .declaration = field.name, .ty = try catalog.resolve(src, field.ty, sink) };
        }
        out.* = .{ .id = @fromBackingInt(i + typed.Type.record_base), .name = src.text(declaration.name), .declaration = declaration.name, .fields = fields };
    }
    for (domains, 0..) |declaration, offset| {
        const backing = try catalog.resolve(src, declaration.backing, sink);
        if (!backing.isInteger() and backing != .bool) return sink.fail("E_DOMAIN_BASE", declaration.backing, "domain backing must be a built-in integer or bool");
        storage[declarations.len + offset].domain = backing;
    }
    for (variant_types, 0..) |declaration, offset| {
        const index = declarations.len + domains.len + offset;
        const cases = try allocator.alloc(typed.Variant, declaration.cases.len);
        for (declaration.cases, cases, 0..) |input, *output, tag| {
            const name = src.text(input.name);
            if (catalog.field_names[index].get(name)) |previous| return sink.failRelated("E_DUPLICATE_VARIANT", input.name, "variant is already declared", .{ .span = cases[previous].declaration, .message = "previous variant declaration" });
            try catalog.field_names[index].put(allocator, name, tag);
            output.* = .{ .name = name, .declaration = input.name, .payload = if (input.payload) |payload| try catalog.resolve(src, payload, sink) else null };
        }
        storage[index].variants = .{ .is_union = declaration.is_union, .cases = cases };
    }
    // Iterative DFS rejects cycles without expanding records or recursing on the host.
    const State = enum { unseen, visiting, complete };
    const states = try allocator.alloc(State, catalog.records.len);
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
            const schema = catalog.records[visit.record];
            const edge_count = if (schema.variants) |v| v.cases.len else if (schema.array != null) @as(usize, 1) else schema.fields.len;
            if (visit.next_field == edge_count) {
                states[visit.record] = .complete;
                _ = work.pop();
                continue;
            }
            work.items[last].next_field += 1;
            const field: typed.Field = if (schema.variants) |v| .{ .name = v.cases[visit.next_field].name, .ty = v.cases[visit.next_field].payload orelse continue, .declaration = v.cases[visit.next_field].declaration } else if (schema.array) |a| .{ .name = "element", .ty = a.element, .declaration = schema.declaration } else schema.fields[visit.next_field];
            if (!field.ty.isAggregate()) continue;
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
