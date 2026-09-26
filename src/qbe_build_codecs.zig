//! Generate copied native values with explicit compiled domain codec calls.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const shape = @import("qbe_build_shapes.zig");
const dispatch = @import("qbe_build_dispatch.zig");
const templates = @import("qbe_build_templates.zig");
const Value = std.json.Value;
/// Render native codec schemas, checked callbacks and the public codec-call ABI.
pub fn write(w: *std.Io.Writer, units: []const Value, metadata: Value, ordinary: []const Value) shape.Error!void {
    const shapes: shape.Shapes = .{ .types = v.array(v.get(metadata, "types")), .ordinary = ordinary, .codecs = true, .descriptors = v.array(v.get(metadata, "descriptors")) };
    try w.print("#define QBE_CODEC_ARGUMENTS {d}\n", .{dispatch.maximum(units, shapes)});
    // Every container being built holds one root while its children are read, so
    // a pool sized by argument count alone runs out on a list of text: the list
    // takes the argument's slot and the first text element has nowhere to root.
    // The nesting bound is the runtime's own, so the pool cannot be short of it.
    // A value being read keeps a root per finished sibling box on its path,
    // so the pool allows a few per level (RECURSIVE-VALUES-3).
    try w.writeAll("#define QBE_CODEC_DEPTH 128\n#define QBE_CODEC_ROOTS (QBE_CODEC_ARGUMENTS+8*QBE_CODEC_DEPTH)\n");
    try w.writeAll(@embedFile("qbe_codecs_runtime.c"));
    try w.writeByte('\n');
    try shapes.typedefs(w);
    try shapes.descriptorTable(w);
    try w.writeAll("static const CoType co_types[]={\n");
    for (shapes.types) |item| {
        try shapes.schema(w, item);
        try w.writeByte(',');
        try codec(w, shapes, v.array(v.get(metadata, "codecs")), v.text(v.get(item, "name")));
        try w.writeAll("},\n");
    }
    if (shapes.types.len == 0) try w.writeAll("{0},\n");
    try w.writeAll("};\n");
    try methods(w, shapes, v.array(v.get(metadata, "callbacks")));
    try @import("qbe_build_validations.zig").write(w, shapes, v.array(v.get(metadata, "validations")));
    try dispatch.render(w, units, shapes);
    try w.writeAll("static const unsigned char *co_injected;\n");
    try w.writeAll(templates.codec_execute);
    try w.writeByte('\n');
    try w.writeAll(templates.codec_start);
    const supported = try dispatch.lookup(w, units, shapes);
    try dispatch.ending(w, templates.codec_end, supported);
}
fn codec(w: *std.Io.Writer, shapes: shape.Shapes, codecs: []const Value, name: []const u8) shape.Error!void {
    for (codecs) |item| {
        if (!std.mem.eql(u8, v.text(v.get(item, "domain")), name)) continue;
        try w.print("&(const CoCodec){{{d},{d},{d},{d},{d},{d},{d}}}", .{
            try shapes.index(v.text(v.get(item, "wire"))),       v.number(v.get(item, "decode")), v.number(v.get(item, "encode")),
            try shapes.index(v.text(v.get(item, "result"))),     v.number(v.get(item, "ok")),     v.number(v.get(item, "err")),
            try shapes.index(v.text(v.get(item, "error_type"))),
        });
        return;
    }
    try w.writeAll("NULL");
}
fn methods(w: *std.Io.Writer, shapes: shape.Shapes, callbacks: []const Value) shape.Error!void {
    for (callbacks) |callback| {
        const parameters = [_]Value{v.get(callback, "input")};
        try shapes.declaration(w, v.text(v.get(callback, "symbol")), v.text(v.get(callback, "output")), &parameters);
    }
    try w.writeAll("static int co_method(size_t function,void *ctx,const void *input,void *output){(void)ctx;(void)input;(void)output;switch(function){\n");
    for (callbacks) |callback| {
        const output = v.text(v.get(callback, "output"));
        const size = try shapes.size(output);
        try w.print("case {d}:{{", .{v.number(v.get(callback, "index"))});
        if (size <= 4096) {
            try shapes.ctype(w, output);
            try w.writeAll(" result=");
        }
        try w.print("{s}(ctx,", .{v.text(v.get(callback, "symbol"))});
        if (size > 4096) try w.writeAll("output,");
        try methodArgument(w, shapes, v.text(v.get(callback, "input")));
        try w.writeAll(");");
        if (size <= 4096) try w.print("memcpy(output,&result,{d});", .{@max(1, size)});
        try w.writeAll("return !myl_qbe_failed(ctx);}\n");
    }
    try w.writeAll("default:return co_bad(\"InternalError\");}}\n");
}
fn methodArgument(w: *std.Io.Writer, shapes: shape.Shapes, name: []const u8) shape.Error!void {
    if (try shapes.byAddress(name)) {
        try w.writeAll("input");
    } else if (try shapes.scalar(name)) {
        try w.print("co_word(input,{d})", .{try shapes.index(name)});
    } else {
        try w.writeAll("*(");
        try shapes.ctype(w, name);
        try w.writeAll(" *)input");
    }
}
