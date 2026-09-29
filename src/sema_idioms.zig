//! Checking of the Python expression idioms that desugar onto existing checked
//! nodes: comparison chains (`PY-CHAIN-1`), sequence
//! repetition (`PY-REPEAT-1`), the step of a counting `range` (`PY-RANGE-STEP-1`)
//! and one `{value:spec}` field of an f-string (`PY-FSTRING-SPEC-1`). Each check
//! is a free function over the concrete checker type; `Checks` exposes the ones
//! the rest of the checker calls as `self.name(...)`.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");
const numeric_surface = @import("numeric_surface.zig");
const range_step = @import("range_step.zig");
const repetition = @import("repetition.zig");
const format_spec = @import("format_spec.zig");
const format_strings = @import("format_strings.zig");
const Error = diagnostic.Error;
const impl = @This();

/// One binary operator whose two operands are already checked nodes.
pub const CheckedBinary = struct { op: ast.BinaryOp, op_span: source.Span, left: typed.NodeId, right: typed.NodeId };

/// The four ordering comparisons, which `str` and `bytes` answer lexicographically.
pub fn textOrdering(op: ast.BinaryOp) bool {
    return op == .lt or op == .le or op == .gt or op == .ge;
}

/// One link of a comparison chain: its operator and the operand to its right.
const ChainLink = struct { op: ast.BinaryOp, op_span: source.Span, span: source.Span, right: ast.NodeId };

/// Bind idiom checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// PY-RANGE-STEP-1: a checked `range` step and the loop lowering it
        /// selects, or no lowering for the implicit step of one.
        pub const RangeStepping = struct {
            lower: ?range_step.Lower(Checker) = null,
            value: ?typed.NodeId = null,
            /// Whether the counter only ever grows, as it does without a step.
            pub fn ascending(self: RangeStepping) bool {
                const lower = self.lower orelse return true;
                return lower.stride == .constant and lower.stride.constant > 0;
            }
            /// The statements that hold and zero-check a runtime stride.
            pub fn setup(self: RangeStepping) Error![]const typed.StatementId {
                const lower = self.lower orelse return &.{};
                return lower.setup(self.value.?);
            }
        };
        /// PY-CHAIN-1: check `a < b <= c` as `a < b and b <= c`, each operand once.
        pub fn checkChain(self: *Checker, node: ast.Node) Error!typed.Node {
            return impl.checkChain(Checker, self, node);
        }
        /// PY-REPEAT-1: type a repeating `*`, or answer false for any other
        /// operator so the ordinary rules apply.
        pub fn idiomBinary(self: *Checker, b: CheckedBinary, out: *typed.Node) Error!bool {
            if (b.op != .mul) return false;
            const operands = repetitionOperands(Checker, self, b) orelse return false;
            out.* = try repetition.build(Checker, self, out.span, operands);
            return true;
        }
        /// Check the optional third argument of `range` against the counter's type.
        pub fn rangeStep(self: *Checker, span: source.Span, syntax: ?ast.NodeId, element: typed.Type) Error!RangeStepping {
            const step_syntax = syntax orelse return .{};
            try self.hint(step_syntax, element);
            const value = try self.expression(step_syntax);
            const step_span = self.syntax.nodes.items[@backingInt(step_syntax)].span;
            try self.require(self.nodes.items[@backingInt(value)].ty, element, step_span);
            const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
            const stride = try range_step.stride(Checker, .{ .checker = self, .span = step_span }, constantInteger(Checker, self, value), element);
            return .{ .lower = .{ .b = b, .element = element, .stride = stride }, .value = value };
        }
        /// PY-REPEAT-1: `name *= count` on a `str`, `bytes` or list binding, or
        /// null when the binding is no repeatable sequence.
        pub fn repeatAssignment(self: *Checker, slot: typed.LocalId, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment")) Error!?@FieldType(typed.Statement, "data") {
            if (a.op != .mul or !repetition.repeatable(self.catalog.records, self.locals.items[@backingInt(slot)].ty)) return null;
            const repeated = try impl.repeatAssignment(Checker, self, slot, a);
            return repeated;
        }
        /// PY-FSTRING-SPEC-1: one `{value:spec}` field, checked and formatted.
        pub fn formatField(self: *Checker, value: typed.NodeId, spec_span: source.Span, span: source.Span) Error!typed.NodeId {
            return impl.formatField(Checker, self, value, spec_span, span);
        }
    };
}

/// The value of a checked integer literal, `k` or `-k`, or null.
fn constantInteger(comptime Checker: type, self: *Checker, id: typed.NodeId) ?i128 {
    return switch (self.nodes.items[@backingInt(id)].data) {
        .integer => |value| value,
        .unary => |unary| if (unary.op == .neg) switch (self.nodes.items[@backingInt(unary.operand)].data) {
            .integer => |value| -value,
            else => null,
        } else null,
        else => null,
    };
}

/// PY-REPEAT-1: the sequence and the count of a `*` that repeats a `str`,
/// `bytes` or list by an integer on either side, or null for any other `*`.
fn repetitionOperands(comptime Checker: type, self: *Checker, b: CheckedBinary) ?repetition.Operands {
    const lt = self.nodes.items[@backingInt(b.left)].ty;
    const rt = self.nodes.items[@backingInt(b.right)].ty;
    if (repetition.repeatable(self.catalog.records, lt) and rt.isInteger()) return .{ .sequence = b.left, .count = b.right, .count_first = false };
    if (repetition.repeatable(self.catalog.records, rt) and lt.isInteger()) return .{ .sequence = b.right, .count = b.left, .count_first = true };
    return null;
}

/// PY-CHAIN-1: `a < b <= c` reads as `a < b and b <= c` with every operand
/// checked and evaluated once, in source order. Each operand but the last is
/// held in an internal local, and a false link skips the rest of the chain,
/// so a later operand is never evaluated after a failed comparison.
fn checkChain(comptime Checker: type, self: *Checker, node: ast.Node) Error!typed.Node {
    var links: std.ArrayList(ChainLink) = .empty;
    var head = node;
    while (head.data == .binary and head.data.binary.chained) {
        const link = head.data.binary;
        try links.append(self.allocator, .{ .op = link.op, .op_span = link.op_span, .span = head.span, .right = link.right });
        head = self.syntax.nodes.items[@backingInt(link.left)];
    }
    const first = head.data.binary;
    try links.append(self.allocator, .{ .op = first.op, .op_span = first.op_span, .span = head.span, .right = first.right });
    std.mem.reverse(ChainLink, links.items);
    const operands = try self.allocator.alloc(ast.NodeId, links.items.len + 1);
    operands[0] = first.left;
    for (links.items, operands[1..]) |link, *operand| operand.* = link.right;
    for (links.items, operands[0 .. operands.len - 1]) |link, left| try self.hintOperands(.{ .op = link.op, .left = left, .right = link.right, .op_span = link.op_span }, null);
    const checked = try checkChainOperands(Checker, self, links.items, operands);
    return chainBlock(Checker, self, node.span, links.items, checked);
}

/// Check each shared operand once, giving contextual Option/Result constructors
/// the actual type of their adjacent equality operand. Node assembly retains source order.
fn checkChainOperands(comptime Checker: type, self: *Checker, links: []const ChainLink, operands: []const ast.NodeId) Error![]typed.NodeId {
    const checked = try self.allocator.alloc(typed.NodeId, operands.len);
    const equality = links[0].op == .eq or links[0].op == .ne;
    const peer_first = equality and try self.awaitsPeerType(operands[0]) and !try self.awaitsPeerType(operands[1]);
    if (peer_first) {
        checked[1] = try self.expression(operands[1]);
        checked[0] = try self.expressionExpected(operands[0], self.nodes.items[@backingInt(checked[1])].ty);
    } else checked[0] = try self.expression(operands[0]);
    const start: usize = if (peer_first) 2 else 1;
    for (operands[start..], start..) |operand, index| {
        const previous = self.nodes.items[@backingInt(checked[index - 1])].ty;
        checked[index] = try checkChainOperand(Checker, self, operand, links[index - 1].op, previous);
    }
    return checked;
}
fn checkChainOperand(comptime Checker: type, self: *Checker, operand: ast.NodeId, op: ast.BinaryOp, previous: typed.Type) Error!typed.NodeId {
    if (op == .eq or op == .ne) if (try self.awaitsPeerType(operand)) return self.expressionExpected(operand, previous);
    return self.expression(operand);
}

/// Assemble a checked comparison chain from its checked operands.
fn chainBlock(comptime Checker: type, self: *Checker, span: source.Span, links: []const ChainLink, checked: []const typed.NodeId) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const slots = try self.allocator.alloc(typed.LocalId, links.len);
    for (slots, checked[0..links.len]) |*slot, value| slot.* = try b.local(self.nodes.items[@backingInt(value)].ty);
    const result = try b.local(.bool);
    var tail: ?typed.StatementId = null;
    var k = links.len;
    while (k > 0) {
        k -= 1;
        const last = k + 1 == links.len;
        const right = if (last) checked[k + 1] else try b.read(slots[k + 1]);
        var comparison: typed.Node = .{ .span = links[k].span, .ty = .bool, .data = .unit };
        try self.binaryValue(.{ .op = links[k].op, .op_span = links[k].op_span, .left = try b.read(slots[k]), .right = right }, &comparison);
        const value = try b.node(comparison.ty, comparison.data);
        var statements: std.ArrayList(typed.StatementId) = .empty;
        if (!last) try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = slots[k + 1], .value = checked[k + 1] } }));
        const store: typed.Store = .{ .slot = result, .value = value };
        try statements.append(self.allocator, try b.stmt(if (k == 0) .{ .initialize = store } else .{ .assign = store }));
        if (tail) |rest| try statements.append(self.allocator, try b.stmt(.{ .branch = .{ .condition = try b.read(result), .then_body = rest, .else_body = null } }));
        tail = try b.stmt(.{ .block = try statements.toOwnedSlice(self.allocator) });
    }
    return b.block(&.{ try b.stmt(.{ .initialize = .{ .slot = slots[0], .value = checked[0] } }), tail.? }, try b.read(result));
}

/// PY-REPEAT-1: `name *= count` on a `str`, `bytes` or list binding. Text and
/// octets rebind the name to the repeated value; a list is repeated in place,
/// as Python's `list.__imul__` is, so every alias observes it.
fn repeatAssignment(comptime Checker: type, self: *Checker, slot: typed.LocalId, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment")) Error!@FieldType(typed.Statement, "data") {
    try self.requireReadable(slot, a.name);
    const count = try self.expression(a.value);
    try self.requireInteger(self.nodes.items[@backingInt(count)].ty, a.op_span);
    const target_type = self.locals.items[@backingInt(slot)].ty;
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    self.locals.items[@backingInt(slot)].usage.writes += 1;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = a.op_span };
    const product = try b.node(target_type, (try repetition.build(Checker, self, a.op_span, .{ .sequence = try b.read(slot), .count = count, .count_first = false })).data);
    if (self.catalog.records[target_type.recordIndex()].collection.kind != .list) {
        try self.requireArenaAssignment(slot, product);
        return .{ .assign = .{ .slot = slot, .value = product } };
    }
    const repeated = try b.local(target_type);
    const arguments = try self.allocator.dupe(typed.NodeId, &.{try b.read(repeated)});
    try self.requireArenaOperation(slot, .extend, arguments);
    return .{ .block = try self.allocator.dupe(typed.StatementId, &.{
        try b.stmt(.{ .initialize = .{ .slot = repeated, .value = product } }),
        try b.stmt(.{ .discard = try b.operation(slot, .clear, &.{}) }),
        try b.stmt(.{ .discard = try b.operation(slot, .extend, arguments) }),
    }) };
}

/// PY-FSTRING-SPEC-1: one `{value:spec}` field. The literal specification is
/// parsed and checked against the value's family here, with CPython's reasons,
/// and travels to the runtime as one packed word.
fn formatField(comptime Checker: type, self: *Checker, value: typed.NodeId, spec_span: source.Span, span: source.Span) Error!typed.NodeId {
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    const family = formatFamily(Checker, self, ty_value) orelse return self.sink.fail(format_strings.code, spec_span, "a format specification applies to a `str`, an integer or a `float` value; convert this value first");
    const parsed = switch (format_spec.parse(self.src.text(spec_span))) {
        .ok => |ok| ok,
        .rejected => |refused| return self.sink.fail(format_strings.code, spec_span, refused.message),
    };
    const spec = switch (format_spec.resolve(parsed, family)) {
        .ok => |ok| ok,
        .rejected => |refused| return self.sink.fail(format_strings.code, spec_span, refused.message),
    };
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const word = try b.node(.i64, .{ .integer = @intCast(format_spec.pack(spec)) });
    if (family == .text) return b.node(ty_value, (try b.access(value, .text_format, &.{word}, false)).data);
    const bits = switch (family) {
        .float => try b.node(.u64, .{ .unwrap = value }),
        .signed => if (ty_value == .i64) value else try b.node(.i64, .{ .cast = value }),
        else => if (ty_value == .u64) value else try b.node(.u64, .{ .cast = value }),
    };
    const str_type = self.catalog.names.get("str") orelse return error.InternalError;
    const owner = try b.local(str_type);
    const empty = try b.node(str_type, .{ .array = &.{} });
    const formatted = try b.block(&.{try b.stmt(.{ .initialize = .{ .slot = owner, .value = empty } })}, try b.operation(owner, .number_format, &.{ bits, word }));
    return b.node(formatted.ty, formatted.data);
}

/// The format-specification family of a value type, or null for a type no
/// specification applies to. A `bool` has none: CPython formats it as an
/// integer, which would print `1` where the reader expects `True`.
fn formatFamily(comptime Checker: type, self: *Checker, ty_value: typed.Type) ?format_spec.Family {
    if (numeric_surface.isFloat(ty_value, self.catalog.records)) return .float;
    if (ty_value.integer()) |info| return if (info.signed) .signed else .unsigned;
    if (ty_value.isAggregate() and self.catalog.records[ty_value.recordIndex()].collection.kind == .string) return .text;
    return null;
}
