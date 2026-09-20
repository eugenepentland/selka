//! Ordinary value ABI metadata with canonical names and native byte offsets.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
pub const Error = native.Error;
/// One native field offset and its canonical semantic type name.
pub const Field = struct { type: ?[]const u8, offset: u64 };
/// Aggregate shape: element count, element stride and the field table. A scalar
/// and a capability carry the empty shape.
pub const Aggregate = struct { count: u64 = 0, stride: u64 = 0, fields: []const Field = &.{} };
/// Native byte layout, finite copied-tree shape and the emitter's
/// argument-crossing decision for one value type.
pub const Type = struct {
    name: []const u8,
    kind: []const u8,
    size: u64,
    alignment: u8,
    aggregate: Aggregate = .{},
    by_address: bool = false,

    /// Emit the flat `wire_types` schema: the aggregate shape keeps its former
    /// keys, in their former order, and `by_address` is appended last.
    pub fn jsonStringify(self: Type, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .kind = self.kind,
            .size = self.size,
            .alignment = self.alignment,
            .count = self.aggregate.count,
            .stride = self.aggregate.stride,
            .fields = self.aggregate.fields,
            .by_address = self.by_address,
        });
    }
};

/// Whether the native value is represented in one scalar register. A capability,
/// an open file, a managed reference and a callable code word all are.
pub fn scalar(ty: typed.Type, records: []const typed.Record) bool {
    // An open file and a capability are both one opaque native word.
    const authority = ty.capabilityIndex() != null or ty.isFile();
    if (ty.isInteger() or ty == .bool or ty == .unit or authority) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.contract.callback != null or ownedPointer(record)) return true;
    return if (record.shape.domain) |backing| scalar(backing, records) else false;
}

/// Whether a record is one owned pointer word: a byte buffer or a resource.
pub fn ownedPointer(record: typed.Record) bool {
    return record.shape.buffer != null or record.shape.resource != null;
}

/// QBE-AGGREF-1's one crossing rule: one argument of this type crosses a call
/// boundary as the address of the caller's storage instead of a value, while a
/// move-only aggregate keeps the by-value boundary and its single owner. The
/// emitter's `argumentType` and this module's manifest both read this answer,
/// so the generated copied-value adapter can never spell the rule a second time.
pub fn byAddress(layout: native.Layout, ty: typed.Type, records: []const typed.Record) bool {
    if (layout.copy == .prohibited) return false;
    return !scalar(ty, records);
}

/// Describe finite ordinary values; runtime identities and domains stay opaque.
pub fn describe(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]const Type {
    return describeWithDomains(allocator, catalog, false);
}

/// Include codec-owned domain backing nodes only for the normative JSON boundary.
pub fn describeWithDomains(allocator: std.mem.Allocator, catalog: *native.Catalog, codecs: bool) Error![]const Type {
    const flags = try @import("native_wire.zig").supported(allocator, catalog.records, codecs);
    defer allocator.free(flags);
    var types: std.ArrayList(Type) = .empty;
    errdefer types.deinit(allocator);
    for (0..typed.Type.record_base + catalog.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(index);
        const ordinary = ty.isInteger() or ty == .bool;
        const injected_stream = codecs and ty == .stream_cap;
        if (ty.isAggregate()) {
            if (!flags[ty.recordIndex()]) continue;
        } else if (!ordinary and !injected_stream) continue;
        const layout = try catalog.layout(ty);
        if (layout.trace or layout.drop) continue;
        var item: Type = .{
            .name = typed.typeName(ty, catalog.records),
            .kind = "scalar",
            .size = layout.size,
            .alignment = layout.alignment,
            .by_address = byAddress(layout, ty, catalog.records),
        };
        if (ty.isAggregate()) {
            const record = catalog.records[ty.recordIndex()];
            if (record.shape.variants) |variants| {
                const fields = try allocator.alloc(Field, variants.cases.len);
                for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| typed.typeName(payload, catalog.records) else null, .offset = layout.payload_offset };
                item.kind = "variant";
                item.aggregate.fields = fields;
            } else {
                const fields = try allocator.alloc(Field, layout.fields.len);
                for (layout.fields, fields) |source, *field| field.* = .{ .type = typed.typeName(source.ty, catalog.records), .offset = source.offset };
                item.aggregate.fields = fields;
                item.kind = if (record.shape.domain != null) "domain" else if (record.shape.array != null) "array" else "record";
                item.aggregate.count = layout.count;
                item.aggregate.stride = layout.stride;
            }
        }
        try types.append(allocator, item);
    }
    return types.toOwnedSlice(allocator);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var catalog = try native.Catalog.initRecords(arena.allocator(), &.{});
    defer catalog.deinit();
    const types = try describeWithDomains(arena.allocator(), &catalog, true);
    try std.testing.expect(types.len > 0);
}
test "describeWithDomains releases temporary metadata on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
