//! Retained catalog projection and deterministic producer-selected List materialization.
const std = @import("std");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const lists = @import("body_check_list_validate.zig");
const Native = @import("type_catalog.zig").Catalog;
pub const Error = lists.Error;
fn builtin(native: Native, ty: typed.Type, name: []const u8) bool {
    const state = native.templates.store orelse return false;
    const id = state.semantic(ty) orelse return false;
    if (@backingInt(id) >= state.graph.nodes.items.len) return false;
    const key = state.graph.nodes.items[@backingInt(id)].key;
    if (key.base != .named) return false;
    const declaration = state.index.declarations.items[key.base.named];
    const actual = declaration.builtin_name orelse return false;
    return std.mem.eql(u8, actual, name);
}
fn sequence(native: Native, name: []const u8, kind: @import("runtime_values.zig").ManagedKind, element: typed.Type) ?value.Sequence {
    const ty = native.names.get(name) orelse return null;
    if (!ty.isAggregate()) return null;
    if (ty.recordIndex() >= native.records.len or !builtin(native, ty, name)) return null;
    const record = native.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != kind or record.shape.buffer != element) return null;
    return .{ .id = ty, .element = element };
}
fn available(native: Native) bool {
    const state = native.templates.store orelse return false;
    const id = state.index.names.get("List") orelse return false;
    const declaration = state.index.declarations.items[id];
    const name = declaration.builtin_name orelse return false;
    return declaration.kind == .buffer and std.mem.eql(u8, name, "List") and declaration.parameters.len == 1;
}
fn canonicalList(native: Native, record: typed.Record) bool {
    return record.isCollection() and record.collection.kind == .list and builtin(native, record.id, "List");
}
/// Snapshot existing common-phase identities without checking or enumerating any body.
pub fn project(a: std.mem.Allocator, native: Native) Error!value.Catalog {
    if (native.records.len > lists.limit) return error.ComponentProtocol;
    var output: value.Catalog = .{
        .string = sequence(native, "str", .string, .u32),
        .bytes = sequence(native, "bytes", .bytes, .u8),
        .base_count = native.records.len,
        .list_available = available(native),
    };
    var entries: std.ArrayList(value.Sequence) = .empty;
    errdefer entries.deinit(a);
    for (native.records) |record| if (canonicalList(native, record) and supported(native, output, record.id, 0)) {
        try entries.append(a, .{ .id = record.id, .element = record.shape.buffer.? });
    };
    output.lists = try entries.toOwnedSlice(a);
    errdefer a.free(output.lists);
    try lists.catalog(a, output);
    return output;
}
/// Observe native append decisions and recover their original semantic intern sites.
pub fn added(a: std.mem.Allocator, native: Native, base_count: usize) Error![]const value.ListRecipe {
    if (base_count > native.records.len or native.records.len > lists.limit) return error.ComponentProtocol;
    const state = native.templates.store orelse return error.ComponentProtocol;
    const output = try a.alloc(value.ListRecipe, native.records.len - base_count);
    errdefer a.free(output);
    for (native.records[base_count..], output) |record, *item| {
        if (!canonicalList(native, record)) return error.ComponentProtocol;
        const id = state.semantic(record.id) orelse return error.ComponentProtocol;
        if (@backingInt(id) >= state.graph.nodes.items.len) return error.ComponentProtocol;
        item.* = .{ .id = record.id, .element = record.shape.buffer.?, .span = state.graph.nodes.items[@backingInt(id)].site };
    }
    return output;
}
/// Apply validated recipes only; the native catalog makes no body type choices.
pub fn apply(a: std.mem.Allocator, native: *Native, input: value.Input, recipes: []const value.ListRecipe) Error!void {
    try lists.recipes(a, input, recipes);
    if (native.records.len != input.catalog.base_count) return error.ComponentProtocol;
    const actual = try project(a, native.*);
    defer a.free(actual.lists);
    if (!equalProjection(actual, input.catalog)) return error.ComponentProtocol;
    for (recipes) |recipe| {
        const before = native.records.len;
        const id = @import("collection_lower.zig").listType(native, recipe.element, recipe.span) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.ComponentProtocol,
        };
        if (id != recipe.id or native.records.len != before + 1 or !canonicalList(native.*, native.records[before])) return error.ComponentProtocol;
        if (native.records[before].shape.buffer != recipe.element) return error.ComponentProtocol;
    }
}
/// Compare the entire canonical native schemas, not pointer identity or selected fields.
pub fn equalCatalog(a: std.mem.Allocator, left: []const typed.Record, right: []const typed.Record) Error!bool {
    const codec = @import("parser_value.zig");
    const first = try codec.encodeTree(a, []const typed.Record, left, "SLKCAT01");
    defer a.free(first);
    const second = try codec.encodeTree(a, []const typed.Record, right, "SLKCAT01");
    defer a.free(second);
    return std.mem.eql(u8, first, second);
}

fn equalProjection(left: value.Catalog, right: value.Catalog) bool {
    if (left.base_count != right.base_count or left.list_available != right.list_available) return false;
    if (left.lists.len != right.lists.len) return false;
    if (!std.meta.eql(left.string, right.string) or !std.meta.eql(left.bytes, right.bytes)) return false;
    for (left.lists, right.lists) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn supported(native: Native, catalog: value.Catalog, ty: typed.Type, depth: usize) bool {
    if (ty == .i64 or ty == .bool or ty == .unit) return true;
    if (catalog.string) |item| if (item.id == ty) return true;
    if (catalog.bytes) |item| if (item.id == ty) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= native.records.len or depth >= 255) return false;
    const record = native.records[ty.recordIndex()];
    return canonicalList(native, record) and supported(native, catalog, record.shape.buffer.?, depth + 1);
}
