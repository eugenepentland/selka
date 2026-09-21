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
            // A copied managed list is a value only on the codec boundary, which
            // is the one that carries a guest context to allocate into.
            if (codecs) {
                if (listScalar(catalog.records[ty.recordIndex()])) |element| {
                    try types.append(allocator, try listType(allocator, catalog, ty, element));
                    continue;
                }
            }
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

/// The scalar a managed text is built from, or null when the record is not one.
/// `str` is a managed buffer whose element is a 32-bit Unicode scalar; a managed
/// byte buffer is `bytes`, whose own encoding the plan stages separately, so it
/// is deliberately not text here.
pub fn listScalar(record: typed.Record) ?typed.Type {
    // A copied managed list is an opaque buffer of one scalar, which is the same
    // shape for `str`, `list[i64]` and a user's `list[u32]`. What separates them
    // is not the element but which declaration it is: `str` is the one that
    // reads as a string, and the parent decides that by this same name. `bytes`
    // is excluded because the plan stages its encoding separately rather than
    // inheriting the list form by accident.
    if (std.mem.eql(u8, record.name, "bytes")) return null;
    const element = record.shape.buffer orelse return null;
    return if (element.isInteger() or element == .bool) element else null;
}

/// One copied managed list in the native wire table: a handle-sized value whose
/// single field names the scalar its children carry.
fn listType(allocator: std.mem.Allocator, catalog: *native.Catalog, ty: typed.Type, element: typed.Type) Error!Type {
    const layout = try catalog.layout(ty);
    const fields = try allocator.alloc(Field, 1);
    fields[0] = .{ .type = typed.typeName(element, catalog.records), .offset = 0 };
    return .{
        .name = typed.typeName(ty, catalog.records),
        .kind = "list",
        .size = layout.size,
        .alignment = layout.alignment,
        .fields = fields,
    };
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

const wire_test_span = @import("source.zig").Span{ .start = 0, .end = 0 };
fn wireTestRecordType(index: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + index);
}

// spec: NATIVE-WIRE-VALUE-1
test "the native wire table carries a flagged value record and refuses an unsupported one" {
    const plain = [_]typed.Field{
        .{ .name = "left", .declaration = wire_test_span, .ty = .i64 },
        .{ .name = "right", .declaration = wire_test_span, .ty = .i64 },
    };
    const refused = [_]typed.Field{
        .{ .name = "clock", .declaration = wire_test_span, .ty = .clock_cap },
        .{ .name = "weight", .declaration = wire_test_span, .ty = .i64 },
    };
    const records = [_]typed.Record{
        .{ .id = wireTestRecordType(0), .name = "Pair", .declaration = wire_test_span, .fields = &plain },
        .{ .id = wireTestRecordType(1), .name = "Stamped", .declaration = wire_test_span, .fields = &refused },
    };
    var catalog = try native.Catalog.init(std.testing.allocator, &records, &.{ "app::Pair", "app::Stamped" });
    defer catalog.deinit();
    const types = try describeWithDomains(std.testing.allocator, &catalog, true);
    defer {
        for (types) |item| if (item.fields.len != 0) std.testing.allocator.free(item.fields);
        std.testing.allocator.free(types);
    }
    var saw_plain = false;
    for (types) |item| {
        if (std.mem.eql(u8, item.name, "Pair")) {
            saw_plain = true;
            try std.testing.expectEqualStrings("record", item.kind);
            try std.testing.expectEqual(@as(usize, 2), item.fields.len);
        }
        try std.testing.expect(!std.mem.eql(u8, item.name, "Stamped"));
    }
    try std.testing.expect(saw_plain);
}

// spec: NATIVE-WIRE-VALUE-2
test "a managed record is refused by the value table however copied its fields are" {
    // A `class` in mylang is a managed heap object, so `native_wire.supported`
    // flags it — it has no buffer or resource identity and its fields are all
    // scalars — while `native_types` can only lay it out as an opaque handle.
    // The value table must therefore omit it: the predicate is necessary, not
    // sufficient, and the table is where the two views have to agree.
    const fields = [_]typed.Field{
        .{ .name = "x", .declaration = wire_test_span, .ty = .i64 },
        .{ .name = "y", .declaration = wire_test_span, .ty = .i64 },
    };
    const records = [_]typed.Record{
        .{ .id = wireTestRecordType(0), .name = "Pair", .declaration = wire_test_span, .fields = &fields },
        .{ .id = wireTestRecordType(1), .name = "Point", .declaration = wire_test_span, .fields = &fields, .managed = true },
    };
    const flags = try @import("native_wire.zig").supported(std.testing.allocator, &records, true);
    defer std.testing.allocator.free(flags);
    try std.testing.expect(flags[0]);
    try std.testing.expect(flags[1]);
    var catalog = try native.Catalog.init(std.testing.allocator, &records, &.{ "app::Pair", "app::Point" });
    defer catalog.deinit();
    const handle = try catalog.layout(wireTestRecordType(1));
    try std.testing.expectEqual(native.Kind.managed, handle.kind);
    try std.testing.expect(handle.trace);
    const value = try catalog.layout(wireTestRecordType(0));
    try std.testing.expectEqual(native.Kind.record, value.kind);
    const types = try describeWithDomains(std.testing.allocator, &catalog, true);
    defer {
        for (types) |item| if (item.fields.len != 0) std.testing.allocator.free(item.fields);
        std.testing.allocator.free(types);
    }
    for (types) |item| try std.testing.expect(!std.mem.eql(u8, item.name, "Point"));
}

// spec: NATIVE-WIRE-LIST-1
test "a copied managed list is carried whatever its element width and bytes is not" {
    // `str`, `list[i64]` and `list[u32]` are the same shape — an opaque buffer of
    // one scalar — so the table carries them all, and the parent decides which
    // one reads as a string. `bytes` is the same shape again and is excluded,
    // because the plan gives it its own encoding rather than inheriting this one,
    // and a boundary that advertised it would fail after promising a call.
    const text: typed.Record = .{ .id = wireTestRecordType(0), .name = "str", .declaration = wire_test_span, .fields = &.{}, .shape = .{ .buffer = .u32 } };
    const wide: typed.Record = .{ .id = wireTestRecordType(1), .name = "List<i64>", .declaration = wire_test_span, .fields = &.{}, .shape = .{ .buffer = .i64 } };
    const octets: typed.Record = .{ .id = wireTestRecordType(2), .name = "bytes", .declaration = wire_test_span, .fields = &.{}, .shape = .{ .buffer = .u8 } };
    try std.testing.expect(listScalar(text) != null);
    try std.testing.expect(listScalar(wide) != null);
    try std.testing.expect(listScalar(octets) == null);
}
