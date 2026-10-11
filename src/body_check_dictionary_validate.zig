//! Closed dictionary/set/view identities and typed operation associations.
const std = @import("std");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Closed canonical dictionary and live-view recipe roles.
pub const Kind = enum { dict, set, dict_item, dict_keys, dict_values, dict_items };
/// Exact retained collection key and value identities.
pub const Descriptor = struct { kind: Kind, key: typed.Type, value: typed.Type };
/// Native declaration spelling for each injected collection authority.
pub fn name(kind: Kind) []const u8 {
    return switch (kind) {
        .dict => "dict",
        .set => "set",
        .dict_item => "DictItem",
        .dict_keys => "DictKeys",
        .dict_values => "DictValues",
        .dict_items => "DictItems",
    };
}
/// Nullable template identity; no display name can supply missing authority.
pub fn basis(catalog: value.Catalog, kind: Kind) ?value.TemplateBasis {
    return switch (kind) {
        .dict => catalog.templates.collections.dict,
        .set => catalog.templates.collections.set,
        .dict_item => catalog.templates.collections.DictItem,
        .dict_keys => catalog.templates.collections.DictKeys,
        .dict_values => catalog.templates.collections.DictValues,
        .dict_items => catalog.templates.collections.DictItems,
    };
}
/// Validate unique synthesized collection declarations independently of requested uses.
pub fn bases(catalog: value.Catalog) Error!void {
    var identities: [6]usize = undefined;
    var count: usize = 0;
    inline for (.{ Kind.dict, Kind.set, Kind.dict_item, Kind.dict_keys, Kind.dict_values, Kind.dict_items }) |kind| {
        if (basis(catalog, kind)) |item| {
            if (item.id >= 1048576 or item.declaration.start != 0 or item.declaration.end != 0) return error.ComponentProtocol;
            for (identities[0..count]) |id| if (id == item.id) return error.ComponentProtocol;
            if (catalog.templates.result) |other| if (other.id == item.id) return error.ComponentProtocol;
            if (catalog.templates.option) |other| if (other.id == item.id) return error.ComponentProtocol;
            identities[count] = item.id;
            count += 1;
        }
    }
}
fn matches(catalog: value.Catalog, record: typed.Record, kind: Kind) bool {
    const authority = basis(catalog, kind) orelse return false;
    if (!std.meta.eql(record.declaration, authority.declaration)) return false;
    const prefix = name(kind);
    if (record.name.len <= prefix.len or record.name[prefix.len] != '<') return false;
    return std.mem.startsWith(u8, record.name, prefix);
}
/// Recover immutable argument roles from the retained common schema.
pub fn identify(catalog: value.Catalog, ty: typed.Type) ?Descriptor {
    if (!ty.isAggregate() or ty.recordIndex() >= catalog.records.len) return null;
    const record = catalog.records[ty.recordIndex()];
    if (!contract(record)) return null;
    if (record.collection.kind == .dictionary and record.managed) {
        if (!dictionaryShape(record)) return null;
        const kind: Kind = if (record.collection.set) .set else .dict;
        if (!matches(catalog, record, kind)) return null;
        const key = record.collection.key orelse return null;
        const element = record.shape.buffer orelse return null;
        if (kind == .set and element != .unit) return null;
        return .{ .kind = kind, .key = key, .value = element };
    }
    if (matches(catalog, record, .dict_item) and plainShape(record) and record.fields.len == 2) {
        if (record.shape.builtin != .none) return null;
        if (!std.mem.eql(u8, record.fields[0].name, "key") or !std.mem.eql(u8, record.fields[1].name, "value")) return null;
        return .{ .kind = .dict_item, .key = record.fields[0].ty, .value = record.fields[1].ty };
    }
    if (record.shape.builtin != .live_view or !plainShape(record) or record.fields.len != 1) return null;
    if (!std.mem.eql(u8, record.fields[0].name, "mapping")) return null;
    const mapping = record.fields[0].ty;
    if (!mapping.isAggregate() or mapping.recordIndex() >= catalog.records.len) return null;
    const owner = catalog.records[mapping.recordIndex()];
    if (!matches(catalog, owner, .dict) or owner.collection.kind != .dictionary or owner.collection.set) return null;
    if (!dictionaryShape(owner) or !contract(owner)) return null;
    inline for (.{ Kind.dict_keys, Kind.dict_values, Kind.dict_items }) |kind| if (matches(catalog, record, kind)) {
        return .{ .kind = kind, .key = owner.collection.key orelse return null, .value = owner.shape.buffer orelse return null };
    };
    return null;
}
fn contract(record: typed.Record) bool {
    if (record.contract.callback != null or record.contract.codec != null or record.contract.codec_declared) return false;
    if (record.contract.move_only or record.contract.requires_handling or !record.contract.storable) return false;
    return true;
}
fn plainShape(record: typed.Record) bool {
    if (!record.isRecord() or record.managed or record.shape.tuple) return false;
    return std.meta.eql(record.collection, @as(@import("type_identity.zig").CollectionShape, .{}));
}
fn dictionaryShape(record: typed.Record) bool {
    if (record.fields.len != 0 or record.shape.array != null or record.shape.domain != null) return false;
    if (record.shape.variants != null or record.shape.resource != null or record.shape.tuple) return false;
    return record.shape.builtin == .none;
}
/// Virtual schemas validate producer graphs; native application independently compares complete schemas.
pub fn schema(a: std.mem.Allocator, catalog: value.Catalog, kind: Kind, recipe: value.DictionaryRecipe, owner: ?typed.Type) Error!typed.Record {
    const authority = basis(catalog, kind) orelse return error.ComponentProtocol;
    var output: typed.Record = .{ .id = recipe.id, .name = try std.fmt.allocPrint(a, "{s}<>", .{name(kind)}), .declaration = authority.declaration, .fields = &.{} };
    if (kind == .dict or kind == .set) {
        output.managed = true;
        output.collection = .{ .kind = .dictionary, .key = recipe.key, .set = kind == .set };
        output.shape.buffer = recipe.value;
    } else if (kind == .dict_item) {
        output.fields = try a.dupe(typed.Field, &.{ .{ .name = "key", .declaration = authority.declaration, .ty = recipe.key }, .{ .name = "value", .declaration = authority.declaration, .ty = recipe.value } });
    } else {
        const mapping_type = owner orelse return error.ComponentProtocol;
        output.fields = try a.dupe(typed.Field, &.{.{ .name = "mapping", .declaration = authority.declaration, .ty = mapping_type }});
        output.shape.builtin = .live_view;
    }
    return output;
}
/// Closed buffer opcode checking, distinct from source dictionary/set semantics.
pub fn operation(item: Descriptor, owner: typed.Type, result: typed.Type, kind: @import("buffer_operations.zig").Kind, arguments: []const typed.Type, writable: bool) Error!void {
    if (item.kind != .dict and item.kind != .set) return error.ComponentProtocol;
    if (arguments.len != kind.arity() or (kind.mutates() and !writable)) return error.ComponentProtocol;
    const expected: typed.Type = switch (kind) {
        .length, .capacity => .u64,
        .contains => .bool,
        .key_at => item.key,
        .value_at, .read, .get, .pop_key, .pop_default, .setdefault => item.value,
        .pop => if (item.kind == .set) item.key else return error.ComponentProtocol,
        .copy => owner,
        .iteration_check, .write, .update, .clear => .unit,
        else => return error.ComponentProtocol,
    };
    if (result != expected) return error.ComponentProtocol;
    for (arguments, 0..) |argument, index| {
        const wanted: typed.Type = switch (kind) {
            .iteration_check, .key_at, .value_at => .i64,
            .read, .contains, .pop_key => item.key,
            .get, .write, .pop_default, .setdefault => if (index == 0) item.key else item.value,
            .update => owner,
            else => return error.ComponentProtocol,
        };
        if (argument != wanted) return error.ComponentProtocol;
    }
}
