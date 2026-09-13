//! Immediate noncapturing function values have exact signatures and checked effect ceilings.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Look up a callable signature without accepting its scalar implementation representation.
pub fn signature(ty: typed.Type, records: []const typed.Record) ?typed.Callable {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return records[ty.recordIndex()].contract.callback;
}
/// Exact parameter and result identity; ceilings must agree at value boundaries.
pub fn equal(a: typed.Callable, b: typed.Callable) bool {
    return a.return_type == b.return_type and a.effects == b.effects and std.mem.eql(typed.Type, a.parameters, b.parameters);
}
/// Validate a runtime target against the callable's parameter, ownership and effect contract.
pub fn accepts(contract: typed.Callable, function: anytype) bool {
    if (function.signature.return_type != contract.return_type) return false;
    if (function.signature.parameter_count != contract.parameters.len) return false;
    for (function.scope.locals[0..function.signature.parameter_count], contract.parameters) |parameter, ty| {
        if (parameter.ty != ty) return false;
    }
    const ceiling = function.policy.effect_bound orelse return false;
    return ceiling.allowed == contract.effects;
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
    name.writer.writeAll("fn(") catch return error.OutOfMemory;
    for (parameters, 0..) |parameter, i| {
        if (i != 0) name.writer.writeByte(',') catch return error.OutOfMemory;
        name.writer.writeAll(typed.typeName(parameter, catalog.records)) catch return error.OutOfMemory;
    }
    name.writer.print(")->{s} effects({d})", .{ typed.typeName(contract.return_type, catalog.records), contract.effects }) catch return error.OutOfMemory;
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
