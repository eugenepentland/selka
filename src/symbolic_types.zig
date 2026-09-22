//! Recursive generic type shapes retain parameters and resolved nominal identities.
const std = @import("std");
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
const callables = @import("callables.zig");
const effect_set = @import("effect_set.zig");
/// An abstract type; arrays preserve their element expression without representative substitution.
pub const Value = union(enum) { callback: *const Callback, length: usize, length_parameter: usize, concrete: typed.Type, parameter: usize, array: *const Array, nominal: *Nominal };
/// A callback signature retains abstract argument types without storing context values.
pub const Callback = struct {
    parameters: []const Value,
    result: Value,
    effects: effect_set.Mask,
    mutates: []const u16 = &.{},
    return_origin: typed.ReturnOrigin = .unknown,
};
/// Symbolic applications keep declaration identity and ordered arguments, with lazy stored-member caches.
pub const Nominal = struct { declaration: usize, arguments: []const Value, schema: ?*Schema = null, properties: ?Properties = null };
/// A declared field or variant payload after substitution into the caller's parameter scope.
/// `default_value` is the backing node id of a declared field default; `fielded`
/// marks a variant case whose payload is a synthesized named-field record.
pub const Field = struct { name: []const u8, span: @import("source.zig").Span, ty: ?Value, default_value: ?usize = null, fielded: bool = false };
/// Shared view of concrete and parameterized record/variant members.
pub const Schema = struct { kind: @import("nominal_templates.zig").Kind, fields: []const Field, key: ?typed.Type = null };
/// Stored-value contracts are independent of nominal argument identity.
pub const Properties = struct { move_only: bool = false, requires_handling: bool = false, cleanup: effect_set.Mask = 0 };
/// Named result payload types before runtime specialization.
pub const ResultShape = struct { ok_type: Value, error_type: Value };
/// Named optional payload before runtime specialization.
pub const OptionShape = struct { element: Value };
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
        if (!std.mem.eql(u16, a.mutates, b.mutates) or !typed.ReturnOrigin.eql(a.return_origin, b.return_origin)) return false;
        if (a.parameters.len != b.parameters.len or !same(a.result, b.result, catalog)) return false;
        for (a.parameters, b.parameters) |x, y| if (!same(x, y, catalog)) return false;
        return true;
    }
    if (other != .concrete) return false;
    const b = @import("callables.zig").signature(other.concrete, catalog.records) orelse return false;
    if (a.effects != b.effects) return false;
    if (!std.mem.eql(u16, a.mutates, b.mutates) or !typed.ReturnOrigin.eql(a.return_origin, b.return_origin)) return false;
    if (a.parameters.len != b.parameters.len or !same(a.result, .{ .concrete = b.return_type }, catalog)) return false;
    for (a.parameters, b.parameters) |x, y| if (!same(x, .{ .concrete = y }, catalog)) return false;
    return true;
}
fn sameConcrete(value: Value, ty: typed.Type, catalog: Catalog) bool {
    const store = catalog.templates.store orelse return false;
    return sameIdentity(value, store.semantic(ty) orelse return false, catalog);
}
fn callbackParameterCount(value: Value, catalog: Catalog) ?usize {
    return switch (value) {
        .callback => |callback| callback.parameters.len,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            break :block signature.parameters.len;
        },
        else => null,
    };
}
fn callbackParameter(value: Value, index: usize, catalog: Catalog) ?Value {
    return switch (value) {
        .callback => |callback| if (index < callback.parameters.len) callback.parameters[index] else null,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            if (index >= signature.parameters.len) break :block null;
            break :block .{ .concrete = signature.parameters[index] };
        },
        else => null,
    };
}
fn callbackResult(value: Value, catalog: Catalog) ?Value {
    return switch (value) {
        .callback => |callback| callback.result,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            break :block .{ .concrete = signature.return_type };
        },
        else => null,
    };
}
fn callbackEffects(value: Value, catalog: Catalog) ?effect_set.Mask {
    return switch (value) {
        .callback => |callback| callback.effects,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            break :block signature.effects;
        },
        else => null,
    };
}
fn callbackMutates(value: Value, catalog: Catalog) ?[]const u16 {
    return switch (value) {
        .callback => |callback| callback.mutates,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            break :block signature.mutates;
        },
        else => null,
    };
}
fn callbackReturnOrigin(value: Value, catalog: Catalog) ?typed.ReturnOrigin {
    return switch (value) {
        .callback => |callback| callback.return_origin,
        .concrete => |ty| block: {
            const signature = callables.signature(ty, catalog.records) orelse break :block null;
            break :block signature.return_origin;
        },
        else => null,
    };
}
/// Directional callback assignability for symbolic values: parameters and result
/// stay exact, while the implementation effect ceiling must be a subset.
pub fn callbackAssignable(implementation: Value, destination: Value, catalog: Catalog) bool {
    const implementation_effects = callbackEffects(implementation, catalog) orelse return false;
    const destination_effects = callbackEffects(destination, catalog) orelse return false;
    if (implementation_effects & ~destination_effects != 0) return false;
    const implementation_mutates = callbackMutates(implementation, catalog) orelse return false;
    const destination_mutates = callbackMutates(destination, catalog) orelse return false;
    if (!callables.positionSubset(implementation_mutates, destination_mutates)) return false;
    const implementation_origin = callbackReturnOrigin(implementation, catalog) orelse return false;
    const destination_origin = callbackReturnOrigin(destination, catalog) orelse return false;
    if (!callables.originSubset(implementation_origin, destination_origin)) return false;
    const implementation_count = callbackParameterCount(implementation, catalog) orelse return false;
    const destination_count = callbackParameterCount(destination, catalog) orelse return false;
    if (implementation_count != destination_count) return false;
    const implementation_result = callbackResult(implementation, catalog) orelse return false;
    const destination_result = callbackResult(destination, catalog) orelse return false;
    if (!same(implementation_result, destination_result, catalog)) return false;
    for (0..implementation_count) |index| {
        const implementation_parameter = callbackParameter(implementation, index, catalog) orelse return false;
        const destination_parameter = callbackParameter(destination, index, catalog) orelse return false;
        if (!same(implementation_parameter, destination_parameter, catalog)) return false;
    }
    return true;
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
        if (!std.mem.eql(u16, callback.mutates, contract.mutates) or !typed.ReturnOrigin.eql(callback.return_origin, contract.return_origin)) return false;
        for (callback.parameters, node.key.arguments[0..callback.parameters.len]) |parameter, key| if (!sameIdentity(parameter, key, catalog)) return false;
        return sameIdentity(callback.result, node.key.arguments[callback.parameters.len], catalog);
    }
    if (value == .nominal) {
        // A tuple is a structural identity: its layout node carries the element
        // identities themselves rather than a named declaration.
        if (node.key.base == .tuple) {
            if (!store.index.isTuple(value.nominal.declaration)) return false;
            if (value.nominal.arguments.len != node.key.arguments.len) return false;
            for (value.nominal.arguments, node.key.arguments) |argument, key| if (!sameIdentity(argument, key, catalog)) return false;
            return true;
        }
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
        .nominal => |value_type| result: {
            const declaration = catalog.templates.store.?.index.declarations.items[value_type.declaration];
            // A tuple's requirements are its elements': its declaration owns no
            // fields, so a blanket declaration-level guarantee would be unsound.
            if (declaration.kind != .tuple) break :result declaration.guarantees.contains(requirement);
            for (value_type.arguments) |argument| if (!supports(argument, requirement, parameters, catalog)) break :result false;
            break :result true;
        },
        .concrete => |ty| result: {
            var required: requirements.Set = .{};
            required.include(requirement);
            break :result required.accepts(ty, catalog.records);
        },
    };
}
