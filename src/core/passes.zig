//! The release passes, in order, shared by `mylang-core build`, `dump-ir --facts`
//! and the tests: leaf inlining, loop unswitching, facts, trip-count guards (then
//! facts again), ownership (`own.zig`, after the facts it may not disturb), and the
//! vector plans. Debug builds run only ownership (`ownership`).
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const inline_leaves = @import("inline.zig");
const vector = @import("vector.zig");
const version = @import("version.zig");
const own = @import("own.zig");

/// Passes only allocate.
pub const Error = std.mem.Allocator.Error;

/// How the fact pass runs: `trusted` facts drive the vector lowering; `verify` keeps
/// comparisons unfolded and plans no vectors; `sabotage`, `sabotage_widening` and
/// `sabotage_length` are verify with one wrong rule (`facts.Sabotage`).
pub const Mode = enum { off, trusted, verify, sabotage, sabotage_widening, sabotage_length };

/// What the passes produced, per function, and what they did.
pub const Result = struct {
    known: []?facts.Facts,
    plans: [][]const vector.Plan,
    counts: Counts = .{},
    /// What ownership did: copy-on-write forms, retains and releases.
    own: own.Stats = .{},
};

/// How often each release pass changed something (`--stats`).
pub const Counts = struct {
    inlined: u32 = 0,
    /// Loop copies added by unswitching and by trip-count guards.
    unswitched: u32 = 0,
    versioned: u32 = 0,
    proven: u32 = 0,
    vectorized: u32 = 0,
};

/// The debug pipeline's only pass: ownership and counting, no facts.
pub fn ownership(arena: std.mem.Allocator, module: *ir.Module) Error!own.Stats {
    return own.run(arena, module, .{});
}

/// Run the release passes over `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, mode: Mode) Error!Result {
    var result: Result = .{
        .known = try arena.alloc(?facts.Facts, module.functions.items.len),
        .plans = try arena.alloc([]const vector.Plan, module.functions.items.len),
    };
    @memset(result.known, null);
    @memset(result.plans, &.{});
    result.counts.inlined = try inline_leaves.inlineLeaves(arena, module);
    if (mode == .off) {
        result.own = try own.run(arena, module, .{});
        return result;
    }
    const verify = mode != .trusted;
    const sabotage: facts.Sabotage = switch (mode) {
        .sabotage => .remainder,
        .sabotage_widening => .widening,
        .sabotage_length => .length,
        else => .none,
    };
    const options: facts.Options = .{ .fold = !verify, .sabotage = sabotage };
    for (module.functions.items, result.known, result.plans) |*function, *slot, *plan| {
        if (function.signature.linkage != .internal) continue;
        result.counts.unswitched += try version.unswitch(arena, function);
        var known = try facts.analyze(arena, function, options);
        result.counts.proven += known.proven;
        // A reduction proven only under a trip bound gets a guarded copy; the facts then run again.
        const guarded = try version.versionReductions(arena, function, known);
        if (guarded != 0) {
            known = try facts.analyze(arena, function, options);
            result.counts.proven += known.proven;
        }
        result.counts.versioned += guarded;
        // Ownership after the facts: the instructions and blocks it adds have none.
        result.own.add(try own.function(arena, module, function, .{ .verify = verify }));
        try extend(arena, &known, function);
        slot.* = known;
        // Vector code comes only from trusted facts, never in a verify build.
        if (!verify) plan.* = try vector.plan(arena, function, known);
        result.counts.vectorized += @intCast(plan.len);
    }
    return result;
}

/// Grow the fact tables over the instructions and blocks added since they were
/// computed: no interval, list fact or bound, and every new block reachable.
fn extend(arena: std.mem.Allocator, known: *facts.Facts, f: *const ir.Function) Error!void {
    const insts = f.insts.items.len;
    const blocks = f.blocks.items.len;
    if (known.ranges.len < insts) known.ranges = try grown(?facts.Interval, arena, known.ranges, insts, null);
    if (known.aggregates.lists.len < insts) {
        known.aggregates.lists = try grown(facts.ListFact, arena, known.aggregates.lists, insts, .{});
        known.aggregates.fields = try grown(?[]const ?facts.Interval, arena, known.aggregates.fields, insts, null);
    }
    if (known.floats.len < insts) known.floats = try grown(?facts.FloatInterval, arena, known.floats, insts, null);
    if (known.bounds.len != 0 and known.bounds.len < insts) known.bounds = try grown(?facts.LengthBound, arena, known.bounds, insts, null);
    if (known.reachable.len < blocks) known.reachable = try grown(bool, arena, known.reachable, blocks, true);
}

fn grown(comptime T: type, arena: std.mem.Allocator, old: []T, len: usize, fill: T) Error![]T {
    const out = try arena.alloc(T, len);
    @memcpy(out[0..old.len], old);
    @memset(out[old.len..], fill);
    return out;
}
