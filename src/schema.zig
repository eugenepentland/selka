//! Public checked schema entry; graph rendering depends only on checked inputs.
const std = @import("std");
const graph = @import("schema_graph.zig");
const Compilation = @import("project_compile.zig").Compilation;
/// Errors returned while checking and rendering the public schema.
pub const RenderError = graph.RenderError;
fn checkTypeConstructors(compilation: *Compilation) RenderError!void {
    inline for (.{ "records", "variants" }) |category| for (@field(compilation.syntax.types, category)) |declaration| {
        if (declaration.type_parameters.len == 0) continue;
        const original = compilation.src.originalSpan(declaration.name) catch return error.InternalError;
        const unit = compilation.index.units[original.input];
        const id = unit.names.get(compilation.src.text(declaration.name)) orelse return error.InternalError;
        if (unit.symbols.items[id].exported) return compilation.diagnostics.fail(
            "E_SCHEMA_GENERIC_TYPE",
            declaration.name,
            "schema export of nominal type constructors requires generic tooling; VM execution of concrete instances is supported",
        );
    };
}
/// Allocate the public schema from a checked project and its resolved export roots.
pub fn render(allocator: std.mem.Allocator, compilation: *Compilation) RenderError![]u8 {
    try compilation.check();
    try checkTypeConstructors(compilation);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    return graph.render(allocator, compilation.index, compilation.program.?, roots);
}
