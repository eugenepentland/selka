//! Public copied-value function dispatch using explicit native ABI byte layouts.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const shape = @import("qbe_build_shapes.zig");
const Value = std.json.Value;
/// Render declarations and native calls for every supported exported function.
pub fn render(w: *std.Io.Writer, units: []const Value, shapes: shape.Shapes) shape.Error!void {
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item != .null and shapes.supported(item)) try shapes.declaration(w, v.text(v.get(unit, "symbol")), v.text(v.get(item, "result")), v.array(v.get(item, v.parameters_key)));
    }
    try w.writeAll(if (shapes.codecs) "static int co_public(void *ctx){(void)ctx;switch(selected){\n" else "static uint64_t wire_dispatch(void *ctx){(void)ctx;switch(selected){\n");
    var index: usize = 0;
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item == .null) continue;
        defer index += 1;
        if (!shapes.supported(item)) continue;
        try w.print("case {d}:{{\n", .{index});
        try call(w, shapes, unit, item);
        try w.writeAll(if (shapes.codecs) "return !myl_qbe_failed(ctx);}\n" else "return 0;}\n");
    }
    try w.writeAll(if (shapes.codecs) "default:return co_bad(\"InternalError\");}}\n" else "default:return 0;}}\n");
}
fn call(w: *std.Io.Writer, shapes: shape.Shapes, unit: Value, item: Value) shape.Error!void {
    const parameters = v.array(v.get(item, v.parameters_key));
    const usesVector = try shapes.usesVector(parameters);
    const result = v.text(v.get(item, "result"));
    const size = try shapes.size(result);
    const prefix = if (shapes.codecs) "co" else "wire";
    if (usesVector) {
        try w.print("uint64_t *packet=malloc({d}*sizeof *packet);if(!packet){{", .{parameters.len});
        try w.writeAll(if (shapes.codecs) "return co_bad(\"OutOfMemory\");}\n" else "myl_qbe_fail(ctx,\"OutOfMemory\");return 0;}\n");
        for (parameters, 0..) |parameter, i| {
            try w.print("packet[{d}]=", .{i});
            try shapes.argument(w, v.text(parameter), i, true);
            try w.writeAll(";\n");
        }
    }
    if (size <= 4096) {
        try shapes.ctype(w, result);
        try w.writeAll(" result=");
    }
    try w.print("{s}(ctx", .{v.text(v.get(unit, "symbol"))});
    if (size > 4096) try w.print(",{s}_return", .{prefix});
    if (usesVector) {
        try w.writeAll(",packet");
    } else for (parameters, 0..) |parameter, i| {
        try w.writeByte(',');
        try shapes.argument(w, v.text(parameter), i, false);
    }
    try w.writeAll(");\n");
    if (usesVector) try w.writeAll("free(packet);\n");
    if (size <= 4096) try w.print("memcpy({s}_return,&result,{d});\n", .{ prefix, @max(1, size) });
}
/// Emit exact-name public signature validation and native type index selection.
pub fn lookup(w: *std.Io.Writer, units: []const Value, shapes: shape.Shapes) shape.Error!bool {
    var index: usize = 0;
    var supported = false;
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item == .null) continue;
        defer index += 1;
        try w.writeAll("if(!strcmp(name,");
        try v.quote(w, v.text(v.get(item, "name")));
        try w.writeAll(")){\n");
        if (!shapes.supported(item)) {
            try w.print("host_error({s},\"UnsupportedSignature\");goto done;}}\n", .{if (shapes.codecs) "execution" else "&out->execution"});
            continue;
        }
        supported = true;
        const parameters = v.array(v.get(item, v.parameters_key));
        if (parameters.len != 0) {
            try w.writeAll("static const size_t parameters[]={");
            for (parameters, 0..) |parameter, i| {
                if (i != 0) try w.writeByte(',');
                try w.print("{d}", .{try shapes.index(v.text(parameter))});
            }
            try w.writeAll("};\n");
            if (shapes.codecs) {
                const names = v.array(v.get(item, "parameter_names"));
                try w.writeAll("static const unsigned char injected[]={");
                for (parameters, 0..) |parameter, i| {
                    if (i != 0) try w.writeByte(',');
                    const name = if (i < names.len) v.text(names[i]) else "";
                    const sentinel = injectedSentinel(v.text(parameter), name);
                    try w.print("{d}", .{sentinel});
                }
                try w.writeAll("};\n");
            }
        }
        const prefix = if (shapes.codecs) "co_" else "";
        const injected = if (!shapes.codecs) "" else if (parameters.len == 0) "co_injected=NULL;" else "co_injected=injected;";
        try w.print("selected={d};{s}result_type={d};{s}argument_count={d};{s}parameter_types={s};{s}goto invoke;}}\n", .{
            index, prefix, try shapes.index(v.text(v.get(item, "result"))), prefix, parameters.len, prefix, if (parameters.len == 0) "NULL" else "parameters", injected,
        });
    }
    return supported;
}
/// The capability types, in capability-index order, the adapter replaces with a
/// deterministic stand-in built from one argument node (TEST-CAPS-3).
const stand_in_types = [_][]const u8{ "clock_cap", "random_cap", "filesystem_cap", "network_cap", "environment_cap" };
/// The adapter's injection code for one parameter: 0 reads a copied value, 1
/// and 2 are standard output and error, and 3 plus a capability index builds
/// that capability's stand-in from the argument node's bits.
fn injectedSentinel(type_name: []const u8, parameter_name: []const u8) u8 {
    if (std.mem.eql(u8, type_name, "stream_cap")) return if (std.mem.eql(u8, parameter_name, "err")) 2 else 1;
    for (stand_in_types, 0..) |candidate, index| if (std.mem.eql(u8, type_name, candidate)) return @intCast(3 + index);
    return 0;
}
/// Insert a reachable invocation label after the unknown-function failure path.
pub fn ending(w: *std.Io.Writer, template: []const u8, supported: bool) shape.Error!void {
    const end = std.mem.indexOfScalar(u8, template, '\n') orelse return error.InvalidManifest;
    try w.writeAll(template[0 .. end + 1]);
    if (supported) try w.writeAll("invoke:\n");
    try w.writeAll(template[end + 1 ..]);
    try w.writeByte('\n');
}
/// Bound static argument pointer tables to the largest supported signature.
pub fn maximum(units: []const Value, shapes: shape.Shapes) usize {
    var count: usize = 1;
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item != .null and shapes.supported(item)) count = @max(count, v.array(v.get(item, v.parameters_key)).len);
    }
    return count;
}
