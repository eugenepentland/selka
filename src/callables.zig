//! Immediate noncapturing function values have exact signatures and checked effect ceilings.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const effect_set = @import("effect_set.zig");
/// Look up a callable signature without accepting its scalar implementation representation.
pub fn signature(ty: typed.Type, records: []const typed.Record) ?typed.Callable {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return records[ty.recordIndex()].contract.callback;
}
/// Whether every position in `subset` is present in `superset`.
pub fn positionSubset(subset: []const u16, superset: []const u16) bool {
    for (subset) |position| {
        var found = false;
        for (superset) |candidate| if (candidate == position) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}
/// Whether `implementation` is a sound subset of `destination`.
pub fn originSubset(implementation: typed.ReturnOrigin, destination: typed.ReturnOrigin) bool {
    return switch (destination) {
        .unknown => true,
        .fresh => implementation == .fresh,
        .params => |destination_params| switch (implementation) {
            .fresh => true,
            .params => |implementation_params| positionSubset(implementation_params, destination_params),
            .unknown => false,
        },
    };
}
/// Exact parameter and result identity; ceilings must agree at value boundaries.
/// This remains the identity relation used when interning or comparing schema records.
pub fn equal(a: typed.Callable, b: typed.Callable) bool {
    return a.return_type == b.return_type and a.effects == b.effects and
        std.mem.eql(typed.Type, a.parameters, b.parameters) and
        std.mem.eql(u16, a.mutates, b.mutates) and typed.ReturnOrigin.eql(a.return_origin, b.return_origin);
}
/// Parameter and result identity is invariant for directional assignability.
fn sameShape(implementation: typed.Callable, destination: typed.Callable) bool {
    if (implementation.return_type != destination.return_type) return false;
    return std.mem.eql(typed.Type, implementation.parameters, destination.parameters);
}
/// Whether an implementation may be used where `destination` is expected.
///
/// Effects may shrink, the implementation mutation footprint must be a subset
/// of the destination footprint, and the return-origin bound must be no wider
/// than the destination's. Parameter and result identity stays invariant.
pub fn assignable(implementation: typed.Callable, destination: typed.Callable) bool {
    if (!sameShape(implementation, destination)) return false;
    if (implementation.effects & ~destination.effects != 0) return false;
    if (!positionSubset(implementation.mutates, destination.mutates)) return false;
    if (!originSubset(implementation.return_origin, destination.return_origin)) return false;
    return true;
}
/// Validate a runtime target against the callable's parameter, ownership and effect contract.
pub fn accepts(destination: typed.Callable, function: anytype) bool {
    if (function.signature.parameter_count > 16 or function.signature.parameter_count != destination.parameters.len) return false;
    var parameters: [16]typed.Type = undefined;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |parameter, index| parameters[index] = parameter.ty;
    const ceiling = function.policy.effect_bound orelse return false;
    const implementation: typed.Callable = .{
        .parameters = parameters[0..function.signature.parameter_count],
        .return_type = function.signature.return_type,
        .effects = ceiling.allowed,
        .mutates = function.signature.declared_mutates,
        .return_origin = function.signature.return_origin,
    };
    return assignable(implementation, destination);
}
// twin-drift-ok: this renders the parenthesized `effects(...)` spelling for callable types; effect_set.write renders the brace-set form used by interface output.
/// Write the named effect list used inside a canonical callable type.
pub fn writeEffects(writer: *std.Io.Writer, mask: effect_set.Mask) std.Io.Writer.Error!void {
    var separator = false;
    inline for (std.meta.tags(effect_set.Effect)) |effect| {
        if (mask & effect_set.bit(effect) != 0) {
            if (separator) try writer.writeAll(", ");
            try writer.writeAll(@tagName(effect));
            separator = true;
        }
    }
}
/// Write the canonical `mutates(...)` suffix for a normalized input-position set.
/// An empty set is omitted because omission is the canonical spelling of it.
pub fn writeMutates(writer: *std.Io.Writer, mutates: []const u16) std.Io.Writer.Error!void {
    if (mutates.len == 0) return;
    try writer.writeAll(" mutates(");
    for (mutates, 0..) |position, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("p{d}", .{position});
    }
    try writer.writeByte(')');
}
/// Intern a callable schema with immediate scalar storage and no captured state.
pub fn intern(allocator: std.mem.Allocator, catalog: *@import("type_catalog.zig").Catalog, contract: typed.Callable, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!typed.Type {
    if (contract.parameters.len > 16) return sink.fail("E_CALLBACK_TYPE", span, "callback signatures support at most 16 value parameters");
    var count: usize = 0;
    for (catalog.records) |record| if (record.contract.callback) |existing| {
        if (equal(existing, contract)) return record.id;
        count += 1;
    };
    if (count == 4096) return sink.fail(diagnostic.generic_limit, span, "callback specialization exceeds 4096 distinct signatures");
    const parameters = try allocator.dupe(typed.Type, contract.parameters);
    var name: std.Io.Writer.Allocating = .init(allocator);
    defer name.deinit();
    name.writer.writeAll("def(") catch return error.OutOfMemory;
    for (parameters, 0..) |parameter, i| {
        if (i != 0) name.writer.writeAll(", ") catch return error.OutOfMemory;
        name.writer.writeAll(typed.typeName(parameter, catalog.records)) catch return error.OutOfMemory;
    }
    name.writer.writeAll(") -> ") catch return error.OutOfMemory;
    name.writer.writeAll(typed.typeName(contract.return_type, catalog.records)) catch return error.OutOfMemory;
    name.writer.writeAll(" effects(") catch return error.OutOfMemory;
    writeEffects(&name.writer, contract.effects) catch return error.OutOfMemory;
    name.writer.writeByte(')') catch return error.OutOfMemory;
    writeMutates(&name.writer, contract.mutates) catch return error.OutOfMemory;
    const id: typed.Type = @fromBackingInt(typed.Type.record_base + catalog.records.len);
    var storage: std.ArrayList(typed.Record) = .{ .items = catalog.records, .capacity = catalog.record_capacity };
    defer {
        catalog.records = storage.items;
        catalog.record_capacity = storage.capacity;
    }
    try storage.append(allocator, .{
        .id = id,
        .name = try name.toOwnedSlice(),
        .declaration = span,
        .fields = &.{},
        .shape = .{ .domain = .u64 },
        .contract = .{ .callback = .{ .parameters = parameters, .return_type = contract.return_type, .effects = contract.effects, .mutates = contract.mutates, .return_origin = contract.return_origin } },
    });
    return id;
}
