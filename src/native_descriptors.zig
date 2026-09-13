//! Stable external C descriptors consumed by the precise native collector.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
pub const Error = native.Error;
const Item = struct { ty: typed.Type, name: []const u8 };
/// Reference descriptor symbols identify semantic types independently of catalog order.
pub fn symbol(allocator: std.mem.Allocator, catalog: *const native.Catalog, ty: typed.Type) Error![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(try catalog.identity(ty), &digest, .{});
    return std.fmt.allocPrint(allocator, "myl_t_{s}", .{std.fmt.bytesToHex(digest, .lower)});
}
fn lessThan(_: void, a: Item, b: Item) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
/// Emit deterministic definitions for values and managed-record bodies. Generated
/// C owns no mutable state and depends only on the versioned native_heap.h ABI.
pub fn generate(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = try a.alloc(Item, typed.Type.record_base + catalog.records.len);
    for (items, 0..) |*item, index| {
        const ty: typed.Type = @fromBackingInt(index);
        item.* = .{ .ty = ty, .name = try symbol(a, catalog, ty) };
    }
    std.mem.sort(Item, items, {}, lessThan);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    writer.writeAll("#include \"native_heap.h\"\n") catch return error.OutOfMemory;
    for (items) |item| writer.print("extern const myl_native_type {s};\n", .{item.name}) catch return error.OutOfMemory;
    for (items) |item| {
        try emit(a, writer, catalog, item.name, try catalog.layout(item.ty), item.ty);
        if (item.ty.isAggregate() and catalog.records[item.ty.recordIndex()].managed) {
            // Collections use their runtime header and typed element descriptors.
            // Nominal managed records can allocate this inline body directly.
            const record = catalog.records[item.ty.recordIndex()];
            if (record.shape.array == null and !record.shape.hasRuntimeIdentity()) {
                const body = try catalog.heapLayout(item.ty);
                defer catalog.releaseLayout(body);
                try emit(a, writer, catalog, try std.fmt.allocPrint(a, "{s}_body", .{item.name}), body, item.ty);
            }
        }
    }
    return output.toOwnedSlice();
}
fn emit(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, name: []const u8, layout: native.Layout, ty: typed.Type) Error!void {
    if (layout.fields.len != 0) {
        writer.print("static const myl_native_field {s}_fields[] = {{\n", .{name}) catch return error.OutOfMemory;
        for (layout.fields) |field| {
            const child = try symbol(a, catalog, field.ty);
            writer.print(" {{.offset={d},.type=&{s},.tag={d}}},\n", .{ field.offset, child, field.tag orelse 0 }) catch return error.OutOfMemory;
        }
        writer.writeAll("};\n") catch return error.OutOfMemory;
    }
    const kind: []const u8 = if (@import("numeric_surface.zig").isFloat(ty, catalog.records)) "MYL_NATIVE_FLOAT" else switch (layout.kind) {
        .managed => "MYL_NATIVE_POINTER",
        .owned_buffer => "MYL_NATIVE_OWNED_BUFFER",
        .owned_pool => "MYL_NATIVE_OWNED_POOL",
        .resource => "MYL_NATIVE_RESOURCE",
        .record, .domain => "MYL_NATIVE_RECORD",
        .array => "MYL_NATIVE_ARRAY",
        .variant => "MYL_NATIVE_VARIANT",
        else => "MYL_NATIVE_PLAIN",
    };
    const fields = if (layout.fields.len == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_fields", .{name});
    var collection_kind: usize = 0;
    var element: []const u8 = "NULL";
    var key: []const u8 = "NULL";
    if (layout.kind == .managed) {
        const record = catalog.records[ty.recordIndex()];
        collection_kind = switch (record.collection.kind) {
            .list => 1,
            .string => 2,
            .dictionary => 3,
            .bytes => 4,
        };
        const element_type: typed.Type = if (record.collection.kind == .string) .u32 else record.shape.buffer orelse return error.InvalidType;
        element = try std.fmt.allocPrint(a, "&{s}", .{try symbol(a, catalog, element_type)});
        if (record.collection.key) |key_type| key = try std.fmt.allocPrint(a, "&{s}", .{try symbol(a, catalog, key_type)});
    }
    writer.print(
        "const myl_native_type {s} = {{.size={d},.alignment={d},.fields={s},.field_count={d}," ++
            ".count={d},.stride={d},.kind={s},.collection_kind={d},.element={s},.key={s}}};\n",
        .{ name, layout.size, layout.alignment, fields, layout.fields.len, layout.count, layout.stride, kind, collection_kind, element, key },
    ) catch return error.OutOfMemory;
}

test "native descriptors are catalog-order independent" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const records_a = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "A", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
        .{ .id = @fromBackingInt(base + 1), .name = "B", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = @fromBackingInt(base), .length = 2 } } },
    };
    const records_b = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "B", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = @fromBackingInt(base + 1), .length = 2 } } },
        .{ .id = @fromBackingInt(base + 1), .name = "A", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
    };
    var first = try native.Catalog.initRecords(std.testing.allocator, &records_a);
    defer first.deinit();
    var second = try native.Catalog.initRecords(std.testing.allocator, &records_b);
    defer second.deinit();
    const a = try generate(std.testing.allocator, &first);
    defer std.testing.allocator.free(a);
    const b = try generate(std.testing.allocator, &second);
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings(a, b);
    try std.testing.expect(std.mem.indexOf(u8, a, "MYL_NATIVE_ARRAY") != null);
}
