//! Concrete composite signatures share nominal identities and specialization limits.
const std = @import("std");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const generic_requirements = @import("generic_requirements.zig");
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
pub fn resolve(allocator: std.mem.Allocator, catalog: *@import("type_catalog.zig").Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding) diagnostic.Error!typed.Type {
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
    if (catalog.templates.store) |store| if (store.index.syntax.callbacks.get(span.start)) |callback| {
        var inputs: [16]typed.Type = undefined;
        for (callback.parameters, 0..) |input, i| inputs[i] = try resolve(allocator, catalog, src, sink, childBinding(binding, input, depth + 1));
        const result = try resolve(allocator, catalog, src, sink, .{ .span = callback.return_type, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .aliases = binding.aliases, .depth = depth + 1 });
        return @import("callables.zig").intern(allocator, catalog, .{
            .parameters = inputs[0..callback.parameters.len],
            .return_type = result,
            .effects = callback.effect_bound.allowed,
            .mutates = callback.mutates,
            .return_origin = .unknown,
        }, span, sink);
    };
    if (catalog.templates.applications.get(span.start)) |template| {
        var values: [16]typed.Type = undefined;
        var lengths: [16]?usize = @splat(null);
        const required = catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
        for (template.syntax.arguments, required, 0..) |argument, parameter, i| {
            if (parameter.constant_length) {
                lengths[i] = try @import("generic_lengths.zig").resolve(src, argument, parameters, binding.lengths, sink);
                values[i] = .u64;
            } else values[i] = try resolve(allocator, catalog, src, sink, .{ .span = argument, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .aliases = binding.aliases, .depth = depth + 1 });
        }
        return @import("nominal_catalog.zig").instantiateLengths(catalog, template.declaration, values[0..template.arguments.len], lengths[0..template.arguments.len], span);
    }
    if (catalog.arrays.templates.get(span.start)) |template| {
        const element = try resolve(allocator, catalog, src, sink, .{ .span = template.syntax.element, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .aliases = binding.aliases, .depth = depth + 1 });
        const length = if (template.length_parameter) |at| try @import("generic_lengths.zig").resolve(src, at, parameters, binding.lengths, sink) else template.length;
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
        return @import("nominal_catalog.zig").instantiateTuple(catalog, elements[0..syntax.elements.len], span);
    };
    // A prelude type named without an import — the mutable octet buffer — is
    // declared with the prelude but materialized on its first mention, so a
    // module-local declaration of that name still wins its own scope.
    const name = src.text(span);
    if (std.mem.eql(u8, name, @import("nominal_templates.zig").byte_buffer_name) and !(catalog.module_names != null and try catalog.module_names.?.topLevel(span)))
        if (try @import("nominal_catalog.zig").materializePrelude(catalog, name, span)) |ty| return ty;
    return catalog.resolve(src, span, sink);
}
