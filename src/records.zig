//! Nominal records/domains, structural arrays, and finite by-value layout checking.
const previousTypeDeclaration = "previous type declaration";
const eDuplicateType = "E_DUPLICATE_TYPE";
const typeIsAlreadyDeclared = "type is already declared";
const generic_arrays = @import("generic_arrays.zig");
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;

const ArrayCatalog = struct {
    resolved: std.AutoHashMapUnmanaged(usize, typed.Type) = .empty,
    templates: std.AutoHashMapUnmanaged(usize, generic_arrays.Template) = .empty,
    shapes: std.AutoHashMapUnmanaged(typed.Array, typed.Type) = .empty,
    specialized: usize = 0,
};

/// Arena-owned type identities, field indexes, and resolved aggregate layouts.
pub const Catalog = struct {
    module_names: ?*Names = null,
    records: []typed.Record,
    names: std.StringHashMapUnmanaged(typed.Type),
    arrays: ArrayCatalog = .{},
    record_capacity: usize = 0,
    field_names: []std.StringHashMapUnmanaged(usize),

    /// Resolve a source type name or interned array span, diagnosing unknown types.
    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (self.arrays.resolved.get(span.start)) |ty| return ty;
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        const key = if (self.module_names) |names| try names.reference(span, .type, null, null, sink) else name;
        return self.names.get(key) orelse sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    /// Intern a specialized numeric array while retaining declaration-based element identity.
    pub fn instantiateArray(self: *Catalog, allocator: std.mem.Allocator, element: typed.Type, length: usize, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        const shape: typed.Array = .{ .element = element, .length = length };
        if (self.arrays.shapes.get(shape)) |found| return found;
        if (self.arrays.specialized == 4096) return sink.fail("E_GENERIC_LIMIT", span, "generic array specialization exceeds 4096 distinct shapes");
        const id: typed.Type = @fromBackingInt(self.records.len + typed.Type.record_base);
        const name = try std.fmt.allocPrint(allocator, "[{d}]{s}", .{ length, typed.typeName(element, self.records) });
        const schema: typed.Record = .{
            .id = id,
            .name = name,
            .declaration = span,
            .fields = &.{},
            .shape = .{ .array = shape },
            .contract = .{ .move_only = length != 0 and typed.moveOnly(element, self.records), .requires_handling = length != 0 and typed.requiresHandling(element, self.records) },
        };
        var storage: std.ArrayList(typed.Record) = .{ .items = self.records, .capacity = self.record_capacity };
        defer {
            self.records = storage.items;
            self.record_capacity = storage.capacity;
        }
        try storage.ensureUnusedCapacity(allocator, 1);
        try self.arrays.shapes.put(allocator, shape, id);
        storage.appendAssumeCapacity(schema);
        self.arrays.specialized += 1;
        return id;
    }
    /// Require a record type and return its declared field layout.
    pub fn record(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a record value");
        const schema = self.records[ty.recordIndex()];
        if (!schema.isRecord()) return sink.fail("E_TYPE", span, "operation requires a record value");
        return schema;
    }
    /// Return the record or enum-indexed table layout used by named construction.
    pub fn constructor(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Record {
        if (ty.isAggregate() and self.records[ty.recordIndex()].tableKey() != null) return self.records[ty.recordIndex()];
        return self.record(ty, span, sink);
    }
    /// Require a fixed array or table and return its element and index schema.
    pub fn array(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Array {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a fixed array value");
        return self.records[ty.recordIndex()].shape.array orelse sink.fail("E_TYPE", span, "operation requires a fixed array value");
    }
    /// Require a nominal scalar domain and return its backing scalar type.
    pub fn domain(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires a nominal scalar domain");
        return self.records[ty.recordIndex()].shape.domain orelse sink.fail("E_TYPE", span, "operation requires a nominal scalar domain");
    }
    /// Require a closed variant type and return its declared cases.
    pub fn variants(self: Catalog, ty: typed.Type, span: Span, sink: *diagnostic.Sink) Error!typed.Variants {
        if (!ty.isAggregate()) return sink.fail("E_TYPE", span, "operation requires an enum or tagged union");
        return self.records[ty.recordIndex()].shape.variants orelse sink.fail("E_TYPE", span, "operation requires an enum or tagged union");
    }
    /// Resolve a variant name to its stable case index.
    pub fn variant(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        _ = try self.variants(ty, name, sink);
        return self.field_names[ty.recordIndex()].get(src.text(name)) orelse sink.fail("E_UNKNOWN_VARIANT", name, "variant is not declared on this type");
    }
    /// Resolve a record field name to its stable field index.
    pub fn field(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        _ = try self.record(ty, name, sink);
        return self.field_names[ty.recordIndex()].get(src.text(name)) orelse sink.fail("E_UNKNOWN_FIELD", name, "field does not exist on this record type");
    }
};

/// All storage is owned by the compilation arena.
pub fn collectWithNames(allocator: std.mem.Allocator, src: Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!Catalog {
    try @import("nominal_type_syntax.zig").requireImplemented(allocator, src, program, sink, module_names);
    const declarations = program.types.records;
    const domains = program.types.domains;
    const variant_types = program.types.variants;
    const arrays = program.types.expressions.arrays;
    const buffers = program.types.buffers;
    const resources = program.types.resources;
    const pools = program.types.pools;
    const pool_base = declarations.len + domains.len + variant_types.len + buffers.len + resources.len;
    const named_count = pool_base + pools.len * 2;
    const storage = try allocator.alloc(typed.Record, named_count + arrays.len);
    var catalog: Catalog = .{ .module_names = module_names, .records = storage[0..named_count], .record_capacity = storage.len, .names = .empty, .field_names = try allocator.alloc(std.StringHashMapUnmanaged(usize), named_count) };
    @memset(catalog.field_names, .empty);
    var collector: Collector = .{ .allocator = allocator, .src = src, .program = program, .sink = sink, .catalog = &catalog, .storage = storage };
    try collector.declareNames();
    try collector.internArrays();
    try collector.resolveFields();
    try collector.validateLayouts();
    return catalog;
}

const Collector = struct {
    allocator: std.mem.Allocator,
    src: Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    catalog: *Catalog,
    storage: []typed.Record,
    fn declareNames(self: *Collector) Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        const catalog = self.catalog;
        const storage = self.storage;
        const module_names = self.catalog.module_names;
        const declarations = self.program.types.records;
        const domains = self.program.types.domains;
        const variant_types = self.program.types.variants;
        const buffers = self.program.types.buffers;
        const resources = self.program.types.resources;
        const pools = self.program.types.pools;
        const pool_base = self.program.types.records.len + self.program.types.domains.len + self.program.types.variants.len + self.program.types.buffers.len + self.program.types.resources.len;
        for (declarations, 0..) |declaration, i| {
            const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
            if (catalog.names.get(name)) |previous| return sink.failRelated(
                eDuplicateType,
                declaration.name,
                "record type is already declared",
                .{
                    .span = declarations[previous.recordIndex()].name,
                    .message = "previous record declaration",
                },
            );
            const id: typed.Type = @fromBackingInt(i + typed.Type.record_base);
            try catalog.names.put(allocator, name, id);
            storage[i] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
        }
        for (domains, 0..) |declaration, offset| {
            const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
            if (catalog.names.get(name)) |previous| return sink.failRelated(eDuplicateType, declaration.name, typeIsAlreadyDeclared, .{ .span = storage[previous.recordIndex()].declaration, .message = previousTypeDeclaration });
            const index = declarations.len + offset;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            try catalog.names.put(allocator, name, id);
            storage[index] = .{ .id = id, .name = name, .declaration = declaration.name, .fields = &.{} };
        }
        for (variant_types, 0..) |declaration, offset| {
            const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
            if (catalog.names.get(name)) |previous| return sink.failRelated(
                eDuplicateType,
                declaration.name,
                typeIsAlreadyDeclared,
                .{
                    .span = storage[previous.recordIndex()].declaration,
                    .message = "conflicting type declaration",
                },
            );
            if (declaration.cases.len == 0) return sink.fail("E_EMPTY_VARIANTS", declaration.name, "closed enum and union types require at least one variant");
            const index = declarations.len + domains.len + offset;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            try catalog.names.put(allocator, name, id);
            const cases = try allocator.alloc(typed.Variant, declaration.cases.len);
            for (declaration.cases, cases, 0..) |input, *output, tag| {
                const variant_name = src.text(input.name);
                if (catalog.field_names[index].get(variant_name)) |previous| return sink.failRelated(
                    "E_DUPLICATE_VARIANT",
                    input.name,
                    "variant is already declared",
                    .{
                        .span = cases[previous].declaration,
                        .message = "previous variant declaration",
                    },
                );
                try catalog.field_names[index].put(allocator, variant_name, tag);
                output.* = .{ .name = variant_name, .declaration = input.name, .payload = null };
            }
            storage[index] = .{
                .id = id,
                .name = name,
                .declaration = declaration.name,
                .fields = &.{},
                .shape = .{
                    .variants = .{ .fallible = declaration.fallible, .is_union = declaration.is_union, .cases = cases },
                },
            };
        }
        for (buffers, 0..) |declaration, offset| {
            const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
            if (catalog.names.get(name)) |previous| return sink.failRelated(eDuplicateType, declaration.name, typeIsAlreadyDeclared, .{ .span = storage[previous.recordIndex()].declaration, .message = previousTypeDeclaration });
            const index = declarations.len + domains.len + variant_types.len + offset;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            try catalog.names.put(allocator, name, id);
            storage[index] = .{
                .id = id,
                .name = name,
                .declaration = declaration.name,
                .fields = &.{},
                .contract = .{
                    .move_only = true,
                },
            };
        }
        for (resources, 0..) |declaration, offset| {
            const name = if (module_names) |names| try names.declaration(declaration.name) else src.text(declaration.name);
            if (catalog.names.get(name)) |previous| return sink.failRelated(eDuplicateType, declaration.name, typeIsAlreadyDeclared, .{ .span = storage[previous.recordIndex()].declaration, .message = previousTypeDeclaration });
            const index = declarations.len + domains.len + variant_types.len + buffers.len + offset;
            const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
            const kind = std.meta.stringToEnum(@import("external_resources.zig").Kind, src.text(declaration.backing)) orelse return sink.fail("E_RESOURCE_KIND", declaration.backing, "resource kind must be filesystem or network");
            try catalog.names.put(allocator, name, id);
            storage[index] = .{
                .id = id,
                .name = name,
                .declaration = declaration.name,
                .fields = &.{},
                .shape = .{
                    .resource = kind,
                },
                .contract = .{
                    .move_only = true,
                },
            };
        }
        for (pools, 0..) |declaration, offset| {
            for ([_]Span{ declaration.name, declaration.handle }, 0..) |span, part| {
                const name = if (module_names) |names| try names.declaration(span) else src.text(span);
                if (catalog.names.get(name)) |previous| return sink.failRelated(eDuplicateType, span, typeIsAlreadyDeclared, .{ .span = storage[previous.recordIndex()].declaration, .message = previousTypeDeclaration });
                const index = pool_base + offset * 2 + part;
                const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
                try catalog.names.put(allocator, name, id);
                storage[index] = .{ .id = id, .name = name, .declaration = span, .fields = &.{} };
                if (part == 1) storage[index].shape.handle_pool = storage[index - 1].id;
            }
        }
    }
    fn internArrays(self: *Collector) Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        const catalog = self.catalog;
        const storage = self.storage;
        const arrays = self.program.types.expressions.arrays;
        for (arrays) |syntax| {
            const depends = generic_arrays.parameter(src, self.program, syntax.element) or catalog.arrays.templates.contains(syntax.element.start);
            if (syntax.index == .enum_type and (depends or generic_arrays.parameter(src, self.program, syntax.index.enum_type))) return sink.fail(
                "E_GENERIC_ARRAY_KEY",
                syntax.span,
                "parameterized arrays currently require a fixed numeric length",
            );
            if (depends) {
                try catalog.arrays.templates.put(allocator, syntax.span.start, .{ .syntax = syntax, .length = try generic_arrays.length(src, syntax.index.length, sink) });
                continue;
            }
            var enum_key: ?typed.Type = null;
            const length: usize = switch (syntax.index) {
                .length => |span| try generic_arrays.length(src, span, sink),
                .enum_type => |span| length: {
                    const ty = try catalog.resolve(src, span, sink);
                    if (!ty.isAggregate() or !catalog.records[ty.recordIndex()].isEnum()) return sink.fail("E_TABLE_KEY", span, "table key must be a closed enum type");
                    enum_key = ty;
                    break :length catalog.records[ty.recordIndex()].shape.variants.?.cases.len;
                },
            };
            const element = try catalog.resolve(src, syntax.element, sink);
            const key: typed.Array = .{ .element = element, .length = length, .key = enum_key };
            const entry = try catalog.arrays.shapes.getOrPut(allocator, key);
            if (!entry.found_existing) {
                const index = catalog.records.len;
                const id: typed.Type = @fromBackingInt(index + typed.Type.record_base);
                const name = if (enum_key) |ty| try std.fmt.allocPrint(
                    allocator,
                    "[{s}]{s}",
                    .{
                        typed.typeName(ty, catalog.records),
                        typed.typeName(element, catalog.records),
                    },
                ) else try std.fmt.allocPrint(
                    allocator,
                    "[{d}]{s}",
                    .{
                        length,
                        typed.typeName(element, catalog.records),
                    },
                );
                var fields: []const typed.Field = &.{};
                if (enum_key) |ty| {
                    const entries = try allocator.alloc(typed.Field, length);
                    for (catalog.records[ty.recordIndex()].shape.variants.?.cases, entries) |variant, *field| field.* = .{ .name = variant.name, .declaration = variant.declaration, .ty = element };
                    fields = entries;
                }
                storage[index] = .{
                    .id = id,
                    .name = name,
                    .declaration = syntax.span,
                    .fields = fields,
                    .shape = .{
                        .array = key,
                    },
                };
                catalog.records = storage[0 .. index + 1];
                entry.value_ptr.* = id;
            }
            try catalog.arrays.resolved.put(allocator, syntax.span.start, entry.value_ptr.*);
        }
    }
    fn resolveFields(self: *Collector) Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        const catalog = self.catalog;
        const storage = self.storage;
        const declarations = self.program.types.records;
        const domains = self.program.types.domains;
        const variant_types = self.program.types.variants;
        const buffers = self.program.types.buffers;
        const pools = self.program.types.pools;
        const pool_base = self.program.types.records.len + self.program.types.domains.len + self.program.types.variants.len + self.program.types.buffers.len + self.program.types.resources.len;
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
            storage[declarations.len + offset].shape.domain = backing;
        }
        for (variant_types, 0..) |declaration, offset| {
            const index = declarations.len + domains.len + offset;
            const cases = @constCast(storage[index].shape.variants.?.cases);
            for (declaration.cases, cases) |input, *output| output.payload = if (input.payload) |payload| try catalog.resolve(src, payload, sink) else null;
            if (declaration.fallible) {
                const named_cases = catalog.field_names[index].contains("ok") and catalog.field_names[index].contains("err");
                if (cases.len != 2 or !named_cases) return sink.fail("E_RESULT_SCHEMA", declaration.name, "a result declares exactly `ok: Value` and `err: Error` payload cases");
                for (cases) |case| if (case.payload == null) return sink.fail("E_RESULT_SCHEMA", case.declaration, "result cases require explicit payload types");
            }
        }
        for (buffers, 0..) |declaration, offset| {
            storage[declarations.len + domains.len + variant_types.len + offset].shape.buffer = try catalog.resolve(src, declaration.backing, sink);
        }
        for (pools, 0..) |declaration, offset| {
            const index = pool_base + offset * 2;
            storage[index].shape.pool = .{ .element = try catalog.resolve(src, declaration.element, sink), .handle = storage[index + 1].id };
        }
    }
    fn finishLayout(self: *Collector, record_index: usize, schema: typed.Record) Error!void {
        const catalog = self.catalog;
        const sink = self.sink;
        var requires_handling = false;
        var move_only = schema.shape.buffer != null or schema.shape.resource != null or schema.shape.pool != null;
        if (schema.shape.variants) |variants| {
            requires_handling = variants.fallible;
            for (variants.cases) |case| if (case.payload) |payload| {
                requires_handling = requires_handling or typed.requiresHandling(payload, catalog.records);
                move_only = move_only or typed.moveOnly(payload, catalog.records);
            };
        } else if (schema.shape.array) |array| {
            requires_handling = array.length != 0 and typed.requiresHandling(array.element, catalog.records);
            move_only = array.length != 0 and typed.moveOnly(array.element, catalog.records);
        } else {
            for (schema.fields) |field| {
                requires_handling = requires_handling or typed.requiresHandling(field.ty, catalog.records);
                move_only = move_only or typed.moveOnly(field.ty, catalog.records);
            }
        }
        if (schema.shape.buffer) |element| {
            if (typed.moveOnly(element, catalog.records) or typed.requiresHandling(element, catalog.records)) return sink.fail(
                "E_BUFFER_ELEMENT",
                schema.declaration,
                "buffer elements must be ordinary copyable values without result obligations",
            );
        }
        if (schema.shape.pool) |pool| {
            if (typed.moveOnly(pool.element, catalog.records) or typed.requiresHandling(pool.element, catalog.records)) return sink.fail(
                "E_POOL_ELEMENT",
                schema.declaration,
                "pool elements must be ordinary copyable values without result obligations",
            );
        }
        catalog.records[record_index].contract.move_only = move_only;
        catalog.records[record_index].contract.requires_handling = requires_handling;
    }
    fn validateLayouts(self: *Collector) Error!void {
        const allocator = self.allocator;
        const sink = self.sink;
        const catalog = self.catalog;
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
