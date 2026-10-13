//! Only initialized worklist slots are read across growth and recursive copies.
const std = @import("std");
const driver = @import("driver.zig");
const report = std.debug.print;

fn checkAbi(a: std.mem.Allocator, zero_rc: bool) !void {
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const runtime = if (zero_rc) try std.mem.concat(a, u8, &.{ "#define MYL_ZERO_RC 1\n", driver.runtime_source }) else driver.runtime_source;
    try dir.dir.writeFile(io, .{ .sub_path = "core_rt.c", .data = runtime });
    try dir.dir.writeFile(io, .{ .sub_path = "harness.c", .data = @embedFile("runtime/owned_copy_stack_fixture.c") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const zig = environment.get("ZIG") orelse "zig";
    const source = try std.fs.path.join(a, &.{ root, "harness.c" });
    const output = try std.fs.path.join(a, &.{ root, "harness" });
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    try environment.put("MYLANG_COUNTERS", try std.fs.path.join(a, &.{ root, "counts.json" }));
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const built = try std.process.run(a, io, .{ .argv = &.{ zig, "cc", "-O2", "-std=c11", "-pthread", "-o", output, source }, .environ_map = &environment, .cwd = .{ .path = root } });
    if (built.term != .exited or built.term.exited != 0) report("copy worklist build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = &environment, .cwd = .{ .path = root } });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("copy stack paths passed; live=0\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    for ([_][]const u8{ "tag", "resource", "descriptor" }) |mode| {
        const refused = try std.process.run(a, io, .{ .argv = &.{ output, mode }, .environ_map = &environment, .cwd = .{ .path = root } });
        try std.testing.expect(refused.term == .signal and refused.term.signal == .ABRT);
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "copy worklist initialized slots preserve active owners through boundary growth and recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try checkAbi(arena.allocator(), false);
    try checkAbi(arena.allocator(), true);
}
