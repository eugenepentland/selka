//! The edit check's developer tool (EC1, EC2).
//!
//!     edit-check-tool functions FILE.zig            the functions of a source file, as JSON lines
//!     edit-check-tool table BINARY REPO_ROOT        a summary of a binary's counter-to-function table
//!     edit-check-tool changed OLD NEW               which functions differ between two versions of a file ("-" = absent)
//!     edit-check-tool map REPO_ROOT COMMIT OUT RUN_DIR...   build the coverage map from collection runs
const std = @import("std");
const dwarf_functions = @import("dwarf_functions.zig");
const zig_functions = @import("zig_functions.zig");
const coverage_map = @import("coverage_map.zig");

/// Entry point: dispatch on the first argument.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return usage();
    var out_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buffer);
    const out = &stdout.interface;
    defer out.flush() catch {};
    if (std.mem.eql(u8, args[1], "functions") and args.len == 3) {
        try printFunctions(init, arena, args[2], out);
    } else if (std.mem.eql(u8, args[1], "table") and args.len == 4) {
        try printTable(init, arena, args[2], args[3], out);
    } else if (std.mem.eql(u8, args[1], "changed") and args.len == 4) {
        try printChanged(init, arena, args[2], args[3], out);
    } else if (std.mem.eql(u8, args[1], "map") and args.len >= 6) {
        const stats = try coverage_map.build(init.gpa, init.io, .{ .repo = args[2], .commit = args[3], .out = args[4], .runs = args[5..] });
        try out.print("{any}\n", .{stats});
    } else return usage();
}

fn usage() error{Usage} {
    std.debug.print("usage: edit-check-tool functions FILE.zig | table BINARY REPO_ROOT | changed OLD NEW | map REPO_ROOT COMMIT OUT RUN_DIR...\n", .{});
    return error.Usage;
}

fn printFunctions(init: std.process.Init, gpa: std.mem.Allocator, path: []const u8, out: *std.Io.Writer) !void {
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, path, gpa, .limited(64 * 1024 * 1024));
    var file = try zig_functions.parse(gpa, source);
    defer file.deinit(gpa);
    try out.print("{{\"rest\":\"{s}\"}}\n", .{&zig_functions.hex(file.rest)});
    for (file.functions) |function| {
        try out.print("{{\"name\":\"{s}\",\"ordinal\":{d},\"line\":{d},\"end\":{d},\"digest\":\"{s}\"}}\n", .{
            function.name, function.ordinal, function.line, function.end_line, &zig_functions.hex(function.digest),
        });
    }
}

fn printTable(init: std.process.Init, gpa: std.mem.Allocator, binary: []const u8, repo: []const u8, out: *std.Io.Writer) !void {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, binary, gpa, .limited(2 << 30));
    var table = try dwarf_functions.load(gpa, bytes, repo);
    defer table.deinit(gpa);
    var mapped: usize = 0;
    var multi: usize = 0;
    for (0..table.counters()) |index| {
        const keys = table.keysOf(index);
        mapped += @intFromBool(keys.len != 0);
        multi += @intFromBool(keys.len > 1);
    }
    try out.print("counters {d}, with a repo function {d}, with several {d}, keys {d}, files {d}\n", .{ table.counters(), mapped, multi, table.keys.len, table.files.len });
    for (table.keys[0..@min(table.keys.len, 8)]) |key| try out.print("  {s}:{d}\n", .{ table.files[key.file], key.line });
}

/// Print one JSON object: whether anything outside the functions changed, and each function
/// that was added, removed or whose tokens changed between OLD and NEW.
fn printChanged(init: std.process.Init, gpa: std.mem.Allocator, old_path: []const u8, new_path: []const u8, out: *std.Io.Writer) !void {
    const old_source = if (std.mem.eql(u8, old_path, "-")) "" else try std.Io.Dir.cwd().readFileAlloc(init.io, old_path, gpa, .limited(64 * 1024 * 1024));
    const new_source = if (std.mem.eql(u8, new_path, "-")) "" else try std.Io.Dir.cwd().readFileAlloc(init.io, new_path, gpa, .limited(64 * 1024 * 1024));
    var old_file = try zig_functions.parse(gpa, old_source);
    defer old_file.deinit(gpa);
    var new_file = try zig_functions.parse(gpa, new_source);
    defer new_file.deinit(gpa);
    const changes = try zig_functions.compare(gpa, old_file, new_file);
    defer gpa.free(changes.items);
    try out.print("{{\"rest_changed\":{s},\"absent_before\":{s},\"absent_after\":{s},\"functions\":[", .{
        if (changes.rest_changed) "true" else "false",
        if (std.mem.eql(u8, old_path, "-")) "true" else "false",
        if (std.mem.eql(u8, new_path, "-")) "true" else "false",
    });
    for (changes.items, 0..) |change, index| {
        if (index != 0) try out.writeAll(",");
        try out.writeAll("{\"name\":");
        try std.json.Stringify.value(change.name, .{}, out);
        try out.print(",\"ordinal\":{d},\"reason\":\"{t}\",\"test\":{s}}}", .{ change.ordinal, change.reason, if (change.is_test) "true" else "false" });
    }
    try out.writeAll("]}\n");
}
