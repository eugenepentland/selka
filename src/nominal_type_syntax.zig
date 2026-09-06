//! Staged nominal type syntax must not reach lowering without template semantics.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Check declared requirements, then explicitly reject unsupported nominal specialization.
/// Parsing and module interface tools can retain the new syntax independently.
pub fn requireImplemented(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*@import("module_names.zig").Names) diagnostic.Error!void {
    var first: ?source.Span = null;
    inline for (.{ "records", "variants" }) |category| {
        for (@field(program.types, category)) |declaration| {
            if (declaration.type_parameters.len == 0) continue;
            if (first == null) first = declaration.name;
        }
    }
    if (first == null and program.types.expressions.applications.len != 0) first = program.types.expressions.applications[0].span;
    if (first) |span| {
        const index = try @import("nominal_templates.zig").collect(allocator, src, program, sink, names);
        var graph = try @import("nominal_layouts.zig").collect(allocator, &index, sink);
        defer graph.deinit();
        return sink.fail("E_GENERIC_TYPE_UNSUPPORTED", span, "nominal type specialization and executable layouts are not implemented yet");
    }
}
