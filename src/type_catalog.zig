//! Shared arena-owned runtime type catalog and aggregate lookup operations.
const generic_arrays = @import("generic_arrays.zig");
const std = @import("std");
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
    template_names: std.StringHashMapUnmanaged(Span) = .empty,

    /// Resolve a source type name or interned array span, diagnosing unknown types.
    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (self.arrays.resolved.get(span.start)) |ty| return ty;
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        const key = if (self.module_names) |names| try names.reference(span, .type, null, null, sink) else name;
        if (self.template_names.contains(key)) return sink.fail("E_GENERIC_ARITY", span, "nominal template requires explicit type arguments");
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
