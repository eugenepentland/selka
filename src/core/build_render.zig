//! Source-aware rendering metadata; the value IR keeps its frozen physical types.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const display_name = @import("selka").display_name;

/// Allocation or a source type without a printable value stops lowering.
pub const Error = error{ OutOfMemory, Unsupported };
/// Ephemeral checked-source metadata, carried in the module's private strings.
pub const prefix = "\x00myl.core.render.source.";
/// Compiler-only declarations authorize each metadata string index and graph ID.
pub const declaration_prefix = "myl_core_render_shape_";
/// Rendering declarations contain numeric private identities, never arbitrary names.
pub const Generated = enum { show, shape };

/// Exact compiler-generated name grammar, shared with ownership and emission.
pub fn generated(symbol: []const u8) ?Generated {
    const show = "myl_core_show_";
    if (std.mem.startsWith(u8, symbol, show)) return if (renderId(symbol[show.len..])) .show else null;
    if (!std.mem.startsWith(u8, symbol, declaration_prefix)) return null;
    const suffix = symbol[declaration_prefix.len..];
    const split = std.mem.indexOfScalar(u8, suffix, '_') orelse return null;
    if (!decimalId(suffix[0..split]) or !renderId(suffix[split + 1 ..])) return null;
    return .shape;
}

/// A render id: the text of one key (`ModuleBuilder.renderId`), and `_v` when the described value is a list view.
fn renderId(id: []const u8) bool {
    const key = if (std.mem.endsWith(u8, id, "_v")) id[0 .. id.len - 2] else id;
    return @import("stable_names.zig").isKeyList(key, 1);
}

/// Whether a show helper's one parameter is a list view (its id carries `_v`), which the helper borrows (CX2).
pub fn borrowsListView(symbol: []const u8) bool {
    const show = "myl_core_show_";
    return std.mem.startsWith(u8, symbol, show) and std.mem.indexOf(u8, symbol[show.len..], "_v") != null;
}

fn decimalId(id: []const u8) bool {
    if (id.len == 0) return false;
    for (id) |byte| if (!std.ascii.isDigit(byte)) return false;
    _ = std.fmt.parseInt(u32, id, 10) catch return false;
    return true;
}

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

/// Render one checked source type without making its borrowed value an owner.
pub fn render(comptime Context: type, b: Context, raw: ir.Ref, source: typed.Type, span: u32) Error!ir.Ref {
    if (raw == .none) return b.runtimeCall("myl_core_none_text", &.{}, .str, &.{}, span);
    // A list view renders in place from its `(data, count)` span (CX2): no copy and no owner, whether it is a
    // plain parameter's view, a slice of an owned list, or a slice of a view. The renderer reads the elements only.
    return renderValue(Context, b, raw, source, span);
}

/// Render `value`, a value of a type that has a block (or a bytes view): the renderer of its checked type.
fn renderValue(comptime Context: type, b: Context, raw: ir.Ref, source: typed.Type, span: u32) Error!ir.Ref {
    // Runtime declarations use storage types. The inverse overlay remains a
    // borrow, so rendering a whole borrowed record/table keeps its owner live.
    const value = try b.borrowStorage(raw, span);
    // A bytes view spells as its bytes do (`text_repr` of the octets, the leaf rule of `myl_core_values_render`), in
    // place through the span form (C9 bytes): no owned copy and no block to render.
    if (b.typeOfRef(value) == .bytes_view) return b.runtimeCall("myl_core_text_repr", &.{ .bytes_view, .bool }, .str, &.{ value, try b.constant(.bool, 1) }, span);
    const first_string = b.mb.module.strings.items.len;
    const first_function = b.mb.module.functions.items.len;
    errdefer {
        b.mb.module.strings.shrinkRetainingCapacity(first_string);
        b.mb.module.functions.shrinkRetainingCapacity(first_function);
    }
    const physical = b.typeOfRef(value);
    const id = try descriptor(Context, b, source, physical, span);
    const symbol = try std.fmt.allocPrint(b.allocator(), "myl_core_show_{s}", .{id});
    const callee = try b.mb.runtimeFunction(symbol, &.{physical}, .str, .runtime_c);
    return b.emit(.{ .op = .call, .ty = .str, .a = @fromBackingInt(callee), .data = try b.extraSlice(&.{value}), .span = span });
}

/// Reserve before visiting children, so boxed recursive schemas form a finite graph.
fn descriptor(comptime Context: type, b: Context, source: typed.Type, raw: ir.Type, span: u32) Error![]const u8 {
    // A borrow overlay has exactly its storage layout. Standard wrappers can
    // instead change layout: Option<str_view> and Option<str> need distinct
    // descriptors even though they name the same checked source type.
    const physical = b.mb.module.storageType(raw);
    const id = try b.mb.renderId(source, physical, b.mb.module.kind(physical) == .list_view);
    const suffix = try std.fmt.allocPrint(b.allocator(), "_{s}", .{id});
    for (b.mb.module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .runtime_c) continue;
        if (std.mem.startsWith(u8, function.name, declaration_prefix) and std.mem.endsWith(u8, function.name, suffix)) {
            // The lowering relies on a declaration another function made: a request of this function too.
            try b.mb.touch(@intCast(index));
            return id;
        }
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
        if (physical == .f32 and std.mem.eql(u8, record.name, "f32")) {
            _ = try b.mb.runtimeFunction("myl_core_str_from_f32", &.{.f32}, .str, .extern_c);
            return .{ .kind = 13, .size = size };
        }
        const child = try descriptor(Context, b, wire, physical, span);
        return .{ .kind = 11, .size = size, .children = try b.allocator().dupe([]const u8, &.{child}), .names = try b.allocator().dupe([]const u8, &.{try display_name.printed(b.allocator(), record.name)}) };
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
        .string, .bytes => return .{ .kind = if (physical.isSpan()) 14 else 3, .size = size, .aux = if (record.collection.kind == .string) 0 else 1 },
        .list => {
            // A list view's span is `{data, count}` (kind 12); an owned list is its block (kind 7).
            const view = b.mb.module.kind(physical) == .list_view;
            const element = if (view) b.mb.module.compound(physical).list_view else b.mb.module.compound(physical).list;
            const child = try descriptor(Context, b, record.shape.buffer.?, element, span);
            return .{ .kind = if (view) 12 else 7, .size = size, .children = try b.allocator().dupe([]const u8, &.{child}) };
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
    names[0] = try display_name.printed(b.allocator(), record.name);
    for (record.fields, fields, 0..) |field, stored, i| {
        children[i] = try descriptor(Context, b, field.ty, stored, span);
        offsets[i] = b.mb.module.fieldOffset(physical, i);
        names[i + 1] = field.name;
    }
    // `json.CodecError` prints as its sentence (CODEC-1): `str(error)` is the line a person acts on, not the record.
    const sentence = std.mem.eql(u8, record.name, "json::CodecError") and fields.len == 4 and fields[3] == .str;
    const aux: u32 = if (sentence) 2 else @intFromBool(record.shape.tuple);
    return .{ .kind = 4, .size = b.mb.module.size(physical), .count = @intCast(fields.len), .aux = aux, .children = children, .offsets = offsets, .names = names };
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
        // Only the builtin Option (and a fallible Result) keeps the prelude spelling; a
        // user enum's `none` is `Kind.none`, never the ambiguous `None` (FR-421).
        const option = std.mem.startsWith(u8, record.name, "Option<") or std.mem.startsWith(u8, record.name, "std_result::Option<");
        names[i] = if (variants.fallible or option) spelling(case.name) else try std.fmt.allocPrint(b.allocator(), "{s}.{s}", .{ try display_name.printed(b.allocator(), record.name), case.name });
    }
    const layout = b.mb.module.unionLayout(physical);
    return .{ .kind = 5, .size = b.mb.module.size(physical), .count = @intCast(cases.len), .aux = if (layout.form == .niche) layout.empty_case + 1 else 0, .children = children, .offsets = present, .names = names };
}

fn spelling(name: []const u8) []const u8 {
    inline for (.{ "ok", "err", "some", "none" }, .{ "Ok", "Err", "Some", "None" }) |source, surface| {
        if (std.mem.eql(u8, name, source)) return surface;
    }
    return name;
}
