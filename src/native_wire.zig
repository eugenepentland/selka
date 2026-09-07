//! Native host schemas for ordinary values and opt-in declared domain codecs.
const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode.zig");
const native_layout = @import("native_layout.zig");

/// Mark finite value shapes supported by the selected host conversion mode.
pub fn supported(allocator: std.mem.Allocator, records: []const typed.Record, codecs: bool) std.mem.Allocator.Error![]bool {
    const flags = try allocator.alloc(bool, records.len);
    @memset(flags, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, i| {
            if (flags[i] or record.shape.hasRuntimeIdentity() or record.contract.move_only) continue;
            if (record.shape.domain != null) {
                const codec = record.contract.codec orelse continue;
                if (!codecs or !valueSupported(codec.wire, flags)) continue;
            } else if (!childrenSupported(record, flags)) continue;
            flags[i] = true;
            changed = true;
        }
    }
    return flags;
}
fn childrenSupported(record: typed.Record, flags: []const bool) bool {
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |ty| {
            if (!valueSupported(ty, flags)) return false;
        };
    } else if (record.shape.array) |array| {
        if (!valueSupported(array.element, flags)) return false;
    } else for (record.fields) |field| {
        if (!valueSupported(field.ty, flags)) return false;
    }
    return true;
}
fn valueSupported(ty: typed.Type, flags: []const bool) bool {
    return if (ty.isAggregate()) flags[ty.recordIndex()] else ty.isInteger() or ty == .bool;
}
/// Check the complete public signature before copying host values or executing code.
pub fn signature(function: bc.Function, flags: []const bool) bool {
    if (function.signature.return_reference != null or !valueSupported(function.signature.return_type, flags)) return false;
    for (function.scope.locals[0..function.signature.parameter_count]) |local| {
        if (local.parameter.reference_parameter != null or !valueSupported(local.ty, flags)) return false;
    }
    return true;
}
/// Emit a private schema table consumed by the bounded native wire reader/writer.
pub fn emit(w: *std.Io.Writer, layout: native_layout.Layout, flags: []const bool, functions: []const bc.Function) error{ WriteFailed, InternalError }!void {
    try w.writeAll("#ifdef MYLANG_EMBED\n");
    try w.writeAll(@embedFile("native_wire.c"));
    try w.writeAll("static const WireSchema wire_schemas[] = {\n");
    for (0..typed.Type.record_base + layout.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(@intCast(index));
        try w.print("{{\"{s}\",", .{typed.typeName(ty, layout.records)});
        if (!valueSupported(ty, flags)) {
            try w.writeAll("0,0,0,0,0,NULL},\n");
        } else if (!ty.isAggregate()) {
            try w.print("1,{d},{d},0,0,NULL}},\n", .{ layout.width(ty), @intFromBool(layout.signed(ty)) });
        } else if (layout.records[ty.recordIndex()].shape.domain != null) {
            try emitCodec(w, layout, layout.records[ty.recordIndex()], functions);
        } else try emitRecord(w, layout, layout.records[ty.recordIndex()]);
    }
    try w.writeAll("};\n#endif\n");
}
/// Emit the common ordinary record/array/variant shape used by both copied host ABIs.
pub fn emitRecord(w: *std.Io.Writer, layout: native_layout.Layout, record: typed.Record) error{WriteFailed}!void {
    const kind: u8 = if (record.shape.variants != null) 4 else if (record.shape.array != null) 3 else 2;
    const count = if (record.shape.variants) |v| v.cases.len else if (record.shape.array) |a| a.length else record.fields.len;
    const tag_bits = if (kind == 4) native_layout.tagBits(count) else 0;
    try w.print("{d},{d},0,{d},{d},", .{ kind, layout.width(record.id), tag_bits, count });
    if (count == 0 and kind != 3) return w.writeAll("NULL},\n");
    try w.writeAll("(const size_t[]){");
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| {
            if (case.payload) |ty| try w.print("{d},", .{@backingInt(ty)}) else try w.writeAll("SIZE_MAX,");
        }
    } else if (record.shape.array) |array| {
        try w.print("{d},", .{@backingInt(array.element)});
    } else for (record.fields) |field| try w.print("{d},", .{@backingInt(field.ty)});
    try w.writeAll("}},\n");
}

fn emitCodec(w: *std.Io.Writer, layout: native_layout.Layout, record: typed.Record, functions: []const bc.Function) !void {
    const codec = record.contract.codec orelse return error.InternalError;
    const result = functions[@backingInt(codec.decode)].signature.return_type;
    const shape = typed.resultShape(result, layout.records) orelse return error.InternalError;
    try w.print("5,{d},{d},0,0,NULL,&(const WireCodec){{{d},{d},{d},{d},{d},{d},{d}}}}},\n", .{
        layout.width(record.id),   @intFromBool(layout.signed(record.id)), @backingInt(codec.wire),
        @backingInt(codec.decode), @backingInt(codec.encode),              @backingInt(result),
        shape.ok_tag,              shape.error_tag,                        @backingInt(shape.error_type),
    });
}
