//! Staged nominal type syntax must not reach lowering without template semantics.
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Check declared requirements, then explicitly reject unsupported nominal specialization.
/// Parsing and module interface tools can retain the new syntax independently.
pub fn requireImplemented(src: source.Source, program: ast.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
    var first: ?source.Span = null;
    inline for (.{ "records", "variants" }) |category| {
        for (@field(program.types, category)) |declaration| {
            if (declaration.type_parameters.len == 0) continue;
            _ = try @import("generic_requirements.zig").resolve(sink.allocator, src, declaration.type_parameters, sink);
            if (first == null) first = declaration.name;
        }
    }
    if (first == null and program.types.expressions.applications.len != 0) first = program.types.expressions.applications[0].span;
    if (first) |span| return sink.fail("E_GENERIC_TYPE_UNSUPPORTED", span, "nominal type templates are parsed, but semantic specialization is not implemented yet");
}
