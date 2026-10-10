//! Native foreign headers and unproved tools cannot reuse Zig cache verdicts.
const std = @import("std");
const driver = @import("driver.zig");
const tools = @import("core_test_options");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();
const diagnostic = std.debug.print;

fn cleanCache(cache: []const u8) !void {
    var directory = try cwd.openDir(io, cache, .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, "native-link-"));
        try std.testing.expect(!std.mem.startsWith(u8, entry.name, "unproved-tool-"));
    }
}

fn buildHeader(a: std.mem.Allocator, root: []const u8, environment: *const std.process.Environ.Map, release: bool, expected: u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    const output = try std.fs.path.join(a, &.{ root, "guest" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try argv.appendSlice(a, &.{ tools.core_path, "build", try std.fs.path.join(a, &.{ root, "app.my" }), "-o", output, "--link", try std.fs.path.join(a, &.{ root, "value.c" }), "--cache-dir", cache });
    if (release) try argv.append(a, "--release");
    const built = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = environment });
    if (built.term != .exited or built.term.exited != 0) diagnostic("foreign header build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    try std.testing.expectEqualStrings("", built.stderr);
    const native = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = environment });
    try std.testing.expect(native.term == .exited and native.term.exited == expected);
    try std.testing.expectEqualStrings("", native.stdout);
    try std.testing.expectEqualStrings("", native.stderr);
    try cleanCache(cache);
}

fn headerEdit(a: std.mem.Allocator, release: bool) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const global = try std.fs.path.join(a, &.{ root, "shared-global" });
    try cwd.createDirPath(io, global);
    const sentinel = try std.fs.path.join(a, &.{ global, "keep" });
    try cwd.writeFile(io, .{ .sub_path = sentinel, .data = "caller-owned" });
    try environment.put("ZIG_GLOBAL_CACHE_DIR", global);
    try temporary.dir.writeFile(io, .{ .sub_path = "app.my", .data = "extern func linked_value(host: Host) -> i32 effects(host)\nfunc main(host: Host) -> int:\n    return int(linked_value(host))\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "value.c", .data = "#include \"value.h\"\nint linked_value(void) { return VALUE; }\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 7\n" });
    const before = try temporary.dir.statFile(io, "value.h", .{});
    try buildHeader(a, root, &environment, release, 7);
    try temporary.dir.writeFile(io, .{ .sub_path = "value.h", .data = "#define VALUE 8\n" });
    try temporary.dir.setTimestamps(io, "value.h", .{ .modify_timestamp = .{ .new = before.mtime } });
    const after = try temporary.dir.statFile(io, "value.h", .{});
    try std.testing.expectEqual(before.size, after.size);
    try std.testing.expectEqual(before.mtime.nanoseconds, after.mtime.nanoseconds);
    try std.testing.expect(before.ctime.nanoseconds != after.ctime.nanoseconds);
    try buildHeader(a, root, &environment, release, 8);
    try std.testing.expectEqualStrings("caller-owned", try cwd.readFileAlloc(io, sentinel, a, .limited(64)));
}

// spec-case: NEW-CORE-DRIVER-1
test "linkNative observes same-size foreign header edits with restored mtime in actual debug and release Core builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try headerEdit(arena.allocator(), false);
    try headerEdit(arena.allocator(), true);
}

const unproved_tool =
    \\#!/bin/sh
    \\out=''
    \\compile=0
    \\while [ "$#" -gt 0 ]; do
    \\  if [ "$1" = '-c' ]; then compile=1; fi
    \\  if [ "$1" = '-o' ]; then shift; out=$1; fi
    \\  shift
    \\done
    \\if [ "$compile" = 1 ]; then printf object > "$out"; exit 0; fi
    \\printf '%s\n%s\n' "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR" >> "$CASE_ROOT/paths"
    \\if [ -f "$CASE_ROOT/fail" ]; then exit 7; fi
    \\mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
    \\if [ ! -f "$ZIG_LOCAL_CACHE_DIR/value" ]; then cat "$CASE_ROOT/value" > "$ZIG_LOCAL_CACHE_DIR/value"; fi
    \\cat "$ZIG_LOCAL_CACHE_DIR/value" > "$out"
    \\
;

fn cleanRecordedCaches(a: std.mem.Allocator, directory: std.Io.Dir) !void {
    const paths = try directory.readFileAlloc(io, "paths", a, .limited(4096));
    var lines = std.mem.tokenizeScalar(u8, paths, '\n');
    var count: usize = 0;
    while (lines.next()) |path| {
        try std.testing.expect(std.mem.indexOf(u8, path, "/native-link-") != null);
        try std.testing.expectError(error.FileNotFound, cwd.access(io, path, .{}));
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), count);
}

// spec-case: NEW-CORE-DRIVER-1
test "linkNative refuses unproved tool native reuse and cleans private caches after ToolFailed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "zig", .data = unproved_tool });
    try temporary.dir.setFilePermissions(io, "zig", .executable_file, .{});
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("CASE_ROOT", root);
    try environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "caller-global" }));
    const original_global = environment.get("ZIG_GLOBAL_CACHE_DIR").?;
    const request: driver.Request = .{
        .zig = try std.fs.path.join(a, &.{ root, "zig" }),
        .work = try std.fs.path.join(a, &.{ root, "cache" }),
        .output = try std.fs.path.join(a, &.{ root, "output" }),
        .mode = .debug,
        .links = &.{},
    };
    var log: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "7", "8" }) |value| {
        try temporary.dir.writeFile(io, .{ .sub_path = "value", .data = value });
        _ = try driver.link(a, io, &environment, request, &log);
        try std.testing.expectEqualStrings(value, try cwd.readFileAlloc(io, request.output, a, .limited(64)));
        try cleanCache(request.work);
    }
    try temporary.dir.writeFile(io, .{ .sub_path = "fail", .data = "" });
    try std.testing.expectError(error.ToolFailed, driver.link(a, io, &environment, request, &log));
    try cleanCache(request.work);
    try std.testing.expectEqualStrings(original_global, environment.get("ZIG_GLOBAL_CACHE_DIR").?);
    try cleanRecordedCaches(a, temporary.dir);
}

const payload_module =
    \\public enum Packet:
    \\    data(value: i64)
    \\    none
;
const payload_main =
    \\import left
    \\func main(out: Stream) -> int:
    \\    mut result = left.Packet.data(value=42)
    \\    out.print(result)
    \\    match result:
    \\        case left.Packet.data(value=n):
    \\            return int(n)
    \\        case _:
    \\            return 1
;

fn payloadPrint(a: std.mem.Allocator, root: []const u8, release: bool) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    const output = try std.fs.path.join(a, &.{ root, "guest" });
    try argv.appendSlice(a, &.{ tools.core_path, "build", try std.fs.path.join(a, &.{ root, "main.my" }), "-o", output, "--cache-dir", try std.fs.path.join(a, &.{ root, "cache" }) });
    if (release) try argv.append(a, "--release");
    const built = try std.process.run(a, io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) diagnostic("payload print build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const native = try std.process.run(a, io, .{ .argv = &.{output} });
    if (native.term != .exited or native.term.exited != 42) diagnostic("payload print run: {s}{s}\n", .{ native.stdout, native.stderr });
    try std.testing.expect(native.term == .exited and native.term.exited == 42);
    try std.testing.expectEqualStrings("Packet.data(value=42)\n", native.stdout);
    try std.testing.expectEqualStrings("", native.stderr);
}

// spec-case: NOMINAL-INSTANCE-1
test "imported fielded enum preserves printed constructor across native cache relocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "left.my", .data = payload_module });
    try temporary.dir.writeFile(io, .{ .sub_path = "main.my", .data = payload_main });
    try payloadPrint(a, root, false);
    try payloadPrint(a, root, false);
    try temporary.dir.writeFile(io, .{ .sub_path = "main.my", .data = "\n" ++ payload_main });
    try payloadPrint(a, root, false);
    try payloadPrint(a, root, true);
}
