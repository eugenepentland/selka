//! Source-aware rendering metadata; the value IR keeps its frozen physical types.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;

/// Allocation or a source type without a printable value stops lowering.
pub const Error = error{ OutOfMemory, Unsupported };
/// Ephemeral checked-source metadata, carried in the module's private strings.
pub const prefix = "\x00myl.core.render.source.";
/// Compiler-only declarations authorize each metadata string index and graph ID.
pub const declaration_prefix = "myl_core_render_shape_";
/// The runtime descriptor's seven fields, with symbolic child references.
pub const Shape = struct {
    kind: u32 = 0,
    size: u32 = 0,
    count: u32 = 0,
    aux: u32 = 0,
    children: []const []const u8 = &.{},
    offsets: []const u32 = &.{},
    names: []const []const u8 = &.{},
};

/// Render one checked source type through a borrowed, managed physical box.
pub fn render(comptime Context: type, b: Context, value: ir.Ref, source: typed.Type, span: u32) Error!ir.Ref {
    if (value == .none) return b.runtimeCall("myl_core_none_text", &.{}, .str, &.{}, span);
    const first_string = b.mb.module.strings.items.len;
    const first_function = b.mb.module.functions.items.len;
    errdefer {
        b.mb.module.strings.shrinkRetainingCapacity(first_string);
        b.mb.module.functions.shrinkRetainingCapacity(first_function);
    }
    const physical = b.typeOfRef(value);
    _ = try descriptor(Context, b, source, physical, span);
    const box = try b.mb.module.intern(b.allocator(), .{ .box = physical });
    const held = try b.emit(.{ .op = .box_make, .ty = box, .a = value, .span = span });
    const symbol = try std.fmt.allocPrint(b.allocator(), "myl_core_show_{d}", .{@backingInt(source)});
    const callee = try b.mb.runtimeFunction(symbol, &.{box}, .str, .runtime_c);
    return b.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(callee), .data = try b.extraSlice(&.{held}), .span = span });
}

/// Reserve before visiting children, so boxed recursive schemas form a finite graph.
fn descriptor(comptime Context: type, b: Context, source: typed.Type, physical: ir.Type, span: u32) Error![]const u8 {
    const id = if (b.mb.module.kind(physical) == .box or (source == .unit and physical != .void))
        try std.fmt.allocPrint(b.allocator(), "{d}_p{d}", .{ @backingInt(source), @backingInt(physical) })
    else
        try std.fmt.allocPrint(b.allocator(), "{d}", .{@backingInt(source)});
    const suffix = try std.fmt.allocPrint(b.allocator(), "_{s}", .{id});
    for (b.mb.module.functions.items) |function| {
        if (function.signature.linkage != .runtime_c) continue;
        if (std.mem.startsWith(u8, function.name, declaration_prefix) and std.mem.endsWith(u8, function.name, suffix)) return id;
    }
    const marker = try std.fmt.allocPrint(b.allocator(), "{s}{s}|", .{ prefix, id });
    const index = b.mb.module.strings.items.len;
    try b.mb.module.strings.append(b.allocator(), marker);
    // A source literal or embedded blob can contain the same marker bytes. Only
    // this compiler-only declaration authorizes parsing the indexed string.
    const symbol = try std.fmt.allocPrint(b.allocator(), "{s}{d}_{s}", .{ declaration_prefix, index, id });
    _ = try b.mb.runtimeFunction(symbol, &.{}, .void, .runtime_c);
    const shape = try sourceShape(Context, b, source, physical, span);
    const json = try std.json.Stringify.valueAlloc(b.allocator(), shape, .{});
    b.mb.module.strings.items[index] = try std.fmt.allocPrint(b.allocator(), "{s}{s}", .{ marker, json });
    return id;
}

fn sourceShape(comptime Context: type, b: Context, source: typed.Type, physical: ir.Type, span: u32) Error!Shape {
    const size = b.mb.module.size(physical);
    if (b.mb.module.kind(physical) == .box) {
        const child = try descriptor(Context, b, source, b.mb.module.compound(physical).box, span);
        return .{ .kind = 6, .size = size, .children = try b.allocator().dupe([]const u8, &.{child}) };
    }
    if (source == .unit) return .{ .size = size };
    if (source == .bool) return .{ .kind = 1, .size = size, .aux = 1 };
    if (source.integer()) |info| return .{ .kind = 1, .size = size, .aux = if (info.signed) 2 else 0 };
    if (!source.isAggregate()) return b.mb.refuse("rendering a non-value source type", span);
    const record = b.mb.input.program.records[source.recordIndex()];
    if (record.isCollection()) return collectionShape(Context, b, record, physical, span);
    if (record.shape.domain) |wire| {
        if (physical == .f64 and std.mem.eql(u8, record.name, "float")) {
            _ = try b.mb.runtimeFunction("myl_core_str_from_f64", &.{.f64}, .str, .extern_c);
            return .{ .kind = 2, .size = size };
        }
        const child = try descriptor(Context, b, wire, physical, span);
        return .{ .kind = 11, .size = size, .children = try b.allocator().dupe([]const u8, &.{child}), .names = try b.allocator().dupe([]const u8, &.{shortName(record.name)}) };
    }
    if (record.shape.variants) |variants| return variantShape(Context, b, record, variants, physical, span);
    if (record.shape.array) |array| {
        const fixed = b.mb.module.compound(physical).array;
        const child = try descriptor(Context, b, array.element, fixed.elem, span);
        return .{ .kind = 8, .size = size, .count = fixed.n, .children = try b.allocator().dupe([]const u8, &.{child}) };
    }
    return recordShape(Context, b, record, physical, span);
}

fn collectionShape(comptime Context: type, b: Context, record: typed.Record, physical: ir.Type, span: u32) Error!Shape {
    const size = b.mb.module.size(physical);
    switch (record.collection.kind) {
        .string, .bytes => return .{ .kind = 3, .size = size, .aux = if (record.collection.kind == .string) 0 else 1 },
        .list => {
            const child = try descriptor(Context, b, record.shape.buffer.?, b.mb.module.compound(physical).list, span);
            return .{ .kind = 7, .size = size, .children = try b.allocator().dupe([]const u8, &.{child}) };
        },
        .dictionary => {
            const table = b.mb.module.compound(physical).dict;
            const key = try descriptor(Context, b, record.collection.key.?, table.key, span);
            const value = try descriptor(Context, b, if (record.collection.set) .unit else record.shape.buffer.?, table.value, span);
            return .{ .kind = 9, .size = size, .aux = if (record.collection.set) 1 else 2, .children = try b.allocator().dupe([]const u8, &.{ key, value }) };
        },
    }
}

fn recordShape(comptime Context: type, b: Context, record: typed.Record, physical: ir.Type, span: u32) Error!Shape {
    if (b.mb.module.kind(physical) != .record) return b.mb.refuse("rendering a source record representation", span);
    const fields = b.mb.module.compound(physical).record;
    if (fields.len != record.fields.len) return b.mb.refuse("rendering a source record layout", span);
    const children = try b.allocator().alloc([]const u8, fields.len);
    const offsets = try b.allocator().alloc(u32, fields.len);
    const names = try b.allocator().alloc([]const u8, fields.len + 1);
    names[0] = shortName(record.name);
    for (record.fields, fields, 0..) |field, stored, i| {
        children[i] = try descriptor(Context, b, field.ty, stored, span);
        offsets[i] = b.mb.module.fieldOffset(physical, i);
        names[i + 1] = field.name;
    }
    return .{ .kind = 4, .size = b.mb.module.size(physical), .count = @intCast(fields.len), .aux = @intFromBool(record.shape.tuple), .children = children, .offsets = offsets, .names = names };
}

fn variantShape(comptime Context: type, b: Context, record: typed.Record, variants: typed.Variants, physical: ir.Type, span: u32) Error!Shape {
    const cases = b.mb.module.compound(physical).@"union";
    const children = try b.allocator().alloc([]const u8, cases.len);
    const present = try b.allocator().alloc(u32, cases.len);
    const names = try b.allocator().alloc([]const u8, cases.len);
    for (variants.cases, cases, 0..) |case, stored, i| {
        children[i] = try descriptor(Context, b, case.payload orelse .unit, stored, span);
        present[i] = if (case.fielded) 2 else @intFromBool(case.payload != null);
        // Exact constructor spelling from native_render.caseName and io_render.variant.
        const anonymous = std.mem.eql(u8, case.name, if (case.payload != null) "some" else "none");
        names[i] = if (variants.fallible or anonymous) spelling(case.name) else try std.fmt.allocPrint(b.allocator(), "{s}.{s}", .{ shortName(record.name), case.name });
    }
    const layout = b.mb.module.unionLayout(physical);
    return .{ .kind = 5, .size = b.mb.module.size(physical), .count = @intCast(cases.len), .aux = if (layout.form == .niche) layout.empty_case + 1 else 0, .children = children, .offsets = present, .names = names };
}

fn shortName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
}

fn spelling(name: []const u8) []const u8 {
    inline for (.{ "ok", "err", "some", "none" }, .{ "Ok", "Err", "Some", "None" }) |source, surface| {
        if (std.mem.eql(u8, name, source)) return surface;
    }
    return name;
}
