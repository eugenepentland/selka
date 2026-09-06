//! Recursive generic type shapes retain parameters and resolved nominal identities.
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
/// An abstract type; arrays preserve their element expression without representative substitution.
pub const Value = union(enum) { concrete: typed.Type, parameter: usize, array: *const Array };
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
pub fn same(a: Value, b: Value, records: []const typed.Record) bool {
    if (array(a, records)) |left| {
        const right = array(b, records) orelse return false;
        return left.length == right.length and left.key == right.key and same(left.element, right.element, records);
    }
    return switch (a) {
        .concrete => |ty| b == .concrete and b.concrete == ty,
        .parameter => |index| b == .parameter and b.parameter == index,
        .array => false,
    };
}
/// Apply ordinary requirement rules recursively; arrays never acquire equality or arithmetic.
pub fn supports(value: Value, requirement: requirements.Requirement, parameters: []const requirements.Parameter, records: []const typed.Record) bool {
    return switch (value) {
        .parameter => |index| parameters[index].requirements.contains(requirement),
        .array => |shape| requirement == .copy and (shape.length == 0 or supports(shape.element, .copy, parameters, records)),
        .concrete => |ty| result: {
            var required: requirements.Set = .{};
            required.include(requirement);
            break :result required.accepts(ty, records);
        },
    };
}
