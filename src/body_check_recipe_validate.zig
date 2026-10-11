//! Bounded tagged catalog recipes and exact retained template case authority.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const lists = @import("body_check_list_validate.zig");
const records = @import("body_check_record_validate.zig");
/// Allocation failure or invalid catalog recipe/template authority.
pub const Error = lists.Error;
const Key = struct { kind: enum { list, result, option }, first: typed.Type, second: typed.Type = .unit };
/// Validate native template declaration authority without supplying annotation answers.
pub fn bases(input: value.Input) Error!void {
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
fn key(recipe: value.CatalogRecipe) Key {
    return switch (recipe) {
        .list => |item| .{ .kind = .list, .first = item.element },
        .result => |item| .{ .kind = .result, .first = item.success, .second = item.failure },
        .option => |item| .{ .kind = .option, .first = item.element },
    };
}
fn existing(item: value.Catalog, record: typed.Record) ?Key {
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
    for (input.program.nodes.items) |node| try output.put(a, node.span, {});
    for (input.program.statements.items) |statement| try output.put(a, statement.span, {});
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
    var known: std.AutoHashMapUnmanaged(Key, void) = .empty;
    defer known.deinit(a);
    for (input.catalog.lists) |item| try known.put(a, .{ .kind = .list, .first = item.element }, {});
    for (input.catalog.records) |item| if (existing(input.catalog, item)) |item_key| try known.put(a, item_key, {});
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
        const id = switch (recipe) {
            inline else => |item| item.id,
        };
        const at = switch (recipe) {
            inline else => |item| item.span,
        };
        if (@backingInt(id) != typed.Type.record_base + input.catalog.base_count + index) return error.ComponentProtocol;
        if (at.start > at.end or at.end > input.context.source.len or !allowed_sites.contains(at)) return error.ComponentProtocol;
        const item_key = key(recipe);
        const duplicate = try known.getOrPut(a, item_key);
        if (duplicate.found_existing) return error.ComponentProtocol;
        try dependency(item_key.first, id);
        if (recipe == .result) try dependency(item_key.second, id);
        var item_depth: usize = 2;
        if (item_key.first.isAggregate()) item_depth = 1 + depths[item_key.first.recordIndex()];
        if (recipe == .result and item_key.second.isAggregate()) item_depth = @max(item_depth, 1 + depths[item_key.second.recordIndex()]);
        if (item_depth > 256) return error.ComponentProtocol;
        depths[id.recordIndex()] = item_depth;
        var schema: typed.Record = .{ .id = id, .name = "", .declaration = at, .fields = &.{} };
        if (recipe == .list) {
            if (!input.catalog.list_available) return error.ComponentProtocol;
            schema.managed = true;
            schema.collection.kind = .list;
            schema.shape.buffer = recipe.list.element;
            try entries.append(a, .{ .id = id, .element = recipe.list.element });
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
        const id = switch (recipe) {
            inline else => |item| item.id,
        };
        if (!accepted[id.recordIndex()]) return error.ComponentProtocol;
    }
    try lists.catalog(a, output);
    return output;
}
fn dependency(ty: typed.Type, id: typed.Type) Error!void {
    if (ty == .i64 or ty == .bool or ty == .unit) return;
    if (!ty.isAggregate() or @backingInt(ty) >= @backingInt(id)) return error.ComponentProtocol;
}
