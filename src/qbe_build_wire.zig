//! Generate the ordinary native copied-value embedding adapter.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const shapes_module = @import("qbe_build_shapes.zig");
const dispatch = @import("qbe_build_dispatch.zig");
const templates = @import("qbe_build_templates.zig");
/// Write ordinary wire schemas and directly callable native function adapters.
pub fn write(w: *std.Io.Writer, units: []const std.json.Value, types: []const std.json.Value, validations: []const std.json.Value) shapes_module.Error!void {
    const shapes: shapes_module.Shapes = .{ .types = types };
    try w.print("#define QBE_WIRE_ARGUMENTS {d}\n", .{dispatch.maximum(units, shapes)});
    try w.writeAll(@embedFile("qbe_wire_runtime.c"));
    try w.writeByte('\n');
    try shapes.typedefs(w);
    try w.writeAll("static const QbeWireType wire_types[]={\n");
    for (types) |item| {
        try shapes.schema(w, item);
        try w.writeAll("},\n");
    }
    if (types.len == 0) try w.writeAll("{0},\n");
    try w.writeAll("};\n");
    try @import("qbe_build_validations.zig").write(w, shapes, validations);
    try dispatch.render(w, units, shapes);
    try w.writeAll(templates.wire_start);
    const supported = try dispatch.lookup(w, units, shapes);
    try dispatch.ending(w, templates.wire_end, supported);
}
