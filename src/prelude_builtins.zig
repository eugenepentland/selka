//! Bare Python builtins lowered to ordinary checked collection operations.
//!
//! Every operation here is total and free of side effects, so it is built from
//! the same checked nodes, loops and collection operations that user code uses:
//! there is no runtime support beyond the existing traps.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const buffer_operations = @import("buffer_operations.zig");
const collections = @import("collection_lower.zig");
const numeric_surface = @import("numeric_surface.zig");
const Error = diagnostic.Error;

/// Value families the prelude folds and orderings understand.
pub const Family = enum { integer, floating, text };

/// The one prelude spelling that appears both in the reserved-name table and in
/// the call dispatch, kept as one const so the two cannot drift.
const reversed_builtin = "reversed";
/// The two scalar/text prelude names, shared by the reserved table and the
/// dispatch below for the same reason.
const ord_builtin = "ord";
const chr_builtin = "chr";

/// Prelude names answered without an import when no binding or declaration shadows them.
pub fn reserved(name: []const u8) bool {
    inline for (.{ "sum", "min", "max", "sorted", "abs", "round", "any", "all", reversed_builtin, "list", "zip", ord_builtin, chr_builtin }) |builtin| {
        if (std.mem.eql(u8, name, builtin)) return true;
    }
    return false;
}

/// Names whose single argument is a sequence the prelude materialises as a new list.
pub fn materializes(name: []const u8) bool {
    return std.mem.eql(u8, name, "list");
}

/// Checked local slots and loop identity of one walk over a list.
pub const Walk = struct { owner: typed.LocalId, index: typed.LocalId, limit: typed.LocalId, slot: typed.LocalId, loop: usize };

/// Checked local slots of one parallel walk over two lists.
pub const Zip = struct { left: Walk, right: Walk, limit: typed.LocalId };

/// One prepared walk over a list: its source, reserved slots, direction and body.
pub const Step = struct { span: source.Span, input: typed.NodeId, walk: Walk, descending: bool, body: typed.StatementId };

/// One prepared walk over two lists: both sources, reserved slots and body.
pub const ZipStep = struct { span: source.Span, left: typed.NodeId, right: typed.NodeId, zip: Zip, body: typed.StatementId };

/// The prelude operations of one checker: bare Python builtins built from checked
/// collection operations, so no runtime support is added beyond the existing traps.
pub fn Prelude(comptime Checker: type) type {
    return struct {
        checker: *Checker,

        /// Build one prelude builtin call, or null when a later recognizer owns this call.
        pub fn build(self: @This(), span: source.Span, name: []const u8, arguments: []const typed.NodeId) Error!?typed.Node {
            return buildCall(Checker, self.checker, span, name, arguments);
        }
        /// `list(range(...))`: the counted range materialised as a new list.
        pub fn rangeList(self: @This(), span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
            return rangeListCall(Checker, self.checker, span, arguments);
        }
        /// `list(xs)`: an independent copy of a list.
        pub fn copyList(self: @This(), span: source.Span, input: typed.NodeId) Error!typed.Node {
            return copyListCall(Checker, self.checker, span, input);
        }
        /// Reserve the slots of one list walk before its body binds an iteration name.
        pub fn reserveWalk(self: @This(), span: source.Span, list: typed.Type) Error!Walk {
            return reserveWalkCall(Checker, self.checker, span, list);
        }
        /// Assemble the statements that walk one list into its reserved slot.
        pub fn walkStatements(self: @This(), step: Step) Error![]const typed.StatementId {
            return walkStatementsCall(Checker, self.checker, step);
        }
        /// Reserve the slots of a parallel walk over two lists.
        pub fn reserveZip(self: @This(), span: source.Span, left: typed.Type, right: typed.Type) Error!Zip {
            return reserveZipCall(Checker, self.checker, span, left, right);
        }
        /// Assemble the statements that walk two lists in step.
        pub fn zipStatements(self: @This(), step: ZipStep) Error![]const typed.StatementId {
            return zipStatementsCall(Checker, self.checker, step);
        }
    };
}

fn builder(comptime Checker: type, checker: *Checker, span: source.Span) collections.Builder(Checker) {
    return .{ .checker = checker, .span = span };
}

fn numericBuilder(comptime Checker: type, checker: *Checker, span: source.Span, float_type: typed.Type) numeric_surface.Builder {
    return .{ .arena = checker.allocator, .nodes = &checker.nodes, .span = span, .float_type = float_type };
}

/// The checked "left is less than right" test for two float values.
fn floatLess(comptime Checker: type, checker: *Checker, span: source.Span, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    const nb = numericBuilder(Checker, checker, span, nodeType(Checker, checker, left));
    return nb.append(try nb.binary(.lt, left, right, checker.sink));
}

fn nodeType(comptime Checker: type, checker: *Checker, id: typed.NodeId) typed.Type {
    return checker.nodes.items[@backingInt(id)].ty;
}

fn retain(comptime Checker: type, checker: *Checker, span: source.Span, value: typed.Node) Error!typed.NodeId {
    return builder(Checker, checker, span).node(value.ty, value.data);
}

fn keep(comptime Checker: type, checker: *Checker, values: []const typed.StatementId) Error![]const typed.StatementId {
    return checker.allocator.dupe(typed.StatementId, values);
}

/// Identify the value family of one scalar type, or null when no prelude fold applies.
fn familyOf(comptime Checker: type, checker: *Checker, ty: typed.Type) ?Family {
    if (ty.isInteger()) return .integer;
    if (numeric_surface.isFloat(ty, checker.catalog.records)) return .floating;
    if (ty.isAggregate() and checker.catalog.records[ty.recordIndex()].collection.kind == .string) return .text;
    return null;
}

/// Recognize the element type of a list argument the folds accept.
fn listElement(comptime Checker: type, checker: *Checker, ty: typed.Type, span: source.Span) Error!typed.Type {
    if (!ty.isAggregate() or !checker.catalog.records[ty.recordIndex()].isCollection()) return checker.sink.fail(unsupported, span, "this prelude builtin requires a list");
    const schema = checker.catalog.records[ty.recordIndex()];
    if (schema.collection.kind != .list) return checker.sink.fail(unsupported, span, "this prelude builtin requires a list of int, float or str values");
    return schema.shape.buffer.?;
}

/// Recognize the element type of a list or string argument `reversed` accepts.
fn sequenceElement(comptime Checker: type, checker: *Checker, ty: typed.Type, span: source.Span) Error!typed.Type {
    if (!ty.isAggregate() or !checker.catalog.records[ty.recordIndex()].isCollection()) return checker.sink.fail(unsupported, span, "reversed requires a list or str");
    const schema = checker.catalog.records[ty.recordIndex()];
    return switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .string => ty,
        else => checker.sink.fail(unsupported, span, "reversed requires a list or str"),
    };
}

const unsupported = "E_PRELUDE_TYPE";
const eArity = "E_ARITY";

/// Build one prelude builtin call, or null when a later recognizer owns this call.
fn buildCall(comptime Checker: type, checker: *Checker, span: source.Span, name: []const u8, arguments: []const typed.NodeId) Error!?typed.Node {
    // `abs` stays a float operation unless the argument is an integer.
    if (std.mem.eql(u8, name, "abs")) {
        if (arguments.len != 1) return checker.sink.fail(eArity, span, "abs requires one argument");
        const ty = nodeType(Checker, checker, arguments[0]);
        if (!ty.isInteger()) return null;
        const magnitude = try absInteger(Checker, checker, span, arguments[0], ty);
        return magnitude;
    }
    if (std.mem.eql(u8, name, "min")) {
        const smallest = try extreme(Checker, checker, span, arguments, false);
        return smallest;
    }
    if (std.mem.eql(u8, name, "max")) {
        const largest = try extreme(Checker, checker, span, arguments, true);
        return largest;
    }
    if (std.mem.eql(u8, name, "zip")) return checker.sink.fail(unsupported, span, "zip is only an iteration source: for a, b in zip(xs, ys)");
    if (std.mem.eql(u8, name, ord_builtin)) return @as(?typed.Node, try ordCall(Checker, checker, span, arguments));
    if (std.mem.eql(u8, name, chr_builtin)) return @as(?typed.Node, try chrCall(Checker, checker, span, arguments));
    if (std.mem.eql(u8, name, "sorted")) {
        if (arguments.len == 0 or arguments.len > 2) return checker.sink.failCallSite(eArity, span, "sorted requires a list and optional key callback", null, buffer_operations.sorted_signature);
        return @as(?typed.Node, try sorted(Checker, checker, span, arguments[0], if (arguments.len == 2) arguments[1] else null));
    }
    const input = try single(Checker, checker, span, name, arguments);
    const built: ?typed.Node = if (std.mem.eql(u8, name, "sum"))
        try sum(Checker, checker, span, input)
    else if (std.mem.eql(u8, name, "any"))
        try anyAll(Checker, checker, span, input, true)
    else if (std.mem.eql(u8, name, "all"))
        try anyAll(Checker, checker, span, input, false)
    else if (std.mem.eql(u8, name, reversed_builtin))
        try reversedList(Checker, checker, span, input)
    else if (std.mem.eql(u8, name, "round"))
        try roundFloat(Checker, checker, span, input)
    else
        null;
    if (built) |value| return value;
    return checker.sink.fail(unsupported, span, "this prelude builtin is not available in this position");
}
/// `ord(text)`: the one Unicode scalar value of a text argument. A one-scalar
/// text *literal* folds here to its `int`, so `b == ord("m")` is an immediate
/// compare with no allocation and no call; every other text becomes the
/// operation's owner, and the emitted length check traps `R_TEXT_SCALAR` when
/// the receiver does not hold exactly one scalar.
fn ordCall(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    const input = try ordArgument(Checker, checker, span, arguments);
    if (constantScalar(Checker, checker, input)) |point| return .{ .span = span, .ty = .i64, .data = .{ .integer = point } };
    const b = builder(Checker, checker, span);
    const owner = try b.local(nodeType(Checker, checker, input));
    return b.block(&.{try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } })}, try b.operation(owner, .text_ord, &.{}));
}

/// `chr(code)`: the one-scalar text for a Unicode scalar value. The owner is an
/// empty text that names the operation's family, the one argument is the code,
/// and an invalid code point is the runtime's located `R_TEXT_SCALAR` trap.
fn chrCall(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    if (arguments.len != 1) {
        const message = try std.fmt.allocPrint(checker.allocator, "`{s}(code: int) -> str` takes 1 argument, but this call passes {d}", .{ chr_builtin, arguments.len });
        return checker.sink.fail(eArity, span, message);
    }
    if (!nodeType(Checker, checker, arguments[0]).isInteger()) return checker.sink.fail(unsupported, span, "chr requires an integer code point");
    const text = checker.catalog.names.get("str") orelse return error.InternalError;
    const b = builder(Checker, checker, span);
    const owner = try b.local(text);
    const empty = try b.node(text, .{ .array = &.{} });
    return b.block(&.{try b.stmt(.{ .initialize = .{ .slot = owner, .value = empty } })}, try b.operation(owner, .text_chr, &.{arguments[0]}));
}

/// The single text argument `ord` takes, rejected with its own signature when
/// the call passes another count or a value that is not text.
fn ordArgument(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.NodeId {
    if (arguments.len != 1) {
        const message = try std.fmt.allocPrint(checker.allocator, "`ord(text: str) -> int` takes 1 argument, but this call passes {d}", .{arguments.len});
        return checker.sink.fail(eArity, span, message);
    }
    const ty = nodeType(Checker, checker, arguments[0]);
    if (!ty.isAggregate() or checker.catalog.records[ty.recordIndex()].collection.kind != .string)
        return checker.sink.fail(unsupported, span, "ord requires a str argument");
    return arguments[0];
}

/// The single scalar of an already-checked one-scalar text literal, or null when
/// the value is not a compile-time text of exactly one scalar. A text literal is
/// an `array` of its scalars, so a one-element array is the folded form.
fn constantScalar(comptime Checker: type, checker: *Checker, value: typed.NodeId) ?i128 {
    const node = checker.nodes.items[@backingInt(value)];
    if (node.data != .array or node.data.array.len != 1) return null;
    const element = checker.nodes.items[@backingInt(node.data.array[0])];
    if (element.data != .integer) return null;
    return element.data.integer;
}

fn single(comptime Checker: type, checker: *Checker, span: source.Span, name: []const u8, arguments: []const typed.NodeId) Error!typed.NodeId {
    if (arguments.len != 1) {
        const signature = preludeSignature(name) orelse name;
        const message = try std.fmt.allocPrint(checker.allocator, "`{s}` takes 1 argument, but this call passes {d}", .{ signature, arguments.len });
        return checker.sink.fail(eArity, span, message);
    }
    return arguments[0];
}

/// The checked shape of one prelude builtin whose only accepted count is one,
/// rendered the way a reader spells the call. Names outside this table keep the
/// bare name in their rejection.
fn preludeSignature(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "round")) return "round(value: float) -> float";
    if (std.mem.eql(u8, name, "sum")) return "sum(values: list[int]) -> int, or sum(values: list[float]) -> float";
    if (std.mem.eql(u8, name, "reversed")) return "reversed(values: list[T]) -> list[T], or reversed(text: str) -> str";
    if (std.mem.eql(u8, name, "any")) return "any(conditions: list[bool]) -> bool";
    if (std.mem.eql(u8, name, "all")) return "all(conditions: list[bool]) -> bool";
    return null;
}

/// `abs(x)` for an integer: the magnitude, trapping only on the unrepresentable minimum.
fn absInteger(comptime Checker: type, checker: *Checker, span: source.Span, value: typed.NodeId, ty: typed.Type) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const slot = try b.local(ty);
    const result = try b.local(ty);
    const read = try b.read(slot);
    const zero = try b.node(ty, .{ .integer = 0 });
    const negative = try b.binary(.lt, read, zero, .bool);
    const magnitude = try b.node(ty, .{ .unary = .{ .op = .neg, .operand = try b.read(slot), .op_span = span } });
    const invert = try b.stmt(.{ .assign = .{ .slot = result, .value = magnitude } });
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }),
        try b.stmt(.{ .initialize = .{ .slot = result, .value = try b.read(slot) } }),
        try b.stmt(.{ .branch = .{ .condition = negative, .then_body = invert, .else_body = null } }),
    }, try b.read(result));
}

/// `round(x)`: the nearest integral float, with halves rounded away from zero.
fn roundFloat(comptime Checker: type, checker: *Checker, span: source.Span, value: typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const floating = nodeType(Checker, checker, value);
    if (!numeric_surface.isFloat(floating, checker.catalog.records)) return checker.sink.fail(unsupported, span, "round requires a float argument");
    const nb = numericBuilder(Checker, checker, span, floating);
    const slot = try b.local(floating);
    const whole = try b.local(floating);
    const fraction = try b.local(floating);
    const result = try b.local(floating);
    const half = try nb.append(try nb.literal("0.5", checker.sink));
    const one = try nb.append(try nb.literal("1.0", checker.sink));
    const negative_one = try nb.append(try nb.literal("-1.0", checker.sink));
    const truncated = try nb.append(try nb.unary(.f64_trunc, try b.read(slot)));
    const remainder = try nb.append(try nb.binary(.sub, try b.read(slot), try b.read(whole), checker.sink));
    const up = try nb.append(try nb.binary(.add, try b.read(whole), one, checker.sink));
    const down = try nb.append(try nb.binary(.add, try b.read(whole), negative_one, checker.sink));
    const at_least_half = try nb.append(try nb.binary(.ge, try b.read(fraction), half, checker.sink));
    const at_most_half = try nb.append(try nb.binary(.le, try b.read(fraction), try nb.append(try nb.negate(half)), checker.sink));
    const above = try b.stmt(.{ .assign = .{ .slot = result, .value = up } });
    const below = try b.stmt(.{ .assign = .{ .slot = result, .value = down } });
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }),
        try b.stmt(.{ .initialize = .{ .slot = whole, .value = truncated } }),
        try b.stmt(.{ .initialize = .{ .slot = fraction, .value = remainder } }),
        try b.stmt(.{ .initialize = .{ .slot = result, .value = try b.read(whole) } }),
        try b.stmt(.{ .branch = .{ .condition = at_least_half, .then_body = above, .else_body = try b.stmt(.{ .branch = .{ .condition = at_most_half, .then_body = below, .else_body = null } }) } }),
    }, try b.read(result));
}

/// `sum(xs)`: every element added in order, starting from zero of the element type.
fn sum(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const element = try listElement(Checker, checker, nodeType(Checker, checker, input), span);
    const family = familyOf(Checker, checker, element) orelse return checker.sink.fail(unsupported, span, "sum requires a list of int or float values");
    if (family == .text) return checker.sink.fail(unsupported, span, "sum requires a list of int or float values");
    const floating = family == .floating;
    const list = try collections.listType(&checker.catalog, element, span);
    const owner = try b.local(list);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const total = try b.local(element);
    const nb = numericBuilder(Checker, checker, span, element);
    const zero = if (floating) try nb.append(try nb.literal("0.0", checker.sink)) else try b.node(element, .{ .integer = 0 });
    const i = try b.read(index);
    const guard = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
    const addend = try b.operation(owner, .read, &.{i});
    const added = if (floating)
        try nb.append(try nb.binary(.add, try b.read(total), addend, checker.sink))
    else
        try b.binary(.add, try b.read(total), addend, element);
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = total, .value = added } }),
    }) });
    const step = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    const loop = checker.loops.next;
    checker.loops.next += 1;
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = limit, .value = try b.length(owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = total, .value = zero } }),
        try b.stmt(.{ .loop = .{ .id = loop, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = body, .step = step } }),
    }, try b.read(total));
}

/// `any(xs)` and `all(xs)`: one Boolean fold over a list of conditions.
fn anyAll(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId, comptime is_any: bool) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const element = try listElement(Checker, checker, nodeType(Checker, checker, input), span);
    if (element != .bool) {
        const message = if (is_any) "any requires a list of bool values" else "all requires a list of bool values";
        return checker.sink.fail(unsupported, span, message);
    }
    const list = try collections.listType(&checker.catalog, element, span);
    const owner = try b.local(list);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const total = try b.local(.bool);
    const done = try b.local(.bool);
    const i = try b.read(index);
    const guard = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
    const folded = try b.binary(if (is_any) .logical_or else .logical_and, try b.read(total), try b.operation(owner, .read, &.{i}), .bool);
    // An answer is decided as soon as `any` sees true or `all` sees false, so
    // stop reading the rest of the list; the loop test re-reads `done`.
    const stop = if (is_any) folded else try b.node(.bool, .{ .unary = .{ .op = .not, .operand = folded, .op_span = span } });
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = total, .value = folded } }),
        try b.stmt(.{ .branch = .{
            .condition = stop,
            .then_body = try b.stmt(.{ .assign = .{ .slot = done, .value = try b.node(.bool, .{ .boolean = true }) } }),
            .else_body = null,
        } }),
    }) });
    const step = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    const loop = checker.loops.next;
    checker.loops.next += 1;
    const active = try b.binary(.logical_and, try b.binary(.lt, i, try b.read(limit), .bool), try b.node(.bool, .{
        .unary = .{ .op = .not, .operand = try b.read(done), .op_span = span },
    }), .bool);
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = limit, .value = try b.length(owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = total, .value = try b.node(.bool, .{ .boolean = !is_any }) } }),
        try b.stmt(.{ .initialize = .{ .slot = done, .value = try b.node(.bool, .{ .boolean = false }) } }),
        try b.stmt(.{ .loop = .{ .id = loop, .condition = active, .body = body, .step = step } }),
    }, try b.read(total));
}

/// Build the checked "left is less than right" test for one value family.
fn less(comptime Checker: type, checker: *Checker, span: source.Span, family: Family, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    const b = builder(Checker, checker, span);
    return switch (family) {
        .integer => try b.binary(.lt, left, right, .bool),
        .floating => try floatLess(Checker, checker, span, left, right),
        .text => try textLess(Checker, checker, span, left, right),
    };
}

/// `min` and `max` of two scalars, or of every element of a list.
fn extreme(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId, comptime greatest: bool) Error!typed.Node {
    if (arguments.len == 1) {
        const found = try extremeOfList(Checker, checker, span, arguments[0], greatest);
        return found;
    }
    if (arguments.len != 2) return checker.sink.failCallSite(eArity, span, "min and max take one list or two values", null, buffer_operations.extreme_signature);
    const left = arguments[0];
    const right = arguments[1];
    const ty = nodeType(Checker, checker, left);
    if (ty != nodeType(Checker, checker, right)) return checker.sink.fail(unsupported, span, "min and max require two values of the same type");
    const family = familyOf(Checker, checker, ty) orelse return checker.sink.fail(unsupported, span, "min and max require int, float or str values");
    const b = builder(Checker, checker, span);
    const result = try b.local(ty);
    const replace = comptime if (greatest) less else swapLess;
    const condition = try replace(Checker, checker, span, family, try b.read(result), right);
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = result, .value = left } }),
        try b.stmt(.{ .branch = .{
            .condition = condition,
            .then_body = try b.stmt(.{ .assign = .{ .slot = result, .value = right } }),
            .else_body = null,
        } }),
    }, try b.read(result));
}

fn swapLess(comptime Checker: type, checker: *Checker, span: source.Span, family: Family, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    return less(Checker, checker, span, family, right, left);
}

fn extremeOfList(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId, comptime greatest: bool) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const element = try listElement(Checker, checker, nodeType(Checker, checker, input), span);
    const family = familyOf(Checker, checker, element) orelse return checker.sink.fail(unsupported, span, "min and max require a list of int, float or str values");
    const list = try collections.listType(&checker.catalog, element, span);
    const owner = try b.local(list);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const result = try b.local(element);
    const i = try b.read(index);
    const guard = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
    const candidate = try b.operation(owner, .read, &.{i});
    const replace = comptime if (greatest) less else swapLess;
    const condition = try replace(Checker, checker, span, family, try b.read(result), candidate);
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .branch = .{
            .condition = condition,
            .then_body = try b.stmt(.{ .assign = .{ .slot = result, .value = try b.operation(owner, .read, &.{i}) } }),
            .else_body = null,
        } }),
    }) });
    const step = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    const loop = checker.loops.next;
    checker.loops.next += 1;
    // An empty list has no smallest element, and the first read reports it as a located trap.
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(1) } }),
        try b.stmt(.{ .initialize = .{ .slot = limit, .value = try b.length(owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = result, .value = try b.operation(owner, .read, &.{try b.integer(0)}) } }),
        try b.stmt(.{ .loop = .{ .id = loop, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = body, .step = step } }),
    }, try b.read(result));
}

/// `sorted(xs, key=callback)`: a stable ascending copy, optionally ordered by an integer key.
fn sorted(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId, key: ?typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const element = try listElement(Checker, checker, nodeType(Checker, checker, input), span);
    const family = if (key == null) familyOf(Checker, checker, element) orelse return checker.sink.fail(unsupported, span, "sorted requires a list of int, float or str values") else .integer;
    if (key == null) {
        const list = try collections.listType(&checker.catalog, element, span);
        const result = try b.local(list);
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = result, .value = try retain(Checker, checker, span, try b.slice(input, null, null)) } }),
            try b.stmt(.{ .discard = try b.operation(result, .sort, &.{}) }),
        }, try b.read(result));
    }
    if (key) |callback| {
        const contract = @import("callables.zig").signature(nodeType(Checker, checker, callback), checker.catalog.records) orelse return checker.sink.fail(unsupported, span, "sorted key requires a callback");
        if (contract.parameters.len != 1 or contract.parameters[0] != element or contract.return_type != .i64 or contract.effects != 0)
            return checker.sink.fail(unsupported, span, "sorted key requires def(T) -> int effects() for the list element type T");
    }
    const list = try collections.listType(&checker.catalog, element, span);
    const source_slot = try b.local(list);
    const target_slot = try b.local(list);
    const swap_slot = try b.local(list);
    const count = try b.local(.i64);
    const width = try b.local(.i64);
    const cursor = try b.local(.i64);
    const middle = try b.local(.i64);
    const end = try b.local(.i64);
    const left_cursor = try b.local(.i64);
    const right_cursor = try b.local(.i64);
    const left_value = try b.local(element);
    const right_value = try b.local(element);
    const key_slot = if (key) |callback| try b.local(nodeType(Checker, checker, callback)) else null;
    const n = try b.read(count);
    const w = try b.read(width);
    const i = try b.read(cursor);
    const fresh = try b.node(list, .{ .acquire_buffer = .{ .capacity = n } });
    const step_up = try b.binary(.add, w, w, .i64);
    // `middle` and `end` clamp one run to the end of the list.
    const middle_bound = try b.binary(.add, i, w, .i64);
    const end_bound = try b.binary(.add, i, step_up, .i64);
    const both = try b.binary(.logical_and, try b.binary(.lt, try b.read(left_cursor), try b.read(middle), .bool), try b.binary(.lt, try b.read(right_cursor), try b.read(end), .bool), .bool);
    const right_order = if (key_slot) |slot| try invokeKey(Checker, checker, span, try b.read(slot), try b.read(right_value)) else try b.read(right_value);
    const left_order = if (key_slot) |slot| try invokeKey(Checker, checker, span, try b.read(slot), try b.read(left_value)) else try b.read(left_value);
    const take_right = try less(Checker, checker, span, family, right_order, left_order);
    const merge = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .assign = .{ .slot = left_value, .value = try b.operation(source_slot, .read, &.{try b.read(left_cursor)}) } }),
        try b.stmt(.{ .assign = .{ .slot = right_value, .value = try b.operation(source_slot, .read, &.{try b.read(right_cursor)}) } }),
        try b.stmt(.{ .branch = .{
            .condition = take_right,
            .then_body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
                try b.stmt(.{ .discard = try b.operation(target_slot, .append, &.{try b.read(right_value)}) }),
                try b.stmt(.{ .assign = .{ .slot = right_cursor, .value = try b.binary(.add, try b.read(right_cursor), try b.integer(1), .i64) } }),
            }) }),
            .else_body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
                try b.stmt(.{ .discard = try b.operation(target_slot, .append, &.{try b.read(left_value)}) }),
                try b.stmt(.{ .assign = .{ .slot = left_cursor, .value = try b.binary(.add, try b.read(left_cursor), try b.integer(1), .i64) } }),
            }) }),
        } }),
    }) });
    const drain_left = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .discard = try b.operation(target_slot, .append, &.{try b.operation(source_slot, .read, &.{try b.read(left_cursor)})}) }),
        try b.stmt(.{ .assign = .{ .slot = left_cursor, .value = try b.binary(.add, try b.read(left_cursor), try b.integer(1), .i64) } }),
    }) });
    const drain_right = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .discard = try b.operation(target_slot, .append, &.{try b.operation(source_slot, .read, &.{try b.read(right_cursor)})}) }),
        try b.stmt(.{ .assign = .{ .slot = right_cursor, .value = try b.binary(.add, try b.read(right_cursor), try b.integer(1), .i64) } }),
    }) });
    const run = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .assign = .{ .slot = middle, .value = middle_bound } }),
        try b.stmt(.{ .branch = .{
            .condition = try b.binary(.lt, middle_bound, n, .bool),
            .then_body = try b.stmt(.{ .assign = .{ .slot = middle, .value = middle_bound } }),
            .else_body = try b.stmt(.{ .assign = .{ .slot = middle, .value = n } }),
        } }),
        try b.stmt(.{ .assign = .{ .slot = end, .value = end_bound } }),
        try b.stmt(.{ .branch = .{
            .condition = try b.binary(.lt, end_bound, n, .bool),
            .then_body = try b.stmt(.{ .assign = .{ .slot = end, .value = end_bound } }),
            .else_body = try b.stmt(.{ .assign = .{ .slot = end, .value = n } }),
        } }),
        try b.stmt(.{ .assign = .{ .slot = left_cursor, .value = i } }),
        try b.stmt(.{ .assign = .{ .slot = right_cursor, .value = try b.read(middle) } }),
        try b.stmt(.{ .loop = .{
            .id = loopId(Checker, checker),
            .condition = both,
            .body = merge,
            .step = null,
        } }),
        try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try b.binary(.lt, try b.read(left_cursor), try b.read(middle), .bool), .body = drain_left, .step = null } }),
        try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try b.binary(.lt, try b.read(right_cursor), try b.read(end), .bool), .body = drain_right, .step = null } }),
        try b.stmt(.{ .assign = .{ .slot = cursor, .value = try b.read(end) } }),
    }) });
    const pass = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .discard = try b.operation(target_slot, .clear, &.{}) }),
        try b.stmt(.{ .assign = .{ .slot = cursor, .value = try b.integer(0) } }),
        try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try b.binary(.lt, try b.read(cursor), n, .bool), .body = run, .step = null } }),
        try b.stmt(.{ .assign = .{ .slot = swap_slot, .value = try b.read(source_slot) } }),
        try b.stmt(.{ .assign = .{ .slot = source_slot, .value = try b.read(target_slot) } }),
        try b.stmt(.{ .assign = .{ .slot = target_slot, .value = try b.read(swap_slot) } }),
        try b.stmt(.{ .assign = .{ .slot = width, .value = step_up } }),
    }) });
    var setup: std.ArrayList(typed.StatementId) = .empty;
    try setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = source_slot, .value = try retain(Checker, checker, span, try b.slice(input, null, null)) } }));
    if (key_slot) |slot| try setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = key.? } }));
    try setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = count, .value = try b.length(source_slot) } }));
    try setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = target_slot, .value = fresh } }));
    try setup.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = width, .value = try b.integer(1) } }));
    try setup.append(checker.allocator, try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try b.binary(.lt, try b.read(width), n, .bool), .body = pass, .step = null } }));
    return b.block(setup.items, try b.read(source_slot));
}

fn invokeKey(comptime Checker: type, checker: *Checker, span: source.Span, callback: typed.NodeId, value: typed.NodeId) Error!typed.NodeId {
    const b = builder(Checker, checker, span);
    const arguments = try checker.allocator.dupe(typed.NodeId, &.{value});
    return b.node(.i64, .{ .invoke = .{ .callee = callback, .arguments = arguments } });
}

fn loopId(comptime Checker: type, checker: *Checker) usize {
    const id = checker.loops.next;
    checker.loops.next += 1;
    return id;
}

/// `reversed(xs)`: a new list holding the elements of `xs` from last to first.
fn reversedList(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const input_type = nodeType(Checker, checker, input);
    const element = try sequenceElement(Checker, checker, input_type, span);
    const list = try collections.listType(&checker.catalog, element, span);
    const owner = try b.local(input_type);
    const output = try b.local(list);
    const index = try b.local(.i64);
    const count = try b.local(.i64);
    const i = try b.read(index);
    const guard = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(count)}) });
    const position = try b.binary(.sub, try b.binary(.sub, try b.read(count), try b.integer(1), .i64), i, .i64);
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .discard = try b.operation(output, .append, &.{try b.operation(owner, .read, &.{position})}) }),
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    const loop = loopId(Checker, checker);
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = owner, .value = input } }),
        try b.stmt(.{ .initialize = .{ .slot = output, .value = try b.node(list, .{ .acquire_buffer = .{ .capacity = try b.length(owner) } }) } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = count, .value = try b.length(owner) } }),
        try b.stmt(.{ .loop = .{ .id = loop, .condition = try b.binary(.lt, i, try b.read(count), .bool), .body = body, .step = null } }),
    }, try b.read(output));
}

/// `list(range(end))` and `list(range(start, end))`: the counted range as a new list.
fn rangeListCall(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    if (arguments.len == 0 or arguments.len > 2) return checker.sink.failCallSite(eArity, span, "range requires end or start, end", null, buffer_operations.range_signature);
    const b = builder(Checker, checker, span);
    for (arguments) |argument| if (!nodeType(Checker, checker, argument).isInteger()) return checker.sink.fail(unsupported, span, "range bounds require integers");
    if (arguments.len == 2 and nodeType(Checker, checker, arguments[0]) != nodeType(Checker, checker, arguments[1])) return checker.sink.fail(unsupported, span, "range bounds require one integer type");
    const element = nodeType(Checker, checker, arguments[arguments.len - 1]);
    const list = try collections.listType(&checker.catalog, element, span);
    const start = try b.local(element);
    const limit = try b.local(element);
    const index = try b.local(element);
    const output = try b.local(list);
    const i = try b.read(index);
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .discard = try b.operation(output, .append, &.{i}) }),
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), element) } }),
    }) });
    const bind = if (arguments.len == 2) arguments[0] else try b.node(element, .{ .integer = 0 });
    const loop = loopId(Checker, checker);
    const capacity = try b.rangeCapacity(try b.read(start), try b.read(limit), element);
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = start, .value = bind } }),
        try b.stmt(.{ .initialize = .{ .slot = limit, .value = arguments[arguments.len - 1] } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.read(start) } }),
        try b.stmt(.{ .initialize = .{ .slot = output, .value = try b.node(list, .{ .acquire_buffer = .{ .capacity = capacity } }) } }),
        try b.stmt(.{ .loop = .{ .id = loop, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = body, .step = null } }),
    }, try b.read(output));
}

/// `list(xs)`: an independent copy of a list.
fn copyListCall(comptime Checker: type, checker: *Checker, span: source.Span, input: typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const ty = nodeType(Checker, checker, input);
    const views = @import("dictionary_views.zig");
    if (views.identify(checker.catalog, ty)) |kind| if (kind != .item) return views.snapshot(Checker, checker, span, input, kind);
    const sequence = ty.isAggregate() and checker.catalog.records[ty.recordIndex()].isCollection();
    if (!sequence or checker.catalog.records[ty.recordIndex()].collection.kind != .list)
        return checker.sink.fail(unsupported, span, "list requires a list, range, reversed source or dictionary view");
    return b.slice(input, null, null);
}

/// Compare two texts the way `sort.compare_strs` does, by Unicode code point order.
fn textLess(comptime Checker: type, checker: *Checker, span: source.Span, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    return builder(Checker, checker, span).binary(.lt, left, right, .bool);
}

fn shortLength(comptime Checker: type, checker: *Checker, span: source.Span, left: typed.NodeId, right: typed.NodeId) Error!typed.NodeId {
    const b = builder(Checker, checker, span);
    const slot = try b.local(.i64);
    const smaller = try b.stmt(.{ .assign = .{ .slot = slot, .value = left } });
    return retain(Checker, checker, span, try b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = slot, .value = right } }),
        try b.stmt(.{ .branch = .{ .condition = try b.binary(.lt, left, right, .bool), .then_body = smaller, .else_body = null } }),
    }, try b.read(slot)));
}

/// Reserve the slots of one list walk before its body binds an iteration name.
fn reserveWalkCall(comptime Checker: type, checker: *Checker, span: source.Span, list: typed.Type) Error!Walk {
    const b = builder(Checker, checker, span);
    const element = try elementOf(Checker, checker, list, span);
    return .{
        .owner = try b.local(list),
        .index = try b.local(.i64),
        .limit = try b.local(.i64),
        .slot = try b.local(element),
        .loop = loopId(Checker, checker),
    };
}

/// Assemble the statements that walk `input` into `walk`, in either direction.
fn walkStatementsCall(comptime Checker: type, checker: *Checker, step: Step) Error![]const typed.StatementId {
    const span = step.span;
    const input = step.input;
    const walk = step.walk;
    const descending = step.descending;
    const body = step.body;
    const b = builder(Checker, checker, span);
    const i = try b.read(walk.index);
    const count = try b.read(walk.limit);
    const guard = try b.stmt(.{ .discard = try b.operation(walk.owner, .iteration_check, &.{count}) });
    const position = if (descending) try b.binary(.sub, try b.binary(.sub, count, try b.integer(1), .i64), i, .i64) else i;
    const iteration = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .initialize = .{ .slot = walk.slot, .value = try b.operation(walk.owner, .read, &.{position}) } }),
        body,
    }) });
    const advance = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = walk.index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    return keep(Checker, checker, &.{
        try b.stmt(.{ .initialize = .{ .slot = walk.owner, .value = input } }),
        try b.stmt(.{ .initialize = .{ .slot = walk.index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = walk.limit, .value = try b.length(walk.owner) } }),
        try b.stmt(.{ .loop = .{ .id = walk.loop, .condition = try b.binary(.lt, i, count, .bool), .body = iteration, .step = advance } }),
    });
}

/// Reserve the slots of a parallel walk over two lists.
fn reserveZipCall(comptime Checker: type, checker: *Checker, span: source.Span, left_list: typed.Type, right_list: typed.Type) Error!Zip {
    const left = try reserveWalkCall(Checker, checker, span, left_list);
    const right = try reserveWalkCall(Checker, checker, span, right_list);
    const limit = try builder(Checker, checker, span).local(.i64);
    return .{ .left = left, .right = right, .limit = limit };
}

/// Element type of a sequence the iteration builtins walk over. A string walks
/// one code point at a time, so its element type is the string type itself.
fn elementOf(comptime Checker: type, checker: *Checker, list: typed.Type, span: source.Span) Error!typed.Type {
    if (!list.isAggregate() or !checker.catalog.records[list.recordIndex()].isCollection()) return checker.sink.fail(unsupported, span, "iteration requires a list or str");
    const schema = checker.catalog.records[list.recordIndex()];
    return switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .string => list,
        else => checker.sink.fail(unsupported, span, "iteration requires a list or str"),
    };
}

/// Assemble the statements that walk two lists in step, stopping at the shorter.
fn zipStatementsCall(comptime Checker: type, checker: *Checker, step: ZipStep) Error![]const typed.StatementId {
    const span = step.span;
    const left_input = step.left;
    const right_input = step.right;
    const zip = step.zip;
    const body = step.body;
    const b = builder(Checker, checker, span);
    const i = try b.read(zip.left.index);
    const guard = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .discard = try b.operation(zip.left.owner, .iteration_check, &.{try b.read(zip.left.limit)}) }),
        try b.stmt(.{ .discard = try b.operation(zip.right.owner, .iteration_check, &.{try b.read(zip.right.limit)}) }),
    }) });
    const iteration = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .initialize = .{ .slot = zip.left.slot, .value = try b.operation(zip.left.owner, .read, &.{i}) } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.right.slot, .value = try b.operation(zip.right.owner, .read, &.{i}) } }),
        body,
    }) });
    const advance = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        guard,
        try b.stmt(.{ .assign = .{ .slot = zip.left.index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    return keep(Checker, checker, &.{
        try b.stmt(.{ .initialize = .{ .slot = zip.left.owner, .value = left_input } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.right.owner, .value = right_input } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.left.limit, .value = try b.length(zip.left.owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.right.limit, .value = try b.length(zip.right.owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.limit, .value = try shortLength(Checker, checker, span, try b.read(zip.left.limit), try b.read(zip.right.limit)) } }),
        try b.stmt(.{ .initialize = .{ .slot = zip.left.index, .value = try b.integer(0) } }),
        try b.stmt(.{ .loop = .{ .id = zip.left.loop, .condition = try b.binary(.lt, i, try b.read(zip.limit), .bool), .body = iteration, .step = advance } }),
    });
}
