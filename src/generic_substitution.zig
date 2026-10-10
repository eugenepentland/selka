//! Concrete composite signatures share nominal identities and specialization limits.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const generic_requirements = @import("generic_requirements.zig");
const generic_lengths = @import("generic_lengths.zig");
const Catalog = @import("type_catalog.zig").Catalog;
const nominal_catalog = @import("nominal_catalog.zig");
/// Declaration parameters and concrete arguments for one source signature.
pub const Binding = struct {
    span: Span,
    parameters: []const @import("ast.zig").TypeParameter,
    arguments: []const typed.Type,
    depth: usize = 0,
    lengths: []const ?usize = &.{},
    aliases: []const @import("generic_requirements.zig").SubjectAlias = &.{},
};

/// Rebase one binding onto a nested callback span without copying its slices.
fn childBinding(binding: Binding, span: Span, depth: usize) Binding {
    return .{
        .span = span,
        .parameters = binding.parameters,
        .arguments = binding.arguments,
        .lengths = binding.lengths,
        .aliases = binding.aliases,
        .depth = depth,
    };
}
/// Resolve a composite signature with concrete arguments and bounded recursive substitution.
pub fn resolve(allocator: std.mem.Allocator, catalog: *Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding) diagnostic.Error!typed.Type {
    const span = binding.span;
    const parameters = binding.parameters;
    const arguments = binding.arguments;
    const depth = binding.depth;
    if (depth == 256) return sink.fail(diagnostic.generic_limit, span, "composite signature exceeds 256 nesting levels");
    switch (generic_requirements.matchScope(binding.aliases, src, span)) {
        .subject => |parameter| {
            if (parameter >= arguments.len) return error.InternalError;
            return arguments[parameter];
        },
        .foreign => {},
        .local => {
            for (parameters, arguments) |parameter, argument| {
                if (std.mem.eql(u8, src.text(parameter.name), src.text(span))) {
                    if (parameter.constant_length) return sink.fail(diagnostic.generic_length, span, "a const length parameter is a value, not a type");
                    return argument;
                }
            }
        },
    }
    if (catalog.templates.store) |store| if (store.index.syntax.suffixes.get(span)) |suffix| {
        const element = try resolve(allocator, catalog, src, sink, childBinding(binding, suffix.base, depth + 1));
        return nominal_catalog.instantiateLengths(catalog, store.index.names.get(if (suffix.kind == .growable) "list" else "Option").?, &.{element}, &.{}, span);
    };
    if (catalog.templates.store) |store| if (store.index.syntax.callbacks.get(span.start)) |callback| {
        return resolveCallback(allocator, catalog, src, sink, binding, callback);
    };
    if (catalog.templates.store) |store| if (store.index.syntax.applications.get(span.start)) |syntax| {
        if (syntax.span.end == span.end) return resolveSourceApplication(allocator, catalog, src, sink, binding);
    };
    if (catalog.arrays.templates.get(span.start)) |template| {
        const element = try resolve(allocator, catalog, src, sink, .{ .span = template.syntax.element, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .aliases = binding.aliases, .depth = depth + 1 });
        const length = if (template.length_parameter) |at| try generic_lengths.resolve(src, at, parameters, binding.lengths, sink) else template.length;
        return catalog.instantiateArray(allocator, element, length, span, sink);
    }
    if (catalog.templates.store) |store| if (store.index.syntax.tuples.get(span.start)) |syntax| {
        var elements: [8]typed.Type = undefined;
        for (syntax.elements, 0..) |element, index| elements[index] = try resolve(allocator, catalog, src, sink, .{
            .span = element,
            .parameters = parameters,
            .arguments = arguments,
            .lengths = binding.lengths,
            .aliases = binding.aliases,
            .depth = depth + 1,
        });
        return nominal_catalog.instantiateTuple(catalog, elements[0..syntax.elements.len], span);
    };
    // A prelude type named without an import — the mutable octet buffer — is
    // declared with the prelude but materialized on its first mention, so a
    // module-local declaration of that name still wins its own scope.
    const name = src.text(span);
    if (std.mem.eql(u8, name, @import("nominal_templates.zig").byte_buffer_name) and !(catalog.module_names != null and try catalog.module_names.?.topLevel(span)))
        if (try nominal_catalog.materializePrelude(catalog, name, span)) |ty| return ty;
    return catalog.resolve(src, span, sink);
}

fn resolveSourceApplication(allocator: std.mem.Allocator, catalog: *Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding) diagnostic.Error!typed.Type {
    const store = catalog.templates.store orelse return error.InternalError;
    const syntax = store.index.syntax.applications.get(binding.span.start) orelse return error.InternalError;
    if (std.mem.eql(u8, src.text(syntax.name), "FixedArray")) {
        if (syntax.arguments.len != 2) return sink.fail(diagnostic.generic_arity, syntax.span, "FixedArray requires an element type and a constant length");
        const element = try resolve(allocator, catalog, src, sink, childBinding(binding, syntax.arguments[0], binding.depth + 1));
        const length = try generic_lengths.resolve(src, syntax.arguments[1], binding.parameters, binding.lengths, sink);
        return catalog.instantiateArray(allocator, element, length, binding.span, sink);
    }
    const expression = try store.index.expression(binding.span, try generic_requirements.resolve(allocator, src, binding.parameters, sink));
    if (expression != .application) return error.InternalError;
    const declaration = expression.application.declaration;
    const required = store.index.declarations.items[declaration].parameters;
    var values: [16]typed.Type = undefined;
    var lengths: [16]?usize = @splat(null);
    for (syntax.arguments, required, 0..) |argument, parameter, i| {
        if (parameter.constant_length) {
            lengths[i] = try generic_lengths.resolve(src, argument, binding.parameters, binding.lengths, sink);
            values[i] = .u64;
        } else values[i] = try resolve(allocator, catalog, src, sink, childBinding(binding, argument, binding.depth + 1));
    }
    return nominal_catalog.instantiateLengths(catalog, declaration, values[0..required.len], lengths[0..required.len], binding.span);
}

fn resolveCallback(allocator: std.mem.Allocator, catalog: *Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding, callback: ast.CallbackType) diagnostic.Error!typed.Type {
    var inputs: [16]typed.Type = undefined;
    for (callback.parameters, 0..) |input, i| inputs[i] = try resolve(allocator, catalog, src, sink, childBinding(binding, input, binding.depth + 1));
    const success = try resolve(allocator, catalog, src, sink, childBinding(binding, callback.return_type, binding.depth + 1));
    var result = success;
    if (callback.failure_type) |failure| {
        const error_type = try resolve(allocator, catalog, src, sink, childBinding(binding, failure, binding.depth + 1));
        result = try @import("frontend_failures.zig").resultType(catalog, allocator, success, error_type, binding.span, sink);
    }
    return @import("callables.zig").intern(allocator, catalog, .{
        .parameters = inputs[0..callback.parameters.len],
        .return_type = result,
        .effects = callback.effect_bound.allowed,
        .labels = try @import("callables.zig").syntaxLabels(allocator, src, callback),
        .mutates = try ast.mutPositions(allocator, callback.parameter_modes.mut),
        .return_origin = .unknown,
    }, binding.span, sink);
}
