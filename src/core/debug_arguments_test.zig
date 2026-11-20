//! A `debug(...)` line in a build that drops debug output (`build --release` sets `drop_debug`) still evaluates its arguments,
//! in order, and drops only the formatting and the write to standard error: a call runs, a `mut` argument is written, a bad
//! index traps, and each evaluated value is destroyed once. These tests lower with `drop_debug` set and look at the Core IR and
//! at a run of it, so they need no release build and run in every gate; the release build itself is `cli_flags_test.zig`.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

/// One line of each argument shape: a call that writes a `mut` argument, a `str` returned by a call, an f-string whose holes
/// call, and an element read. `counter` ends at 2, so the standard output shows that the writes happened.
const effects =
    \\func bump(mut n: int) -> int:
    \\    n += 1
    \\    return n
    \\func describe(x: int) -> str:
    \\    return f"item {x}"
    \\func main(out: Stream) -> int:
    \\    mut counter = 0
    \\    const xs = [1, 2, 3]
    \\    debug(bump(mut counter))
    \\    debug(describe(counter), f"{bump(mut counter)} of {describe(2)}")
    \\    debug(xs[1])
    \\    print(out, counter)
    \\    return 0
;

/// A bad index inside `debug`: the line is the only reader of `xs[i]`.
const trap =
    \\func main(out: Stream) -> int:
    \\    const xs = [1, 2, 3]
    \\    mut i = 1
    \\    i += 3
    \\    debug(xs[i])
    \\    print(out, "reached")
    \\    return 0
;

/// What a lowered program does with its `debug` lines: how many calls to each helper it makes, how many lines it begins
/// writing to standard error, and how many element reads it keeps.
const Census = struct { bump: usize = 0, describe: usize = 0, lines_written: usize = 0, element_reads: usize = 0 };

fn census(module: *const ir.Module) Census {
    var counted: Census = .{};
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| {
            if (inst.op == .list_get) counted.element_reads += 1;
            if (inst.op != .call) continue;
            const target = module.functions.items[inst.a.index()].name;
            if (std.mem.eql(u8, target, "bump")) counted.bump += 1;
            if (std.mem.eql(u8, target, "describe")) counted.describe += 1;
            if (std.mem.eql(u8, target, "myl_core_output_begin")) counted.lines_written += 1;
        }
    }
    return counted;
}

fn lower(a: std.mem.Allocator, text: []const u8, drop_debug: bool) !ir.Module {
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .source = unit.src, .drop_debug = drop_debug }, &refusal);
}

/// Lower `text`, run the debug pipeline's ownership pass (`optimized` false) or the release passes with their facts verified
/// (`optimized` true), link it unoptimized with the leak check on and run it. A value the dropped line left alive would
/// print "blocks live at exit", so standard error shows leaks as well as debug text.
fn execute(a: std.mem.Allocator, text: []const u8, drop_debug: bool, optimized: bool) !support.Run {
    var module = try lower(a, text, drop_debug);
    const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
    try support.verified(a, &module, result.plans);
    return support.runOwned(a, &module, .{ .own = false, .verify = optimized, .analysis = support.analysis(&result) });
}

fn expectQuiet(a: std.mem.Allocator, optimized: bool) !void {
    const run = try execute(a, effects, true, optimized);
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("2\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
}

fn expectTrap(a: std.mem.Allocator, optimized: bool) !void {
    const run = try execute(a, trap, true, optimized);
    try std.testing.expectEqual(@as(u8, 1), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "R_LIST_BOUNDS") != null);
}

test "a dropped debug line keeps the calls and the element read of its arguments and writes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const written = try lower(a, effects, false);
    try std.testing.expectEqualDeep(Census{ .bump = 2, .describe = 2, .lines_written = 3, .element_reads = 1 }, census(&written));
    const dropped = try lower(a, effects, true);
    try std.testing.expectEqualDeep(Census{ .bump = 2, .describe = 2, .lines_written = 0, .element_reads = 1 }, census(&dropped));
}

test "a dropped debug line evaluates its arguments once, destroys what it built and writes nothing to standard error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectQuiet(a, false);
    // The same line through the release passes, as `build --release` runs them (the link stays unoptimized).
    try expectQuiet(a, true);
    const loud = try execute(a, effects, false, false);
    try std.testing.expectEqualStrings("2\n", loud.stdout);
    try std.testing.expectEqualStrings("1\nitem 1 2 of item 2\n2\n", loud.stderr);
}

test "a bad index inside a dropped debug line traps as it does when the line is written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectTrap(a, false);
    try expectTrap(a, true);
}
