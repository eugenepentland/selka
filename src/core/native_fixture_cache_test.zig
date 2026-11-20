//! Construction reuse must not reuse a fixture's execution or mutable outputs.
const std = @import("std");
const native = @import("native_fixture.zig");
const cache = @import("native_fixture_cache.zig");
const tools = @import("tool_identity.zig");
// Cache mechanics need real compilation and execution, but not a second copy
// of the runtime's stress/accounting suite. Those assertions remain unchanged.
const source = @embedFile("native_fixture_cache_probe.c");

// spec-case: NATIVE-FIXTURE-CACHE-1
test "native fixture identity separates source runtime names flags tool target epoch and sanitizer" {
    const tool: tools.Identity = .{ .path = "zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = false };
    const base: cache.Program = .{ .root = "root", .binary = "root/fixture", .runtime = "runtime", .source = "source" };
    const original = cache.key(base, tool, false, "");
    var changed = tool;
    changed.digest[0] += 1;
    var cpu = tool;
    cpu.native_target[0] += 1;
    var runtime = base;
    runtime.runtime = "changed";
    var text = base;
    text.source = "changed";
    var runtime_name = base;
    runtime_name.runtime_name = "core_rt.c";
    var source_name = base;
    source_name.source_name = "harness.c";
    var flags = base;
    flags.flags = &.{ "-O2", "-std=c11", "-pthread" };
    var more = base;
    more.flags = &(cache.default_flags ++ [_][]const u8{"-O3"});
    for ([_][32]u8{
        cache.key(runtime, tool, false, ""),
        cache.key(text, tool, false, ""),
        cache.key(runtime_name, tool, false, ""),
        cache.key(source_name, tool, false, ""),
        cache.key(flags, tool, false, ""),
        cache.key(more, tool, false, ""),
        cache.key(base, changed, false, ""),
        cache.key(base, cpu, false, ""),
        cache.key(base, tool, true, ""),
        cache.key(base, tool, false, "123"),
    }) |other| try std.testing.expect(!std.mem.eql(u8, &original, &other));
    // Where a build happens is not what it builds.
    var moved = base;
    moved.root = "elsewhere";
    moved.binary = "elsewhere/other";
    try std.testing.expectEqualSlices(u8, &original, &cache.key(moved, tool, false, ""));
}

// spec-case: NATIVE-FIXTURE-CACHE-1
test "native fixture reuse is for sources whose only quoted include is the runtime text beside them" {
    try std.testing.expect(cache.supported(source, "core_rt_all.c"));
    try std.testing.expect(cache.supported("#include \"core_rt_all.c\"\n  #  include <assert.h>\nint main(void) { return 0; }\n", "core_rt_all.c"));
    try std.testing.expect(cache.supported("#include \"core_rt.c\"\n", "core_rt.c"));
    try std.testing.expect(!cache.supported("#include \"core_rt.c\"\n", "core_rt_all.c"));
    try std.testing.expect(!cache.supported("#include \"untracked.h\"", "core_rt_all.c"));
    try std.testing.expect(!cache.supported("#include \"core_rt_all.c\"\n#include \"untracked.h\"\n", "core_rt_all.c"));
    try std.testing.expect(!cache.supported("#define HEADER \"core_rt_all.c\"\n#include HEADER\n", "core_rt_all.c"));
    try std.testing.expect(!cache.supported("#include_next <stdio.h>\n", "core_rt_all.c"));
}

test "native fixture cache reuses construction executes fresh and repairs corrupt binary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var store = std.testing.tmpDir(.{ .iterate = true });
    defer store.cleanup();
    const cache_directory = try store.dir.realPathFileAlloc(io, ".", a);
    var first_dir = std.testing.tmpDir(.{});
    defer first_dir.cleanup();
    var second_dir = std.testing.tmpDir(.{});
    defer second_dir.cleanup();
    const first_root = try first_dir.dir.realPathFileAlloc(io, ".", a);
    const second_root = try second_dir.dir.realPathFileAlloc(io, ".", a);
    const options: native.Options = .{ .counted = true, .cache_directory = cache_directory };
    var first = try native.Fixture.init(a, first_root, source, options);
    try std.testing.expect(!first.reused);
    const one = try first.run("accounting", "1");
    try std.testing.expectEqual(@as(u8, 0), one.status);
    var second = try native.Fixture.init(a, second_root, source, options);
    try std.testing.expect(second.reused);
    try std.testing.expect(!std.mem.eql(u8, first.binary, second.binary));
    const two = try second.run("accounting", "1");
    try std.testing.expectEqualStrings(one.stdout, two.stdout);
    try std.testing.expectEqualStrings(one.counts, two.counts);
    try std.testing.expectEqual(@as(u8, 0), two.status);
    try std.testing.expectEqualStrings("{\"cache_probe\":true}\n", two.counts);
    try std.testing.expectEqualStrings("cache probe executed\n", two.stdout);
    // A fresh run must actually recreate its private counters, including a hit.
    try second_dir.dir.deleteFile(io, "counts.json");
    const again = try second.run("accounting", "1");
    try std.testing.expectEqualStrings(two.counts, again.counts);
    var iterator = store.dir.iterate();
    var corrupted: usize = 0;
    while (try iterator.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".bin")) continue;
        try store.dir.writeFile(io, .{ .sub_path = entry.name, .data = "broken" });
        corrupted += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), corrupted);
    var repaired = try native.Fixture.init(a, second_root, source, options);
    try std.testing.expect(!repaired.reused);
    const repaired_run = try repaired.run("accounting", "1");
    try std.testing.expectEqualStrings(one.counts, repaired_run.counts);
}

/// Build the probe in a fresh root against one store, with these flags and source name; true when restored.
fn programIn(a: std.mem.Allocator, directory: []const u8, flags: []const []const u8, source_name: []const u8) !bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = source_name, .data = source });
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    return cache.build(a, &environment, .{
        .program = .{ .root = root, .binary = try std.fs.path.join(a, &.{ root, "program" }), .runtime = "", .source = source, .source_name = source_name, .flags = flags },
        .sanitized = false,
        .directory = directory,
        .reuse = true,
    });
}

// spec: NATIVE-FIXTURE-CACHE-1
test "a program is restored under any root and rebuilt when its flags or file names change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = std.testing.tmpDir(.{});
    defer store.cleanup();
    const directory = try store.dir.realPathFileAlloc(std.testing.io, ".", a);
    const optimized: []const []const u8 = &.{ "-O2", "-std=c11" };
    const plain: []const []const u8 = &.{ "-O0", "-std=c11" };
    try std.testing.expect(!try programIn(a, directory, optimized, "fixture.c"));
    try std.testing.expect(try programIn(a, directory, optimized, "fixture.c"));
    try std.testing.expect(!try programIn(a, directory, plain, "fixture.c"));
    try std.testing.expect(!try programIn(a, directory, optimized, "renamed.c"));
    try std.testing.expect(try programIn(a, directory, plain, "fixture.c"));
}

test "native fixture construction fails closed when the selected tool is missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = std.process.Environ.Map.init(a);
    defer environment.deinit();
    try environment.put("ZIG", try std.fs.path.join(a, &.{ root, "missing-tool" }));
    try std.testing.expectError(error.FixtureBuildFailed, cache.build(a, &environment, .{
        .program = .{ .root = root, .binary = try std.fs.path.join(a, &.{ root, "fixture" }), .runtime = "runtime", .source = source },
        .sanitized = false,
        .directory = try std.fs.path.join(a, &.{ root, "cache" }),
        .reuse = true,
    }));
    try std.testing.expectError(error.FileNotFound, directory.dir.statFile(std.testing.io, "fixture", .{}));
}
