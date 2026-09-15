//! Small C entry and diagnostic adapters emitted by the native build driver.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const host = @import("qbe_build_host.zig");
/// Metadata, allocation, and unsupported executable-entry failures.
pub const Error = host.Error || error{UnsupportedNativeEntry};
/// Emit typed runtime descriptors, host bridges, and source-location tables.
pub fn metadata(allocator: std.mem.Allocator, manifest: std.json.Value) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    const host_source = try host.source(allocator, v.get(manifest, "host"));
    defer allocator.free(host_source);
    try w.print("#include \"qbe_runtime.h\"\n{s}\n{s}\n", .{ v.text(v.get(manifest, "runtime_data")), host_source });
    for (v.array(v.get(manifest, "functions"))) |unit| {
        const symbol = v.text(v.get(unit, "symbol"));
        const locations = v.array(v.get(unit, "locations"));
        try w.print("static const MylQbeLocation {s}_meta_locations[] = {{\n", .{symbol});
        for (locations) |location| {
            try w.writeByte('{');
            try v.quote(w, v.text(v.get(location, "path")));
            try w.print(",{d},{d}}},\n", .{ v.number(v.get(location, "line")), v.number(v.get(location, "column")) });
        }
        if (locations.len == 0) try w.writeAll("{0,0,0},\n");
        try w.print("}};\nconst MylQbeFunction {s}_meta = {{", .{symbol});
        try v.quote(w, v.text(v.get(unit, "name")));
        try w.print(",{s}_meta_locations,{d}}};\n", .{ symbol, locations.len });
    }
    return buffer.toOwnedSlice();
}
/// Emit an executable entry that initializes host calls and grants capabilities.
pub fn entry(allocator: std.mem.Allocator, manifest: std.json.Value, provider: bool) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    const name = v.text(v.get(manifest, "entry"));
    const parameters = v.array(v.get(manifest, "entry_parameters"));
    const argv_element = v.text(v.get(manifest, "entry_argv_element"));
    if (argv_element.len != 0 and parameters.len == 0) return error.UnsupportedNativeEntry;
    const uses_packed = parameters.len > 128;
    try w.writeAll("#include \"qbe_grants.h\"\n#include \"native_providers.h\"\n#include <stdlib.h>\nextern void myl_qbe_host_begin(void *);\n");
    if (argv_element.len != 0) try w.print("extern const myl_native_type {s};\n", .{argv_element});
    try w.print("extern uint64_t {s}(void *", .{name});
    if (uses_packed) try w.writeAll(",uint64_t *") else for (parameters) |_| try w.writeAll(",uint64_t");
    try w.writeAll(");\nstatic uint64_t entry_run(void *ctx) {\n myl_qbe_host_begin(ctx); if(myl_qbe_failed(ctx))return 0;\n");
    if (uses_packed) try w.print("uint64_t *arguments=calloc({d},sizeof *arguments);if(!arguments){{myl_qbe_fail_allocation(ctx);return 0;}}\n", .{parameters.len});
    for (parameters, 0..) |parameter, index| {
        if (uses_packed) try w.print("arguments[{d}]=", .{index}) else try w.print("uint64_t arg{d}=", .{index});
        if (index == 0 and argv_element.len != 0) {
            try w.print("(uint64_t)myl_qbe_argv_list(ctx,&{s});\n", .{argv_element});
        } else {
            try w.print("{s};\n", .{try grant(v.text(parameter))});
        }
    }
    try w.writeAll("if(myl_qbe_failed(ctx)){");
    if (uses_packed) try w.writeAll("free(arguments);");
    try w.print("return 0;}} uint64_t answer={s}(ctx", .{name});
    if (uses_packed) try w.writeAll(",arguments") else for (parameters, 0..) |_, index| try w.print(",arg{d}", .{index});
    try w.writeAll(");");
    if (uses_packed) try w.writeAll("free(arguments);");
    try w.writeAll("return answer;}\nint main(int argc,char **argv){");
    if (provider) try w.writeAll("MylangNativeProviders providers=mylang_native_providers();");
    try w.print("return mylang_qbe_run_grants(entry_run,argc,argv,{s});}}\n", .{if (provider) "&providers" else "NULL"});
    return buffer.toOwnedSlice();
}
fn grant(name: []const u8) Error![]const u8 {
    const names = [_][]const u8{ "allocator", "clock_cap", "random_cap", "environment_cap", "filesystem_cap", "network_cap" };
    const calls = [_][]const u8{ "UINT64_C(1)", "myl_qbe_grant_external(ctx,0)", "myl_qbe_grant_external(ctx,1)", "myl_qbe_grant_external(ctx,2)", "myl_qbe_grant_resource(ctx,0)", "myl_qbe_grant_resource(ctx,1)" };
    for (names, calls) |type_name, call| if (std.mem.eql(u8, name, type_name)) return call;
    return error.UnsupportedNativeEntry;
}

// spec-case: ARGV-1
test "entry metadata rejects ordinary values as implicit capability grants" {
    try std.testing.expectError(error.UnsupportedNativeEntry, grant("i64"));
}
test "entry metadata builds the optional argv list before calling the guest" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":["str_list"],"entry_argv_element":"myl_t_str","functions":[{"symbol":"main_native","name":"main","locations":[]}]}
    , .{});
    defer parsed.deinit();
    const generated = try entry(std.testing.allocator, parsed.value, false);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "myl_qbe_argv_list(ctx,&myl_t_str)") != null);
}
test "entry and location metadata retain provider setup and byte-escaped source paths" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":["clock_cap"],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a\\b.my","line":2,"column":3}]}]}
    , .{});
    defer parsed.deinit();
    const generated = try entry(std.testing.allocator, parsed.value, true);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "myl_qbe_grant_external(ctx,0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "mylang_qbe_run_grants(entry_run,argc,argv,&providers)") != null);
    const locations = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(locations);
    try std.testing.expect(std.mem.indexOf(u8, locations, "main_native_meta_locations,1") != null);
}
