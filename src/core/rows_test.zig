//! The S1 microbenchmark rows as programs of their own (`test/core/row_*.my`, split from
//! benchmarks/runtime/{ports,expanded/compute,expanded/collections}/main.my) build in the
//! new core with the old core's checksums. Rows the new core still refuses are skipped, but
//! the number it builds may not shrink: that ratchet is what a regression fails.
const std = @import("std");
const options = @import("core_test_options");

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// One row: the checksums of the original benchmark program (built with the old core) for
/// `64 300 7` and `4100 30 999983` (size, iterations, seed).
const Row = struct { name: []const u8, small: []const u8, large: []const u8 };

const rows = [_]Row{
    .{ .name = "record_reads", .small = "186354", .large = "30078402" },
    .{ .name = "tagged_stack", .small = "292093", .large = "27069" },
    .{ .name = "mutate_unique", .small = "291158", .large = "2080125" },
    .{ .name = "mutate_shared", .small = "465360", .large = "2094872" },
    .{ .name = "record_construct", .small = "14222873", .large = "96468820" },
    .{ .name = "record_update", .small = "14222873", .large = "96468820" },
    .{ .name = "option_handle", .small = "20099847", .large = "141810414" },
    .{ .name = "result_propagate", .small = "21992052", .large = "151009200" },
    .{ .name = "list_scan", .small = "10276935", .large = "61961280" },
    .{ .name = "list_append", .small = "402157080", .large = "470844891" },
    .{ .name = "list_filter", .small = "45897138", .large = "225065351" },
    .{ .name = "alloc_short", .small = "14553600", .large = "7858549" },
    .{ .name = "alloc_retained", .small = "14553600", .large = "7858549" },
    .{ .name = "mutate_nested", .small = "546312", .large = "8288660" },
};

/// How many rows the new core builds today; a lane may raise it, none may lower it.
const built_floor = 6;

fn firstField(text: []const u8) []const u8 {
    var fields = std.mem.tokenizeAny(u8, text, " \n");
    return fields.next() orelse "";
}

fn exitedWith(term: std.process.Child.Term, status: u8) bool {
    return term == .exited and term.exited == status;
}

/// Build `row` at one level and return its executable, or null when the new core refuses it.
fn buildRow(arena: std.mem.Allocator, root: []const u8, row: Row, release: bool) !?[]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/row_{s}.my", .{ options.fixtures, row.name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, row.name, if (release) "release" else "debug" });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    if (release) try argv.append(arena, "--release");
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (exitedWith(built.term, 0)) return output;
    if (std.mem.indexOf(u8, built.stderr, "E_CORE_UNSUPPORTED") != null) return null;
    report("{s}: the new core failed to build the row:\n{s}\n", .{ row.name, built.stderr });
    return error.BuildFailed;
}

/// The row's checksum for `size iterations seed`.
fn checksum(arena: std.mem.Allocator, executable: []const u8, arguments: []const []const u8) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, executable);
    try argv.appendSlice(arena, arguments);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    return firstField(result.stdout);
}

/// Whether `row` builds at `release` and prints the original's checksums; null when refused.
fn rowAgrees(arena: std.mem.Allocator, root: []const u8, row: Row, release: bool) !?bool {
    const executable = (try buildRow(arena, root, row, release)) orelse return null;
    const small = try checksum(arena, executable, &.{ "64", "300", "7" });
    const large = try checksum(arena, executable, &.{ "4100", "30", "999983" });
    const agrees = std.mem.eql(u8, small, row.small) and std.mem.eql(u8, large, row.large);
    if (!agrees) report("{s} ({s}): checksums {s} and {s}, expected {s} and {s}\n", .{ row.name, if (release) "release" else "debug", small, large, row.small, row.large });
    return agrees;
}

/// The number of rows built at both levels; every one must agree with the original.
fn builtRows(arena: std.mem.Allocator, root: []const u8) !usize {
    var built: usize = 0;
    for (rows) |row| {
        const debug = try rowAgrees(arena, root, row, false);
        const release = try rowAgrees(arena, root, row, true);
        if (debug == null or release == null) continue;
        try std.testing.expect(debug.? and release.?);
        built += 1;
    }
    return built;
}

// spec: NEW-CORE-ROWS-1
test "the S1 row programs that build give the original benchmarks' checksums, and the built count does not shrink" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    try std.testing.expect(try builtRows(arena.allocator(), root) >= built_floor);
}

// spec-case: NEW-CORE-ROWS-1
test "a row the new core fails to build for a reason other than a refusal is an error, not a skip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const missing: Row = .{ .name = "no_such_row", .small = "", .large = "" };
    try std.testing.expectError(error.BuildFailed, buildRow(arena.allocator(), root, missing, false));
}
