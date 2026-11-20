//! Two writes in one `match mut` arm in the gate (lane FX17, 15 November 2026). The pair grid
//! (`experiments/audit-work-20261111/FX15-grid/grid.py --pairs`) writes two writes in one arm of `match mut b:`, whose
//! payload binding `items` is a list of text, of records with a text field or of integers, a dictionary or a set: every
//! write of the payload's kind (an element assignment, a field of an element, `append`, `lists.exchange`, the builtin
//! `exchange` and `take` of an element, `lists.pop`; a dictionary store, `dicts.add`, `dicts.pop`; `sets.add`,
//! `sets.include`, `sets.discard`, `sets.remove`) by every write, with a read of the binding between them, after both or
//! none, and judges each against the same writes on a plain `mut` local. Before FX17, 114 of the 459 cells passed the
//! check and stopped the build with `E_CORE_UNSUPPORTED`: a write whose receiver is the binding itself after a finished
//! write through a receiver temporary staged from it (rule Z3: the binding's recorded version had not moved with that
//! write), and any write of a managed field of an element (`items[0].text = v`: the write read the payload again instead
//! of taking the read it had made, and took a field of a borrow). `test/fixtures/match-mut-pairs/<type>_cells.selka` holds
//! the 426 cells that run as the plain local does (the other 33 are takes of an `int`, refused at the check for both),
//! grouped into one program with a `main` that calls each, and `<type>_cells.out` the plain local's output. This test
//! builds each program `--debug-o0 --verify-facts` and by default, runs both under the leak check, and compares.
const std = @import("std");
const testing = std.testing;

const fixtures = "test/fixtures/match-mut-pairs";

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

/// The grouped cells of `type_name` build in every mode, run under the leak check and print what the plain local prints.
fn expectCells(type_name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("", try failures(arena.allocator(), type_name));
}

test "pair grid: two writes in one match mut arm over a list of records with a text field run as on a plain mut local" {
    try expectCells("recs");
}

test "pair grid: two writes in one match mut arm over a list of text and a list of integers run as on a plain mut local" {
    try expectCells("texts");
    try expectCells("ints");
}

test "pair grid: two writes in one match mut arm over a dictionary and a set run as on a plain mut local" {
    try expectCells("dict");
    try expectCells("set");
}
