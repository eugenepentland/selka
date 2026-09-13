//! Generate native JSON codecs and callback adapters from the build manifest.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const host = @import("qbe_build_host.zig");
/// Invalid native JSON schema or output allocation failure.
pub const Error = host.Error;
/// Emit ordinary typed JSON helpers and embed their native runtime support.
pub fn source(allocator: std.mem.Allocator, metadata: std.json.Value, wire_types: std.json.Value) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    const own_types = v.get(metadata, "types");
    const types = v.array(if (own_types == .null) wire_types else own_types);
    try writer.writeAll("#include \"qbe_runtime.h\"\n#include \"native_host.h\"\n#include \"native_owned.h\"\n#include <stdlib.h>\n#include <string.h>\n");
    const byte_descriptor = v.text(v.get(metadata, "byte_descriptor"));
    try writer.print("{s}\nextern const myl_native_type {s};\n#define JSON_BYTE_DESCRIPTOR {s}\n", .{ v.text(v.get(metadata, "schema")), byte_descriptor, byte_descriptor });
    try writer.writeAll(@embedFile("qbe_json_runtime.c"));
    try writer.writeAll("\nstatic const QbeJsonType json_native_types[]={\n");
    for (types) |item| try emitType(writer, types, item);
    try writer.writeAll("};\n");
    try callbacks(allocator, writer, types, v.array(v.get(metadata, "callbacks")));
    for (v.array(v.get(metadata, "operations"))) |operation| {
        const type_index = try host.index(types, v.text(v.get(operation, "type")));
        try writer.print("uint64_t {s}(void *ctx,void *input,int64_t limit,void *output,uint64_t authority){{return json_convert(ctx,", .{v.text(v.get(operation, "symbol"))});
        try writer.print("{d},{d},{d},input,limit,output,authority);}}\n", .{ v.number(v.get(operation, "index")), type_index, @intFromBool(v.boolean(v.get(operation, "decode"))) });
    }
    if (v.boolean(v.get(metadata, "document"))) {
        const word_descriptor = v.text(v.get(metadata, "word_descriptor"));
        try writer.print("extern const myl_native_type {s};\n#define JSON_WORD_DESCRIPTOR {s}\n", .{ word_descriptor, word_descriptor });
        try writer.writeAll(@embedFile("qbe_json_document.c"));
        try writer.writeByte('\n');
    }
    return output.toOwnedSlice();
}
fn emitType(writer: *std.Io.Writer, types: []const std.json.Value, item: std.json.Value) Error!void {
    const kinds = [_][]const u8{ "scalar", "record", "array", "variant", "domain" };
    const kind = for (kinds, 0..) |name, i| {
        if (std.mem.eql(u8, name, v.text(v.get(item, "kind")))) break i;
    } else return error.InvalidManifest;
    const children = v.array(v.get(item, "fields"));
    const count = if (kind == 2) v.number(v.get(item, "count")) else children.len;
    try writer.writeByte('{');
    try v.quote(writer, v.text(v.get(item, "name")));
    try writer.print(",{d},{d},{d},{d},", .{ v.number(v.get(item, "size")), count, v.number(v.get(item, "stride")), kind });
    try host.fields(writer, types, children);
    try writer.writeAll("},\n");
}
fn backing(types: []const std.json.Value, start: usize) Error!usize {
    var current = start;
    for (0..types.len) |_| {
        const item = types[current];
        if (!std.mem.eql(u8, v.text(v.get(item, "kind")), "domain")) return current;
        const children = v.array(v.get(item, "fields"));
        if (children.len != 1) return error.InvalidManifest;
        current = try host.index(types, v.text(v.get(children[0], "type")));
    }
    return error.InvalidManifest;
}
fn scalar(types: []const std.json.Value, i: usize) Error!bool {
    return std.mem.eql(u8, v.text(v.get(types[try backing(types, i)], "kind")), "scalar");
}
fn ctype(writer: *std.Io.Writer, types: []const std.json.Value, i: usize) Error!void {
    if (try scalar(types, i)) try writer.writeAll("uint64_t") else try writer.print("JsonValue{d}", .{i});
}
fn callbacks(allocator: std.mem.Allocator, writer: *std.Io.Writer, types: []const std.json.Value, declarations: []const std.json.Value) Error!void {
    const used = try allocator.alloc(bool, types.len);
    defer allocator.free(used);
    @memset(used, false);
    for (declarations) |callback| {
        const input = try host.index(types, v.text(v.get(callback, "input")));
        const result = try host.index(types, v.text(v.get(callback, "output")));
        for ([_]usize{ input, result }) |i| {
            if (used[i] or try scalar(types, i)) continue;
            try writer.print("typedef struct {{_Alignas({d}) unsigned char bytes[{d}];}} JsonValue{d};\n", .{ v.number(v.get(types[i], "alignment")), @max(1, v.number(v.get(types[i], "size"))), i });
            used[i] = true;
        }
        try callbackDeclaration(writer, types, callback, input, result);
    }
    try writer.writeAll("typedef struct {size_t function;void *input,*output;} JsonCallbackState;\nstatic _Thread_local JsonCallbackState *json_callback;\n");
    try writer.writeAll("static uint64_t json_codec_dispatch(void *ctx){(void)ctx;switch(json_callback->function){\n");
    for (declarations) |callback| try callbackCase(writer, types, callback);
    try writer.writeAll("default:return 0;}}\nstatic int json_invoke(const NativeJsonCall *call,NativeJsonOutput *out){\n");
    try writer.writeAll(" memset(out,0,sizeof *out);size_t input_type=0,output_type=0;\n switch(call->function){\n");
    for (declarations) |callback| {
        try writer.print("case {d}:input_type={d};output_type={d};break;\n", .{ v.number(v.get(callback, "index")), try host.index(types, v.text(v.get(callback, "input"))), try host.index(types, v.text(v.get(callback, "output"))) });
    }
    try writer.writeAll(@embedFile("qbe_json_invoke.inc"));
}
fn callbackDeclaration(writer: *std.Io.Writer, types: []const std.json.Value, callback: std.json.Value, input: usize, result: usize) Error!void {
    const large = v.number(v.get(types[result], "size")) > 4096;
    try writer.writeAll("extern ");
    if (large) try writer.writeAll("uint64_t") else try ctype(writer, types, result);
    try writer.print(" {s}(void *", .{v.text(v.get(callback, "symbol"))});
    if (large) try writer.writeAll(", void *");
    try writer.writeAll(", ");
    if (v.number(v.get(types[input], "size")) > 4096) try writer.writeAll("const void *") else try ctype(writer, types, input);
    try writer.writeAll(");\n");
}
fn callbackCase(writer: *std.Io.Writer, types: []const std.json.Value, callback: std.json.Value) Error!void {
    const input = try host.index(types, v.text(v.get(callback, "input")));
    const result = try host.index(types, v.text(v.get(callback, "output")));
    const size = v.number(v.get(types[result], "size"));
    try writer.print("case {d}:{{", .{v.number(v.get(callback, "index"))});
    if (size <= 4096) {
        try ctype(writer, types, result);
        try writer.writeAll(" value=");
    }
    try writer.print("{s}(ctx,", .{v.text(v.get(callback, "symbol"))});
    if (size > 4096) try writer.writeAll("json_callback->output,");
    try argument(writer, types, input);
    try writer.writeAll(");");
    if (size <= 4096) try writer.print("memcpy(json_callback->output,&value,{d});", .{@max(1, size)});
    try writer.writeAll("return 0;}\n");
}
fn argument(writer: *std.Io.Writer, types: []const std.json.Value, input: usize) Error!void {
    if (v.number(v.get(types[input], "size")) > 4096) {
        try writer.writeAll("json_callback->input");
    } else if (try scalar(types, input)) {
        try writer.print("json_word(json_callback->input,&json_native_types[{d}])", .{try backing(types, input)});
    } else try writer.print("*(JsonValue{d} *)json_callback->input", .{input});
}

test "JSON generator validates ordinary operation identities" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"operations":[{"type":"missing"}]}
    , .{});
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidManifest, source(std.testing.allocator, parsed.value, .null));
}

test "native json generator matches established Python C output" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"types":[{"name":"i64","kind":"scalar","size":8,"alignment":8,"bits":64,"signed":true},{"name":"Box","kind":"record","size":8,"alignment":8,"fields":[{"type":"i64","offset":0}]},{"name":"Big","kind":"array","size":8192,"alignment":8,"count":1024,"stride":8,"fields":[{"type":"i64","offset":0}]},{"name":"Code","kind":"domain","size":8,"alignment":8,"fields":[{"type":"i64","offset":0}]}],"schema":"/*schema*/","byte_descriptor":"bytes","word_descriptor":"words","document":true,"callbacks":[{"input":"Box","output":"Big","symbol":"decode_box","index":1},{"input":"Code","output":"Box","symbol":"encode_box","index":2}],"operations":[{"type":"Box","symbol":"convert_box","index":0,"decode":true}]}
    , .{});
    defer parsed.deinit();
    const result = try source(std.testing.allocator, parsed.value, .null);
    defer std.testing.allocator.free(result);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(result, &digest, .{});
    try std.testing.expectEqualStrings("50c1ba4cc80f6c28b3be2f300605ef1d41a5304c0de370a65b6334e305c4e8f3", &std.fmt.bytesToHex(digest, .lower));
}
