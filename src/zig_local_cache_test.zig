//! The Zig local cache a test process runs with (NATIVE-ZIG-CACHE-4): `zig
//! build` hands every test step a private `ZIG_LOCAL_CACHE_DIR`, so a test
//! that runs `zig cc` itself leaves nothing in the project's `.zig-cache`.
const std = @import("std");
const t = std.testing;

/// Whether the local cache at `directory` holds Zig's copy of an object named
/// `name`, which it keeps at `o/<digest>/<name>`.
fn cachedObject(directory: []const u8, name: []const u8) !bool {
    const objects = try std.fs.path.join(t.allocator, &.{ directory, "o" });
    defer t.allocator.free(objects);
    var dir = try std.Io.Dir.cwd().openDir(t.io, objects, .{ .iterate = true });
    defer dir.close(t.io);
    var entries = dir.iterate();
    while (try entries.next(t.io)) |entry| {
        if (entry.kind != .directory) continue;
        const path = try std.fs.path.join(t.allocator, &.{ entry.name, name });
        defer t.allocator.free(path);
        if (dir.access(t.io, path, .{})) |_| return true else |_| {}
    }
    return false;
}

// spec: NATIVE-ZIG-CACHE-4
test "a test's own zig cc keeps its cache in the run's private scratch" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scratch = t.environ.getPosix("ZIG_LOCAL_CACHE_DIR") orelse "";
    const project = try std.Io.Dir.cwd().realPathFileAlloc(t.io, ".zig-cache", a);
    try t.expect(std.fs.path.isAbsolute(scratch));
    try t.expect(!std.mem.startsWith(u8, scratch, project));
    // A testing tmpDir lives under the project's `.zig-cache/tmp`, so without
    // the variable Zig would find this project's `build.zig` above it and
    // cache the object there.
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "zig_cache_probe.c", .data = "int zig_cache_probe(void) { return 4; }\n" });
    const result = try std.process.run(a, t.io, .{
        .argv = &.{ @import("native_test_options").zig_path, "cc", "-c", "zig_cache_probe.c", "-o", "zig_cache_probe.o" },
        .cwd = .{ .dir = temporary.dir },
    });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try t.expect(try cachedObject(scratch, "zig_cache_probe.o"));
}
