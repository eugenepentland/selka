//! Typed recognition of retired comprehensions and generator arguments.
//! Their loops still establish bindings, expected types and ownership facts for
//! certain source repairs. Rejected forms produce no executable Core value.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");
const numeric_surface = @import("numeric_surface.zig");
const record_layouts = @import("record_layouts.zig");
const set_lower = @import("set_lower.zig");
const hashable_keys = @import("hashable_keys.zig");
const Error = diagnostic.Error;
const impl = @This();

/// The diagnostic a generator expression outside a consuming call reports.
pub const generator_code = @import("gather_use.zig").generator_code;
const generator_message = "generator arguments were removed; use a typed accumulator and an explicit loop";
const generator_alternative = "declare a typed accumulator, iterate the source and append or fold each value";
const fold_code = "E_PRELUDE_TYPE";
const pairs_message = "dict() consumes a generator of (key, value) pairs";
const pairs_alternative = "build the dictionary with an explicit loop that assigns each key: `d[k] = v`";
const sum_message = "sum requires int or float values";
const sum_alternative = "count matches with an explicit loop: `mut count = 0`, then `for x in xs:`, `if p:`, `count = count + 1`";

/// The value family a former comprehension or consuming generator builds.
pub const Use = @import("gather_use.zig").Use;

/// One active gather and the expected and inferred accumulator types.
pub const Sink = struct {
    use: Use,
    expected: ?typed.Type = null,
    result: ?typed.Type = null,
};

/// Per-checker gather state: the stack of gathers being checked, innermost
/// last, and the use each consuming call gave its generator argument, keyed by
/// that argument's span.
pub const State = struct {
    stack: std.ArrayList(Sink) = .empty,
    uses: std.AutoHashMapUnmanaged(source.Span, Use) = .empty,
};

/// Bind gather checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// PY-GATHER-1: check a comprehension or generator expression's loop and
        /// retain its inferred type and publish a removal diagnostic.
        pub fn checkGather(self: *Checker, node: ast.Node, gather: ast.Gather) Error!typed.Node {
            return impl.checkGather(Checker, self, node, gather);
        }
        /// Check the innermost step of the gather being checked.
        pub fn statementGatherStep(self: *Checker, stmt: ast.Statement, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
            return impl.statementGatherStep(Checker, self, stmt, step);
        }
        /// PY-GENERATOR-1: record that the generator expression `id`, if it is
        /// one, is consumed as `use`; answer whether it was one.
        pub fn consumeGenerator(self: *Checker, id: ast.NodeId, use: Use) Error!bool {
            const node = self.syntax.nodes.items[@backingInt(id)];
            if (node.data != .gather or node.data.gather.shape != .generator) return false;
            try self.gathers.uses.put(self.allocator, node.span, use);
            return true;
        }
        /// Whether the checked argument `id` is a generator its call folded already.
        pub fn foldedGenerator(self: *Checker, id: ast.NodeId) bool {
            const node = self.syntax.nodes.items[@backingInt(id)];
            if (node.data != .gather or node.data.gather.shape != .generator) return false;
            const use = self.gathers.uses.get(node.span) orelse return false;
            return use.folds() or use == .set or use == .dict;
        }
    };
}

fn checkGather(comptime Checker: type, self: *Checker, node: ast.Node, gather: ast.Gather) Error!typed.Node {
    const use: Use = switch (gather.shape) {
        .list => .list,
        .set => .set,
        .dict => .dict,
        .generator => self.gathers.uses.get(node.span) orelse
            return self.sink.failRelated(generator_code, node.span, generator_message, .{ .span = node.span, .message = generator_alternative, .role = .alternative }),
    };
    try self.gathers.stack.append(self.allocator, .{ .use = use, .expected = self.expected_types.get(node.span) });
    defer _ = self.gathers.stack.pop();
    const loop = try self.statement(gather.loop);
    const sink = self.gathers.stack.items[self.gathers.stack.items.len - 1];
    const result_type = sink.result orelse return error.InternalError;
    try @import("comprehension_migration.zig").publish(Checker, self, node, gather, use, result_type);
    _ = loop;
    // Recognition retains the inferred type; rejected syntax has no executable Core.
    return .{ .span = node.span, .ty = result_type, .data = .unit };
}

/// The value family a fold accepts: integers, floats and, for `min`/`max`, `str`.
fn foldFamily(comptime Checker: type, self: *Checker, ty: typed.Type) ?enum { integer, floating, text } {
    if (ty.isInteger()) return .integer;
    if (numeric_surface.isFloat(ty, self.catalog.records)) return .floating;
    if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].collection.kind == .string) return .text;
    return null;
}

/// Retain the inferred accumulator type without allocating executable state.
fn accumulator(comptime Checker: type, self: *Checker, ty: typed.Type) void {
    const sink = &self.gathers.stack.items[self.gathers.stack.items.len - 1];
    if (sink.result == null) sink.result = ty;
}

/// The element type the context expects of a list or set gather, if any.
fn expectedElement(comptime Checker: type, self: *Checker, sink: Sink) ?typed.Type {
    const expected = sink.expected orelse return null;
    if (!expected.isAggregate()) return null;
    const schema = self.catalog.records[expected.recordIndex()];
    if (sink.use == .set) return if (schema.collection.set) schema.collection.key else null;
    if (sink.use == .list) return if (schema.isCollection() and schema.collection.kind == .list) schema.shape.buffer else null;
    return null;
}

fn statementGatherStep(comptime Checker: type, self: *Checker, stmt: ast.Statement, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
    if (self.gathers.stack.items.len == 0) return error.InternalError;
    const sink = self.gathers.stack.items[self.gathers.stack.items.len - 1];
    const b: collections.Builder(Checker) = .{ .checker = self, .span = stmt.span };
    switch (sink.use) {
        .dict => return dictionaryStep(Checker, self, b, sink, step),
        .list, .set => {
            if (expectedElement(Checker, self, sink)) |element| try self.hint(step.value, element);
            const value = try self.expression(step.value);
            const element = self.nodes.items[@backingInt(value)].ty;
            if (sink.use == .set) {
                // A set gathers into the unit-valued table of `set[T]` (SET-1),
                // so its elements must be hashable (HASH-KEYS-1).
                try self.requireSetElement(element, stmt.span);
                const set_type = if (expectedElement(Checker, self, sink) != null) sink.expected.? else try set_lower.setType(&self.catalog, element, stmt.span);
                try self.require(element, self.catalog.records[set_type.recordIndex()].collection.key.?, self.syntax.nodes.items[@backingInt(step.value)].span);
                accumulator(Checker, self, set_type);
                return .{ .block = &.{} };
            }
            if (!typed.storable(element, self.catalog.records) or typed.moveOnly(element, self.catalog.records))
                return self.sink.failOwnership(.{ .code = collections.list_type_error, .rule = .T4 }, stmt.span, "list elements require storable values without owned resources");
            const list_type = if (expectedElement(Checker, self, sink) != null) sink.expected.? else try collections.listType(&self.catalog, element, stmt.span);
            try self.require(element, self.catalog.records[list_type.recordIndex()].shape.buffer.?, self.syntax.nodes.items[@backingInt(step.value)].span);
            accumulator(Checker, self, list_type);
            return .{ .block = &.{} };
        },
        .sum, .any, .all, .min, .max => return foldStep(Checker, self, sink, step),
    }
}

/// Type a dict comprehension entry or a generator's key/value pair.
fn dictionaryStep(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), sink: Sink, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
    const expected = if (sink.expected) |ty| (if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].collection.kind == .dictionary and !self.catalog.records[ty.recordIndex()].collection.set) ty else null) else null;
    var key: typed.NodeId = undefined;
    var value: typed.NodeId = undefined;
    if (step.key) |key_syntax| {
        if (expected) |ty| {
            try self.hint(key_syntax, self.catalog.records[ty.recordIndex()].collection.key.?);
            try self.hint(step.value, self.catalog.records[ty.recordIndex()].shape.buffer.?);
        }
        key = try self.expression(key_syntax);
        value = try self.expression(step.value);
    } else {
        const pair = try self.expression(step.value);
        const pair_type = self.nodes.items[@backingInt(pair)].ty;
        const tuple = record_layouts.tupleRecord(self.catalog.records, pair_type);
        if (tuple == null or tuple.?.fields.len != 2) return self.sink.failRelated(fold_code, b.span, pairs_message, .{ .span = b.span, .message = pairs_alternative, .role = .alternative });
        key = try b.node(tuple.?.fields[0].ty, .unit);
        value = try b.node(tuple.?.fields[1].ty, .unit);
    }
    const key_type = self.nodes.items[@backingInt(key)].ty;
    const value_type = self.nodes.items[@backingInt(value)].ty;
    const dict_type = expected orelse dict: {
        const state = self.catalog.templates.store orelse return error.InternalError;
        break :dict try @import("nominal_catalog.zig").instantiateLengths(&self.catalog, state.index.names.get("dict").?, &.{ key_type, value_type }, &.{}, b.span);
    };
    const schema = self.catalog.records[dict_type.recordIndex()];
    try hashable_keys.require(self.allocator, self.catalog.records, self.sink, key_type, b.span, false);
    try self.require(key_type, schema.collection.key.?, b.span);
    try self.require(value_type, schema.shape.buffer.?, b.span);
    if (!typed.storable(value_type, self.catalog.records) or typed.moveOnly(value_type, self.catalog.records) or self.requiresHandling(value_type))
        return self.sink.failOwnership(.{ .code = "E_DICT_TYPE", .rule = .T4 }, b.span, "dictionary values require copyable storable values without pending results");
    accumulator(Checker, self, dict_type);
    return .{ .block = &.{} };
}

/// One value folded into `sum`, `any`, `all`, `min` or `max`.
fn foldStep(comptime Checker: type, self: *Checker, sink: Sink, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
    if (sink.use == .any or sink.use == .all) try self.hint(step.value, .bool);
    const value = try self.expression(step.value);
    const ty = self.nodes.items[@backingInt(value)].ty;
    const value_span = self.syntax.nodes.items[@backingInt(step.value)].span;
    switch (sink.use) {
        .any, .all => if (ty != .bool) {
            return self.sink.fail(fold_code, value_span, if (sink.use == .any) "any requires bool values" else "all requires bool values");
        },
        .sum => {
            const family = foldFamily(Checker, self, ty);
            if (family == null or family.? == .text) return self.sink.failRelated(fold_code, value_span, sum_message, .{ .span = value_span, .message = sum_alternative, .role = .alternative });
        },
        .min, .max => if (foldFamily(Checker, self, ty) == null) {
            return self.sink.fail(fold_code, value_span, "min and max require int, float or str values");
        },
        else => return error.InternalError,
    }
    accumulator(Checker, self, ty);
    return .{ .block = &.{} };
}

// spec: PY-GENERATOR-1
test "a consuming prelude call names the use its generator argument gets" {
    try std.testing.expectEqual(Use.sum, Use.consuming("sum").?);
    try std.testing.expectEqual(Use.list, Use.consuming("sorted").?);
    try std.testing.expectEqual(Use.dict, Use.consuming("dict").?);
    try std.testing.expect(Use.consuming("len") == null);
    try std.testing.expect(Use.max.folds());
    try std.testing.expect(!Use.set.folds());
}
