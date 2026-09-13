//! Resolve Python constructor calls through declaration identities, not spelling guesses.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const Catalog = @import("records.zig").Catalog;
const Call = @import("call_arguments.zig").Call;

/// Lower calls targeting ordinary records to the existing named-field syntax.
pub fn lower(allocator: std.mem.Allocator, src: source.Source, catalog: Catalog, call: Call, sink: *diagnostic.Sink) diagnostic.Error!?ast.Node {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    if (catalog.templates.applications.get(call.name.start)) |application| {
        const declaration = catalog.templates.store.?.index.declarations.items[application.declaration];
        if (declaration.kind == .record) {
            const node = try construct(allocator, call, declaration.fields, sink);
            return node;
        }
    }
    const ty = try recordType(src, catalog, call.name, sink) orelse return null;
    const node = try construct(allocator, call, catalog.records[ty.recordIndex()].fields, sink);
    return node;
}
fn construct(allocator: std.mem.Allocator, call: Call, declarations: anytype, sink: *diagnostic.Sink) diagnostic.Error!ast.Node {
    if (call.arguments.len > declarations.len) return sink.fail("E_ARITY", call.name, "too many arguments for this record");
    const fields = try allocator.alloc(ast.FieldInit, call.arguments.len);
    for (fields, call.arguments, 0..) |*field, value, index| {
        const keyword = if (call.argument_names.len == 0) null else call.argument_names[index];
        const declaration = declarations[index];
        const name = if (@hasField(@TypeOf(declaration), "declaration")) declaration.declaration else declaration.name;
        field.* = .{ .name = keyword orelse name, .value = value };
    }
    return .{ .span = call.name, .data = .{ .record = .{ .name = call.name, .fields = fields } } };
}
fn recordType(src: source.Source, catalog: Catalog, name: source.Span, sink: *diagnostic.Sink) diagnostic.Error!?typed.Type {
    const applied = catalog.arrays.resolved.get(name.start);
    const ty = applied orelse named: {
        if (catalog.module_names) |names| {
            if (try names.symbolKind(name) != .type) return null;
            break :named try catalog.resolve(src, name, sink);
        }
        break :named catalog.names.get(src.text(name)) orelse return null;
    };
    if (!ty.isAggregate()) return null;
    if (!catalog.records[ty.recordIndex()].isRecord()) return null;
    return ty;
}
