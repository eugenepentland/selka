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
    const value = try self.expressionExpected(expression, expected);
    try self.require(self.nodes.items[@backingInt(value)].ty, expected, span);
    return wrapSuccess(Checker, self, value, span);
}

/// Check a fail statement against its declared error and build the Err variant.
pub fn checkFail(comptime Checker: type, self: *Checker, expression: ast.NodeId, span: source.Span) diagnostic.Error!typed.NodeId {
    const expected = self.failure_type orelse return self.sink.fail("E_FAIL_CONTEXT", span, "fail requires an enclosing function with a fails clause");
    var value = try self.expressionExpected(expression, expected);
    const actual = self.nodes.items[@backingInt(value)].ty;
    if (actual != expected) {
        if (typed.wrappingCase(self.catalog.records, expected, actual)) |tag| {
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
