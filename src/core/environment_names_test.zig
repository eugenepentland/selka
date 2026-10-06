//! Environment enumeration reads grants and keeps native callback state opaque.
const std = @import("std");
const options = @import("core_test_options");
const report = std.debug.print;

fn assertNames(a: std.mem.Allocator, binary: []const u8) !void {
    var environment = std.process.Environ.Map.init(a);
    try environment.put("PATH", "context-probe");
    try environment.put("ONLY_VISIBLE", "ok");
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const Case = struct { grants: ?[]const u8, output: []const u8, malformed: bool = false };
    for ([_]Case{
        .{ .grants = null, .output = "3\nMYL_CORE_LEAKCHECK\nONLY_VISIBLE\nPATH\n" },
        .{ .grants = null, .output = "3\nMYL_CORE_LEAKCHECK\nONLY_VISIBLE\nPATH\n", .malformed = true },
        .{ .grants = "--allow-env=B,A", .output = "2\nA\nB\n" },
        .{ .grants = "--restrict --allow-env=B,A", .output = "2\nA\nB\n" },
    }) |case| {
        if (case.malformed) try environment.put("INVALID_\xff", "ignored") else _ = environment.remove("INVALID_\xff");
        if (case.grants) |value| try environment.put("MYLANG_OPTIONS", value);
        const result = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
        try std.testing.expect(result.term == .exited and result.term.exited == 0);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expectEqualStrings(case.output, result.stdout);
    }
}

fn qualify(a: std.mem.Allocator, mode: []const []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try std.fmt.allocPrint(a, "{s}/c_environment_context.my", .{options.fixtures});
    const provider = try std.fmt.allocPrint(a, "{s}/c_environment_context_provider.c", .{options.fixtures});
    const binary = try std.fs.path.join(a, &.{ root, "probe" });
    {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", binary, "--link", provider, "--cache-dir", root });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("Core environment context build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        try std.testing.expectEqualStrings("", built.stderr);
        try assertNames(a, binary);
    }
}

// spec-case: ENVIRONMENT-NAMES-1
test "Core Environment names come from grants rather than the linked provider context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| try qualify(arena.allocator(), mode);
}
