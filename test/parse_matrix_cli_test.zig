//! The parse grid in the gate (lane FR28, 15 November 2026). The grid (`experiments/audit-work-20261111/FR28-grid/grid.py`) maps every
//! parse of text by where the text comes from: `parse_int`, `parse_float` and `parse_f32` of a `str`, and `bytes.parse_int`,
//! `bytes.parse_float` and their ranged forms of `bytes` (the whole data, and the inside of data padded by one octet each side).
//! A cell is one source of the text (a parameter, an `own` or `mut` parameter, a field, a slice, an element, a loop variable, a
//! `match` binding, a call's result with and without `from`, a trim, a `split` piece ...) and one consumer of the answer (printed,
//! `unwrap_or`, bound, `is Some`, `match`, arithmetic); `main` compares each cell's answer for four texts with the same consumer
//! applied to the parse of a plain local copy. Before FR28, `parse_f32(text)` of a `str` parameter (and of a local bound from one,
//! and of a format string's text) passed the check and stopped the build with `E_CORE_HIDDEN_COPY`: the lowering copied the
//! borrowed text and the span form of its runtime helper then read the original, leaving the copy unnamed and dropped. Every other
//! parse already had its name in `build_borrowed_view.spanReceiver`. `test/fixtures/parse-matrix/<parse>_cells.selka` holds every cell
//! that checks (860 of 862: a generic body refuses `parse_f32`, `E_UNKNOWN_SYMBOL`, a gap this lane left), grouped into one
//! program with a `main` that calls each, and `<parse>_cells.out` the output of the cells (every line starts with `ok`). This test
//! builds each program as the language suites are built (`--debug-o0 --verify-facts`) and as `selka build` does by default, runs both
//! under the leak check, and compares their output with the expected one.
const std = @import("std");
const testing = std.testing;

const fixtures = "test/fixtures/parse-matrix";

/// A build of the grouped program: the compiler's flags.
const Mode = struct { name: []const u8, flags: []const []const u8 };

const modes = [_]Mode{
    .{ .name = "--debug-o0 --verify-facts", .flags = &.{ "--debug-o0", "--verify-facts" } },
    .{ .name = "default build", .flags = &.{} },
};

fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

fn run(a: std.mem.Allocator, argv: []const []const u8, leak_check: bool) !std.process.RunResult {
    var environment = try @import("test_paths").privateEnvironment(a);
    if (leak_check) try environment.put("SELKA_CORE_LEAKCHECK", "1");
    return std.process.run(a, testing.io, .{ .argv = argv, .environ_map = &environment });
}

/// Build the grouped program of `type_name` in every mode and run it under the leak check: what went wrong, or "".
fn failures(a: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const source = try std.fmt.allocPrint(a, fixtures ++ "/{s}_cells.selka", .{type_name});
    const expected = try std.Io.Dir.cwd().readFileAlloc(testing.io, try std.fmt.allocPrint(a, fixtures ++ "/{s}_cells.out", .{type_name}), a, .unlimited);
    const binary = try std.fs.path.join(a, &.{ directory, "cells" });
    var out: std.ArrayList(u8) = .empty;
    for (modes) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ compilerPath(), "build", source, "-o", binary, "--cache-dir", try std.fs.path.join(a, &.{ directory, "cache" }) });
        try argv.appendSlice(a, mode.flags);
        try argv.append(a, "--zig=" ++ @import("test_options").zig_path);
        const built = try run(a, argv.items, false);
        if (built.term != .exited or built.term.exited != 0) {
            try out.print(a, "{s} ({s}): build failed: {s}\n", .{ source, mode.name, built.stderr[0..@min(built.stderr.len, 400)] });
            continue;
        }
        const ran = try run(a, &.{binary}, true);
        if (ran.term != .exited or ran.term.exited != 0) try out.print(a, "{s} ({s}): {any}: {s}\n", .{ source, mode.name, ran.term, ran.stderr[0..@min(ran.stderr.len, 400)] });
        if (!std.mem.eql(u8, expected, ran.stdout)) try out.print(a, "{s} ({s}): output differs from {s}_cells.out:\n{s}\n", .{ source, mode.name, type_name, firstDifference(expected, ran.stdout) });
    }
    return out.items;
}

/// The first line of `got` that differs from `want` (the rest of `got` from there), for a readable failure.
fn firstDifference(want: []const u8, got: []const u8) []const u8 {
    var line_start: usize = 0;
    for (got, 0..) |byte, index| {
        if (index >= want.len or want[index] != byte) return got[line_start..@min(got.len, line_start + 300)];
        if (byte == '\n') line_start = index + 1;
    }
    return "(output ends early)";
}

/// The grouped cells of `type_name` build in every mode, run under the leak check and print what their oracles print.
fn expectCells(type_name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("", try failures(arena.allocator(), type_name));
}

test "parse grid: parse_int, parse_float and parse_f32 of text from every source run as the same parse of a local copy does" {
    try expectCells("parse_int");
    try expectCells("parse_float");
    try expectCells("parse_f32");
}

test "parse grid: bytes.parse_int and bytes.parse_float of data from every source run as the same parse of a local copy does" {
    try expectCells("bytes_parse_int");
    try expectCells("bytes_parse_float");
}

test "parse grid: the ranged byte parses over the whole data run as the same parse of a local copy does" {
    try expectCells("bytes_parse_int_range");
    try expectCells("bytes_parse_float_range");
}

test "parse grid: the ranged byte parses over the inside of padded data run as the same parse of a local copy does" {
    try expectCells("bytes_parse_int_inner");
    try expectCells("bytes_parse_float_inner");
}
