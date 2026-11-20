//! The exchange grid in the gate (lane FX15, 15 November 2026). The grid
//! (`experiments/audit-work-20261111/FX15-grid/grid.py`) writes an exchange or a take of a list element for each element
//! type, place of the list (a `mut` local, a `mut` parameter, a field of a `mut` record, a `match mut` binding),
//! replacement (a fresh value, `own name`, a call's result) and use of the result (bound, one field read, dropped,
//! returned, passed on, passed `own`), for `lists.exchange(mut xs, i, v)`, `exchange(mut xs[i], v)` and `take(mut xs[i])`,
//! and judges each against an oracle that copies the element and stores the replacement. Before FX15, every cell whose
//! element was a record with a managed field and whose code read the old element's fields stopped the build with the
//! internal error `E_OWNERSHIP_VALIDATION`: the old element was `emptied` (each managed field taken by its read), and the
//! certificate writer refused a transferred read in that state. `test/fixtures/exchange-matrix/<type>_cells.selka` holds every
//! cell that runs correctly, grouped into one program with a `main` that calls each, and `<type>_cells.out` the output of
//! the cells' oracles. Since FR27 the cells of a `match mut` binding's elements (`exchange(mut items[0], v)` and
//! `take(mut items[0])`, once refused with `E_SINGLE_OWNER_OVERLAP`) are in the fixtures too: 2,120 of the grid's 2,160 cells run,
//! the other 40 are takes of a type with no empty value. This test builds each program as the language suites are built (`--debug-o0 --verify-facts`) and as
//! `selka build` does by default, runs both under the leak check, and compares their output with the oracles'.
const std = @import("std");
const testing = std.testing;

const fixtures = "test/fixtures/exchange-matrix";

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

test "exchange grid: a list of records with a text field, exchanged and taken every way, runs as a copy and a store do" {
    try expectCells("rec_text");
}

test "exchange grid: a list of records with two managed fields and a scalar, exchanged and taken every way, runs as a copy and a store do" {
    try expectCells("rec_two");
}

test "exchange grid: a list of nested records, exchanged and taken every way, runs as a copy and a store do" {
    try expectCells("rec_nested");
}

test "exchange grid: lists of scalar records, enums with a text payload, options of text, lists, dictionaries, text and integers run as a copy and a store do" {
    try expectCells("rec_scalar");
    try expectCells("enum_text");
    try expectCells("opt_text");
    try expectCells("list_int");
    try expectCells("dict_int");
    try expectCells("text");
    try expectCells("int");
}
