//! A native receipt whose object is gone rebuilds its unit: the build succeeds and its program equals a `--no-cache` build.
//! Covered for a shared receipt read by a tree with fresh private stores, and for a private receipt whose replay records are
//! removed, so the build takes the unit path and not the replay.
const std = @import("std");
const tools = @import("core_test_options");

const io = std.testing.io;
const program = "func helper(x: int) -> int:\n    return x + 1\n\nfunc main() -> int:\n    return helper(41) - 42\n";

/// Run the compiler on `source` with `flags` and `environment`, writing the program to `output`. Returns the exit status.
fn build(a: std.mem.Allocator, executable: []const u8, source: []const u8, output: []const u8, flags: []const []const u8, environment: *const std.process.Environ.Map) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ executable, "build", source, "-o", output });
    try argv.appendSlice(a, flags);
    const result = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = environment });
    return switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
}

/// Delete every unit object (`*.o`) under the per-user unit store of `xdg`, and report how many it removed.
fn deleteObjects(a: std.mem.Allocator, xdg: []const u8) !usize {
    const units = try std.fs.path.join(a, &.{ xdg, "selka", "core-runtime", "units-v1" });
    var top = std.Io.Dir.cwd().openDir(io, units, .{ .iterate = true }) catch return 0;
    defer top.close(io);
    var deleted: usize = 0;
    var shards = top.iterate();
    while (try shards.next(io)) |shard| {
        if (shard.kind != .directory) continue;
        var dir = try top.openDir(io, shard.name, .{ .iterate = true });
        defer dir.close(io);
        var files = dir.iterate();
        while (try files.next(io)) |file| {
            if (file.kind != .file or !std.mem.endsWith(u8, file.name, ".o")) continue;
            try dir.deleteFile(io, file.name);
            deleted += 1;
        }
    }
    return deleted;
}

/// The program bytes `output` holds.
fn program_bytes(a: std.mem.Allocator, output: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, output, a, .limited(64 << 20));
}

test "a shared native receipt whose unit object is gone rebuilds the unit in a tree with fresh private stores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "app.selka", .data = program });
    const executable = try std.Io.Dir.cwd().realPathFileAlloc(io, tools.corePath(), a);
    const source = try std.fs.path.join(a, &.{ root, "app.selka" });
    const xdg = try std.fs.path.join(a, &.{ root, "xdg" });
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    var environment = try tools.privateEnvironment(a);
    try environment.put("XDG_CACHE_HOME", xdg);
    try environment.put("SELKA_STAGE_SHARED_CACHE", shared);
    const first_cache = try std.fs.path.join(a, &.{ root, "first-cache" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, try std.fs.path.join(a, &.{ root, "first" }), &.{ "--cache-dir", first_cache }, &environment));
    try std.testing.expect((try deleteObjects(a, xdg)) > 0);
    const second_cache = try std.fs.path.join(a, &.{ root, "second-cache" });
    const second = try std.fs.path.join(a, &.{ root, "second" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, second, &.{ "--cache-dir", second_cache }, &environment));
    const reference = try std.fs.path.join(a, &.{ root, "reference" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, reference, &.{"--no-cache"}, &environment));
    try std.testing.expectEqualSlices(u8, try program_bytes(a, reference), try program_bytes(a, second));
}

test "a private native receipt whose unit object is gone rebuilds the unit, and the program equals a no-cache build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "app.selka", .data = program });
    const executable = try std.Io.Dir.cwd().realPathFileAlloc(io, tools.corePath(), a);
    const source = try std.fs.path.join(a, &.{ root, "app.selka" });
    const xdg = try std.fs.path.join(a, &.{ root, "xdg" });
    var environment = try tools.privateEnvironment(a);
    try environment.put("XDG_CACHE_HOME", xdg);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const first = try std.fs.path.join(a, &.{ root, "first" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, first, &.{ "--cache-dir", cache }, &environment));
    try std.testing.expect((try deleteObjects(a, xdg)) > 0);
    // The replay records and linked programs would answer this build without the unit path; remove them, keep the receipts.
    try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(a, &.{ cache, "replay-v1" }));
    try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(a, &.{ cache, "programs-v2" }));
    const second = try std.fs.path.join(a, &.{ root, "second" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, second, &.{ "--cache-dir", cache }, &environment));
    const reference = try std.fs.path.join(a, &.{ root, "reference" });
    try std.testing.expectEqual(@as(u8, 0), try build(a, executable, source, reference, &.{"--no-cache"}, &environment));
    try std.testing.expectEqualSlices(u8, try program_bytes(a, reference), try program_bytes(a, second));
}
