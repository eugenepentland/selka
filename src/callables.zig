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
/// Exact parameter and result identity; ceilings must agree at value boundaries.
/// This remains the identity relation used when interning or comparing schema records.
pub fn equal(a: typed.Callable, b: typed.Callable) bool {
    return a.return_type == b.return_type and a.effects == b.effects and std.mem.eql(typed.Type, a.parameters, b.parameters);
}
/// Parameter and result identity is invariant for directional assignability.
fn sameShape(implementation: typed.Callable, destination: typed.Callable) bool {
    if (implementation.return_type != destination.return_type) return false;
    return std.mem.eql(typed.Type, implementation.parameters, destination.parameters);
}
/// Whether an implementation may be used where `destination` is expected.
///
/// The first directional clause is the effect ceiling: an implementation may
/// promise fewer effects than the destination contract, but never more.
/// M1/M2 add mutation-footprint and return-origin subset clauses here; parameter
/// and result identity stays invariant.
pub fn assignable(implementation: typed.Callable, destination: typed.Callable) bool {
    if (!sameShape(implementation, destination)) return false;
    if (implementation.effects & ~destination.effects != 0) return false;
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
        .contract = .{ .callback = .{ .parameters = parameters, .return_type = contract.return_type, .effects = contract.effects } },
    });
    return id;
}
