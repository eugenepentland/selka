//! Compiler-owned nominal descriptors for copied native host declarations.
const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode.zig");
const Layout = @import("native_layout.zig").Layout;
/// Emit checked data shapes and declarations before direct native call sites.
pub fn emit(w: *std.Io.Writer, layout: Layout, program: bc.Program) error{WriteFailed}!void {
    try w.writeAll(@embedFile("native_host.c"));
    try w.writeAll("static const HostShape host_shapes[] = {\n");
    for (0..typed.Type.record_base + program.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(@intCast(index));
        try w.print("{{\"{s}\",", .{typed.typeName(ty, program.records)});
        if (!ty.isAggregate()) {
            if (ty.isInteger() or ty == .bool)
                try w.print("1,{d},{d},0,0,NULL}},\n", .{ layout.width(ty), @intFromBool(layout.signed(ty)) })
            else
                try w.writeAll("0,0,0,0,0,NULL},\n");
        } else try shape(w, layout, program.records[ty.recordIndex()]);
    }
    try w.writeAll("};\nstatic const HostDeclaration host_declarations[] = {\n");
    var count: usize = 0;
    for (program.functions) |function| {
        if (function.policy.host == null) continue;
        count += 1;
        try w.print("{{\"{s}\",", .{function.name});
        if (function.signature.parameter_count == 0) try w.writeAll("NULL") else {
            try w.writeAll("(const size_t[]){");
            for (function.scope.locals[0..function.signature.parameter_count]) |parameter| try w.print("{d},", .{@backingInt(parameter.ty)});
            try w.writeByte('}');
        }
        try w.print(",{d},{d},{d}}},\n", .{ function.signature.parameter_count, @backingInt(function.signature.return_type), function.policy.effects });
    }
    if (count == 0) try w.writeAll("{NULL,NULL,0,0,0},\n");
    try w.print("}};\nstatic const size_t host_declaration_count={d};\n", .{count});
}
fn shape(w: *std.Io.Writer, layout: Layout, record: typed.Record) !void {
    if (record.shape.hasRuntimeIdentity() or record.contract.move_only) return w.writeAll("0,0,0,0,0,NULL},\n");
    if (record.shape.domain) |backing| return w.print("5,{d},{d},0,1,(const size_t[]){{{d}}}}},\n", .{ layout.width(record.id), @intFromBool(layout.signed(record.id)), @backingInt(backing) });
    try @import("native_wire.zig").emitRecord(w, layout, record);
}
/// Resolve the compact host declaration index independently of bytecode labels.
pub fn declarationIndex(functions: []const bc.Function, target: usize) usize {
    var result: usize = 0;
    for (functions[0..target]) |function| if (function.policy.host != null) {
        result += 1;
    };
    return result;
}
