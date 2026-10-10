//! Public checked schema entry; graph rendering depends only on checked inputs.
const std = @import("std");
const graph = @import("schema_graph.zig");
const Compilation = @import("project_compile.zig").Compilation;
/// Errors returned while checking and rendering the public schema.
pub const RenderError = graph.RenderError || @import("frontend_runtime.zig").HostError;
/// Allocate the public schema from a checked project and its resolved export roots.
pub fn render(allocator: std.mem.Allocator, compilation: *Compilation) RenderError![]u8 {
    try compilation.check();
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    return graph.render(allocator, compilation.index, compilation.program.?, roots);
}
