//! Bounded tagged catalog recipes and exact retained template case authority.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const lists = @import("body_check_list_validate.zig");
const records = @import("body_check_record_validate.zig");
const dictionaries = @import("body_check_dictionary_validate.zig");
const structural = @import("body_check_structural_validate.zig");
/// Allocation failure or invalid catalog recipe/template authority.
pub const Error = lists.Error;
const Key = struct {
    kind: enum { list, result, option, byte_buffer, dict, set, dict_item, dict_keys, dict_values, dict_items, tuple, array },
    first: typed.Type,
    second: typed.Type = .unit,
    length: usize = 0,
    elements: [8]typed.Type = @splat(.unit),
};
/// Validate native template declaration authority without supplying annotation answers.
pub fn bases(input: value.Input) Error!void {
    try dictionaries.bases(input.catalog);
    if (input.catalog.templates.result) |basis| _ = try basisCases(input, basis, true);
    if (input.catalog.templates.option) |basis| _ = try basisCases(input, basis, false);
    if (input.catalog.templates.result) |result| if (input.catalog.templates.option) |option| {
        if (result.id == option.id) return error.ComponentProtocol;
    };
}
fn basisCases(input: value.Input, basis: value.TemplateBasis, result: bool) Error!?@import("ast.zig").Variants {
    if (basis.id >= 1048576 or basis.declaration.start > basis.declaration.end or basis.declaration.end > input.context.source.len) return error.ComponentProtocol;
    if (basis.declaration.start == 0 and basis.declaration.end == 0) return null;
    for (input.program.types.variants) |raw| if (std.meta.eql(raw.name, basis.declaration)) {
        const expected_name = if (result) "Result" else "Option";
        if (!std.mem.eql(u8, input.context.source[raw.name.start..raw.name.end], expected_name)) return error.ComponentProtocol;
        if (input.modules.len == 0) return error.ComponentProtocol;
        var standard = false;
        for (input.modules) |module| {
            if (std.mem.eql(u8, module.context.name, "std_result") and raw.name.start >= module.offset and raw.name.end <= module.offset + module.context.source.len) standard = true;
        }
        if (!standard) return error.ComponentProtocol;
        if (!raw.is_union or raw.fallible != result or raw.type_parameters.len != (if (result) @as(usize, 2) else 1)) return error.ComponentProtocol;
        return raw;
    };
    return error.ComponentProtocol;
}
fn cases(a: std.mem.Allocator, input: value.Input, recipe: value.CatalogRecipe) Error![]const typed.Variant {
    const result = recipe == .result;
    const basis = (if (result) input.catalog.templates.result else input.catalog.templates.option) orelse return error.ComponentProtocol;
    const raw = try basisCases(input, basis, result);
    const output = try a.alloc(typed.Variant, 2);
    const first = if (result) recipe.result.success else recipe.option.element;
    if (raw) |declaration| {
        if (declaration.cases.len != 2) return error.ComponentProtocol;
        var found: u2 = 0;
        for (declaration.cases, output) |item, *out| {
            const name = input.context.source[item.name.start..item.name.end];
            if (item.fields.len != 0) return error.ComponentProtocol;
            const is_first = std.mem.eql(u8, name, if (result) "ok" else "some");
            const is_second = std.mem.eql(u8, name, if (result) "err" else "none");
            if (!is_first and !is_second) return error.ComponentProtocol;
            const bit: u2 = if (is_first) 1 else 2;
            if (found & bit != 0) return error.ComponentProtocol;
            found |= bit;
            var payload: ?typed.Type = null;
            if (result or is_first) {
                const at = item.payload orelse return error.ComponentProtocol;
                const parameter = declaration.type_parameters[if (result and is_second) @as(usize, 1) else 0].name;
                if (!std.mem.eql(u8, input.context.source[at.start..at.end], input.context.source[parameter.start..parameter.end])) return error.ComponentProtocol;
                payload = if (result and is_second) recipe.result.failure else first;
            } else if (item.payload != null) return error.ComponentProtocol;
            out.* = .{ .name = name, .declaration = item.name, .payload = payload };
        }
        if (found != 3) return error.ComponentProtocol;
    } else if (result) {
        output[0] = .{ .name = "ok", .declaration = .{ .start = 0, .end = 0 }, .payload = first };
        output[1] = .{ .name = "err", .declaration = .{ .start = 0, .end = 0 }, .payload = recipe.result.failure };
    } else {
        output[0] = .{ .name = "none", .declaration = .{ .start = 0, .end = 0 }, .payload = null };
        output[1] = .{ .name = "some", .declaration = .{ .start = 0, .end = 0 }, .payload = first };
    }
    return output;
}
fn key(recipe: value.CatalogRecipe) Error!Key {
    return switch (recipe) {
        .list => |item| .{ .kind = .list, .first = item.element },
        .byte_buffer => .{ .kind = .byte_buffer, .first = .unit },
        .result => |item| .{ .kind = .result, .first = item.success, .second = item.failure },
        .option => |item| .{ .kind = .option, .first = item.element },
        .collection => |item| collectionKey(item),
        .structural => |item| switch (item) {
            .tuple => |entry| try tupleKey(entry.elements),
            .array => |entry| .{ .kind = .array, .first = entry.element, .length = entry.length },
        },
    };
}
fn tupleKey(elements: []const typed.Type) Error!Key {
    if (elements.len < 2 or elements.len > 8) return error.ComponentProtocol;
    var result: Key = .{ .kind = .tuple, .first = .unit, .length = elements.len };
    @memcpy(result.elements[0..elements.len], elements);
    return result;
}
fn collectionKey(recipe: value.CollectionRecipe) Key {
    return switch (recipe) {
        .set => |item| .{ .kind = .set, .first = item.element },
        inline else => |item, tag| .{ .kind = @field(@FieldType(Key, "kind"), @tagName(tag)), .first = item.key, .second = item.value },
    };
}
fn existing(item: value.Catalog, record: typed.Record) ?Key {
    if (structural.tuple(record)) {
        var result: Key = .{ .kind = .tuple, .first = .unit, .length = record.fields.len };
        for (record.fields, 0..) |field, index| result.elements[index] = field.ty;
        return result;
    }
    if (structural.array(record)) {
        const shape = record.shape.array.?;
        return .{ .kind = .array, .first = shape.element, .second = shape.key orelse .unit, .length = shape.length };
    }
    if (dictionaries.identify(item, record.id)) |entry| return .{ .kind = switch (entry.kind) {
        .dict => .dict,
        .set => .set,
        .dict_item => .dict_item,
        .dict_keys => .dict_keys,
        .dict_values => .dict_values,
        .dict_items => .dict_items,
    }, .first = entry.key, .second = entry.value };
    if (item.templates.result != null and std.mem.startsWith(u8, record.name, "Result<")) {
        if (typed.resultShape(record.id, item.records)) |shape| return .{ .kind = .result, .first = shape.ok_type, .second = shape.error_type };
    }
    if (item.templates.option != null and std.mem.startsWith(u8, record.name, "Option<")) {
        if (record.shape.variants) |variants| if (@import("prelude.zig").optionCases(variants)) |shape| return .{ .kind = .option, .first = shape.element };
    }
    return null;
}
const Sites = std.AutoHashMapUnmanaged(source.Span, void);
fn sites(a: std.mem.Allocator, input: value.Input) Error!Sites {
    var output: Sites = .empty;
    errdefer output.deinit(a);
    for (input.program.nodes.items) |node| {
        try output.put(a, node.span, {});
        if (node.data == .call) if (node.data.call.owner) |owner| try output.put(a, owner, {});
    }
    for (input.program.statements.items) |statement| {
        try output.put(a, statement.span, {});
        if (statement.data == .assignment and statement.data.assignment.op == .mul) {
            try output.put(a, statement.data.assignment.op_span, {});
        }
    }
    for (input.program.functions) |function| {
        try output.put(a, function.name, {});
        try output.put(a, function.signature.return_type, {});
        if (function.signature.failure_type) |at| try output.put(a, at, {});
        for (function.signature.parameters) |parameter| try output.put(a, parameter.ty, {});
    }
    for (input.program.types.expressions.suffixes) |item| try output.put(a, item.span, {});
    for (input.program.types.expressions.applications) |item| try output.put(a, item.span, {});
    return output;
}
/// Caller-owned arena view validates choices; final schemas are independently materialized and compared.
pub fn expanded(a: std.mem.Allocator, input: value.Input, recipes: []const value.CatalogRecipe) Error!value.Catalog {
    if (input.catalog.records.len != input.catalog.base_count) return error.ComponentProtocol;
    try lists.catalog(a, input.catalog);
    try bases(input);
    if (recipes.len > lists.limit - input.catalog.base_count) return error.ComponentProtocol;
    var known: std.AutoHashMapUnmanaged(Key, typed.Type) = .empty;
    defer known.deinit(a);
    if (input.catalog.templates.byte_buffer.identity != null) try known.put(a, .{ .kind = .byte_buffer, .first = .unit }, input.catalog.templates.byte_buffer.identity.?.id);
    for (input.catalog.lists) |item| try known.put(a, .{ .kind = .list, .first = item.element }, item.id);
    for (input.catalog.records) |item| if (existing(input.catalog, item)) |item_key| try known.put(a, item_key, item.id);
    var allowed_sites = try sites(a, input);
    defer allowed_sites.deinit(a);
    const schemas = try a.alloc(typed.Record, input.catalog.base_count + recipes.len);
    @memcpy(schemas[0..input.catalog.base_count], input.catalog.records);
    var entries: std.ArrayList(value.Sequence) = .empty;
    try entries.appendSlice(a, input.catalog.lists);
    var output = input.catalog;
    output.records = schemas;
    output.base_count = schemas.len;
    const depths = try a.alloc(usize, schemas.len);
    @memset(depths, 1);
    for (recipes, 0..) |recipe, index| {
        const id = value.recipeId(recipe);
        const at = value.recipeSpan(recipe);
        if (@backingInt(id) != typed.Type.record_base + input.catalog.base_count + index) return error.ComponentProtocol;
        const anonymous_tuple = recipe == .structural and recipe.structural == .tuple;
        if (!anonymous_tuple) {
            if (at.start > at.end or at.end > input.context.source.len) return error.ComponentProtocol;
            if (!allowed_sites.contains(at)) return error.ComponentProtocol;
        }
        const item_key = try key(recipe);
        const duplicate = try known.getOrPut(a, item_key);
        if (duplicate.found_existing) return error.ComponentProtocol;
        duplicate.value_ptr.* = id;
        try dependencies(input.catalog, recipe, item_key, id);
        depths[id.recordIndex()] = try recipeDepth(recipe, item_key, depths);
        var schema: typed.Record = .{ .id = id, .name = "", .declaration = at, .fields = &.{} };
        if (recipe == .structural) {
            schema = try structural.schema(a, schemas[0..id.recordIndex()], recipe.structural);
        } else if (recipe == .list) {
            if (!input.catalog.list_available) return error.ComponentProtocol;
            schema.managed = true;
            schema.collection.kind = .list;
            schema.shape.buffer = recipe.list.element;
            try entries.append(a, .{ .id = id, .element = recipe.list.element });
        } else if (recipe == .byte_buffer) {
            if (!input.catalog.templates.byte_buffer.available) return error.ComponentProtocol;
            schema.name = "byte_buffer";
            schema.managed = true;
            schema.collection.kind = .bytes;
            schema.shape.buffer = .u8;
            output.templates.byte_buffer.identity = .{ .id = id, .element = .u8 };
        } else if (dictionaryKind(recipe)) |kind| {
            const owner = if (kind == .dict_keys or kind == .dict_values or kind == .dict_items) known.get(.{ .kind = .dict, .first = item_key.first, .second = item_key.second }) orelse return error.ComponentProtocol else null;
            schema = try dictionaries.schema(a, input.catalog, kind, .{ .id = id, .key = item_key.first, .value = item_key.second, .span = at }, owner);
        } else {
            schema.shape.variants = .{ .fallible = recipe == .result, .is_union = true, .cases = try cases(a, input, recipe) };
            schema.contract.requires_handling = recipe == .result;
        }
        if (schema.shape.variants) |shape| for (shape.cases) |item_case| if (item_case.payload) |payload| {
            if (payload.isAggregate()) {
                const contract = schemas[payload.recordIndex()].contract;
                schema.contract.requires_handling = schema.contract.requires_handling or contract.requires_handling;
                schema.contract.move_only = schema.contract.move_only or contract.move_only;
                schema.contract.storable = schema.contract.storable and contract.storable;
            }
        };
        schema.contract.storable = schema.contract.storable and !schema.contract.requires_handling;
        schemas[id.recordIndex()] = schema;
    }
    output.lists = try entries.toOwnedSlice(a);
    const accepted = try records.policy(a, output);
    defer a.free(accepted);
    for (recipes) |recipe| {
        const id = value.recipeId(recipe);
        if (!accepted[id.recordIndex()]) return error.ComponentProtocol;
    }
    try hashableKeys(a, output);
    try lists.catalog(a, output);
    return output;
}
fn dependency(ty: typed.Type, id: typed.Type) Error!void {
    if (scalar(ty)) return;
    if (!ty.isAggregate() or @backingInt(ty) >= @backingInt(id)) return error.ComponentProtocol;
}

fn recipeDepth(recipe: value.CatalogRecipe, item_key: Key, depths: []const usize) Error!usize {
    var result: usize = if (recipe == .byte_buffer) 1 else 2;
    if (recipe == .structural and recipe.structural == .tuple) {
        for (recipe.structural.tuple.elements) |element| if (element.isAggregate()) {
            result = @max(result, 1 + depths[element.recordIndex()]);
        };
    }
    if (item_key.first.isAggregate()) result = 1 + depths[item_key.first.recordIndex()];
    if (pairRecipe(recipe) and item_key.second.isAggregate()) result = @max(result, 1 + depths[item_key.second.recordIndex()]);
    if (result > 256) return error.ComponentProtocol;
    return result;
}

fn dependencies(catalog: value.Catalog, recipe: value.CatalogRecipe, item: Key, id: typed.Type) Error!void {
    if (recipe == .structural and recipe.structural == .tuple) {
        for (recipe.structural.tuple.elements) |element| try dependency(element, id);
        return;
    }
    if (recipe == .result and item.first.isFile()) {
        const string = catalog.string orelse return error.ComponentProtocol;
        if (item.second != string.id) return error.ComponentProtocol;
    } else try dependency(item.first, id);
    if (pairRecipe(recipe)) try dependency(item.second, id);
}

fn dictionaryKind(recipe: value.CatalogRecipe) ?dictionaries.Kind {
    if (recipe != .collection) return null;
    return switch (recipe.collection) {
        inline else => |_, tag| @field(dictionaries.Kind, @tagName(tag)),
    };
}
fn pairRecipe(recipe: value.CatalogRecipe) bool {
    if (recipe == .result) return true;
    return recipe == .collection and recipe.collection != .set;
}

fn hashableKeys(a: std.mem.Allocator, output: value.Catalog) Error!void {
    const hashable = try records.hashablePolicy(a, output);
    defer a.free(hashable);
    for (output.records) |schema| if (dictionaries.identify(output, schema.id)) |entry| {
        if (entry.kind == .dict or entry.kind == .set) {
            if (entry.key.isAggregate()) {
                if (!hashable[entry.key.recordIndex()]) return error.ComponentProtocol;
            } else if (!scalar(entry.key)) return error.ComponentProtocol;
        }
    };
}

fn scalar(ty: typed.Type) bool {
    return @import("body_check_numeric_validate.zig").scalar(ty);
}
