//! The Zig local cache a test's `zig cc` runs with (NATIVE-ZIG-CACHE-4). `zig build` hands every
//! test step a private `ZIG_LOCAL_CACHE_DIR` (the run's scratch), so a test that runs `zig cc`
//! itself leaves nothing in the project's `.zig-cache`. The probe gives its `zig cc` a cache of
//! its own instead of relying on that inherited directory: a sibling process may move the inherited
//! cache aside mid-run (a worktree's cache trim does), and then `zig cc` exits 1 and the probe
//! fails. The inherited value is still checked: it must be absolute and outside the project's cache.
const std = @import("std");
const t = std.testing;

/// Whether the local cache at `directory` holds Zig's copy of an object named
/// `name`, which it keeps at `o/<digest>/<name>`. A cache with no `o` holds none.
fn cachedObject(directory: []const u8, name: []const u8) !bool {
    const objects = try std.fs.path.join(t.allocator, &.{ directory, "o" });
    defer t.allocator.free(objects);
    var dir = std.Io.Dir.cwd().openDir(t.io, objects, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
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

/// A fresh cache directory for the probe: a random name under `$TMPDIR` (or `/tmp`), outside the
/// project's `.zig-cache`, so no other process can share or move it.
fn privateCache(a: std.mem.Allocator) ![]const u8 {
    const base = try std.Io.Dir.cwd().realPathFileAlloc(t.io, t.environ.getPosix("TMPDIR") orelse "/tmp", a);
    var random: [8]u8 = undefined;
    t.io.random(&random);
    const hex = std.fmt.bytesToHex(random, .lower);
    const path = try std.fmt.allocPrint(a, "{s}/zig-local-{s}", .{ base, hex[0..] });
    var made = try std.Io.Dir.cwd().createDirPathOpen(t.io, path, .{});
    made.close(t.io);
    return path;
}

/// Fails the test unless `zig cc` exited 0; when it did not, its stderr is the first difference shown.
fn expectCompiled(result: std.process.RunResult) !void {
    switch (result.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    try t.expectEqualStrings("", result.stderr);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

// spec: NATIVE-ZIG-CACHE-4
test "a test's own zig cc keeps its cache in the run's private scratch" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inherited = t.environ.getPosix("ZIG_LOCAL_CACHE_DIR") orelse "";
    const project = try std.Io.Dir.cwd().realPathFileAlloc(t.io, ".zig-cache", a);
    try t.expect(std.fs.path.isAbsolute(inherited));
    try t.expect(!std.mem.startsWith(u8, inherited, project));
    const cache = try privateCache(a);
    defer std.Io.Dir.cwd().deleteTree(t.io, cache) catch {};
    // A testing tmpDir lives under the project's `.zig-cache/tmp`, so without
    // the variable Zig would find this project's `build.zig` above it and
    // cache the object there.
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "zig_cache_probe.c", .data = "int zig_cache_probe(void) { return 4; }\n" });
    var environment = try t.environ.createMap(a);
    try environment.put("ZIG_LOCAL_CACHE_DIR", cache);
    const result = try std.process.run(a, t.io, .{
        .argv = &.{ @import("native_test_options").zig_path, "cc", "-c", "zig_cache_probe.c", "-o", "zig_cache_probe.o" },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    try expectCompiled(result);
    try t.expect(try cachedObject(cache, "zig_cache_probe.o"));
    // The inherited scratch and the project's cache stay untouched by the probe.
    try t.expect(!(try cachedObject(inherited, "zig_cache_probe.o")));
    try t.expect(!(try cachedObject(project, "zig_cache_probe.o")));
}
