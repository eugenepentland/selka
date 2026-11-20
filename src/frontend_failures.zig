//! Lower source failure clauses and optional injection to existing nominal variants.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("type_catalog.zig").Catalog;

/// Intern the ordinary Result identity used by a source failure clause.
pub fn resultType(catalog: *Catalog, allocator: std.mem.Allocator, success: typed.Type, failure: typed.Type, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!typed.Type {
    _ = allocator;
    _ = sink;
    const store = catalog.templates.store orelse return error.InternalError;
    return @import("nominal_catalog.zig").instantiateLengths(catalog, store.index.names.get("Result") orelse return error.InternalError, &.{ success, failure }, &.{}, span);
}

fn variant(comptime Checker: type, self: *Checker, value: typed.NodeId, destination: typed.Type, tag: usize, span: source.Span) diagnostic.Error!typed.NodeId {
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = destination, .data = .{ .variant = .{ .tag = tag, .value = value } } });
    return id;
}

/// Wrap a successful value only for a failure-declared source function.
pub fn wrapSuccess(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) diagnostic.Error!typed.NodeId {
    if (self.failure_type == null) return value;
    const shape = typed.resultShape(self.return_type, self.catalog.records) orelse return error.InternalError;
    return variant(Checker, self, value, self.return_type, shape.ok_tag, span);
}

/// Check an ordinary successful return and lower its explicit failure contract.
pub fn checkReturn(comptime Checker: type, self: *Checker, expression: ast.NodeId, span: source.Span) diagnostic.Error!typed.NodeId {
    const expected = if (self.failure_type != null) self.success_type else self.return_type;
    if (expected == .unit) try refuseUnitValue(Checker, self, expression, span);
    const value = try self.expressionExpected(expression, expected);
    try self.requireNode(value, expected, span, null);
    try self.moveTemporaryElement(expression, value);
    try @import("option_flow.zig").moveReturned(Checker, self, expression, value, span);
    return wrapSuccess(Checker, self, value, span);
}

/// The message of `return Unit()` or `return unit` in a function whose successful result is `Unit`.
pub const unit_value_message = "`Unit` has no constructor and no value named `unit`: a function that returns `Unit` " ++
    "ends with a bare `return` (its one value is written `()`)";

/// Refuse `return Unit()`, `return Unit` and `return unit` in a function whose successful result is `Unit` (F-41), with
/// the certain edit that deletes the value and leaves a bare `return`. Only a spelling that names nothing in scope is
/// refused here: a declared `Unit` or `unit` keeps its ordinary check and diagnostic.
fn refuseUnitValue(comptime Checker: type, self: *Checker, expression: ast.NodeId, span: source.Span) diagnostic.Error!void {
    const node = self.syntax.nodes.items[@backingInt(expression)];
    const name = switch (node.data) {
        .call => |call| if (call.owner == null and call.arguments.len == 0 and call.type_arguments.len == 0) call.name else return,
        .name => |spelled| spelled,
        else => return,
    };
    const text = self.src.text(name);
    if (!std.mem.eql(u8, text, "Unit") and !std.mem.eql(u8, text, "unit")) return;
    if (self.active.contains(text) or try self.topLevel(name)) return;
    // The statement starts at its `return` keyword; the edit deletes from the keyword's end to the value's end.
    const keyword = "return";
    if (span.end < node.span.end or !std.mem.startsWith(u8, self.src.text(span), keyword)) return self.sink.fail("E_UNKNOWN_FUNCTION", name, unit_value_message);
    const deleted: source.Span = .{ .start = span.start + keyword.len, .end = node.span.end };
    return self.sink.failFix("E_UNKNOWN_FUNCTION", name, unit_value_message, .{ .span = deleted, .text = "" });
}

/// The code of a `try` or `fail value` refused because several cases of the enclosing error union
/// can carry the error: the order of an enum's cases must not choose the error a program reports.
pub const ambiguous_case_code = "E_ERROR_CASE_AMBIGUOUS";

/// A conversion into an error union that several cases fit, as `refuseAmbiguous` reports it.
pub const Ambiguous = struct {
    /// Which statement converts: `try operation()` or `fail value`.
    form: enum { try_, fail },
    /// The enclosing function's error union.
    container: typed.Type,
    /// The type of the error being converted.
    payload: typed.Type,
    /// The cases of `container` that carry `payload`; `fit.count` is at least two.
    fit: typed.CaseFit,
    /// Where the diagnostic points: the `try` expression or the `fail` statement.
    span: source.Span,
    /// The enclosing `fails` clause's spelling of the union, when it names the union itself (no
    /// type parameter), so the repair and the example can construct a case of it.
    spelling: ?source.Span = null,
    /// For `fail value`: the value, which the certain repair wraps in the first fitting case.
    value: ?source.Span = null,
};

/// Where an ambiguous conversion is and what repairs it: the `try` or `fail value`, the `fails` clause's spelling of the union when
/// it can name the union (so the repair can construct a case of it), and for `fail value` the value the repair wraps.
pub const Site = struct {
    form: @FieldType(Ambiguous, "form"),
    span: source.Span,
    spelling: ?source.Span = null,
    value: ?source.Span = null,
    /// The cases coincide for every instance of a generic function, so the refusal is at its declaration.
    every_instance: bool = false,
};

/// What an ambiguous conversion's message names, however the checker came by it: the union and the error as the message prints
/// them, the fitting cases in declaration order, and the first of them with the field a fielded case wraps the error in.
pub const Cases = struct {
    union_name: []const u8,
    /// The error's type, or null when the checker holds only that it is some type parameter's.
    payload_name: ?[]const u8,
    /// The fitting cases as the message lists them (`Io and Parse`).
    list: []const u8,
    count: usize,
    first: []const u8,
    field: ?[]const u8,
};

/// The name a union's cases are constructed through: the union as the message spells it, without the type arguments of a generic
/// one (`Wrap[str]` is built as `Wrap.First(...)`, which takes its arguments from the expected type).
fn constructorName(union_name: []const u8) []const u8 {
    return union_name[0 .. std.mem.indexOfScalar(u8, union_name, '[') orelse union_name.len];
}

/// Refuse a conversion that several cases fit, listing them in declaration order. `fail value`
/// carries the certain repair: name the first fitting case, the one the compiler chose until now.
/// `try` gets the spelling by example and no repair, since naming the case means matching the
/// result, which changes the statement's shape and the error's trace.
pub fn refuse(allocator: std.mem.Allocator, sink: *diagnostic.Sink, src: source.Source, site: Site, cases: Cases) diagnostic.Error {
    const constructor = constructorName(cases.union_name);
    const error_name = if (cases.payload_name) |name| try std.fmt.allocPrint(allocator, "{s} error", .{name}) else "error";
    const every = if (site.every_instance) " for every instance" else "";
    const head = try std.fmt.allocPrint(allocator, "{d} cases of {s} can carry this {s} ({s}){s}, and the order of the cases must not choose one", .{ cases.count, cases.union_name, error_name, cases.list, every });
    switch (site.form) {
        .try_ => {
            const example = try caseText(allocator, constructor, cases.first, cases.field, "error");
            const message = try std.fmt.allocPrint(allocator, "`try` cannot convert the error: {s}; match the result and fail with the case you mean, for example `fail {s}` in its `Err(error)` arm", .{ head, example });
            return sink.fail(ambiguous_case_code, site.span, message);
        },
        .fail => {
            const value = site.value orelse return error.InternalError;
            const repaired = try caseText(allocator, constructor, cases.first, cases.field, src.text(value));
            const advice = "name the case, `fail {s}`. {s} is the case the compiler chose until now: check that it is the one you meant";
            const message = try std.fmt.allocPrint(allocator, "`fail` cannot convert the value: {s}; " ++ advice, .{ head, repaired, cases.first });
            if (site.spelling == null) return sink.fail(ambiguous_case_code, site.span, message);
            return sink.failFix(ambiguous_case_code, site.span, message, .{ .span = value, .text = repaired });
        },
    }
}

/// Refuse a conversion whose types the checker holds as types (`refuse` for the records' case names): the fitting cases are
/// listed in declaration order, and the first of them is the one the repair names.
pub fn refuseAmbiguous(allocator: std.mem.Allocator, sink: *diagnostic.Sink, src: source.Source, records: []const typed.Record, refusal: Ambiguous) diagnostic.Error {
    const variants = records[refusal.container.recordIndex()].shape.variants orelse return error.InternalError;
    const union_name = if (refusal.spelling) |spelling| src.text(spelling) else try typed.surfaceTypeName(allocator, refusal.container, records);
    var names: std.Io.Writer.Allocating = .init(allocator);
    defer names.deinit();
    for (refusal.fit.kept(), 0..) |tag, i| {
        const separator: []const u8 = if (i == 0) "" else if (i + 1 == refusal.fit.count) " and " else ", ";
        names.writer.print("{s}{s}", .{ separator, variants.cases[tag].name }) catch return error.OutOfMemory;
    }
    const hidden = refusal.fit.count - refusal.fit.kept().len;
    if (hidden != 0) names.writer.print(" and {d} more", .{hidden}) catch return error.OutOfMemory;
    const first = refusal.fit.tags[0];
    const field: ?[]const u8 = if (typed.wrappingRecord(records, refusal.container, first, refusal.payload)) |record| records[record.recordIndex()].fields[0].name else null;
    return refuse(allocator, sink, src, .{ .form = refusal.form, .span = refusal.span, .spelling = refusal.spelling, .value = refusal.value }, .{
        .union_name = union_name,
        .payload_name = try typed.surfaceTypeName(allocator, refusal.payload, records),
        .list = try allocator.dupe(u8, names.written()),
        .count = refusal.fit.count,
        .first = variants.cases[first].name,
        .field = field,
    });
}

/// `Union.Case(value)` for a positional case or `Union.Case(field=value)` for a fielded one.
fn caseText(allocator: std.mem.Allocator, union_name: []const u8, case: []const u8, field: ?[]const u8, value: []const u8) std.mem.Allocator.Error![]const u8 {
    if (field) |name| return std.fmt.allocPrint(allocator, "{s}.{s}({s}={s})", .{ union_name, case, name, value });
    return std.fmt.allocPrint(allocator, "{s}.{s}({s})", .{ union_name, case, value });
}

/// Refuse an ambiguous conversion in the function the sema checker is checking; in an instance of a
/// generic function, whose cases fit only for its type arguments, a note names the instance.
fn refuseInFunction(comptime Checker: type, self: *Checker, refusal: Ambiguous) diagnostic.Error {
    const id = self.current_function orelse return refuseAmbiguous(self.allocator, self.sink, self.src, self.catalog.records, refusal);
    const function = self.syntaxFunction(id);
    const arguments = self.instance_keys.items[@backingInt(id)].arguments;
    var located = refusal;
    // The cases of an instance fit for its type arguments, so naming the first one repairs this instance and not the template.
    located.spelling = if (arguments.len == 0) unionSpelling(function.signature) else null;
    const failed = refuseAmbiguous(self.allocator, self.sink, self.src, self.catalog.records, located);
    if (arguments.len == 0) return failed;
    var names: std.Io.Writer.Allocating = .init(self.allocator);
    defer names.deinit();
    for (arguments, 0..) |argument, i| {
        const name = try typed.surfaceTypeName(self.allocator, argument, self.catalog.records);
        names.writer.print("{s}{s}", .{ if (i == 0) "" else ", ", name }) catch return error.OutOfMemory;
    }
    const note = try std.fmt.allocPrint(self.allocator, "in the instance {s}[{s}]: the cases fit for these type arguments", .{ self.src.text(function.name), names.written() });
    self.sink.items.items[self.sink.items.items.len - 1].related = .{ .span = function.name, .message = note };
    return failed;
}

/// What a refusal adds when the checked value `node` is a direct call of a function declared `fails`, written where its plain
/// value `expected` is needed (`2 + parse("1")`, `show(parse("22"))`, `mut n: int = parse("333")`): the sentence naming the call and
/// the two ways out, and the edit that writes `try ` before the call, which is certain only when the enclosing function declares
/// `fails` with the same error type.
pub const MissingTry = struct { sentence: []const u8, insert: ?diagnostic.Edit };

/// The success type a `fails` call must have for the advice: a given type, or any integer (an operand of `-` or `<`).
pub const Wanted = union(enum) { type: typed.Type, integer };

/// Whether a `try` written here is refused, so no advice may name it: in a contract condition (`@requires`, `@ensures`, `@invariant`),
/// in a lambda (it has no `fails` of its own), in a `detach` loop and in a function with an `on fail:` clause (there `try` is a
/// declaration's value or a statement, not an operand or an argument), and while a result is still pending (the exit of a `try` would
/// drop it, `requireHandledAt`).
fn tryRefused(comptime Checker: type, self: *Checker) bool {
    if (self.contract.checking != null or self.current_lambda != null) return true;
    for (self.loops.active.items) |scope| if (scope.detach != null) return true;
    if (self.current_function) |function| {
        const body = self.syntax.statements.items[@backingInt(self.syntaxFunction(function).body)].span;
        if (std.mem.indexOf(u8, self.src.text(body), "on fail") != null) return true;
    }
    for (self.locals.items, 0..) |local, index| {
        if (self.pendingObligation(local) and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index))) return true;
    }
    return false;
}

/// The advice for a `fails` call used as its value, or null when `node` is anything else: a variable that holds a `Result`, a
/// call of a function that returns a `Result` value, a call through a function value, a result whose success type is not `wanted`,
/// or a place where `try` is refused (`tryRefused`).
pub fn missingTry(comptime Checker: type, self: *Checker, node: typed.NodeId, wanted: Wanted) diagnostic.Error!?MissingTry {
    const found = self.nodes.items[@backingInt(node)];
    const shape = typed.resultShape(found.ty, self.catalog.records) orelse return null;
    switch (wanted) {
        .type => |expected| if (shape.ok_type != expected) return null,
        .integer => if (!shape.ok_type.isInteger()) return null,
    }
    if (tryRefused(Checker, self)) return null;
    const call = switch (found.data) {
        .call => |direct| direct,
        else => return null,
    };
    if (self.syntaxFunction(call.function).signature.failure_type == null) return null;
    const text = self.src.text(found.span);
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
    const name = text[0..open];
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') return null;
    if (name.len == 0) return null;
    const failure = try typed.surfaceTypeName(self.allocator, shape.error_type, self.catalog.records);
    const handle = try std.fmt.allocPrint(self.allocator, "handle it with `const n = {s}(...) else Err(e):`", .{name});
    const enclosing = self.failure_type;
    const sentence = if (enclosing) |declared|
        try std.fmt.allocPrint(self.allocator, "`{s}` can fail: write `try {s}(...)` to take its value and pass the error on{s}, or {s}", .{
            name,
            name,
            if (declared == shape.error_type) "" else try std.fmt.allocPrint(self.allocator, " (this function's `fails` must carry `{s}`)", .{failure}),
            handle,
        })
    else
        try std.fmt.allocPrint(self.allocator, "`{s}` can fail: {s}, or declare `fails {s}` on this function and write `try {s}(...)`", .{ name, handle, failure, name });
    const same = if (enclosing) |declared| declared == shape.error_type else false;
    return .{ .sentence = sentence, .insert = if (same) .{ .span = .{ .start = found.span.start, .end = found.span.start }, .text = "try " } else null };
}

/// Refuse an ambiguous `try` in the function the sema checker is checking (`checkPropagation`).
pub fn refuseAmbiguousTry(comptime Checker: type, self: *Checker, container: typed.Type, payload: typed.Type, fit: typed.CaseFit, span: source.Span) diagnostic.Error {
    return refuseInFunction(Checker, self, .{ .form = .try_, .container = container, .payload = payload, .fit = fit, .span = span });
}

/// What a `fail` statement converting an error is in the source. `on fail:` rewrites a `try` in its
/// reach into a match whose failure arm fails the error, a statement spanning only the `try` keyword
/// with the keyword as its value: that one is a `try`, and its value is not text a repair can wrap.
pub fn failSite(statement: source.Span, value: source.Span) struct { form: @FieldType(Ambiguous, "form"), value: ?source.Span } {
    if (statement.start == value.start) return .{ .form = .try_, .value = null };
    return .{ .form = .fail, .value = value };
}

/// The `fails` clause's spelling of the error union, which the repair constructs a case through: a generic union's cases are
/// built through its bare name (`Wrap.First(...)`), whatever type arguments the clause gives it, so a generic function has one too.
pub fn unionSpelling(signature: ast.FunctionSignature) ?source.Span {
    return signature.failure_type;
}

/// Check a fail statement against its declared error and build the Err variant.
pub fn checkFail(comptime Checker: type, self: *Checker, expression: ast.NodeId, span: source.Span) diagnostic.Error!typed.NodeId {
    const expected = self.failure_type orelse return self.sink.fail("E_FAIL_CONTEXT", span, "fail requires an enclosing function with a fails clause");
    var value = try self.expressionExpected(expression, expected);
    // A failure takes its value as a `return` does: a new option's `unwrap_or` (F-71) or a new list's element (F-55) moves.
    try self.moveTemporaryElement(expression, value);
    try @import("option_flow.zig").moveReturned(Checker, self, expression, value, span);
    const actual = self.nodes.items[@backingInt(value)].ty;
    if (actual != expected) {
        const fit = typed.errorCaseFit(self.catalog.records, expected, actual);
        if (fit.count > 1) {
            const at = failSite(span, self.syntax.nodes.items[@backingInt(expression)].span);
            return refuseInFunction(Checker, self, .{ .form = at.form, .container = expected, .payload = actual, .fit = fit, .span = span, .value = at.value });
        }
        if (fit.unique()) |tag| {
            if (typed.wrappingRecord(self.catalog.records, expected, tag, actual)) |record| {
                const fields = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = 0, .value = value }});
                value = @fromBackingInt(self.nodes.items.len);
                try self.nodes.append(self.allocator, .{ .span = span, .ty = record, .data = .{ .record = fields } });
            }
            value = try variant(Checker, self, value, expected, tag, span);
        } else try self.require(actual, expected, span);
    }
    const shape = typed.resultShape(self.return_type, self.catalog.records) orelse return error.InternalError;
    return variant(Checker, self, value, self.return_type, shape.error_tag, span);
}

/// Inject a present value into expected optional layers without flattening an existing layer.
pub fn injectOptional(comptime Checker: type, self: *Checker, value: typed.NodeId, expected: typed.Type, span: source.Span) diagnostic.Error!typed.NodeId {
    const actual = self.nodes.items[@backingInt(value)].ty;
    if (actual == expected) return value;
    const shape = @import("prelude.zig").optionShape(expected, self.catalog.records) orelse return value;
    const payload = try injectOptional(Checker, self, value, shape.element, span);
    if (self.nodes.items[@backingInt(payload)].ty != shape.element) return value;
    return variant(Checker, self, payload, expected, shape.some, span);
}

/// Build the node an `own` marker gives the checked `value`. An implicit `Some` is a constructor, so
/// the marker moves onto the value it wraps: `own value` against `T?` is `Some(own value)`, not a marked
/// wrapper. `injectOptional` gives its wrapper the span of that value, which an explicit `Some(...)`
/// never has, so Core sees the same tree for both spellings and the wrappers stay unmarked.
pub fn ownedValue(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) diagnostic.Error!typed.Node {
    const node = self.nodes.items[@backingInt(value)];
    if (node.data == .variant) if (node.data.variant.value) |payload| {
        const wrapped = self.nodes.items[@backingInt(payload)].span;
        if (wrapped.start == node.span.start and wrapped.end == node.span.end) {
            const marked = try ownedValue(Checker, self, payload, span);
            const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, marked);
            return .{ .span = span, .ty = node.ty, .view = node.view, .own = false, .data = .{ .variant = .{ .tag = node.data.variant.tag, .value = id } } };
        }
    };
    var marked = node;
    marked.own = true;
    marked.span = span;
    return marked;
}
