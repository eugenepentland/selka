//! Dictionary ordinals after deletes name the entry a bitmap scan names (the Fenwick rank in core_dict.c).
const std = @import("std");
const native = @import("native_fixture.zig");

fn checkRank(a: std.mem.Allocator) !void {
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const output = try native.buildProgram(a, root, .{ .source = @embedFile("runtime/dict_rank_fixture.c"), .binary_name = "harness", .source_name = "harness.c" });
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = &environment, .cwd = .{ .path = root } });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("dict ordinals match a scan: 2812 checked\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

test "dictionary ordinals after deletes match a bitmap scan across dead words growth and copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try checkRank(arena.allocator());
}
