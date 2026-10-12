//! Ephemeral dictionary projections support immediate reads and explicit snapshots.
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

/// Extract an immediately consumed projection's mapping, preserving evaluation.
pub fn owner(comptime Checker: type, checker: *Checker, span: Span, view: typed.NodeId) Error!typed.NodeId {
    const expression = checker.nodes.items[@backingInt(view)];
    const ty = expression.ty;
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    // Constructed projections need no owner-bearing intermediate record.
    // Keep any receiver setup before the projected mapping's evaluation.
    if (expression.data == .block_value) {
        const block = expression.data.block_value;
        const mapping = try owner(Checker, checker, span, block.value);
        return b.node(checker.nodes.items[@backingInt(mapping)].ty, .{ .block_value = .{ .body = block.body, .value = mapping } });
    }
    if (expression.data == .record) return expression.data.record[0].value;
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
    if (kind == .keys or kind == .values) return b.access(mapping, if (kind == .keys) .keys else .values, &.{}, false);
    const mapping_type = checker.nodes.items[@backingInt(mapping)].ty;
    const value_type = try element(&checker.catalog, mapping_type, kind, span);
    const result_type = try collections.listType(&checker.catalog, value_type, span);
    const input = try b.local(mapping_type);
    const output = try b.local(result_type);
    const count = try b.local(.i64);
    const cursor = try b.local(.i64);
    const i = try b.read(cursor);
    const value = try copiedItem(Checker, checker, span, input, i);
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

fn copiedItem(comptime Checker: type, checker: *Checker, span: Span, mapping: typed.LocalId, position: typed.NodeId) Error!typed.NodeId {
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const key = try b.access(try b.operation(mapping, .key_at, &.{position}), .copy, &.{}, false);
    const value = try b.access(try b.operation(mapping, .value_at, &.{position}), .copy, &.{}, false);
    const item = try element(&checker.catalog, checker.locals.items[@backingInt(mapping)].ty, .items, span);
    const fields = try checker.allocator.dupe(typed.FieldInit, &.{
        .{ .index = 0, .value = try b.node(key.ty, key.data) },
        .{ .index = 1, .value = try b.node(value.ty, value.data) },
    });
    return b.node(item, .{ .record = fields });
}

/// Test membership in a directly consumed projection without allocating a snapshot.
pub fn contains(comptime Checker: type, checker: *Checker, span: Span, needle: typed.NodeId, mapping: typed.NodeId, kind: Kind, negate: bool) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    if (kind == .keys) {
        const member = try b.local(checker.nodes.items[@backingInt(needle)].ty);
        const input = try b.local(checker.nodes.items[@backingInt(mapping)].ty);
        var result = try b.operation(input, .contains, &.{try b.read(member)});
        if (negate) result = try b.node(.bool, .{ .unary = .{ .op = .not, .operand = result, .op_span = span } });
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = member, .value = needle } }),
            try b.stmt(.{ .initialize = .{ .slot = input, .value = mapping } }),
        }, result);
    }
    const member = try b.local(checker.nodes.items[@backingInt(needle)].ty);
    const input = try b.local(checker.nodes.items[@backingInt(mapping)].ty);
    const count = try b.local(.i64);
    const cursor = try b.local(.i64);
    const found = try b.local(.bool);
    const i = try b.read(cursor);
    const value = try at(Checker, checker, span, input, i, kind);
    const equal = try b.binary(.eq, try b.read(member), value, .bool);
    const loop_id = checker.loops.next;
    checker.loops.next += 1;
    const matched = try b.stmt(.{ .block = try checker.allocator.dupe(typed.StatementId, &.{
        try b.stmt(.{ .assign = .{ .slot = found, .value = try b.node(.bool, .{ .boolean = true }) } }),
        try b.stmt(.{ .loop_exit = .{ .target = loop_id, .continuing = false } }),
    }) });
    var result = try b.read(found);
    if (negate) result = try b.node(.bool, .{ .unary = .{ .op = .not, .operand = result, .op_span = span } });
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = member, .value = needle } }),
        try b.stmt(.{ .initialize = .{ .slot = input, .value = mapping } }),
        try b.stmt(.{ .initialize = .{ .slot = count, .value = try b.length(input) } }),
        try b.stmt(.{ .initialize = .{ .slot = cursor, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = found, .value = try b.node(.bool, .{ .boolean = false }) } }),
        try b.stmt(.{ .loop = .{
            .id = loop_id,
            .condition = try b.binary(.lt, i, try b.read(count), .bool),
            .body = try b.stmt(.{ .branch = .{ .condition = equal, .then_body = matched, .else_body = null } }),
            .step = try b.stmt(.{ .assign = .{ .slot = cursor, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
        } }),
    }, result);
}

/// One parsed expression's immediate consumer and certain snapshot target.
const Use = struct { direct: bool = false, snapshot: ?Span = null, inferred: ?Span = null };
/// Per-check projection context, shared by concrete and symbolic bodies.
pub const Consumers = struct {
    entries: []Use,

    /// Index immediate consumers and inferred bindings in one syntax pass.
    pub fn init(allocator: std.mem.Allocator, src: @import("source.zig").Source, program: @import("ast.zig").Program) Error!Consumers {
        const entries = try allocator.alloc(Use, program.nodes.items.len);
        @memset(entries, .{});
        for (program.statements.items) |statement| switch (statement.data) {
            .for_each => |each| entries[@backingInt(each.iterable)].direct = true,
            .binding => |binding| if (binding.annotation == null) inferred(entries, program, binding.value, binding.name),
            .assignment => |assignment| if (assignment.op == .set) inferred(entries, program, assignment.value, assignment.name),
            else => {},
        };
        for (program.nodes.items) |node| switch (node.data) {
            .length => |input| entries[@backingInt(input)].direct = true,
            .membership => |membership| entries[@backingInt(membership.container)].direct = true,
            .comprehension => |each| if (each.source == .iterable) {
                entries[@backingInt(each.source.iterable)].direct = true;
            },
            .call => |call| if (call.owner == null and call.arguments.len != 0) {
                const name = src.text(call.name);
                inline for (.{ "list", "set", "sorted" }) |consumer| if (std.mem.eql(u8, name, consumer)) {
                    entries[@backingInt(call.arguments[0])].snapshot = call.name;
                };
            },
            else => {},
        };
        return .{ .entries = entries };
    }

    /// Release this check's syntax index after both checking passes finish.
    pub fn deinit(self: Consumers, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
    }
};
fn inferred(entries: []Use, program: @import("ast.zig").Program, id: @import("ast.zig").NodeId, name: Span) void {
    entries[@backingInt(id)].inferred = name;
    const value = program.nodes.items[@backingInt(id)];
    if (value.data == .list_literal) for (value.data.list_literal) |element_id| {
        entries[@backingInt(element_id)].inferred = name;
    };
}

/// Reject a dictionary view outside a direct iteration or immediate consumer.
pub fn validateUse(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId, ty: typed.Type) Error!void {
    const kind = identify(checker.catalog, ty) orelse return;
    return validateKind(Checker, checker, id, kind);
}

/// Apply the same ephemeral-view boundary in ordinary and symbolic checking.
pub fn validateKind(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId, kind: Kind) Error!void {
    if (kind == .item or try immediateUse(Checker, checker, id)) return;
    const syntax = if (@hasField(Checker, "syntax")) checker.syntax else checker.program;
    const span = syntax.nodes.items[@backingInt(id)].span;
    const replacement = try std.fmt.allocPrint(checker.allocator, "list({s})", .{checker.src.text(span)});
    const message = try std.fmt.allocPrint(checker.allocator, "dictionary views cannot be stored or passed to functions; use {s} for an independent snapshot", .{replacement});
    if (!snapshotFixCertain(Checker, checker, id)) return checker.sink.fail("E_VIEW_STORED", span, message);
    return checker.sink.failFix("E_VIEW_STORED", span, message, .{ .span = span, .text = replacement });
}

fn immediateUse(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId) Error!bool {
    const use = checker.view_consumers.entries[@backingInt(id)];
    if (use.direct) return true;
    const call = use.snapshot orelse return false;
    const name = checker.src.text(call);
    if (checker.active.contains(name)) return false;
    if (checker.catalog.module_names) |names| {
        const kind = try names.symbolKind(call);
        return kind == null;
    }
    return !checker.functions.contains(name) and !checker.catalog.names.contains(name);
}

// Annotated fields/returns need a declaration migration. Only inferred locals
// and their list literals have a certain source-only materialization edit.
fn snapshotFixCertain(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId) bool {
    const name = checker.view_consumers.entries[@backingInt(id)].inferred orelse return false;
    return !checker.active.contains(checker.src.text(name));
}
