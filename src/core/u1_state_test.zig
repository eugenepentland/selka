//! Lane U1 (docs/audits/runtime-parity-plan-2026-10-08.md §8): the runtime's growth of
//! large blocks, uniqueness tests hoisted out of loops, and loop-carried state kept out
//! of memory. Every expected output is the base compiler's (main 35df839be) for the
//! same program and arguments.
const std = @import("std");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const report = std.debug.print;

const Ran = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Build `test/core/NAME.my` with `flags` and run it with `args` under the leak check;
/// a counting build writes its counters beside the executable (`countsOf`).
fn leakChecked(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8, args: []const []const u8) !Ran {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{d}-{d}", .{ root, name, flags.len, if (flags.len > 0) flags[flags.len - 1].len else 0 });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "build", source, "-o", output, "--cache-dir", cache });
    try argv.appendSlice(arena, flags);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    try environment.put("MYLANG_COUNTERS", try std.fmt.allocPrint(arena, "{s}.json", .{output}));
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(arena, output);
    try run_argv.appendSlice(arena, args);
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited);
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = ran.term.exited };
}

/// The counters a counting run of `leakChecked` wrote for `name` built with `flags`.
fn countsOf(arena: std.mem.Allocator, root: []const u8, name: []const u8, flags: []const []const u8) !std.json.Value {
    const path = try std.fmt.allocPrint(arena, "{s}/{s}-{d}-{d}.json", .{ root, name, flags.len, flags[flags.len - 1].len });
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, arena, .limited(16 << 20));
    return std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
}

/// Counter `name` of the emitted function `function` in a counting run's document.
fn functionCounter(counts: std.json.Value, function: []const u8, name: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return (row.object.get(name) orelse return 0).integer;
    }
    return -1;
}

/// Debug, release, and release with the facts verified.
const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };

// spec: NEW-CORE-U1-GROW-1
test "a large byte buffer grows with realloc, and every append, reserve and shared append keeps its answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    for (modes) |flags| {
        const plain = try leakChecked(a, root, "u1_growth", flags, &.{});
        try std.testing.expectEqualStrings("407375991 70000851576\n7822122 916196 1005004\n0\n1 1\n", plain.stdout);
        try std.testing.expectEqualStrings("", plain.stderr);
        const more = try leakChecked(a, root, "u1_growth", flags, &.{"x"});
        try std.testing.expectEqualStrings("158614987 700003052886\n21729292 2869998 2000019\n0\n1 1\n", more.stdout);
        try std.testing.expectEqual(@as(u8, 0), more.status);
    }
    // A counting build: the large buffer's doublings are reallocations, not copies into
    // fresh blocks, so only its small-block growth copies.
    const counting = [_][]const u8{ "--release", "--counters" };
    const ran = try leakChecked(a, root, "u1_growth", &counting, &.{});
    try std.testing.expectEqualStrings("407375991 70000851576\n7822122 916196 1005004\n0\n1 1\n", ran.stdout);
    const counts = try countsOf(a, root, "u1_growth", &counting);
    try std.testing.expect(functionCounter(counts, "u1_growth::byte_appends", "reallocs") >= 6);
    try std.testing.expect(functionCounter(counts, "u1_growth::byte_appends", "buffer_grow_bytes") < 1024);
}
