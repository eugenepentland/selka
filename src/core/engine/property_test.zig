//! The property test of the engine (plan C1): random graphs of queries over an in-memory filesystem, random edit
//! sequences, and after every edit the incremental answers equal a from-scratch evaluation, and the number of queries
//! recomputed, served and cut off equals what the rules of validation require (`model_test.zig`), which is the least the
//! edit needs: a query whose reads are as they were is served, and a query is run only when one of its reads changed.
//!
//! Edits change a file's bytes, touch it (new stamps, same bytes), replace it (new inode), remove it, add or remove a
//! directory entry, set, unset or change a variable, a placement variable or a tool, and move the clock by nothing,
//! within the racy window or past it. Between edits the engine is restarted (a new process over the same store) or
//! started on a new revision, and now and then a record is removed. Some rounds run with verify mode sampling every
//! served query, which must then find nothing.
const std = @import("std");
const fixture_rules = @import("fixture_test.zig");
const model_rules = @import("model_test.zig");
const script = @import("kinds/script.zig");
const memory_world = @import("memory_world.zig");
const paths = @import("core_test_options");
const Fixture = fixture_rules.Fixture;

/// A small deterministic generator (splitmix64): the same seed gives the same rounds on every machine.
const Generator = struct {
    state: u64,

    fn next(self: *Generator) u64 {
        self.state +%= 0x9e3779b97f4a7c15;
        var mixed = self.state;
        mixed = (mixed ^ (mixed >> 30)) *% 0xbf58476d1ce4e5b9;
        mixed = (mixed ^ (mixed >> 27)) *% 0x94d049bb133111eb;
        return mixed ^ (mixed >> 31);
    }

    fn below(self: *Generator, limit: usize) usize {
        return @intCast(self.next() % limit);
    }

    fn percent(self: *Generator) usize {
        return self.below(100);
    }
};

const file_paths = [_][]const u8{ "/w/f0", "/w/f1", "/w/f2", "/w/f3", "/w/f4", "/w/f5" };
const entry_paths = [_][]const u8{ "/w/d/e0", "/w/d/e1", "/w/d/e2.selka", "/w/d/e3.selka" };
const variable_names = [_][]const u8{ "V0", "V1", "V2" };
const tool_paths = [_][]const u8{ "/bin/t0", "/bin/t1" };
const contents = [_][]const u8{ "", "a", "b", "aa", "ab", "bb", "abc", "aaa" };
const part_names = [_][]const u8{ "p0", "p1", "p2", "p3", "pz" };
const folds = [_]script.Fold{ .concat, .length, .length, .parity, .parity, .empty };

fn pick(generator: *Generator, comptime from: []const []const u8) []const u8 {
    return from[generator.below(from.len)];
}

fn randomNames(arena: std.mem.Allocator, generator: *Generator) std.mem.Allocator.Error![]const []const u8 {
    const names = try arena.alloc([]const u8, 1 + generator.below(3));
    for (names) |*name| name.* = pick(generator, &part_names);
    return names;
}

fn randomOp(arena: std.mem.Allocator, generator: *Generator, below: u32) std.mem.Allocator.Error!script.Op {
    const choice = generator.below(if (below == 0) 7 else 11);
    return switch (choice) {
        0, 1 => .{ .file = pick(generator, &file_paths) },
        2 => .{ .exists = if (generator.percent() < 70) pick(generator, &file_paths) else "/w/probe" },
        3 => .{ .listing = .{ .path = "/w/d", .filter = @intCast(generator.below(2)) } },
        4 => .{ .variable = pick(generator, &variable_names) },
        5 => .{ .placement = "PLACE_P" },
        6 => .{ .tool = pick(generator, &tool_paths) },
        7, 8 => .{ .node = @intCast(generator.below(below)) },
        else => .{ .part = .{ .node = @intCast(generator.below(below)), .names = try randomNames(arena, generator) } },
    };
}

fn randomGraph(arena: std.mem.Allocator, generator: *Generator, count: usize) std.mem.Allocator.Error!script.Graph {
    const nodes = try arena.alloc(script.Node, count);
    for (nodes, 0..) |*node, at| {
        const ops = try arena.alloc(script.Op, 1 + generator.below(4));
        for (ops) |*op| op.* = try randomOp(arena, generator, @intCast(at));
        var exposed: std.ArrayList(script.Expose) = .empty;
        for (0..ops.len) |index| {
            if (generator.percent() < 50) try exposed.append(arena, .{ .name = part_names[index], .op = @intCast(index) });
        }
        node.* = .{ .ops = ops, .fold = folds[generator.below(folds.len)], .expose = exposed.items };
    }
    return .{ .nodes = nodes };
}

fn edit(generator: *Generator, files: *memory_world.MemoryWorld) std.mem.Allocator.Error!void {
    const choice = generator.percent();
    if (choice < 25) {
        try files.write(pick(generator, &file_paths), pick(generator, &contents));
    } else if (choice < 35) {
        files.touch(pick(generator, &file_paths));
    } else if (choice < 45) {
        try files.replace(pick(generator, &file_paths), pick(generator, &contents));
    } else if (choice < 55) {
        files.remove(pick(generator, &file_paths));
    } else if (choice < 65) {
        try files.write(pick(generator, &entry_paths), "e");
    } else if (choice < 70) {
        files.remove(pick(generator, &entry_paths));
    } else if (choice < 80) {
        try files.setVariable(pick(generator, &variable_names), pick(generator, &contents));
    } else if (choice < 85) {
        files.unsetVariable(pick(generator, &variable_names));
    } else if (choice < 88) {
        try files.setVariable("PLACE_P", pick(generator, &contents));
    } else if (choice < 92) {
        try files.setTool(pick(generator, &tool_paths), @splat(@intCast(generator.below(3))));
    }
    const pass = generator.percent();
    if (pass < 30) return;
    files.advance(if (pass < 50) 20 * std.time.ns_per_ms else 2 * std.time.ns_per_s);
}

fn populate(generator: *Generator, files: *memory_world.MemoryWorld) std.mem.Allocator.Error!void {
    for (file_paths) |path| if (generator.percent() < 70) try files.write(path, pick(generator, &contents));
    for (entry_paths) |path| if (generator.percent() < 50) try files.write(path, "e");
    try files.makeDirectory("/w/d");
    for (variable_names) |name| if (generator.percent() < 70) try files.setVariable(name, pick(generator, &contents));
    for (tool_paths) |path| try files.setTool(path, @splat(1));
    files.advance(2 * std.time.ns_per_s);
}

/// What the script kind's numbers add up to since `before`.
fn delta(fx: *Fixture, before: model_rules.Tally) model_rules.Tally {
    const numbers = fx.numbers();
    return .{
        .recomputed = numbers.count(.recomputed) - before.recomputed,
        .served = numbers.count(.served) - before.served,
        .cutoffs = numbers.count(.early_cutoffs) - before.cutoffs,
    };
}

fn totals(fx: *Fixture) model_rules.Tally {
    const numbers = fx.numbers();
    return .{ .recomputed = numbers.count(.recomputed), .served = numbers.count(.served), .cutoffs = numbers.count(.early_cutoffs) };
}

/// One round: a random graph and `steps` rounds of edit, restart and query. Returns the first disagreement as a
/// message, or null when the engine agreed with the truth and the rules throughout.
fn round(gpa: std.mem.Allocator, seed: u64, steps: usize) !?[]const u8 {
    var generator: Generator = .{ .state = seed };
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    const graph = try randomGraph(a, &generator, 8 + generator.below(24));
    const fx = try Fixture.create(gpa, graph);
    defer fx.destroy();
    try populate(&generator, &fx.files);
    var model = try model_rules.Model.init(a, graph, fx.files.world());
    const verify: u32 = if (generator.percent() < 50) 1 else 0;
    try fx.restart(.{ .verify_every = verify });
    for (0..steps) |step| {
        for (0..1 + generator.below(3)) |_| try edit(&generator, &fx.files);
        if (generator.percent() < 60) {
            try fx.restart(.{ .verify_every = verify });
        } else fx.runner.newRevision();
        model.restart();
        if (generator.percent() < 8) {
            const lost: u32 = @intCast(generator.below(graph.nodes.len));
            const path = try fx.recordPath(a, lost);
            @import("store.zig").discard(std.testing.io, path);
            model.forget(lost);
        }
        const before = totals(fx);
        for (0..1 + generator.below(5)) |_| {
            const node: u32 = @intCast(generator.below(graph.nodes.len));
            const got = try fx.run(node);
            const want = try model_rules.truth(a, graph, fx.files.world(), node);
            if (!std.mem.eql(u8, got, want)) {
                const message = try std.fmt.allocPrint(gpa, "seed {d} step {d}: node {d} gave \"{s}\", from scratch \"{s}\"", .{ seed, step, node, got, want });
                return message;
            }
            const predicted = try model.answer(node);
            if (!std.mem.eql(u8, predicted, want)) {
                const message = try std.fmt.allocPrint(gpa, "seed {d} step {d}: the model gave \"{s}\" for node {d}, from scratch \"{s}\"", .{ seed, step, predicted, node, want });
                return message;
            }
        }
        const did = delta(fx, before);
        if (did.recomputed != model.tally.recomputed or did.served != model.tally.served or did.cutoffs != model.tally.cutoffs) {
            const message = try std.fmt.allocPrint(gpa, "seed {d} step {d}: the engine recomputed {d}, served {d}, cut off {d}; the rules need {d}, {d}, {d}", .{
                seed, step, did.recomputed, did.served, did.cutoffs, model.tally.recomputed, model.tally.served, model.tally.cutoffs,
            });
            return message;
        }
    }
    return null;
}

/// How many rounds to run: `SELKA_ENGINE_PROPERTY_ROUNDS` when set, else enough to be a unit test.
fn rounds() usize {
    const text = paths.lookup(std.testing.environ, "SELKA_ENGINE_PROPERTY_ROUNDS") orelse return 40;
    return std.fmt.parseInt(usize, text, 10) catch 40;
}

/// Free a disagreement message, if there is one.
fn release(gpa: std.mem.Allocator, message: ?[]const u8) void {
    if (message) |text| gpa.free(text);
}

/// The first disagreement of the first `count` rounds, or null when the engine agreed throughout.
fn firstDisagreement(gpa: std.mem.Allocator, count: usize) !?[]const u8 {
    for (0..count) |at| {
        if (try round(gpa, 0x5e1ca000 + at, 24)) |message| return message;
    }
    return null;
}

test "after every edit the incremental answers equal a from-scratch evaluation, and the work is what the rules need" {
    const message = try firstDisagreement(std.testing.allocator, rounds());
    defer release(std.testing.allocator, message);
    try std.testing.expectEqual(@as(?[]const u8, null), message);
}
