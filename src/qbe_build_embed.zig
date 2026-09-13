//! Native library embedding adapter generation without a scripting runtime.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const templates = @import("qbe_build_templates.zig");
const dispatch = @import("qbe_build_dispatch.zig");
const Value = std.json.Value;
/// Build allocation, manifest and output errors.
pub const Error = error{ OutOfMemory, InvalidManifest, WriteFailed };
/// Generate all scalar, ordinary copied-value and codec public library entry points.
pub fn libraryWrapper(allocator: std.mem.Allocator, manifest: Value) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const w = &output.writer;
    const units = v.array(v.get(manifest, "functions"));
    try validate(units, v.get(manifest, "schema"));
    const entry = v.text(v.get(manifest, "entry"));
    const parameters = v.array(v.get(manifest, "entry_parameters"));
    try w.writeAll(templates.embed_prelude);
    try w.writeByte('\n');
    try schema(w, v.get(manifest, "schema"));
    try declaration(w, entry, parameters.len);
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item != .null and supported(item)) try declaration(w, v.text(v.get(unit, "symbol")), v.array(v.get(item, v.parameters_key)).len);
    }
    try entryRun(w, entry, parameters);
    try scalarDispatch(w, units);
    try w.writeAll(templates.embed_run);
    try w.writeByte('\n');
    try w.writeAll(templates.embed_start);
    const any_supported = try lookup(w, units);
    try dispatch.ending(w, templates.embed_end, any_supported);
    const wire = v.get(manifest, "wire_types");
    if (wire != .null) try @import("qbe_build_wire.zig").write(w, units, v.array(wire));
    const codecs = v.get(manifest, "codecs");
    if (codecs != .null) try @import("qbe_build_codecs.zig").write(w, units, codecs, v.array(wire));
    return output.toOwnedSlice();
}
fn validate(units: []const Value, schema_value: Value) Error!void {
    if (schema_value != .null and schema_value != .string) return error.InvalidManifest;
    for (units, 0..) |unit, i| {
        const item = v.get(unit, "export");
        if (item == .null) continue;
        const name = v.get(item, "name");
        if (name != .string or v.get(item, "result") != .string) return error.InvalidManifest;
        const parameters = v.get(item, v.parameters_key);
        if (parameters != .array) return error.InvalidManifest;
        for (v.array(parameters)) |parameter| if (parameter != .string) return error.InvalidManifest;
        for (units[0..i]) |previous| {
            const old = v.get(previous, "export");
            if (old != .null and std.mem.eql(u8, v.text(v.get(old, "name")), v.text(name))) return error.InvalidManifest;
        }
    }
}

fn schema(w: *std.Io.Writer, value: Value) Error!void {
    try w.writeAll("const char *mylang_native_schema_json_v1(void){return ");
    if (value == .null) try w.writeAll("NULL") else try v.quote(w, v.text(value));
    try w.writeAll(";}\nconst char *mylang_native_schema_sha256_v1(void){return ");
    if (value == .null) {
        try w.writeAll("NULL");
    } else {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(v.text(value), &digest, .{});
        try v.quote(w, &std.fmt.bytesToHex(digest, .lower));
    }
    try w.writeAll(";}\n");
}
fn declaration(w: *std.Io.Writer, symbol: []const u8, count: usize) Error!void {
    if (symbol.len == 0) return error.InvalidManifest;
    for (symbol, 0..) |byte, i| {
        if (std.ascii.isAlphabetic(byte) or byte == '_') continue;
        if (i == 0 or !std.ascii.isDigit(byte)) return error.InvalidManifest;
    }
    try w.print("extern uint64_t {s}(void *", .{symbol});
    if (count > 128) try w.writeAll(",const uint64_t *") else for (0..count) |_| try w.writeAll(",uint64_t");
    try w.writeAll(");\n");
}
fn entryRun(w: *std.Io.Writer, entry: []const u8, parameters: []const Value) Error!void {
    try w.writeAll("static uint64_t entry_run(void *ctx){\n");
    for (parameters, 0..) |parameter, i| {
        const name = v.text(parameter);
        try w.print("uint64_t arg{d}=", .{i});
        if (std.mem.eql(u8, name, "allocator")) {
            try w.writeAll("1;\n");
        } else {
            const kind: u8 = if (std.mem.eql(u8, name, "clock_cap")) 0 else if (std.mem.eql(u8, name, "random_cap")) 1 else if (std.mem.eql(u8, name, "environment_cap")) 2 else return error.InvalidManifest;
            try w.print("myl_qbe_grant_external(ctx,{d});\n", .{kind});
        }
    }
    if (parameters.len != 0) try w.writeAll("if(myl_qbe_failed(ctx))return 0;\n");
    if (parameters.len > 128) {
        try packet(w, parameters.len);
        for (parameters, 0..) |_, i| try w.print("packet[{d}]=arg{d};\n", .{ i, i });
        try w.print("uint64_t result={s}(ctx,packet);free(packet);return result;}}\n", .{entry});
    } else {
        try w.print("return {s}(ctx", .{entry});
        for (parameters, 0..) |_, i| try w.print(",arg{d}", .{i});
        try w.writeAll(");}\n");
    }
}
fn scalar(name: []const u8) bool {
    for ([_][]const u8{ "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |kind| if (std.mem.eql(u8, name, kind)) return true;
    return false;
}
fn supported(item: Value) bool {
    const flag = v.get(item, "scalar");
    if (flag != .null and !v.boolean(flag)) return false;
    if (!scalar(v.text(v.get(item, "result")))) return false;
    for (v.array(v.get(item, v.parameters_key))) |parameter| if (!scalar(v.text(parameter))) return false;
    return true;
}
fn packet(w: *std.Io.Writer, count: usize) Error!void {
    try w.print("uint64_t *packet=malloc({d}*sizeof *packet);if(!packet){{myl_qbe_fail(ctx,\"OutOfMemory\");return 0;}}\n", .{count});
}
fn scalarDispatch(w: *std.Io.Writer, units: []const Value) Error!void {
    try w.writeAll("static uint64_t dispatch(void *ctx){(void)ctx;switch(selected){\n");
    var index: usize = 0;
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item == .null) continue;
        defer index += 1;
        if (!supported(item)) continue;
        const parameters = v.array(v.get(item, v.parameters_key));
        const symbol = v.text(v.get(unit, "symbol"));
        try w.print("case {d}:{{", .{index});
        if (parameters.len > 128) {
            try packet(w, parameters.len);
            try w.print("for(size_t i=0;i<{d};++i)packet[i]=inputs[i].bits;uint64_t result={s}(ctx,packet);free(packet);return result;}}\n", .{ parameters.len, symbol });
        } else {
            try w.print("return {s}(ctx", .{symbol});
            for (parameters, 0..) |_, i| try w.print(",inputs[{d}].bits", .{i});
            try w.writeAll(");}\n");
        }
    }
    try w.writeAll("default:return 0;}}\n");
}
fn lookup(w: *std.Io.Writer, units: []const Value) Error!bool {
    var index: usize = 0;
    var any_supported = false;
    for (units) |unit| {
        const item = v.get(unit, "export");
        if (item == .null) continue;
        defer index += 1;
        try w.writeAll("if(!strcmp(name,");
        try v.quote(w, v.text(v.get(item, "name")));
        try w.writeAll(")){\n");
        if (!supported(item)) {
            try w.writeAll("host_error(&out->execution,\"UnsupportedSignature\");goto done;}\n");
            continue;
        }
        any_supported = true;
        const parameters = v.array(v.get(item, v.parameters_key));
        try w.print("if(count!={d}", .{parameters.len});
        for (parameters, 0..) |parameter, i| {
            try w.print("||!valid_scalar(arguments[{d}],", .{i});
            try v.quote(w, v.text(parameter));
            try w.writeByte(')');
        }
        try w.writeAll("){host_error(&out->execution,\"InvalidArgument\");goto done;}\n");
        try w.print("selected={d};return_type=", .{index});
        try v.quote(w, v.text(v.get(item, "result")));
        try w.writeAll(";goto invoke;}\n");
    }
    return any_supported;
}

test "library adapter preserves hidden exports, exact schema and empty wire entry points" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(Value, allocator,
        \\{"entry":"entry","entry_parameters":[],"functions":[{"symbol":"entry","export":null},{"symbol":"add","export":{"name":"module::add","scalar":true,"parameters":["i64"],"result":"i64"}}],"schema":"{}","wire_types":[{"name":"i64","kind":"scalar","size":8,"alignment":8}],"codecs":{"types":[{"name":"i64","kind":"scalar","size":8,"alignment":8}],"codecs":[],"callbacks":[]}}
    , .{});
    defer parsed.deinit();
    const source = try libraryWrapper(allocator, parsed.value);
    defer allocator.free(source);
    try std.testing.expect(std.mem.indexOf(u8, source, "case 0:{return add(ctx,inputs[0].bits)") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "mylang_native_call_values_v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "mylang_native_call_codecs_v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a") != null);
    try std.testing.expectError(error.InvalidManifest, libraryWrapper(allocator, .null));
}
