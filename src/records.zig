//! Nominal records/domains, structural arrays, and finite by-value layout checking.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;

pub const Catalog = struct {
    module_names: ?*Names = null,
    records: []typed.Record,
    names: std.StringHashMapUnmanaged(typed.Type),
    array_types: std.AutoHashMapUnmanaged(usize, typed.Type) = .empty,
    field_names: []std.StringHashMapUnmanaged(usize),

    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (self.array_types.get(span.start)) |ty| return ty;
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        const key = if (self.module_names) |names| try names.reference(span, .type, null, null, sink) else name;
        return self.names.get(key) orelse sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    pub fn record(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a record value");
        const schema = self.records[ty.recordIndex()];
        if (!schema.isRecord()) return sink.fail("E_TYPE", span, "operation requires a record value");
        return schema;
    }
    pub fn constructor(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (ty.isAggregate() and self.records[ty.recordIndex()].tableKey() != null) return self.records[ty.recordIndex()];
        return self.record(ty, span, sink);
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
pub fn collect(allocator: std.mem.Allocator, src: Source, declarations: []const ast.Record, domains: []const ast.Domain, variant_types: []const ast.Variants, arrays: []const ast.ArrayType, buffers: []const ast.Domain, resources: []const ast.Domain, pools: []const ast.Pool, sink: *diagnostic.Sink) Error!Catalog {
    return collectWithNames(allocator, src, declarations, domains, variant_types, arrays, buffers, resources, pools, sink, null);
}

pub fn collectWithNames(allocator: std.mem.Allocator, src: Source, declarations: []const ast.Record, domains: []const ast.Domain, variant_types: []const ast.Variants, arrays: []const ast.ArrayType, buffers: []const ast.Domain, resources: []const ast.Domain, pools: []const ast.Pool, sink: *diagnostic.Sink, module_names: ?*Names) Error!Catalog {
    const pool_base = declarations.len + domains.len + variant_types.len + buffers.len + resources.len;
    const named_count = pool_base + pools.len * 2;
    const storage = try allocator.alloc(typed.Record, named_count + arrays.len);
    var catalog: Catalog = .{ .module_names = module_names, .records = storage[0..named_count], .names = .empty, .field_names = try allocator.alloc(std.StringHashMapUnmanaged(usize), named_count) };
    @memset(catalog.field_names, .empty);
    for (declarations, 0..) |declaration, i| {
        const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "record type is already declared", .{ .span = declarations[previous.recordIndex()].name, .message = "previous record declaration" });
        const id: typed.Type = @fromBackingInt(i + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[i] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
    }
    for (domains, 0..) |declaration, offset| {
        const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "previous type declaration" });
        const index = declarations.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
    }
    for (variant_types, 0..) |declaration, offset| {
        const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "conflicting type declaration" });
        if (declaration.cases.len == 0) return sink.fail("E_EMPTY_VARIANTS", declaration.name, "closed enum and union types require at least one variant");
        const index = declarations.len + domains.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        const cases = try allocator.alloc(typed.Variant, declaration.cases.len);
        for (declaration.cases, cases, 0..) |input, *output, tag| {
            const variant_name = src.text(input.name);
            if (catalog.field_names[index].get(variant_name)) |previous| return sink.failRelated("E_DUPLICATE_VARIANT", input.name, "variant is already declared", .{ .span = cases[previous].declaration, .message = "previous variant declaration" });
            try catalog.field_names[index].put(allocator, variant_name, tag);
            output.* = .{ .name = variant_name, .declaration = input.name, .payload = null };
        }
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{}, .variants = .{ .fallible = declaration.fallible, .is_union = declaration.is_union, .cases = cases } };
    }
    for (buffers, 0..) |declaration, offset| {
        const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "previous type declaration" });
        const index = declarations.len + domains.len + variant_types.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        try catalog.names.put(allocator, name, id);
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{}, .move_only = true };
    }
    for (resources, 0..) |declaration, offset| {
        const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
        if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", declaration.name, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "previous type declaration" });
        const index = declarations.len + domains.len + variant_types.len + buffers.len + offset;
        const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
        const kind = std.meta.stringToEnum(@import("external_resources.zig").Kind, src.text(declaration.backing)) orelse return sink.fail("E_RESOURCE_KIND", declaration.backing, "resource kind must be filesystem or network");
        try catalog.names.put(allocator, name, id);
        storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{}, .resource = kind, .move_only = true };
    }
    for (pools, 0..) |declaration, offset| {
        for ([_]Span{ declaration.name, declaration.handle }, 0..) |span, part| {
            const name = if (module_names) |names| try names.declaration(span) else src.text(span);
            if (catalog.names.get(name)) |previous| return sink.failRelated("E_DUPLICATE_TYPE", span, "type is already declared", .{ .span = storage[previous.recordIndex()].declaration, .message = "previous type declaration" });
            const index = pool_base + offset * 2 + part;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            try catalog.names.put(allocator, name, id);
            storage[index] = .{ .id = id, .name = name, .declaration = span, .fields = &.{} };
            if (part == 1) storage[index].handle_pool = storage[index - 1].id;
        }
    }
    var interned: std.AutoHashMapUnmanaged(typed.Array, typed.Type) = .empty;
    for (arrays) |syntax| {
        var enum_key: ?typed.Type = null;
        const length: usize = switch (syntax.index) {
            .length => |span| length: {
                const digits = src.text(span);
                for (digits) |c| if (!std.ascii.isDigit(c)) return sink.fail("E_ARRAY_LENGTH", span, "array length must be an unsuffixed decimal integer");
                const count = std.fmt.parseInt(usize, digits, 10) catch return sink.fail("E_ARRAY_LENGTH", span, "array length exceeds the host index range");
                if (count > std.math.maxInt(usize) / @sizeOf(typed.Value)) return sink.fail("E_ARRAY_LENGTH", span, "array value storage exceeds the host address range");
                break :length count;
            },
            .enum_type => |span| length: {
                const ty = try catalog.resolve(src, span, sink);
                if (!ty.isAggregate() or !catalog.records[ty.recordIndex()].isEnum()) return sink.fail("E_TABLE_KEY", span, "table key must be a closed enum type");
                enum_key = ty;
                break :length catalog.records[ty.recordIndex()].variants.?.cases.len;
            },
        };
        const element = try catalog.resolve(src, syntax.element, sink);
        const key: typed.Array = .{ .element = element, .length = length, .key = enum_key };
        const entry = try interned.getOrPut(allocator, key);
        if (!entry.found_existing) {
            const index = catalog.records.len;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            const name = if (enum_key) |ty| try std.fmt.allocPrint(allocator, "[{s}]{s}", .{ typed.typeName(ty, catalog.records), typed.typeName(element, catalog.records) }) else try std.fmt.allocPrint(allocator, "[{d}]{s}", .{ length, typed.typeName(element, catalog.records) });
            var fields: []const typed.Field = &.{};
            if (enum_key) |ty| {
                const entries = try allocator.alloc(typed.Field, length);
                for (catalog.records[ty.recordIndex()].variants.?.cases, entries) |variant, *field| field.* = .{ .name = variant.name, .declaration = variant.declaration, .ty = element };
                fields = entries;
            }
            storage[index] = .{ .id = id, .name = name, .declaration = syntax.span, .fields = fields, .array = key };
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
        out.* = .{ .id = @fromBackingInt(i + typed.Type.record_base), .name = out.name, .declaration = declaration.name, .fields = fields };
    }
    for (domains, 0..) |declaration, offset| {
        const backing = try catalog.resolve(src, declaration.backing, sink);
        if (!backing.isInteger() and backing != .bool) return sink.fail("E_DOMAIN_BASE", declaration.backing, "domain backing must be a built-in integer or bool");
        storage[declarations.len + offset].domain = backing;
    }
    for (variant_types, 0..) |declaration, offset| {
        const index = declarations.len + domains.len + offset;
        const cases = @constCast(storage[index].variants.?.cases);
        for (declaration.cases, cases) |input, *output| output.payload = if (input.payload) |payload| try catalog.resolve(src, payload, sink) else null;
        if (declaration.fallible) {
            if (cases.len != 2 or !catalog.field_names[index].contains("ok") or !catalog.field_names[index].contains("err")) return sink.fail("E_RESULT_SCHEMA", declaration.name, "a result declares exactly `ok: Value` and `err: Error` payload cases");
            for (cases) |case| if (case.payload == null) return sink.fail("E_RESULT_SCHEMA", case.declaration, "result cases require explicit payload types");
        }
    }
    for (buffers, 0..) |declaration, offset| {
        storage[declarations.len + domains.len + variant_types.len + offset].buffer = try catalog.resolve(src, declaration.backing, sink);
    }
    for (pools, 0..) |declaration, offset| {
        const index = pool_base + offset * 2;
        storage[index].pool = .{ .element = try catalog.resolve(src, declaration.element, sink), .handle = storage[index + 1].id };
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
            const edge_count = if (schema.variants) |v| v.cases.len else if (schema.array != null or schema.buffer != null or schema.pool != null) @as(usize, 1) else schema.fields.len;
            if (visit.next_field == edge_count) {
                var requires_handling = false;
                var move_only = schema.buffer != null or schema.resource != null or schema.pool != null;
                if (schema.variants) |variants| {
                    requires_handling = variants.fallible;
                    for (variants.cases) |case| if (case.payload) |payload| {
                        requires_handling = requires_handling or typed.requiresHandling(payload, catalog.records);
                        move_only = move_only or typed.moveOnly(payload, catalog.records);
                    };
                } else if (schema.array) |array| {
                    requires_handling = array.length != 0 and typed.requiresHandling(array.element, catalog.records);
                    move_only = array.length != 0 and typed.moveOnly(array.element, catalog.records);
                } else {
                    for (schema.fields) |field| {
                        requires_handling = requires_handling or typed.requiresHandling(field.ty, catalog.records);
                        move_only = move_only or typed.moveOnly(field.ty, catalog.records);
                    }
                }
                if (schema.buffer) |element| {
                    if (typed.moveOnly(element, catalog.records) or typed.requiresHandling(element, catalog.records)) return sink.fail("E_BUFFER_ELEMENT", schema.declaration, "buffer elements must be ordinary copyable values without result obligations");
                }
                if (schema.pool) |pool| {
                    if (typed.moveOnly(pool.element, catalog.records) or typed.requiresHandling(pool.element, catalog.records)) return sink.fail("E_POOL_ELEMENT", schema.declaration, "pool elements must be ordinary copyable values without result obligations");
                }
                catalog.records[visit.record].move_only = move_only;
                catalog.records[visit.record].requires_handling = requires_handling;
                states[visit.record] = .complete;
                _ = work.pop();
                continue;
            }
            work.items[last].next_field += 1;
            const field: typed.Field = if (schema.variants) |v| .{ .name = v.cases[visit.next_field].name, .ty = v.cases[visit.next_field].payload orelse continue, .declaration = v.cases[visit.next_field].declaration } else if (schema.array) |a| .{ .name = "element", .ty = a.element, .declaration = schema.declaration } else if (schema.buffer) |element| .{ .name = "element", .ty = element, .declaration = schema.declaration } else if (schema.pool) |pool| .{ .name = "element", .ty = pool.element, .declaration = schema.declaration } else schema.fields[visit.next_field];
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
