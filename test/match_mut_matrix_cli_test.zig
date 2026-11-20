//! The `match mut` binding matrix in the gate (lane FX12, 15 November 2026). The matrix
//! (`experiments/audit-work-20261111/FX12-matrix/matrix.py`) writes one program per payload type, use of the binding and
//! place of the matched value, and judges each against an oracle: the same use of a plain `mut` local. Before FX12, every
//! cell that gave the binding to an operation that makes a new value (`copy`, a text or bytes method, a library function,
//! `in` on a set) ended with SIGSEGV: the binding was read as a receiver through its own SSA variable, which a `match mut`
//! binding never has, and so passed `undef`, the null owner. `test/fixtures/match-mut-matrix/<type>_cells.selka` holds every cell
//! that runs correctly, grouped into one program with a `main` that calls each, and `<type>_cells.out` the output of the cells'
//! oracles. This test builds each program as the language suites are built (`--debug-o0 --verify-facts`) and as `selka
//! build` does by default, runs both under the leak check, and compares their output with the oracles'.
const std = @import("std");
const testing = std.testing;

const fixtures = "test/fixtures/match-mut-matrix";

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

test "match mut matrix: a str binding used every way, at every place, runs as a plain local does" {
    try expectCells("text");
}

test "match mut matrix: a bytes binding used every way, at every place, runs as a plain local does" {
    try expectCells("bytes");
}

test "match mut matrix: a byte_buffer binding used every way, at every place, runs as a plain local does" {
    try expectCells("buffer");
}

test "match mut matrix: an int[] binding used every way, at every place, runs as a plain local does" {
    try expectCells("list");
}

test "match mut matrix: a dictionary binding used every way, at every place, runs as a plain local does" {
    try expectCells("dict");
}

test "match mut matrix: a set binding used every way, at every place, runs as a plain local does" {
    try expectCells("set");
}

test "match mut matrix: record, option, enum and int bindings used every way, at every place, run as plain locals do" {
    try expectCells("record");
    try expectCells("option");
    try expectCells("enum");
    try expectCells("scalar");
}
