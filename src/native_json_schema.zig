//! Emit nominal field/case names for the shared native JSON codec bridge.
const std = @import("std");
const typed = @import("typed.zig");
/// Schemas describe data shapes; runtime identity and domain conversion stay explicit.
pub fn emit(w: *std.Io.Writer, program: @import("bytecode_model.zig").Program) error{WriteFailed}!void {
    const records = program.records;
    try w.writeAll(@embedFile("native_json_abi.h"));
    try w.writeAll("static const NativeJsonShape json_shapes[] = {\n");
    for (0..typed.Type.record_base + records.len) |index| {
        const ty: typed.Type = @fromBackingInt(@intCast(index));
        try w.print("{{\"{s}\",", .{typed.typeName(ty, records)});
        if (!ty.isAggregate()) {
            try w.print("{d},0,NULL,NULL,SIZE_MAX,0}},\n", .{@as(u8, if (ty.isInteger() or ty == .bool) 1 else 0)});
            continue;
        }
        const record = records[ty.recordIndex()];
        if (record.shape.hasRuntimeIdentity() or record.contract.move_only) {
            try w.writeAll("0,0,NULL,NULL,SIZE_MAX,0},\n");
            continue;
        }
        if (record.shape.domain) |backing| {
            try w.print("5,1,(const size_t[]){{{d}}},NULL,SIZE_MAX,0}},\n", .{@backingInt(backing)});
            continue;
        }
        const kind: u8 = if (record.shape.variants != null) 4 else if (record.shape.array != null) 3 else 2;
        const count = if (record.shape.variants) |v| v.cases.len else record.count();
        try w.print("{d},{d},", .{ kind, count });
        try children(w, record);
        try w.writeAll(",");
        try names(w, record);
        if (record.tableKey()) |key| try w.print(",{d},", .{@backingInt(key)}) else try w.writeAll(",SIZE_MAX,");
        const flags: u8 = if (record.shape.variants) |v| @as(u8, @intFromBool(v.is_union)) | (@as(u8, @intFromBool(v.fallible)) << 1) else 0;
        try w.print("{d}}},\n", .{flags});
    }
    try w.writeAll("};\nstatic const NativeJsonCodec json_codecs[] = {\n");
    for (records) |record| if (record.contract.codec) |codec| {
        const result = program.functions[@backingInt(codec.decode)].signature.return_type;
        try w.print("{{{d},{d},{d},{d},{d}}},\n", .{ @backingInt(record.id), @backingInt(codec.wire), @backingInt(codec.decode), @backingInt(codec.encode), @backingInt(result) });
    };
    try w.writeAll("{SIZE_MAX,0,0,0,0}};\n");
}
fn children(w: *std.Io.Writer, record: typed.Record) !void {
    if (record.count() == 0 and record.shape.variants == null and record.shape.array == null) return w.writeAll("NULL");
    try w.writeAll("(const size_t[]){");
    if (record.shape.array) |array| {
        try w.print("{d},", .{@backingInt(array.element)});
    } else if (record.shape.variants) |variants| {
        for (variants.cases) |case| {
            if (case.payload) |ty| try w.print("{d},", .{@backingInt(ty)}) else try w.writeAll("SIZE_MAX,");
        }
    } else for (record.fields) |field| try w.print("{d},", .{@backingInt(field.ty)});
    try w.writeByte('}');
}
fn names(w: *std.Io.Writer, record: typed.Record) !void {
    if (record.shape.array != null or (record.fields.len == 0 and record.shape.variants == null)) return w.writeAll("NULL");
    try w.writeAll("(const char *const[]){");
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| try w.print("\"{s}\",", .{case.name});
    } else for (record.fields) |field| try w.print("\"{s}\",", .{field.name});
    try w.writeByte('}');
}
