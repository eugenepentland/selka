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
const index_checks = @import("index_checks.zig");
const fields = @import("fields.zig");
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");

/// Passes only allocate.
pub const Error = std.mem.Allocator.Error;

/// How the fact pass runs: `trusted` facts drive the vector lowering; `verify` keeps
/// comparisons unfolded and plans no vectors; `sabotage`, `sabotage_widening` and
/// `sabotage_length` are verify with one wrong rule (`facts.Sabotage`), and
/// `sabotage_overflow` verify with the overflow facts' rules off by one, and `sabotage_index`
/// verify with a dominating check taken to cover the next index too (`index_checks`), and
/// `sabotage_field` verify with each field interval's top dropped (`fields.zig`).
pub const Mode = enum { off, trusted, verify, sabotage, sabotage_widening, sabotage_length, sabotage_overflow, sabotage_index, sabotage_field };

/// What the passes produced, per function, and what they did.
pub const Result = struct {
    known: []?facts.Facts,
    plans: [][]const vector.Plan,
    counts: Counts = .{},
    /// Exactly the same pass events, indexed by physical Core function.
    per_function: []FunctionStats = &.{},
    /// Verify builds re-emit checks the fact pass has proved.
    verifying: bool = false,
    /// What ownership did: copy-on-write forms, retains and releases.
    own: own.Stats = .{},
    /// Sparse source frames of instructions and blocks cloned by these passes.
    provenance: origins.Table = .{},
};

/// Pass events for one emitted body; cloned work belongs to its physical caller.
pub const FunctionStats = struct { counts: Counts = .{}, own: own.Stats = .{} };

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

/// Run debug ownership with the same per-function accounting as release.
pub fn debug(arena: std.mem.Allocator, module: *ir.Module) Error!Result {
    var result: Result = .{ .known = &.{}, .plans = &.{}, .per_function = try arena.alloc(FunctionStats, module.functions.items.len) };
    @memset(result.per_function, .{});
    const summaries = try effects.analyze(arena, module);
    for (module.functions.items, result.per_function, 0..) |*function, *local, index| {
        if (function.signature.linkage != .internal) continue;
        local.own = try own.function(arena, module, function, .{ .function_index = @intCast(index), .effects = &summaries });
        result.own.add(local.own);
    }
    return result;
}

/// Run the release passes over `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, mode: Mode) Error!Result {
    try @import("fuse_text.zig").whitespace(arena, module);
    _ = try @import("fuse_slice_key.zig").run(arena, module);
    var result: Result = .{
        .known = try arena.alloc(?facts.Facts, module.functions.items.len),
        .plans = try arena.alloc([]const vector.Plan, module.functions.items.len),
        .per_function = try arena.alloc(FunctionStats, module.functions.items.len),
    };
    @memset(result.known, null);
    @memset(result.plans, &.{});
    @memset(result.per_function, .{});
    const inlined = try arena.alloc(u32, module.functions.items.len);
    @memset(inlined, 0);
    result.counts.inlined = try inline_leaves.inlineLeavesCounted(arena, module, &result.provenance, inlined);
    if (mode == .off) {
        const summaries = try effects.analyze(arena, module);
        for (module.functions.items, result.per_function, inlined, 0..) |*function, *local, expanded, index| {
            if (function.signature.linkage != .internal) continue;
            local.counts.inlined = expanded;
            local.own = try own.function(arena, module, function, .{ .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries });
            result.own.add(local.own);
        }
        return result;
    }
    const verify = mode != .trusted;
    result.verifying = verify;
    const sabotage: facts.Sabotage = switch (mode) {
        .sabotage => .remainder,
        .sabotage_widening => .widening,
        .sabotage_length => .length,
        .sabotage_overflow => .overflow,
        .sabotage_index => .index,
        .sabotage_field => .field,
        else => .none,
    };
    // A first fact pass with every parameter unknown gives each call site's argument
    // intervals; `parameterRanges` turns them into the parameter intervals the real
    // pass starts from. It changes no function. It runs callees first, so each
    // function's return interval (NEW-CORE-F1-OVERFLOW-3) is known at its calls.
    const first = try arena.alloc(?facts.Facts, module.functions.items.len);
    const returns = try arena.alloc(?facts.Interval, module.functions.items.len);
    @memset(first, null);
    @memset(returns, null);
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const changed = try version.unswitch(arena, function, result.provenance.context(@intCast(index)));
        result.per_function[index].counts.unswitched = changed;
        result.counts.unswitched += changed;
    }
    // The whole-program field intervals (NEW-CORE-F2-FIELD-1) come from the writes under the
    // first pass's facts; a second round sees them, and each round's hulls hold on their own.
    const order = try calleesFirst(arena, module);
    const closed = try fields.closedTypes(arena, module);
    var field_table: facts.FieldIntervals = .{ .module = module };
    for (0..2) |_| {
        for (order) |index| {
            const function = &module.functions.items[index];
            const known = try facts.analyze(arena, function, .{ .fold = !verify, .sabotage = sabotage, .mark = false, .returns = returns, .fields = field_table });
            first[index] = known;
            returns[index] = facts.returnRange(&known, function, sabotage);
        }
        field_table = try fields.hulls(arena, module, first, closed, sabotage == .field);
    }
    const parameters = try parameterRanges(arena, module, first);
    // Closed caller bounds can prove an affine callback safe only after the
    // all-call parameter pass. Deliberately corrupted facts cannot prove safety.
    if (sabotage == .none) result.counts.inlined += try inline_leaves.withParametersCounted(arena, module, parameters, &result.provenance, inlined);
    // The effect summaries of the inlined module; the passes below keep every function's meaning.
    const summaries = try effects.analyze(arena, module);
    for (module.functions.items, result.known, result.plans, parameters, 0..) |*function, *slot, *plan, params, index| {
        if (function.signature.linkage != .internal) continue;
        const options: facts.Options = .{ .fold = !verify, .sabotage = sabotage, .params = params, .returns = returns, .fields = field_table };
        var known = try facts.analyze(arena, function, options);
        if (!verify and @import("byte_index.zig").forward(module, function, &known) != 0) {
            // The existing fact and vector rules now see the original counted index.
            known = try facts.analyze(arena, function, options);
        }
        result.counts.proven += known.proven;
        result.per_function[index].counts.proven += known.proven;
        // A reduction proven only under a trip bound gets a guarded copy; the facts then run again.
        const guarded = try version.versionReductions(arena, function, known, result.provenance.context(@intCast(index)));
        if (guarded != 0) {
            known = try facts.analyze(arena, function, options);
            result.counts.proven += known.proven;
            result.per_function[index].counts.proven += known.proven;
        }
        result.counts.versioned += guarded;
        result.per_function[index].counts.versioned = guarded;
        result.per_function[index].counts.inlined = inlined[index];
        // Ownership after the facts: the instructions and blocks it adds have none.
        result.per_function[index].own = try own.function(arena, module, function, .{ .verify = verify, .facts = &known, .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries });
        result.own.add(result.per_function[index].own);
        // Checks a dominating check already made, among them those ownership split (NEW-CORE-F2-INDEX-3).
        const covered = try index_checks.run(arena, function, &known, sabotage == .index);
        result.counts.proven += covered;
        result.per_function[index].counts.proven += covered;
        try extend(arena, &known, function);
        slot.* = known;
        // Vector code comes only from trusted facts, never in a verify build.
        if (!verify) plan.* = try vector.plan(arena, function, known);
        result.per_function[index].counts.vectorized = @intCast(plan.len);
        result.counts.vectorized += @intCast(plan.len);
    }
    return result;
}

/// The internal functions in an order that puts each callee before its callers
/// (a depth-first postorder of the direct-call graph); a cycle is broken where the
/// search meets a function still open, whose calls then see no return interval.
fn calleesFirst(arena: std.mem.Allocator, module: *const ir.Module) Error![]const u32 {
    const count = module.functions.items.len;
    const state = try arena.alloc(enum { new, open, done }, count);
    @memset(state, .new);
    var order: std.ArrayList(u32) = .empty;
    var stack: std.ArrayList(struct { function: u32, next: usize }) = .empty;
    for (module.functions.items, 0..) |root, root_index| {
        if (root.signature.linkage != .internal or state[root_index] != .new) continue;
        state[root_index] = .open;
        try stack.append(arena, .{ .function = @intCast(root_index), .next = 0 });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const insts = module.functions.items[top.function].insts.items;
            if (top.next < insts.len) {
                const inst = insts[top.next];
                top.next += 1;
                if (inst.op != .call) continue;
                const callee = inst.a.index();
                if (callee >= count or state[callee] != .new or module.functions.items[callee].signature.linkage != .internal) continue;
                state[callee] = .open;
                try stack.append(arena, .{ .function = @intCast(callee), .next = 0 });
                continue;
            }
            state[top.function] = .done;
            try order.append(arena, top.function);
            _ = stack.pop();
        }
    }
    return order.items;
}

/// Per function, the interval of each parameter over every call that reaches it
/// (NEW-CORE-FACTS-10), or no intervals (the parameter types' ranges).
///
/// A function qualifies when it is internal, no `func_ref` names it (a function value
/// could be called from anywhere), and every reachable call is in a function the
/// first pass analysed. Each argument's interval comes from facts computed with that
/// caller's own parameters unknown, so it holds whatever the caller is passed, and a
/// recursive call needs no fixed point. An argument with no interval makes its
/// parameter unknown.
pub fn parameterRanges(arena: std.mem.Allocator, module: *const ir.Module, first: []const ?facts.Facts) Error![]const []const ?facts.Interval {
    const count = module.functions.items.len;
    const out = try arena.alloc([]const ?facts.Interval, count);
    @memset(out, &.{});
    const usable = try arena.alloc(bool, count);
    for (module.functions.items, usable) |function, *flag| flag.* = function.signature.linkage == .internal;
    const merged = try arena.alloc(?[]?facts.Interval, count);
    @memset(merged, null);
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| {
            if (inst.op == .func_ref and inst.data < count) usable[@intCast(inst.data)] = false;
        }
    }
    for (module.functions.items, first) |*caller, known| {
        for (caller.blocks.items, 0..) |block, b| {
            if (known) |facts_of| if (b >= facts_of.reachable.len or !facts_of.reachable[b]) continue;
            for (block.insts.items) |ref| {
                const call = caller.inst(ref);
                if (call.op != .call) continue;
                const callee = call.a.index();
                if (callee >= count or !usable[callee]) continue;
                try mergeCall(arena, .{ .caller = caller, .known = known, .call = call }, &merged[callee], module.functions.items[callee].signature.params.len);
            }
        }
    }
    for (out, merged, usable) |*slot, ranges, flag| {
        if (flag) if (ranges) |known| {
            slot.* = known;
        };
    }
    return out;
}

/// One call's contribution to its callee's parameter intervals.
const CallSite = struct { caller: *const ir.Function, known: ?facts.Facts, call: ir.Inst };

/// Join one call's argument intervals into `merged` (created at the first call seen).
fn mergeCall(arena: std.mem.Allocator, site: CallSite, merged: *?[]?facts.Interval, arity: usize) Error!void {
    const arguments = site.caller.operands(site.call.data);
    if (merged.*) |ranges| {
        for (ranges, 0..) |*slot, i| {
            const now = slot.* orelse continue;
            const next = if (i < arguments.len) argumentRange(site, arguments[i]) else null;
            slot.* = if (next) |range| facts.Interval.hull(now, range) else null;
        }
        return;
    }
    const fresh = try arena.alloc(?facts.Interval, arity);
    for (fresh, 0..) |*slot, i| slot.* = if (i < arguments.len) argumentRange(site, arguments[i]) else null;
    merged.* = fresh;
}

/// An argument's interval in its caller, or null when the caller was not analysed.
fn argumentRange(site: CallSite, argument: ir.Ref) ?facts.Interval {
    const known = site.known orelse return null;
    return facts.valueRange(&known, site.caller, argument);
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
