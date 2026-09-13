//! Resolve Python payload-variant construction `Type.case(value)` through declared identities.
//! The legacy surface spells the same construction `new Type.case(value)`; the Python surface
//! reuses ordinary call syntax, so the checker rewrites the call before resolving a function.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("records.zig").Catalog;
const Call = @import("call_arguments.zig").Call;

/// Lower `Type.case(value)` to the existing variant node when the owner names a declared
/// enum or tagged union and the member names one of its cases. Returns null for every other
/// call, leaving domain functions, collection methods and module functions untouched.
pub fn lower(src: source.Source, catalog: Catalog, call: Call, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!?ast.Node {
    const owner = call.owner orelse return null;
    if (call.type_arguments.len != 0) return null;
    const ty = try catalog.variantType(src, owner, sink) orelse return null;
    const schema = catalog.records[ty.recordIndex()].shape.variants.?;
    if (!hasCase(schema, src.text(call.name))) return null;
    try @import("call_arguments.zig").positional(call, sink);
    if (call.arguments.len != 1) return sink.fail(
        "E_ARITY",
        call.name,
        "variant construction takes exactly one payload; an empty case is written without parentheses",
    );
    return .{ .span = span, .data = .{ .variant = .{ .ty = owner, .name = call.name, .value = call.arguments[0] } } };
}

fn hasCase(schema: @import("typed.zig").Variants, name: []const u8) bool {
    for (schema.cases) |case| if (std.mem.eql(u8, case.name, name)) return true;
    return false;
}
