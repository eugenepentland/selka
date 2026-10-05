//! The S1 conformance gate (docs/design/new-core-s1.md §9): every file of the pinned list
//! (`test/core/conformance.pins`, the 31 `tests/lang` files) runs under `mylang-core test` at
//! debug and release. A test the pins record as passing must still pass, no other test may
//! fail unless it is pinned `known-fail`, and a crash or a vanished test fails the gate.
//! Tests the new core does not support yet are reported `unsupported` and never fail it.
//! `experiments/new-core-s1-20261005/conformance.py --pin` regenerates the pins from the
//! old core's results; the same script compares every test with the old core directly.
const std = @import("std");
const options = @import("core_test_options");

/// Failure detail goes to the test's stderr.
const report_failure = std.debug.print;

/// What the pins say about one file.
const Pinned = struct {
    name: []const u8,
    passing: []const []const u8,
    known_failures: []const []const u8,
};

/// A pinned expectation a run broke.
const Violation = struct { name: []const u8, why: []const u8 };

const Parsed = struct { files: []const Pinned };

fn parsePins(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!Parsed {
    var files: std.ArrayList(Pinned) = .empty;
    var passing: std.ArrayList([]const u8) = .empty;
    var known: std.ArrayList([]const u8) = .empty;
    var current: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "file ")) {
            if (current) |name| try files.append(arena, .{ .name = name, .passing = try passing.toOwnedSlice(arena), .known_failures = try known.toOwnedSlice(arena) });
            current = line["file ".len..];
        } else if (std.mem.startsWith(u8, line, "pass ")) {
            try passing.append(arena, line["pass ".len..]);
        } else if (std.mem.startsWith(u8, line, "known-fail ")) {
            try known.append(arena, line["known-fail ".len..]);
        }
    }
    if (current) |name| try files.append(arena, .{ .name = name, .passing = try passing.toOwnedSlice(arena), .known_failures = try known.toOwnedSlice(arena) });
    return .{ .files = try files.toOwnedSlice(arena) };
}

fn statusOf(report: std.json.Value, name: []const u8) ?[]const u8 {
    for (report.object.get("tests").?.array.items) |item| {
        if (std.mem.eql(u8, item.object.get("name").?.string, name)) return item.object.get("status").?.string;
    }
    return null;
}

fn listed(names: []const []const u8, wanted: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, wanted)) return true;
    return false;
}

/// Compare one file's `--json` report with its pins; every broken expectation is appended to `out`.
fn judge(arena: std.mem.Allocator, pinned: Pinned, report: std.json.Value, out: *std.ArrayList(Violation)) std.mem.Allocator.Error!void {
    for (pinned.passing) |name| {
        const status = statusOf(report, name) orelse {
            try out.append(arena, .{ .name = name, .why = "pinned as passing, but no longer discovered" });
            continue;
        };
        if (!std.mem.eql(u8, status, "passed")) try out.append(arena, .{ .name = name, .why = try std.fmt.allocPrint(arena, "pinned as passing, now {s}", .{status}) });
    }
    for (report.object.get("tests").?.array.items) |item| {
        const name = item.object.get("name").?.string;
        const failed = std.mem.eql(u8, item.object.get("status").?.string, "failed");
        const excused = listed(pinned.known_failures, name) or listed(pinned.passing, name);
        if (failed and !excused) try out.append(arena, .{ .name = name, .why = try std.fmt.allocPrint(arena, "failed: {s}", .{item.object.get("reason").?.string}) });
    }
}

/// Run one pinned file at one level and return its parsed report, or a crash as an error.
fn runFile(arena: std.mem.Allocator, name: []const u8, release: bool, cache: []const u8) !std.json.Value {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.lang_tests, name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.core_path, "test", source, "--json", "--cache-dir", cache });
    if (release) try argv.append(arena, "--release");
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    const clean = switch (result.term) {
        .exited => |code| code <= 1,
        else => false,
    };
    if (!clean) {
        report_failure("{s} ({s}): mylang-core test did not finish cleanly:\n{s}\n", .{ name, if (release) "release" else "debug", result.stderr });
        return error.CoreCrashed;
    }
    return (try std.json.parseFromSlice(std.json.Value, arena, result.stdout, .{})).value;
}

/// The number of broken expectations over every pinned file at one level.
fn violations(arena: std.mem.Allocator, pins: Parsed, release: bool, cache: []const u8) !usize {
    var broken: std.ArrayList(Violation) = .empty;
    for (pins.files) |pinned| {
        try judge(arena, pinned, try runFile(arena, pinned.name, release, cache), &broken);
    }
    for (broken.items) |violation| report_failure("conformance ({s}): {s}: {s}\n", .{ if (release) "release" else "debug", violation.name, violation.why });
    return broken.items.len;
}

// spec: NEW-CORE-CONF-1
test "the pinned S1 conformance list passes at debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const cache = try std.fmt.allocPrint(arena.allocator(), "{s}/cache", .{try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator())});
    const path = try std.fmt.allocPrint(arena.allocator(), "{s}/conformance.pins", .{options.fixtures});
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, arena.allocator(), .limited(1 << 20));
    const pins = try parsePins(arena.allocator(), text);
    try std.testing.expectEqual(@as(usize, 31), pins.files.len);
    try std.testing.expectEqual(@as(usize, 0), try violations(arena.allocator(), pins, false, cache));
    try std.testing.expectEqual(@as(usize, 0), try violations(arena.allocator(), pins, true, cache));
}

const sample_report =
    \\{"version":"native-tests-v1","tests":[
    \\{"name":"m::kept","status":"passed","reason":"","at":""},
    \\{"name":"m::regressed","status":"failed","reason":"R_LIST_BOUNDS (index 7, length 3)","at":""},
    \\{"name":"m::now_refused","status":"unsupported","reason":"record","at":"3:1"},
    \\{"name":"m::known","status":"failed","reason":"expected true, got false","at":""},
    \\{"name":"m::fresh_failure","status":"failed","reason":"expected true, got false","at":""},
    \\{"name":"m::unsupported_new","status":"unsupported","reason":"dict type","at":""}
    \\],"passed":1,"failed":3,"skipped":0,"cached":0,"unsupported":2}
;

// spec-case: NEW-CORE-CONF-1
test "a pinned test that fails, vanishes or is refused, and an unpinned failure, break the gate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pins = try parsePins(a,
        \\file m
        \\pass m::kept
        \\pass m::regressed
        \\pass m::now_refused
        \\pass m::vanished
        \\known-fail m::known
        \\
    );
    const report = (try std.json.parseFromSlice(std.json.Value, a, sample_report, .{})).value;
    var broken: std.ArrayList(Violation) = .empty;
    try judge(a, pins.files[0], report, &broken);
    try std.testing.expectEqual(@as(usize, 4), broken.items.len);
    try std.testing.expectEqualStrings("m::regressed", broken.items[0].name);
    try std.testing.expectEqualStrings("pinned as passing, now failed", broken.items[0].why);
    try std.testing.expectEqualStrings("pinned as passing, now unsupported", broken.items[1].why);
    try std.testing.expectEqualStrings("pinned as passing, but no longer discovered", broken.items[2].why);
    try std.testing.expectEqualStrings("m::fresh_failure", broken.items[3].name);
}

// spec-case: NEW-CORE-CONF-1
test "a run that does not finish cleanly is an error, not a report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const cache = try std.fmt.allocPrint(arena.allocator(), "{s}/cache", .{try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator())});
    try std.testing.expectError(error.CoreCrashed, runFile(arena.allocator(), "no_such_file_in_tests_lang", false, cache));
}
