//! Recursive generic type shapes retain parameters and resolved nominal identities.
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
/// An abstract type; arrays preserve their element expression without representative substitution.
pub const Value = union(enum) { concrete: typed.Type, parameter: usize, array: *const Array, nominal: *Nominal };
/// Symbolic applications keep declaration identity and ordered arguments, with lazy stored-member caches.
pub const Nominal = struct { declaration: usize, arguments: []const Value, schema: ?*Schema = null, properties: ?Properties = null };
/// A declared field or variant payload after substitution into the caller's parameter scope.
pub const Field = struct { name: []const u8, span: @import("source.zig").Span, ty: ?Value };
/// Shared view of concrete and parameterized record/variant members.
pub const Schema = struct { kind: @import("nominal_templates.zig").Kind, fields: []const Field, key: ?typed.Type = null };
/// Stored-value contracts are independent of nominal argument identity.
pub const Properties = struct { move_only: bool = false, requires_handling: bool = false, region: bool = false, cleanup: @import("effect_set.zig").Mask = 0 };
const Catalog = @import("type_catalog.zig").Catalog;
/// Structural fixed-array shape with a concrete length and optional enum key.
pub const Array = struct { element: Value, length: usize, key: ?typed.Type = null };
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
        return left.length == right.length and left.key == right.key and same(left.element, right.element, catalog);
    }
    if (a == .nominal and b == .concrete) return sameConcrete(a, b.concrete, catalog);
    if (a == .concrete and b == .nominal) return sameConcrete(b, a.concrete, catalog);
    return switch (a) {
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
fn sameConcrete(value: Value, ty: typed.Type, catalog: Catalog) bool {
    const store = catalog.templates.store orelse return false;
    return sameIdentity(value, store.semantic(ty) orelse return false, catalog);
}
fn sameIdentity(value: Value, id: @import("nominal_layouts.zig").Id, catalog: Catalog) bool {
    const store = catalog.templates.store.?;
    if (value == .concrete) return store.runtime(id) == value.concrete;
    const node = store.graph.nodes.items[@backingInt(id)];
    if (value == .nominal) {
        if (node.key.base != .named or value.nominal.declaration != node.key.base.named or value.nominal.arguments.len != node.key.arguments.len) return false;
        for (value.nominal.arguments, node.key.arguments) |argument, key| if (!sameIdentity(argument, key, catalog)) return false;
        return true;
    }
    if (value == .array and node.key.base == .array) {
        const key = if (node.key.base.array.key) |key_id| store.runtime(key_id) else null;
        return value.array.length == node.key.base.array.length and value.array.key == key and sameIdentity(value.array.element, node.key.arguments[0], catalog);
    }
    return false;
}
/// Apply ordinary requirement rules recursively; arrays never acquire equality or arithmetic.
pub fn supports(value: Value, requirement: requirements.Requirement, parameters: []const requirements.Parameter, catalog: Catalog) bool {
    return switch (value) {
        .parameter => |index| parameters[index].requirements.contains(requirement),
        .array => |shape| requirement == .copy and (shape.length == 0 or supports(shape.element, .copy, parameters, catalog)),
        .nominal => |value_type| catalog.templates.store.?.index.declarations.items[value_type.declaration].guarantees.contains(requirement),
        .concrete => |ty| result: {
            var required: requirements.Set = .{};
            required.include(requirement);
            break :result required.accepts(ty, catalog.records);
        },
    };
}
