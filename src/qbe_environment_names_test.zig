//! Native provider contexts cannot substitute for Environment name grants.
const std = @import("std");
const report = std.debug.print;

fn assertNames(a: std.mem.Allocator, binary: []const u8) !void {
    var environment = std.process.Environ.Map.init(a);
    try environment.put("PATH", "context-probe");
    try environment.put("ONLY_VISIBLE", "ok");
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const Case = struct { options: ?[]const u8, output: []const u8, malformed: bool = false };
    for ([_]Case{
        .{ .options = null, .output = "3\nMYL_CORE_LEAKCHECK\nONLY_VISIBLE\nPATH\n" },
        .{ .options = null, .output = "3\nMYL_CORE_LEAKCHECK\nONLY_VISIBLE\nPATH\n", .malformed = true },
        .{ .options = "--allow-env=B,A", .output = "2\nA\nB\n" },
        .{ .options = "--restrict --allow-env=B,A", .output = "2\nA\nB\n" },
    }) |case| {
        if (case.malformed) try environment.put("INVALID_\xff", "ignored") else _ = environment.remove("INVALID_\xff");
        if (case.options) |value| try environment.put("MYLANG_OPTIONS", value);
        const result = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expectEqualStrings(case.output, result.stdout);
    }
}

fn qualify(a: std.mem.Allocator, mode: []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const qbe = std.testing.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const tool_dir = std.fs.path.dirname(qbe) orelse return error.ToolNotFound;
    const compiler = try std.fs.path.join(a, &.{ tool_dir, "mylang" });
    const binary = try std.fs.path.join(a, &.{ root, "probe" });
    const argv: []const []const u8 = &.{
        compiler,     "build",                                      "test/core/c_environment_context.my", "-o", binary,   "--qbe", qbe,
        "--provider", "test/core/c_environment_context_provider.c", "--cache-dir",                        root, "--mode", mode,
    };
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv });
    if (built.term != .exited or built.term.exited != 0) report("environment context build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    try std.testing.expectEqualStrings("", built.stderr);
    try assertNames(a, binary);
}

// spec-case: ENVIRONMENT-NAMES-1
test "QBE Environment names come from grants rather than the linked provider context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "Debug", "ReleaseSafe" }) |mode| try qualify(arena.allocator(), mode);
}
