//! Concrete composite signatures share nominal identities and specialization limits.
const std = @import("std");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
/// Declaration parameters and concrete arguments for one source signature.
pub const Binding = struct { span: Span, parameters: []const @import("ast.zig").TypeParameter, arguments: []const typed.Type, depth: usize = 0, lengths: []const ?usize = &.{} };
/// Resolve a composite signature with concrete arguments and bounded recursive substitution.
pub fn resolve(allocator: std.mem.Allocator, catalog: *@import("type_catalog.zig").Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding) diagnostic.Error!typed.Type {
    const span = binding.span;
    const parameters = binding.parameters;
    const arguments = binding.arguments;
    const depth = binding.depth;
    if (depth == 256) return sink.fail(diagnostic.generic_limit, span, "composite signature exceeds 256 nesting levels");
    for (parameters, arguments) |parameter, argument| {
        if (std.mem.eql(u8, src.text(parameter.name), src.text(span))) {
            if (parameter.constant_length) return sink.fail(diagnostic.generic_length, span, "a const length parameter is a value, not a type");
            return argument;
        }
    }
    if (catalog.templates.applications.get(span.start)) |template| {
        var values: [16]typed.Type = undefined;
        var lengths: [16]?usize = @splat(null);
        const required = catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
        for (template.syntax.arguments, required, 0..) |argument, parameter, i| {
            if (parameter.constant_length) {
                lengths[i] = try @import("generic_lengths.zig").resolve(src, argument, parameters, binding.lengths, sink);
                values[i] = .u64;
            } else values[i] = try resolve(allocator, catalog, src, sink, .{ .span = argument, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .depth = depth + 1 });
        }
        return @import("nominal_catalog.zig").instantiateLengths(catalog, template.declaration, values[0..template.arguments.len], lengths[0..template.arguments.len], span);
    }
    if (catalog.arrays.templates.get(span.start)) |template| {
        const element = try resolve(allocator, catalog, src, sink, .{ .span = template.syntax.element, .parameters = parameters, .arguments = arguments, .lengths = binding.lengths, .depth = depth + 1 });
        const length = if (template.length_parameter) |at| try @import("generic_lengths.zig").resolve(src, at, parameters, binding.lengths, sink) else template.length;
        return catalog.instantiateArray(allocator, element, length, span, sink);
    }
    return catalog.resolve(src, span, sink);
}
