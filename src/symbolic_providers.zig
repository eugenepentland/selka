//! Provider payload contracts over concrete or symbolic nominal records.
const std = @import("std");
const typed = @import("typed.zig");
const symbolic = @import("symbolic_types.zig");
const contracts = @import("provider_contracts.zig");
const Context = @import("symbolic_shapes.zig").Context;
const Span = @import("source.zig").Span;
const Error = @import("diagnostic.zig").Error;
const Value = symbolic.Value;
/// A numeric array whose element is known to be exactly u8 for every valid substitution.
pub fn bytes(value: Value, records: []const typed.Record) bool {
    const shape = symbolic.array(value, records) orelse return false;
    return shape.key == null and shape.element == .concrete and shape.element.concrete == .u8;
}
/// Resource declarations are nominal concrete leaves, even inside a symbolic result wrapper.
pub fn resource(value: Value, records: []const typed.Record) ?@import("external_resources.zig").Kind {
    return if (value == .concrete) typed.resourceKind(value.concrete, records) else null;
}
fn matches(context: Context, value: Value, requirement: contracts.Requirement) bool {
    return switch (requirement) {
        .i64 => symbolic.same(value, .{ .concrete = .i64 }, context.catalog),
        .u64 => symbolic.same(value, .{ .concrete = .u64 }, context.catalog),
        .boolean => symbolic.same(value, .{ .concrete = .bool }, context.catalog),
        .bytes => bytes(value, context.catalog.records),
        .resource => resource(value, context.catalog.records) != null,
    };
}
/// Match complete named fields and return their types in the shared contract's slot order.
pub fn payload(context: Context, value: Value, operation: contracts.Operation, span: Span) Error!?[3]?Value {
    const result = (try context.matchResult(value, span)) orelse return null;
    const completion = operation == .completion;
    if (!matches(context, if (completion) result.ok_type else result.error_type, if (completion) .boolean else .i64)) return null;
    const record = if (completion) result.error_type else result.ok_type;
    if (context.kind(record) != .record) return null;
    const shape = try context.schema(record, span);
    const required = contracts.fields(operation);
    if (shape.fields.len != required.len) return null;
    var found: [3]?Value = @splat(null);
    for (required, 0..) |rule, slot| {
        for (shape.fields) |field| {
            if (!std.mem.eql(u8, field.name, rule.name)) continue;
            const field_type = field.ty orelse return null;
            if (!matches(context, field_type, rule.requirement)) return null;
            found[slot] = field_type;
        }
        if (found[slot] == null) return null;
    }
    return found;
}
