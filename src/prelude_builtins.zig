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
const callables = @import("callables.zig");
const record_layouts = @import("record_layouts.zig");
const range_step = @import("range_step.zig");
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
    inline for (.{ "sum", "min", "max", "sorted", "abs", "round", "any", "all", reversed_builtin, "list", "set", "dict", "zip", "repr", ord_builtin, chr_builtin }) |builtin| {
        if (std.mem.eql(u8, name, builtin)) return true;
    }
    return false;
}

/// Names whose single argument is a sequence the prelude materialises as a new list.
pub fn materializes(name: []const u8) bool {
    return std.mem.eql(u8, name, "list") or std.mem.eql(u8, name, "set");
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
        /// `sorted(...)`: a sorted copy of one list, keyed or descending as asked.
        pub fn sorted(self: @This(), call: SortedCall) Error!typed.Node {
            return sortedCall(Checker, self.checker, call);
        }
        /// `values.sort(key=..., reverse=...)`: the statements of one keyed or
        /// descending in-place sort.
        pub fn keyedSort(self: @This(), sort: KeyedSort) Error![]const typed.StatementId {
            return keyedSortCall(Checker, self.checker, sort);
        }
        /// The key type a checked `key=` callback returns, or a diagnostic when
        /// it does not map one list element to an ordered key.
        pub fn sortKey(self: @This(), span: source.Span, element: typed.Type, callback: typed.NodeId) Error!typed.Type {
            return keyType(Checker, self.checker, span, element, callback);
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
    if (std.mem.eql(u8, name, "repr")) return @as(?typed.Node, try reprCall(Checker, checker, span, arguments));
    if (std.mem.eql(u8, name, ord_builtin)) return @as(?typed.Node, try ordCall(Checker, checker, span, arguments));
    if (std.mem.eql(u8, name, chr_builtin)) return @as(?typed.Node, try chrCall(Checker, checker, span, arguments));
    if (std.mem.eql(u8, name, "round") and arguments.len == 2) return @as(?typed.Node, try roundDigits(Checker, checker, span, arguments));
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
    if (std.mem.eql(u8, name, "round")) return "round(value: float) -> float, or round(value: float, ndigits: int) -> float";
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

/// PRELUDE-ROUND-2: `round(x, n)`, the float nearest `x`'s exact binary value
/// rounded to `n` decimal digits with halves away from zero, `n` negative
/// rounding left of the point. The owner is the empty text naming the runtime
/// family, as `chr`'s is; the arguments are the float and the digit count.
fn roundDigits(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    const floating = nodeType(Checker, checker, arguments[0]);
    if (!numeric_surface.isFloat(floating, checker.catalog.records)) return checker.sink.fail(unsupported, span, "round requires a float argument");
    const digits_type = nodeType(Checker, checker, arguments[1]);
    if (!digits_type.isInteger()) return checker.sink.fail(unsupported, span, "round's digit count must be an integer");
    const b = builder(Checker, checker, span);
    const digits = if (digits_type == .i64) arguments[1] else try b.node(.i64, .{ .cast = arguments[1] });
    const text = checker.catalog.names.get("str") orelse return error.InternalError;
    const owner = try b.local(text);
    const empty = try b.node(text, .{ .array = &.{} });
    return b.block(&.{try b.stmt(.{ .initialize = .{ .slot = owner, .value = empty } })}, try b.operation(owner, .float_round, &.{ arguments[0], digits }));
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
    // PRELUDE-EXTREME-2: each argument evaluates once, left to right; the
    // comparison and the replacement both read the second one's temporary.
    const other = try b.local(ty);
    const replace = comptime if (greatest) less else swapLess;
    const condition = try replace(Checker, checker, span, family, try b.read(result), try b.read(other));
    return b.block(&.{
        try b.stmt(.{ .initialize = .{ .slot = result, .value = left } }),
        try b.stmt(.{ .initialize = .{ .slot = other, .value = right } }),
        try b.stmt(.{ .branch = .{
            .condition = condition,
            .then_body = try b.stmt(.{ .assign = .{ .slot = result, .value = try b.read(other) } }),
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

/// `sorted(xs)`, `sorted(xs, key=callback)` and `sorted(xs, reverse=flag)`: a
/// stable copy of the list, ordered by the elements themselves or by the key
/// each one maps to. The copy is then sorted in place exactly as
/// `values.sort(...)` sorts, so both spellings share one engine.
fn sortedCall(comptime Checker: type, checker: *Checker, call: SortedCall) Error!typed.Node {
    const span = call.sort.span;
    const b = builder(Checker, checker, span);
    const element = try listElement(Checker, checker, nodeType(Checker, checker, call.input), span);
    if (call.sort.key == null and (element == .bool or !orderedField(Checker, checker, element)))
        return checker.sink.fail(unsupported, span, "sorted requires a list of int, float, str or bytes values, or a key=callback that maps each element to one");
    const list = try collections.listType(&checker.catalog, element, span);
    const result = try b.local(list);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    if (call.sort.key == null and call.sort.reverse == null) {
        try statements.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = result, .value = try retain(Checker, checker, span, try b.slice(call.input, null, null)) } }));
        try statements.append(checker.allocator, try b.stmt(.{ .discard = try b.operation(result, .sort, &.{}) }));
    } else {
        // A keyed copy is gathered already sorted from the original list into
        // a new one, so no copy is made only to be permuted.
        const original = try b.local(nodeType(Checker, checker, call.input));
        try statements.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = original, .value = call.input } }));
        var sort = call.sort;
        sort.owner = result;
        sort.source = original;
        try statements.appendSlice(checker.allocator, try keyedSortCall(Checker, checker, sort));
    }
    return b.block(statements.items, try b.read(result));
}

/// One `sorted(...)` call: the checked list argument and the sort it asks for,
/// whose `owner` the copy replaces.
pub const SortedCall = struct { input: typed.NodeId, sort: KeyedSort };

/// One keyed or descending sort: the list local it orders — or, when
/// `source` names the original list, the fresh local its sorted copy is
/// gathered into — the checked key callback (null to order by the elements
/// themselves), the checked `reverse` flag (null for ascending), and whether
/// `reverse=` was written before `key=`, which is the order the two are
/// evaluated in.
pub const KeyedSort = struct {
    span: source.Span,
    owner: typed.LocalId,
    source: ?typed.LocalId = null,
    key: ?typed.NodeId = null,
    reverse: ?typed.NodeId = null,
    reverse_first: bool = false,
};

/// Whether a key field type has an order the native keyed sort compares:
/// every integer width, `bool`, `float`, `str` and `bytes`.
fn orderedField(comptime Checker: type, checker: *Checker, ty: typed.Type) bool {
    if (ty.isInteger() or ty == .bool) return true;
    if (ty.isAggregate() and typed.isByteString(checker.catalog.records[ty.recordIndex()])) return true;
    return familyOf(Checker, checker, ty) != null;
}

/// Whether a key type is ordered: one ordered field, or a flat tuple of them,
/// compared field by field.
pub fn orderedKey(comptime Checker: type, checker: *Checker, ty: typed.Type) bool {
    if (orderedField(Checker, checker, ty)) return true;
    const tuple = record_layouts.tupleRecord(checker.catalog.records, ty) orelse return false;
    for (tuple.fields) |field| if (!orderedField(Checker, checker, field.ty)) return false;
    return true;
}

const eSortKey = "E_SORT_KEY";

/// Check a checked `key=` argument against the list element type and answer
/// the key type it returns. A key takes exactly one element, never as `mut`,
/// and returns an ordered key: an integer, `bool`, `float`, `str`, or a flat
/// tuple of those.
pub fn keyType(comptime Checker: type, checker: *Checker, span: source.Span, element: typed.Type, callback: typed.NodeId) Error!typed.Type {
    const contract = callables.signature(nodeType(Checker, checker, callback), checker.catalog.records) orelse
        return checker.sink.fail(eSortKey, span, "key= takes a function or lambda of one list element that returns its sort key");
    const element_name = try typed.surfaceTypeName(checker.allocator, element, checker.catalog.records);
    if (contract.parameters.len != 1 or contract.parameters[0] != element) {
        const message = try std.fmt.allocPrint(checker.allocator, "the key must take exactly one `{s}`, the list's element type: def(item: {s}) -> K", .{ element_name, element_name });
        return checker.sink.fail(eSortKey, span, message);
    }
    if (contract.mutates.len != 0) return checker.sink.fail(eSortKey, span, "a sort key reads its element and must not declare it `mut`");
    if (!orderedKey(Checker, checker, contract.return_type)) {
        const found = try typed.surfaceTypeName(checker.allocator, contract.return_type, checker.catalog.records);
        const message = try std.fmt.allocPrint(checker.allocator, "the key returns `{s}`, which has no order; return an int, float, str, bytes or bool, or a tuple of them", .{found});
        return checker.sink.fail(eSortKey, span, message);
    }
    return contract.return_type;
}

/// Build one keyed or descending sort. Every key is computed exactly once, in
/// input order, into one key list sized to the list; the native keyed sort
/// then orders positions by key and moves the elements into place, or, for a
/// sorted copy (`sort.source`), gathers them in order into a new list of the
/// same size. Without a key the list is its own key list.
pub fn keyedSortCall(comptime Checker: type, checker: *Checker, sort: KeyedSort) Error![]const typed.StatementId {
    const b = builder(Checker, checker, sort.span);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const input = sort.source orelse sort.owner;
    const flag = try b.local(.bool);
    const flag_value = sort.reverse orelse try b.node(.bool, .{ .boolean = false });
    const flag_init = try b.stmt(.{ .initialize = .{ .slot = flag, .value = flag_value } });
    const count = try b.local(.i64);
    const count_init = try b.stmt(.{ .initialize = .{ .slot = count, .value = try b.length(input) } });
    const callback = sort.key orelse {
        try statements.appendSlice(checker.allocator, &.{ flag_init, count_init });
        try statements.appendSlice(checker.allocator, try keyedPlacement(Checker, checker, sort, .{ .keys = input, .flag = flag, .count = count }));
        return statements.items;
    };
    const callback_type = nodeType(Checker, checker, callback);
    const key_type = (callables.signature(callback_type, checker.catalog.records) orelse return error.InternalError).return_type;
    const key_slot = try b.local(callback_type);
    const key_init = try b.stmt(.{ .initialize = .{ .slot = key_slot, .value = callback } });
    try statements.appendSlice(checker.allocator, if (sort.reverse_first) &.{ flag_init, key_init } else &.{ key_init, flag_init });
    const key_list = try collections.listType(&checker.catalog, key_type, sort.span);
    const keys = try b.local(key_list);
    const index = try b.local(.i64);
    const i = try b.read(index);
    // The element is held in its own local across the key call, the way a
    // `for` loop binds it, so every managed value it carries stays rooted
    // while the key allocates.
    const element = try b.local(listElementType(Checker, checker, input));
    const key = try b.node(key_type, .{ .invoke = .{
        .callee = try b.read(key_slot),
        .arguments = try checker.allocator.dupe(typed.NodeId, &.{try b.read(element)}),
    } });
    const body = try b.stmt(.{ .block = try keep(Checker, checker, &.{
        try b.stmt(.{ .assign = .{ .slot = element, .value = try b.operation(input, .read, &.{i}) } }),
        try b.stmt(.{ .discard = try b.operation(keys, .append, &.{key}) }),
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
    }) });
    try statements.appendSlice(checker.allocator, &.{
        count_init,
        try b.stmt(.{ .initialize = .{ .slot = keys, .value = try b.node(key_list, .{ .acquire_buffer = .{ .capacity = try b.read(count) } }) } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try b.binary(.lt, i, try b.read(count), .bool), .body = body, .step = null } }),
    });
    try statements.appendSlice(checker.allocator, try keyedPlacement(Checker, checker, sort, .{ .keys = keys, .flag = flag, .count = count }));
    return statements.items;
}

/// The locals the native keyed sort reads once the keys exist.
const Placement = struct { keys: typed.LocalId, flag: typed.LocalId, count: typed.LocalId };

/// The native keyed sort itself: in place on `sort.owner`, or, for a sorted
/// copy, first a new empty list with room for every element in `sort.owner`,
/// which the sort fills from `sort.source` in order.
fn keyedPlacement(comptime Checker: type, checker: *Checker, sort: KeyedSort, placement: Placement) Error![]const typed.StatementId {
    const b = builder(Checker, checker, sort.span);
    const input = sort.source orelse sort.owner;
    const operation = try b.stmt(.{ .discard = try b.operation(sort.owner, .sort_keyed, &.{ try b.read(input), try b.read(placement.keys), try b.read(placement.flag) }) });
    if (sort.source == null) return keep(Checker, checker, &.{operation});
    const list = checker.locals.items[@backingInt(sort.owner)].ty;
    const fresh = try b.node(list, .{ .acquire_buffer = .{ .capacity = try b.read(placement.count) } });
    return keep(Checker, checker, &.{ try b.stmt(.{ .initialize = .{ .slot = sort.owner, .value = fresh } }), operation });
}

/// The element type of the list a local holds.
fn listElementType(comptime Checker: type, checker: *Checker, owner: typed.LocalId) typed.Type {
    const list = checker.locals.items[@backingInt(owner)].ty;
    return checker.catalog.records[list.recordIndex()].shape.buffer.?;
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
    if (arguments.len == 0 or arguments.len > 3) return checker.sink.failCallSite(eArity, span, "range requires end; start, end; or start, end, step", null, buffer_operations.range_signature);
    const b = builder(Checker, checker, span);
    for (arguments) |argument| if (!nodeType(Checker, checker, argument).isInteger()) return checker.sink.fail(unsupported, span, "range bounds require integers");
    for (arguments[1..]) |argument| if (nodeType(Checker, checker, arguments[0]) != nodeType(Checker, checker, argument)) return checker.sink.fail(unsupported, span, "range bounds require one integer type");
    if (arguments.len == 3) return steppedRangeList(Checker, checker, span, arguments);
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

/// PY-RANGE-STEP-1: `list(range(start, stop, step))`, counting in the step's
/// direction through the same loop a stepped `for` uses.
fn steppedRangeList(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    const b = builder(Checker, checker, span);
    const element = nodeType(Checker, checker, arguments[0]);
    const list = try collections.listType(&checker.catalog, element, span);
    const index = try b.local(element);
    const limit = try b.local(element);
    const output = try b.local(list);
    const lower: range_step.Lower(Checker) = .{ .b = b, .element = element, .stride = try range_step.stride(Checker, b, constantInteger(Checker, checker, arguments[2]), element) };
    const body = try b.stmt(.{ .discard = try b.operation(output, .append, &.{try b.read(index)}) });
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = index, .value = arguments[0] } }));
    try statements.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = limit, .value = arguments[1] } }));
    try statements.appendSlice(checker.allocator, try lower.setup(arguments[2]));
    try statements.append(checker.allocator, try b.stmt(.{ .initialize = .{ .slot = output, .value = try b.node(list, .{ .acquire_buffer = .{ .capacity = try b.integer(0) } }) } }));
    try statements.append(checker.allocator, try b.stmt(.{ .loop = .{ .id = loopId(Checker, checker), .condition = try lower.condition(index, limit), .body = body, .step = try lower.advance(index, limit) } }));
    return b.block(statements.items, try b.read(output));
}

/// The value of a checked integer literal, negated or not, or null for any
/// value the checker does not know.
fn constantInteger(comptime Checker: type, checker: *Checker, value: typed.NodeId) ?i128 {
    const node = checker.nodes.items[@backingInt(value)];
    return switch (node.data) {
        .integer => |known| known,
        .unary => |unary| if (unary.op == .neg and checker.nodes.items[@backingInt(unary.operand)].data == .integer) -checker.nodes.items[@backingInt(unary.operand)].data.integer else null,
        else => null,
    };
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

/// Exact Python scalar repr keeps the ordinary printing and str paths unchanged.
fn reprCall(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    if (arguments.len != 1) return checker.sink.fail("E_ARITY", span, "repr requires one scalar argument");
    const input = arguments[0];
    const ty = nodeType(Checker, checker, input);
    const text = try collections.preludeType(&checker.catalog, "str", span);
    const b = builder(Checker, checker, span);
    if (ty.isInteger() or ty == .bool)
        return .{ .span = span, .ty = text, .data = .{ .cast = input } };
    if (numeric_surface.isFloat(ty, checker.catalog.records)) {
        const word = try b.node(.i64, .{ .integer = @intCast(@import("format_spec.zig").pack(.{ .family = .float })) });
        const bits = try b.node(.u64, .{ .unwrap = input });
        const empty = try b.node(text, .{ .array = &.{} });
        return b.access(empty, .number_format, &.{ bits, word }, false);
    }
    if (ty.isAggregate()) {
        const schema = checker.catalog.records[ty.recordIndex()];
        if (schema.collection.kind == .string or typed.isByteString(schema)) return b.access(input, .text_repr, &.{}, false);
    }
    return checker.sink.fail("E_REPR_TYPE", span, "repr accepts str, bytes, int, float and bool; collections and records have no repr yet");
}
