//! Nominal records, managed prelude types, structural arrays, and layout checking.
const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("source.zig").Source;
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Names = @import("module_names.zig").Names;
const builtin = @import("builtin");
const typed = @import("typed.zig");
const literals_fact = @import("ast_literals.zig");

/// Shared arena-owned runtime type catalog used by semantic checking.
pub const Catalog = @import("type_catalog.zig").Catalog;

/// Collect declarations and the unconditional managed prelude catalog.
pub fn collectWithNames(allocator: std.mem.Allocator, src: Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!Catalog {
    var catalog = try @import("nominal_catalog.zig").collect(allocator, src, program, sink, module_names);
    // A merged program records its literals; one that was not is scanned, as every program once was.
    const scanned: []const ast.Literal = if (program.facts.literals == null) try literals_fact.scan(allocator, src, program) else &.{};
    defer allocator.free(scanned);
    const literals = program.facts.literals orelse scanned;
    // A Debug compiler holds the recorded list against the scan it replaces.
    if (builtin.mode == .debug and program.facts.literals != null and program.facts.loader == null) {
        const check = try literals_fact.scan(allocator, src, program);
        defer allocator.free(check);
        std.debug.assert(literals_fact.same(check, literals));
    }
    try catalog.arrays.resolved.ensureUnusedCapacity(allocator, std.math.cast(u32, literals.len) orelse return error.InternalError);
    // Every text literal asks for the one `str` type and is told the same answer once the first has interned it, so only the first asks.
    var text: ?typed.Type = null;
    for (literals) |literal| {
        if (literal.bytes) |length| {
            // Managed bytes need no array schema; concrete fixed-array contexts intern their decoded shape when the expression is checked.
            const ty = try catalog.instantiateArray(allocator, .u8, length, literal.span, sink);
            catalog.arrays.resolved.putAssumeCapacity(literal.span.start, ty);
        } else {
            if (text == null) {
                const state = catalog.templates.store orelse return error.InternalError;
                text = try @import("nominal_catalog.zig").instantiateLengths(&catalog, state.index.names.get("str").?, &.{}, &.{}, literal.span);
            }
            catalog.arrays.resolved.putAssumeCapacity(literal.span.start, text.?);
        }
    }
    // Last, so a program that already materialized the buffer keeps its type table order.
    try @import("nominal_catalog.zig").materializeGenericBareNames(&catalog, src, program);
    return catalog;
}
