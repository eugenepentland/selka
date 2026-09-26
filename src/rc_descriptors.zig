//! Direct owning-edge metadata for the RC-v1 runtime (RC-OWNERSHIP-PLAN-1).
//! Shapes stop at pointers; allocation descriptors separately describe bodies.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");

/// Layout, allocation or output failure while generating ownership metadata.
pub const Error = native.Error;
/// The generated C module registered before guest construction begins.
pub const module_symbol = "myl_rc_generated_module";

const Item = struct { ty: typed.Type, name: []const u8, body: bool = false, unique_body: bool = false };

/// Stable shape symbol corresponding to a native semantic type identity.
pub fn symbol(allocator: std.mem.Allocator, catalog: *const native.Catalog, ty: typed.Type) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_rc", .{try descriptors.symbol(allocator, catalog, ty)});
}

/// Emit shapes for every inline type and independently allocated record body.
/// Allocation adapters register their runtime-owned collection headers separately.
pub fn generate(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const items = try collect(a, catalog);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    writer.writeAll("#include \"native_rc.h\"\n") catch return error.OutOfMemory;
    for (items) |item| {
        writer.print("extern const myl_native_type {s};\nextern const myl_rc_shape {s}_rc;\n", .{ item.name, item.name }) catch return error.OutOfMemory;
    }
    for (items) |item| {
        const layout = if (item.body) try catalog.heapLayout(item.ty) else try catalog.layout(item.ty);
        defer if (item.body) catalog.releaseLayout(layout);
        try emit(a, writer, catalog, item, layout);
    }
    try module(writer, items);
    return output.toOwnedSlice();
}

fn collect(a: std.mem.Allocator, catalog: *native.Catalog) Error![]const Item {
    var items: std.ArrayList(Item) = .empty;
    for (0..typed.Type.record_base + catalog.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(index);
        const name = try descriptors.symbol(a, catalog, ty);
        try items.append(a, .{ .ty = ty, .name = name });
        if (!ty.isAggregate()) continue;
        const record = catalog.records[ty.recordIndex()];
        if (record.managed and record.shape.array == null and !record.shape.hasRuntimeIdentity()) {
            const body = try catalog.heapLayout(ty);
            defer catalog.releaseLayout(body);
            try items.append(a, .{ .ty = ty, .name = try std.fmt.allocPrint(a, "{s}_body", .{name}), .body = true, .unique_body = body.drop });
        }
    }
    const result = try items.toOwnedSlice(a);
    std.mem.sort(Item, result, {}, less);
    return result;
}

fn less(_: void, a: Item, b: Item) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn emit(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, item: Item, layout: native.Layout) Error!void {
    const kind: []const u8 = switch (layout.kind) {
        .managed, .niche => "POINTER",
        .record, .domain => "RECORD",
        .array => "ARRAY",
        .variant => "VARIANT",
        .scalar, .handle, .pool_handle, .callable, .resource, .owned_buffer, .owned_pool => "NONE",
    };
    const fields = layout.kind == .record or layout.kind == .domain or layout.kind == .variant;
    if (fields and layout.fields.len != 0) {
        writer.print("static const myl_rc_field {s}_rc_fields[] = {{\n", .{item.name}) catch return error.OutOfMemory;
        for (layout.fields) |field| {
            writer.print(" {{.offset={d},.shape=&{s},.tag={d}}},\n", .{ field.offset, try symbol(a, catalog, field.ty), field.tag orelse 0 }) catch return error.OutOfMemory;
        }
        writer.writeAll("};\n") catch return error.OutOfMemory;
    }
    writer.print("const myl_rc_shape {s}_rc = {{.size={d},.kind=MYL_RC_SHAPE_{s}", .{ item.name, layout.size, kind }) catch return error.OutOfMemory;
    switch (layout.kind) {
        .record, .domain, .variant => {
            const member = if (layout.kind == .variant) "variant" else "record";
            const list = if (layout.fields.len == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_rc_fields", .{item.name});
            writer.print(",.as.{s}={{.fields={s},.count={d}", .{ member, list, layout.fields.len }) catch return error.OutOfMemory;
            if (layout.kind == .variant) writer.writeAll(",.tag_offset=0") catch return error.OutOfMemory;
            writer.writeAll("}") catch return error.OutOfMemory;
        },
        .array => {
            if (layout.fields.len != 1) return error.InvalidType;
            writer.print(",.as.array={{.element=&{s},.count={d},.stride={d}}}", .{ try symbol(a, catalog, layout.fields[0].ty), layout.count, layout.stride }) catch return error.OutOfMemory;
        },
        else => {},
    }
    writer.writeAll("};\n") catch return error.OutOfMemory;
}

fn module(writer: *std.Io.Writer, items: []const Item) Error!void {
    writer.writeAll("static const myl_rc_shape *const myl_rc_generated_shapes[] = {\n") catch return error.OutOfMemory;
    for (items) |item| writer.print(" &{s}_rc,\n", .{item.name}) catch return error.OutOfMemory;
    writer.writeAll("};\nstatic const myl_rc_descriptor myl_rc_generated_descriptors[] = {\n") catch return error.OutOfMemory;
    for (items) |item| writer.print(" {{.type=&{s},.shape=&{s}_rc,.edges=NULL,.finalize={s}}},\n", .{ item.name, item.name, if (item.unique_body) "myl_rc_finalize_unique" else "NULL" }) catch return error.OutOfMemory;
    writer.print("}};\nconst myl_rc_module {s} = {{.abi=MYL_RC_ABI_VERSION," ++
        ".shapes=myl_rc_generated_shapes,.shape_count={d}," ++
        ".descriptors=myl_rc_generated_descriptors,.descriptor_count={d}}};\n", .{ module_symbol, items.len, items.len }) catch return error.OutOfMemory;
}
