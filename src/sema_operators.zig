//! Checking of operators and operator-like expressions: unary and binary
//! arithmetic on integers and floats, comparisons and text operators, table,
//! dictionary and text literals, conditional expressions, membership tests and
//! indexing. Each check is a free function over the concrete checker type;
//! `Checks` exposes the ones the rest of the checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eCellEquality = sema_shared.eCellEquality;
const eOptionTest = sema_shared.eOptionTest;
const std = @import("std");
const hashable_keys = @import("hashable_keys.zig");
const set_lower = @import("set_lower.zig");
const eSetIndex = set_lower.index_code;
const set_index_message = "a set is not indexable; test membership with `x in s` or iterate it with `for x in s`";
const ast = @import("ast.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const arrays = @import("array_literals.zig");
const idioms = @import("sema_idioms.zig");
/// Whether a type is either managed byte kind — the immutable byte string or the
/// mutable octet buffer. The two hold the same one-octet elements and compare
/// content the same way, so one comparison may name both.
fn isByteKind(schemas: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and schemas[ty.recordIndex()].collection.kind == .bytes;
}
/// The accepted spelling beside a rejected tuple index, which is the only way
/// to reach a tuple's values.
const tuple_index_alternative = "a tuple has no elements to index; bind its values with `head, rest = ...`";
/// The two checked operands of a binary numeric operator.
const NumericOperands = struct { left: typed.NodeId, right: typed.NodeId };
const impl = @This();
/// Bind operator checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Byte membership accepts either a byte scalar, widened to int, or a whole subsequence.
        pub fn byteMembership(self: *Checker, span: source.Span, needle: *typed.NodeId, container_type: typed.Type) Error!typed.Type {
            return impl.byteMembership(Checker, self, span, needle, container_type);
        }
        /// Append one `u8` literal node per byte and return their ids, for byte literals
        /// expanded into element lists.
        pub fn byteValues(self: *Checker, bytes: []const u8, span: source.Span) Error![]const typed.NodeId {
            return impl.byteValues(Checker, self, bytes, span);
        }
        /// `value_if_true if condition else value_if_false`. Both arms are checked
        /// against the contextual expected type when there is one and must agree
        /// otherwise, and the result is desugared to an if/else that assigns a fresh
        /// temporary: only the chosen arm runs, while definite assignment, option
        /// narrowing, effect, origin and ownership analysis see the two-branch
        /// statement they already understand.
        pub fn checkConditional(self: *Checker, node: ast.Node, conditional: @FieldType(@FieldType(ast.Node, "data"), "conditional")) Error!typed.Node {
            return impl.checkConditional(Checker, self, node, conditional);
        }
        /// Check a dictionary literal against its expected type, or infer key and value
        /// types from the first entry; a context that demands a table builds a table.
        pub fn checkDictionaryLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId, out: *typed.Node) Error!void {
            return impl.checkDictionaryLiteral(Checker, self, node, entries, out);
        }
        /// Check `needle in container` on a list, dictionary or text, comparing by the
        /// container's element or key type.
        pub fn checkMembership(self: *Checker, node: ast.Node, membership: @FieldType(@FieldType(ast.Node, "data"), "membership"), temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkMembership(Checker, self, node, membership, temporaries);
        }
        /// Type a text or byte-string literal as `str`, `bytes`, or the byte array its context
        /// expects, expanding bytes into element nodes where needed.
        pub fn checkTextLiteral(self: *Checker, node: ast.Node, bytes: []const u8, out: *typed.Node) Error!void {
            return impl.checkTextLiteral(Checker, self, node, bytes, out);
        }
        /// Check a unary operator: `is None` on an Option, negation, `not`, and the float
        /// intrinsics on their operand.
        pub fn checkUnary(self: *Checker, node: ast.Node, u: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!typed.Node {
            return impl.checkUnary(Checker, self, node, u);
        }
        /// Check a binary operator on checked operands: numeric arithmetic and comparison,
        /// text concatenation and repetition, and aggregate equality.
        pub fn checkValueBinary(self: *Checker, b: @FieldType(@FieldType(ast.Node, "data"), "binary"), out: *typed.Node) Error!void {
            return impl.checkValueBinary(Checker, self, b, out);
        }
        /// Type one binary operator over two already checked operands, promoting
        /// an integer operand of a float operation and answering the operator's node.
        pub fn binaryValue(self: *Checker, b: idioms.CheckedBinary, out: *typed.Node) Error!void {
            return impl.binaryValue(Checker, self, b, out);
        }
        /// Check `value[index]` on a list, dictionary, text, bytes, tuple or fixed array.
        pub fn checkValueIndex(self: *Checker, node: ast.Node, access: @FieldType(@FieldType(ast.Node, "data"), "index"), out: *typed.Node) Error!void {
            return impl.checkValueIndex(Checker, self, node, access, out);
        }
    };
}
/// Append one `u8` literal node per byte and return their ids, for byte literals
/// expanded into element lists.
fn byteValues(comptime Checker: type, self: *Checker, bytes: []const u8, span: source.Span) Error![]const typed.NodeId {
    const values = try self.allocator.alloc(typed.NodeId, bytes.len);
    for (bytes, values) |byte, *value| {
        value.* = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = span, .ty = .u8, .data = .{ .integer = byte } });
    }
    return values;
}
fn numericOperands(comptime Checker: type, self: *Checker, operation: idioms.CheckedBinary) Error!NumericOperands {
    var left = operation.left;
    var right = operation.right;
    const lt = self.nodes.items[@backingInt(left)].ty;
    const rt = self.nodes.items[@backingInt(right)].ty;
    const promote = operation.op == .python_div or numeric_surface.isFloat(lt, self.catalog.records) or numeric_surface.isFloat(rt, self.catalog.records);
    if (promote) {
        const builder = self.numericBuilder(operation.op_span);
        if (lt.isInteger()) left = try builder.append(try builder.fromInteger(left));
        if (rt.isInteger()) right = try builder.append(try builder.fromInteger(right));
    }
    return .{ .left = left, .right = right };
}
fn checkUnary(comptime Checker: type, self: *Checker, node: ast.Node, u: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!typed.Node {
    var out: typed.Node = undefined;
    out.span = node.span;
    const operand = self.resolved[@backingInt(u.operand)].?;
    const operand_ty = self.nodes.items[@backingInt(operand)].ty;
    if (u.op == .is_none) {
        const shape = prelude.optionShape(operand_ty, self.catalog.records) orelse return self.sink.fail(eOptionTest, u.op_span, "is None requires an Option value");
        if (self.transfers(operand_ty)) return self.sink.fail(eOptionTest, u.op_span, "use match for an Option carrying an owned value or checked Result");
        return option_flow.testValue(self, operand, shape, node.span);
    }
    out.ty = if (u.op == .not) .bool else operand_ty;
    if (u.op == .neg and numeric_surface.isFloat(out.ty, self.catalog.records)) return self.numericBuilder(node.span).negate(operand);
    // A `float` operand is the binary64 value itself, so the float-in/float-out
    // `f64_*` operations answer a float instead of demanding a bit pattern.
    if (@import("float_intrinsics.zig").floatwise(u.op) and numeric_surface.isFloat(operand_ty, self.catalog.records)) {
        return self.numericBuilder(u.op_span).unary(std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, operand);
    }
    if (u.op == .neg) try self.requireInteger(out.ty, u.op_span) else try self.require(operand_ty, if (u.op == .not) .bool else .u64, u.op_span);
    out.data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } };
    return out;
}
/// Build an enum-indexed table from a dict literal whose context already demands `[Kind]T`.
fn checkTableLiteral(comptime Checker: type, self: *Checker, node: ast.Node, entries: []const ast.NodeId, expected: typed.Type, out: *typed.Node) Error!void {
    const key = arrays.table(self.catalog, expected).?;
    const context: arrays.Context = .{ .src = self.src, .syntax = self.syntax, .catalog = self.catalog, .key = key };
    const named = try arrays.initializers(self.allocator, context, entries, self.sink);
    out.ty = expected;
    out.data = .{ .record = try self.fields(expected, named, true, node.span) };
}
fn checkDictionaryLiteral(comptime Checker: type, self: *Checker, node: ast.Node, entries: []const ast.NodeId, out: *typed.Node) Error!void {
    const expected = self.expected_types.get(node.span);
    if (expected) |ty_value| if (arrays.table(self.catalog, ty_value) != null) return checkTableLiteral(Checker, self, node, entries, ty_value, out);
    if (expected) |expected_type| {
        out.ty = expected_type;
    } else {
        if (entries.len == 0) return self.sink.fail("E_DICT_INFERENCE", node.span, "empty dictionary requires a dict key/value annotation");
        const state = self.catalog.templates.store orelse return error.InternalError;
        const key = self.nodes.items[@backingInt(self.resolved[@backingInt(entries[0])].?)].ty;
        const value = self.nodes.items[@backingInt(self.resolved[@backingInt(entries[1])].?)].ty;
        out.ty = try nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("dict").?, &.{ key, value }, &.{}, node.span);
    }
    if (!out.ty.isAggregate() or self.catalog.records[out.ty.recordIndex()].collection.kind != .dictionary) return self.sink.fail("E_DICT_TYPE", node.span, "dictionary literal requires dict key/value types");
    if (typed.isSet(self.catalog.records[out.ty.recordIndex()])) return self.sink.fail("E_DICT_TYPE", node.span, "`{}` is an empty dict; write `set()` for an empty set, as Python does");
    const schema = self.catalog.records[out.ty.recordIndex()];
    const key = schema.collection.key.?;
    try hashable_keys.require(self.allocator, self.catalog.records, self.sink, key, node.span, typed.isSet(schema));
    const items = try self.allocator.alloc(typed.NodeId, entries.len);
    for (entries, items, 0..) |entry, *item, index| {
        item.* = self.resolved[@backingInt(entry)].?;
        try self.require(self.nodes.items[@backingInt(item.*)].ty, if (index % 2 == 0) key else schema.shape.buffer.?, self.syntax.nodes.items[@backingInt(entry)].span);
    }
    out.data = .{ .array = items };
}
/// A `b"..."` literal is always the managed bytes type; plain text keeps its array form.
fn byteLiteralType(comptime Checker: type, self: *Checker, node: ast.Node) Error!typed.Type {
    const spelling = self.src.text(node.span);
    if (spelling.len == 0 or spelling[0] != 'b') return self.ty(node.span);
    return collections.preludeType(&self.catalog, "bytes", node.span);
}
fn checkTextLiteral(comptime Checker: type, self: *Checker, node: ast.Node, bytes: []const u8, out: *typed.Node) Error!void {
    out.ty = if (node.data == .text) try self.ty(node.span) else self.expected_types.get(node.span) orelse try byteLiteralType(Checker, self, node);
    if (out.ty.isAggregate() and self.catalog.records[out.ty.recordIndex()].collection.kind == .bytes) {
        out.data = .{ .array = try byteValues(Checker, self, bytes, node.span) };
        return;
    }
    if (out.ty.isAggregate() and self.catalog.records[out.ty.recordIndex()].collection.kind == .string) {
        const view = std.unicode.Utf8View.init(bytes) catch return self.sink.fail("E_TEXT_UTF8", node.span, "str literals require valid UTF-8");
        var iterator = view.iterator();
        var points: std.ArrayList(typed.NodeId) = .empty;
        while (iterator.nextCodepoint()) |point| {
            const id: typed.NodeId = @fromBackingInt(@intCast(self.nodes.items.len));
            try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .u32, .data = .{ .integer = point } });
            try points.append(self.allocator, id);
        }
        out.data = .{ .array = try points.toOwnedSlice(self.allocator) };
    } else {
        out.ty = try self.ty(node.span);
        out.data = .{ .array = try byteValues(Checker, self, bytes, node.span) };
    }
}
fn checkFloatBinary(comptime Checker: type, self: *Checker, span: source.Span, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId) Error!typed.Node {
    const builder: collections.Builder(Checker) = .{ .checker = self, .span = span };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    var values: [2]typed.NodeId = undefined;
    for ([_]typed.NodeId{ left, right }, &values) |input, *value| {
        const slot = try builder.local(self.nodes.items[@backingInt(input)].ty);
        try statements.append(self.allocator, try builder.stmt(.{ .initialize = .{ .slot = slot, .value = input } }));
        value.* = try builder.read(slot);
    }
    const result = try self.numericBuilder(span).binary(op, values[0], values[1], self.sink);
    return builder.block(statements.items, try builder.node(result.ty, result.data));
}
fn checkValueBinary(comptime Checker: type, self: *Checker, syntax: @FieldType(@FieldType(ast.Node, "data"), "binary"), out: *typed.Node) Error!void {
    // PY-CHAIN-1: a chained comparison checks its own operands in order.
    if (syntax.chained) {
        out.* = try self.checkChain(.{ .span = out.span, .data = .{ .binary = syntax } });
        return;
    }
    return binaryValue(Checker, self, .{
        .op = syntax.op,
        .op_span = syntax.op_span,
        .left = self.resolved[@backingInt(syntax.left)].?,
        .right = self.resolved[@backingInt(syntax.right)].?,
    }, out);
}
fn binaryValue(comptime Checker: type, self: *Checker, b: idioms.CheckedBinary, out: *typed.Node) Error!void {
    if (try self.idiomBinary(b, out)) return;
    const operands = try numericOperands(Checker, self, b);
    const left = operands.left;
    const right = operands.right;
    const lt = self.nodes.items[@backingInt(left)].ty;
    const rt = self.nodes.items[@backingInt(right)].ty;
    // Equality of the two byte kinds is content equality of the same octets,
    // so a byte string and an octet buffer compare without a conversion;
    // every other operator still requires one type on both sides.
    const mixed_bytes = (b.op == .eq or b.op == .ne) and isByteKind(self.catalog.records, lt) and isByteKind(self.catalog.records, rt);
    // `|`, `&` and `^` are the set operators (SET-OPERATORS-1) and, on two
    // integers, the bitwise operators (PY-SET-OPS-1); any other operand is refused.
    const set_left = typed.setRecord(self.catalog.records, lt) != null;
    if (!set_left and !lt.isInteger()) if (set_lower.bitwiseSpelling(self.src.text(b.op_span))) |builtin| {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` combines two sets or two integers (`{s}(a, b)`)", .{ self.src.text(b.op_span), builtin });
        return self.sink.fail(set_lower.bitwise_code, b.op_span, message);
    };
    if (!mixed_bytes) try self.require(rt, lt, b.op_span);
    if (set_left) if (try self.checkSetBinary(b.op, left, right, b.op_span)) |combined| {
        out.* = combined;
        return;
    };
    if ((b.op == .eq or b.op == .ne) and self.requiresCellEquality(lt))
        return self.sink.fail(eCellEquality, b.op_span, "Cell equality is not defined, including inside collections");
    if (numeric_surface.isFloat(lt, self.catalog.records)) {
        out.* = try checkFloatBinary(Checker, self, out.span, b.op, left, right);
        return;
    }
    const text_operands = lt.isAggregate() and self.catalog.records[lt.recordIndex()].isCollection();
    if (text_operands) {
        const sequence = self.catalog.records[lt.recordIndex()].collection.kind;
        const concatenation = b.op == .add and (sequence == .string or sequence == .bytes);
        // PY-TEXT-ORDER-1: str orders by code point and bytes by octet, as Python does.
        const ordering = idioms.textOrdering(b.op) and (sequence == .string or sequence == .bytes);
        const accepted = concatenation or ordering or b.op == .eq or b.op == .ne;
        if (!accepted) return self.sink.fail("E_TEXT_OPERATOR", b.op_span, "managed collections support equality; str and bytes also support `+` and `<`, `<=`, `>`, `>=`");
        out.ty = if (b.op == .add) lt else .bool;
    } else switch (b.op) {
        .f64_eq, .f64_lt, .f64_le => {
            try self.require(lt, .u64, b.op_span);
            out.ty = .bool;
        },
        .f64_add, .f64_sub, .f64_mul, .f64_div => {
            try self.require(lt, .u64, b.op_span);
            out.ty = .u64;
        },
        .logical_and, .logical_or => {
            try self.require(lt, .bool, b.op_span);
            out.ty = .bool;
        },
        .eq, .ne => {
            if (!typed.supportsEquality(lt, self.catalog.records)) return self.sink.fail("E_TYPE", b.op_span, "aggregate equality is not defined; compare the relevant elements explicitly");
            out.ty = .bool;
        },
        .lt, .le, .gt, .ge => {
            try self.requireInteger(lt, b.op_span);
            out.ty = .bool;
        },
        else => {
            try self.requireInteger(lt, b.op_span);
            out.ty = lt;
        },
    }
    out.data = .{ .binary = .{
        .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(b.op)).?,
        .left = left,
        .right = right,
        .op_span = b.op_span,
    } };
}
/// `value_if_true if condition else value_if_false`. Both arms are checked
/// against the contextual expected type when there is one and must agree
/// otherwise, and the result is desugared to an if/else that assigns a fresh
/// temporary: only the chosen arm runs, while definite assignment, option
/// narrowing, effect, origin and ownership analysis see the two-branch
/// statement they already understand.
fn checkConditional(comptime Checker: type, self: *Checker, node: ast.Node, conditional: @FieldType(@FieldType(ast.Node, "data"), "conditional")) Error!typed.Node {
    const condition = try self.expressionExpected(conditional.condition, .bool);
    try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(conditional.condition)].span);
    const expected = self.expected_types.get(node.span);
    const before = try self.pendingState(self.locals.items.len);
    const init_before = try self.initSnapshot();
    const facts_before = try self.option_facts.snapshot(self.allocator);
    try self.assumeOption(conditional.condition, true);
    const then_value = try conditionalArm(Checker, self, conditional.then_value, expected);
    const facts_then = try self.option_facts.snapshot(self.allocator);
    const then_state = try self.pendingState(before.len);
    const init_then = try self.initSnapshot();
    self.restorePending(before);
    self.initRestore(init_before);
    self.option_facts.restore(facts_before);
    try self.assumeOption(conditional.condition, false);
    const else_value = try conditionalArm(Checker, self, conditional.else_value, expected orelse self.nodes.items[@backingInt(then_value)].ty);
    try requireConditionalArms(Checker, self, expected, then_value, else_value);
    // Both arms continue, so the facts and ownership state they agree on
    // survive the expression exactly as they survive an `if`/`else`.
    self.option_facts.intersect(facts_then);
    self.initIntersect(init_then);
    try self.samePending(then_state, node.span, eResultPath);
    self.restorePending(then_state);
    const value_type = expected orelse self.nodes.items[@backingInt(then_value)].ty;
    return conditionalValue(Checker, self, node, condition, then_value, else_value, value_type);
}
/// One conditional arm, checked against the expected result type when the
/// context supplies one and on its own otherwise.
fn conditionalArm(comptime Checker: type, self: *Checker, id: ast.NodeId, expected: ?typed.Type) Error!typed.NodeId {
    return if (expected) |ty_value| self.expressionExpected(id, ty_value) else self.expression(id);
}
/// Both arms of a conditional have one type: the contextual expected type
/// when there is one, and otherwise the then arm's own type. Integer literal
/// arms adopt the expected width through the ordinary hint, and no numeric
/// widening happens between arms.
fn requireConditionalArms(comptime Checker: type, self: *Checker, expected: ?typed.Type, then_value: typed.NodeId, else_value: typed.NodeId) Error!void {
    const then_type = self.nodes.items[@backingInt(then_value)].ty;
    if (expected) |ty_value| {
        try self.require(then_type, ty_value, self.nodes.items[@backingInt(then_value)].span);
        return self.require(self.nodes.items[@backingInt(else_value)].ty, ty_value, self.nodes.items[@backingInt(else_value)].span);
    }
    const else_type = self.nodes.items[@backingInt(else_value)].ty;
    if (then_type == else_type) return;
    const then_name = try typed.surfaceTypeName(self.allocator, then_type, self.catalog.records);
    const else_name = try typed.surfaceTypeName(self.allocator, else_type, self.catalog.records);
    const message = try std.fmt.allocPrint(self.allocator, "conditional arms must agree: `{s}` here, `{s}` in the else arm", .{ then_name, else_name });
    return self.sink.fail("E_TYPE", self.nodes.items[@backingInt(then_value)].span, message);
}
/// The desugared conditional: a fresh unnamed temporary each arm assigns,
/// read as the block's value. The temporary is not a source binding, so no
/// name can resolve to it and no pending obligation outlives its read.
fn conditionalValue(comptime Checker: type, self: *Checker, node: ast.Node, condition: typed.NodeId, then_value: typed.NodeId, else_value: typed.NodeId, value_type: typed.Type) Error!typed.Node {
    const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(value_type) },
        .name = "<conditional>",
        .declaration = node.span,
        .ty = value_type,
        .mutable = false,
        .usage = .{ .reads = 1, .temporary = true },
    });
    const then_assign = try conditionalAssign(Checker, self, self.nodes.items[@backingInt(then_value)].span, slot, then_value);
    const else_assign = try conditionalAssign(Checker, self, self.nodes.items[@backingInt(else_value)].span, slot, else_value);
    const branch: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .branch = .{ .condition = condition, .then_body = then_assign, .else_body = else_assign } } });
    const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .block = try self.allocator.dupe(typed.StatementId, &.{branch}) } });
    const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = node.span, .ty = value_type, .data = .{ .local = slot } });
    return .{ .span = node.span, .ty = value_type, .data = .{ .block_value = .{ .body = body, .value = read } } };
}
/// One arm of the desugared conditional: the value stored into its temporary.
fn conditionalAssign(comptime Checker: type, self: *Checker, span: source.Span, slot: typed.LocalId, value: typed.NodeId) Error!typed.StatementId {
    const id: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = span, .terminates = false, .data = .{ .assign = .{ .slot = slot, .value = value } } });
    return id;
}
fn checkMembership(comptime Checker: type, self: *Checker, node: ast.Node, membership: @FieldType(@FieldType(ast.Node, "data"), "membership"), temporaries: []const typed.Type) Error!typed.Node {
    const needle = try self.expressionWithTemporaries(membership.needle, temporaries);
    const container = try self.expressionWithTemporaries(membership.container, temporaries);
    const container_type = self.nodes.items[@backingInt(container)].ty;
    if (!container_type.isAggregate() or !self.catalog.records[container_type.recordIndex()].isCollection()) return self.sink.fail("E_MEMBERSHIP", node.span, "membership requires a list, dictionary, or str");
    const schema = self.catalog.records[container_type.recordIndex()];
    const compared = switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .dictionary => schema.collection.key.?,
        .string => container_type,
        .bytes => null,
    };
    if (compared) |key_or_element| if (self.requiresCellEquality(key_or_element))
        return self.sink.fail(eCellEquality, node.span, "membership over Cell-bearing values requires equality, which Cell does not define");
    var member = needle;
    const expected = switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .dictionary => schema.collection.key.?,
        .string => container_type,
        .bytes => try byteMembership(Checker, self, node.span, &member, container_type),
    };
    // Both byte kinds name a contiguous octet needle, so a byte string finds
    // its octets inside an octet buffer and the reverse without conversion.
    const member_type = self.nodes.items[@backingInt(member)].ty;
    const mixed_needle = schema.collection.kind == .bytes and isByteKind(self.catalog.records, member_type);
    if (!mixed_needle) try self.require(member_type, expected, node.span);
    const inputs = [_]typed.NodeId{ member, container };
    var locals: [2]typed.LocalId = undefined;
    var statements: [2]typed.StatementId = undefined;
    for (inputs, 0..) |input, i| {
        locals[i] = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = "<membership>", .declaration = node.span, .ty = self.nodes.items[@backingInt(input)].ty, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
        statements[i] = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .initialize = .{ .slot = locals[i], .value = input } } });
    }
    const needle_read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = node.span, .ty = if (mixed_needle) member_type else expected, .data = .{ .local = locals[0] } });
    var result: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .buffer_operation = .{ .owner = locals[1], .kind = .contains, .arguments = try self.allocator.dupe(typed.NodeId, &.{needle_read}) } } });
    if (membership.negate) {
        const inverse: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .unary = .{ .op = .not, .operand = result, .op_span = node.span } } });
        result = inverse;
    }
    const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
    try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .block = try self.allocator.dupe(typed.StatementId, &statements) } });
    return .{ .span = node.span, .ty = .bool, .data = .{ .block_value = .{ .body = body, .value = result } } };
}
/// Byte membership accepts either a byte scalar, widened to int, or a whole subsequence.
fn byteMembership(comptime Checker: type, self: *Checker, span: source.Span, needle: *typed.NodeId, container_type: typed.Type) Error!typed.Type {
    const actual = self.nodes.items[@backingInt(needle.*)].ty;
    if (!actual.isInteger()) return container_type;
    if (actual != .i64) needle.* = try (collections.Builder(Checker){ .checker = self, .span = span }).node(.i64, .{ .cast = needle.* });
    return .i64;
}
fn checkValueIndex(comptime Checker: type, self: *Checker, node: ast.Node, access: @FieldType(@FieldType(ast.Node, "data"), "index"), out: *typed.Node) Error!void {
    const base = self.resolved[@backingInt(access.base)].?;
    const index_value = self.resolved[@backingInt(access.index)].?;
    const receiver_type = self.nodes.items[@backingInt(base)].ty;
    if (typed.setRecord(self.catalog.records, receiver_type) != null)
        return self.sink.fail(eSetIndex, node.span, set_index_message);
    if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].collection.kind != .list) {
        const receiver = self.catalog.records[receiver_type.recordIndex()];
        if (receiver.collection.kind == .dictionary) {
            try self.require(self.nodes.items[@backingInt(index_value)].ty, receiver.collection.key.?, node.span);
        } else try self.requireInteger(self.nodes.items[@backingInt(index_value)].ty, node.span);
        if (receiver.collection.kind == .bytes) {
            const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
            out.ty = .i64;
            out.data = .{ .cast = try b.node(receiver.shape.buffer.?, .{ .index = .{ .base = base, .index = index_value } }) };
            return;
        }
        out.ty = if (receiver.collection.kind == .string) receiver_type else receiver.shape.buffer.?;
        out.data = .{ .index = .{ .base = base, .index = index_value } };
        return;
    }
    if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].isCollection()) {
        out.* = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, .read, &.{index_value}, false);
        return;
    }
    if (record_layouts.tupleRecord(self.catalog.records, receiver_type) != null)
        return self.sink.fail("E_TUPLE_INDEX", node.span, tuple_index_alternative);
    const schema = try self.catalog.array(receiver_type, node.span, self.sink);
    try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(access.index)].span);
    if (self.requiresHandling(schema.element) and schema.length != 1) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements; handle or transfer the entire array");
    const key = try self.arrayKey(schema, index_value);
    out.ty = schema.element;
    out.data = .{ .index = .{ .base = base, .index = key.key, .from_end = key.from_end } };
}

/// The checker fields `byteValues` writes, so a test can expand a literal alone.
const NodeStub = struct { allocator: std.mem.Allocator, nodes: std.ArrayList(typed.Node) = .empty };

test "a byte literal expands to one u8 node per byte, in order" {
    var stub: NodeStub = .{ .allocator = std.testing.allocator };
    defer stub.nodes.deinit(std.testing.allocator);
    const span: source.Span = .{ .start = 3, .end = 9 };
    const ids = try Checks(NodeStub).byteValues(&stub, "\x00A\xff", span);
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(@as(usize, 3), stub.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 2), @backingInt(ids[2]));
    try std.testing.expectEqual(typed.Type.u8, stub.nodes.items[1].ty);
    try std.testing.expectEqual(@as(i128, 0x41), stub.nodes.items[1].data.integer);
    try std.testing.expectEqual(@as(i128, 0xff), stub.nodes.items[@backingInt(ids[2])].data.integer);
}
