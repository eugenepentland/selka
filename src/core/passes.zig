//! The release passes, in order, shared by `mylang-core build`, `dump-ir --facts`
//! and the tests: leaf inlining, loop unswitching, facts, trip-count guards (then
//! facts again), and the vector plans. Debug builds run none of them.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const inline_leaves = @import("inline.zig");
const vector = @import("vector.zig");
const version = @import("version.zig");

/// Passes only allocate.
pub const Error = std.mem.Allocator.Error;

/// How the fact pass runs: `trusted` facts drive the vector lowering; `verify` keeps
/// comparisons unfolded and plans no vectors; `sabotage` is verify with one wrong rule.
pub const Mode = enum { off, trusted, verify, sabotage };

/// What the passes produced, per function, and what they did.
pub const Result = struct {
    known: []?facts.Facts,
    plans: [][]const vector.Plan,
    inlined: u32 = 0,
    /// Loop copies added by unswitching and by trip-count guards.
    unswitched: u32 = 0,
    versioned: u32 = 0,
    proven: u32 = 0,
    vectorized: u32 = 0,
};

/// Run the release passes over `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, mode: Mode) Error!Result {
    var result: Result = .{
        .known = try arena.alloc(?facts.Facts, module.functions.items.len),
        .plans = try arena.alloc([]const vector.Plan, module.functions.items.len),
    };
    @memset(result.known, null);
    @memset(result.plans, &.{});
    result.inlined = try inline_leaves.inlineLeaves(arena, module);
    if (mode == .off) return result;
    const verify = mode != .trusted;
    const options: facts.Options = .{ .fold = !verify, .sabotage = mode == .sabotage };
    for (module.functions.items, result.known, result.plans) |*function, *slot, *plan| {
        if (function.signature.linkage != .internal) continue;
        result.unswitched += try version.unswitch(arena, function);
        var known = try facts.analyze(arena, function, options);
        result.proven += known.proven;
        // A reduction proven only under a trip bound gets a guarded copy; the facts then run again.
        const guarded = try version.versionReductions(arena, function, known);
        if (guarded != 0) {
            known = try facts.analyze(arena, function, options);
            result.proven += known.proven;
        }
        result.versioned += guarded;
        slot.* = known;
        // Vector code comes only from trusted facts, never in a verify build.
        if (!verify) plan.* = try vector.plan(arena, function, known);
        result.vectorized += @intCast(plan.len);
    }
    return result;
}
