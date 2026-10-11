//! Canonical structural tuples and fixed arrays, without nominal template authority.
const std = @import("std");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
/// Allocation and structural protocol failures.
pub const Error = error{ OutOfMemory, ComponentProtocol };

fn copyable(record: typed.Record) bool {
    if (record.managed or record.shape.hasRuntimeIdentity() or record.shape.builtin != .none) return false;
    if (record.contract.callback != null or record.contract.codec != null or record.contract.codec_declared) return false;
    if (record.contract.move_only) return false;
    if (!record.contract.storable and !record.contract.requires_handling) return false;
    for (record.fields) |field| if (field.boxed) return false;
    return true;
}
/// Retained tuples may originate in annotations; their field names remain positional.
pub fn tuple(record: typed.Record) bool {
    return copyable(record) and tupleLayout(record);
}
/// Layout authority is independent of whether current body policy admits its ownership.
pub fn tupleLayout(record: typed.Record) bool {
    if (!record.isRecord() or !record.shape.tuple) return false;
    if (record.fields.len < 2 or record.fields.len > 8) return false;
    for (record.fields, 0..) |field, index| {
        if (field.default_value != null or field.name.len != 2) return false;
        if (field.name[0] != '$' or field.name[1] != '0' + index) return false;
    }
    return true;
}
/// Fixed arrays carry no domain, variant, tuple or runtime identity.
pub fn array(record: typed.Record) bool {
    const shape = record.shape.array orelse return false;
    if (!copyable(record) or record.shape.tuple) return false;
    if (record.shape.domain != null or record.shape.variants != null) return false;
    if (shape.key == null and record.fields.len != 0) return false;
    return true;
}
/// Build an arena schema for structural validation; native materialization remains independent.
pub fn schema(a: std.mem.Allocator, records: []const typed.Record, item_recipe: value.StructuralRecipe) Error!typed.Record {
    switch (item_recipe) {
        .tuple => |item| {
            if (item.elements.len < 2 or item.elements.len > 8) return error.ComponentProtocol;
            const fields = try a.alloc(typed.Field, item.elements.len);
            var contract: typed.RecordContract = .{};
            for (item.elements, fields, 0..) |element, *field, index| {
                field.* = .{ .name = try typed.positionalFieldName(a, index), .declaration = .{ .start = 0, .end = 0 }, .ty = element };
                contract.storable = contract.storable and typed.storable(element, records);
                contract.move_only = contract.move_only or typed.moveOnly(element, records);
                contract.requires_handling = contract.requires_handling or typed.requiresHandling(element, records);
            }
            contract.storable = contract.storable and !contract.requires_handling;
            return .{ .id = item.id, .name = "", .declaration = .{ .start = 0, .end = 0 }, .fields = fields, .shape = .{ .tuple = true }, .contract = contract };
        },
        .array => |item| return .{
            .id = item.id,
            .name = "",
            .declaration = item.span,
            .fields = &.{},
            .shape = .{ .array = .{ .element = item.element, .length = item.length } },
            .contract = .{
                .storable = item.length == 0 or typed.storable(item.element, records),
                .move_only = item.length != 0 and typed.moveOnly(item.element, records),
                .requires_handling = item.length != 0 and typed.requiresHandling(item.element, records),
            },
        },
    }
}
/// Recover direct tuple/array appends before consulting the nominal graph.
pub fn recipe(a: std.mem.Allocator, record: typed.Record) Error!?value.CatalogRecipe {
    if (record.shape.tuple) {
        if (!tuple(record) or record.declaration.start != 0 or record.declaration.end != 0) return error.ComponentProtocol;
        const elements = try a.alloc(typed.Type, record.fields.len);
        errdefer a.free(elements);
        for (record.fields, elements) |field, *element| {
            if (field.declaration.start != 0 or field.declaration.end != 0) return error.ComponentProtocol;
            element.* = field.ty;
        }
        return .{ .structural = .{ .tuple = .{ .id = record.id, .elements = elements } } };
    }
    if (record.shape.array) |shape| {
        if (!array(record) or shape.key != null) return error.ComponentProtocol;
        return .{ .structural = .{ .array = .{ .id = record.id, .element = shape.element, .length = shape.length, .span = record.declaration } } };
    }
    return null;
}
