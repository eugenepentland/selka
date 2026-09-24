//! Checking of the `set[T]` surface (SET-1, SET-OPERATORS-1): set literals,
//! `set()`, the set methods on a named or expression receiver, and the
//! combining and comparing operators. Everything is desugared onto the
//! dictionary operations of the set's unit-valued table and the loops of
//! `set_lower.zig`; the element type must be hashable (HASH-KEYS-1).
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const buffer_operations = @import("buffer_operations.zig");
const collections = @import("collection_lower.zig");
const hashable_keys = @import("hashable_keys.zig");
const set_lower = @import("set_lower.zig");
const sema_shared = @import("sema_shared.zig");
const Error = diagnostic.Error;
const BufferKind = buffer_operations.Kind;
const eCollectionMethod = sema_shared.eCollectionMethod;
/// Diagnostic code for a set whose element type nothing determines.
const eSetInference = "E_SET_INFERENCE";
/// Diagnostic code for an operator a set does not define.
const eSetOperator = "E_SET_OPERATOR";
const eSetIndex = set_lower.index_code;

/// One set method call whose receiver and arguments are already checked: the
/// receiver expression, the local it names when it is one (for the arena
/// store check), the method and its argument nodes.
pub const SetCall = struct { span: source.Span, base: typed.NodeId, receiver: ?typed.LocalId, kind: BufferKind, arguments: []const typed.NodeId };

const impl = @This();
/// Bind set checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Check `{a, b, ...}`: the element type comes from the expected set
        /// type or the first element, and every element must match it.
        pub fn checkSetLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkSetLiteral(Checker, self, node, inputs, temporaries);
        }
        /// Check one set method with checked operands and desugar it.
        pub fn checkSetMethod(self: *Checker, call: SetCall) Error!typed.Node {
            return impl.checkSetMethod(Checker, self, call);
        }
        /// Check a set method whose operands are still unchecked syntax: each is
        /// checked against the element or the set type the method takes.
        pub fn checkSetMethodSyntax(self: *Checker, node: ast.Node, call: SetCall, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkSetMethodSyntax(Checker, self, node, call, inputs, temporaries);
        }
        /// `set()`: an empty set of the type the context expects.
        pub fn checkEmptySet(self: *Checker, span: source.Span) Error!typed.Node {
            return impl.checkEmptySet(Checker, self, span);
        }
        /// A binary operator whose left operand is a set, or null when the
        /// operator keeps its ordinary meaning (`==` and `!=`).
        pub fn checkSetBinary(self: *Checker, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!?typed.Node {
            return impl.checkSetBinary(Checker, self, op, left, right, span);
        }
        /// Require a set element type that can be hashed.
        pub fn requireSetElement(self: *Checker, element: typed.Type, span: source.Span) Error!void {
            return impl.requireSetElement(Checker, self, element, span);
        }
    };
}

fn requireSetElement(comptime Checker: type, self: *Checker, element: typed.Type, span: source.Span) Error!void {
    try hashable_keys.require(self.allocator, self.catalog.records, self.sink, element, span, true);
    if (!typed.storable(element, self.catalog.records) or typed.moveOnly(element, self.catalog.records) or self.requiresHandling(element))
        return self.sink.fail(hashable_keys.set_code, span, "set elements require copyable storable values without pending results");
}

fn checkSetLiteral(comptime Checker: type, self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const expected = self.expected_types.get(node.span);
    const expected_set = if (expected) |ty| (if (typed.setRecord(self.catalog.records, ty) != null) ty else null) else null;
    var element: ?typed.Type = if (expected_set) |ty| self.catalog.records[ty.recordIndex()].collection.key.? else null;
    const values = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, values) |input, *value| {
        if (element) |ty| try self.hint(input, ty);
        value.* = try self.expressionWithTemporaries(input, temporaries);
        const actual = self.nodes.items[@backingInt(value.*)].ty;
        if (element) |ty| try self.require(actual, ty, self.syntax.nodes.items[@backingInt(input)].span) else element = actual;
    }
    try requireSetElement(Checker, self, element.?, node.span);
    const ty = expected_set orelse try set_lower.setType(&self.catalog, element.?, node.span);
    const sets: set_lower.Builder(Checker) = .{ .b = .{ .checker = self, .span = node.span } };
    return sets.literal(ty, values);
}

fn checkEmptySet(comptime Checker: type, self: *Checker, span: source.Span) Error!typed.Node {
    const expected = self.expected_types.get(span) orelse
        return self.sink.fail(eSetInference, span, "`set()` needs an expected set type: annotate the binding, as in `seen: set[int] = set()`");
    const schema = typed.setRecord(self.catalog.records, expected) orelse
        return self.sink.fail(eSetInference, span, "`set()` builds a set, but the context expects another type");
    try requireSetElement(Checker, self, schema.collection.key.?, span);
    return .{ .span = span, .ty = expected, .data = .{ .array = &.{} } };
}

/// The operand type one set method takes: its element for `add`, `remove` and
/// `discard`, and another set of the same type for every other method.
fn operandType(schema: typed.Record, owner: typed.Type, kind: BufferKind) typed.Type {
    return switch (kind) {
        .set_add, .set_discard, .remove => schema.collection.key.?,
        else => owner,
    };
}

fn checkSetMethodSyntax(comptime Checker: type, self: *Checker, node: ast.Node, call: SetCall, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const owner = self.nodes.items[@backingInt(call.base)].ty;
    const schema = self.catalog.records[owner.recordIndex()];
    const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, arguments) |input, *argument| {
        try self.hint(input, operandType(schema, owner, call.kind));
        argument.* = try self.expressionWithTemporaries(input, temporaries);
    }
    var checked = call;
    checked.span = node.span;
    checked.arguments = arguments;
    return checkSetMethod(Checker, self, checked);
}

fn checkSetMethod(comptime Checker: type, self: *Checker, call: SetCall) Error!typed.Node {
    const owner = self.nodes.items[@backingInt(call.base)].ty;
    const schema = self.catalog.records[owner.recordIndex()];
    if (call.kind == .read or call.kind == .write) return self.sink.fail(eSetIndex, call.span, "a set is not indexable; test membership with `x in s` and add with `s.add(x)`");
    if (!buffer_operations.setMethod(call.kind)) return self.sink.fail(eCollectionMethod, call.span, try self.unknownMethodMessage(schema.collection.kind, owner));
    const names = try self.signatureNames(owner);
    if (call.arguments.len != call.kind.arity()) return self.methodArityFailure(.{ .span = call.span, .name = call.span, .kind = call.kind, .names = names, .arguments = call.arguments.len });
    for (call.arguments) |argument| {
        const actual = self.nodes.items[@backingInt(argument)].ty;
        try self.requireArgument(.{ .actual = actual, .expected = operandType(schema, owner, call.kind), .span = call.span, .kind = call.kind, .names = names });
    }
    const sets: set_lower.Builder(Checker) = .{ .b = .{ .checker = self, .span = call.span } };
    const b = sets.b;
    return switch (call.kind) {
        .set_add => added: {
            const operands = [_]typed.NodeId{ call.arguments[0], try b.node(.unit, .unit) };
            try self.requireArenaOperation(call.receiver, .write, &operands);
            break :added b.access(call.base, .write, &operands, false);
        },
        // `remove` traps with `R_MISSING_KEY` exactly as `d.pop(key)` does;
        // `discard` is the pop with a unit default, so a missing element is
        // simply absent afterwards.
        .remove => b.access(call.base, .pop_key, call.arguments, false),
        .set_discard => b.access(call.base, .pop_default, &.{ call.arguments[0], try b.node(.unit, .unit) }, false),
        .update => updated: {
            try self.requireArenaOperation(call.receiver, .update, call.arguments);
            break :updated b.access(call.base, .update, call.arguments, false);
        },
        .pop, .clear, .copy => b.access(call.base, call.kind, call.arguments, false),
        .set_union => sets.combine(.@"union", call.base, call.arguments[0]),
        .set_intersection => sets.combine(.intersection, call.base, call.arguments[0]),
        .set_difference => sets.combine(.difference, call.base, call.arguments[0]),
        .set_symmetric_difference => sets.combine(.symmetric_difference, call.base, call.arguments[0]),
        .set_subset => sets.relation(.subset, call.base, call.arguments[0]),
        .set_superset => sets.relation(.superset, call.base, call.arguments[0]),
        .set_disjoint => sets.relation(.disjoint, call.base, call.arguments[0]),
        else => error.InternalError,
    };
}

fn checkSetBinary(comptime Checker: type, self: *Checker, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!?typed.Node {
    const sets: set_lower.Builder(Checker) = .{ .b = .{ .checker = self, .span = span } };
    return switch (op) {
        .eq, .ne => null,
        .bit_or => try sets.combine(.@"union", left, right),
        .bit_and => try sets.combine(.intersection, left, right),
        .sub => try sets.combine(.difference, left, right),
        .bit_xor => try sets.combine(.symmetric_difference, left, right),
        .le => try sets.relation(.subset, left, right),
        .lt => try sets.relation(.proper_subset, left, right),
        .ge => try sets.relation(.superset, left, right),
        .gt => try sets.relation(.proper_superset, left, right),
        else => self.sink.fail(eSetOperator, span, "sets combine with `|`, `&`, `-` and `^`, compare with `<=`, `<`, `>=` and `>`, and test equality with `==`"),
    };
}
