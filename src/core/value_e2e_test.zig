//! S1 lane V end-to-end: the `test/core/v_*.my` fixtures (records, unions, `?`, lists, `mut`
//! parameters, wide records, equality, numeric conversions, traps) are built at debug, release
//! and release with `--verify-facts`; each prints what the old core prints for the same file
//! (recorded below) and exits with its status. `-Dcore-diff=true` rebuilds them with the old compiler.
const std = @import("std");
const options = @import("core_test_options");

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

const Outcome = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// How a fixture is built.
const Mode = enum { debug, release, verify, old };

fn scratch(arena: std.mem.Allocator, dir: std.testing.TmpDir) ![]const u8 {
    return dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
}

/// Build `test/core/NAME.my` in `mode` and run it; the build must succeed.
fn runFixture(arena: std.mem.Allocator, root: []const u8, name: []const u8, mode: Mode) !Outcome {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, name, @tagName(mode) });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache-{s}", .{ root, if (mode == .old) "old" else "new" });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ if (mode == .old) options.old_path else options.core_path, "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    switch (mode) {
        .debug => {},
        .release, .old => try argv.append(arena, "--release"),
        .verify => try argv.appendSlice(arena, &.{ "--release", "--verify-facts" }),
    }
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) {
        report("build of {s} ({s}) failed:\n{s}{s}\n", .{ name, @tagName(mode), built.stdout, built.stderr });
        return error.BuildFailed;
    }
    const result = try std.process.run(arena, std.testing.io, .{ .argv = &.{output} });
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .status = status };
}

/// Whether the fixture prints `expected` and exits with `status` at debug, release and verify.
fn matches(arena: std.mem.Allocator, name: []const u8, expected: []const u8, status: u8) !bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena, dir);
    var same = true;
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const got = try runFixture(arena, root, name, mode);
        if (!std.mem.eql(u8, got.stdout, expected) or got.status != status) {
            report("{s} ({s}) printed:\n{s}status {d}, expected:\n{s}status {d}\n{s}\n", .{ name, @tagName(mode), got.stdout, got.status, expected, status, got.stderr });
            same = false;
        }
    }
    if (options.differential) {
        const old = try runFixture(arena, root, name, .old);
        same = same and std.mem.eql(u8, old.stdout, expected) and old.status == status;
    }
    return same;
}

/// The stderr of the fixture's release build run, for the trap tests.
fn stderrOf(arena: std.mem.Allocator, name: []const u8, mode: Mode) ![]const u8 {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena, dir);
    return (try runFixture(arena, root, name, mode)).stderr;
}

const v_records_output =
    \\7 5 0
    \\False 42 6
    \\5 48
    \\2202
    \\2231
    \\False True True
    \\
;

// spec-case: NEW-CORE-RECORD-2
test "records: construction, nested field writes, narrow fields and enums print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_records", v_records_output, 0));
}

const v_unions_output =
    \\9 20 1
    \\18410
    \\ok 31
    \\err negative
    \\err negative
    \\29
    \\ok 10
    \\err neg
    \\err neg
    \\321
    \\1
    \\10
    \\
;

// spec-case: NEW-CORE-UNION-2
test "unions, Option, Result with ?, enums and recursive boxed values print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_unions", v_unions_output, 0));
}

const v_lists_output =
    \\8
    \\6558 1 5
    \\11039
    \\5 1 78
    \\4 11
    \\142
    \\3 3
    \\
;

// spec-case: NEW-CORE-LIST-2
test "element writes, pop, writes through record fields and matches on union elements print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_lists", v_lists_output, 0));
}

const v_mut_output =
    \\5 5 16
    \\104
    \\1 1
    \\3 3 3 11
    \\5 5 3 9
    \\4 1 3
    \\130 0
    \\3 5 -1 15
    \\
;

// spec-case: NEW-CORE-MUT-1
test "mut parameters of lists and records write their final values back to the caller as the old core does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_mut", v_mut_output, 0));
}

const v_wide_output =
    \\66 4 48
    \\1974 5
    \\1064
    \\104 0 21 False
    \\1356043 33039
    \\671
    \\93
    \\
;

// spec: NEW-CORE-RECORD-3
test "records and unions over four words, in loops, lists, boxes and calls, print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_wide", v_wide_output, 0));
}

const v_equality_output =
    \\False True False True
    \\True True
    \\True
    \\False
    \\True False True True False
    \\True False True True
    \\True False True False
    \\True False
    \\True True
    \\
;

// spec: NEW-CORE-EQ-1
test "== and != compare records, unions, Option and lists of scalars structurally" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_equality", v_equality_output, 0));
}

const v_numeric_output =
    \\5
    \\0 5
    \\5 254
    \\-128 127 0 -128
    \\-9223372036854775808 9223372036854774784 0
    \\
;

// spec: NEW-CORE-NUMERIC-1
test "unit arguments, i16 and u8 ranges and float-to-int truncation print what the old core prints, and the last conversion traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_numeric", v_numeric_output, 1));
    // -129.0 truncates to -129, outside i8: the old core's trap code, in debug and release.
    for ([_]Mode{ .debug, .release }) |mode| {
        const stderr = try stderrOf(arena.allocator(), "v_numeric", mode);
        try std.testing.expect(std.mem.indexOf(u8, stderr, "error[R_FLOAT_CONVERSION]: native execution failed") != null);
    }
}

// spec-case: NEW-CORE-LIST-1
test "pop of an empty list and a list_set past the end trap R_LIST_BOUNDS like the old core, with its pop and index details" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_trap_pop", "", 1));
    try std.testing.expect(try matches(arena.allocator(), "v_trap_set", "9\n", 1));
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const popped = try stderrOf(arena.allocator(), "v_trap_pop", mode);
        try std.testing.expect(std.mem.indexOf(u8, popped, "error[R_LIST_BOUNDS]: native execution failed (length 0)") != null);
        try std.testing.expect(std.mem.indexOf(u8, popped, "MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":0}") != null);
        const set = try stderrOf(arena.allocator(), "v_trap_set", mode);
        try std.testing.expect(std.mem.indexOf(u8, set, "error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)") != null);
    }
}

const v_nested_output =
    \\302 2
    \\550278 1 1
    \\
;

// spec-case: NEW-CORE-PLACE-1
test "appends and writes to elements of lists of lists and records print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_nested", v_nested_output, 0));
}

const v_mut_window_output =
    \\102 True 1
    \\2 3 2
    \\
;

// spec-case: NEW-CORE-MUT-1
test "a mut argument's value is read when the call runs, after a nested call that writes the same place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_mut_window", v_mut_window_output, 0));
}
