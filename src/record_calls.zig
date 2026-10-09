//! Resolve Python constructor calls through declaration identities, not spelling guesses.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const templates = @import("nominal_templates.zig");
const Catalog = @import("records.zig").Catalog;
const Call = @import("call_arguments.zig").Call;

/// One declared field a constructor call may supply or default: its source name
/// and the backing node id of its declared literal default, when it has one.
const Field = struct { name: source.Span, default_value: ?usize = null };

/// Lower calls targeting ordinary records to the existing named-field syntax.
pub fn lower(allocator: std.mem.Allocator, src: source.Source, catalog: Catalog, nodes: []const ast.Node, call: Call, sink: *diagnostic.Sink) diagnostic.Error!?ast.Node {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    if (catalog.templates.applications.get(call.name.start)) |application| {
        const declaration = catalog.templates.store.?.index.declarations.items[application.declaration];
        if (declaration.kind == .record) {
            const node = try construct(allocator, src, nodes, call, try templateFields(allocator, declaration.fields), sink);
            return node;
        }
    }
    const ty = try recordType(src, catalog, call.name, sink) orelse return null;
    const node = try construct(allocator, src, nodes, call, try checkedFields(allocator, catalog.records[ty.recordIndex()].fields), sink);
    return node;
}
/// Normalize a generic record template's fields for construction.
fn templateFields(allocator: std.mem.Allocator, declarations: []const templates.Field) std.mem.Allocator.Error![]const Field {
    const fields = try allocator.alloc(Field, declarations.len);
    for (declarations, fields) |declaration, *out| out.* = .{ .name = declaration.name, .default_value = declaration.default_value };
    return fields;
}
/// Normalize a checked record's fields for construction.
fn checkedFields(allocator: std.mem.Allocator, declarations: []const typed.Field) std.mem.Allocator.Error![]const Field {
    const fields = try allocator.alloc(Field, declarations.len);
    for (declarations, fields) |declaration, *out| out.* = .{ .name = declaration.declaration, .default_value = declaration.default_value };
    return fields;
}
/// Map a constructor call to the record's named-field initializers. Supplied
/// positional and named arguments come first, in source order; every field the
/// call omits and whose declaration carries a default contributes one trailing
/// initializer referencing that declared literal node.
fn construct(allocator: std.mem.Allocator, src: source.Source, nodes: []const ast.Node, call: Call, declarations: []const Field, sink: *diagnostic.Sink) diagnostic.Error!ast.Node {
    if (call.arguments.len > declarations.len) return sink.fail("E_ARITY", call.name, "too many arguments for this record");
    const labels = try allocator.alloc([]const u8, declarations.len);
    for (declarations, labels) |field, *label| label.* = src.text(field.name);
    const sites = try allocator.alloc(source.Span, call.arguments.len);
    for (call.arguments, sites) |argument, *site| site.* = nodes[@backingInt(argument)].span;
    try @import("frontend_named_fields.zig").require(sink, call.name, "E_NAMED_FIELDS", .{ .labels = labels, .sites = sites, .names = call.argument_names });
    const supplied = try allocator.alloc(bool, declarations.len);
    defer allocator.free(supplied);
    @memset(supplied, false);
    for (call.arguments, 0..) |_, index| {
        const keyword = if (call.argument_names.len == 0) null else call.argument_names[index];
        const at = if (keyword) |name| declarationIndex(src, declarations, name) else index;
        if (at) |found| supplied[found] = true;
    }
    var fields: std.ArrayList(ast.FieldInit) = .empty;
    for (call.arguments, 0..) |value, index| {
        const keyword = if (call.argument_names.len == 0) null else call.argument_names[index];
        const declaration = declarations[if (keyword) |name| declarationIndex(src, declarations, name) orelse index else index];
        try fields.append(allocator, .{ .name = keyword orelse declaration.name, .value = value });
    }
    for (declarations, 0..) |declaration, index| {
        if (supplied[index]) continue;
        const value = declaration.default_value orelse continue;
        try fields.append(allocator, .{ .name = declaration.name, .value = @fromBackingInt(value), .default = true });
    }
    return .{ .span = call.name, .data = .{ .record = .{ .name = call.name, .fields = try fields.toOwnedSlice(allocator) } } };
}
/// The index of the declaration a named argument binds, or null when no field
/// has that spelling; the caller then keeps the diagnostic-producing fallback.
fn declarationIndex(src: source.Source, declarations: []const Field, name: source.Span) ?usize {
    for (declarations, 0..) |declaration, index| {
        if (std.mem.eql(u8, src.text(declaration.name), src.text(name))) return index;
    }
    return null;
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
