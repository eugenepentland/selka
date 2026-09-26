//! Call compiled invariant clauses at decoded-value boundaries.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const shape = @import("qbe_build_shapes.zig");
const Value = std.json.Value;
/// Declare supported callbacks and emit one dispatcher keyed by native type index.
pub fn write(w: *std.Io.Writer, shapes: shape.Shapes, callbacks: []const Value) shape.Error!void {
    for (callbacks) |callback| {
        if (shape.find(shapes.types, v.text(v.get(callback, "input"))) == null) continue;
        const parameters = [_]Value{v.get(callback, "input")};
        try shapes.declaration(w, v.text(v.get(callback, "symbol")), v.text(v.get(callback, "output")), &parameters);
    }
    const prefix = if (shapes.codecs) "co" else "wire";
    try w.print("static int {s}_validate_one(void *ctx,size_t index,const void *input){{(void)ctx;(void)input;switch(index){{\n", .{prefix});
    for (callbacks) |callback| {
        const input = v.text(v.get(callback, "input"));
        const index = shape.find(shapes.types, input) orelse continue;
        try w.print("case {d}:(void){s}(ctx,", .{ index, v.text(v.get(callback, "symbol")) });
        try argument(w, shapes, input);
        try w.writeAll(");return !myl_qbe_failed(ctx);\n");
    }
    try w.writeAll("default:return 1;}}\n");
}
fn argument(w: *std.Io.Writer, shapes: shape.Shapes, input: []const u8) shape.Error!void {
    if (try shapes.byAddress(input)) return w.writeAll("input");
    if (try shapes.scalar(input)) {
        const index = try shapes.index(input);
        return if (shapes.codecs) w.print("co_word(input,{d})", .{index}) else w.print("wire_word(input,&wire_types[{d}])", .{index});
    }
    try w.writeAll("*(const ");
    try shapes.ctype(w, input);
    try w.writeAll(" *)input");
}
