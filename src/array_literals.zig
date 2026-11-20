//! Contextual fixed-array and enum-indexed-table literals for the Python surface.
//! A list literal whose expected type is `[N]T` builds the array, and a dict literal whose
//! expected type is `[Kind]T` builds the table; neither spelling needs a `new` keyword.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("records.zig").Catalog;

/// Stable diagnostic code for a list literal whose length differs from its expected array.
pub const length_code = "E_ARRAY_LENGTH";

/// Stable diagnostic code for a table entry key that does not name one of its enum cases.
pub const key_code = "E_TABLE_KEY";

/// Fixed numeric array shape of an expected type, or null for every other type.
pub fn fixed(catalog: Catalog, ty: typed.Type) ?typed.Array {
    if (!ty.isAggregate()) return null;
    const shape = catalog.records[ty.recordIndex()].shape.array orelse return null;
    return if (shape.key == null) shape else null;
}

/// Enum key type of an expected enum-indexed table, or null for every other type.
pub fn table(catalog: Catalog, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate()) return null;
    return catalog.records[ty.recordIndex()].tableKey();
}

/// Report a list literal whose element count differs from its expected fixed array length.
pub fn wrongLength(allocator: std.mem.Allocator, span: source.Span, found: usize, shape: typed.Array, sink: *diagnostic.Sink) diagnostic.Error {
    const message = std.fmt.allocPrint(
        allocator,
        "list literal has {d} element(s); the expected fixed array holds exactly {d}",
        .{ found, shape.length },
    ) catch return error.OutOfMemory;
    return sink.fail(length_code, span, message);
}

/// Source, declarations and the table's own key enum, resolved once per literal.
pub const Context = struct { src: source.Source, syntax: ast.Program, catalog: Catalog, key: typed.Type };

/// Translate `{Kind.a: v, ...}` entry nodes into the named initializers a table construction uses.
/// Each key must name a case of the table's own key enum; the value nodes are passed through
/// unchanged so the ordinary complete-accounting rules report duplicates and missing cases.
pub fn initializers(
    allocator: std.mem.Allocator,
    context: Context,
    entries: []const ast.NodeId,
    sink: *diagnostic.Sink,
) diagnostic.Error![]const ast.FieldInit {
    const fields = try allocator.alloc(ast.FieldInit, entries.len / 2);
    for (fields, 0..) |*field, index| {
        const name = try caseName(context.src, context.syntax, context.catalog, context.key, entries[index * 2], sink);
        field.* = .{ .name = name, .value = entries[index * 2 + 1] };
    }
    return fields;
}

const key_shape = "table entry keys name a case of the table's key enum, such as `Kind.first`";

fn caseName(
    src: source.Source,
    syntax: ast.Program,
    catalog: Catalog,
    key: typed.Type,
    id: ast.NodeId,
    sink: *diagnostic.Sink,
) diagnostic.Error!source.Span {
    const node = syntax.nodes.items[@backingInt(id)];
    const qualifier: source.Span, const name: source.Span = switch (node.data) {
        .variant => |variant| .{ variant.ty, variant.name },
        .field => |field| qualified: {
            const base = syntax.nodes.items[@backingInt(field.base)];
            if (base.data != .name) return sink.fail(key_code, node.span, key_shape);
            break :qualified .{ base.data.name, field.name };
        },
        else => return sink.fail(key_code, node.span, key_shape),
    };
    const ty = try catalog.variantType(src, qualifier, sink) orelse return sink.fail(key_code, node.span, key_shape);
    if (ty != key) return sink.fail(key_code, node.span, "table entry key names a case of a different enum than the table's key");
    return name;
}
