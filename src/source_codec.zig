//! Resolve source codec operations to methods selected by the domain declaration.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// Recognize reserved source codec operation names.
pub fn operation(name: []const u8) bool {
    return std.mem.eql(u8, name, "codec_encode") or std.mem.eql(u8, name, "codec_decode");
}

/// Preserve source operands while selecting the declared public codec method.
/// Complete signature, data-graph and transitive-effect validation runs after bodies.
pub fn resolve(src: source.Source, program: ast.Program, catalog: @import("records.zig").Catalog, call: Call, sink: *diagnostic.Sink) diagnostic.Error!Call {
    if (!operation(src.text(call.name)) or call.owner != null) return call;
    if (call.type_arguments.len != 1 or call.arguments.len != 1)
        return sink.fail("E_CODEC_ARITY", call.name, "codec operation requires one explicit domain type and one value argument");
    const target = call.type_arguments[0];
    const ty = try catalog.resolve(src, target, sink);
    _ = try catalog.domain(ty, target, sink);
    for (program.types.domains) |domain| {
        if (try catalog.resolve(src, domain.name, sink) != ty) continue;
        const codec = domain.codec orelse return sink.fail("E_CODEC_REQUIRED", target, "domain has no declared codec");
        return .{ .owner = target, .name = if (std.mem.eql(u8, src.text(call.name), "codec_encode")) codec.encode else codec.decode, .arguments = call.arguments };
    }
    return sink.fail("E_CODEC_REQUIRED", target, "domain has no declared codec");
}
