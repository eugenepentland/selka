//! The release passes, in order, shared by `selka-core build`, `dump-ir --facts`
//! and the tests: leaf inlining, loop unswitching, facts, trip-count guards (then
//! facts again), ownership (`own.zig`, after the facts it may not disturb), and the
//! vector plans. Debug builds run only ownership (`ownership`).
const std = @import("std");
const cache_miss = @import("selka").cache_miss;
const fast_blake3 = @import("fast_blake3.zig");
const demand_ir = @import("demand_ir.zig");
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
const ownership_export = @import("ownership_export.zig");
const validate_ownership = @import("validate_ownership.zig");
const verify_ir = @import("verify_ir.zig");
const certificate = @import("ownership_certificate.zig");
const cutoff = @import("optimizer_cutoff.zig");

/// Passes allocate and reject malformed compiler ownership markers.
pub const Error = std.mem.Allocator.Error || own.Error;
pub const CachedError = @import("demand_ir.zig").Error || Error;

fn validateSelections(a: std.mem.Allocator, module: *const ir.Module) Error!void {
    @import("marker_validation.zig").validateModule(a, module) catch |err| switch (err) {
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
    emission: struct {
        verifying: bool = false,
        effects: ?effects.Summaries = null,
        /// The whole-program field intervals the final facts were computed under; a fact certificate states a field read through them.
        fields: facts.FieldIntervals = .{},
    } = .{},
    /// What ownership did: in-place updates, direct drops and stack promotion.
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
    return debugInternal(arena, backing, module, null, null);
}

/// Debug ownership with persistent function-stage reuse.
pub fn debugCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, cache: *cache_mod.Context) Error!Result {
    return debugInternal(arena, backing, module, cache, null);
}

/// Run the passes for a build that must report a located `E_CORE_UNSUPPORTED`
/// when ownership has no schedule: the refusal names the function, the
/// operation and its source span (REGRESSION-R2, DECISIONS F8).
pub const Reporting = struct {
    arena: std.mem.Allocator,
    backing: std.mem.Allocator,
    module: *ir.Module,
    /// Filled before `error.Unsupported` returns.
    refusal: *own.Refusal,

    /// Release passes with analysis backing.
    pub fn runWithScratch(self: Reporting, mode: Mode) Error!Result {
        return runInternal(self.arena, self.backing, self.module, mode, null, self.refusal) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => return error.Unsupported,
            error.CacheMiss => unreachable,
        };
    }

    /// Release passes with persistent function-stage reuse.
    pub fn runCached(self: Reporting, mode: Mode, cache: *cache_mod.Context) CachedError!Result {
        return runInternal(self.arena, self.backing, self.module, mode, cache, self.refusal);
    }

    /// Development emission with compact verified facts.
    pub fn runCachedDeferred(self: Reporting, mode: Mode, cache: *cache_mod.Context, table: *deferred_facts.Table) CachedError!Result {
        cache.deferred = table;
        return runInternal(self.arena, self.backing, self.module, mode, cache, self.refusal);
    }

    /// Debug passes retain a structured refusal without a persistent cache.
    pub fn debugWithScratch(self: Reporting) Error!Result {
        return debugInternal(self.arena, self.backing, self.module, null, self.refusal);
    }

    /// Debug passes with persistent reuse.
    pub fn debugCached(self: Reporting, cache: *cache_mod.Context) Error!Result {
        return debugInternal(self.arena, self.backing, self.module, cache, self.refusal);
    }
};

fn debugInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context, refusal: ?*own.Refusal) Error!Result {
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
            if (cache_mod.validFinal(cached, false) and (!validating(refusal) or cached.state.validated)) if (try cache.?.restoreFinal(arena, @intCast(index), cached, &result.provenance)) |restored| {
                function.* = restored;
                local.own = cached.state.own;
                result.own.add(local.own);
                _ = work.reset(.retain_capacity);
                continue;
            };
            cache.?.rejected(.debug);
        }
        local.own = try own.functionWithScratch(arena, backing, module, function, .{ .function_index = @intCast(index), .effects = &summaries, .refusal = refusal });
        result.own.add(local.own);
        const validated = try validatedFinal(arena, backing, module, @intCast(index), refusal);
        if (cache) |context| {
            context.changed(index);
            if (key) |digest| try context.saveFinal(work.allocator(), digest, @intCast(index), &result.provenance, .{
                .known = null,
                .plans = &.{},
                .counts = .{},
                .own = local.own,
                .validated = validated,
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
    return runInternal(arena, backing, module, mode, null, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Unsupported,
        error.CacheMiss => unreachable, // No cache or lowering handles on this path.
    };
}

/// Apply stages in the same order as `runWithScratch`, restoring only validated functions.
pub fn runCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context) CachedError!Result {
    return runInternal(arena, backing, module, mode, cache, null);
}

/// Development emission retains compact verified facts and decodes only LLVM misses.
pub fn runCachedDeferred(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: *cache_mod.Context, table: *deferred_facts.Table) CachedError!Result {
    cache.deferred = table;
    return runInternal(arena, backing, module, mode, cache, null);
}

fn runInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: ?*cache_mod.Context, refusal: ?*own.Refusal) CachedError!Result {
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
        try inlineCached(arena, backing, module, .{ .cache = context, .result = &result, .counts = inlined, .stage = .inline_leaf, .mode = mode, .shortcut = if (shortcut) |*state| state else null }) +
            try inlineCached(arena, backing, module, .{ .cache = context, .result = &result, .counts = inlined, .stage = .inline_cfg, .mode = mode, .shortcut = if (shortcut) |*state| state else null })
    else
        try inline_leaves.inlineLeavesCountedWithScratch(arena, backing, module, &result.provenance, inlined);
    if (mode == .off) {
        const summaries = try effects.analyze(arena, module);
        for (module.functions.items, result.per_function, inlined, 0..) |*function, *local, expanded, index| {
            if (function.signature.linkage != .internal) continue;
            local.counts.inlined = expanded;
            local.own = try own.functionWithScratch(arena, backing, module, function, .{ .provenance = &result.provenance, .function_index = @intCast(index), .effects = &summaries, .refusal = refusal });
            result.own.add(local.own);
            _ = try validateOwnership(arena, backing, module, @intCast(index), refusal);
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
    completeJoins(if (shortcut) |*state| state else null, parameters);
    result.emission.fields = field_table;
    try resolveParameters(arena, if (shortcut) |*state| state else null, parameters, inlined, &result);
    try ensureRedRaw(cache, green);

    // Closed caller bounds can prove an affine callback safe only after the
    // all-call parameter pass. Deliberately corrupted facts cannot prove safety.
    if (sabotage == .none) result.counts.inlined += if (cache) |context|
        try inlineCached(arena, backing, module, .{
            .cache = context,
            .result = &result,
            .counts = inlined,
            .parameters = parameters,
            .stage = .parameter_inline,
            .mode = mode,
            .shortcut = if (shortcut) |*state| state else null,
        })
    else
        try inline_leaves.withParametersCountedWithScratch(arena, backing, module, parameters, &result.provenance, inlined);
    // The effect summaries of the inlined module; the passes below keep every function's meaning.
    const summaries = try prepareEffects(arena, module, cache, .{ .shortcut = if (shortcut) |*state| state else null, .parameters = parameters, .inlined = inlined, .result = &result });
    try observeFacts(cache, module, .{ .parameters = parameters, .returns = returns, .summaries = &summaries, .fields = field_table });
    try finalFunctions(.{ .arena = arena, .backing = backing, .temporary = &temporary, .scratch = &scratch }, module, cache, .{
        .result = &result,
        .effects = &summaries,
        .parameters = parameters,
        .returns = returns,
        .fields = field_table,
        .inlined = inlined,
        .options = .{ .mode = mode, .verify = verify, .sabotage = sabotage },
        .shortcut = if (shortcut) |*state| state else null,
        .refusal = refusal,
    });
    try retainEmissionEffects(arena, module, cache, if (shortcut) |*state| state else null, &result);
    if (shortcut) |*state| try saveIndex(state);
    try observeOptimized(cache, module, &result);
    if (cache) |context| if (context.statistics.restores.cutoff.findings != 0) {
        const first = shortcut.?.publication.cut.first.?;
        const stage: cache_mod.Stage = @fromBackingInt(@intCast(first[1]));
        std.debug.panic("early cutoff: {d} deferred functions read something that changed and were kept; the first is {s} at stage {s} (optimizer_cutoff.zig)", .{
            context.statistics.restores.cutoff.findings,
            module.functions.items[first[0]].name,
            @tagName(stage),
        });
    };
    return result;
}

/// Tell the engine's shadow, when it is watching, that the final stage analysed function `index` in this build.
fn markAnalysed(cache: ?*cache_mod.Context, index: usize) Error!void {
    const context = cache orelse return;
    const observer = context.lazy.optimized orelse return;
    try observer.markFresh(@intCast(index));
}

/// Hand the engine's shadow what the passes made of each function, when it is watching (`optimizer_shadow.zig`).
fn observeOptimized(cache: ?*cache_mod.Context, module: *const ir.Module, result: *const Result) Error!void {
    const context = cache orelse return;
    const observer = context.lazy.optimized orelse return;
    @import("optimizer_shadow.zig").collect(observer, module, context, .{ .provenance = &result.provenance }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
}

/// Hand the cross-function facts just joined to the engine's shadow, when it is watching (`program_facts_shadow.zig`). A module
/// whose canonical form is unknown (`UnknownMetadata`) is left unobserved, as the optimizer cache leaves it unkeyed.
fn observeFacts(cache: ?*cache_mod.Context, module: *const ir.Module, joined: @import("program_facts_shadow.zig").Joined) Error!void {
    const context = cache orelse return;
    const observer = context.lazy.facts orelse return;
    const state = if (context.prepared) |*prepared| prepared else return;
    @import("program_facts_shadow.zig").collect(observer, module, &state.canon, joined) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnknownMetadata => {},
    };
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
    var writer = @import("selka").persist_codec.Writer.init(arena);
    defer writer.deinit();
    try writer.write(@TypeOf(table.types), table.types);
    var digest: [32]u8 = undefined;
    fast_blake3.hash(writer.bytes.items, &digest);
    return digest;
}

fn fieldInput(arena: std.mem.Allocator, context: ?*cache_mod.Context, table_digest: [32]u8, calls: struct { returns: []const ?facts.Interval, targets: []const u32 }) Error![32]u8 {
    var writer = @import("selka").persist_codec.Writer.init(arena);
    defer writer.deinit();
    try writer.write([32]u8, table_digest);
    for (calls.targets) |target| {
        // The callee by the digest of its reference, so the input does not move when a function is added elsewhere.
        if (context) |prepared| if (prepared.calleeName(target)) |name| {
            try writer.write([32]u8, name);
        } else try writer.write(u32, target) else try writer.write(u32, target);
        try writer.write(?facts.Interval, calls.returns[target]);
    }
    var digest: [32]u8 = undefined;
    fast_blake3.hash(writer.bytes.items, &digest);
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

/// A deferred function whose exploration input differs from its entry's is recomputed from here on. With the cutoff that is the
/// function alone: its callers compare their own inputs at their turns. Otherwise every deferred function is (`demoteExploration`).
fn demoteDeferred(arena: std.mem.Allocator, shortcut: ?*shortcut_mod.Index, index: usize, inlined: []u32, result: *Result) CachedError!void {
    const state = shortcut orelse return;
    if (!state.publication.cut.active()) return demoteExploration(arena, shortcut, inlined, result);
    const events = try state.demoteAt(@intCast(index), .parameter_inline);
    inlined[index] = events.inlined;
    result.counts.inlined += events.inlined;
    result.per_function[index].counts.unswitched = events.unswitched;
    result.counts.unswitched += events.unswitched;
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
    const digest = try fieldInput(a, context, table_digest, .{ .returns = input.returns, .targets = targets });
    return digest;
}

fn savedSummary(state: *shortcut_mod.Index, module: *ir.Module, index: usize, dependency: ?[32]u8) CachedError!?cache_mod.Summary {
    try state.settle(@intCast(index));
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

fn savedFieldRound(module: *const ir.Module, state: *shortcut_mod.Index, index: usize, round: usize, dependency: [32]u8) CachedError!?shortcut_mod.FieldRound {
    try state.settle(@intCast(index));
    const saved = state.entries[index].demand.fields.rounds[round] orelse return null;
    if (!saved.summary.valid(module) or !saved.writes.valid(module)) return null;
    if (!std.mem.eql(u8, &saved.input, &dependency)) return null;
    return saved;
}

/// Two whole-program field rounds retain compact evidence instead of fact arrays or bodies. A build whose entries came from a state
/// with stored joins takes the joins for the functions left alone when every recomputed function contributes what its stored row held
/// (`fastFieldSummaries`); otherwise every function is visited (`fullFieldSummaries`).
fn fieldSummaries(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, work: ExplorationWork) CachedError!facts.FieldIntervals {
    if (input.shortcut) |state| if (state.joinsToTake()) |stored| {
        if (try fastFieldSummaries(arena, module, input, .{ .work = work, .state = state, .stored = stored })) |table| return table;
        // A recomputed function contributed something else: start again with every function visited.
        @memset(input.returns, null);
        state.context.statistics.restores.cutoff.rejoined += 1;
    };
    return fullFieldSummaries(arena, module, input, work);
}

/// Publish the index of a finished build; the verify mode first reads the rows it left unread and checks them.
fn saveIndex(state: *shortcut_mod.Index) CachedError!void {
    if (state.publication.cut.mode == .verify) try state.verifyRows();
    try state.save();
}

/// Complete the joins this build made with the hulls its rounds led to and, in the verify mode, check them against the stored ones.
fn completeJoins(shortcut: ?*shortcut_mod.Index, parameters: []const []const ?facts.Interval) void {
    const state = shortcut orelse return;
    state.finishJoins(parameters);
    if (state.publication.cut.mode == .verify) state.verifyJoins();
}

/// The verify mode's comparison of a function recomputed in a full round with the row the stored joins were made from.
fn compareWithStored(arena: std.mem.Allocator, state: *shortcut_mod.Index, module: *const ir.Module, request: struct { function: usize, fresh: shortcut_mod.Fresh, demoted: bool }) CachedError!void {
    if (state.publication.cut.mode != .verify or state.publication.joins.stored == null) return;
    const references = try shortcut_mod.Index.targetsOf(arena, &module.functions.items[request.function], .func_ref);
    var fresh = request.fresh;
    fresh.references = references;
    const same = try state.sameAsStored(@intCast(request.function), fresh);
    if (!same and !request.demoted) state.publication.joins.differs = true;
}

/// A deferred function whose dependencies differ from its entry's is recomputed from here on; the verify mode remembers the first.
fn demoteInRound(arena: std.mem.Allocator, state: *shortcut_mod.Index, index: usize, counted: struct { inlined: []u32, result: *Result }) CachedError!bool {
    try demoteDeferred(arena, state, index, counted.inlined, counted.result);
    // A deferred function from another manifest is compared with the stored row, so the fast rounds would not have taken the joins.
    if (!state.inJoinedSlot(index)) state.publication.joins.differs = true else if (state.publication.joins.demoted == null) state.publication.joins.demoted = @intCast(index);
    return true;
}

/// What the fast field rounds work with: the build's scratch, the index and the joins stored beside the entries it started from (D-G3p-17).
const FastRounds = struct { work: ExplorationWork, state: *shortcut_mod.Index, stored: @import("optimizer_joins.zig").Joins };

/// The field rounds of a build whose deferred functions are exactly the stored ones. A deferred function was found under its lowering key,
/// so its body, its callees' declarations and the checkpoints it saw are those of its row; what its row contributed to the field table, the
/// parameter hulls and its callers' dependency inputs is what the stored joins hold as long as the functions recomputed contribute the
/// same. Those are visited as the full rounds visit them; the others only note their stored return interval at their turn in the order.
/// Null when a recomputed function contributes something else (or has no stored row to compare with): the caller then takes the full rounds.
fn fastFieldSummaries(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, fast: FastRounds) CachedError!?facts.FieldIntervals {
    const temporary = fast.work.temporary;
    const scratch = fast.work.scratch;
    const state = fast.state;
    const stored = fast.stored;
    const order = try calleesFirstIndexed(arena, module, input.shortcut);
    var table: facts.FieldIntervals = .{ .module = module };
    var table_digest = try fieldDigest(temporary.allocator(), table);
    for (0..2) |round| {
        for (order) |index| {
            if (index >= stored.returns[round].len) return null;
            const kept = state.green[index];
            if (kept and state.inJoinedSlot(index)) {
                input.returns[index] = stored.returns[round][index];
                continue;
            }
            const function = &module.functions.items[index];
            const targets = try explorationTargets(temporary.allocator(), module, input.shortcut, index);
            const dependency = try fieldInput(temporary.allocator(), input.cache, table_digest, .{ .returns = input.returns, .targets = targets });
            var record: ?shortcut_mod.FieldRound = null;
            if (kept or state.isLoose(index)) {
                // A deferred function from another manifest keeps its own round when its dependencies are the same, and is compared with the
                // stored row like a recomputed one; when they are not, the full rounds recompute it.
                record = try savedFieldRound(module, state, index, round, dependency);
                if (record == null and kept) return null;
                if (record != null and !kept) state.context.statistics.restores.rounds += 1;
            }
            if (record == null) record = try freshRound(arena, module, input, .{ .function = index, .round = round, .table = table, .dependency = dependency, .scratch = fast.work });
            const current = record.?;
            const references = try shortcut_mod.Index.targetsOf(temporary.allocator(), function, .func_ref);
            if (!try state.sameAsStored(@intCast(index), .{ .round = round, .record = current, .targets = targets, .references = references })) return null;
            input.returns[index] = current.summary.returned;
            if (round == 1) try state.summary(arena, index, current.summary);
            _ = temporary.reset(.retain_capacity);
            _ = scratch.reset(.retain_capacity);
        }
        table = .{ .module = module, .types = stored.tables[round].types };
        table_digest = stored.tables[round].digest;
    }
    for (state.entries) |*entry| entry.demand.fields.final = table_digest;
    for (stored.hulls, 0..) |hull, index| fast.work.parameters.out[index] = hull;
    state.publication.joins.made = stored;
    state.context.statistics.restores.cutoff.joined += 1;
    return table;
}

/// What `freshRound` analyses: the function and round, the table the round starts from, the dependency digest and the build's scratch.
const FreshRound = struct { function: usize, round: usize, table: facts.FieldIntervals, dependency: [32]u8, scratch: ExplorationWork };

/// Analyse function `request.function` afresh in a field round and keep what the round holds of it.
fn freshRound(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, request: FreshRound) CachedError!shortcut_mod.FieldRound {
    const function = &module.functions.items[request.function];
    const known = try facts.analyzeWithScratch(request.scratch.temporary.allocator(), request.scratch.scratch.allocator(), function, .{
        .fold = input.mode == .trusted,
        .sabotage = input.sabotage,
        .mark = false,
        .returns = input.returns,
        .fields = request.table,
    });
    const record: shortcut_mod.FieldRound = .{
        .input = request.dependency,
        .summary = try cache_mod.summarize(arena, request.scratch.scratch.allocator(), module, function, &known, input.sabotage),
        .writes = try fields.contribution(arena, module, function, &known),
    };
    if (input.cache) |context| context.changed(request.function);
    if (input.shortcut) |state| state.entries[request.function].demand.fields.rounds[request.round] = record;
    return record;
}

fn fullFieldSummaries(arena: std.mem.Allocator, module: *ir.Module, input: Exploration, work: ExplorationWork) CachedError!facts.FieldIntervals {
    const temporary = work.temporary;
    const scratch = work.scratch;
    const parameters = work.parameters;
    const inlined = work.inlined;
    const result = work.result;
    const contributions = try arena.alloc(?fields.Contribution, module.functions.items.len);
    @memset(contributions, null);
    const order = try calleesFirstIndexed(arena, module, input.shortcut);
    var table: facts.FieldIntervals = .{ .module = module };
    var table_digest = try fieldDigest(temporary.allocator(), table);
    for (0..2) |round| {
        parameters.* = try ParameterSummary.initIndexed(arena, module, input.shortcut);
        for (module.functions.items) |*function| {
            if (function.signature.linkage != .internal) try parameters.add(arena, module, function, null);
        }
        for (order) |index| {
            const targets = try explorationTargets(temporary.allocator(), module, input.shortcut, index);
            const dependency = try fieldInput(temporary.allocator(), input.cache, table_digest, .{ .returns = input.returns, .targets = targets });
            var record: ?shortcut_mod.FieldRound = null;
            var demoted = false;
            if (input.shortcut) |state| {
                if (state.green[index]) {
                    record = try savedFieldRound(module, state, index, round, dependency);
                    if (record == null) demoted = try demoteInRound(arena, state, index, .{ .inlined = inlined, .result = result });
                } else if (state.isLoose(index)) {
                    // Red only by position: the round it saw is this round when its dependencies are the same (G3p-0).
                    record = try savedFieldRound(module, state, index, round, dependency);
                    if (record != null) state.context.statistics.restores.rounds += 1;
                }
            }
            if (record == null) {
                record = try freshRound(arena, module, input, .{ .function = index, .round = round, .table = table, .dependency = dependency, .scratch = work });
                if (input.shortcut) |state| try compareWithStored(temporary.allocator(), state, module, .{ .function = index, .fresh = .{ .round = round, .record = record.?, .targets = targets, .references = &.{} }, .demoted = demoted });
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
        table_digest = try fieldDigest(temporary.allocator(), table);
        if (input.shortcut) |state| try state.noteRound(arena, round, .{ .table = table, .digest = table_digest, .returns = input.returns });
    }
    if (input.shortcut) |state| {
        for (state.entries, state.green, module.functions.items) |entry, green, function| {
            if (!green or function.signature.linkage != .internal) continue;
            if (entry.demand.fields.final == null) {
                try demoteExploration(arena, input.shortcut, inlined, result);
                break;
            }
            if (!std.mem.eql(u8, &entry.demand.fields.final.?, &table_digest)) {
                try demoteExploration(arena, input.shortcut, inlined, result);
                break;
            }
        }
        for (state.entries) |*entry| entry.demand.fields.final = table_digest;
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
    inlined: []u32,
    options: struct { mode: Mode, verify: bool, sabotage: facts.Sabotage },
    shortcut: ?*shortcut_mod.Index,
    /// Where the ownership pass stopped, when the caller wants it named.
    refusal: ?*own.Refusal = null,
};

/// The early cutoff at the final stage (G3p (c)): a deferred function whose callee changed the return interval or effect its final key
/// reads is recomputed, with the events of the stages it skipped counted.
fn finalCutoff(shortcut: ?*shortcut_mod.Index, index: usize, counted: struct { inlined: []u32, result: *Result }) CachedError!void {
    const state = shortcut orelse return;
    if (index >= state.green.len or !state.green[index]) return;
    const skipped = (try state.finalDemote(@intCast(index))) orelse return;
    counted.inlined[index] = skipped.inlined;
    counted.result.counts.inlined += skipped.inlined;
    counted.result.per_function[index].counts.unswitched = skipped.unswitched;
    counted.result.counts.unswitched += skipped.unswitched;
}

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
        try finalCutoff(shortcut, index, .{ .inlined = inlined, .result = result });
        if (cache) |context| try verifyFinal(context, shortcut, .{
            .stage = .final,
            .function = @intCast(index),
            .mode = @backingInt(mode),
            .provenance = &result.provenance,
            .inputs = .{ .parameters = params, .fields = fields_digest, .returns = returns, .effects = &summaries },
        }, temporary.allocator());
        _ = temporary.reset(.retain_capacity);
        result.per_function[index].counts.inlined = inlined[index];
        if (cache) |context| if (context.lazy.raw != null and index < green.len and green[index]) {
            try serveByMetadata(context, shortcut.?, index, .{ .result = result, .validating = validating(round.refusal) });
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
        if (try cachedFinal(arena, temporary.allocator(), cache, .{ .function = @intCast(index), .key = key, .provenance = &result.provenance, .validated = validating(round.refusal) })) |cached| {
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
        result.per_function[index].own = try own.functionWithScratch(arena, backing, module, function, .{
            .verify = verify,
            .facts = &known,
            .provenance = &result.provenance,
            .function_index = @intCast(index),
            .effects = &summaries,
            .refusal = round.refusal,
        });
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
        const validated = try validatedFinal(arena, backing, module, @intCast(index), round.refusal);

        // Vector code comes only from trusted facts, never in a verify build.
        if (!verify) plan.* = try vector.plan(arena, function, known);
        const artifact = try retainFinalFacts(arena, temporary.allocator(), cache, index, &known);
        slot.* = if (artifact == null) known else null;
        result.per_function[index].counts.vectorized = @intCast(plan.len);
        try markAnalysed(cache, index);
        result.counts.vectorized += @intCast(plan.len);
        if (cache) |context| {
            context.changed(index);
            if (key) |digest| try context.saveFinal(temporary.allocator(), digest, @intCast(index), &result.provenance, .{
                .known = known,
                .plans = plan.*,
                .counts = result.per_function[index].counts,
                .own = result.per_function[index].own,
                .artifact = artifact,
                .validated = validated,
            });
        }
        if (shortcut) |state| if (key) |digest| if (artifact) |encoded| try rememberFinal(arena, cache.?, state, index, .{
            .key = digest,
            .provenance = &result.provenance,
            .state = .{ .known = null, .plans = plan.*, .counts = result.per_function[index].counts, .own = result.per_function[index].own, .validated = validated },
            .analysis = .{ .digest = encoded.digest, .loop_ids = encoded.loop_ids },
        });
        _ = temporary.reset(.retain_capacity);
    }
}

// Split fusions append compound types and helper declarations outside the slice
// recorder, so they must see every body that calls a split. The demand shortcut
// therefore never defers such a body (or, through its callers, anything that
// inlines it); every other body stays eligible. Marks the split declarations.
fn splitDeclarations(arena: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error![]const bool {
    const marks = try arena.alloc(bool, module.functions.items.len);
    @memset(marks, false);
    for (module.functions.items, marks) |function, *mark| mark.* = splitDeclaration(module, function);
    return marks;
}

fn splitDeclaration(module: *const ir.Module, function: ir.Function) bool {
    const sig = function.signature;
    // The explicit split takes spans (C9 2b, views 3); the catalog lists it either way.
    const whitespace_span = std.mem.eql(u8, function.name, "myl_core_span_str_split_whitespace");
    const takes_spans = whitespace_span or sig.passing.views == 0 or sig.passing.views == 3;
    if (sig.linkage == .internal or !takes_spans) return false;
    if (sig.passing.hasOwned() or sig.passing.hasConsumes() or sig.passing.hasExtras()) return false;
    if (module.kind(sig.ret) != .list or module.compound(sig.ret).list != .str) return false;
    const explicit = std.mem.eql(u8, function.name, "myl_core_str_split");
    const whitespace = sig.linkage == .runtime_c and @import("copy_sites.zig").isWhitespaceSplit(function.name);
    if (!explicit and !whitespace) return false;
    return std.mem.eql(ir.Type, sig.params, if (explicit) &.{ .str, .str } else &.{.str});
}

fn prepareOptimizer(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, mode: Mode, cache: ?*cache_mod.Context) CachedError!?shortcut_mod.Index {
    var shortcut: ?shortcut_mod.Index = if (cache) |context| blk: {
        if (context.lazy.raw == null or (mode != .verify and mode != .trusted)) break :blk null;
        break :blk try shortcut_mod.Index.prepareDemand(arena, context, .{ .mode = @backingInt(mode), .field_proof = hasRecordTypes(module), .eager_callees = try splitDeclarations(arena, module), .cutoff = context.lazy.cutoff });
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
    } else if (shortcut) |*state| state.catalog = .{ .raw_count = module.functions.items.len, .raw_layout = state.catalog.raw_layout };
    try @import("fuse_text.zig").whitespace(arena, module);
    try @import("split_views.zig").run(arena, module);
    const fusion_requests: ?[]std.ArrayList(u32) = if (shortcut != null)
        try arena.alloc(std.ArrayList(u32), before_fusions.len)
    else
        null;
    if (fusion_requests) |requests| @memset(requests, .empty);
    _ = try @import("fuse_encode.zig").runRecording(arena, module, fusion_requests);
    _ = try @import("fuse_slice_key.zig").runRecording(arena, module, fusion_requests);
    if (cache) |context| try context.prepare(arena);
    if (shortcut) |*state| {
        if (state.catalog.layout) |old| if (seeded) {
            const current = cache.?.layoutDigest() orelse return cache_miss.at(@src());
            if (!std.mem.eql(u8, &old, &current)) return cache_miss.at(@src());
        };
        try state.extend(arena);

        for (state.entries, state.green, 0..) |*entry, green_body, index| {
            if (green_body) {
                cache.?.prepared.?.digests[index] = entry.raw;
                state.publication.cut.noteBase(index, entry.raw, entry.raw);
                continue;
            }
            const identity_known = entry.raw != null;
            const was_raw = entry.raw;
            entry.raw = try cache.?.bodyDigest(@intCast(index));
            state.publication.cut.noteBase(index, was_raw, entry.raw);
            state.noteLoose(index);
            if (identity_known or index >= before_fusions.len) continue;
            const after = @import("ir_snapshot.zig").digest(fusion_scratch.allocator(), cache.?.source, module.functions.items[index]) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidSnapshot => null,
            };
            _ = fusion_scratch.reset(.retain_capacity);
            entry.demand.fusion.identity = before_fusions[index] != null and after != null and std.mem.eql(u8, &before_fusions[index].?, &after.?);
        }
        try finishFusionInputs(arena, &fusion_scratch, state, .{ .seeded = seeded, .requests = fusion_requests.? });
    } else shortcut = try prepareShortcut(arena, cache, mode);
    return shortcut;
}

fn finishFusionInputs(arena: std.mem.Allocator, temporary: *std.heap.ArenaAllocator, state: *shortcut_mod.Index, replay: struct { seeded: bool, requests: []const std.ArrayList(u32) }) CachedError!void {
    const scratch = temporary.allocator();
    const fusion = @import("fusion_checkpoint.zig");
    const module = state.context.source.module;
    const raw_count = state.catalog.raw_count;
    if (raw_count > module.functions.items.len) return cache_miss.at(@src());
    const requests = try arena.alloc([]const u32, raw_count);
    for (state.entries[0..raw_count], state.green[0..raw_count], requests, 0..) |*entry, green, *inventory, index| {
        // A catalog that holds no requests (the empty one of a program whose layout moved) holds none for any function.
        const stored: []const u32 = if (index < state.catalog.requests.len) state.catalog.requests[index] else &.{};
        if (green and module.functions.items[index].signature.linkage == .internal) {
            inventory.* = stored;
            continue;
        }
        inventory.* = replay.requests[index].items;
        if (replay.seeded and !std.mem.eql(u32, inventory.*, stored)) return cache_miss.at(@src());
        if (!entry.demand.fusion.identity) if (entry.demand.lowered) |lowered| if (entry.raw) |output| {
            entry.demand.fusion.key = try fusion.save(scratch, state.context, @intCast(index), lowered, output);
        };
        _ = temporary.reset(.retain_capacity);
    }
    const declarations = try arena.alloc(fusion.Declaration, module.functions.items.len - raw_count);
    for (module.functions.items[raw_count..], declarations) |function, *declaration| {
        if (function.signature.linkage != .runtime_c) return cache_miss.at(@src());
        declaration.* = .{ .name = function.name, .signature = function.signature };
    }
    state.catalog = .{ .layout = state.context.layoutDigest(), .raw_layout = state.catalog.raw_layout, .raw_count = raw_count, .declarations = declarations, .requests = requests };
}

fn hasDeferredBodies(state: *const shortcut_mod.Index, module: *const ir.Module) bool {
    for (state.green, module.functions.items[0..state.green.len]) |green, function| {
        if (green and function.signature.linkage == .internal) return true;
    }
    return false;
}

/// What the effects of the inlined module reuse: the demand shortcut and the parameter hulls each function ended with.
const EffectReuse = struct { shortcut: ?*shortcut_mod.Index, parameters: []const []const ?facts.Interval, inlined: []u32, result: *Result };

fn prepareEffects(arena: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context, reuse: EffectReuse) CachedError!effects.Summaries {
    const shortcut = reuse.shortcut;
    const reused_effects = try arena.alloc(?effects.Reused, module.functions.items.len);
    @memset(reused_effects, null);
    if (shortcut) |state| for (state.green, state.entries, reused_effects) |green_body, entry, *slot| {
        if (green_body) slot.* = entry.demand.effect;
    };
    if (shortcut) |state| try reuseLooseEffects(arena, module, state, reuse.parameters, reused_effects);
    var summaries = try effects.analyzeReused(arena, module, reused_effects);
    if (shortcut) |state| if (state.publication.cut.active()) {
        summaries = try settleEffects(arena, module, state, .{ .reused = reused_effects, .summaries = summaries, .inlined = reuse.inlined, .result = reuse.result });
    };
    // Install the internal calling convention before any ownership body runs.
    // The proof survives omitted bodies; the closed catalog guard is checked anew.
    // Source `mut` result fields remain described by Signature.passing ownership.
    const changed_convention = installConsuming(module, &summaries);
    if (changed_convention) if (cache) |context| try context.prepare(arena);
    if (cache) |context| {
        context.lazy.finals = try arena.alloc(?cache_mod.FinalMetadata, module.functions.items.len);
        @memset(context.lazy.finals, null);
        context.lazy.loaded = try arena.alloc(bool, module.functions.items.len);
        @memset(context.lazy.loaded, true);
    }
    // A function that kept the effect its entry holds keeps that retained copy: the analysis returned the same slices.
    if (shortcut) |state| for (state.entries, summaries.params, summaries.may, reused_effects) |*entry, params_effect, answers, kept| {
        if (kept != null) continue;
        entry.demand.effect = try effects.retain(arena, .{ .params = params_effect, .may = answers });
    };
    return summaries;
}

/// Whether an analysis gave function `index` the effect `old` holds (the same paths, not the same bytes: the analysis keeps its path sets sorted
/// but their capacities and the build that wrote them are not part of the effect).
fn sameEffect(summaries: effects.Summaries, index: usize, old: ?effects.Reused) bool {
    const was = old orelse return false;
    if (!std.meta.eql(summaries.may[index], was.may)) return false;
    const now = summaries.params[index];
    if (now.len != was.params.len) return false;
    for (now, was.params) |each, before| {
        if (each.borrow_only != before.borrow_only or each.consumes != before.consumes) return false;
        if (!each.reads.same(&before.reads) or !each.writes.same(&before.writes)) return false;
        if (!each.when_true.same(&before.when_true) or !each.when_false.same(&before.when_false)) return false;
    }
    return true;
}

/// The functions whose reused result is not right because they share a call cycle with a function computed afresh: `edges` are the
/// callees of each function (a reused function's from its entry, the others' from their bodies).
fn reusedInFreshCycle(arena: std.mem.Allocator, module: *const ir.Module, reused: []const ?effects.Reused, stored: []const ?[]const u32) std.mem.Allocator.Error![]bool {
    const count = module.functions.items.len;
    const edges = try arena.alloc([]const u32, count);
    const fresh = try arena.alloc(bool, count);
    for (module.functions.items, edges, fresh, 0..) |function, *each, *is_fresh, index| {
        is_fresh.* = function.signature.linkage == .internal and reused[index] == null;
        each.* = &.{};
        if (function.signature.linkage != .internal) continue;
        if (stored[index]) |calls| {
            each.* = calls;
            continue;
        }
        var calls: std.ArrayList(u32) = .empty;
        for (function.insts.items) |inst| if (inst.op == .call) try calls.append(arena, @intCast(inst.a.index()));
        each.* = calls.items;
    }
    return cutoff.sharesCycle(arena, edges, fresh);
}

/// What `settleEffects` works on: the slots reused and the analysis made with them, and the build's event counts.
const EffectSettle = struct { reused: []?effects.Reused, summaries: effects.Summaries, inlined: []u32, result: *Result };

/// The early cutoff of the effects (G3p (c)). A function whose effect was not reused changed it when it differs from its entry's.
/// A function whose effect was reused is only right while every callee of its final body kept the effect it had, so a reusing
/// function that calls a changed one computes its own from here (a deferred function is restored at the checkpoint after the
/// parameter inlining first), and the analysis runs again until no reused effect reads a changed one.
fn settleEffects(arena: std.mem.Allocator, module: *ir.Module, state: *shortcut_mod.Index, work: EffectSettle) CachedError!effects.Summaries {
    var summaries = work.summaries;
    const cut = &state.publication.cut;
    const count = module.functions.items.len;
    while (true) {
        for (module.functions.items, 0..) |function, index| {
            if (function.signature.linkage != .internal or work.reused[index] != null or index >= cut.moved.len) continue;
            if (!sameEffect(summaries, index, state.entries[index].demand.effect)) cut.mark(index, cutoff.Moved.effect);
        }
        var again = false;
        const stored = try arena.alloc(?[]const u32, count);
        for (stored, 0..) |*each, index| each.* = if (state.green[index] and module.functions.items[index].signature.linkage == .internal)
            (state.record(@intCast(index), .parameter) orelse return cache_miss.at(@src())).graph.calls
        else
            null;
        const cyclic = try reusedInFreshCycle(arena, module, work.reused, stored);
        for (0..count) |index| {
            if (work.reused[index] == null or module.functions.items[index].signature.linkage != .internal) continue;
            const deferred = state.green[index];
            if (!deferred and !state.isLoose(index)) continue;
            if (!cyclic[index] and !try state.callsChanged(@intCast(index), deferred, cutoff.Moved.effect)) continue;
            if (deferred) {
                const events = try state.demoteAt(@intCast(index), .final);
                work.inlined[index] = events.inlined;
                work.result.counts.inlined += events.inlined;
                work.result.per_function[index].counts.unswitched = events.unswitched;
                work.result.counts.unswitched += events.unswitched;
            }
            work.reused[index] = null;
            again = true;
        }
        if (!again) {
            if (cut.mode == .verify) try verifyEffects(arena, module, state, work.reused);
            return summaries;
        }
        summaries = try effects.analyzeReused(arena, module, work.reused);
    }
}

/// A function that is red only by position keeps the effect its entry holds when its parameter hull is the one the entry saw (the
/// parameter round inlines by hull) and every function it calls keeps its effect too: the effect is a function of the body after
/// that round and of the callees' effects, and the entry's body and callees are those of this build (G3p-0, `looseEntries`).
fn reuseLooseEffects(arena: std.mem.Allocator, module: *const ir.Module, state: *shortcut_mod.Index, parameters: []const []const ?facts.Interval, reused: []?effects.Reused) Error!void {
    const count = module.functions.items.len;
    const keep = try arena.alloc(bool, count);
    @memset(keep, false);
    var candidates: std.ArrayList(u32) = .empty;
    for (0..count) |index| {
        if (!state.isLoose(index) or state.green[index] or index >= parameters.len) continue;
        const entry = state.entries[index];
        if (entry.demand.effect == null or !shortcut_mod.equalRanges(entry.parameters, parameters[index])) continue;
        keep[index] = true;
        try candidates.append(arena, @intCast(index));
    }
    var changed = candidates.items.len != 0;
    while (changed) {
        changed = false;
        for (candidates.items) |index| {
            if (!keep[index]) continue;
            for (module.functions.items[index].insts.items) |inst| {
                if (inst.op != .call) continue;
                const callee = inst.a.index();
                if (callee >= count or module.functions.items[callee].signature.linkage != .internal) continue;
                if (state.green[callee] or keep[callee]) continue;
                keep[index] = false;
                changed = true;
                break;
            }
        }
    }
    for (candidates.items) |index| if (keep[index]) {
        reused[index] = state.entries[index].demand.effect;
        state.context.statistics.restores.effects += 1;
    };
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
        changed = changed or function.signature.passing.consumes != mask;
        // This profitability proof only selects compact positions. A retained
        // arbitrary-position ownership convention remains part of the ABI.
        function.signature.passing.consumes = mask;
    }
    return changed;
}

fn retainEmissionEffects(arena: std.mem.Allocator, module: *ir.Module, cache: ?*cache_mod.Context, shortcut: ?*shortcut_mod.Index, result: *Result) CachedError!void {
    if (cache) |context| if (context.lazy.raw != null) {
        const final_reused = try arena.alloc(?effects.Reused, module.functions.items.len);
        @memset(final_reused, null);
        for (context.lazy.finals, context.lazy.loaded, final_reused) |metadata, present, *slot| {
            if (!present) slot.* = metadata.?.emission_effect;
        }
        var final_effects = try effects.analyzeReused(arena, module, final_reused);
        if (shortcut) |state| if (state.publication.cut.active()) {
            final_effects = try settleEmission(arena, module, context, state, .{ .reused = final_reused, .summaries = final_effects, .result = result });
        };
        result.emission.effects = final_effects;
        if (shortcut) |state| for (context.lazy.finals, final_effects.params, final_effects.may, final_reused, 0..) |*metadata, param_effects, answers, kept, index| {
            // A function that kept its emission effect keeps the retained copy its metadata holds.
            if (kept != null) continue;
            if (metadata.*) |*record| {
                record.emission_effect = try effects.retain(arena, .{ .params = param_effects, .may = answers });
                state.entries[index].demand.metadata = record.*;
            }
        };
    };
}

/// What `settleEmission` works on: the slots reused, the analysis made with them, and the build's result.
const EmissionSettle = struct { reused: []?effects.Reused, summaries: effects.Summaries, result: *Result };

/// The early cutoff of the emission effects, as `settleEffects` is for the effects of the optimizer: a deferred function whose
/// final body calls a function whose emission effect changed has its final body restored and its own effect computed.
fn settleEmission(arena: std.mem.Allocator, module: *ir.Module, context: *cache_mod.Context, state: *shortcut_mod.Index, work: EmissionSettle) CachedError!effects.Summaries {
    var summaries = work.summaries;
    const cut = &state.publication.cut;
    while (true) {
        for (module.functions.items, 0..) |function, index| {
            if (function.signature.linkage != .internal or work.reused[index] != null or index >= cut.moved.len) continue;
            if (!sameEffect(summaries, index, cut.old_emission[index])) cut.mark(index, cutoff.Moved.emission);
        }
        var again = false;
        const stored = try arena.alloc(?[]const u32, module.functions.items.len);
        for (stored, context.lazy.finals, context.lazy.loaded) |*each, maybe, present| each.* = if (present) null else if (maybe) |metadata| metadata.outgoing else null;
        const cyclic = try reusedInFreshCycle(arena, module, work.reused, stored);
        for (context.lazy.finals, context.lazy.loaded, 0..) |maybe, present, index| {
            if (present or work.reused[index] == null) continue;
            const metadata = maybe orelse continue;
            var reads = cyclic[index];
            for (metadata.outgoing) |target| {
                if (target == index or target >= cut.moved.len or module.functions.items[target].signature.linkage != .internal) continue;
                reads = reads or cut.moved[target] & cutoff.Moved.emission != 0;
            }
            if (!reads) continue;
            cut.old_emission[index] = metadata.emission_effect;
            try restoreDeferredFinal(arena, arena, context, @intCast(index), work.result);
            work.reused[index] = null;
            again = true;
        }
        if (!again) return summaries;
        summaries = try effects.analyzeReused(arena, module, work.reused);
    }
}

const FinalInput = struct { key: [32]u8, state: cache_mod.FinalState, analysis: cache_mod.Analysis, provenance: *const origins.Table };

fn rememberFinal(arena: std.mem.Allocator, context: *cache_mod.Context, shortcut: *shortcut_mod.Index, index: usize, input: FinalInput) Error!void {
    const state = input.state;
    const analysis = input.analysis;
    const body = try context.bodyDigest(@intCast(index)) orelse return;
    const plain = try context.plainDigest(@intCast(index)) orelse return;
    var retained = state;
    retained.known = null;
    retained.artifact = null;
    retained.plans = try cache_mod.retainPlans(arena, state.plans);
    const metadata: cache_mod.FinalMetadata = .{
        .key = input.key,
        .body = .{ .positioned = body, .plain = plain },
        .outgoing = try shortcut_mod.Index.targets(arena, &context.source.module.functions.items[index]),
        .render = try context.renderMetadata(arena, @intCast(index), input.provenance) orelse return,
        .analysis = .{ .digest = analysis.digest, .loop_ids = try arena.dupe(usize, analysis.loop_ids) },
        .state = retained,
    };
    if (index < shortcut.publication.cut.old_emission.len) {
        if (shortcut.entries[index].demand.metadata) |previous| shortcut.publication.cut.old_emission[index] = previous.emission_effect;
    }
    shortcut.entries[index].demand.metadata = metadata;
    if (index < context.lazy.finals.len) context.lazy.finals[index] = metadata;
}

/// Restore a deferred final body and its verified facts before an emission miss.
pub fn restoreDeferredFinal(arena: std.mem.Allocator, work: std.mem.Allocator, context: *cache_mod.Context, index: u32, result: *Result) CachedError!void {
    if (index >= context.lazy.loaded.len or context.lazy.loaded[index]) return;
    if (index >= context.lazy.finals.len) return cache_miss.at(@src());
    const metadata = context.lazy.finals[index] orelse return cache_miss.at(@src());
    const value = try cachedFinal(arena, work, context, .{ .function = index, .key = metadata.key, .provenance = &result.provenance }) orelse return cache_miss.at(@src());
    const kept = context.source.module.functions.items[index].module;
    context.source.module.functions.items[index] = value.function;
    context.source.module.functions.items[index].module = kept;
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
            input.returns[index] = try facts.returnRange(scratch.allocator(), &known, function, input.sabotage);
            _ = temporary.reset(.retain_capacity);
            _ = scratch.reset(.retain_capacity);
            continue;
        }
        const dependency = try summaryInput(temporary.allocator(), module, input, index, table_digest);
        if (index < green.len and green[index]) {
            if (try savedSummary(input.shortcut.?, module, index, dependency)) |summary| {
                try parameter_summary.addSummary(arena, summary);
                input.returns[index] = summary.returned;
                _ = temporary.reset(.retain_capacity);
                continue;
            }
            try demoteDeferred(arena, input.shortcut, index, work.inlined, work.result);
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

const FinalRequest = struct { function: u32, key: ?[32]u8, provenance: *origins.Table, validated: bool = false };
const CachedFinal = struct { function: ir.Function, state: cache_mod.FinalState, analysis: cache_mod.Analysis };

/// Whether the passes are asked to validate each function's ownership certificate.
fn validating(refusal: ?*own.Refusal) bool {
    const report = refusal orelse return false;
    const sink = report.certificates orelse return false;
    return sink.check;
}

/// Record a rejection. The passes stop at it, unless the sink keeps going so that certificates can still be written.
fn reject(arena: std.mem.Allocator, sink: *certificate.Sink, message: []const u8) Error!bool {
    _ = arena;
    if (sink.rejection == null) sink.rejection = message;
    if (sink.keep_going) return false;
    return error.Unsupported;
}

/// Validate function `index` of `module` now that its passes have finished: describe its final IR from the table the
/// ownership pass kept and run the validator (`validate_ownership.zig`). True when it ran. A rejection leaves its
/// message in the sink and fails the pass; a function the exporter cannot describe fails it too, since nothing
/// checked it.
fn validateOwnership(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, index: u32, refusal: ?*own.Refusal) Error!bool {
    if (!validating(refusal)) return false;
    const sink = refusal.?.certificates.?;
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    const a = work.allocator();
    const name = module.functions.items[index].name;
    switch (try ownership_export.build(a, module, sink, index)) {
        .refused => |reason| {
            return reject(arena, sink, try std.fmt.allocPrint(arena, "ownership validation could not describe {s}: {s}", .{ name, reason }));
        },
        .described => |function| switch (try validate_ownership.validateWith(a, function, .{ .construct_read = validate_ownership.build_mode, .counted = &sink.construct_reads })) {
            .accepted => sink.validated += 1,
            .unchecked => sink.unchecked += 1,
            .rejected => |failure| {
                const text = try validate_ownership.describe(a, name, failure);
                return reject(arena, sink, try arena.dupe(u8, text));
            },
        },
    }
    return true;
}

/// Where `serveByMetadata` records what it served, and whether the build validates.
const Served = struct { result: *Result, validating: bool };

/// Serve function `index`'s final body by its metadata alone (a green body of the demand shortcut): the body stays out of the
/// module and its counts come from the metadata. A validating build takes it only when the build that made it validated it
/// (`validatedFinal`), since no check of this build sees it; otherwise the build starts again with every body (`build_retry`).
fn serveByMetadata(context: *cache_mod.Context, shortcut: *const shortcut_mod.Index, index: usize, served: Served) CachedError!void {
    const metadata = shortcut.entries[index].demand.metadata orelse return cache_miss.at(@src());
    if (served.validating and !metadata.state.validated) return cache_miss.at(@src());
    const result = served.result;
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
}

/// Validate the final body of function `index` (`validateOwnership`), check its IR (`verify_ir.functionHolds`) and check it has no
/// hidden copy (`verify_ir.functionWrittenCopies`, N5): true when all three accept it, which is what a final record's `validated`
/// says. A validating compiler reuses a record, and serves a body by its metadata alone, only when it says so, so a body no check of
/// this build sees was checked by the build that made it. The IR verifier's source and `copy_sites.zig` are in this file's import
/// closure, so the `opt` stage identity a final record's key binds covers the three checks.
fn validatedFinal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, index: u32, refusal: ?*own.Refusal) Error!bool {
    if (!try validateOwnership(arena, backing, module, index, refusal)) return false;
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    if (!try verify_ir.functionHolds(work.allocator(), module, index)) return false;
    return verify_ir.functionWrittenCopies(work.allocator(), module, index);
}

fn cachedFinal(arena: std.mem.Allocator, work: std.mem.Allocator, cache: ?*cache_mod.Context, request: FinalRequest) Error!?CachedFinal {
    const context = cache orelse return null;
    const key = request.key orelse return null;
    var value = try context.load(work, .final, key, cache_mod.Final) orelse return null;
    // A compiler that validates reuses only a body that was validated when it was saved.
    if (request.validated and !value.state.validated) {
        context.rejected(.final);
        return null;
    }
    const description = value.analysis orelse {
        context.rejected(.final);
        return null;
    };
    const artifact = try context.loadFacts(work, description) orelse {
        context.rejected(.final);
        return null;
    };
    if (context.deferred == null) value.state.known = try deferred_facts.decode(work, artifact);
    if (cache_mod.validFinal(value, true)) if (try context.restoreFinal(arena, request.function, value, request.provenance)) |restored| {
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
    if (request.key) |digest| if (try request.cache.loadSummary(work, .first_facts, digest)) |summary| {
        if (summary.valid(request.module)) return summary;
        request.cache.rejected(.first_facts);
    };
    const function = &request.module.functions.items[request.function];
    const known = try facts.analyzeWithScratch(work, scratch, function, request.options);
    const summary = try cache_mod.summarize(work, scratch, request.module, function, &known, request.options.sabotage);
    if (request.key) |digest| try request.cache.saveSummary(work, digest, summary);
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
    /// What the passes made so far; its provenance table is the one the stages write.
    result: *Result,
    counts: []u32,
    parameters: []const []const ?facts.Interval = &.{},
    stage: cache_mod.Stage,
    mode: Mode,
    shortcut: ?*shortcut_mod.Index = null,
};

fn inlineCached(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, round: InlineRound) CachedError!u32 {
    const cache = round.cache;
    const provenance = &round.result.provenance;
    const parameters = round.parameters;
    const stage = round.stage;
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    var total: u32 = 0;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        if (round.shortcut) |state| {
            state.cursor(stage, @intCast(index));
            if (state.green[index]) {
                // The early cutoff (G3p (c)): a deferred function that reads a changed function here is recomputed from this stage.
                const skipped = (try state.cutoffDemote(stage, @intCast(index))) orelse {
                    try verifyStage(arena, module, state, .{ .round = round, .index = @intCast(index) }, work.allocator());
                    _ = work.reset(.retain_capacity);
                    continue;
                };
                round.counts[index] += skipped.inlined;
                total += skipped.inlined;
                round.result.per_function[index].counts.unswitched = skipped.unswitched;
                round.result.counts.unswitched += skipped.unswitched;
            }
        }
        if (stage == .inline_cfg) if (cache.lazy.raw) |raw| try prepareReaderQueries(module, raw, @intCast(index));
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

/// The verify mode of the early cutoff: a deferred function that reads a recomputed one and stays deferred is derived afresh at this
/// stage (restored at the checkpoint before it, its key built from the callees as they are now) and the key compared with its entry's.
/// A different key is a read the cutoff missed, counted as a finding.
fn verifyStage(arena: std.mem.Allocator, module: *ir.Module, state: *shortcut_mod.Index, kept: struct { round: InlineRound, index: u32 }, work: std.mem.Allocator) CachedError!void {
    const round = kept.round;
    const index = kept.index;
    if (state.publication.cut.mode != .verify or !state.readsRecomputed(round.stage, index)) return;
    const cache = round.cache;
    try state.restoreBefore(round.stage, index);
    if (round.stage == .inline_cfg) if (cache.lazy.raw) |raw| try prepareReaderQueries(module, raw, index);
    const params = if (index < round.parameters.len) round.parameters[index] else &.{};
    // It reads a function that moved in source positions only and did not inline it: its key would differ, and its result must not.
    if (state.readsShiftedKept(round.stage, index)) return verifyShifted(arena, module, state, .{ .round = round, .index = index }, work);
    const key = try cache.key(work, .{ .stage = round.stage, .function = index, .mode = @backingInt(round.mode), .provenance = &round.result.provenance, .inputs = .{ .parameters = params } });
    const saved = state.savedKey(round.stage, index);
    if (key == null or saved == null or !std.mem.eql(u8, &key.?, &saved.?)) noteFinding(cache, state, index, round.stage);
}

/// The verify mode for a deferred function that reads a function moved in source positions only and kept its result (`Cut.shiftedAt`): the stage
/// is run afresh on the body restored before it, and its result must be the entry's, positions included. A difference is a finding.
fn verifyShifted(arena: std.mem.Allocator, module: *ir.Module, state: *shortcut_mod.Index, kept: struct { round: InlineRound, index: u32 }, work: std.mem.Allocator) CachedError!void {
    const round = kept.round;
    const index = kept.index;
    const cache = round.cache;
    const provenance = &round.result.provenance;
    const params = if (index < round.parameters.len) round.parameters[index] else &.{};
    const changed = if (round.stage == .inline_cfg)
        try inline_leaves.cfgCallerDemandWithScratch(arena, work, module, index, provenance, cache.lazy.raw)
    else
        try inline_leaves.leafCallerDemand(arena, work, module, index, params, .{ .provenance = provenance, .raw = cache.lazy.raw });
    cache.changed(index);
    try state.settle(index);
    const phase: shortcut_mod.Phase = switch (round.stage) {
        .inline_leaf => .leaf,
        .inline_cfg => .cfg,
        else => .parameter,
    };
    const saved = state.record(index, phase) orelse return noteFinding(cache, state, index, round.stage);
    const output = try cache.bodyDigest(index) orelse return noteFinding(cache, state, index, round.stage);
    const ancestry = cache_mod.Provenance.capture(work, cache.source, provenance, index) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => return noteFinding(cache, state, index, round.stage),
    };
    const same_result = std.mem.eql(u8, &saved.output, &output) and saved.provenance.equal(ancestry);
    if (saved.changed != changed or !same_result) return noteFinding(cache, state, index, round.stage);
    state.loadedAfter(round.stage, index);
}

/// Count a finding of the verify mode and keep the first for the report.
fn noteFinding(cache: *cache_mod.Context, state: *shortcut_mod.Index, index: u32, stage: cache_mod.Stage) void {
    cache.statistics.restores.cutoff.findings += 1;
    state.publication.cut.found(index, @backingInt(stage));
}

/// The verify mode at the final stage: a deferred function that reads a recomputed one gets its final key derived afresh and compared.
fn verifyFinal(context: *cache_mod.Context, shortcut: ?*shortcut_mod.Index, request: cache_mod.Request, work: std.mem.Allocator) CachedError!void {
    const state = shortcut orelse return;
    const index = request.function;
    if (state.publication.cut.mode != .verify or !state.keptReadingRecomputed(.final, index)) return;
    try state.restoreBefore(.final, index);
    const events = try state.eventsFor(.final, index);
    var asked = request;
    asked.inputs.events = .{ events.inlined, events.unswitched };
    const key = try context.key(work, asked);
    const saved = state.savedKey(.final, index);
    if (key == null or saved == null or !std.mem.eql(u8, &key.?, &saved.?)) noteFinding(context, state, index, .final);
}

/// The verify mode of the effects: each reused effect of a deferred function that calls a recomputed one is derived afresh, from its
/// body restored after the parameter inlining, and compared with what the entry holds.
fn verifyEffects(arena: std.mem.Allocator, module: *ir.Module, state: *shortcut_mod.Index, reused: []const ?effects.Reused) CachedError!void {
    const probe = try arena.dupe(?effects.Reused, reused);
    var probed: std.ArrayList(u32) = .empty;
    for (probe, 0..) |slot, index| {
        if (slot == null or !state.keptReadingRecomputed(.final, @intCast(index))) continue;
        try state.restoreBefore(.final, @intCast(index));
        probe[index] = null;
        try probed.append(arena, @intCast(index));
    }
    if (probed.items.len == 0) return;
    const summaries = try effects.analyzeReused(arena, module, probe);
    for (probed.items) |index| {
        if (!sameEffect(summaries, index, state.entries[index].demand.effect)) noteFinding(state.context, state, index, .debug);
    }
}

/// Materialize only the exact one-hop query inspected by bounded reader trials.
/// This runs at the existing stage cursor, whose errors already admit demand loading.
/// Prepare every direct shell; only the later expensive cloning trials are capped.
pub fn prepareReaderQueries(module: *ir.Module, raw: *demand_ir.Context, caller: u32) demand_ir.Error!void {
    const reader = @import("inline_reader.zig");
    for (module.functions.items[caller].insts.items) |inst| {
        if (inst.op != .call or inst.a.index() == caller) continue;
        const target: u32 = @intCast(inst.a.index());
        if (!reader.mutationSignature(module, &module.functions.items[target])) continue;
        try raw.ensure(target);
        if (!reader.mutationShell(module, &module.functions.items[target])) continue;
        if (reader.mutationQuery(module, &module.functions.items[target])) |query| try raw.ensure(query);
    }
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
    const module: ir.Module = .{ .functions = .fromOwnedSlice(&functions) };
    const summary = try ParameterSummary.initIndexed(a, &module, null);
    defer a.free(summary.out);
    defer a.free(summary.usable);
    defer a.free(summary.merged);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "initIndexed parameter summaries release partial arrays on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parameterSummaryAllocationFailure, .{});
}
