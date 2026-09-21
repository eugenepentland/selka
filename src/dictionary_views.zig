//! Typed dictionary views retain a mapping by value and materialize only explicitly.
const std = @import("std");
const typed = @import("typed.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const Span = @import("source.zig").Span;
const Error = @import("diagnostic.zig").Error;
const nominal = @import("nominal_catalog.zig");
const collections = @import("collection_lower.zig");
const BufferKind = @import("buffer_operations.zig").Kind;
const Symbolic = @import("symbolic_types.zig").Value;
const Shapes = @import("symbolic_shapes.zig").Context;

/// The three live dictionary projections and their value-record item.
pub const Kind = enum {
    keys,
    values,
    items,
    item,

    /// Canonical prelude type of this dictionary projection.
    pub fn name(self: Kind) []const u8 {
        return switch (self) {
            .keys => "DictKeys",
            .values => "DictValues",
            .items => "DictItems",
            .item => "DictItem",
        };
    }
};

/// Recognize a projection method without treating unrelated collection methods as views.
pub fn operation(kind: BufferKind) ?Kind {
    return switch (kind) {
        .keys => .keys,
        .values => .values,
        .items => .items,
        else => null,
    };
}

/// Recognize an injected dictionary view by declaration identity, never its display name.
pub fn identify(catalog: Catalog, ty: typed.Type) ?Kind {
    const store = catalog.templates.store orelse return null;
    const id = store.semantic(ty) orelse return null;
    const key = store.graph.nodes.items[@backingInt(id)].key;
    if (key.base != .named) return null;
    return declarationKind(catalog, key.base.named);
}

/// Resolve an injected dictionary projection from its nominal declaration.
pub fn declarationKind(catalog: Catalog, declaration: usize) ?Kind {
    const store = catalog.templates.store orelse return null;
    const name = store.index.declarations.items[declaration].builtin_name orelse return null;
    inline for (std.meta.tags(Kind)) |kind| if (std.mem.eql(u8, name, kind.name())) return kind;
    return null;
}

/// Recognize views during symbolic checking without guessing concrete type parameters.
pub fn symbolicKind(catalog: Catalog, value: Symbolic) ?Kind {
    return switch (value) {
        .concrete => |ty| identify(catalog, ty),
        .nominal => |application| declarationKind(catalog, application.declaration),
        else => null,
    };
}

/// Resolve a view's retained dictionary type in an uninstantiated template.
pub fn symbolicOwner(shapes: Shapes, view: Symbolic, span: Span) Error!Symbolic {
    return (try shapes.schema(view, span)).fields[0].ty.?;
}

/// Resolve the yielded element of a symbolic dictionary view.
pub fn symbolicElement(shapes: Shapes, mapping: Symbolic, kind: Kind, span: Span) Error!Symbolic {
    const key = try shapes.collectionKey(mapping, span);
    const value = (try shapes.container(mapping, span)).?.element;
    return switch (kind) {
        .keys => key,
        .values => value,
        .items => shapes.nominal(shapes.catalog.templates.store.?.index.names.get(Kind.item.name()).?, &.{ key, value }),
        .item => error.InternalError,
    };
}

/// Instantiate a projection or item using the mapping's concrete key and value types.
pub fn typeOf(catalog: *Catalog, mapping: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    const schema = catalog.records[mapping.recordIndex()];
    const store = catalog.templates.store orelse return error.InternalError;
    const declaration = store.index.names.get(kind.name()) orelse return error.InternalError;
    if (declarationKind(catalog.*, declaration) != kind) return store.context.sink.fail("E_TYPE", span, "dictionary view type is shadowed by a user declaration");
    return nominal.instantiateLengths(catalog, declaration, &.{ schema.collection.key.?, schema.shape.buffer.? }, &.{}, span);
}

/// Build a nonallocating view value around one already checked dictionary expression.
pub fn construct(comptime Checker: type, checker: *Checker, span: Span, mapping: typed.NodeId, kind: Kind) Error!typed.Node {
    const ty = try typeOf(&checker.catalog, checker.nodes.items[@backingInt(mapping)].ty, kind, span);
    const fields = try checker.allocator.dupe(typed.FieldInit, &.{.{ .index = 0, .value = mapping }});
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    return b.block(&.{}, try b.node(ty, .{ .record = fields }));
}

/// Extract the retained mapping from a checked live-view expression.
pub fn owner(comptime Checker: type, checker: *Checker, span: Span, view: typed.NodeId) Error!typed.NodeId {
    const ty = checker.nodes.items[@backingInt(view)].ty;
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    return b.node(checker.catalog.records[ty.recordIndex()].fields[0].ty, .{ .field = .{ .base = view, .index = 0 } });
}

/// Element type yielded by one dictionary projection.
pub fn element(catalog: *Catalog, mapping: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    return switch (kind) {
        .keys => catalog.records[mapping.recordIndex()].collection.key.?,
        .values => catalog.records[mapping.recordIndex()].shape.buffer.?,
        .items => typeOf(catalog, mapping, .item, span),
        .item => error.InternalError,
    };
}

/// Read a projected dictionary element in insertion order without constructing a snapshot.
pub fn at(comptime Checker: type, checker: *Checker, span: Span, mapping: typed.LocalId, position: typed.NodeId, kind: Kind) Error!typed.NodeId {
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const key = try b.operation(mapping, .key_at, &.{position});
    if (kind == .keys) return key;
    const value = try b.operation(mapping, .value_at, &.{position});
    if (kind == .values) return value;
    const mapping_type = checker.locals.items[@backingInt(mapping)].ty;
    const item = try typeOf(&checker.catalog, mapping_type, .item, span);
    const fields = try checker.allocator.dupe(typed.FieldInit, &.{ .{ .index = 0, .value = key }, .{ .index = 1, .value = value } });
    return b.node(item, .{ .record = fields });
}

/// Copy a view to independent list storage in one capacity-sized pass.
pub fn snapshot(comptime Checker: type, checker: *Checker, span: Span, view: typed.NodeId, kind: Kind) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const mapping = try owner(Checker, checker, span, view);
    const mapping_type = checker.nodes.items[@backingInt(mapping)].ty;
    const value_type = try element(&checker.catalog, mapping_type, kind, span);
    const result_type = try collections.listType(&checker.catalog, value_type, span);
    const input = try b.local(mapping_type);
    const output = try b.local(result_type);
    const count = try b.local(.i64);
    const cursor = try b.local(.i64);
    const i = try b.read(cursor);
    const value = try at(Checker, checker, span, input, i, kind);
    const loop_id = checker.loops.next;
    checker.loops.next += 1;
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = input, .value = mapping } }),
        try b.stmt(.{ .initialize = .{ .slot = count, .value = try b.length(input) } }),
        try b.stmt(.{ .initialize = .{ .slot = cursor, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = output, .value = try b.node(result_type, .{ .acquire_buffer = .{ .capacity = try b.read(count) } }) } }),
        try b.stmt(.{ .loop = .{
            .id = loop_id,
            .condition = try b.binary(.lt, i, try b.read(count), .bool),
            .body = try b.stmt(.{ .discard = try b.operation(output, .append, &.{value}) }),
            .step = try b.stmt(.{ .assign = .{ .slot = cursor, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
        } }),
    }, try b.read(output));
}
