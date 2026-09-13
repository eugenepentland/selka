//! Recursive generic type shapes retain parameters and resolved nominal identities.
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
/// An abstract type; arrays preserve their element expression without representative substitution.
pub const Value = union(enum) { callback: *const Callback, length: usize, length_parameter: usize, concrete: typed.Type, parameter: usize, array: *const Array, nominal: *Nominal };
/// A callback signature retains abstract argument types without storing context values.
pub const Callback = struct { parameters: []const Value, result: Value, effects: @import("effect_set.zig").Mask };
/// Symbolic applications keep declaration identity and ordered arguments, with lazy stored-member caches.
pub const Nominal = struct { declaration: usize, arguments: []const Value, schema: ?*Schema = null, properties: ?Properties = null };
/// A declared field or variant payload after substitution into the caller's parameter scope.
pub const Field = struct { name: []const u8, span: @import("source.zig").Span, ty: ?Value };
/// Shared view of concrete and parameterized record/variant members.
pub const Schema = struct { kind: @import("nominal_templates.zig").Kind, fields: []const Field, key: ?typed.Type = null };
/// Stored-value contracts are independent of nominal argument identity.
pub const Properties = struct { move_only: bool = false, requires_handling: bool = false, cleanup: @import("effect_set.zig").Mask = 0 };
/// Named result payload types before runtime specialization.
pub const ResultShape = struct { ok_type: Value, error_type: Value };
const Catalog = @import("type_catalog.zig").Catalog;
/// Structural fixed-array shape with a concrete length and optional enum key.
pub const Array = struct { element: Value, length: usize, length_parameter: ?usize = null, key: ?typed.Type = null };
/// View concrete and symbolic arrays through the same shape contract.
pub fn array(value: Value, records: []const typed.Record) ?Array {
    if (value == .array) return value.array.*;
    if (value != .concrete or !value.concrete.isAggregate()) return null;
    const shape = records[value.concrete.recordIndex()].shape.array orelse return null;
    return .{ .element = .{ .concrete = shape.element }, .length = shape.length, .key = shape.key };
}
/// Compare shapes structurally, preserving distinct leaves and enum-key identities.
pub fn same(a: Value, b: Value, catalog: Catalog) bool {
    if (array(a, catalog.records)) |left| {
        const right = array(b, catalog.records) orelse return false;
        return left.length == right.length and left.length_parameter == right.length_parameter and left.key == right.key and same(left.element, right.element, catalog);
    }
    if (a == .callback) return sameCallback(a.callback.*, b, catalog);
    if (b == .callback) return sameCallback(b.callback.*, a, catalog);
    if (a == .nominal and b == .concrete) return sameConcrete(a, b.concrete, catalog);
    if (a == .concrete and b == .nominal) return sameConcrete(b, a.concrete, catalog);
    return switch (a) {
        .callback => unreachable,
        .length => |value| b == .length and b.length == value,
        .length_parameter => |value| b == .length_parameter and b.length_parameter == value,
        .concrete => |ty| b == .concrete and b.concrete == ty,
        .parameter => |index| b == .parameter and b.parameter == index,
        .array => false,
        .nominal => |left| result: {
            if (b != .nominal or left.declaration != b.nominal.declaration or left.arguments.len != b.nominal.arguments.len) break :result false;
            for (left.arguments, b.nominal.arguments) |x, y| if (!same(x, y, catalog)) break :result false;
            break :result true;
        },
    };
}
fn sameCallback(a: Callback, other: Value, catalog: Catalog) bool {
    if (other == .callback) {
        const b = other.callback;
        if (a.effects != b.effects) return false;
        if (a.parameters.len != b.parameters.len or !same(a.result, b.result, catalog)) return false;
        for (a.parameters, b.parameters) |x, y| if (!same(x, y, catalog)) return false;
        return true;
    }
    if (other != .concrete) return false;
    const b = @import("callables.zig").signature(other.concrete, catalog.records) orelse return false;
    if (a.effects != b.effects) return false;
    if (a.parameters.len != b.parameters.len or !same(a.result, .{ .concrete = b.return_type }, catalog)) return false;
    for (a.parameters, b.parameters) |x, y| if (!same(x, .{ .concrete = y }, catalog)) return false;
    return true;
}
fn sameConcrete(value: Value, ty: typed.Type, catalog: Catalog) bool {
    const store = catalog.templates.store orelse return false;
    return sameIdentity(value, store.semantic(ty) orelse return false, catalog);
}
fn sameIdentity(value: Value, id: @import("nominal_layouts.zig").Id, catalog: Catalog) bool {
    const store = catalog.templates.store.?;
    if (value == .concrete) return store.runtime(id) == value.concrete;
    if (value == .length) return store.graph.nodes.items[@backingInt(id)].key.base == .length and store.graph.nodes.items[@backingInt(id)].key.base.length == value.length;
    const node = store.graph.nodes.items[@backingInt(id)];
    if (value == .callback) {
        const callback = value.callback;
        if (node.key.base != .callback or node.key.arguments.len != callback.parameters.len + 1) return false;
        const contract = node.key.base.callback;
        if (callback.effects != contract.effects) return false;
        for (callback.parameters, node.key.arguments[0..callback.parameters.len]) |parameter, key| if (!sameIdentity(parameter, key, catalog)) return false;
        return sameIdentity(callback.result, node.key.arguments[callback.parameters.len], catalog);
    }
    if (value == .nominal) {
        if (node.key.base != .named or value.nominal.declaration != node.key.base.named or value.nominal.arguments.len != node.key.arguments.len) return false;
        for (value.nominal.arguments, node.key.arguments) |argument, key| if (!sameIdentity(argument, key, catalog)) return false;
        return true;
    }
    if (value == .array and node.key.base == .array) {
        if (value.array.length_parameter != null) return false;
        const key = if (node.key.base.array.key) |key_id| store.runtime(key_id) else null;
        return value.array.length == node.key.base.array.length and value.array.key == key and sameIdentity(value.array.element, node.key.arguments[0], catalog);
    }
    return false;
}
/// Apply ordinary requirement rules recursively; arrays never acquire equality or arithmetic.
pub fn supports(value: Value, requirement: requirements.Requirement, parameters: []const requirements.Parameter, catalog: Catalog) bool {
    return switch (value) {
        .callback => requirement == .copy or requirement == .storable,
        .length, .length_parameter => false,
        .parameter => |index| parameters[index].requirements.contains(requirement),
        .array => |shape| (requirement == .copy or requirement == .storable) and ((shape.length_parameter == null and shape.length == 0) or supports(shape.element, requirement, parameters, catalog)),
        .nominal => |value_type| catalog.templates.store.?.index.declarations.items[value_type.declaration].guarantees.contains(requirement),
        .concrete => |ty| result: {
            var required: requirements.Set = .{};
            required.include(requirement);
            break :result required.accepts(ty, catalog.records);
        },
    };
}
