//! Retained catalog projection and deterministic producer-selected type materialization.
const std = @import("std");
const nominal = @import("nominal_catalog.zig");
const dictionaries = @import("body_check_dictionary_validate.zig");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const lists = @import("body_check_list_validate.zig");
const record_validate = @import("body_check_record_validate.zig");
const buffer_name = @import("nominal_templates.zig").byte_buffer_name;
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
    if (record.id != ty) return null;
    if (!record.isCollection() or record.collection.kind != kind or record.shape.buffer != element) return null;
    return .{ .id = ty, .element = element };
}
fn template(native: Native, name: []const u8, kind: @import("nominal_templates.zig").Kind, arity: usize) ?value.TemplateBasis {
    const state = native.templates.store orelse return null;
    const id = state.index.names.get(name) orelse return null;
    const declaration = state.index.declarations.items[id];
    const actual = declaration.builtin_name orelse return null;
    if (declaration.kind != kind or !std.mem.eql(u8, actual, name) or declaration.parameters.len != arity) return null;
    return .{ .id = id, .declaration = declaration.name };
}
fn available(native: Native) bool {
    const state = native.templates.store orelse return false;
    const id = state.index.names.get("List") orelse return false;
    const declaration = state.index.declarations.items[id];
    const name = declaration.builtin_name orelse return false;
    return declaration.kind == .buffer and std.mem.eql(u8, name, "List") and declaration.parameters.len == 1;
}
fn bufferBasis(native: Native) value.BufferBasis {
    var identity: ?value.Sequence = null;
    for (native.records) |record| {
        if (!builtin(native, record.id, buffer_name)) continue;
        if (!record.managed or record.collection.kind != .bytes or record.shape.buffer != .u8) continue;
        identity = .{ .id = record.id, .element = .u8 };
        break;
    }
    const state = native.templates.store orelse return .{};
    const existing = template(native, buffer_name, .buffer, 0) != null;
    const addable = !state.index.names.contains(buffer_name) and !state.index.syntax.aliases.contains(buffer_name);
    return .{ .available = existing or addable, .identity = identity };
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
        .records = try a.dupe(typed.Record, native.records),
        .list_available = available(native),
        .templates = .{ .result = template(native, "Result", .result, 2), .option = template(native, "Option", .variants, 1), .byte_buffer = bufferBasis(native), .collections = .{
            .dict = template(native, "dict", .buffer, 2),
            .set = template(native, "set", .buffer, 1),
            .DictItem = template(native, "DictItem", .record, 2),
            .DictKeys = template(native, "DictKeys", .record, 2),
            .DictValues = template(native, "DictValues", .record, 2),
            .DictItems = template(native, "DictItems", .record, 2),
        } },
    };
    errdefer a.free(output.records);
    var entries: std.ArrayList(value.Sequence) = .empty;
    errdefer entries.deinit(a);
    for (native.records) |record| if (canonicalList(native, record)) {
        try entries.append(a, .{ .id = record.id, .element = record.shape.buffer.? });
    };
    output.lists = try entries.toOwnedSlice(a);
    errdefer a.free(output.lists);
    const accepted = try record_validate.policy(a, output);
    defer a.free(accepted);
    var count: usize = 0;
    for (output.lists) |entry| if (accepted[entry.id.recordIndex()]) {
        @constCast(output.lists)[count] = entry;
        count += 1;
    };
    const filtered = try a.dupe(value.Sequence, output.lists[0..count]);
    a.free(output.lists);
    output.lists = filtered;
    try lists.catalog(a, output);
    return output;
}
/// Observe native append decisions and recover their original semantic intern sites.
pub fn added(a: std.mem.Allocator, native: Native, base_count: usize) Error![]const value.CatalogRecipe {
    if (base_count > native.records.len or native.records.len > lists.limit) return error.ComponentProtocol;
    const state = native.templates.store orelse return error.ComponentProtocol;
    const output = try a.alloc(value.CatalogRecipe, native.records.len - base_count);
    errdefer a.free(output);
    for (native.records[base_count..], output) |record, *item| {
        const id = state.semantic(record.id) orelse return error.ComponentProtocol;
        if (@backingInt(id) >= state.graph.nodes.items.len) return error.ComponentProtocol;
        const site = state.graph.nodes.items[@backingInt(id)].site;
        if (canonicalList(native, record)) {
            item.* = .{ .list = .{ .id = record.id, .element = record.shape.buffer.?, .span = site } };
        } else if (builtin(native, record.id, "Result")) {
            const shape = typed.resultShape(record.id, native.records) orelse return error.ComponentProtocol;
            item.* = .{ .result = .{ .id = record.id, .success = shape.ok_type, .failure = shape.error_type, .span = site } };
        } else if (builtin(native, record.id, "Option")) {
            const shape = @import("prelude.zig").optionCases(record.shape.variants orelse return error.ComponentProtocol) orelse return error.ComponentProtocol;
            item.* = .{ .option = .{ .id = record.id, .element = shape.element, .span = site } };
        } else if (builtin(native, record.id, buffer_name)) {
            item.* = .{ .byte_buffer = .{ .id = record.id, .span = site } };
        } else if (try collectionRecipe(native, record, site)) |recipe| {
            item.* = recipe;
        } else return error.ComponentProtocol;
    }
    return output;
}
/// Apply validated recipes only; the native catalog makes no body type choices.
pub fn apply(a: std.mem.Allocator, native: *Native, input: value.Input, recipes: []const value.CatalogRecipe) Error!void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    _ = try @import("body_check_recipe_validate.zig").expanded(arena.allocator(), input, recipes);
    if (native.records.len != input.catalog.base_count) return error.ComponentProtocol;
    const actual = try project(a, native.*);
    defer a.free(actual.lists);
    defer a.free(actual.records);
    if (!equalProjection(actual, input.catalog)) return error.ComponentProtocol;
    if (!try equalCatalog(a, actual.records, input.catalog.records)) return error.ComponentProtocol;
    for (recipes) |recipe| {
        const before = native.records.len;
        const id = switch (recipe) {
            .list => |item| @import("collection_lower.zig").listType(native, item.element, item.span),
            .byte_buffer => |item| @import("collection_lower.zig").preludeType(native, buffer_name, item.span),
            .result => |item| nominal.instantiateLengths(native, (input.catalog.templates.result orelse return error.ComponentProtocol).id, &.{ item.success, item.failure }, &.{}, item.span),
            .option => |item| nominal.instantiateLengths(native, (input.catalog.templates.option orelse return error.ComponentProtocol).id, &.{item.element}, &.{}, item.span),
            .collection => |item| switch (item) {
                .set => |entry| collectionApply(native, input.catalog, .set, .{ .id = entry.id, .key = entry.element, .value = .unit, .span = entry.span }),
                inline else => |entry, tag| collectionApply(native, input.catalog, @field(dictionaries.Kind, @tagName(tag)), entry),
            },
        } catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.ComponentProtocol,
        };
        const expected = value.recipeId(recipe);
        if (id != expected or native.records.len != before + 1) return error.ComponentProtocol;
        const observed = try added(a, native.*, before);
        defer a.free(observed);
        if (!std.meta.eql(recipe, observed[0])) return error.ComponentProtocol;
    }
}
/// Compare the entire canonical native schemas, not pointer identity or selected fields.
pub fn equalCatalog(a: std.mem.Allocator, left: []const typed.Record, right: []const typed.Record) Error!bool {
    const codec = @import("parser_value.zig");
    const first = try codec.encodeTreeProfile(a, []const typed.Record, left, "SLKCAT01", .body);
    defer a.free(first);
    const second = try codec.encodeTreeProfile(a, []const typed.Record, right, "SLKCAT01", .body);
    defer a.free(second);
    return std.mem.eql(u8, first, second);
}

fn equalProjection(left: value.Catalog, right: value.Catalog) bool {
    if (!std.meta.eql(left.templates, right.templates)) return false;
    if (left.base_count != right.base_count or left.list_available != right.list_available) return false;
    if (left.lists.len != right.lists.len) return false;
    if (!std.meta.eql(left.string, right.string) or !std.meta.eql(left.bytes, right.bytes)) return false;
    for (left.lists, right.lists) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}

fn collectionApply(native: *Native, catalog: value.Catalog, kind: dictionaries.Kind, item: value.DictionaryRecipe) @import("diagnostic.zig").Error!typed.Type {
    const authority = dictionaries.basis(catalog, kind) orelse return error.InternalError;
    return nominal.instantiateLengths(native, authority.id, if (kind == .set) &.{item.key} else &.{ item.key, item.value }, &.{}, item.span);
}
fn collectionRecipe(native: Native, record: typed.Record, site: @import("source.zig").Span) Error!?value.CatalogRecipe {
    const helpers = dictionaries;
    if (builtin(native, record.id, "dict")) return .{ .collection = .{ .dict = .{
        .id = record.id,
        .key = record.collection.key orelse return error.ComponentProtocol,
        .value = record.shape.buffer orelse return error.ComponentProtocol,
        .span = site,
    } } };
    if (builtin(native, record.id, "set")) return .{ .collection = .{ .set = .{ .id = record.id, .element = record.collection.key orelse return error.ComponentProtocol, .span = site } } };
    inline for (.{ helpers.Kind.dict_item, helpers.Kind.dict_keys, helpers.Kind.dict_values, helpers.Kind.dict_items }) |kind| {
        if (builtin(native, record.id, helpers.name(kind))) {
            var key: typed.Type = undefined;
            var element: typed.Type = undefined;
            if (kind == .dict_item) {
                if (record.fields.len != 2) return error.ComponentProtocol;
                key = record.fields[0].ty;
                element = record.fields[1].ty;
            } else {
                if (record.fields.len != 1) return error.ComponentProtocol;
                const mapping = record.fields[0].ty;
                if (!builtin(native, mapping, "dict")) return error.ComponentProtocol;
                const schema = native.records[mapping.recordIndex()];
                key = schema.collection.key orelse return error.ComponentProtocol;
                element = schema.shape.buffer orelse return error.ComponentProtocol;
            }
            const recipe: value.DictionaryRecipe = .{ .id = record.id, .key = key, .value = element, .span = site };
            return .{ .collection = @unionInit(value.CollectionRecipe, @tagName(kind), recipe) };
        }
    }
    return null;
}
