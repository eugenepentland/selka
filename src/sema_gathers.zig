//! Checking of comprehensions and generator expressions that lower through their
//! own loops (`PY-GATHER-1`, `PY-GENERATOR-1`). The parser builds each one as an
//! ordinary `for` statement per clause, an `if` branch per filter, and one
//! innermost `gather_step` statement; this file checks that loop in place and
//! gives the step a destination. A list, set or dict comprehension appends,
//! adds or writes into a fresh collection. A generator expression is the
//! argument of the call that consumes it: `sum`, `any`, `all`, `min` and `max`
//! fold each value into one accumulator with no intermediate list, `any` and
//! `all` leave the loops at the first deciding value, and `sorted`, `list`,
//! `set`, `dict` and `str.join` receive the collection the loop builds. Each
//! check is a free function over the concrete checker type; `Checks` exposes the
//! ones the rest of the checker calls as `self.name(...)`.
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
pub const generator_code = diagnostic.generator;
const generator_message = "a generator expression is accepted only as the argument of sum, any, all, min, max, sorted, list, set, dict or str.join";
const generator_alternative = "build a list with a comprehension instead: `values = [x * x for x in xs]`";
const fold_code = "E_PRELUDE_TYPE";
const pairs_message = "dict() consumes a generator of (key, value) pairs";
const pairs_alternative = "or write a dict comprehension: `{k: v for k, v in pairs}`";
const sum_message = "sum requires int or float values";
const sum_alternative = "count matches with `sum(1 for x in xs if p)`";

/// What one gather builds from the values its loop produces.
pub const Use = enum {
    list,
    set,
    dict,
    sum,
    any,
    all,
    min,
    max,

    /// The use a consuming prelude call gives its generator argument, or null
    /// for a call that takes none.
    pub fn consuming(name: []const u8) ?Use {
        inline for (.{ "sum", "any", "all", "min", "max", "set", "dict" }, .{ Use.sum, .any, .all, .min, .max, .set, .dict }) |spelling, use| {
            if (std.mem.eql(u8, name, spelling)) return use;
        }
        if (std.mem.eql(u8, name, "sorted") or std.mem.eql(u8, name, "list")) return .list;
        return null;
    }
    /// Whether the use folds into one scalar instead of building a collection.
    pub fn folds(self: Use) bool {
        return switch (self) {
            .sum, .any, .all, .min, .max => true,
            else => false,
        };
    }
};

/// One active gather: what it builds, the accumulator its step created, the
/// type its context expects, and the loop depth its outermost loop starts at.
pub const Sink = struct {
    use: Use,
    span: source.Span,
    expected: ?typed.Type = null,
    result: ?typed.LocalId = null,
    /// For `min` and `max`: whether any value was seen yet.
    seen: ?typed.LocalId = null,
    depth: usize,
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
        /// return the value its step built.
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
    try self.gathers.stack.append(self.allocator, .{ .use = use, .span = node.span, .expected = self.expected_types.get(node.span), .depth = self.loops.active.items.len });
    defer _ = self.gathers.stack.pop();
    const loop = try self.statement(gather.loop);
    const sink = self.gathers.stack.items[self.gathers.stack.items.len - 1];
    const result = sink.result orelse return error.InternalError;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const result_type = self.locals.items[@backingInt(result)].ty;
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = result, .value = try initialValue(Checker, self, b, use, result_type) } }));
    if (sink.seen) |seen| try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = seen, .value = try b.node(.bool, .{ .boolean = false }) } }));
    try statements.append(self.allocator, loop.id);
    if (sink.seen) |seen| {
        // Python raises ValueError here; the language traps with its message.
        const message = if (use == .min) "min() arg is an empty sequence" else "max() arg is an empty sequence";
        try statements.append(self.allocator, try b.stmt(.{ .assertion = .{ .condition = try b.read(seen), .message = message } }));
    }
    return b.block(statements.items, try b.read(result));
}

/// The value an accumulator starts from: an empty collection, zero, or the
/// identity of `any` and `all`. `min` and `max` start from the element type's
/// zero, which the first value always replaces.
fn initialValue(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), use: Use, ty: typed.Type) Error!typed.NodeId {
    return switch (use) {
        .list => b.node(ty, .{ .acquire_buffer = .{ .capacity = try b.integer(0) } }),
        .set, .dict => b.node(ty, .{ .array = &.{} }),
        .any => b.node(.bool, .{ .boolean = false }),
        .all => b.node(.bool, .{ .boolean = true }),
        .sum, .min, .max => zero(Checker, self, b, ty),
    };
}

/// Zero of an integer, `float` or `str` type.
fn zero(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), ty: typed.Type) Error!typed.NodeId {
    if (ty.isInteger()) return b.node(ty, .{ .integer = 0 });
    if (numeric_surface.isFloat(ty, self.catalog.records)) {
        const nb = self.numericBuilder(b.span);
        return nb.append(try nb.literal("0.0", self.sink));
    }
    return b.node(ty, .{ .array = &.{} });
}

/// The value family a fold accepts: integers, floats and, for `min`/`max`, `str`.
fn foldFamily(comptime Checker: type, self: *Checker, ty: typed.Type) ?enum { integer, floating, text } {
    if (ty.isInteger()) return .integer;
    if (numeric_surface.isFloat(ty, self.catalog.records)) return .floating;
    if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].collection.kind == .string) return .text;
    return null;
}

/// Create the accumulator of the innermost gather on its first step, of `ty`.
fn accumulator(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), ty: typed.Type) Error!typed.LocalId {
    const sink = &self.gathers.stack.items[self.gathers.stack.items.len - 1];
    if (sink.result) |slot| return slot;
    const slot = try b.local(ty);
    sink.result = slot;
    return slot;
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
                const result = try accumulator(Checker, self, b, set_type);
                const sets: set_lower.Builder(Checker) = .{ .b = b };
                return .{ .block = try self.allocator.dupe(typed.StatementId, &.{try sets.add(result, value)}) };
            }
            if (!typed.storable(element, self.catalog.records) or typed.moveOnly(element, self.catalog.records) or self.requiresHandling(element))
                return self.sink.fail(collections.list_type_error, stmt.span, "list elements require copyable storable values without pending results");
            const list_type = if (expectedElement(Checker, self, sink) != null) sink.expected.? else try collections.listType(&self.catalog, element, stmt.span);
            try self.require(element, self.catalog.records[list_type.recordIndex()].shape.buffer.?, self.syntax.nodes.items[@backingInt(step.value)].span);
            const result = try accumulator(Checker, self, b, list_type);
            return .{ .discard = try b.operation(result, .append, &.{value}) };
        },
        .sum, .any, .all, .min, .max => return foldStep(Checker, self, b, sink, step),
    }
}

/// A dict comprehension's `key: value`, or a `dict(...)` generator's
/// `(key, value)` pair, written into the result.
fn dictionaryStep(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), sink: Sink, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
    const expected = if (sink.expected) |ty| (if (ty.isAggregate() and self.catalog.records[ty.recordIndex()].collection.kind == .dictionary and !self.catalog.records[ty.recordIndex()].collection.set) ty else null) else null;
    var statements: std.ArrayList(typed.StatementId) = .empty;
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
        // `dict(...)` consumes a generator of two-value tuples.
        const pair = try self.expression(step.value);
        const pair_type = self.nodes.items[@backingInt(pair)].ty;
        const tuple = record_layouts.tupleRecord(self.catalog.records, pair_type);
        if (tuple == null or tuple.?.fields.len != 2) return self.sink.failRelated(fold_code, b.span, pairs_message, .{ .span = b.span, .message = pairs_alternative, .role = .alternative });
        const slot = try b.local(pair_type);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = pair } }));
        key = try b.node(tuple.?.fields[0].ty, .{ .field = .{ .base = try b.read(slot), .index = 0 } });
        value = try b.node(tuple.?.fields[1].ty, .{ .field = .{ .base = try b.read(slot), .index = 1 } });
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
        return self.sink.fail("E_DICT_TYPE", b.span, "dictionary values require copyable storable values without pending results");
    const result = try accumulator(Checker, self, b, dict_type);
    const key_slot = try b.local(key_type);
    const value_slot = try b.local(value_type);
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = key_slot, .value = key } }));
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = value_slot, .value = value } }));
    try statements.append(self.allocator, try b.stmt(.{ .discard = try b.operation(result, .write, &.{ try b.read(key_slot), try b.read(value_slot) }) }));
    return .{ .block = try statements.toOwnedSlice(self.allocator) };
}

/// One value folded into `sum`, `any`, `all`, `min` or `max`.
fn foldStep(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), sink: Sink, step: ast.GatherStep) Error!@FieldType(typed.Statement, "data") {
    if (sink.use == .any or sink.use == .all) try self.hint(step.value, .bool);
    const value = try self.expression(step.value);
    const ty = self.nodes.items[@backingInt(value)].ty;
    const value_span = self.syntax.nodes.items[@backingInt(step.value)].span;
    switch (sink.use) {
        .any, .all => {
            if (ty != .bool) return self.sink.fail(fold_code, value_span, if (sink.use == .any) "any requires bool values" else "all requires bool values");
            const result = try accumulator(Checker, self, b, .bool);
            // The answer is decided by the first true (`any`) or false (`all`)
            // value, so leave every loop of the gather there, as Python stops.
            const decided = if (sink.use == .any) value else try b.node(.bool, .{ .unary = .{ .op = .not, .operand = value, .op_span = b.span } });
            const settle = try b.stmt(.{ .assign = .{ .slot = result, .value = try b.node(.bool, .{ .boolean = sink.use == .any }) } });
            const leave = try leaveGather(Checker, self, b, sink);
            const then_body = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ settle, leave }) });
            self.statements.items[@backingInt(then_body)].terminates = true;
            return .{ .branch = .{ .condition = decided, .then_body = then_body, .else_body = null } };
        },
        .sum => {
            const family = foldFamily(Checker, self, ty);
            if (family == null or family.? == .text) return self.sink.failRelated(fold_code, value_span, sum_message, .{ .span = value_span, .message = sum_alternative, .role = .alternative });
            const result = try accumulator(Checker, self, b, ty);
            const added = if (family.? == .floating) float: {
                const nb = self.numericBuilder(b.span);
                break :float try nb.append(try nb.binary(.add, try b.read(result), value, self.sink));
            } else try b.binary(.add, try b.read(result), value, ty);
            return .{ .assign = .{ .slot = result, .value = added } };
        },
        .min, .max => {
            const family = foldFamily(Checker, self, ty) orelse return self.sink.fail(fold_code, value_span, "min and max require int, float or str values");
            const result = try accumulator(Checker, self, b, ty);
            const seen = self.gathers.stack.items[self.gathers.stack.items.len - 1].seen orelse seen: {
                const slot = try b.local(.bool);
                self.gathers.stack.items[self.gathers.stack.items.len - 1].seen = slot;
                break :seen slot;
            };
            const candidate = try b.local(ty);
            const bind = try b.stmt(.{ .initialize = .{ .slot = candidate, .value = value } });
            const better = if (sink.use == .min)
                try less(Checker, self, b, family, try b.read(candidate), try b.read(result))
            else
                try less(Checker, self, b, family, try b.read(result), try b.read(candidate));
            const take = try b.stmt(.{ .assign = .{ .slot = result, .value = try b.read(candidate) } });
            const first = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
                take,
                try b.stmt(.{ .assign = .{ .slot = seen, .value = try b.node(.bool, .{ .boolean = true }) } }),
            }) });
            const unseen = try b.node(.bool, .{ .unary = .{ .op = .not, .operand = try b.read(seen), .op_span = b.span } });
            const replace = try b.stmt(.{ .branch = .{ .condition = better, .then_body = take, .else_body = null } });
            const choose = try b.stmt(.{ .branch = .{ .condition = unseen, .then_body = first, .else_body = replace } });
            return .{ .block = try self.allocator.dupe(typed.StatementId, &.{ bind, choose }) };
        },
        else => return error.InternalError,
    }
}

/// `left < right` for one fold family.
fn less(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), family: anytype, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    if (family == .floating) {
        const nb = self.numericBuilder(b.span);
        return nb.append(try nb.binary(.lt, left, right, self.sink));
    }
    return b.binary(.lt, left, right, .bool);
}

/// The statement that leaves the outermost loop of the gather `sink`, with
/// the cleanup a `break` there performs.
fn leaveGather(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), sink: Sink) Error!typed.StatementId {
    if (sink.depth >= self.loops.active.items.len) return error.InternalError;
    const loop = self.loops.active.items[sink.depth];
    var owned: std.ArrayList(typed.LocalId) = .empty;
    for (self.locals.items[loop.before.len..], loop.before.len..) |local, index| {
        if (typed.moveOnly(local.ty, self.catalog.records)) try owned.append(self.allocator, @fromBackingInt(index));
    }
    const id = try b.stmt(.{ .loop_exit = .{ .target = loop.id, .continuing = false } });
    self.statements.items[@backingInt(id)].terminates = true;
    self.statements.items[@backingInt(id)].owned_cleanup = try owned.toOwnedSlice(self.allocator);
    return id;
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
