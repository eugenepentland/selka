//! Shared arena-owned runtime type catalog and aggregate lookup operations.
const generic_arrays = @import("generic_arrays.zig");
const std = @import("std");
const typed = @import("typed.zig");
const prelude = @import("prelude.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;

const ArrayCatalog = struct {
    resolved: std.AutoHashMapUnmanaged(usize, typed.Type) = .empty,
    templates: std.AutoHashMapUnmanaged(usize, generic_arrays.Template) = .empty,
    shapes: std.AutoHashMapUnmanaged(typed.Array, typed.Type) = .empty,
    /// GENERIC-SITE-BUDGET-1: distinct array shapes and callback signatures
    /// each source spelling has specialized.
    sites: std.AutoHashMapUnmanaged(Site, usize) = .empty,
};
/// What a spelling specializes, and where it starts in the merged source.
const Site = struct { kind: SiteKind, start: usize };
/// The two specialization families counted per spelling.
pub const SiteKind = enum { array, callback };
/// GENERIC-SITE-BUDGET-1: the most distinct array shapes, or callback
/// signatures, one source spelling may specialize. A spelling makes a new one
/// only when a generic body is instantiated at new types, so this stops
/// polymorphic recursion through that spelling, while a program's total grows
/// with its spellings: a thousand byte literals of a thousand lengths are a
/// thousand spellings with one shape each.
pub const max_site_specializations = 4096;

/// Arena-owned type identities, field indexes, and resolved aggregate layouts.
pub const Catalog = struct {
    module_names: ?*Names = null,
    records: []typed.Record,
    names: std.StringHashMapUnmanaged(typed.Type),
    arrays: ArrayCatalog = .{},
    record_capacity: usize = 0,
    field_names: std.ArrayList(std.StringHashMapUnmanaged(usize)) = .empty,
    templates: struct {
        names: std.StringHashMapUnmanaged(Span) = .empty,
        applications: std.AutoHashMapUnmanaged(usize, *const @import("nominal_templates.zig").Application) = .empty,
        store: ?*@import("nominal_state.zig").Store = null,
    } = .{},

    /// Resolve a source type name or interned array span, diagnosing unknown types.
    pub fn resolve(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        if (self.arrays.resolved.get(span.start)) |ty| return ty;
        const name = src.text(span);
        if (typed.Type.fromName(name)) |builtin| return builtin;
        if (prelude.scalar(name)) if (self.names.get(name)) |ty| return ty;
        // A reserved capability or file spelling applies only where the project
        // resolves no declaration of that name, so a declared type always wins.
        if (self.module_names) |names| if (try names.symbolKind(span) == null) {
            if (prelude.reservedType(name)) |reserved| return reserved;
        };
        const key = if (self.module_names) |names| try names.reference(span, .type, null, null, sink) else name;
        if (self.templates.names.contains(key)) return sink.fail("E_GENERIC_ARITY", span, "nominal template requires explicit type arguments");
        if (self.names.get(key)) |declared| return declared;
        return prelude.reservedType(name) orelse sink.fail("E_UNKNOWN_TYPE", span, "type is not declared");
    }
    /// Recognize a declared variant type before interpreting a dotted member as a field.
    pub fn variantType(self: Catalog, src: Source, span: Span, sink: *diagnostic.Sink) Error!?typed.Type {
        const key = if (self.module_names) |names| qualified: {
            if (try names.symbolKind(span) != .type) return null;
            break :qualified try names.reference(span, .type, null, null, sink);
        } else src.text(span);
        const value = self.names.get(key) orelse return null;
        if (!value.isAggregate() or self.records[value.recordIndex()].shape.variants == null) return null;
        return value;
    }
    /// Retain canonical alias targets for checked public schemas; resolution may fail with SourceError or OutOfMemory.
    pub fn aliases(self: Catalog, allocator: std.mem.Allocator, src: Source, syntax: @import("ast.zig").Program, sink: *diagnostic.Sink) Error![]const typed.TypeAlias {
        const result = try allocator.alloc(typed.TypeAlias, syntax.types.expressions.aliases.len);
        errdefer allocator.free(result);
        for (syntax.types.expressions.aliases, result) |alias, *out| {
            out.* = .{
                .name = if (self.module_names) |names| try names.declaration(alias.name) else src.text(alias.name),
                .target = try self.resolve(src, alias.name, sink),
                .declaration = alias.name,
            };
        }
        return result;
    }
    /// Count one new specialization at `span`, refusing the 4097th a single
    /// spelling would make (GENERIC-SITE-BUDGET-1).
    pub fn chargeSite(self: *Catalog, allocator: std.mem.Allocator, kind: SiteKind, span: Span, sink: *diagnostic.Sink) Error!void {
        const count = try self.arrays.sites.getOrPut(allocator, .{ .kind = kind, .start = span.start });
        if (!count.found_existing) count.value_ptr.* = 0;
        if (count.value_ptr.* == max_site_specializations) return sink.fail("E_GENERIC_LIMIT", span, switch (kind) {
            .array => "generic array specialization at this spelling exceeds 4096 distinct shapes",
            .callback => "callback specialization at this spelling exceeds 4096 distinct signatures",
        });
        count.value_ptr.* += 1;
    }
    /// Intern a specialized numeric array while retaining declaration-based element identity.
    pub fn instantiateArray(self: *Catalog, allocator: std.mem.Allocator, element: typed.Type, length: usize, span: Span, sink: *diagnostic.Sink) Error!typed.Type {
        const shape: typed.Array = .{ .element = element, .length = length };
        if (self.arrays.shapes.get(shape)) |found| return found;
        try self.chargeSite(allocator, .array, span, sink);
        const id: typed.Type = @fromBackingInt(self.records.len + typed.Type.record_base);
        const name = try std.fmt.allocPrint(allocator, "[{d}]{s}", .{ length, typed.typeName(element, self.records) });
        const schema: typed.Record = .{
            .id = id,
            .name = name,
            .declaration = span,
            .fields = &.{},
            .shape = .{ .array = shape },
            .contract = .{
                .storable = length == 0 or typed.storable(element, self.records),
                .move_only = length != 0 and typed.moveOnly(element, self.records),
                .requires_handling = length != 0 and typed.requiresHandling(element, self.records),
            },
        };
        var storage: std.ArrayList(typed.Record) = .{ .items = self.records, .capacity = self.record_capacity };
        defer {
            self.records = storage.items;
            self.record_capacity = storage.capacity;
        }
        try storage.ensureUnusedCapacity(allocator, 1);
        try self.arrays.shapes.put(allocator, shape, id);
        storage.appendAssumeCapacity(schema);
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
        const members = &self.field_names.items[ty.recordIndex()];
        return members.get(src.text(name)) orelse {
            const message = try declaredMessage(sink.allocator, "variant is not declared on this type", "variants", members);
            return sink.fail("E_UNKNOWN_VARIANT", name, message);
        };
    }
    /// Resolve a record field name to its stable field index.
    pub fn field(self: Catalog, ty: typed.Type, src: Source, name: Span, sink: *diagnostic.Sink) Error!usize {
        const schema = try self.record(ty, name, sink);
        if (schema.shape.tuple) return sink.fail("E_TYPE", name, "a tuple has no fields; take it apart with `head, rest = value`");
        const members = &self.field_names.items[ty.recordIndex()];
        return members.get(src.text(name)) orelse {
            const message = try declaredMessage(sink.allocator, "field does not exist on this record type", "fields", members);
            return sink.fail("E_UNKNOWN_FIELD", name, message);
        };
    }
    /// Intern or look up the anonymous record for a tuple with these element types.
    /// Records are append-only and in compilation order, and the element list is
    /// compared in source order, so the same element list always answers the same
    /// identity: caches, fingerprints and interface rendering cannot thrash.
    pub fn tupleType(self: *Catalog, elements: []const typed.Type) Error!typed.Type {
        if (typed.internedTuple(self.records, elements)) |found| return found;
        const store = self.templates.store orelse return error.InternalError;
        const allocator = store.context.allocator;
        const fields = try allocator.alloc(typed.Field, elements.len);
        for (elements, fields, 0..) |element, *slot, index| slot.* = .{
            .name = try typed.positionalFieldName(allocator, index),
            .declaration = .{ .start = 0, .end = 0 },
            .ty = element,
        };
        const id: typed.Type = @fromBackingInt(typed.Type.record_base + self.records.len);
        const schema: typed.Record = .{
            .id = id,
            .name = try self.tupleName(allocator, elements),
            .declaration = .{ .start = 0, .end = 0 },
            .fields = fields,
            .shape = .{ .tuple = true },
            .contract = tupleContract(elements, self.records),
        };
        var storage: std.ArrayList(typed.Record) = .{ .items = self.records, .capacity = self.record_capacity };
        defer {
            self.records = storage.items;
            self.record_capacity = storage.capacity;
        }
        try storage.ensureUnusedCapacity(allocator, 1);
        storage.appendAssumeCapacity(schema);
        const indexed = self.field_names.items.len;
        try self.field_names.resize(allocator, storage.items.len);
        @memset(self.field_names.items[indexed..], .empty);
        return id;
    }
    /// Render the canonical internal spelling of a tuple type, so one element
    /// list has one name in diagnostics, interfaces and identity fingerprints.
    fn tupleName(self: Catalog, allocator: std.mem.Allocator, elements: []const typed.Type) std.mem.Allocator.Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        try out.appendSlice(allocator, "tuple<");
        for (elements, 0..) |element, index| {
            if (index != 0) try out.append(allocator, ',');
            try out.appendSlice(allocator, typed.typeName(element, self.records));
        }
        try out.append(allocator, '>');
        return out.toOwnedSlice(allocator);
    }
};

/// Ownership and result obligations of an anonymous tuple, derived from its
/// elements exactly as `record_layouts.finishLayout` derives them from fields.
fn tupleContract(elements: []const typed.Type, records: []const typed.Record) typed.RecordContract {
    var storable = true;
    var move_only = false;
    var requires_handling = false;
    for (elements) |element| {
        storable = storable and typed.storable(element, records);
        move_only = move_only or typed.moveOnly(element, records);
        requires_handling = requires_handling or typed.requiresHandling(element, records);
    }
    return .{ .storable = storable and !requires_handling, .move_only = move_only, .requires_handling = requires_handling };
}

/// Compose a diagnostic message with a sorted `; declared <label>: a, b` hint.
fn declaredMessage(allocator: std.mem.Allocator, base: []const u8, label: []const u8, members: *const std.StringHashMapUnmanaged(usize)) Error![]const u8 {
    const names = try allocator.alloc([]const u8, members.count());
    defer allocator.free(names);
    var count: usize = 0;
    var iterator = members.iterator();
    while (iterator.next()) |entry| : (count += 1) names[count] = entry.key_ptr.*;
    std.mem.sort([]const u8, names, {}, nameLessThan);
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(allocator);
    for (names[0..count], 0..) |name, index| {
        if (index != 0) try joined.appendSlice(allocator, ", ");
        try joined.appendSlice(allocator, name);
    }
    return std.fmt.allocPrint(allocator, "{s}; declared {s}: {s}", .{ base, label, joined.items });
}
fn nameLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
