//! Infer call arguments from existing checked shapes without defaults or runtime evaluation.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const symbolic = @import("symbolic_types.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const Value = symbolic.Value;
const Error = diagnostic.Error;
const eInference = "E_GENERIC_INFERENCE";
/// One call's partial substitution; parameter indexes belong to the callee.
pub const Context = struct {
    src: source.Source,
    catalog: Catalog,
    parameters: []const ast.TypeParameter,
    sink: *diagnostic.Sink,
    site: source.Span,
    values: [16]?Value = @splat(null),
    work: usize = 0,
    /// Collect constraints from one already-checked argument, preserving symbolic caller identities.
    pub fn match(self: *Context, expected: source.Span, actual: Value) Error!void {
        return self.matchDepth(expected, actual, 0);
    }
    fn matchDepth(self: *Context, expected: source.Span, actual: Value, depth: usize) Error!void {
        if (depth == 256 or self.work == 100000) return self.sink.fail(diagnostic.generic_limit, self.site, "generic inference exceeds shape depth/work budget");
        self.work += 1;
        for (self.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(expected))) continue;
            if (self.values[index]) |previous| {
                if (!symbolic.same(previous, actual, self.catalog)) return self.sink.failRelated(
                    eInference,
                    self.site,
                    "call arguments and expected result infer conflicting generic types or lengths",
                    .{ .span = parameter.name, .message = "conflicting parameter declared here" },
                );
            } else self.values[index] = actual;
            return;
        }
        if (self.catalog.arrays.templates.get(expected.start)) |template| {
            const shape = symbolic.array(actual, self.catalog.records) orelse return self.mismatch();
            if (shape.key != null) return self.mismatch();
            if (template.length_parameter) |at| {
                const length: Value = if (shape.length_parameter) |index| .{ .length_parameter = index } else .{ .length = shape.length };
                try self.matchDepth(at, length, depth + 1);
            }
            return self.matchDepth(template.syntax.element, shape.element, depth + 1);
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.tuples.get(expected.start)) |syntax| {
            const shapes = @import("symbolic_shapes.zig");
            const arity = shapes.tupleArity(self.catalog, actual) orelse return self.mismatch();
            if (arity != syntax.elements.len) return self.mismatch();
            for (syntax.elements, 0..) |element, index| try self.matchDepth(element, shapes.tupleElement(self.catalog, actual, index).?, depth + 1);
            return;
        };
        if (self.catalog.templates.applications.get(expected.start)) |template| {
            return self.matchNominal(template.declaration, template.syntax.arguments, actual, depth);
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.callbacks.get(expected.start)) |callback| {
            return self.matchCallback(callback, actual, depth);
        };
        // Concrete leaves and fixed dimensions are checked against the completed substitution.
    }
    fn matchNominal(self: *Context, declaration: usize, arguments: []const source.Span, actual: Value, depth: usize) Error!void {
        if (actual == .nominal) {
            if (declaration != actual.nominal.declaration or arguments.len != actual.nominal.arguments.len) return self.mismatch();
            for (arguments, actual.nominal.arguments) |expected, argument| try self.matchDepth(expected, argument, depth + 1);
            return;
        }
        if (actual != .concrete) return self.mismatch();
        const store = self.catalog.templates.store orelse return self.mismatch();
        const id = store.semantic(actual.concrete) orelse return self.mismatch();
        const key = store.graph.nodes.items[@backingInt(id)].key;
        if (key.base != .named or key.base.named != declaration or key.arguments.len != arguments.len) return self.mismatch();
        for (arguments, key.arguments) |expected, argument| {
            const base = store.graph.nodes.items[@backingInt(argument)].key.base;
            const value: Value = if (base == .length) .{ .length = base.length } else .{
                .concrete = store.runtime(argument) orelse return self.sink.fail(eInference, self.site, "unmaterialized phantom type requires explicit generic arguments"),
            };
            try self.matchDepth(expected, value, depth + 1);
        }
    }
    fn matchCallback(self: *Context, expected: ast.CallbackType, actual: Value, depth: usize) Error!void {
        if (actual == .callback) {
            const signature = actual.callback;
            if (expected.parameters.len != signature.parameters.len) return self.mismatch();
            for (expected.parameters, signature.parameters) |parameter, value| try self.matchDepth(parameter, value, depth + 1);
            return self.matchDepth(expected.return_type, signature.result, depth + 1);
        }
        if (actual != .concrete) return self.mismatch();
        const signature = @import("callables.zig").signature(actual.concrete, self.catalog.records) orelse return self.mismatch();
        if (expected.parameters.len != signature.parameters.len) return self.mismatch();
        for (expected.parameters, signature.parameters) |parameter, value| try self.matchDepth(parameter, .{ .concrete = value }, depth + 1);
        return self.matchDepth(expected.return_type, .{ .concrete = signature.return_type }, depth + 1);
    }
    fn mismatch(self: *Context) Error {
        return self.sink.fail(eInference, self.site, "argument shape does not match the generic parameter type");
    }
    /// Whether the available argument and result constraints determine every parameter.
    pub fn complete(self: *const Context) bool {
        for (self.values[0..self.parameters.len]) |value| if (value == null) return false;
        return true;
    }
    /// Require a unique value for every parameter without inventing defaults.
    pub fn finish(self: *Context, output: []Value) Error!void {
        for (self.parameters, output, 0..) |parameter, *value, index| {
            value.* = self.values[index] orelse return self.sink.failRelated(
                eInference,
                self.site,
                "cannot infer every generic argument from call arguments and expected result; supply explicit type arguments",
                .{ .span = parameter.name, .message = "undetermined parameter declared here" },
            );
        }
    }
};
