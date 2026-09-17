//! Ordinary value ABI metadata with canonical names and native byte offsets.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
pub const Error = native.Error;
/// One native field offset and its canonical semantic type name.
pub const Field = struct { type: ?[]const u8, offset: u64 };
/// Native byte layout and finite copied-tree shape for one value type.
pub const Type = struct { name: []const u8, kind: []const u8, size: u64, alignment: u8, count: u64 = 0, stride: u64 = 0, fields: []const Field = &.{} };

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
        var item: Type = .{ .name = typed.typeName(ty, catalog.records), .kind = "scalar", .size = layout.size, .alignment = layout.alignment };
        if (ty.isAggregate()) {
            const record = catalog.records[ty.recordIndex()];
            if (record.shape.variants) |variants| {
                const fields = try allocator.alloc(Field, variants.cases.len);
                for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| typed.typeName(payload, catalog.records) else null, .offset = layout.payload_offset };
                item.kind = "variant";
                item.fields = fields;
            } else {
                const fields = try allocator.alloc(Field, layout.fields.len);
                for (layout.fields, fields) |source, *field| field.* = .{ .type = typed.typeName(source.ty, catalog.records), .offset = source.offset };
                item.fields = fields;
                item.kind = if (record.shape.domain != null) "domain" else if (record.shape.array != null) "array" else "record";
                item.count = layout.count;
                item.stride = layout.stride;
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
