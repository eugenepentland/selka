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
        const layout = try catalog.layout(item.ty);
        if (layout.kind == .niche) {
            // QBE-NICHE-1: a niche optional's word is its payload reference or
            // null, and every descriptor walk — tracing, the region check, the
            // escape copier, structural equality — already treats a null pointer
            // as no reference. So the runtime sees the payload's own pointer
            // descriptor under this name and needs no kind of its own.
            const payload = layout.fields[0].ty;
            try emit(a, writer, catalog, item.name, try catalog.layout(payload), payload);
        } else try emit(a, writer, catalog, item.name, layout, item.ty);
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
    var trace_field_count: usize = 0;
    if (layout.trace) for (layout.fields) |field| {
        if ((try catalog.layout(field.ty)).trace) trace_field_count += 1;
    };
    if (trace_field_count != 0) {
        writer.print("static const myl_native_field {s}_trace_fields[] = {{\n", .{name}) catch return error.OutOfMemory;
        for (layout.fields) |field| {
            if (!(try catalog.layout(field.ty)).trace) continue;
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
    const trace_fields = if (trace_field_count == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_trace_fields", .{name});
    const trace_mode = if (!layout.trace) "MYL_NATIVE_TRACE_NONE" else "MYL_NATIVE_TRACE_FIELDS";
    var collection_kind: usize = 0;
    var element: []const u8 = "NULL";
    var key: []const u8 = "NULL";
    if (layout.kind == .managed and catalog.records[ty.recordIndex()].isCollection()) {
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
            ".count={d},.stride={d},.kind={s},.collection_kind={d},.element={s},.key={s}," ++
            ".trace_fields={s},.trace_field_count={d},.trace_mode={s}}};\n",
        .{ name, layout.size, layout.alignment, fields, layout.fields.len, layout.count, layout.stride, kind, collection_kind, element, key, trace_fields, trace_field_count, trace_mode },
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

test "native descriptors separate GC fields from complete structural fields" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const node: typed.Type = @fromBackingInt(base);
    const holder: typed.Type = @fromBackingInt(base + 1);
    const fields = [_]typed.Field{
        .{ .name = "span", .declaration = span, .ty = .u64 },
        .{ .name = "node", .declaration = span, .ty = node },
    };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .managed = true },
        .{ .id = holder, .name = "Holder", .declaration = span, .fields = &fields },
    };
    var catalog = try native.Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const output = try generate(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(output);
    const holder_name = try symbol(std.testing.allocator, &catalog, holder);
    defer std.testing.allocator.free(holder_name);
    const node_name = try symbol(std.testing.allocator, &catalog, node);
    defer std.testing.allocator.free(node_name);
    const trace_field = try std.fmt.allocPrint(std.testing.allocator, "static const myl_native_field {s}_trace_fields[] = {{\n {{.offset=8,.type=&{s},.tag=0}},\n}};", .{ holder_name, node_name });
    defer std.testing.allocator.free(trace_field);
    try std.testing.expect(std.mem.indexOf(u8, output, trace_field) != null);
    const holder_mode = try std.fmt.allocPrint(std.testing.allocator, ".trace_fields={s}_trace_fields,.trace_field_count=1,.trace_mode=MYL_NATIVE_TRACE_FIELDS", .{holder_name});
    defer std.testing.allocator.free(holder_mode);
    try std.testing.expect(std.mem.indexOf(u8, output, holder_mode) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".trace_fields=NULL,.trace_field_count=0,.trace_mode=MYL_NATIVE_TRACE_NONE") != null);
}

// spec-case: QBE-NICHE-1
test "a niche optional is described to the runtime exactly as its payload's pointer" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const node: typed.Type = @fromBackingInt(base);
    const maybe: typed.Type = @fromBackingInt(base + 1);
    const holder: typed.Type = @fromBackingInt(base + 2);
    const cases = [_]typed.Variant{ .{ .name = "none", .declaration = span, .payload = null }, .{ .name = "some", .declaration = span, .payload = node } };
    const fields = [_]typed.Field{
        .{ .name = "span", .declaration = span, .ty = .u64 },
        .{ .name = "next", .declaration = span, .ty = maybe },
    };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .managed = true },
        .{ .id = maybe, .name = "Option<Node>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &cases } } },
        .{ .id = holder, .name = "Holder", .declaration = span, .fields = &fields },
    };
    var catalog = try native.Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const output = try generate(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(output);
    const holder_name = try symbol(std.testing.allocator, &catalog, holder);
    defer std.testing.allocator.free(holder_name);
    const node_name = try symbol(std.testing.allocator, &catalog, node);
    defer std.testing.allocator.free(node_name);
    const maybe_name = try symbol(std.testing.allocator, &catalog, maybe);
    defer std.testing.allocator.free(maybe_name);
    // The holder's GC table names the optional's own descriptor at the field's offset.
    const traced = try std.fmt.allocPrint(std.testing.allocator, "static const myl_native_field {s}_trace_fields[] = {{\n {{.offset=8,.type=&{s},.tag=0}},\n}};", .{ holder_name, maybe_name });
    defer std.testing.allocator.free(traced);
    try std.testing.expect(std.mem.indexOf(u8, output, traced) != null);
    // That descriptor is the payload's pointer descriptor under the optional's name.
    const maybe_head = try std.fmt.allocPrint(std.testing.allocator, "const myl_native_type {s} = ", .{maybe_name});
    defer std.testing.allocator.free(maybe_head);
    const node_head = try std.fmt.allocPrint(std.testing.allocator, "const myl_native_type {s} = ", .{node_name});
    defer std.testing.allocator.free(node_head);
    const maybe_at = std.mem.indexOf(u8, output, maybe_head).? + maybe_head.len;
    const node_at = std.mem.indexOf(u8, output, node_head).? + node_head.len;
    const maybe_body = output[maybe_at..std.mem.indexOfScalarPos(u8, output, maybe_at, '\n').?];
    const node_body = output[node_at..std.mem.indexOfScalarPos(u8, output, node_at, '\n').?];
    try std.testing.expectEqualStrings(node_body, maybe_body);
    try std.testing.expect(std.mem.indexOf(u8, maybe_body, ".size=8,.alignment=8,.fields=NULL,") != null);
    try std.testing.expect(std.mem.indexOf(u8, maybe_body, ".kind=MYL_NATIVE_POINTER,") != null);
}
