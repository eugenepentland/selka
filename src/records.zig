//! Nominal records, managed prelude types, structural arrays, and layout checking.
const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("source.zig").Source;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;

/// Shared arena-owned runtime type catalog used by semantic checking.
pub const Catalog = @import("type_catalog.zig").Catalog;

/// Collect declarations and the unconditional managed prelude catalog.
pub fn collectWithNames(allocator: std.mem.Allocator, src: Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!Catalog {
    var catalog = try @import("nominal_catalog.zig").collect(allocator, src, program, sink, module_names);
    for (program.nodes.items) |node| if (node.data == .text) {
        const state = catalog.templates.store orelse return error.InternalError;
        const ty = try @import("nominal_catalog.zig").instantiateLengths(&catalog, state.index.names.get("str").?, &.{}, &.{}, node.span);
        try catalog.arrays.resolved.put(allocator, node.span.start, ty);
    } else if (node.data == .bytes) {
        const ty = try catalog.instantiateArray(allocator, .u8, node.data.bytes.len, node.span, sink);
        try catalog.arrays.resolved.put(allocator, node.span.start, ty);
    };
    return catalog;
}
