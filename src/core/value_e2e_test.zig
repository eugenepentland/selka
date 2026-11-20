//! S1 lane V end-to-end: the `test/core/v_*.selka` fixtures (records, unions, `?`, lists, `mut`
//! parameters, wide records, equality, numeric conversions, traps) are built at debug, release
//! and release with `--verify-facts`; each prints what the old core prints for the same file
//! (recorded below) and exits with its status. `-Dcore-diff=true` rebuilds them with the old compiler.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");

/// The flag that builds with the release passes.
const release_flag = @import("e2e_test.zig").optimize_flag;

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

const Outcome = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// How a fixture is built.
const Mode = enum { debug, release, verify, old };

fn scratch(arena: std.mem.Allocator, dir: std.testing.TmpDir) ![]const u8 {
    return dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
}

/// Build `test/core/NAME.selka` in `mode` and run it; the build must succeed.
fn runFixture(arena: std.mem.Allocator, root: []const u8, name: []const u8, mode: Mode) !Outcome {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, name, @tagName(mode) });
    const cache = if (mode == .old) try std.fmt.allocPrint(arena, "{s}/cache-{s}", .{ root, if (mode == .old) "old" else "new" }) else try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ if (mode == .old) options.old_path else options.corePath(), "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    // An `extern def` fixture (`v_extern_*`) also links its C source, `test/core/NAME.c`.
    if (std.mem.startsWith(u8, name, "v_extern_")) try argv.appendSlice(arena, &.{ "--link", try std.fmt.allocPrint(arena, "{s}/{s}.c", .{ options.fixtures, name }) });
    if (mode != .debug) try support.requireRelease();
    switch (mode) {
        .debug => {},
        .release, .old => try argv.append(arena, release_flag),
        .verify => try argv.appendSlice(arena, &.{ release_flag, "--verify-facts" }),
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

/// Every mode a fixture runs in: debug, release and verify, and the old compiler when the differential is on.
const all_modes: []const Mode = if (options.differential) &.{ .debug, .release, .verify, .old } else &.{ .debug, .release, .verify };

/// The debug build alone: what a debug test checks.
const debug_modes: []const Mode = &.{.debug};

/// The release builds: release, verify, and the old compiler when the differential is on. A "(release)" test checks these.
const release_modes: []const Mode = if (options.differential) &.{ .release, .verify, .old } else &.{ .release, .verify };

/// Whether the fixture prints `expected` and exits with `status` in every one of `modes`.
fn matchesIn(arena: std.mem.Allocator, name: []const u8, expected: []const u8, status: u8, modes: []const Mode) !bool {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena, dir);
    var same = true;
    for (modes) |mode| {
        const after_mismatch = mode != .debug and !same;
        if (after_mismatch and !support.releaseEnabled()) return false;
        const got = try runFixture(arena, root, name, mode);
        if (!std.mem.eql(u8, got.stdout, expected) or got.status != status) {
            if (mode != .old) report("{s} ({s}) printed:\n{s}status {d}, expected:\n{s}status {d}\n{s}\n", .{ name, @tagName(mode), got.stdout, got.status, expected, status, got.stderr });
            same = false;
        }
    }
    return same;
}

/// Whether the fixture prints `expected` and exits with `status` at debug, release and verify.
fn matches(arena: std.mem.Allocator, name: []const u8, expected: []const u8, status: u8) !bool {
    return matchesIn(arena, name, expected, status, all_modes);
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

const v_mut_rebind_output =
    \\2208 33 2208
    \\38943 38678 33 38943
    \\1 34 2243 51
    \\2 3 1990 90466 33
    \\3 102 109246 2 2563
    \\
;

// spec: NEW-CORE-MUT-2
test "whole mut collection and record rebinding writes the final value back while preserving source snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_mut_rebind", v_mut_rebind_output, 0));
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
    \\False True False
    \\True False False True
    \\True False
    \\True False
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
    try std.testing.expect(try matchesIn(arena.allocator(), "v_numeric", v_numeric_output, 1, debug_modes));
    // -129.0 truncates to -129, outside i8: the old core's trap code, in debug.
    const stderr = try stderrOf(arena.allocator(), "v_numeric", .debug);
    try std.testing.expect(std.mem.indexOf(u8, stderr, "error[R_FLOAT_CONVERSION]: native execution failed") != null);
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "unit arguments, i16 and u8 ranges and float-to-int truncation print what the old core prints, and the last conversion traps (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_numeric", v_numeric_output, 1, release_modes));
    // -129.0 truncates to -129, outside i8: the old core's trap code, in release.
    const stderr = try stderrOf(arena.allocator(), "v_numeric", .release);
    try std.testing.expect(std.mem.indexOf(u8, stderr, "error[R_FLOAT_CONVERSION]: native execution failed") != null);
}

/// The pop and list_set trap details a fixture build in `mode` reports on stderr.
fn expectListBoundsTraps(arena: std.mem.Allocator, mode: Mode) !void {
    const popped = try stderrOf(arena, "v_trap_pop", mode);
    try std.testing.expect(std.mem.indexOf(u8, popped, "error[R_LIST_BOUNDS]: native execution failed (length 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, popped, "SELKA-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":0}") != null);
    const set = try stderrOf(arena, "v_trap_set", mode);
    try std.testing.expect(std.mem.indexOf(u8, set, "error[R_LIST_BOUNDS]: native execution failed (index 2, length 2)") != null);
}

// spec-case: NEW-CORE-LIST-1
test "pop of an empty list and a list_set past the end trap R_LIST_BOUNDS like the old core, with its pop and index details" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trap_pop", "", 1, debug_modes));
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trap_set", "9\n", 1, debug_modes));
    try expectListBoundsTraps(arena.allocator(), .debug);
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "pop of an empty list and a list_set past the end trap R_LIST_BOUNDS like the old core, with its pop and index details (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trap_pop", "", 1, release_modes));
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trap_set", "9\n", 1, release_modes));
    for ([_]Mode{ .release, .verify }) |mode| {
        try expectListBoundsTraps(arena.allocator(), mode);
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

const v_wide_managed_output =
    \\2834 3 1
    \\103012 3104
    \\3 3 50 2
    \\
;

// spec-case: NEW-CORE-RECORD-3
test "records and unions over four words that hold lists print what the old core prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_wide_managed", v_wide_managed_output, 0));
}

/// Build `test/core/NAME.selka` in `mode` and run it under `SELKA_CORE_LEAKCHECK=1`; its stderr.
fn leakReport(arena: std.mem.Allocator, root: []const u8, name: []const u8, mode: Mode) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.selka", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-leak-{s}", .{ root, name, @tagName(mode) });
    const cache = try options.suiteCache(arena, @src());
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    if (mode == .release) try support.requireRelease();
    if (mode == .release) try argv.append(arena, release_flag);
    const built = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    var environment = try std.testing.environ.createMap(arena);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const ran = try std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    return ran.stderr;
}

// spec-case: NEW-CORE-RC-7
test "the value fixtures end with no block live under SELKA_CORE_LEAKCHECK=1, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const names = [_][]const u8{
        "v_records",
        "v_unions",
        "v_lists",
        "v_mut",
        "v_wide",
        "v_wide_managed",
        "v_nested",
        "v_mut_window",
        "v_equality",
        "v_mut_rebind",
        "v_arena",
        "v_str_eq",
        "v_methods",
        "v_narrow",
        "v_snapshot",
        "v_text",
        "v_loops",
        "v_hull",
        "v_sort",
        "v_units",
    };
    for ([_]Mode{ .debug, .release }) |mode| {
        for (names) |name| {
            try std.testing.expectEqualStrings("", try leakReport(arena.allocator(), root, name, mode));
        }
    }
}

/// Run `test/core/NAME.selka` built in `mode` with `args`.
fn runWith(arena: std.mem.Allocator, root: []const u8, name: []const u8, mode: Mode, args: []const []const u8) !Outcome {
    _ = try runFixture(arena, root, name, mode);
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}", .{ root, name, @tagName(mode) });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, output);
    try argv.appendSlice(arena, args);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .status = status };
}

/// The fixture `v_trace` built in `mode` fails with exit status 1 and the old core's error return trace on stderr.
fn expectErrorTrace(arena: std.mem.Allocator, mode: Mode) !void {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena, dir);
    const failed = try runWith(arena, root, "v_trace", mode, &.{"x"});
    try std.testing.expectEqual(@as(u8, 1), failed.status);
    const lines = [_][]const u8{
        "error: negative\n",
        "v_trace.selka:8:9    parse    Err(...) created\n",
        "v_trace.selka:14:12  forward  try propagated\n",
        "v_trace.selka:18:13  pass_on  try propagated\n",
        "v_trace.selka:55:13  main     try propagated\n",
    };
    for (lines) |line| try std.testing.expect(std.mem.indexOf(u8, failed.stderr, line) != null);
}

// spec: NEW-CORE-TRACE-1
test "a main that returns an Err reports it with the old core's error return trace: created, returned, propagated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trace", "run 3 8\nrun failed negative\n", 4, debug_modes));
    try expectErrorTrace(arena.allocator(), .debug);
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "a main that returns an Err reports it with the old core's error return trace: created, returned, propagated (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_trace", "run 3 8\nrun failed negative\n", 4, release_modes));
    try expectErrorTrace(arena.allocator(), .release);
}

const v_str_eq_output =
    \\True False True False True False
    \\True False False
    \\True False True
    \\True False
    \\True False False True
    \\2 -1
    \\
;

// spec-case: NEW-CORE-STR-1
test "str == and != compare bytes, inside records, unions and lists, as the old core does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_str_eq", v_str_eq_output, 0));
}

const v_arena_output =
    \\19507
    \\4 5 44
    \\6
    \\
;

// spec-case: NEW-CORE-ARENA-1
test "migrated arena values break and continue preserve the frozen output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_arena", v_arena_output, 0));
}

/// The failed assert's stderr from the `v_assert` fixture built in `mode`.
fn expectAssertTrap(arena: std.mem.Allocator, mode: Mode) !void {
    const failed = try stderrOf(arena, "v_assert", mode);
    // A comparison's values follow the message (F-18).
    try std.testing.expect(std.mem.indexOf(u8, failed, "v_assert.selka:13:16: error[R_ASSERT]: native execution failed: limit exceeded (left 11, right 10)\n  in checked_sum at ") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed, "SELKA-TRAP {\"version\":1,\"operation\":\"limit exceeded (left 11, right 10)\"}") != null);
}

// spec-case: NEW-CORE-ASSERT-1
test "a failed assert traps R_ASSERT with its message at the condition, flushing the output before it, at every level" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert", "6\n4\n", 1, debug_modes));
    try expectAssertTrap(arena.allocator(), .debug);
    // The comparison's two values follow its message (F-18).
    try std.testing.expect(std.mem.indexOf(u8, try stderrOf(arena.allocator(), "v_assert", .debug), "limit exceeded (left 11, right 10)") != null);
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "a failed assert traps R_ASSERT with its message at the condition, flushing the output before it, at every level (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert", "6\n4\n", 1, release_modes));
    for ([_]Mode{ .release, .verify }) |mode| {
        try expectAssertTrap(arena.allocator(), mode);
    }
}

/// The stderr of the `v_assert_message` and `v_assert_message_err` fixtures built in `mode`.
fn expectAssertMessages(arena: std.mem.Allocator, mode: Mode) !void {
    const computed = try stderrOf(arena, "v_assert_message", mode);
    const computed_prefix = try std.fmt.allocPrint(arena, "bad \"n\"=7\n{s}/v_assert_message.selka:6:12: error[R_ASSERT]: native execution failed\n  in check at ", .{options.fixtures});
    try std.testing.expect(std.mem.startsWith(u8, computed, computed_prefix));
    try std.testing.expect(std.mem.indexOf(u8, computed, "SELKA-TRAP {\"version\":1,\"operation\":\"\"}") != null);
    const literal_false = try stderrOf(arena, "v_assert_message_err", mode);
    const literal_prefix = try std.fmt.allocPrint(arena, "too big: 5\n{s}/v_assert_message_err.selka:21:20: error[R_ASSERT]: native execution failed\n", .{options.fixtures});
    try std.testing.expect(std.mem.startsWith(u8, literal_false, literal_prefix));
}

// spec: NEW-CORE-S4-ASSERT-MESSAGE-1
test "an assert whose message is a computed str prints it on its own stderr line, then traps R_ASSERT without a message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert_message", "1\n2\n", 1, debug_modes));
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert_message_err", "1\n2\n", 1, debug_modes));
    try expectAssertMessages(arena.allocator(), .debug);
}

// F-72: the message is any `str` expression, so two texts joined with `+` print their joined text on the failure path.
test "an assert whose message joins two texts prints the joined text, then traps R_ASSERT at the condition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert_message_joined", "6\n", 1, debug_modes));
    const computed = try stderrOf(arena.allocator(), "v_assert_message_joined", .debug);
    const prefix = try std.fmt.allocPrint(arena.allocator(), "failed for: third\n{s}/v_assert_message_joined.selka:2:12: error[R_ASSERT]: native execution failed\n", .{options.fixtures});
    try std.testing.expect(std.mem.startsWith(u8, computed, prefix));
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "an assert whose message is a computed str prints it on its own stderr line, then traps R_ASSERT without a message (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert_message", "1\n2\n", 1, release_modes));
    try std.testing.expect(try matchesIn(arena.allocator(), "v_assert_message_err", "1\n2\n", 1, release_modes));
    try expectAssertMessages(arena.allocator(), .release);
}

const v_buffer_mut_output =
    \\True False False False True
    \\True False False True
    \\8:3132334100cebb78 2
    \\8:3132334100cebb78 12:3132334100cebb7861626342
    \\14:3132334100cebb78616263423132
    \\1000000 137293856
    \\
;

// spec: NEW-CORE-S4-TAKE-1
test "byte_buffer appends through mut record fields print what the old core prints, in place and leak-free" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(a, dir);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_]Mode{ .debug, .release, .verify }) |mode| {
        const retired = try runFixture(a, root, "v_buffer_mut", mode);
        try std.testing.expectEqual(@as(u8, 1), retired.status);
        try std.testing.expectEqualStrings("", retired.stdout);
        try std.testing.expect(std.mem.indexOf(u8, retired.stderr, "R_LIST_BOUNDS") != null);
        try std.testing.expect(std.mem.indexOf(u8, retired.stderr, "index -1, length 10") != null);
        // The current fixture replaces only the negative interval with a reversed one.
        const current = try runFixture(a, root, "v_buffer_mut_current", mode);
        try std.testing.expectEqual(@as(u8, 0), current.status);
        try std.testing.expectEqualStrings(v_buffer_mut_output, current.stdout);
        try std.testing.expectEqualStrings("", current.stderr);
        // Retain the full 600,000 mut-field append workload under the leak checker.
        const output = try std.fmt.allocPrint(a, "{s}/v_buffer_mut_current-{s}", .{ root, @tagName(mode) });
        const leaked = try std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
        try std.testing.expect(leaked.term == .exited and leaked.term.exited == 0);
        try std.testing.expectEqualStrings(v_buffer_mut_output, leaked.stdout);
        try std.testing.expectEqualStrings("", leaked.stderr);
    }
    try oldBufferMut(a, root);
}

fn oldBufferMut(a: std.mem.Allocator, root: []const u8) !void {
    if (!options.differential) return;
    const old = try runFixture(a, root, "v_buffer_mut", .old);
    try std.testing.expectEqual(@as(u8, 0), old.status);
    try std.testing.expectEqualStrings(v_buffer_mut_output, old.stdout);
}

const v_methods_output =
    \\7
    \\3 4
    \\1 2 1
    \\1 1
    \\43
    \\202
    \\
;

// spec: NEW-CORE-LIST-3
test "len of a string counts scalars, clear and copy keep value semantics, and keyword calls evaluate in source order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_methods", v_methods_output, 0));
}

const v_narrow_output =
    \\2 105 140 3
    \\142 40 2
    \\0 -1
    \\
;

// spec: NEW-CORE-PLACE-2
test "a write through a narrowed Option (xs.append, xs[i] = v after `is None` returns) reaches the Option the caller holds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_narrow", v_narrow_output, 0));
}

const v_snapshot_output =
    \\1 50
    \\1 4
    \\1 7
    \\1 50 1
    \\11 3 17
    \\
;

// spec: NEW-CORE-PLACE-3
// spec-case: MUT-REBIND-CALLER-1
test "a read through a receiver captured before an argument wrote its place sees the receiver as it was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_snapshot", v_snapshot_output, 0));
}

const v_text_output =
    \\total 7 of 3 items 2 True None a-xb
    \\-9223372036854775807 18446744073709551615 -5 200 False
    \\héllo 5  True
    \\w0, w1, w4, w9 w0 True w0w1w4
    \\465 n4 6
    \\
;

// spec: NEW-CORE-TEXT-1
test "f-strings, str(x), concatenation and join build the old core's text, with nothing leaked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_text", v_text_output, 0));
}

const v_loops_output =
    \\2 -1 -1
    \\45 0 30 0
    \\61 0
    \\
;

// spec: NEW-CORE-LOOP-1
test "while True has no exit edge: only break and return leave it, and the function needs no return after it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_loops", v_loops_output, 0));
}

const v_domain_output =
    \\1000 True True
    \\4 2 True
    \\
;

// spec: NEW-CORE-DOMAIN-1
test "a domain over an integer or a bool is its wire type: wrap and unwrap change nothing, equality compares the values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_domain", v_domain_output, 0));
}

const v_udiv_output =
    \\127 127 2 18446744073709551615 6148914691236517205
    \\
;

// spec: NEW-CORE-VERIFY-4
test "a verify build does not call an unsigned operand above half its range negative: proven unsigned divisions of high values run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_udiv", v_udiv_output, 0));
}

const v_hull_output =
    \\3807232 -1 -1 -1
    \\3271444 87 2145 19
    \\669 406 -1
    \\
;

/// The doubling loop of `v_hull` built in `mode` still traps on overflow with exit status 1.
fn expectHullTrap(arena: std.mem.Allocator, mode: Mode) !void {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena, dir);
    const trapped = try runWith(arena, root, "v_hull", mode, &.{ "5", "100000", "999999" });
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(std.mem.indexOf(u8, trapped.stderr, "error[R_OVERFLOW]: native execution failed (mul: left 5764607523034234879, right 2, width 64)") != null);
}

// spec-case: NEW-CORE-FACTS-8
test "a list a loop rewrites keeps the hull of what it was given and what is written: remainders and bounds are proven, a doubling loop still traps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_hull", v_hull_output, 192, debug_modes));
    try expectHullTrap(arena.allocator(), .debug);
}

// The release half of the test above: release and verify builds, skipped by default (release builds are off).
test "a list a loop rewrites keeps the hull of what it was given and what is written: remainders and bounds are proven, a doubling loop still traps (release)" {
    try support.requireRelease();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matchesIn(arena.allocator(), "v_hull", v_hull_output, 192, release_modes));
    for ([_]Mode{ .release, .verify }) |mode| {
        try expectHullTrap(arena.allocator(), mode);
    }
}

const v_sort_output =
    \\0 True 0 0 0
    \\1 True 999999567 999999567 999999567
    \\2 True 999995170 999995170 999995170
    \\15 True 13616722 637315704 637315704
    \\16 True 610459072 144699617 144699617
    \\17 True 311143526 869027907 869027907
    \\100 True 587004387 399235360 399235360
    \\1000 True 376096651 67562437 67562437
    \\5000 True 886678288 132888976 132888976
    \\840054931 948237542 -3 12
    \\, Apple, apple, fig, fig, pear, zebra, éclair 428206146 8
    \\-128 -100 127 0 18446744073709551615 0 255
    \\-725 -100 2 1 200 350 1000 1000
    \\90399 a -497,84,482
    \\
;

// spec: NEW-CORE-SORT-1
test "xs.sort() and sorted(xs) of integers, floats and text give the old core's order: stable, NaN last, signed zeros tied, no leak" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_sort", v_sort_output, 0));
}

const v_dict_view_len_output =
    \\3 3 3
    \\
;

// spec: NEW-CORE-S5-VIEW-LEN-1
test "len of a dictionary's keys or values view is an int, and a program may return it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_dict_view_len", v_dict_view_len_output, 2));
}

const v_units_output =
    \\455 122
    \\0 True
    \\
;

// spec: NEW-CORE-UNIT-1
test "a list of Unit holds its length: append, write, read, pop, iteration, copies and equality match the old core" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_units", v_units_output, 0));
}

const v_capability_arrays_output =
    \\zero
    \\grid 0
    \\the record keeps its copy
    \\filled 1
    \\nested
    \\one route
    \\many routes
    \\in a
    \\in b
    \\in a
    \\
;

const v_capability_arrays_errors =
    \\one
    \\grid 1
    \\swapped
    \\rewritten
    \\filled 0
    \\row replaced
    \\many routes
    \\
;

// spec: NEW-CORE-S5-CAP-COLLECTIONS-1
test "fixed arrays of Stream and Host plus named Filesystem owners preserve output and cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_capability_arrays", v_capability_arrays_output, 5));
    try std.testing.expectEqualStrings(v_capability_arrays_errors, try stderrOf(arena.allocator(), "v_capability_arrays", .release));
}

const v_extern_narrow_output =
    \\-5 -300 250 65000 -70000 4000000000
    \\7 3 7
    \\-5 44 -300 4464
    \\-5 -300 255 65535
    \\195
    \\
;

// spec-case: NEW-CORE-S5-EXTERN-ABI-1
test "source extern calls pass i8, i16, u8, u16 and bool arguments widened as C reads them, at debug, release and verify" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try matches(arena.allocator(), "v_extern_narrow", v_extern_narrow_output, 0));
}
