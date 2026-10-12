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
const forward = @import("forward.zig");
const index_checks = @import("index_checks.zig");
const fields = @import("fields.zig");
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");
const deferred_facts = @import("deferred_facts.zig");
const cache_mod = @import("optimization_cache.zig");
const shortcut_mod = @import("optimizer_shortcut.zig");

/// Passes allocate and reject malformed compiler ownership markers.
pub const Error = std.mem.Allocator.Error || own.Error;
pub const CachedError = @import("demand_ir.zig").Error || Error;

fn validateSelections(a: std.mem.Allocator, module: *const ir.Module) Error!void {
    @import("borrow_selection.zig").validateModule(a, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedInstruction => return error.Unsupported,
    };
}

/// How the fact pass runs: `trusted` facts drive the vector lowering; `verify` keeps
/// comparisons unfolded and plans no vectors; `sabotage`, `sabotage_widening` and
/// `sabotage_length` are verify with one wrong rule (`facts.Sabotage`), and
/// `sabotage_overflow` verify with the overflow facts' rules off by one, and `sabotage_index`
/// verify with a dominating check taken to cover the next index too (`index_checks`), and
/// `sabotage_field` verify with each field interval's top dropped (`fields.zig`), and
/// `sabotage_version` verify with each bounds guard admitting one index too many (`version.zig`).
pub const Mode = enum { off, trusted, verify, sabotage, sabotage_widening, sabotage_length, sabotage_overflow, sabotage_index, sabotage_field, sabotage_version };

/// What the passes produced, per function, and what they did.
pub const Result = struct {
    known: []?facts.Facts,
    plans: [][]const vector.Plan,
    counts: Counts = .{},
    /// Exactly the same pass events, indexed by physical Core function.
    per_function: []FunctionStats = &.{},
    /// Verify builds re-emit checks the fact pass has proved.
    emission: struct { verifying: bool = false, effects: ?effects.Summaries = null } = .{},
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
    try validateSelections(backing, module);
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
    return runInternal(arena, backing, module, mode, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Unsupported,
        error.CacheMiss => unreachable, // No cache or lowering handles on this path.
    };
}

/// Apply stages in the same order as `runWithScratch`, restoring only validated functions.
pub fn runCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context) CachedError!Result {
    return runInternal(arena, backing, module, mode, cache);
}

/// Development emission retains compact verified facts and decodes only LLVM misses.
pub fn runCachedDeferred(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context, table: *deferred_facts.Table) CachedError!Result {
    cache.deferred = table;
    return runInternal(arena, backing, module, mode, cache);
}

fn runInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: ?*cache_mod.Context) CachedError!Result {
    try validateSelections(backing, module);
    var shortcut = try prepareOptimizer(arena, backing, module, mode, cache);
    var result: Result = .{
        .known = try arena.alloc(?facts.Facts, module.functions.items.len),
        .plans = try arena.alloc([]const vector.Plan, module.functions.items.len),
        .per_function = try arena.alloc(FunctionStats, module.functions.items.len),
    };
    @memset(result.known, null);
    @memset(result.plans, &.{});
    @memset(result.per_function, .{});
    const green: []const bool = if (shortcut) |index| index.green else &.{};
    try attachCheckpoints(arena, backing, if (shortcut) |*state| state else null, &result.provenance);
    defer detachCheckpoints(cache);
    const inlined = try arena.alloc(u32, module.functions.items.len);
    @memset(inlined, 0);
    result.counts.inlined = if (cache) |context|
        try inlineCached(arena, backing, module, .{ .cache = context, .provenance = &result.provenance, .counts = inlined, .stage = .inline_leaf, .mode = mode, .shortcut = if (shortcut) |*state| state else null }) +
            try inlineCached(arena, backing, module, .{ .cache = context, .provenance = &result.provenance, .counts = inlined, .stage = .inline_cfg, .mode = mode, .shortcut = if (shortcut) |*state| state else null })
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
    result.emission.verifying = verify;
    const sabotage: facts.Sabotage = switch (mode) {
        .sabotage => .remainder,
        .sabotage_widening => .widening,
        .sabotage_length => .length,
        .sabotage_overflow => .overflow,
        .sabotage_index => .index,
        .sabotage_field => .field,
        .sabotage_version => .version,
        else => .none,
    };
    // A first fact pass with every parameter unknown gives each call site's argument
    // intervals; `parameterRanges` turns them into the parameter intervals the real
    // pass starts from. It changes no function. It runs callees first, so each
    // function's return interval (NEW-CORE-F1-OVERFLOW-3) is known at its calls.
    var parameter_summary = try ParameterSummary.initIndexed(arena, module, if (shortcut) |*state| state else null);
    // Only compact call/return summaries survive the exploratory pass. These
    // arenas have independent backing so resetting them really releases memory.
    var temporary = std.heap.ArenaAllocator.init(backing);
    defer temporary.deinit();
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const returns = try arena.alloc(?facts.Interval, module.functions.items.len);
    @memset(returns, null);
    try unswitchFunctions(arena, module, &result, .{ .cache = cache, .shortcut = if (shortcut) |*state| state else null }, mode, &temporary);
    const field_table = if (hasRecordTypes(module))
        try fieldSummaries(arena, module, .{
            .cache = cache,
            .mode = mode,
            .sabotage = sabotage,
            .returns = returns,
            .shortcut = if (shortcut) |*state| state else null,
            .provenance = &result.provenance,
        }, .{ .temporary = &temporary, .scratch = &scratch, .parameters = &parameter_summary, .inlined = inlined, .result = &result })
    else blk: {
        try exploratorySummaries(arena, module, .{
            .cache = cache,
            .mode = mode,
            .sabotage = sabotage,
            .returns = returns,
            .shortcut = if (shortcut) |*state| state else null,
            .provenance = &result.provenance,
            .fields = .{ .module = module },
        }, .{ .temporary = &temporary, .scratch = &scratch, .parameters = &parameter_summary, .inlined = inlined, .result = &result });
        // Array facts also need type information when no record field rounds run.
        break :blk facts.FieldIntervals{ .module = module };
    };
    const parameters = parameter_summary.finish();
    try resolveParameters(arena, if (shortcut) |*state| state else null, parameters, inlined, &result);
    try ensureRedRaw(cache, green);

    // Closed caller bounds can prove an affine callback safe only after the
    // all-call parameter pass. Deliberately corrupted facts cannot prove safety.
    if (sabotage == .none) result.counts.inlined += if (cache) |context|
        try inlineCached(arena, backing, module, .{
            .cache = context,
            .provenance = &result.provenance,
            .counts = inlined,
            .parameters = parameters,
            .stage = .parameter_inline,
            .mode = mode,
            .shortcut = if (shortcut) |*state| state else null,
        })
    else
        try inline_leaves.withParametersCountedWithScratch(arena, backing, module, parameters, &result.provenance, inlined);
    // The effect summaries of the inlined module; the passes below keep every function's meaning.
    const summaries = try prepareEffects(arena, module, cache, if (shortcut) |*state| state else null);
    try finalFunctions(.{ .arena = arena, .backing = backing, .temporary = &temporary, .scratch = &scratch }, module, cache, .{
        .result = &result,
        .effects = &summaries,
        .parameters = parameters,
        .returns = returns,
        .fields = field_table,
        .inlined = inlined,
        .options = .{ .mode = mode, .verify = verify, .sabotage = sabotage },
        .shortcut = if (shortcut) |*state| state else null,
    });
    try retainEmissionEffects(arena, module, cache, if (shortcut) |*state| state else null, &result);
    if (shortcut) |*state| try state.save();
    return result;
}

fn ensureRedRaw(cache: ?*cache_mod.Context, green: []const bool) CachedError!void {
    const context = cache orelse return;
    const handles = context.lazy.raw orelse return;
    for (green, 0..) |green_body, index| if (!green_body) try handles.ensure(@intCast(index));
}

fn hasRecordTypes(module: *const ir.Module) bool {
    for (module.compounds.items) |compound| if (compound == .record) return true;
    return false;
}

fn fieldDigest(arena: std.mem.Allocator, table: facts.FieldIntervals) Error![32]u8 {
    var writer = @import("mylang").persist_codec.Writer.init(arena);
    defer writer.deinit();
    try writer.write(@TypeOf(table.types), table.types);
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &digest, .{});
    return digest;
}

fn fieldInput(arena: std.mem.Allocator, table_digest: [32]u8, returns: []const ?facts.Interval, targets: []const u32) Error![32]u8 {
    var writer = @import("mylang").persist_codec.Writer.init(arena);
    defer writer.deinit();
    try writer.write([32]u8, table_digest);
    for (targets) |target| {
        try writer.write(u32, target);
        try writer.write(?facts.Interval, returns[target]);
    }
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &digest, .{});
    return digest;
}

/// A changed exploratory dependency resumes candidates at their exact pre-fact bodies.
fn demoteExploration(arena: std.mem.Allocator, shortcut: ?*shortcut_mod.Index, inlined: []u32, result: *Result) CachedError!void {
    const state = shortcut orelse return;
    const prior = try arena.dupe(bool, state.green);
    for (state.green, state.context.source.module.functions.items) |*green, function| {
        if (function.signature.linkage == .internal) green.* = false;
    }
    if (state.context.lazy.raw == null) return;
    for (try state.resumeParameters(prior), 0..) |resumed, index| if (resumed) |events| {
        inlined[index] = events.inlined;
        result.counts.inlined += events.inlined;
        result.per_function[index].counts.unswitched = events.unswitched;
        result.counts.unswitched += events.unswitched;
    };
}

fn explorationTargets(a: std.mem.Allocator, module: *ir.Module, shortcut: ?*shortcut_mod.Index, index: u32) Error![]const u32 {
    if (shortcut) |state| if (state.green[index] and state.context.lazy.raw != null) {
        const history = state.entries[index].demand.history orelse return state.entries[index].demand.graph.direct_calls;
        return if (history.outputs[2]) |checkpoint| checkpoint.graph.calls else state.entries[index].demand.graph.direct_calls;
    };
    return shortcut_mod.Index.targetsOf(a, &module.functions.items[index], .call);
}

fn summaryInput(a: std.mem.Allocator, module: *ir.Module, input: Exploration, index: u32, table_digest: [32]u8) Error!?[32]u8 {
    const context = input.cache orelse return null;
    if (context.lazy.raw == null) return null;
    const targets = try explorationTargets(a, module, input.shortcut, index);
    const digest = try fieldInput(a, table_digest, input.returns, targets);
    return digest;
}

fn savedSummary(state: *shortcut_mod.Index, module: *ir.Module, index: usize, dependency: ?[32]u8) ?cache_mod.Summary {
    const summary = state.entries[index].summary orelse return null;
    if (state.context.lazy.raw == null) return summary;
    const expected = state.entries[index].summary_input orelse return null;
    const current = dependency orelse return null;
    if (!std.mem.eql(u8, &expected, &current) or !summary.valid(module)) return null;
    return summary;
}

const ExplorationWork = struct {
    temporary: *std.heap.ArenaAllocator,
    scratch: *std.heap.ArenaAllocator,
    parameters: *ParameterSummary,
    inlined: []u32,
    result: *Result,
};

fn savedFieldRound(module: *const ir.Module, state: *shortcut_mod.Index, index: usize, round: usize, dependency: [32]u8) ?shortcut_mod.FieldRound {
    const saved = state.entries[index].demand.fields.rounds[round] orelse return null;
    if (!saved.summary.valid(module) or !saved.writes.valid(module)) return null;
    if (!std.mem.eql(u8, &saved.input, &dependency)) return null;
    return saved;
}

/// Two whole-program field rounds retain compact evidence instead of fact arrays or bodies.
fn fieldSummaries(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, work: ExplorationWork) CachedError!facts.FieldIntervals {
    const temporary = work.temporary;
    const scratch = work.scratch;
    const parameters = work.parameters;
    const inlined = work.inlined;
    const result = work.result;
    const contributions = try arena.alloc(?fields.Contribution, module.functions.items.len);
    @memset(contributions, null);
    const order = try calleesFirstIndexed(arena, module, input.shortcut);
    var table: facts.FieldIntervals = .{ .module = module };
    for (0..2) |round| {
        const table_digest = try fieldDigest(temporary.allocator(), table);
        parameters.* = try ParameterSummary.initIndexed(arena, module, input.shortcut);
        for (module.functions.items) |*function| {
            if (function.signature.linkage != .internal) try parameters.add(arena, module, function, null);
        }
        for (order) |index| {
            const targets = try explorationTargets(temporary.allocator(), module, input.shortcut, index);
            const dependency = try fieldInput(temporary.allocator(), table_digest, input.returns, targets);
            var record: ?shortcut_mod.FieldRound = null;
            if (input.shortcut) |state| if (state.green[index]) {
                record = savedFieldRound(module, state, index, round, dependency);
                if (record == null) try demoteExploration(arena, input.shortcut, inlined, result);
            };
            if (record == null) {
                const function = &module.functions.items[index];
                const known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, .{
                    .fold = input.mode == .trusted,
                    .sabotage = input.sabotage,
                    .mark = false,
                    .returns = input.returns,
                    .fields = table,
                });
                record = .{
                    .input = dependency,
                    .summary = try cache_mod.summarize(arena, module, function, &known, input.sabotage),
                    .writes = try fields.contribution(arena, module, function, &known),
                };
                if (input.cache) |context| context.changed(index);
                if (input.shortcut) |state| state.entries[index].demand.fields.rounds[round] = record;
            }
            const current = record.?;
            contributions[index] = current.writes;
            try parameters.addSummary(arena, current.summary);
            input.returns[index] = current.summary.returned;
            if (round == 1) if (input.shortcut) |state| try state.summary(arena, index, current.summary);
            _ = temporary.reset(.retain_capacity);
            _ = scratch.reset(.retain_capacity);
        }
        table = try fields.fromContributions(arena, module, contributions, input.sabotage == .field);
    }
    const final_digest = try fieldDigest(temporary.allocator(), table);
    if (input.shortcut) |state| {
        for (state.entries, state.green, module.functions.items) |entry, green, function| {
            if (!green or function.signature.linkage != .internal) continue;
            if (entry.demand.fields.final == null) {
                try demoteExploration(arena, input.shortcut, inlined, result);
                break;
            }
            if (!std.mem.eql(u8, &entry.demand.fields.final.?, &final_digest)) {
                try demoteExploration(arena, input.shortcut, inlined, result);
                break;
            }
        }
        for (state.entries) |*entry| entry.demand.fields.final = final_digest;
    }
    return table;
}

fn attachCheckpoints(arena: std.mem.Allocator, backing: std.mem.Allocator, shortcut: ?*shortcut_mod.Index, provenance: *origins.Table) Error!void {
    if (shortcut) |state| if (state.context.lazy.raw != null) try state.attach(arena, backing, provenance);
}

fn detachCheckpoints(cache: ?*cache_mod.Context) void {
    if (cache) |context| {
        context.lazy.checkpoints = null;
        if (context.lazy.raw) |handles| handles.inspection = null;
    }
}

fn resolveParameters(arena: std.mem.Allocator, shortcut: ?*shortcut_mod.Index, parameters: []const []const ?facts.Interval, inlined: []u32, result: *Result) CachedError!void {
    const state = shortcut orelse return;
    const was_green = if (state.context.lazy.raw != null) try arena.dupe(bool, state.green) else &.{};
    try state.parameters(arena, parameters);
    if (state.context.lazy.raw == null) return;
    for (try state.resumeParameters(was_green), 0..) |resumed, index| if (resumed) |events| {
        inlined[index] = events.inlined;
        result.counts.inlined += events.inlined;
        result.per_function[index].counts.unswitched = events.unswitched;
        result.counts.unswitched += events.unswitched;
    };
}

const FinalMemory = struct { arena: std.mem.Allocator, backing: std.mem.Allocator, temporary: *std.heap.ArenaAllocator, scratch: *std.heap.ArenaAllocator };
const FinalRound = struct {
    result: *Result,
    effects: *const effects.Summaries,
    parameters: []const []const ?facts.Interval,
    returns: []const ?facts.Interval,
    fields: facts.FieldIntervals,
    inlined: []const u32,
    options: struct { mode: Mode, verify: bool, sabotage: facts.Sabotage },
    shortcut: ?*shortcut_mod.Index,
};

fn finalFunctions(memory: FinalMemory, module: *ir.Module, cache: ?*cache_mod.Context, round: FinalRound) CachedError!void {
    const arena = memory.arena;
    const backing = memory.backing;
    const temporary = memory.temporary;
    const scratch = memory.scratch;
    const result = round.result;
    const summaries = round.effects.*;
    const parameters = round.parameters;
    const returns = round.returns;
    const inlined = round.inlined;
    const mode = round.options.mode;
    const verify = round.options.verify;
    const sabotage = round.options.sabotage;
    const shortcut = round.shortcut;
    const green: []const bool = if (shortcut) |index| index.green else &.{};
    const fields_digest = try fieldDigest(temporary.allocator(), round.fields);
    for (module.functions.items, result.known, result.plans, parameters, 0..) |*function, *slot, *plan, params, index| {
        if (function.signature.linkage != .internal) continue;
        result.per_function[index].counts.inlined = inlined[index];
        if (cache) |context| if (context.lazy.raw != null and index < green.len and green[index]) {
            const metadata = shortcut.?.entries[index].demand.metadata orelse return error.CacheMiss;
            context.lazy.finals[index] = metadata;
            context.lazy.loaded[index] = false;
            result.per_function[index] = .{ .counts = metadata.state.counts, .own = metadata.state.own };
            result.counts.inlined += metadata.state.counts.inlined;
            result.counts.unswitched += metadata.state.counts.unswitched;
            result.counts.proven += metadata.state.counts.proven;
            result.counts.versioned += metadata.state.counts.versioned;
            result.counts.vectorized += metadata.state.counts.vectorized;
            result.own.add(metadata.state.own);
            context.statistics.bypassed += 1;
            continue;
        };
        if (cache) |context| {
            context.statistics.active_functions += 1;
            context.statistics.final_loaded += 1;
        }
        const key = if (index < green.len and green[index]) shortcut.?.entries[index].final else if (cache) |context| try context.key(temporary.allocator(), .{
            .stage = .final,
            .function = @intCast(index),
            .mode = @backingInt(mode),
            .provenance = &result.provenance,
            .inputs = .{
                .parameters = params,
                .fields = fields_digest,
                .returns = returns,
                .effects = &summaries,
                .events = .{ inlined[index], result.per_function[index].counts.unswitched },
            },
        }) else null;
        if (shortcut) |state| try state.final(arena, index, params, key, .{ inlined[index], result.per_function[index].counts.unswitched });
        if (try cachedFinal(arena, temporary.allocator(), cache, .{ .function = @intCast(index), .key = key, .provenance = &result.provenance })) |cached| {
            if (index < green.len and green[index]) cache.?.statistics.bypassed += 1;
            function.* = cached.function;
            slot.* = cached.state.known;
            plan.* = cached.state.plans;
            result.per_function[index] = .{ .counts = cached.state.counts, .own = cached.state.own };
            result.counts.proven += cached.state.counts.proven;
            result.counts.versioned += cached.state.counts.versioned;
            result.counts.vectorized += cached.state.counts.vectorized;
            result.own.add(cached.state.own);
            if (shortcut) |state| if (key) |digest| try rememberFinal(arena, cache.?, state, index, .{ .key = digest, .state = cached.state, .analysis = cached.analysis, .provenance = &result.provenance });
            _ = temporary.reset(.retain_capacity);
            continue;
        }
        if (cache) |context| context.statistics.fresh_work += 1;
        const options: facts.Options = .{ .fold = !verify, .sabotage = sabotage, .params = params, .returns = returns, .fields = round.fields };
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
        // A small flat counted loop whose list indexes a guard can range-check before it gets
        // a copy with those checks proven (NEW-CORE-F2-VERSION-1); the facts then run again.
        const ranged = try version.versionBounds(arena, function, known, .{ .provenance = result.provenance.context(@intCast(index)), .sabotage = sabotage == .version });
        if (ranged != 0) {
            known = try facts.analyze(arena, function, options);
            result.counts.proven += known.proven;
            result.per_function[index].counts.proven += known.proven;
        }
        result.counts.versioned += guarded + ranged;
        result.per_function[index].counts.versioned = guarded + ranged;
        result.per_function[index].counts.inlined = inlined[index];
        // Ownership after the facts: the instructions and blocks it adds have none.
        result.per_function[index].own = try own.functionWithScratch(arena, backing, module, function, .{ .verify = verify, .facts = &known, .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries });
        result.own.add(result.per_function[index].own);
        // Checks already established by a dominating check, including ownership splits.
        const covered = try index_checks.run(arena, function, &known, sabotage == .index) +
            try @import("overflow_edges.zig").run(arena, function);
        result.counts.proven += covered;
        result.per_function[index].counts.proven += covered;
        // Preserve scalar record fields in SSA before planning vectors.
        const forwarded = try forward.run(arena, module, function);
        try extend(temporary.allocator(), &known, function);
        forward.ranges(&known, forwarded.made);

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
        if (shortcut) |state| if (key) |digest| if (artifact) |encoded| try rememberFinal(arena, cache.?, state, index, .{
            .key = digest,
            .provenance = &result.provenance,
            .state = .{ .known = null, .plans = plan.*, .counts = result.per_function[index].counts, .own = result.per_function[index].own },
            .analysis = .{ .digest = encoded.digest, .loop_ids = encoded.loop_ids },
        });
        _ = temporary.reset(.retain_capacity);
    }
}

// Split fusions can append compound types and helper requests outside the slice
// recorder. Load these raw catalogs eagerly until replay covers all producers;
// ordinary per-stage and emission caches still operate after the exact fusions.
fn splitFusionCatalog(module: *const ir.Module) bool {
    for (module.functions.items) |function| {
        const sig = function.signature;
        if (sig.linkage == .internal or sig.owned != 0 or sig.views != 0) continue;
        if (module.kind(sig.ret) != .list or module.compound(sig.ret).list != .str) continue;
        const explicit = std.mem.eql(u8, function.name, "myl_core_str_split");
        const whitespace = sig.linkage == .runtime_c and std.mem.eql(u8, function.name, "myl_core_str_split_whitespace");
        if (!explicit and !whitespace) continue;
        if (std.mem.eql(ir.Type, sig.params, if (explicit) &.{ .str, .str } else &.{.str})) return true;
    }
    return false;
}

fn prepareOptimizer(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: ?*cache_mod.Context) CachedError!?shortcut_mod.Index {
    const eager_splits = cache != null and cache.?.lazy.raw != null and splitFusionCatalog(module);
    var shortcut: ?shortcut_mod.Index = if (cache) |context| blk: {
        if (eager_splits or context.lazy.raw == null or (mode != .verify and mode != .trusted)) break :blk null;
        break :blk try shortcut_mod.Index.prepareDemand(arena, context, @backingInt(mode), hasRecordTypes(module));
    } else null;
    if (shortcut == null) if (cache) |context| if (context.lazy.raw) |handles| {
        for (module.functions.items, 0..) |_, index| try handles.ensure(@intCast(index));
    };
    var fusion_scratch = std.heap.ArenaAllocator.init(backing);
    defer fusion_scratch.deinit();
    const before_fusions = try arena.alloc(?[32]u8, module.functions.items.len);
    @memset(before_fusions, null);
    if (shortcut) |state| for (state.green, 0..) |green_body, index| {
        // A matching lowering key binds this body and the full raw catalog.
        // Fusions read no other bodies or parameter facts, so their prior base
        // identity remains valid when later inlining makes the function non-green.
        if (green_body or state.entries[index].raw != null) continue;
        before_fusions[index] = @import("ir_snapshot.zig").digest(fusion_scratch.allocator(), cache.?.source, module.functions.items[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => null,
        };
        _ = fusion_scratch.reset(.retain_capacity);
    };
    const seeded = if (shortcut) |state| state.catalog.layout != null and hasDeferredBodies(&state, module) else false;
    if (seeded) {
        try @import("fusion_checkpoint.zig").seed(arena, module, shortcut.?.catalog);
    } else if (shortcut) |*state| state.catalog = .{ .raw_count = module.functions.items.len };
    try @import("fuse_text.zig").whitespace(arena, module);
    try @import("split_views.zig").run(arena, module);
    const fusion_requests: ?[]std.ArrayList(u32) = if (shortcut != null)
        try arena.alloc(std.ArrayList(u32), before_fusions.len)
    else
        null;
    if (fusion_requests) |requests| @memset(requests, .empty);
    _ = try @import("fuse_slice_key.zig").runRecording(arena, module, fusion_requests);
    if (cache) |context| try context.prepare(arena);
    if (shortcut) |*state| {
        if (state.catalog.layout) |old| if (seeded) {
            const current = cache.?.layoutDigest() orelse return error.CacheMiss;
            if (!std.mem.eql(u8, &old, &current)) return error.CacheMiss;
        };
        try state.extend(arena);

        for (state.entries, state.green, 0..) |*entry, green_body, index| {
            if (green_body) {
                cache.?.prepared.?.digests[index] = entry.raw;
                continue;
            }
            const identity_known = entry.raw != null;
            entry.raw = try cache.?.bodyDigest(@intCast(index));
            if (identity_known or index >= before_fusions.len) continue;
            const after = @import("ir_snapshot.zig").digest(fusion_scratch.allocator(), cache.?.source, module.functions.items[index]) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidSnapshot => null,
            };
            _ = fusion_scratch.reset(.retain_capacity);
            entry.demand.fusion.identity = before_fusions[index] != null and after != null and std.mem.eql(u8, &before_fusions[index].?, &after.?);
        }
        try finishFusionInputs(arena, &fusion_scratch, state, .{ .seeded = seeded, .requests = fusion_requests.? });
    } else if (!eager_splits) shortcut = try prepareShortcut(arena, cache, mode);
    return shortcut;
}

fn finishFusionInputs(arena: std.mem.Allocator, temporary: *std.heap.ArenaAllocator, state: *shortcut_mod.Index, replay: struct { seeded: bool, requests: []const std.ArrayList(u32) }) CachedError!void {
    const scratch = temporary.allocator();
    const fusion = @import("fusion_checkpoint.zig");
    const module = state.context.source.module;
    const raw_count = state.catalog.raw_count;
    if (raw_count > module.functions.items.len) return error.CacheMiss;
    const requests = try arena.alloc([]const u32, raw_count);
    for (state.entries[0..raw_count], state.green[0..raw_count], requests, 0..) |*entry, green, *inventory, index| {
        if (green and module.functions.items[index].signature.linkage == .internal) {
            inventory.* = state.catalog.requests[index];
            continue;
        }
        inventory.* = replay.requests[index].items;
        if (replay.seeded and !std.mem.eql(u32, inventory.*, state.catalog.requests[index])) return error.CacheMiss;
        if (!entry.demand.fusion.identity) if (entry.demand.lowered) |lowered| if (entry.raw) |output| {
            entry.demand.fusion.key = try fusion.save(scratch, state.context, @intCast(index), lowered, output);
        };
        _ = temporary.reset(.retain_capacity);
    }
    const declarations = try arena.alloc(fusion.Declaration, module.functions.items.len - raw_count);
    for (module.functions.items[raw_count..], declarations) |function, *declaration| {
        if (function.signature.linkage != .runtime_c) return error.CacheMiss;
        declaration.* = .{ .name = function.name, .signature = function.signature };
    }
    state.catalog = .{ .layout = state.context.layoutDigest(), .raw_count = raw_count, .declarations = declarations, .requests = requests };
}

fn hasDeferredBodies(state: *const shortcut_mod.Index, module: *const ir.Module) bool {
    for (state.green, module.functions.items[0..state.green.len]) |green, function| {
        if (green and function.signature.linkage == .internal) return true;
    }
    return false;
}

fn prepareEffects(arena: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context, shortcut: ?*shortcut_mod.Index) Error!effects.Summaries {
    const reused_effects = try arena.alloc(?effects.Reused, module.functions.items.len);
    @memset(reused_effects, null);
    if (shortcut) |state| for (state.green, state.entries, reused_effects) |green_body, entry, *slot| {
        if (green_body) slot.* = entry.demand.effect;
    };
    const summaries = try effects.analyzeReused(arena, module, reused_effects);
    // Install the internal calling convention before any ownership body runs.
    // The proof survives omitted bodies; the closed catalog guard is checked anew.
    // Source `mut` result fields remain described solely by Signature.owned.
    const changed_convention = installConsuming(module, &summaries);
    if (changed_convention) if (cache) |context| try context.prepare(arena);
    if (cache) |context| {
        context.lazy.finals = try arena.alloc(?cache_mod.FinalMetadata, module.functions.items.len);
        @memset(context.lazy.finals, null);
        context.lazy.loaded = try arena.alloc(bool, module.functions.items.len);
        @memset(context.lazy.loaded, true);
    }
    if (shortcut) |state| for (state.entries, summaries.params, summaries.may) |*entry, params_effect, answers| {
        entry.demand.effect = try effects.retain(arena, .{ .params = params_effect, .may = answers });
    };
    return summaries;
}

fn installConsuming(module: *ir.Module, summaries: *const effects.Summaries) bool {
    const closed = @import("consume.zig").closed(module);
    var changed = false;
    for (module.functions.items, summaries.params, 0..) |*function, params, index| {
        var mask: u64 = 0;
        if (closed and index != module.entry and function.signature.linkage == .internal) {
            for (params, 0..) |effect, param| {
                if (param < 64 and effect.consumes) mask |= @as(u64, 1) << @intCast(param);
            }
        }
        changed = changed or function.signature.consumes != mask;
        function.signature.consumes = mask;
    }
    return changed;
}

fn retainEmissionEffects(arena: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context, shortcut: ?*shortcut_mod.Index, result: *Result) Error!void {
    if (cache) |context| if (context.lazy.raw != null) {
        const final_reused = try arena.alloc(?effects.Reused, module.functions.items.len);
        @memset(final_reused, null);
        for (context.lazy.finals, context.lazy.loaded, final_reused) |metadata, present, *slot| {
            if (!present) slot.* = metadata.?.emission_effect;
        }
        const final_effects = try effects.analyzeReused(arena, module, final_reused);
        result.emission.effects = final_effects;
        if (shortcut) |state| for (context.lazy.finals, final_effects.params, final_effects.may, 0..) |*metadata, param_effects, answers, index| {
            if (metadata.*) |*record| {
                record.emission_effect = try effects.retain(arena, .{ .params = param_effects, .may = answers });
                state.entries[index].demand.metadata = record.*;
            }
        };
    };
}

const FinalInput = struct { key: [32]u8, state: cache_mod.FinalState, analysis: cache_mod.Analysis, provenance: *const origins.Table };

fn rememberFinal(arena: std.mem.Allocator, context: *cache_mod.Context, shortcut: *shortcut_mod.Index, index: usize, input: FinalInput) Error!void {
    const state = input.state;
    const analysis = input.analysis;
    const body = try context.bodyDigest(@intCast(index)) orelse return;
    var retained = state;
    retained.known = null;
    retained.artifact = null;
    retained.plans = try cache_mod.retainPlans(arena, state.plans);
    const metadata: cache_mod.FinalMetadata = .{
        .key = input.key,
        .body = body,
        .outgoing = try shortcut_mod.Index.targets(arena, &context.source.module.functions.items[index]),
        .render = try context.renderMetadata(arena, @intCast(index), input.provenance) orelse return,
        .analysis = .{ .digest = analysis.digest, .loop_ids = try arena.dupe(usize, analysis.loop_ids) },
        .state = retained,
    };
    shortcut.entries[index].demand.metadata = metadata;
    if (index < context.lazy.finals.len) context.lazy.finals[index] = metadata;
}

/// Restore a deferred final body and its verified facts before an emission miss.
pub fn restoreDeferredFinal(arena: std.mem.Allocator, work: std.mem.Allocator, context: *cache_mod.Context, index: u32, result: *Result) CachedError!void {
    if (index >= context.lazy.loaded.len or context.lazy.loaded[index]) return;
    if (index >= context.lazy.finals.len) return error.CacheMiss;
    const metadata = context.lazy.finals[index] orelse return error.CacheMiss;
    const value = try cachedFinal(arena, work, context, .{ .function = index, .key = metadata.key, .provenance = &result.provenance }) orelse return error.CacheMiss;
    context.source.module.functions.items[index] = value.function;
    result.known[index] = value.state.known;
    result.plans[index] = value.state.plans;
    context.lazy.loaded[index] = true;
    context.statistics.final_loaded += 1;
}

fn prepareShortcut(arena: std.mem.Allocator, cache: ?*cache_mod.Context, mode: Mode) CachedError!?shortcut_mod.Index {
    if (mode == .off) return null;
    const context = cache orelse return null;
    return shortcut_mod.Index.prepare(arena, context, @backingInt(mode));
}

const Exploration = struct {
    cache: ?*cache_mod.Context,
    mode: Mode,
    sabotage: facts.Sabotage,
    returns: []?facts.Interval,
    shortcut: ?*shortcut_mod.Index,
    provenance: *const origins.Table,
    fields: facts.FieldIntervals = .{},
};

fn exploratorySummaries(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, work: ExplorationWork) CachedError!void {
    const temporary = work.temporary;
    const scratch = work.scratch;
    const parameter_summary = work.parameters;
    const green: []const bool = if (input.shortcut) |index| index.green else &.{};
    const table_digest = try fieldDigest(temporary.allocator(), input.fields);
    // Unanalysed callers still invalidate their callees' parameter intervals.
    for (module.functions.items) |*function| {
        if (function.signature.linkage != .internal) try parameter_summary.add(arena, module, function, null);
    }
    for (try calleesFirstIndexed(arena, module, input.shortcut)) |index| {
        const function = &module.functions.items[index];
        if (input.cache == null) {
            const known = try facts.analyzeWithScratch(temporary.allocator(), scratch.allocator(), function, .{ .fold = input.mode == .trusted, .sabotage = input.sabotage, .mark = false, .returns = input.returns, .fields = input.fields });
            try parameter_summary.add(arena, module, function, known);
            input.returns[index] = facts.returnRange(&known, function, input.sabotage);
            _ = temporary.reset(.retain_capacity);
            _ = scratch.reset(.retain_capacity);
            continue;
        }
        const dependency = try summaryInput(temporary.allocator(), module, input, index, table_digest);
        if (index < green.len and green[index]) {
            if (savedSummary(input.shortcut.?, module, index, dependency)) |summary| {
                try parameter_summary.addSummary(arena, summary);
                input.returns[index] = summary.returned;
                _ = temporary.reset(.retain_capacity);
                continue;
            }
            try demoteExploration(arena, input.shortcut, work.inlined, work.result);
        }
        const key = if (input.cache) |context| try context.key(temporary.allocator(), .{
            .stage = .first_facts,
            .function = index,
            .mode = @backingInt(input.mode),
            .provenance = input.provenance,
            .inputs = .{ .returns = input.returns },
        }) else null;
        const summary = try firstSummary(temporary.allocator(), scratch.allocator(), .{
            .module = module,
            .function = index,
            .options = .{ .fold = input.mode == .trusted, .sabotage = input.sabotage, .mark = false, .returns = input.returns, .fields = input.fields },
            .cache = input.cache.?,
            .key = key,
        });
        try parameter_summary.addSummary(arena, summary);
        if (input.shortcut) |state| {
            try state.summary(arena, index, summary);
            state.entries[index].summary_input = dependency;
        }
        input.returns[index] = summary.returned;
        _ = temporary.reset(.retain_capacity);
        _ = scratch.reset(.retain_capacity);
    }
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
const CachedFinal = struct { function: ir.Function, state: cache_mod.FinalState, analysis: cache_mod.Analysis };

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
            try table.deferArtifact(arena, request.function, context.store, context.factsKey(description.digest), artifact);
        } else state.known = if (state.known) |known| try known.clone(arena) else null;
        state.plans = try cache_mod.retainPlans(arena, state.plans);
        context.statistics.restores.final += 1;
        return .{ .function = restored, .state = state, .analysis = description };
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

const StageControl = struct { cache: ?*cache_mod.Context, shortcut: ?*shortcut_mod.Index };

fn unswitchFunctions(arena: std.mem.Allocator, module: *ir.Module, result: *Result, control: StageControl, mode: Mode, temporary: *std.heap.ArenaAllocator) Error!void {
    const cache = control.cache;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        if (control.shortcut) |state| if (state.green[index]) continue;
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
        if (control.shortcut) |state| try state.checkpoint(arena, @intCast(index), .{ .stage = .unswitch, .key = key, .changed = changed.? }, &result.provenance);
    }
}

const InlineRound = struct {
    cache: *cache_mod.Context,
    provenance: *origins.Table,
    counts: []u32,
    parameters: []const []const ?facts.Interval = &.{},
    stage: cache_mod.Stage,
    mode: Mode,
    shortcut: ?*shortcut_mod.Index = null,
};

fn inlineCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, round: InlineRound) CachedError!u32 {
    const cache = round.cache;
    const provenance = round.provenance;
    const parameters = round.parameters;
    const stage = round.stage;
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    var total: u32 = 0;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        if (round.shortcut) |state| {
            state.cursor(stage, @intCast(index));
            if (state.green[index]) continue;
        }
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
                try inline_leaves.cfgCallerDemandWithScratch(arena, work.allocator(), module, @intCast(index), provenance, cache.lazy.raw)
            else
                try inline_leaves.leafCallerDemand(arena, work.allocator(), module, @intCast(index), params, .{ .provenance = provenance, .raw = cache.lazy.raw });
            cache.changed(index);
            if (key) |digest| try cache.saveTransform(work.allocator(), digest, @intCast(index), provenance, changed.?);
        }
        round.counts[index] += changed.?;
        total += changed.?;
        if (round.shortcut) |state| try state.checkpoint(arena, @intCast(index), .{ .stage = stage, .key = key, .changed = changed.? }, provenance);
        _ = work.reset(.retain_capacity);
    }
    return total;
}

/// The internal functions in an order that puts each callee before its callers
/// (a depth-first postorder of the direct-call graph); a cycle is broken where the
/// search meets a function still open, whose calls then see no return interval.
fn calleesFirst(arena: std.mem.Allocator, module: *const ir.Module) Error![]const u32 {
    return calleesFirstIndexed(arena, module, null);
}

fn calleesFirstIndexed(arena: std.mem.Allocator, module: *const ir.Module, shortcut: ?*shortcut_mod.Index) Error![]const u32 {
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
            const cached_calls: ?[]const u32 = if (shortcut) |indexed| if (indexed.context.lazy.raw != null and indexed.green[top.function]) indexed.entries[top.function].demand.history.?.outputs[2].?.graph.calls else null else null;
            const edge_count = if (cached_calls) |calls| calls.len else insts.len;
            if (top.next < edge_count) {
                const next = top.next;
                top.next += 1;
                const callee = if (cached_calls) |calls| calls[next] else blk: {
                    const inst = insts[next];
                    if (inst.op != .call) continue;
                    break :blk inst.a.index();
                };
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
        return initIndexed(arena, module, null);
    }

    fn initIndexed(arena: std.mem.Allocator, module: *const ir.Module, shortcut: ?*shortcut_mod.Index) Error!ParameterSummary {
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
        for (module.functions.items, 0..) |function, index| {
            if (shortcut) |state| if (function.signature.linkage == .internal and state.context.lazy.raw != null and state.green[index]) {
                for (state.entries[index].demand.history.?.outputs[1].?.graph.references) |target| if (target < count) {
                    usable[target] = false;
                };
                continue;
            };
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

fn parameterSummaryAllocationFailure(a: std.mem.Allocator) Error!void {
    var functions = [_]ir.Function{
        .{ .name = "caller", .signature = .{ .params = &.{.i64}, .ret = .i64 } },
        .{ .name = "callee", .signature = .{ .params = &.{.i64}, .ret = .i64 } },
    };
    const module: ir.Module = .{ .functions = .{ .items = &functions, .capacity = functions.len } };
    const summary = try ParameterSummary.initIndexed(a, &module, null);
    defer a.free(summary.out);
    defer a.free(summary.usable);
    defer a.free(summary.merged);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "initIndexed parameter summaries release partial arrays on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parameterSummaryAllocationFailure, .{});
}
