//! Private native unit files live through linking and are removed with staging.
const std = @import("std");
const driver = @import("driver.zig");
const io = std.testing.io;
const tool_source =
    \\#!/bin/sh
    \\out=''
    \\compile=0
    \\for argument in "$@"; do
    \\  if [ "$argument" = '-c' ]; then compile=1; fi
    \\done
    \\while [ "$#" -gt 0 ]; do
    \\  case "$1" in
    \\    -o) shift; out=$1 ;;
    \\    *.o) if [ "$compile" = 0 ]; then test -f "$1" || exit 9; fi ;;
    \\  esac
    \\  shift
    \\done
    \\if [ "$compile" = 1 ]; then printf object > "$out"; exit 0; fi
    \\if [ -f "$CASE_ROOT/fail" ]; then exit 7; fi
    \\printf linked > "$out"
;

fn clean(directory: std.Io.Dir) !void {
    var cache = try directory.openDir(io, "cache", .{ .iterate = true });
    defer cache.close(io);
    var entries = cache.iterate();
    while (try entries.next(io)) |entry| try std.testing.expect(!std.mem.startsWith(u8, entry.name, "native-link-"));
}

// spec-case: NEW-CORE-DRIVER-1
test "A01 uncached native multiunit objects survive link and clean after success and failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "zig", .data = tool_source });
    try temporary.dir.setFilePermissions(io, "zig", .executable_file, .{});
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("CASE_ROOT", root);
    const request: driver.Request = .{
        .zig = try std.fs.path.join(a, &.{ root, "zig" }),
        .work = try std.fs.path.join(a, &.{ root, "cache" }),
        .output = try std.fs.path.join(a, &.{ root, "output" }),
        .links = &.{},
        .units = &.{
            .{ .name = "entry", .source_path = "entry.my", .kind = .entry, .llvm = "entry text", .dependencies = .{} },
            .{ .name = "module", .source_path = "module.my", .kind = .module, .llvm = "module text", .dependencies = .{} },
        },
    };
    var log: std.ArrayList(u8) = .empty;
    for (0..2) |_| {
        const outcome = try driver.link(a, io, &environment, request, &log);
        try std.testing.expect(!outcome.tool.cacheable);
        try std.testing.expectEqual(@as(u32, 2), outcome.counts.compiled);
        try std.testing.expectEqual(@as(u32, 0), outcome.counts.reused);
        try std.testing.expectEqualStrings("linked", try temporary.dir.readFileAlloc(io, "output", a, .limited(64)));
        try clean(temporary.dir);
    }
    try temporary.dir.writeFile(io, .{ .sub_path = "fail", .data = "" });
    try std.testing.expectError(error.ToolFailed, driver.link(a, io, &environment, request, &log));
    try clean(temporary.dir);
}
