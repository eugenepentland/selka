//! Checking of operators and operator-like expressions: unary and binary
//! arithmetic on integers and floats, comparisons and text operators, table,
//! dictionary and text literals, conditional expressions, membership tests and
//! indexing. Each check is a free function over the concrete checker type;
//! `Checks` exposes the ones the rest of the checker calls as `self.name(...)`.
const repetition = @import("repetition.zig");
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const text_scalar = @import("scalar_text_helpers.zig");
const dictionary_views = @import("dictionary_views.zig");
const option_flow = @import("option_flow.zig");
const option_spelling = @import("option_spelling.zig");
const bit_operators = @import("bit_operators.zig");
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
const float_syntax = @import("float_syntax.zig");
const number_literal = @import("number_literal.zig");
const literal_peer = @import("literal_peer.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const arrays = @import("array_literals.zig");
const idioms = @import("sema_idioms.zig");
/// Whether a type is either managed byte kind — the immutable byte string or the
/// mutable octet buffer. The two hold the same one-octet elements and compare
/// content the same way, so one comparison may name both.
fn isByteKind(schemas: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and schemas[ty.recordIndex()].collection.kind == .bytes;
}
/// The note beside a rejected tuple index: tuples are removed (F-50's rule: name only a spelling that is accepted).
const tuple_index_alternative = "a tuple has no elements to index, and tuples were removed; use a record with named fields";
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
        /// Refuse one comparison link whose side is `None`, naming the presence
        /// test it repairs to; chain links carry no certain edit.
        pub fn refusePresenceLink(self: *Checker, op: ast.BinaryOp, left: ast.NodeId, right: ast.NodeId, certain: bool) Error!void {
            return impl.refusePresenceLink(Checker, self, op, left, right, certain);
        }
        /// Type one binary operator over two already checked operands, promoting
        /// an integer operand of a float operation and answering the operator's node.
        pub fn binaryValue(self: *Checker, b: idioms.CheckedBinary, out: *typed.Node) Error!void {
            return impl.binaryValue(Checker, self, b, out);
        }
        /// Make an element of a new list a value position takes (`const piece = strings.split(text, sep)[1]`) a move out of
        /// that list (F-55), in place; any other value is left as it was.
        pub fn moveTemporaryElement(self: *Checker, syntax_value: ast.NodeId, value: typed.NodeId) Error!void {
            return impl.moveTemporaryElement(Checker, self, syntax_value, value);
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
    const records = self.catalog.records;
    // An unsuffixed float literal beside an `f32` operand takes `f32`, as the name-based hint does for
    // operands the checker cannot see yet (`f32(x) * 6.0`).
    if (numeric_surface.isF32(lt, records) and numeric_surface.isFloat(rt, records)) {
        if (try adoptF32Literal(Checker, self, right)) |adopted| right = adopted;
    } else if (numeric_surface.isF32(rt, records) and numeric_surface.isFloat(lt, records)) {
        if (try adoptF32Literal(Checker, self, left)) |adopted| left = adopted;
    }
    const lt_now = self.nodes.items[@backingInt(left)].ty;
    const rt_now = self.nodes.items[@backingInt(right)].ty;
    // `f32` and `float` never meet in one operation: the binary32 operand is widened by a
    // certain `float(...)` repair, and an integer operand is converted explicitly with `f32(...)`.
    if (numeric_surface.isF32(lt_now, records) or numeric_surface.isF32(rt_now, records)) {
        if (numeric_surface.isBinaryFloat(lt_now, records) and numeric_surface.isBinaryFloat(rt_now, records) and lt_now != rt_now)
            return refuseMixedWidth(Checker, self, operation.op_span, if (numeric_surface.isF32(lt_now, records)) left else right);
        if (lt_now.isInteger()) return refuseIntegerOperand(Checker, self, operation.op_span, left);
        if (rt_now.isInteger()) return refuseIntegerOperand(Checker, self, operation.op_span, right);
        return .{ .left = left, .right = right };
    }
    const promote = operation.op == .python_div or numeric_surface.isFloat(lt_now, records) or numeric_surface.isFloat(rt_now, records);
    if (promote) {
        const builder = self.numericBuilder(operation.op_span);
        if (lt_now.isInteger()) left = try builder.append(try builder.fromInteger(left));
        if (rt_now.isInteger()) right = try builder.append(try builder.fromInteger(right));
    }
    return .{ .left = left, .right = right };
}

/// Re-type a float literal operand at binary32, rounding its own spelling straight to binary32. Null when
/// the operand is not a float literal, so the caller keeps the operand and its width diagnostic.
fn adoptF32Literal(comptime Checker: type, self: *Checker, id: typed.NodeId) Error!?typed.NodeId {
    _ = @sizeOf(Checker);
    const node = self.nodes.items[@backingInt(id)];
    if (node.data != .wrap or node.ty != self.catalog.names.get("float").?) return null;
    var text = self.src.text(node.span);
    const negative = text.len != 0 and text[0] == '-';
    if (negative) text = text[1..];
    if (!float_syntax.isLiteral(text)) return null;
    const value = switch (try number_literal.floatAs(f32, self.allocator, text)) {
        .ok => |magnitude| magnitude,
        .bad => return null,
    };
    if (!std.math.isFinite(value)) return null;
    const pattern: u32 = @as(u32, @bitCast(value)) ^ (if (negative) @as(u32, 0x8000_0000) else 0);
    const builder = self.numericBuilderFor(node.span, self.catalog.names.get("f32").?);
    const adopted = try builder.append(try builder.constant(pattern));
    return adopted;
}

/// Refuse a binary operation on an `f32` and a `float` operand. The certain repair widens the
/// binary32 operand with `float(...)`, which is exact, so no result changes.
fn refuseMixedWidth(comptime Checker: type, self: *Checker, op_span: source.Span, narrow: typed.NodeId) Error!NumericOperands {
    _ = @sizeOf(Checker);
    const span = self.nodes.items[@backingInt(narrow)].span;
    const text = try std.fmt.allocPrint(self.allocator, "float({s})", .{self.src.text(span)});
    _ = op_span;
    return self.sink.failFix(numeric_surface.float_width_code, span, "f32 and float are different types; widen the f32 operand with float(...), or convert the float with f32(...)", .{ .span = span, .text = text });
}

/// Refuse an integer operand of an `f32` operation, which needs an explicit conversion.
fn refuseIntegerOperand(comptime Checker: type, self: *Checker, op_span: source.Span, integer_node: typed.NodeId) Error!NumericOperands {
    _ = @sizeOf(Checker);
    _ = op_span;
    const span = self.nodes.items[@backingInt(integer_node)].span;
    const text = try std.fmt.allocPrint(self.allocator, "f32({s})", .{self.src.text(span)});
    return self.sink.failFix(numeric_surface.float_width_code, span, "an f32 operation takes no implicit integer operand; convert it with f32(...)", .{ .span = span, .text = text });
}
fn checkUnary(comptime Checker: type, self: *Checker, node: ast.Node, u: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!typed.Node {
    var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
    const operand = self.resolved.at(@backingInt(u.operand)).?;
    const operand_ty = self.nodes.items[@backingInt(operand)].ty;
    if (@import("extern_types.zig").is(operand_ty, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, u.op_span, .operator);
    if (u.op == .is_none) {
        const shape = prelude.optionShape(operand_ty, self.catalog.records) orelse return self.sink.fail(eOptionTest, u.op_span, "is None requires an Option value");
        if (self.transfers(operand_ty)) return self.sink.fail(eOptionTest, u.op_span, "use match for an Option carrying an owned value or checked Result");
        return option_flow.testValue(self, operand, shape, node.span);
    }
    out.ty = if (u.op == .not) .bool else operand_ty;
    // MASK-LOGIC-1: `not` on a mask complements each lane and answers a mask.
    if (u.op == .not) if (numeric_surface.vectorShape(operand_ty, self.catalog.records)) |shape| {
        if (shape.element != .bool) return self.sink.fail("E_SIMD_LANE", u.op_span, "not on a Simd takes a mask, Simd[bool, N]");
        return .{ .span = node.span, .ty = operand_ty, .data = .{ .unary = .{ .op = .not, .operand = operand, .op_span = u.op_span } } };
    };
    if (u.op == .neg) {
        if (numeric_surface.vectorShape(out.ty, self.catalog.records)) |shape| {
            if (!numeric_surface.isBinaryFloat(shape.element, self.catalog.records) and !shape.element.isInteger()) return self.sink.fail("E_SIMD_LANE", u.op_span, "Simd negation needs float or integer lanes");
            return .{ .span = node.span, .ty = out.ty, .data = .{ .vector_neg = .{ .operand = operand, .op_span = u.op_span } } };
        }
    }
    if (u.op == .neg and numeric_surface.isBinaryFloat(out.ty, self.catalog.records)) return self.numericBuilderFor(node.span, out.ty).negate(operand);
    if (u.op == .f64_bits or u.op == .f32_bits or u.op == .f64_from_bits or u.op == .f32_from_bits) return checkBitPattern(Checker, self, node.span, u, operand, operand_ty);
    // A `float` operand is the binary64 value itself, so the float-in/float-out
    // `f64_*` operations answer a float instead of demanding a bit pattern.
    if (@import("float_intrinsics.zig").floatwise(u.op) and numeric_surface.isFloat(operand_ty, self.catalog.records)) {
        return self.numericBuilder(u.op_span).unary(std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, operand);
    }
    if (u.op == .neg or u.op == .bit_not) {
        try self.refuseMissingTry(operand, .integer, u.op_span);
        try self.requireInteger(out.ty, u.op_span);
    } else {
        try self.refuseMissingTry(operand, .{ .type = if (u.op == .not) .bool else .u64 }, u.op_span);
        try self.require(operand_ty, if (u.op == .not) .bool else .u64, u.op_span);
    }
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
        const key = self.nodes.items[@backingInt(self.resolved.at(@backingInt(entries[0])).?)].ty;
        const value = self.nodes.items[@backingInt(self.resolved.at(@backingInt(entries[1])).?)].ty;
        out.ty = try nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("dict").?, &.{ key, value }, &.{}, node.span);
    }
    if (!out.ty.isAggregate() or self.catalog.records[out.ty.recordIndex()].collection.kind != .dictionary) return self.sink.fail("E_DICT_TYPE", node.span, "dictionary literal requires dict key/value types");
    if (typed.isSet(self.catalog.records[out.ty.recordIndex()])) return self.sink.fail("E_DICT_TYPE", node.span, "`{}` is an empty dict; write `set()` for an empty set, as Python does");
    const schema = self.catalog.records[out.ty.recordIndex()];
    const key = schema.collection.key.?;
    try hashable_keys.require(self.allocator, self.catalog.records, self.sink, key, node.span, typed.isSet(schema));
    const items = try self.allocator.alloc(typed.NodeId, entries.len);
    for (entries, items, 0..) |entry, *item, index| {
        item.* = self.resolved.at(@backingInt(entry)).?;
        try self.require(self.nodes.items[@backingInt(item.*)].ty, if (index % 2 == 0) key else schema.shape.buffer.?, self.syntax.nodes.items[@backingInt(entry)].span);
    }
    out.data = .{ .array = items };
}
/// Parsed byte literals keep managed bytes identity even when their span includes parentheses.
fn byteLiteralType(comptime Checker: type, self: *Checker, node: ast.Node) Error!typed.Type {
    return collections.preludeType(&self.catalog, "bytes", node.span);
}
fn checkTextLiteral(comptime Checker: type, self: *Checker, node: ast.Node, bytes: []const u8, out: *typed.Node) Error!void {
    out.ty = if (node.data == .text) try collections.preludeType(&self.catalog, "str", node.span) else self.expected_types.get(node.span) orelse try byteLiteralType(Checker, self, node);
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
        out.ty = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, node.span, self.sink);
        out.data = .{ .array = try byteValues(Checker, self, bytes, node.span) };
    }
}
/// The bit pattern of a floating value (`__float_bits`, `__f32_bits`) or the floating value a bit pattern
/// names (`__float_from_bits`, `__f32_from_bits`). The operand's type fixes the width; the intrinsic
/// is compiler-internal, and `math.bits` and `math.from_bits` are its public spellings.
fn checkBitPattern(comptime Checker: type, self: *Checker, span: source.Span, u: @FieldType(@FieldType(ast.Node, "data"), "unary"), operand: typed.NodeId, operand_ty: typed.Type) Error!typed.Node {
    _ = @sizeOf(Checker);
    const records = self.catalog.records;
    const to_bits = u.op == .f64_bits or u.op == .f32_bits;
    const narrow = u.op == .f32_bits or u.op == .f32_from_bits;
    const floating: ?typed.Type = if (narrow) self.catalog.names.get("f32") else self.catalog.names.get("float");
    const want: typed.Type = if (narrow) .u32 else .u64;
    if (to_bits) {
        if (!(if (narrow) numeric_surface.isF32(operand_ty, records) else numeric_surface.isFloat(operand_ty, records))) return self.sink.fail("E_TYPE", span, "a bit pattern is read from a value of the matching floating type");
        return .{ .span = span, .ty = want, .data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } } };
    }
    try self.require(operand_ty, want, u.op_span);
    return .{ .span = span, .ty = floating orelse return error.InternalError, .data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } } };
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
    const result = try self.numericBuilderFor(span, self.nodes.items[@backingInt(left)].ty).binary(op, values[0], values[1], self.sink);
    return builder.block(statements.items, try builder.node(result.ty, result.data));
}
fn checkValueBinary(comptime Checker: type, self: *Checker, syntax: @FieldType(@FieldType(ast.Node, "data"), "binary"), out: *typed.Node) Error!void {
    // A chained comparison refuses each link after its operands are checked.
    if (!syntax.chained) try refusePresenceLink(Checker, self, syntax.op, syntax.left, syntax.right, true);
    // PY-CHAIN-1: a chained comparison checks its own operands in order.
    if (syntax.chained) {
        out.* = try self.checkChain(.{ .span = out.span, .data = .{ .binary = syntax } });
        return;
    }
    return binaryValue(Checker, self, .{
        .op = syntax.op,
        .op_span = syntax.op_span,
        .left = self.resolved.at(@backingInt(syntax.left)).?,
        .right = self.resolved.at(@backingInt(syntax.right)).?,
    }, out);
}
/// Whether `id` is the `None` keyword typed as an optional's absence, not the
/// `()` unit literal that shares the same untyped shape.
fn isNoneOperand(comptime Checker: type, self: *Checker, id: ast.NodeId) bool {
    _ = @sizeOf(Checker);
    if (self.syntax.nodes.items[@backingInt(id)].data != .unit) return false;
    const checked = self.resolved.at(@backingInt(id)) orelse return false;
    return switch (self.nodes.items[@backingInt(checked)].data) {
        .variant => |variant| variant.value == null,
        else => false,
    };
}

/// Refuse `a & b`, `a | b` and `a ^ b` on two integers, naming the prelude
/// operation and keeping both operands' source text. A call binds tighter than
/// the operator and than any comparison around it, so the edit is certain in
/// every expression position.
fn refuseBitOperator(comptime Checker: type, self: *Checker, b: idioms.CheckedBinary, builtin: []const u8) Error {
    _ = @sizeOf(Checker);
    const left_span = self.nodes.items[@backingInt(b.left)].span;
    const right_span = self.nodes.items[@backingInt(b.right)].span;
    const span = source.Span.join(left_span, right_span);
    const text = try bit_operators.callText(self.allocator, builtin, self.src.text(left_span), self.src.text(right_span));
    return self.sink.failFix(bit_operators.code, b.op_span, bit_operators.message, .{ .span = span, .text = text });
}

/// Refuse one comparison link when one side is `None` and the other an Option,
/// with the certain edit `test <value> is None` or `<value> is not None`.
fn refusePresenceLink(comptime Checker: type, self: *Checker, op: ast.BinaryOp, left: ast.NodeId, right: ast.NodeId, certain: bool) Error!void {
    if (op != .eq and op != .ne) return;
    const left_none = isNoneOperand(Checker, self, left);
    if (left_none == isNoneOperand(Checker, self, right)) return;
    const other = if (left_none) right else left;
    const checked = self.resolved.at(@backingInt(other)) orelse return;
    const other_type = self.nodes.items[@backingInt(checked)].ty;
    if (prelude.optionShape(other_type, self.catalog.records) == null) return;
    const left_span = self.syntax.nodes.items[@backingInt(left)].span;
    const right_span = self.syntax.nodes.items[@backingInt(right)].span;
    const span = source.Span.join(left_span, right_span);
    const message = option_spelling.comparison_message;
    const certain_edit = certain and !self.transfers(other_type) and !option_spelling.adjacentComparison(self.src, span);
    if (!certain_edit) return self.sink.fail(option_spelling.comparison_code, span, message);
    const text = try option_spelling.testText(self.allocator, self.src.text(self.syntax.nodes.items[@backingInt(other)].span), op == .ne);
    return self.sink.failFix(option_spelling.comparison_code, span, message, .{ .span = span, .text = text });
}

/// Whether a Simd operator exists only on integer lanes: the wrapping forms and the bit operators.
fn integerOnlyOperator(op: typed.BinaryOp) bool {
    return switch (op) {
        .wrapping_add, .wrapping_sub, .wrapping_mul, .bit_and, .bit_or, .bit_xor => true,
        else => false,
    };
}

/// Whether an operator is one of the integer operations spelled as calls (`bit_and`, `shift_right`, `wrapping_add`, ...),
/// whose two operands share one integer type.
fn integerOperation(op: ast.BinaryOp) bool {
    return switch (op) {
        .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .wrapping_add, .wrapping_sub, .wrapping_mul, .saturating_add, .saturating_sub, .saturating_mul => true,
        else => false,
    };
}

/// Whether a mask takes an operator: the lane-by-lane bit operators, which `and` and `or` reach as `bit_and` and `bit_or`.
fn maskOperator(op: typed.BinaryOp) bool {
    return switch (op) {
        .bit_and, .bit_or, .bit_xor => true,
        else => false,
    };
}

/// Check elementwise arithmetic and comparison of two `Simd` values of one type. A comparison answers
/// the mask `Simd[bool, N]`.
fn checkVectorBinary(comptime Checker: type, self: *Checker, b: idioms.CheckedBinary, out: *typed.Node) Error!void {
    _ = @sizeOf(Checker);
    const records = self.catalog.records;
    const lt = self.nodes.items[@backingInt(b.left)].ty;
    const rt = self.nodes.items[@backingInt(b.right)].ty;
    const shape = numeric_surface.vectorShape(lt, records) orelse return self.sink.fail("E_TYPE", b.op_span, "a Simd operator needs Simd operands on both sides");
    if (numeric_surface.vectorShape(rt, records) == null) {
        if (shape.element == .bool) return self.sink.fail("E_TYPE", b.op_span, "a mask combines only with a mask; a bool is not a mask, so splat it with simd.splat");
        return self.sink.fail("E_TYPE", b.op_span, "a Simd operator needs Simd operands on both sides; splat a scalar with simd.splat");
    }
    if (lt != rt) return self.sink.fail("E_TYPE", b.op_span, "Simd operands must have the same type");
    // `&`, `|` and `^` are spelled `bit_and`, `bit_or` and `bit_xor` on any Simd, as on an integer.
    if (set_lower.bitwiseSpelling(self.src.text(b.op_span))) |builtin| return refuseBitOperator(Checker, self, b, builtin);
    const float_lanes = numeric_surface.isBinaryFloat(shape.element, records);
    const mask_lanes = shape.element == .bool;
    const lanes_ok = float_lanes or shape.element.isInteger() or mask_lanes;
    if (!lanes_ok) return self.sink.fail("E_SIMD_LANE", b.op_span, "Simd arithmetic and comparisons need float or integer lanes; a mask supports only its lane reads and select");
    const op: typed.BinaryOp = switch (b.op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .python_div => .div,
        .eq => .eq,
        .ne => .ne,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
        .wrapping_add => .wrapping_add,
        .wrapping_sub => .wrapping_sub,
        .wrapping_mul => .wrapping_mul,
        .bit_and => .bit_and,
        .bit_or => .bit_or,
        .bit_xor => .bit_xor,
        // MASK-LOGIC-1: `and` and `or` on masks are the lane-by-lane bit operators, with both operands evaluated.
        .logical_and => if (mask_lanes) .bit_and else return self.sink.fail("E_SIMD_OPERATOR", b.op_span, "Simd supports `and` and `or` on masks; use float or integer lanes with the operators of their kind"),
        .logical_or => if (mask_lanes) .bit_or else return self.sink.fail("E_SIMD_OPERATOR", b.op_span, "Simd supports `and` and `or` on masks; use float or integer lanes with the operators of their kind"),
        else => return self.sink.fail("E_SIMD_OPERATOR", b.op_span, "Simd supports + - * / on float lanes, + - * and the bit operators on integer lanes, and comparisons"),
    };
    if (mask_lanes and !maskOperator(op)) return self.sink.fail("E_SIMD_LANE", b.op_span, "a mask supports and, or, not, bit_and, bit_or, bit_xor, select and its lane reads");
    if (float_lanes and integerOnlyOperator(op)) return self.sink.fail("E_SIMD_LANE", b.op_span, "wrapping and bit operators on a Simd need integer lanes");
    if (!float_lanes and op == .div) return self.sink.fail("E_SIMD_OPERATOR", b.op_span, "integer Simd lanes do not divide yet; use float lanes for /");
    out.ty = switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge => try self.catalog.instantiateShape(self.allocator, .{ .element = .bool, .length = shape.length, .vector = true }, out.span, self.sink),
        else => lt,
    };
    out.data = .{ .vector_binary = .{ .op = op, .left = b.left, .right = b.right, .op_span = b.op_span } };
}
/// A handle answers `==` and `!=` only: arithmetic, bitwise operators and ordering are refused (`extern_types.zig`).
fn refuseHandleOperator(comptime Checker: type, self: *Checker, b: idioms.CheckedBinary) Error!void {
    const handles = @import("extern_types.zig");
    const records = self.catalog.records;
    if (!handles.is(self.nodes.items[@backingInt(b.left)].ty, records) and !handles.is(self.nodes.items[@backingInt(b.right)].ty, records)) return;
    if (b.op == .eq or b.op == .ne) return;
    return handles.refuse(self.sink, b.op_span, if (idioms.textOrdering(b.op)) .ordering else .operator);
}
fn binaryValue(comptime Checker: type, self: *Checker, b: idioms.CheckedBinary, out: *typed.Node) Error!void {
    // An operator would consume a `@linear` operand without ending it (D-FFI-11).
    if (typed.linear(self.nodes.items[@backingInt(b.left)].ty, self.catalog.records) or typed.linear(self.nodes.items[@backingInt(b.right)].ty, self.catalog.records))
        return @import("linear_rules.zig").refuse(self.sink, b.op_span, .read);
    try refuseHandleOperator(Checker, self, b);
    if (try self.idiomBinary(b, out)) return;
    const records = self.catalog.records;
    const vector_operands = numeric_surface.vectorShape(self.nodes.items[@backingInt(b.left)].ty, records) != null or numeric_surface.vectorShape(self.nodes.items[@backingInt(b.right)].ty, records) != null;
    if (vector_operands) return checkVectorBinary(Checker, self, b, out);
    if (integerOperation(b.op)) {
        const rule = try std.fmt.allocPrint(self.allocator, "`{s}` takes two operands of one integer type", .{@tagName(b.op)});
        try literal_peer.refuseMismatch(Checker, self, "E_TYPE", b.left, b.right, rule);
    }
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
    if (!set_left) if (set_lower.bitwiseSpelling(self.src.text(b.op_span))) |builtin| {
        if (lt.isInteger() and rt.isInteger()) return refuseBitOperator(Checker, self, b, builtin);
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` combines two sets or two integers (`{s}(a, b)`)", .{ self.src.text(b.op_span), builtin });
        return self.sink.fail(set_lower.bitwise_code, b.op_span, message);
    };
    if (!mixed_bytes) {
        // `parse(x) + 1`: the left operand is the `fails` call, and it is the right operand's type that it lacks.
        try self.refuseMissingTry(left, .{ .type = rt }, b.op_span);
        try self.requireNode(right, lt, b.op_span, null);
    }
    if (set_left) if (try self.checkSetBinary(b.op, left, right, b.op_span)) |combined| {
        out.* = combined;
        return;
    };
    if ((b.op == .eq or b.op == .ne) and self.requiresCellEquality(lt))
        return self.sink.fail(eCellEquality, b.op_span, "Cell equality is not defined, including inside collections");
    if (numeric_surface.isBinaryFloat(lt, self.catalog.records)) {
        out.* = try checkFloatBinary(Checker, self, out.span, b.op, left, right);
        return;
    }
    const text_operands = lt.isAggregate() and self.catalog.records[lt.recordIndex()].isCollection();
    if (text_operands) {
        const sequence = self.catalog.records[lt.recordIndex()].collection.kind;
        // `list + list` builds a new list holding copies of both operands' elements, as `str + str` builds new text.
        if (b.op == .add and sequence == .list) {
            out.* = try prelude_builtins.concatLists(Checker, self, out.span, left, right);
            return;
        }
        const concatenation = b.op == .add and (sequence == .string or sequence == .bytes);
        // PY-TEXT-ORDER-1: str orders by code point and bytes by octet, as Python does.
        const ordering = idioms.textOrdering(b.op) and (sequence == .string or sequence == .bytes);
        const accepted = concatenation or ordering or b.op == .eq or b.op == .ne;
        if (!accepted) return self.sink.fail("E_TEXT_OPERATOR", b.op_span, "managed collections support equality; str, bytes and lists also support `+`, and str and bytes `<`, `<=`, `>`, `>=`");
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
            try self.refuseMissingTry(left, .{ .type = .bool }, b.op_span);
            try self.require(lt, .bool, b.op_span);
            out.ty = .bool;
        },
        .eq, .ne => {
            if (!typed.supportsEquality(lt, self.catalog.records)) return self.sink.fail("E_TYPE", b.op_span, "aggregate equality is not defined; compare the relevant elements explicitly");
            out.ty = .bool;
        },
        .lt, .le, .gt, .ge => {
            try self.refuseMissingTry(left, .integer, b.op_span);
            try self.requireInteger(lt, b.op_span);
            out.ty = .bool;
        },
        else => {
            try self.refuseMissingTry(left, .integer, b.op_span);
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
    try self.requireNode(condition, .bool, self.syntax.nodes.items[@backingInt(conditional.condition)].span, null);
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
    if (@import("control_expression_migration.zig").nestedSelection(self.syntax, node)) {
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .name = "<removed-selection>",
            .declaration = node.span,
            .ty = value_type,
            .mutable = false,
            .ownership = .{ .initialized = true },
            .usage = .{ .temporary = true, .reads = 1 },
        });
        return .{ .span = node.span, .ty = value_type, .data = .{ .local = slot } };
    }
    const spelling = try @import("control_expression_symbolic.zig").typedSpelling(self.allocator, self.src, node.span, value_type, self.catalog);
    return @import("control_expression_migration.zig").reject(self.src, self.syntax, self.sink, node, spelling);
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
/// Whether `id` is a name or a plain number written out, possibly negated: a read that costs nothing to repeat.
fn plainOperand(comptime Checker: type, self: *Checker, id: ast.NodeId) bool {
    const data = self.syntax.nodes.items[@backingInt(id)].data;
    if (data == .unary and data.unary.op == .neg) return self.syntax.nodes.items[@backingInt(data.unary.operand)].data == .integer;
    return data == .name or data == .integer;
}

/// SP3-F-11: `x in range(a, b)` is refused because the module declares no `range` to call, which names a module the author
/// never wrote and does not say that `range` is a loop header. `refusal` is the unknown-name refusal of that call, the
/// last one raised; it keeps its code, its place and its verdict and takes a message that names the comparison, with the
/// bounds as written: `a <= x < b`, or `x < a or b <= x` after `not in`. The repair is offered only when the needle and
/// every bound is a name or a number and there is no step; a step has no one comparison, so its message says to write the
/// bounds and the remainder out. A call that does resolve (a function named `range` the module declares) never gets here.
fn explainRangeMembership(comptime Checker: type, self: *Checker, node: ast.Node, membership: @FieldType(@FieldType(ast.Node, "data"), "membership")) Error!void {
    const container = self.syntax.nodes.items[@backingInt(membership.container)];
    if (container.data != .call or container.data.call.owner != null or self.sink.items.items.len == 0) return;
    const call = container.data.call;
    if (!std.mem.eql(u8, self.src.text(call.name), "range") or call.arguments.len == 0 or call.arguments.len > 3) return;
    for (call.argument_names) |named| if (named != null) return;
    const refusal = &self.sink.items.items[self.sink.items.items.len - 1];
    const unknown = std.mem.eql(u8, refusal.code, "E_UNKNOWN_SYMBOL") or std.mem.eql(u8, refusal.code, "E_UNKNOWN_FUNCTION");
    if (!unknown or refusal.span.start != call.name.start) return;
    const lead = "`range` is a loop source (`for i in range(a, b):`), not a collection, so `in` cannot test against it";
    if (call.arguments.len == 3) {
        refusal.message = lead ++ "; with a step, write the bounds and the step's remainder out as comparisons";
        return;
    }
    const needle = self.src.text(self.syntax.nodes.items[@backingInt(membership.needle)].span);
    const low = if (call.arguments.len == 2) self.src.text(self.syntax.nodes.items[@backingInt(call.arguments[0])].span) else "0";
    const high = self.src.text(self.syntax.nodes.items[@backingInt(call.arguments[call.arguments.len - 1])].span);
    const long = needle.len > 40 or low.len > 40 or high.len > 40 or std.mem.indexOfScalar(u8, needle, '\n') != null or
        std.mem.indexOfScalar(u8, low, '\n') != null or std.mem.indexOfScalar(u8, high, '\n') != null;
    const comparison = if (long)
        (if (membership.negate) "x < a or b <= x" else "a <= x < b")
    else if (membership.negate)
        try std.fmt.allocPrint(self.allocator, "{s} < {s} or {s} <= {s}", .{ needle, low, high, needle })
    else
        try std.fmt.allocPrint(self.allocator, "{s} <= {s} < {s}", .{ low, needle, high });
    refusal.message = try std.fmt.allocPrint(self.allocator, "{s}: write the comparison `{s}`", .{ lead, comparison });
    if (long) return;
    for ([_]ast.NodeId{ membership.needle, call.arguments[0], call.arguments[call.arguments.len - 1] }) |operand| {
        if (!plainOperand(Checker, self, operand)) return;
    }
    const text = if (membership.negate) try std.fmt.allocPrint(self.allocator, "({s})", .{comparison}) else comparison;
    refusal.provenance.fix = .{ .edit = .{ .span = node.span, .text = text } };
}
fn checkMembership(comptime Checker: type, self: *Checker, node: ast.Node, membership: @FieldType(@FieldType(ast.Node, "data"), "membership"), temporaries: []const typed.Type) Error!typed.Node {
    const needle = try self.expressionWithTemporaries(membership.needle, temporaries);
    const container = self.expressionWithTemporaries(membership.container, temporaries) catch |failure| {
        if (failure == error.SourceError) try explainRangeMembership(Checker, self, node, membership);
        return failure;
    };
    const container_type = self.nodes.items[@backingInt(container)].ty;
    if (dictionary_views.identify(self.catalog, container_type)) |kind| if (kind != .item) {
        const mapping = try dictionary_views.owner(Checker, self, node.span, container);
        const expected = try dictionary_views.element(&self.catalog, self.nodes.items[@backingInt(mapping)].ty, kind, node.span);
        try self.require(self.nodes.items[@backingInt(needle)].ty, expected, node.span);
        if (self.requiresCellEquality(expected)) return self.sink.fail(eCellEquality, node.span, "membership over Cell-bearing values requires equality, which Cell does not define");
        if (kind == .values) {
            const needle_pure = repetition.pure(self.nodes.items, self.catalog.records, needle) or repetition.literalListPure(Checker, self, membership.needle);
            const certain = needle_pure and repetition.dictionaryValuesPure(Checker, self, self.syntax.nodes.items[@backingInt(membership.container)].span);
            const replacement = if (certain) try std.fmt.allocPrint(self.allocator, "{s}lists.contains(list({s}), {s})", .{
                if (membership.negate) "not " else "", self.src.text(self.syntax.nodes.items[@backingInt(membership.container)].span), self.src.text(self.syntax.nodes.items[@backingInt(membership.needle)].span),
            }) else null;
            try repetition.removed(Checker, self, node.span, .{
                .code = "E_LIST_MEMBERSHIP_REMOVED",
                .message = "membership over dictionary values was removed; use lists.contains(list(dicts.values(mapping)), value)",
                .module = "lists",
            }, replacement);
            return .{ .span = node.span, .ty = .bool, .data = .{ .boolean = false } };
        }
        return dictionary_views.contains(Checker, self, node.span, needle, mapping, kind, membership.negate);
    };
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
    if (schema.collection.kind == .list) {
        const needle_pure = repetition.pure(self.nodes.items, self.catalog.records, needle) or repetition.literalListPure(Checker, self, membership.needle);
        const container_pure = repetition.pure(self.nodes.items, self.catalog.records, container) or repetition.literalListPure(Checker, self, membership.container);
        const certain = repetition.swapCertain(needle_pure, container_pure, self.src.text(self.syntax.nodes.items[@backingInt(membership.needle)].span), self.src.text(self.syntax.nodes.items[@backingInt(membership.container)].span));
        const replacement = if (certain) try std.fmt.allocPrint(self.allocator, "{s}lists.contains({s}, {s})", .{
            if (membership.negate) "not " else "", self.src.text(self.syntax.nodes.items[@backingInt(membership.container)].span), self.src.text(self.syntax.nodes.items[@backingInt(membership.needle)].span),
        }) else null;
        try repetition.removed(Checker, self, node.span, .{
            .code = "E_LIST_MEMBERSHIP_REMOVED",
            .message = "list membership was removed; use lists.contains(values, value), preserving operand evaluation order when either operand has effects",
            .module = "lists",
        }, replacement);
        return .{ .span = node.span, .ty = .bool, .data = .{ .boolean = false } };
    }
    // A pure needle is read where it is (CX2, F1): a text or bytes view needle is never copied into an owned temporary and
    // dropped. The container is the operation's owner, so a container that is not already a local gets its temporary.
    if (repetition.pure(self.nodes.items, self.catalog.records, member)) {
        const container_node = self.nodes.items[@backingInt(container)];
        const local_container = container_node.data == .local and !container_node.own;
        const owner: typed.LocalId = if (local_container) self.nodes.items[@backingInt(container)].data.local else @fromBackingInt(self.locals.items.len);
        var body: []const typed.StatementId = &.{};
        if (!local_container) {
            try self.locals.append(self.allocator, .{ .name = "<membership>", .declaration = node.span, .ty = self.nodes.items[@backingInt(container)].ty, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
            const statement: typed.StatementId = @fromBackingInt(self.statements.items.len);
            try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .initialize = .{ .slot = owner, .value = container } } });
            body = try self.allocator.dupe(typed.StatementId, &.{statement});
        }
        // The probe is a block value, as the temporaries path is, so it consumes no queued temporary of the enclosing statement.
        const probe: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .buffer_operation = .{ .owner = owner, .kind = .contains, .arguments = try self.allocator.dupe(typed.NodeId, &.{member}) } } });
        var value: typed.NodeId = probe;
        if (membership.negate) {
            value = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .unary = .{ .op = .not, .operand = probe, .op_span = node.span } } });
        }
        const block: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .block = body } });
        return .{ .span = node.span, .ty = .bool, .data = .{ .block_value = .{ .body = block, .value = value } } };
    }
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
/// The name of the hidden owner an element of a new list moves out of (F-55). It is no `<` name: those are receiver
/// temporaries, which borrow; this one owns the list until its last use, as a local bound to the call would.
pub const temporary_list_name = "temporary list";
/// F-55: `TEMP[i]` in a position that takes its value (a binding, an assignment, a `return`, a store, an `own` argument),
/// where TEMP is the new list a call returns or a list literal and the element type is managed, so a read would only lend
/// the element. The checked read is `{ <collection> = TEMP; read(<collection>, i) }`; it becomes
/// `{ temporary list = TEMP; pop_at(temporary list, i) }`: the hidden owner takes the list as `mut items = TEMP` would,
/// `pop_at` moves the element out with the same bounds trap, and the rest of the list is dropped with its owner. A call
/// whose result is declared `from` a parameter lends its list and keeps the read, as does every other base.
fn moveTemporaryElement(comptime Checker: type, self: *Checker, syntax_value: ast.NodeId, value: typed.NodeId) Error!void {
    const marked = self.syntax.nodes.items[@backingInt(syntax_value)];
    // `own TEMP[i]` is checked as the move it now is, so Core says the marker is not needed.
    const spelled = if (marked.data == .own_argument) self.syntax.nodes.items[@backingInt(marked.data.own_argument)] else marked;
    if (self.nodes.items[@backingInt(value)].data == .borrow_selection) return moveNewOptionDefault(Checker, self, spelled, value);
    if (spelled.data != .index) return;
    const base = self.syntax.nodes.items[@backingInt(spelled.data.index.base)];
    if (base.data != .call and base.data != .list_literal) return;
    const node = self.nodes.items[@backingInt(value)];
    if (node.data == .index) return moveTemporaryEntry(Checker, self, base, value);
    if (node.data != .block_value) return;
    const read_id = node.data.block_value.value;
    const read = self.nodes.items[@backingInt(read_id)];
    if (read.data != .buffer_operation or read.data.buffer_operation.kind != .read) return;
    if (!@import("own_parameters.zig").managed(self.catalog.records, read.ty)) return;
    const owner = read.data.buffer_operation.owner;
    const owner_local = self.locals.items[@backingInt(owner)];
    if (!std.mem.eql(u8, owner_local.name, "<collection>")) return;
    const owner_type = owner_local.ty;
    if (!owner_type.isAggregate() or self.catalog.records[owner_type.recordIndex()].collection.kind != .list) return;
    // The list is the initializer of the read's owner, the last statement of the block.
    const body = self.statements.items[@backingInt(node.data.block_value.body)].data;
    if (body != .block or body.block.len == 0) return;
    const rooted = self.statements.items[@backingInt(body.block[body.block.len - 1])].data;
    if (rooted != .initialize or rooted.initialize.slot != owner) return;
    if (base.data == .call and !freshList(Checker, self, rooted.initialize.value, 0)) return;
    // The position is read once; the read the index was stays in front of the move as its bounds check, so a position
    // out of range traps exactly as the index did (the same code, place and trap detail), and `pop_at` then moves.
    const b: collections.Builder(Checker) = .{ .checker = self, .span = read.span };
    const position = try b.local(self.nodes.items[@backingInt(read.data.buffer_operation.arguments[0])].ty);
    const hold = try b.stmt(.{ .initialize = .{ .slot = position, .value = read.data.buffer_operation.arguments[0] } });
    const bounds = try b.stmt(.{ .discard = try b.operation(owner, .read, &.{try b.read(position)}) });
    const statements = try std.mem.concat(self.allocator, typed.StatementId, &.{ body.block, &.{ hold, bounds } });
    self.statements.items[@backingInt(node.data.block_value.body)].data = .{ .block = statements };
    self.nodes.items[@backingInt(read_id)].data.buffer_operation.arguments = try self.allocator.dupe(typed.NodeId, &.{try b.read(position)});
    self.nodes.items[@backingInt(read_id)].data.buffer_operation.kind = .pop_at;
    const hidden = &self.locals.items[@backingInt(owner)];
    hidden.name = temporary_list_name;
    hidden.mutable = true;
    hidden.usage = .{ .reads = 1, .writes = 1 };
}
/// F-55 for a dictionary: `TEMP[key]`, checked as a plain index of the call's new dictionary, becomes
/// `{ temporary list = TEMP; pop_key(temporary list, key) }`, which moves the value out with the same missing-key trap.
fn moveTemporaryEntry(comptime Checker: type, self: *Checker, base: ast.Node, value: typed.NodeId) Error!void {
    if (base.data != .call) return;
    const node = self.nodes.items[@backingInt(value)];
    const access = node.data.index;
    const map_type = self.nodes.items[@backingInt(access.base)].ty;
    if (!map_type.isAggregate() or self.catalog.records[map_type.recordIndex()].collection.kind != .dictionary) return;
    if (!@import("own_parameters.zig").managed(self.catalog.records, node.ty)) return;
    if (!freshList(Checker, self, access.base, 0)) return;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const hidden = try b.local(map_type);
    self.locals.items[@backingInt(hidden)].name = temporary_list_name;
    self.locals.items[@backingInt(hidden)].usage = .{ .reads = 1, .writes = 1 };
    const rooted = try b.stmt(.{ .initialize = .{ .slot = hidden, .value = access.base } });
    const taken = try b.operation(hidden, .pop_key, &.{access.index});
    const moved = try b.block(&.{rooted}, taken);
    self.nodes.items[@backingInt(value)] = moved;
}
/// The names of the hidden owners an owned `unwrap_or` moves its result out of (F-71). They are no `<` names, as
/// `temporary list` is not: each owns its value until the block ends, as a local bound to it would.
pub const temporary_option_name = "temporary option";
const temporary_default_name = "temporary default";
const temporary_payload_name = "temporary payload";
const temporary_result_name = "temporary result";
/// F-71: `R.unwrap_or(d)` (or `unwrap_or(R, d)`) in a position that takes its value, where R is a new option (the
/// test F-55 applies to a new list: a call whose result is not declared `from` a parameter) and `d` is a value of its own
/// (`ownDefault`), so the result is owned on both paths. The checked borrow selection becomes the block
/// `options.take_or` runs, inline: `{ temporary option = R; temporary default = d; match own temporary option:
/// case Some(temporary payload): temporary result = own temporary payload; case None: temporary result = own temporary
/// default }`, whose value moves `temporary result` out. The unused default is dropped with its owner. Any other
/// receiver or default, and every position that only reads, keeps the borrow selection; a `const` binding accepted
/// before (it only lent) now owns the same value.
fn moveNewOptionDefault(comptime Checker: type, self: *Checker, spelled: ast.Node, value: typed.NodeId) Error!void {
    const node = self.nodes.items[@backingInt(value)];
    const selection = node.data.borrow_selection;
    if (selection.kind != .optional_default) return;
    // `own R.unwrap_or(d)` keeps today's refusal: a fresh value takes no marker.
    if (node.own) return;
    // A payload with no managed storage (a number, a record of numbers) is copied by the selection: nothing to move.
    if (!@import("own_parameters.zig").managed(self.catalog.records, node.ty)) return;
    // A `@linear` payload is never dropped unconsumed: the unused default (or payload) of an owned reading would be.
    if (typed.linear(node.ty, self.catalog.records)) return;
    if (!freshList(Checker, self, selection.first, 0)) return;
    // The default is a value position of the owned reading: a nested owned `unwrap_or` or an element of a new list moves.
    const default_syntax = optionDefaultSyntax(Checker, self, spelled) orelse return;
    try moveTemporaryElement(Checker, self, default_syntax, selection.second);
    if (!ownDefault(Checker, self, selection.second, 0)) return;
    const option_type = self.nodes.items[@backingInt(selection.first)].ty;
    const shape = @import("prelude.zig").optionShape(option_type, self.catalog.records) orelse return;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const option = try hiddenOwner(Checker, self, b, option_type, temporary_option_name);
    const fallback = try hiddenOwner(Checker, self, b, node.ty, temporary_default_name);
    const result = try hiddenOwner(Checker, self, b, node.ty, temporary_result_name);
    const payload: typed.LocalId = @fromBackingInt(self.locals.items.len);
    try self.locals.append(self.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(node.ty) },
        .name = temporary_payload_name,
        .usage = .{ .reads = 1 },
        .declaration = node.span,
        .ty = node.ty,
        .mutable = false,
    });
    const rooted = try b.stmt(.{ .initialize = .{ .slot = option, .value = selection.first } });
    const eager = try b.stmt(.{ .initialize = .{ .slot = fallback, .value = selection.second } });
    const take = try b.stmt(.{ .initialize = .{ .slot = result, .value = try movedOut(Checker, b, payload) } });
    const some = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{take}) });
    const give = try b.stmt(.{ .initialize = .{ .slot = result, .value = try movedOut(Checker, b, fallback) } });
    const none = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{give}) });
    const arms = try self.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = payload, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    const select = try b.stmt(.{ .match = .{ .value = try movedOut(Checker, b, option), .arms = arms } });
    // The move out of the result spans the method's name, not the whole expression: a `return` of the block is then no
    // bare return of a local to Core (`return own x`), and gives the moved value as any other value position does.
    const given: collections.Builder(Checker) = .{ .checker = self, .span = optionMethodName(Checker, self, spelled) orelse node.span };
    // Built first: building appends nodes, which may move the table the result is written into.
    const owned = try b.block(&.{ rooted, eager, select }, try movedOut(Checker, given, result));
    self.nodes.items[@backingInt(value)] = owned;
}
/// A hidden owner of an owned `unwrap_or` (F-71), initialized once in its block and moved from once.
fn hiddenOwner(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), ty: typed.Type, name: []const u8) Error!typed.LocalId {
    const slot = try b.local(ty);
    const hidden = &self.locals.items[@backingInt(slot)];
    hidden.name = name;
    hidden.mutable = false;
    hidden.usage = .{ .reads = 1, .writes = 1 };
    return slot;
}
/// A read of a hidden owner that gives its value away, as `own name` does in source.
fn movedOut(comptime Checker: type, b: collections.Builder(Checker), slot: typed.LocalId) Error!typed.NodeId {
    const id = try b.read(slot);
    b.checker.nodes.items[@backingInt(id)].own = true;
    return id;
}
/// The span of the name `unwrap_or` in `R.unwrap_or(d)` or `unwrap_or(R, d)`, or null for any other node.
fn optionMethodName(comptime Checker: type, self: *Checker, spelled: ast.Node) ?source.Span {
    _ = self;
    return switch (spelled.data) {
        .method_call => |call| call.name,
        .call => |call| call.name,
        else => null,
    };
}
/// The syntax of the default of `R.unwrap_or(d)` or of the prelude spelling `unwrap_or(R, d)`, or null for any other node.
fn optionDefaultSyntax(comptime Checker: type, self: *Checker, spelled: ast.Node) ?ast.NodeId {
    const name, const arguments = switch (spelled.data) {
        .method_call => |call| .{ call.name, call.arguments },
        .call => |call| .{ call.name, call.arguments },
        else => return null,
    };
    if (!std.mem.eql(u8, self.src.text(name), "unwrap_or") or arguments.len == 0) return null;
    return arguments[arguments.len - 1];
}
/// Whether a checked default of `unwrap_or` is a value of its own (F-71), so that an owned reading owns its result on
/// the `None` path too: a literal (a static constant with no owner), a new value (`freshList`'s calls and literals, a joined
/// text, a format string, a constructor of such values, an owned `unwrap_or`), or a named owner the source gives with
/// `own`. A bare name, a field, an element, a parameter and a lent call are places, and keep the borrow selection.
fn ownDefault(comptime Checker: type, self: *Checker, id: typed.NodeId, depth: usize) bool {
    if (depth > 16) return false;
    const node = self.nodes.items[@backingInt(id)];
    if (node.view) return false;
    if (!@import("own_parameters.zig").managed(self.catalog.records, node.ty)) return true;
    return switch (node.data) {
        .local => node.own,
        .binary, .format => true,
        .variant => |variant| if (variant.value) |payload| ownDefault(Checker, self, payload, depth + 1) else true,
        .record => |fields| for (fields) |field| {
            if (!ownDefault(Checker, self, field.value, depth + 1)) break false;
        } else true,
        .block_value => |block| freshList(Checker, self, id, depth) or ownedBlock(Checker, self, block),
        else => freshList(Checker, self, id, depth),
    };
}
/// Whether a block is an owned `unwrap_or` (F-71) or an element moved out of a new list (F-55): its value is the move out
/// of `temporary result`, or `pop_at`/`pop_key` on `temporary list`.
fn ownedBlock(comptime Checker: type, self: *Checker, block: @FieldType(@FieldType(typed.Node, "data"), "block_value")) bool {
    const value = self.nodes.items[@backingInt(block.value)];
    return switch (value.data) {
        .local => |slot| value.own and std.mem.eql(u8, self.locals.items[@backingInt(slot)].name, temporary_result_name),
        .buffer_operation => |operation| (operation.kind == .pop_at or operation.kind == .pop_key) and
            std.mem.eql(u8, self.locals.items[@backingInt(operation.owner)].name, temporary_list_name),
        else => false,
    };
}
/// Whether a checked call's value is a list nothing else holds: a call of a function whose result is not declared
/// `from` a parameter, a library operation that builds a new list (`split`, `keys`, `copy`, ...), a literal, or a block
/// whose value is one of those. Anything that may lend (`dicts.get`, a view, a read) is not.
fn freshList(comptime Checker: type, self: *Checker, id: typed.NodeId, depth: usize) bool {
    if (depth > 16) return false;
    const node = self.nodes.items[@backingInt(id)];
    if (node.view) return false;
    return switch (node.data) {
        .call => |call| self.syntaxFunction(call.function).signature.borrowing.len == 0,
        .array, .acquire_buffer => true,
        .buffer_operation => |operation| switch (operation.kind) {
            .split, .splitlines, .split_whitespace, .keys, .values, .items, .copy, .to_list => true,
            else => false,
        },
        .block_value => |block| freshList(Checker, self, block.value, depth + 1) or builtList(Checker, self, block, depth),
        else => false,
    };
}
/// Whether a block's value reads a builder temporary the block initializes with a new list (`list(range(n))`).
fn builtList(comptime Checker: type, self: *Checker, block: @FieldType(@FieldType(typed.Node, "data"), "block_value"), depth: usize) bool {
    const value = self.nodes.items[@backingInt(block.value)];
    if (value.data != .local) return false;
    if (!std.mem.eql(u8, self.locals.items[@backingInt(value.data.local)].name, "<collection>")) return false;
    const body = self.statements.items[@backingInt(block.body)].data;
    if (body != .block) return false;
    for (body.block) |statement| {
        const data = self.statements.items[@backingInt(statement)].data;
        if (data == .initialize and data.initialize.slot == value.data.local) return freshList(Checker, self, data.initialize.value, depth + 1);
    }
    return false;
}
fn checkValueIndex(comptime Checker: type, self: *Checker, node: ast.Node, access: @FieldType(@FieldType(ast.Node, "data"), "index"), out: *typed.Node) Error!void {
    const base = self.resolved.at(@backingInt(access.base)).?;
    const index_value = self.resolved.at(@backingInt(access.index)).?;
    const receiver_type = self.nodes.items[@backingInt(base)].ty;
    if (typed.setRecord(self.catalog.records, receiver_type) != null)
        return self.sink.fail(eSetIndex, node.span, set_index_message);
    if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].collection.kind != .list) {
        const receiver = self.catalog.records[receiver_type.recordIndex()];
        if (receiver.collection.kind == .dictionary) {
            try self.require(self.nodes.items[@backingInt(index_value)].ty, receiver.collection.key.?, node.span);
        } else try self.requireInteger(self.nodes.items[@backingInt(index_value)].ty, node.span);
        if (receiver.collection.kind == .string or receiver.collection.kind == .bytes)
            try @import("negative_index.zig").check(Checker, self, index_value, false);
        if (receiver.collection.kind == .bytes) {
            const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
            out.ty = .i64;
            out.data = .{ .cast = try b.node(receiver.shape.buffer.?, .{ .index = .{ .base = base, .index = index_value } }) };
            return;
        }
        // Wave 3 phase 2: `text[index]` is the octet at that byte offset, an int.
        // The scalar read is `strings.char_at`, which lowers to the `.read`
        // operation and still answers a one-scalar `str`.
        if (receiver.collection.kind == .string) {
            out.ty = .i64;
            out.data = .{ .index = .{ .base = base, .index = index_value } };
            return;
        }
        out.ty = receiver.shape.buffer.?;
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
    if (self.requiresHandling(schema.element) and schema.length != 1) return self.sink.failOwnership(
        .{ .code = eResultOperation, .rule = .L1 },
        node.span,
        "indexing would drop other result-bearing elements; handle or transfer the entire array",
    );
    const key = try self.arrayKey(schema, index_value);
    out.ty = schema.element;
    out.data = .{ .index = .{ .base = base, .index = key.key } };
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
