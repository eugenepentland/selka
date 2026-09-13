//! Generate copied-host C metadata without invoking Python.
const std = @import("std");
const v = @import("qbe_build_value.zig");
/// Metadata or allocation failure while constructing a native build artifact.
pub const Error = error{ InvalidManifest, OutOfMemory, WriteFailed };
/// Resolve a canonical type identity to its serialized table position.
pub fn index(types: []const std.json.Value, name: []const u8) Error!usize {
    for (types, 0..) |item, i| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return i;
    return error.InvalidManifest;
}
/// Write the child type indices and byte offsets shared by native C schemas.
pub fn fields(writer: *std.Io.Writer, types: []const std.json.Value, children: []const std.json.Value) Error!void {
    if (children.len == 0) return writer.writeAll("NULL,NULL");
    try writer.writeAll("(const size_t[]){");
    for (children, 0..) |field, i| {
        if (i != 0) try writer.writeByte(',');
        const ty = v.get(field, "type");
        if (ty == .null) try writer.writeAll("SIZE_MAX") else try writer.print("{d}", .{try index(types, v.text(ty))});
    }
    try writer.writeAll("},(const size_t[]){");
    for (children, 0..) |field, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{d}", .{v.number(v.get(field, "offset"))});
    }
    try writer.writeByte('}');
}
/// Embed the copied-host runtime and emit its immutable schemas and entry stubs.
pub fn source(allocator: std.mem.Allocator, metadata: std.json.Value) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    const types = v.array(v.get(metadata, "types"));
    const declarations = v.array(v.get(metadata, "declarations"));
    try writer.writeAll(@embedFile("qbe_host_runtime.c"));
    try writer.writeAll("\nstatic const QbeHostType qbe_host_types[] = {\n");
    for (types, 0..) |item, i| {
        if (try index(types, v.text(v.get(item, "name"))) != i) return error.InvalidManifest;
        try emitType(writer, types, item);
    }
    if (types.len == 0) try writer.writeAll("{0},\n");
    try writer.writeAll("};\nstatic const QbeHostDeclaration qbe_host_declarations[] = {\n");
    for (declarations) |declaration| try emitDeclaration(writer, types, declaration);
    if (declarations.len == 0) try writer.writeAll("{0},\n");
    try writer.print("}};\nstatic const size_t qbe_host_declaration_count={d};\n", .{declarations.len});
    for (declarations, 0..) |declaration, i| {
        try writer.print("void {s}_host(void *ctx,const void *const *arguments,void *output) {{ qbe_host_invoke(ctx,{d},arguments,output); }}\n", .{ v.text(v.get(declaration, "symbol")), i });
    }
    return output.toOwnedSlice();
}
// twin-drift-ok: Host schemas encode unsupported kinds, scalar bit widths and explicit variant counts; JSON schemas use a distinct runtime ABI.
fn emitType(writer: *std.Io.Writer, types: []const std.json.Value, item: std.json.Value) Error!void {
    const kinds = [_][]const u8{ "unsupported", "scalar", "record", "array", "variant", "domain" };
    const kind = for (kinds, 0..) |name, i| {
        if (std.mem.eql(u8, name, v.text(v.get(item, "kind")))) break i;
    } else return error.InvalidManifest;
    const children = v.array(v.get(item, "fields"));
    const count = if (kind == 3 or kind == 4) v.number(v.get(item, "count")) else children.len;
    try writer.writeByte('{');
    try v.quote(writer, v.text(v.get(item, "name")));
    try writer.print(",{d},{d},{d},{d},{d},{d},", .{ v.number(v.get(item, "size")), count, v.number(v.get(item, "stride")), kind, v.number(v.get(item, "bits")), @intFromBool(v.boolean(v.get(item, "signed"))) });
    try fields(writer, types, children);
    try writer.writeAll("},\n");
}
fn emitDeclaration(writer: *std.Io.Writer, types: []const std.json.Value, declaration: std.json.Value) Error!void {
    try writer.writeByte('{');
    try v.quote(writer, v.text(v.get(declaration, "name")));
    try writer.writeByte(',');
    const parameters = v.array(v.get(declaration, "parameters"));
    if (parameters.len == 0) {
        try writer.writeAll("NULL");
    } else {
        try writer.writeAll("(const size_t[]){");
        for (parameters, 0..) |parameter, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("{d}", .{try index(types, v.text(parameter))});
        }
        try writer.writeByte('}');
    }
    try writer.print(",{d},{d},{d}}},\n", .{ parameters.len, try index(types, v.text(v.get(declaration, "result"))), v.number(v.get(declaration, "effects")) });
}

test "host metadata rejects missing and duplicate canonical identities" {
    try std.testing.expectError(error.InvalidManifest, index(&.{}, "missing"));
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"types":[{"name":"i64","kind":"scalar","size":8},{"name":"i64","kind":"scalar","size":8}]}
    , .{});
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidManifest, source(std.testing.allocator, parsed.value));
}
test "empty host metadata embeds preflight and produces valid sentinel tables" {
    const result = try source(std.testing.allocator, .null);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "qbe_host_declaration_count=0;") != null);
}

test "native host generator matches established Python C output" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"types":[{"name":"i64","kind":"scalar","size":8,"alignment":8,"bits":64,"signed":true},{"name":"Box","kind":"record","size":8,"alignment":8,"fields":[{"type":"i64","offset":0}]},{"name":"Big","kind":"array","size":8192,"alignment":8,"count":1024,"stride":8,"fields":[{"type":"i64","offset":0}]},{"name":"Code","kind":"domain","size":8,"alignment":8,"fields":[{"type":"i64","offset":0}]}],"declarations":[{"name":"echo","symbol":"host_echo","parameters":["Box","Code"],"result":"Big","effects":64}]}
    , .{});
    defer parsed.deinit();
    const result = try source(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(result);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(result, &digest, .{});
    try std.testing.expectEqualStrings("582baa6b570c7e23afb10631bdb3b8d86ef2dcba331f083e4bc5a3957b9a49db", &std.fmt.bytesToHex(digest, .lower));
}
