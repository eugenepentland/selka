//! Concrete composite signatures share nominal identities and specialization limits.
const std = @import("std");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
/// Declaration parameters and concrete arguments for one source signature.
pub const Binding = struct { span: Span, parameters: []const @import("ast.zig").TypeParameter, arguments: []const typed.Type, depth: usize = 0 };
/// Resolve a composite signature with concrete arguments and bounded recursive substitution.
pub fn resolve(allocator: std.mem.Allocator, catalog: *@import("type_catalog.zig").Catalog, src: Source, sink: *diagnostic.Sink, binding: Binding) diagnostic.Error!typed.Type {
    const span = binding.span;
    const parameters = binding.parameters;
    const arguments = binding.arguments;
    const depth = binding.depth;
    if (depth == 256) return sink.fail(diagnostic.generic_limit, span, "composite signature exceeds 256 nesting levels");
    for (parameters, arguments) |parameter, argument| {
        if (std.mem.eql(u8, src.text(parameter.name), src.text(span))) return argument;
    }
    if (catalog.templates.applications.get(span.start)) |template| {
        var values: [16]typed.Type = undefined;
        for (template.syntax.arguments, 0..) |argument, i| values[i] = try resolve(allocator, catalog, src, sink, .{ .span = argument, .parameters = parameters, .arguments = arguments, .depth = depth + 1 });
        return @import("nominal_catalog.zig").instantiate(catalog, template.declaration, values[0..template.arguments.len], span);
    }
    if (catalog.arrays.templates.get(span.start)) |template| {
        const element = try resolve(allocator, catalog, src, sink, .{ .span = template.syntax.element, .parameters = parameters, .arguments = arguments, .depth = depth + 1 });
        return catalog.instantiateArray(allocator, element, template.length, span, sink);
    }
    return catalog.resolve(src, span, sink);
}
