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
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");
const deferred_facts = @import("deferred_facts.zig");
const cache_mod = @import("optimization_cache.zig");

/// Passes only allocate.
pub const Error = std.mem.Allocator.Error;

/// How the fact pass runs: `trusted` facts drive the vector lowering; `verify` keeps
/// comparisons unfolded and plans no vectors; `sabotage`, `sabotage_widening` and
/// `sabotage_length` are verify with one wrong rule (`facts.Sabotage`), and
/// `sabotage_overflow` verify with the overflow facts' rules off by one.
pub const Mode = enum { off, trusted, verify, sabotage, sabotage_widening, sabotage_length, sabotage_overflow };

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
pub const Counts = @import("pass_statistics.zig").Counts;

/// The debug pipeline's only pass: ownership and counting, no facts.
pub fn ownership(arena: std.mem.Allocator, module: *ir.Module) Error!own.Stats {
    return ownershipWithScratch(arena, arena, module);
}

/// Run ownership with independently reclaimable analysis backing.
pub fn ownershipWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module) Error!own.Stats {
    return own.runWithScratch(arena, backing, module, .{});
}

/// Run debug ownership with the same per-function accounting as release.
pub fn debug(arena: std.mem.Allocator, module: *ir.Module) Error!Result {
    return debugWithScratch(arena, arena, module);
}

/// Debug ownership keeps IR/statistics on `arena` and reclaims work through `backing`.
pub fn debugWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module) Error!Result {
    return debugInternal(arena, backing, module, null);
}

/// Debug ownership with persistent function-stage reuse.
pub fn debugCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, cache: *cache_mod.Context) Error!Result {
    return debugInternal(arena, backing, module, cache);
}

fn debugInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context) Error!Result {
    if (cache) |context| try context.prepare(arena);
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    var result: Result = .{ .known = &.{}, .plans = &.{}, .per_function = try arena.alloc(FunctionStats, module.functions.items.len) };
    @memset(result.per_function, .{});
    const summaries = try effects.analyze(arena, module);
    for (module.functions.items, result.per_function, 0..) |*function, *local, index| {
        if (function.signature.linkage != .internal) continue;
        const key = if (cache) |context| try context.key(work.allocator(), .{ .stage = .debug, .function = @intCast(index), .mode = 0, .provenance = &result.provenance, .inputs = .{ .effects = &summaries } }) else null;
        const hit = if (cache) |context| if (key) |digest| try context.load(work.allocator(), .debug, digest, cache_mod.Final) else null else null;
        if (hit) |cached| {
            if (cache_mod.validFinal(cached, false)) if (try cache.?.restore(arena, @intCast(index), cached.function, cached.provenance, &result.provenance)) |restored| {
                function.* = restored;
                local.own = cached.state.own;
                result.own.add(local.own);
                _ = work.reset(.retain_capacity);
                continue;
            };
            cache.?.rejected(.debug);
        }
        local.own = try own.functionWithScratch(arena, backing, module, function, .{ .function_index = @intCast(index), .effects = &summaries });
        result.own.add(local.own);
        if (cache) |context| {
            context.changed(index);
            if (key) |digest| try context.saveFinal(work.allocator(), digest, @intCast(index), &result.provenance, .{
                .known = null,
                .plans = &.{},
                .counts = .{},
                .own = local.own,
            });
        }
        _ = work.reset(.retain_capacity);
    }
    return result;
}

/// Run the release passes over `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, mode: Mode) Error!Result {
    return runWithScratch(arena, arena, module, mode);
}

/// Keep final IR/facts on `arena`; use `backing` for independently reclaimable pass storage.
pub fn runWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode) Error!Result {
    return runInternal(arena, backing, module, mode, null);
}

/// Apply stages in the same order as `runWithScratch`, restoring only validated functions.
pub fn runCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context) Error!Result {
    return runInternal(arena, backing, module, mode, cache);
}

/// Development emission retains compact verified facts and decodes only LLVM misses.
pub fn runCachedDeferred(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context, table: *deferred_facts.Table) Error!Result {
    cache.deferred = table;
    return runInternal(arena, backing, module, mode, cache);
}

fn runInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: ?*cache_mod.Context) Error!Result {
    try @import("fuse_text.zig").whitespace(arena, module);
    _ = try @import("fuse_slice_key.zig").run(arena, module);
    if (cache) |context| try context.prepare(arena);
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
    result.counts.inlined = if (cache) |context|
        try inlineCached(arena, backing, module, .{ .cache = context, .provenance = &result.provenance, .counts = inlined, .stage = .inline_leaf, .mode = mode }) +
            try inlineCached(arena, backing, module, .{ .cache = context, .provenance = &result.provenance, .counts = inlined, .stage = .inline_cfg, .mode = mode })
    else
        try inline_leaves.inlineLeavesCountedWithScratch(arena, backing, module, &result.provenance, inlined);
    if (mode == .off) {
        const summaries = try effects.analyze(arena, module);
        for (module.functions.items, result.per_function, inlined, 0..) |*function, *local, expanded, index| {
            if (function.signature.linkage != .internal) continue;
            local.counts.inlined = expanded;
            local.own = try own.functionWithScratch(arena, backing, module, function, .{ .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries });
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
        else => .none,
    };
    // A first fact pass with every parameter unknown gives each call site's argument
    // intervals; `parameterRanges` turns them into the parameter intervals the real
    // pass starts from. It changes no function. It runs callees first, so each
    // function's return interval (NEW-CORE-F1-OVERFLOW-3) is known at its calls.
    var parameter_summary = try ParameterSummary.init(arena, module);
    // Only compact call/return summaries survive the exploratory pass. These
    // arenas have independent backing so resetting them really releases memory.
    var temporary = std.heap.ArenaAllocator.init(backing);
    defer temporary.deinit();
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const returns = try arena.alloc(?facts.Interval, module.functions.items.len);
    @memset(returns, null);
    try unswitchFunctions(arena, module, &result, cache, mode, &temporary);
    // Unanalysed callers still invalidate their callees' parameter intervals.
    for (module.functions.items) |*function| {
        if (function.signature.linkage != .internal) try parameter_summary.add(arena, module, function, null);
    }
    for (try calleesFirst(arena, module)) |index| {
        const function = &module.functions.items[index];
        if (cache == null) {
            const known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, .{ .fold = !verify, .sabotage = sabotage, .mark = false, .returns = returns });
            try parameter_summary.add(arena, module, function, known);
            returns[index] = facts.returnRange(&known, function, sabotage);
            _ = temporary.reset(.retain_capacity);
            _ = scratch.reset(.retain_capacity);
            continue;
        }
        const key = if (cache) |context| try context.key(temporary.allocator(), .{ .stage = .first_facts, .function = index, .mode = @backingInt(mode), .provenance = &result.provenance, .inputs = .{ .returns = returns } }) else null;
        const summary = try firstSummary(temporary.allocator(), scratch.allocator(), .{
            .module = module,
            .function = index,
            .options = .{ .fold = !verify, .sabotage = sabotage, .mark = false, .returns = returns },
            .cache = cache.?,
            .key = key,
        });
        try parameter_summary.addSummary(arena, summary);
        returns[index] = summary.returned;
        _ = temporary.reset(.retain_capacity);
        _ = scratch.reset(.retain_capacity);
    }
    const parameters = parameter_summary.finish();
    // Closed caller bounds can prove an affine callback safe only after the
    // all-call parameter pass. Deliberately corrupted facts cannot prove safety.
    if (sabotage == .none) result.counts.inlined += if (cache) |context|
        try inlineCached(arena, backing, module, .{ .cache = context, .provenance = &result.provenance, .counts = inlined, .parameters = parameters, .stage = .parameter_inline, .mode = mode })
    else
        try inline_leaves.withParametersCountedWithScratch(arena, backing, module, parameters, &result.provenance, inlined);
    // The effect summaries of the inlined module; the passes below keep every function's meaning.
    const summaries = try effects.analyze(arena, module);
    for (module.functions.items, result.known, result.plans, parameters, 0..) |*function, *slot, *plan, params, index| {
        if (function.signature.linkage != .internal) continue;
        result.per_function[index].counts.inlined = inlined[index];
        const key = if (cache) |context| try context.key(temporary.allocator(), .{
            .stage = .final,
            .function = @intCast(index),
            .mode = @backingInt(mode),
            .provenance = &result.provenance,
            .inputs = .{
                .parameters = params,
                .returns = returns,
                .effects = &summaries,
                .events = .{ inlined[index], result.per_function[index].counts.unswitched },
            },
        }) else null;
        if (try cachedFinal(arena, temporary.allocator(), cache, .{ .function = @intCast(index), .key = key, .provenance = &result.provenance })) |cached| {
            function.* = cached.function;
            slot.* = cached.state.known;
            plan.* = cached.state.plans;
            result.per_function[index] = .{ .counts = cached.state.counts, .own = cached.state.own };
            result.counts.proven += cached.state.counts.proven;
            result.counts.versioned += cached.state.counts.versioned;
            result.counts.vectorized += cached.state.counts.vectorized;
            result.own.add(cached.state.own);
            _ = temporary.reset(.retain_capacity);
            continue;
        }
        const options: facts.Options = .{ .fold = !verify, .sabotage = sabotage, .params = params, .returns = returns };
        var known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, options);
        _ = scratch.reset(.retain_capacity);
        if (!verify and @import("byte_index.zig").forward(module, function, &known) != 0) {
            // The existing fact and vector rules now see the original counted index.
            _ = temporary.reset(.retain_capacity);
            known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, options);
            _ = scratch.reset(.retain_capacity);
        }
        result.counts.proven += known.proven;
        result.per_function[index].counts.proven += known.proven;
        // A reduction proven only under a trip bound gets a guarded copy; the facts then run again.
        const guarded = try version.versionReductions(arena, function, known, result.provenance.context(@intCast(index)));
        if (guarded != 0) {
            _ = temporary.reset(.retain_capacity);
            known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, options);
            _ = scratch.reset(.retain_capacity);
            result.counts.proven += known.proven;
            result.per_function[index].counts.proven += known.proven;
        }
        result.counts.versioned += guarded;
        result.per_function[index].counts.versioned = guarded;
        result.per_function[index].counts.inlined = inlined[index];
        // Ownership after the facts: the instructions and blocks it adds have none.
        result.per_function[index].own = try own.functionWithScratch(arena, backing, module, function, .{ .verify = verify, .facts = &known, .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries });
        result.own.add(result.per_function[index].own);
        try extend(temporary.allocator(), &known, function);
        // Vector code comes only from trusted facts, never in a verify build.
        if (!verify) plan.* = try vector.plan(arena, function, known);
        const artifact = try retainFinalFacts(arena, temporary.allocator(), cache, index, &known);
        slot.* = if (artifact == null) known else null;
        result.per_function[index].counts.vectorized = @intCast(plan.len);
        result.counts.vectorized += @intCast(plan.len);
        if (cache) |context| {
            context.changed(index);
            if (key) |digest| try context.saveFinal(temporary.allocator(), digest, @intCast(index), &result.provenance, .{
                .known = known,
                .plans = plan.*,
                .counts = result.per_function[index].counts,
                .own = result.per_function[index].own,
                .artifact = artifact,
            });
        }
        _ = temporary.reset(.retain_capacity);
    }
    return result;
}

fn retainFinalFacts(arena: std.mem.Allocator, work: std.mem.Allocator, cache: ?*cache_mod.Context, index: usize, known: *facts.Facts) Error!?deferred_facts.Artifact {
    if (cache) |context| if (context.deferred) |table| {
        const encoded = try deferred_facts.encode(work, known.*);
        const artifact = try retainedArtifact(arena, encoded);
        table.entries[index] = artifact;
        return artifact;
    };
    known.* = try known.clone(arena);
    return null;
}

fn retainedArtifact(arena: std.mem.Allocator, artifact: deferred_facts.Artifact) Error!deferred_facts.Artifact {
    return .{ .bytes = try arena.dupe(u8, artifact.bytes), .digest = artifact.digest, .loop_ids = try arena.dupe(usize, artifact.loop_ids) };
}

const FinalRequest = struct { function: u32, key: ?[32]u8, provenance: *origins.Table };
const CachedFinal = struct { function: ir.Function, state: cache_mod.FinalState };

fn cachedFinal(arena: std.mem.Allocator, work: std.mem.Allocator, cache: ?*cache_mod.Context, request: FinalRequest) Error!?CachedFinal {
    const context = cache orelse return null;
    const key = request.key orelse return null;
    var value = try context.load(work, .final, key, cache_mod.Final) orelse return null;
    const description = value.analysis orelse {
        context.rejected(.final);
        return null;
    };
    const artifact = try context.loadFacts(work, description) orelse {
        context.rejected(.final);
        return null;
    };
    if (context.deferred == null) value.state.known = try deferred_facts.decode(work, artifact);
    if (cache_mod.validFinal(value, true)) if (try context.restore(arena, request.function, value.function, value.provenance, request.provenance)) |restored| {
        var state = value.state;
        if (context.deferred) |table| {
            table.entries[request.function] = try retainedArtifact(arena, artifact);
        } else state.known = if (state.known) |known| try known.clone(arena) else null;
        state.plans = try cache_mod.retainPlans(arena, state.plans);
        return .{ .function = restored, .state = state };
    };
    context.rejected(.final);
    return null;
}

const FirstRequest = struct {
    module: *ir.Module,
    function: u32,
    options: facts.Options,
    cache: *cache_mod.Context,
    key: ?[32]u8,
};

fn firstSummary(work: std.mem.Allocator, scratch: std.mem.Allocator, request: FirstRequest) Error!cache_mod.Summary {
    if (request.key) |digest| if (try request.cache.load(work, .first_facts, digest, cache_mod.Summary)) |summary| {
        if (summary.valid(request.module)) return summary;
        request.cache.rejected(.first_facts);
    };
    const function = &request.module.functions.items[request.function];
    const known = try facts.analyzeWithScratch(work, scratch, function, request.options);
    const summary = try cache_mod.summarize(work, request.module, function, &known, request.options.sabotage);
    if (request.key) |digest| try request.cache.save(digest, cache_mod.Summary, summary);
    return summary;
}

fn unswitchFunctions(arena: std.mem.Allocator, module: *ir.Module, result: *Result, cache: ?*cache_mod.Context, mode: Mode, temporary: *std.heap.ArenaAllocator) Error!void {
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const key = if (cache) |context| try context.key(temporary.allocator(), .{ .stage = .unswitch, .function = @intCast(index), .mode = @backingInt(mode), .provenance = &result.provenance }) else null;
        var changed: ?u32 = null;
        if (cache) |context| if (key) |digest| {
            if (try context.load(temporary.allocator(), .unswitch, digest, cache_mod.Transform)) |cached| {
                if (try context.restoreTransform(arena, temporary.allocator(), @intCast(index), cached, &result.provenance)) |restored| {
                    function.* = restored;
                    changed = cached.changed;
                } else context.rejected(.unswitch);
            }
        };
        if (changed == null) {
            changed = try version.unswitch(arena, function, result.provenance.context(@intCast(index)));
            if (cache) |context| {
                context.changed(index);
                if (key) |digest| try context.saveTransform(temporary.allocator(), digest, @intCast(index), &result.provenance, changed.?);
            }
        }
        _ = temporary.reset(.retain_capacity);
        result.per_function[index].counts.unswitched = changed.?;
        result.counts.unswitched += changed.?;
    }
}

const InlineRound = struct {
    cache: *cache_mod.Context,
    provenance: *origins.Table,
    counts: []u32,
    parameters: []const []const ?facts.Interval = &.{},
    stage: cache_mod.Stage,
    mode: Mode,
};

fn inlineCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, round: InlineRound) Error!u32 {
    const cache = round.cache;
    const provenance = round.provenance;
    const parameters = round.parameters;
    const stage = round.stage;
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    var total: u32 = 0;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const params = if (index < parameters.len) parameters[index] else &.{};
        const key = try cache.key(work.allocator(), .{ .stage = stage, .function = @intCast(index), .mode = @backingInt(round.mode), .provenance = provenance, .inputs = .{ .parameters = params } });
        var changed: ?u32 = null;
        if (key) |digest| if (try cache.load(work.allocator(), stage, digest, cache_mod.Transform)) |cached| {
            if (try cache.restoreTransform(arena, work.allocator(), @intCast(index), cached, provenance)) |restored| {
                function.* = restored;
                changed = cached.changed;
            } else cache.rejected(stage);
        };
        if (changed == null) {
            changed = if (stage == .inline_cfg)
                try inline_leaves.cfgCaller(arena, module, @intCast(index), provenance)
            else
                try inline_leaves.leafCallerWithScratch(arena, work.allocator(), module, @intCast(index), params, provenance);
            cache.changed(index);
            if (key) |digest| try cache.saveTransform(work.allocator(), digest, @intCast(index), provenance, changed.?);
        }
        round.counts[index] += changed.?;
        total += changed.?;
        _ = work.reset(.retain_capacity);
    }
    return total;
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
    var summary = try ParameterSummary.init(arena, module);
    for (module.functions.items, first) |*caller, known| try summary.add(arena, module, caller, known);
    return summary.finish();
}

/// Compact streaming form of `parameterRanges`: no caller Facts are retained.
const ParameterSummary = struct {
    out: [][]const ?facts.Interval,
    usable: []bool,
    merged: []?[]?facts.Interval,

    fn init(arena: std.mem.Allocator, module: *const ir.Module) Error!ParameterSummary {
        const count = module.functions.items.len;
        const out = try arena.alloc([]const ?facts.Interval, count);
        errdefer arena.free(out);
        @memset(out, &.{});
        const usable = try arena.alloc(bool, count);
        errdefer arena.free(usable);
        for (module.functions.items, usable) |function, *flag| flag.* = function.signature.linkage == .internal;
        const merged = try arena.alloc(?[]?facts.Interval, count);
        errdefer arena.free(merged);
        @memset(merged, null);
        for (module.functions.items) |function| {
            for (function.insts.items) |inst| {
                if (inst.op == .func_ref and inst.data < count) usable[@intCast(inst.data)] = false;
            }
        }
        return .{ .out = out, .usable = usable, .merged = merged };
    }

    fn add(self: *ParameterSummary, arena: std.mem.Allocator, module: *const ir.Module, caller: *const ir.Function, known: ?facts.Facts) Error!void {
        for (caller.blocks.items, 0..) |block, b| {
            if (known) |facts_of| if (b >= facts_of.reachable.len or !facts_of.reachable[b]) continue;
            for (block.insts.items) |ref| {
                const call = caller.inst(ref);
                if (call.op != .call) continue;
                const callee = call.a.index();
                if (callee >= self.usable.len or !self.usable[callee]) continue;
                try mergeCall(arena, .{ .caller = caller, .known = known, .call = call }, &self.merged[callee], module.functions.items[callee].signature.params.len);
            }
        }
    }

    fn addSummary(self: *ParameterSummary, arena: std.mem.Allocator, summary: cache_mod.Summary) Error!void {
        for (summary.calls) |call| {
            if (call.callee >= self.usable.len or !self.usable[call.callee]) continue;
            if (self.merged[call.callee]) |ranges| {
                for (ranges, call.ranges) |*slot, next| {
                    const now = slot.* orelse continue;
                    slot.* = if (next) |range| facts.Interval.hull(now, range) else null;
                }
            } else self.merged[call.callee] = try arena.dupe(?facts.Interval, call.ranges);
        }
    }

    fn finish(self: *ParameterSummary) []const []const ?facts.Interval {
        for (self.out, self.merged, self.usable) |*slot, ranges, flag| {
            if (flag) if (ranges) |known| {
                slot.* = known;
            };
        }
        return self.out;
    }
};

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

// spec-case: NEW-CORE-FACTS-10
test "streamed parameter hulls match collected facts after each caller is reclaimed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var transient = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer transient.deinit();
    for ([_]enum { direct, unknown, function_value, recursive }{ .direct, .unknown, .function_value, .recursive }) |scenario| {
        var module: ir.Module = .{};
        for ([_][]const u8{ "callee", "left", "right" }) |name| {
            try module.functions.append(a, .{ .name = name, .signature = .{ .params = &.{.i64}, .ret = .i64 } });
        }
        const target = &module.functions.items[0];
        try target.insts.appendSlice(a, &.{
            .{ .op = .param, .ty = .i64, .data = 0 },
            .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 1 }).pack() },
        });
        try target.extra.append(a, @fromBackingInt(0));
        try target.blocks.append(a, .{});
        if (scenario == .recursive) try target.blocks.items[0].insts.append(a, @fromBackingInt(1));
        const left = &module.functions.items[1];
        try left.insts.appendSlice(a, &.{
            .{ .op = .iconst, .ty = .i64, .data = @bitCast(@as(i64, -4)) },
            .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 1 }).pack() },
            .{ .op = .iconst, .ty = .i64, .data = 999 },
            .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 1, .len = 1 }).pack() },
        });
        try left.extra.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(2) });
        try left.blocks.appendSlice(a, &.{ .{}, .{} });
        try left.blocks.items[0].insts.append(a, @fromBackingInt(1));
        try left.blocks.items[1].insts.append(a, @fromBackingInt(3));
        const right = &module.functions.items[2];
        try right.insts.appendSlice(a, &.{
            .{ .op = .iconst, .ty = .i64, .data = 12 },
            .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 1 }).pack() },
        });
        try right.extra.append(a, @fromBackingInt(0));
        try right.blocks.append(a, .{});
        try right.blocks.items[0].insts.append(a, @fromBackingInt(1));
        if (scenario == .function_value) try right.insts.append(a, .{ .op = .func_ref, .ty = .i64, .data = 0 });
        const first = try a.alloc(?facts.Facts, 3);
        for (module.functions.items, first, 0..) |function, *slot, index| {
            const ranges = try a.alloc(?facts.Interval, function.insts.items.len);
            @memset(ranges, null);
            if (index == 0) ranges[0] = .{ .lo = 0, .hi = 5 };
            const reachable = try a.alloc(bool, function.blocks.items.len);
            @memset(reachable, true);
            if (index == 1) reachable[1] = false;
            slot.* = if (scenario == .unknown and index == 2) null else .{
                .ranges = ranges,
                .reachable = reachable,
                .floats = &.{},
                .aggregates = .{ .lists = &.{}, .dicts = &.{}, .fields = &.{} },
            };
        }
        const collected = try parameterRanges(a, &module, first);
        var streamed = try ParameterSummary.init(a, &module);
        for ([_]usize{ 2, 0, 1 }) |index| {
            const known = if (first[index]) |value| try value.clone(transient.allocator()) else null;
            try streamed.add(a, &module, &module.functions.items[index], known);
            _ = transient.reset(.retain_capacity);
            @memset(try transient.allocator().alloc(u8, 1024 * 1024), 0xa5);
            _ = transient.reset(.retain_capacity);
        }
        const actual = streamed.finish();
        for (collected, actual) |before, after| {
            try std.testing.expectEqual(before.len, after.len);
            for (before, after) |x, y| try std.testing.expect(std.meta.eql(x, y));
        }
        switch (scenario) {
            .direct, .recursive => try std.testing.expect(std.meta.eql(actual[0][0], facts.Interval{ .lo = -4, .hi = 12 })),
            .unknown => try std.testing.expectEqual(@as(?facts.Interval, null), actual[0][0]),
            .function_value => try std.testing.expectEqual(@as(usize, 0), actual[0].len),
        }
    }
}
