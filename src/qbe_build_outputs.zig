//! Small C entry and diagnostic adapters emitted by the native build driver.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const host = @import("qbe_build_host.zig");
/// One packed-argument cleanup shared by every early grant exit.
const free_arguments = "free(arguments);";
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
        // One message per pc, `""` when the instruction is not an assertion. Pad
        // to the location count so the runtime's `position < count` check always
        // names a real entry, even for a hand-written manifest.
        const messages = v.array(v.get(unit, "messages"));
        try w.print("}};\nstatic const char *{s}_meta_messages[] = {{\n", .{symbol});
        for (0..locations.len) |pc| {
            try v.quote(w, if (pc < messages.len) v.text(messages[pc]) else "");
            try w.writeAll(",\n");
        }
        if (locations.len == 0) try w.writeAll("\"\",\n");
        try w.writeAll("};\n");
        try w.print("const MylQbeFunction {s}_meta = {{", .{symbol});
        try v.quote(w, v.text(v.get(unit, "name")));
        try w.print(",{s}_meta_locations,{d},{s}_meta_messages}};\n", .{ symbol, locations.len, symbol });
    }
    return buffer.toOwnedSlice();
}
/// Emit an executable entry that initializes host calls and grants capabilities.
pub fn entry(allocator: std.mem.Allocator, manifest: std.json.Value, provider: bool) Error![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    errdefer buffer.deinit();
    const w = &buffer.writer;
    const name = v.text(v.get(manifest, "entry"));
    if (name.len == 0) return error.UnsupportedNativeEntry;
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
        try w.writeAll("if(myl_qbe_failed(ctx)){");
        if (uses_packed) try w.writeAll(free_arguments);
        try w.writeAll("return 0;}\n");
    }
    try w.writeAll("if(myl_qbe_failed(ctx)){");
    if (uses_packed) try w.writeAll(free_arguments);
    try w.print("return 0;}} uint64_t answer={s}(ctx", .{name});
    if (uses_packed) try w.writeAll(",arguments") else for (parameters, 0..) |_, index| try w.print(",arg{d}", .{index});
    try w.writeAll(");");
    if (uses_packed) try w.writeAll(free_arguments);
    try w.writeAll("return answer;}\nint main(int argc,char **argv){");
    if (provider) try w.writeAll("MylangNativeProviders providers=mylang_native_providers();");
    try w.print("return mylang_qbe_run_grants(entry_run,argc,argv,{s});}}\n", .{if (provider) "&providers" else "NULL"});
    return buffer.toOwnedSlice();
}
fn grant(name: []const u8) Error![]const u8 {
    const names = [_][]const u8{ "allocator", "clock_cap", "random_cap", "environment_cap", "filesystem_cap", "network_cap", "host_cap" };
    const calls = [_][]const u8{
        "UINT64_C(1)",
        "myl_qbe_grant_external_checked(ctx,0,\"--allow-clock\")",
        "myl_qbe_grant_external_checked(ctx,1,\"--allow-random\")",
        "myl_qbe_grant_external_checked(ctx,2,\"--allow-env\")",
        "myl_qbe_grant_resource_checked(ctx,0,\"--allow-read=DIR\")",
        "myl_qbe_grant_resource_checked(ctx,1,\"--allow-endpoint\")",
        "myl_qbe_grant_host_checked(ctx,\"--allow-host\")",
    };
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
    try std.testing.expect(std.mem.indexOf(u8, generated, "myl_qbe_grant_external_checked(ctx,0,\"--allow-clock\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "mylang_qbe_run_grants(entry_run,argc,argv,&providers)") != null);
    const locations = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(locations);
    try std.testing.expect(std.mem.indexOf(u8, locations, "main_native_meta_locations,1") != null);
}
// spec-case: NATIVE-TEST-10
test "assert messages are emitted once per pc and linked into the function metadata" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":1,"column":1},{"path":"a.my","line":4,"column":5}],"messages":["","x should be two"]}]}
    , .{});
    defer parsed.deinit();
    const generated = try metadata(std.testing.allocator, parsed.value);
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "static const char *main_native_meta_messages[] = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "\n\"\",\n\"x should be two\",\n};\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ",main_native_meta_locations,2,main_native_meta_messages};") != null);
    const without = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"entry":"main_native","entry_parameters":[],"functions":[{"symbol":"main_native","name":"main","locations":[{"path":"a.my","line":1,"column":1}]}]}
    , .{});
    defer without.deinit();
    const padded = try metadata(std.testing.allocator, without.value);
    defer std.testing.allocator.free(padded);
    try std.testing.expect(std.mem.indexOf(u8, padded, "static const char *main_native_meta_messages[] = {\n\"\",\n};\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, padded, ",main_native_meta_locations,1,main_native_meta_messages};") != null);
}
