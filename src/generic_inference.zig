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
/// What one type parameter was inferred as, and the argument that said so (null: the expected result).
pub const Inferred = struct { value: Value, from: ?source.Span };
/// One call's partial substitution; parameter indexes belong to the callee.
pub const Context = struct {
    src: source.Source,
    catalog: Catalog,
    parameters: []const ast.TypeParameter,
    sink: *diagnostic.Sink,
    site: source.Span,
    values: [16]?Inferred = @splat(null),
    work: usize = 0,
    /// Collect constraints from one already-checked argument written at `argument`, preserving symbolic caller identities.
    pub fn matchArgument(self: *Context, expected: source.Span, actual: Value, argument: source.Span) Error!void {
        return self.matchDepth(expected, actual, 0, argument);
    }
    /// Collect constraints from the type the call's result is expected to have. For a callee declared
    /// `-> success fails failure` the call answers a `Result`, so an expected `Result[S, E]` gives `S` to the
    /// success spelling and `E` to the failure spelling; any other expected type is matched against the success spelling.
    pub fn matchResult(self: *Context, success: source.Span, failure: ?source.Span, actual: Value) Error!void {
        if (failure) |failure_span| if (self.resultHalves(actual)) |halves| {
            try self.matchDepth(success, halves[0], 0, null);
            return self.matchDepth(failure_span, halves[1], 0, null);
        };
        return self.matchDepth(success, actual, 0, null);
    }
    fn matchDepth(self: *Context, expected: source.Span, actual: Value, depth: usize, from: ?source.Span) Error!void {
        if (depth == 256 or self.work == 100000) return self.sink.fail(diagnostic.generic_limit, self.site, "generic inference exceeds shape depth/work budget");
        self.work += 1;
        for (self.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(expected))) continue;
            if (self.values[index]) |previous| {
                if (!symbolic.same(previous.value, actual, self.catalog)) return self.conflict(parameter, previous, .{ .value = actual, .from = from });
            } else self.values[index] = .{ .value = actual, .from = from };
            return;
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.suffixes.get(expected)) |suffix| {
            const declaration = store.index.names.get(if (suffix.kind == .growable) "list" else "Option").?;
            return self.matchNominal(declaration, &.{suffix.base}, actual, depth, from);
        };
        if (self.catalog.arrays.templates.get(expected.start)) |template| {
            const shape = symbolic.array(actual, self.catalog.records) orelse return self.mismatch();
            if (shape.key != null) return self.mismatch();
            if (template.length_parameter) |at| {
                const length: Value = if (shape.length_parameter) |index| .{ .length_parameter = index } else .{ .length = shape.length };
                try self.matchDepth(at, length, depth + 1, from);
            }
            return self.matchDepth(template.syntax.element, shape.element, depth + 1, from);
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.tuples.get(expected.start)) |syntax| {
            const shapes = @import("symbolic_shapes.zig");
            const arity = shapes.tupleArity(self.catalog, actual) orelse return self.mismatch();
            if (arity != syntax.elements.len) return self.mismatch();
            for (syntax.elements, 0..) |element, index| try self.matchDepth(element, shapes.tupleElement(self.catalog, actual, index).?, depth + 1, from);
            return;
        };
        if (self.catalog.templates.applications.get(expected.start)) |template| if (template.syntax.span.end == expected.end) {
            return self.matchNominal(template.declaration, template.syntax.arguments, actual, depth, from);
        };
        if (self.catalog.templates.store) |store| if (store.index.syntax.callbacks.get(expected.start)) |callback| {
            return self.matchCallback(callback, actual, depth, from);
        };
        // Concrete leaves and fixed dimensions are checked against the completed substitution.
    }
    /// The success and failure types of a builtin `Result` value, or null for any other value.
    fn resultHalves(self: *const Context, actual: Value) ?[2]Value {
        switch (actual) {
            .concrete => |ty| {
                const shape = @import("typed.zig").resultShape(ty, self.catalog.records) orelse return null;
                return .{ .{ .concrete = shape.ok_type }, .{ .concrete = shape.error_type } };
            },
            .nominal => |nominal| {
                const store = self.catalog.templates.store orelse return null;
                const declaration = store.index.names.get("Result") orelse return null;
                if (nominal.declaration != declaration or nominal.arguments.len != 2) return null;
                return .{ nominal.arguments[0], nominal.arguments[1] };
            },
            else => return null,
        }
    }
    /// Two arguments (or an argument and the expected result) infer different types for one parameter:
    /// the message names both and the note points at the one that inferred it first.
    fn conflict(self: *Context, parameter: ast.TypeParameter, first: Inferred, second: Inferred) Error {
        const sentence = "the type parameter `{s}` is inferred as {s} from {s} and as {s} from {s}; " ++
            "write the type arguments in brackets after the function's name, or make the two agree";
        const message = std.fmt.allocPrint(self.sink.allocator, sentence, .{
            self.src.text(parameter.name),
            try self.typeText(first.value),
            try self.originText(first.from),
            try self.typeText(second.value),
            try self.originText(second.from),
        }) catch return error.OutOfMemory;
        const at = second.from orelse self.site;
        const note: diagnostic.Related = if (first.from) |earlier|
            .{ .span = earlier, .message = "the argument that inferred it first" }
        else
            .{ .span = parameter.name, .message = "conflicting parameter declared here" };
        return self.sink.failRelated(eInference, at, message, note);
    }
    /// A type as the source spells it (`int`, not the builtin's tag `i64`; `typed.surfaceTypeName`).
    fn typeText(self: *const Context, value: Value) Error![]const u8 {
        return switch (value) {
            .concrete => |ty| try @import("typed.zig").surfaceTypeName(self.sink.allocator, ty, self.catalog.records),
            else => "another type",
        };
    }
    fn originText(self: *Context, from: ?source.Span) Error![]const u8 {
        const span = from orelse return "the expected result";
        const text = self.src.text(span);
        const shown = if (text.len > 40) text[0..40] else text;
        const ellipsis: []const u8 = if (text.len > 40) "..." else "";
        return std.fmt.allocPrint(self.sink.allocator, "the argument `{s}{s}`", .{ shown, ellipsis }) catch return error.OutOfMemory;
    }
    fn matchNominal(self: *Context, declaration: usize, arguments: []const source.Span, actual: Value, depth: usize, from: ?source.Span) Error!void {
        if (actual == .nominal) {
            if (declaration != actual.nominal.declaration or arguments.len != actual.nominal.arguments.len) return self.mismatch();
            for (arguments, actual.nominal.arguments) |expected, argument| try self.matchDepth(expected, argument, depth + 1, from);
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
            try self.matchDepth(expected, value, depth + 1, from);
        }
    }
    /// A function argument for a function-typed parameter: its parameter types and its result are unified with the
    /// parameter's. A function type spelled `-> T fails E` has a `Result[T, E]` result, so a function argument's
    /// result gives its success type to `T` and its failure type to `E`.
    fn matchCallback(self: *Context, expected: ast.CallbackType, actual: Value, depth: usize, from: ?source.Span) Error!void {
        var result: Value = undefined;
        if (actual == .callback) {
            const signature = actual.callback;
            if (expected.parameters.len != signature.parameters.len) return self.mismatch();
            for (expected.parameters, signature.parameters) |parameter, value| try self.matchDepth(parameter, value, depth + 1, from);
            result = signature.result;
        } else {
            if (actual != .concrete) return self.mismatch();
            const signature = @import("callables.zig").signature(actual.concrete, self.catalog.records) orelse return self.mismatch();
            if (expected.parameters.len != signature.parameters.len) return self.mismatch();
            for (expected.parameters, signature.parameters) |parameter, value| try self.matchDepth(parameter, .{ .concrete = value }, depth + 1, from);
            result = .{ .concrete = signature.return_type };
        }
        const failure = expected.failure_type orelse return self.matchDepth(expected.return_type, result, depth + 1, from);
        const halves = self.resultHalves(result) orelse return self.mismatch();
        try self.matchDepth(expected.return_type, halves[0], depth + 1, from);
        return self.matchDepth(failure, halves[1], depth + 1, from);
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
            const found = self.values[index] orelse {
                const message = std.fmt.allocPrint(
                    self.sink.allocator,
                    "no argument of this call and no expected result determines the type parameter `{s}`; write the type arguments in brackets after the function's name",
                    .{self.src.text(parameter.name)},
                ) catch return error.OutOfMemory;
                return self.sink.failRelated(eInference, self.site, message, .{ .span = parameter.name, .message = "undetermined parameter declared here" });
            };
            value.* = found.value;
        }
    }
};
