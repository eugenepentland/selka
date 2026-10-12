//! One `mylang-core build`: check, build the Core IR, compute facts (optimized modes),
//! emit LLVM IR and link. Every failure is rendered into `report`.
const std = @import("std");
const single_owner_contract = @import("single_owner.zig");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build_ir = @import("build.zig");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");
const driver = @import("driver.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const cost_remarks = @import("cost_remarks.zig");
const verify_ir = @import("verify_ir.zig");
const target_description = @import("target.zig");
const build_replay = @import("build_replay.zig");
const run_budget = @import("run_budget.zig");
const stage_store = @import("stage_store.zig");
const stage_metrics = @import("stage_metrics.zig");
const optimization_cache = @import("optimization_cache.zig");
const lowering_cache = @import("lowering_cache.zig");
const lowering_demand = @import("lowering_demand.zig");
const ir_snapshot = @import("ir_snapshot.zig");
const deferred_facts = @import("deferred_facts.zig");
const backend_owned = @import("backend_owned.zig");
const callable_digest = @import("callable_digest.zig");
const tool_identity = @import("tool_identity.zig");

/// What the command line asked for.
pub const Options = struct {
    zig: []const u8,
    output: []const u8 = "",
    mode: @import("build_mode.zig").Mode = .optimized_debug,
    links: []const []const u8 = &.{},
    /// What to show besides the executable.
    show: Show = .{},
    cache: []const u8 = ".mylang-cache/core",
    /// Fact pass mode in an optimized build: `on`, `off` (`--no-facts`, to measure
    /// what facts buy), `verify` (`--verify-facts`: every fact the build relies on
    /// is also checked at run time and traps `R_CORE_FACT` when it does not hold),
    /// or `sabotage` (`--sabotage-facts`, test only: verify with one wrong rule), with
    /// `sabotage_widening` and `sabotage_length` for the other wrong rules of `facts.Sabotage`
    /// (`--sabotage-facts=widening`, `--sabotage-facts=length`), and `sabotage_overflow`
    /// for the overflow facts' rules (`--sabotage-facts=overflow`), and `sabotage_index` for
    /// the dominating-check rule (`--sabotage-facts=index`), and `sabotage_field` for the
    /// whole-program field intervals (`--sabotage-facts=field`), and `sabotage_version` for
    /// the bounds versioning guard (`--sabotage-facts=version`).
    facts: enum { on, off, verify, sabotage, sabotage_widening, sabotage_length, sabotage_overflow, sabotage_index, sabotage_field, sabotage_version } = .on,
};

/// Extra outputs of a build.
pub const Show = struct {
    /// Also write the emitted LLVM IR here (`--emit-llvm`).
    llvm: ?[]const u8 = null,
    /// Print what the optimization passes did (`--stats`) to the report.
    stats: bool = false,
    /// What the emitted code itself does beyond the program: vector lowering, trap
    /// frames and run-time counters.
    codegen: Codegen = .{},
    /// `--verify-cache`: recompile every unit the object store served and require
    /// identical object bytes; such a build never replays.
    verify_cache: bool = false,
    /// `--cache-report` (`text`) or `--report` (`json`, NEW-CORE-S5-REPORT-1): say what
    /// the caches served and how many tools ran.
    cache_report: CacheReport = .off,
    /// How the front end's diagnostics reach the report: `errors` only, as text
    /// (`mylang-core`), or every diagnostic, warnings included, as the `mylang` CLI
    /// prints them in `text` or `json` (`--diagnostics=json`, NEW-CORE-S5-CLI-1).
    diagnostics: Diagnostics = .errors,
    /// Forward command-level compiler artifact suppression to test compiler children.
    compiler_cache_disabled: bool = false,
};

/// Compilation choices controlling experimental semantics and generated code.
pub const Codegen = struct {
    /// Validate the experimental single-owner source contract before code generation.
    single_owner: bool = false,
    zero_rc: bool = false,
    /// Emit only generic LLVM vector code, no x86 intrinsics (`--generic-vectors`): the
    /// portable fallback a target without AVX2 would get, testable on this one.
    generic_vectors: bool = false,
    /// How trap reports find their caller frames (`--trap-frames=dwarf|labels|none`;
    /// default: the target's).
    trap_frames: ?target_description.Traps = null,
    /// A counting build (`--counters`, NEW-CORE-COUNTERS-1): the program records its
    /// count updates, uniqueness tests, copies and memory traffic and writes them as
    /// JSON at exit (`emit_count.zig`, `runtime/core_count.c`).
    counters: bool = false,
};

/// What `Show.diagnostics` selects.
pub const Diagnostics = enum { errors, text, json };

/// What `Show.cache_report` selects: no report, the `mylang-core: cache:` line, or one
/// `cache-report-v1` JSON line.
pub const CacheReport = enum { off, text, json };

/// Why a build stopped after its report was written.
pub const Error = error{ SourceError, Unsupported, ToolFailed, WriteFailed, OutOfMemory, InvalidIr, PolicyDenied, ConfigurationFailed, CacheMiss };

/// Build `path` into `options.output`. An unchanged build replays its last
/// identical build's executable (`build_replay.zig`) before checking anything.
pub fn build(init: std.process.Init, path: []const u8, options: Options, report: *std.ArrayList(u8)) Error!u8 {
    return buildWith(init, path, options, null, report);
}

/// `build` for `mylang run`: the program also installs `budget` when `main` starts
/// (NEW-CORE-S5-RUN-1). The budget is part of the replay key.
pub fn buildRun(init: std.process.Init, path: []const u8, options: Options, budget: run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    return buildWith(init, path, options, budget, report);
}

/// The project entry `path` resolves to, with its configuration (`mylang.json`).
pub fn resolveEntry(init: std.process.Init, path: []const u8, report: *std.ArrayList(u8)) Error!project_entry.Entry {
    return project_entry.resolve(init.arena.allocator(), init.io, path, report);
}

fn buildWith(init: std.process.Init, path: []const u8, options: Options, budget: ?run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    const prepared = try @import("compiler_sharing.zig").prepare(init, options.show.verify_cache or options.show.compiler_cache_disabled);
    const request: BuildRequest = .{ .init = prepared, .path = path, .options = options, .budget = budget, .report = report };
    return @import("build_retry.zig").run(request, report, BuildRequest.attempt);
}

const BuildRequest = struct {
    init: std.process.Init,
    path: []const u8,
    options: Options,
    budget: ?run_budget.RunBudget,
    report: *std.ArrayList(u8),

    fn attempt(self: BuildRequest, lazy: bool) Error!u8 {
        return buildAttempt(self.init, self.path, self.options, self.budget, self.report, lazy);
    }
};

fn buildAttempt(init: std.process.Init, path: []const u8, options: Options, budget: ?run_budget.RunBudget, report: *std.ArrayList(u8), allow_lazy: bool) Error!u8 {
    const allocator = init.arena.allocator();
    const compression = @import("stage_compression.zig").Policy.parse(init.environ_map.get("MYLANG_STAGE_CACHE_COMPRESSION")) catch {
        try report.appendSlice(allocator, "mylang-core: MYLANG_STAGE_CACHE_COMPRESSION must be 'zlib' or 'none'\n");
        return error.ConfigurationFailed;
    };
    const entry = try project_entry.resolve(allocator, init.io, path, report);
    const replaying = options.show.llvm == null;
    const context: build_replay.Context = .{ .arena = allocator, .io = init.io, .environment = init.environ_map, .cache = options.cache, .zig = options.zig, .flags = try flags(init, options, budget), .entry = entry };
    if (try replayBuild(context, options, report)) return 0;
    var storage = try stage_store.Store.initWithOptions(init.gpa, init.io, options.cache, .{ .compression = compression });
    defer storage.deinit();
    var stages: stage_metrics.Report = .{};
    if (!allow_lazy) stages.lowering.fallbacks = 1;
    var lowered_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer lowered_arena.deinit();
    var demand_enabled = !options.show.verify_cache and !options.show.codegen.single_owner;
    const lazy_allowed = useDemandBodies(options, budget);
    const Prepared = struct { module: ir.Module, unit: Unit, sources: ?[]const @import("unit_cache.zig").Dependency, lazy: ?*lowering_cache.Deferred };
    var prepared: Prepared = while (true) {
        const checked_start = stage_metrics.now(init.io);
        const report_start = report.items.len;
        var session = frontend.Session.init(init.gpa, init.io, entry.root);
        defer session.deinit();
        entry.configure(&session);
        if (options.show.diagnostics != .errors) session.setFormat(if (options.show.diagnostics == .json) .json else .text);
        const drop_debug = options.mode == .release and budget == null;
        var demand = try lowering_demand.Context.init(lowered_arena.allocator(), &storage, entry.path, drop_debug);
        if (!options.show.verify_cache) {
            try session.enableCache(init.gpa, options.cache);
            try session.enableSharedCache(init.environ_map);
        }
        var frontend_profile = language.timings.Profile.init(init.io, options.show.cache_report != .off, .compiler);
        session.setProfile(&frontend_profile);
        if (demand_enabled) session.configureDemand(demand.callback());
        const checked = session.checkFile(allocator, if (options.show.diagnostics == .errors) entry.path else path, report) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.SourceError,
        };
        try validateSource(allocator, checked, options, report);
        if (options.show.diagnostics != .errors) try report.appendSlice(allocator, try session.warnings(allocator));
        const sources = if (replaying) try build_replay.inputs(context, &session) else null;
        try entry.validate(allocator, &session, report);
        stages.nanoseconds.frontend += stage_metrics.elapsed(init.io, checked_start);
        stages.frontend = session.statistics();
        stages.nanoseconds.frontend_phases = try stage_metrics.frontendPhases(allocator, &frontend_profile);
        frontendMetrics(&stages, &session);
        if (session.demandState()) |state| demand.attach(state.prepared, state.omitted);
        const lowering_start = stage_metrics.now(init.io);
        var refusal: build_ir.Refusal = .{};
        const input: build_ir.Input = .{ .program = checked.program, .source = checked.src, .drop_debug = drop_debug, .single_owner = options.show.codegen.single_owner, .zero_rc = options.show.codegen.zero_rc };
        var lowering = lowering_cache.Cache.init(&storage);
        lowering.demand = &demand;
        const a = lowered_arena.allocator();
        const lazy = if (lazy_allowed) try a.create(lowering_cache.Deferred) else null;
        if (lazy) |state| state.* = .{ .arena = a, .store = &storage, .force_eager = !allow_lazy };
        lowering.lazy = lazy;
        const uncached = options.show.verify_cache or (options.show.codegen.single_owner and !options.show.codegen.zero_rc);
        const lowered = if (uncached) build_ir.buildExecutable(a, input, &refusal) else build_ir.buildExecutableCached(a, input, &refusal, &lowering);
        var module = lowered catch |err| switch (err) {
            error.CacheMiss => {
                // A cache can disappear after admission. Discard partial IR and
                // diagnostics, then check complete trees exactly once.
                stages.nanoseconds.lowering += stage_metrics.elapsed(init.io, lowering_start);
                stages.lowering.fallbacks += 1;
                demand_enabled = false;
                report.shrinkRetainingCapacity(report_start);
                _ = lowered_arena.reset(.free_all);
                continue;
            },
            error.Unsupported => {
                try refused(allocator, checked.src, refusal, options.show.diagnostics, report);
                return error.Unsupported;
            },
            else => |other| return other,
        };
        stages.lowering.reused = lowering.reused;
        stages.lowering.lowered = lowering.lowered;
        stages.lowering.deferred = demand.count();
        if (!options.show.verify_cache) try demand.finish();
        if (budget) |installed| try run_budget.instrumentRun(a, &module, installed);
        const unit = try retainUnit(a, &module, try unitFor(a, checked, entry.path, session.single != null));
        stages.nanoseconds.lowering += stage_metrics.elapsed(init.io, lowering_start);
        if (lazy) |state| try state.prepare(&module, unit.src);
        break .{ .module = module, .unit = unit, .sources = sources, .lazy = lazy };
    };
    const module = &prepared.module;
    if (prepared.lazy) |state| state.input.module = module;
    const caches: StageContext = .{
        .storage = if (options.show.verify_cache or (options.show.codegen.single_owner and !options.show.codegen.zero_rc)) null else &storage,
        .io = init.io,
        .lanes = @import("unit_cache.zig").width(init.environ_map, module.functions.items.len),
        .metrics = &stages,
        .demand = if (prepared.lazy) |state| &state.context else null,
    };
    const outcome = try linkEmittedCached(init, module, prepared.unit, options, caches, report);
    materializationMetrics(&stages, prepared.lazy);
    const flush_start = stage_metrics.now(init.io);
    const flushed = try storage.flush();
    const publication: stage_metrics.Storage = .{ .flush_nanoseconds = stage_metrics.elapsed(init.io, flush_start), .flush_succeeded = flushed, .reads = storage.statistics(), .compression = @tagName(compression) };
    // A record that cannot be written costs the next build its replay, nothing more.
    if (replaying) build_replay.remember(context, prepared.sources, outcome.tool, .{ .program = outcome.program, .foreign = outcome.foreign }, report.items) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => {},
    };
    if (options.show.cache_report != .off) try cacheReport(allocator, options.show.cache_report, outcome, &stages, &publication, report);
    return 0;
}

fn validateSource(a: std.mem.Allocator, checked: frontend.Checked, options: Options, report: *std.ArrayList(u8)) Error!void {
    if (!options.show.codegen.single_owner) return;
    const format: language.diagnostic_output.Format = if (options.show.diagnostics == .json) .json else .text;
    if (!try single_owner_contract.validateMode(a, checked.program, checked.src, format, report, options.show.codegen.zero_rc)) return error.SourceError;
}

fn replayBuild(context: build_replay.Context, options: Options, report: *std.ArrayList(u8)) Error!bool {
    if (options.show.llvm != null or options.show.verify_cache) return false;
    if (!try build_replay.replay(context, options.output, report)) return false;
    if (options.show.cache_report != .off) try cacheReport(context.arena, options.show.cache_report, null, null, null, report);
    return true;
}

fn useDemandBodies(options: Options, budget: ?run_budget.RunBudget) bool {
    if (options.show.codegen.single_owner) return false;
    if (budget != null or verify_ir.enabled) return false;
    if (options.mode != .optimized_debug or options.facts != .on) return false;
    return !options.show.stats and options.show.llvm == null and !options.show.verify_cache;
}

fn frontendMetrics(stages: *stage_metrics.Report, session: *const frontend.Session) void {
    const cache = session.cache orelse return;
    stages.frontend_misses = cache.semantic.statistics.rejections;
}

fn materializationMetrics(stages: *stage_metrics.Report, lazy: ?*lowering_cache.Deferred) void {
    const state = lazy orelse {
        stages.lowering.materialized = stages.lowering.reused + stages.lowering.lowered;
        return;
    };
    stages.lowering.materialized = state.restored + stages.lowering.lowered;
    for (state.tables.loaded.items) |loaded| {
        if (!loaded) stages.lowering.unloaded += 1;
    }
}

/// Report the new core's refusal of a construct at `refusal`, as text or as a
/// `diagnostic-v1` record.
/// Entry metadata shared by ordinary builds and cost's identical LLVM emission.
pub fn unitFor(a: std.mem.Allocator, checked: frontend.Checked, absolute: []const u8, single: bool) std.mem.Allocator.Error!Unit {
    return .{
        .src = checked.src,
        .source_path = if (single) absolute else shownPath(checked.src, checked.program),
        .main = .{
            .parameters = try mainParameters(a, checked.program),
            .result = mainResult(checked.program),
            .capabilities = try mainCapabilities(a, checked.program),
            .runtime_options = true,
        },
    };
}

fn refused(allocator: std.mem.Allocator, src: language.source.Source, refusal: build_ir.Refusal, diagnostics: Diagnostics, report: *std.ArrayList(u8)) Error!void {
    const message = try std.fmt.allocPrint(allocator, "the new core does not support {s} yet", .{refusal.reason});
    if (diagnostics == .json) {
        const item: language.diagnostic.Diagnostic = .{ .severity = .err, .code = "E_CORE_UNSUPPORTED", .span = .{ .start = refusal.span, .end = refusal.span }, .message = message };
        return report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, src, .json));
    }
    const at = frontend.position(src, .{ .start = refusal.span, .end = refusal.span });
    try report.print(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: {s}\n", .{ at.path, at.line, at.column, message });
}

/// The canonical encoding of every build flag that changes the executable or the
/// report, with `--link` sources by absolute path.
fn flags(init: std.process.Init, options: Options, budget: ?run_budget.RunBudget) Error![]const u8 {
    const allocator = init.arena.allocator();
    const links = try allocator.alloc([]const u8, options.links.len);
    for (options.links, links) |link, *absolute| absolute.* = std.Io.Dir.cwd().realPathFileAlloc(init.io, link, allocator) catch link;
    return std.json.Stringify.valueAlloc(allocator, .{
        .mode = options.mode,
        .single_owner = options.show.codegen.single_owner,
        .zero_rc = options.show.codegen.zero_rc,
        .facts = options.facts,
        .stats = options.show.stats,
        .vectors = options.show.codegen.generic_vectors,
        .frames = options.show.codegen.trap_frames,
        .counters = options.show.codegen.counters,
        .links = links,
        .diagnostics = options.show.diagnostics,
        .run = budget,
    }, .{}) catch return error.OutOfMemory;
}

/// Say what the caches served: for a replayed build (`outcome` null) that it replayed,
/// else the units linked, reused, compiled and verified, whether the program store
/// served the executable, and the tool processes started.
fn cacheReport(allocator: std.mem.Allocator, form: CacheReport, outcome: ?driver.Outcome, stages: ?*const stage_metrics.Report, storage: ?*const stage_metrics.Storage, report: *std.ArrayList(u8)) Error!void {
    const c = if (outcome) |built| built.counts else driver.Counts{};
    const program = if (outcome) |built| (if (built.program_reused) "reused" else "linked") else "replayed";
    if (form == .json) {
        const record = std.json.Stringify.valueAlloc(allocator, .{
            .version = "cache-report-v1",
            .program = program,
            .units = c.units,
            .reused = c.reused,
            .compiled = c.compiled,
            .verified = c.verified,
            .processes = c.processes,
            .stages = stages,
            .storage = storage,
            .program_shared = if (outcome) |built| built.program_shared else false,
        }, .{}) catch return error.OutOfMemory;
        try report.print(allocator, "{s}\n", .{record});
        return;
    }
    if (outcome == null) return report.appendSlice(allocator, "mylang-core: cache: replayed the last identical build\n");
    const format = "mylang-core: cache: {d} units, {d} reused, {d} compiled, {d} verified; program {s}; {d} processes\n";
    try report.print(allocator, format, .{ c.units, c.reused, c.compiled, c.verified, program, c.processes });
}

/// What the back half of a build needs to know about the checked source.
pub const Unit = struct {
    /// The merged source trap positions are located in.
    src: language.source.Source,
    /// The path traps and error traces report: the entry file's, as the old core shows it
    /// (`shownPath`).
    source_path: []const u8,
    /// The entry function's parameter names (which pick stdout or stderr for a
    /// `Stream`) and, when it returns a `Result`, its case tags.
    main: emit_llvm.Main,
};

/// Detach the backend's remaining frontend views onto its result arena. The
/// caller may release checked trees after success; partial copies on failure
/// remain in that arena and leave the frontend safe to release exactly once.
pub fn retainUnit(arena: std.mem.Allocator, module: *ir.Module, given: Unit) std.mem.Allocator.Error!Unit {
    try backend_owned.retainModule(arena, module);
    var retained = given;
    retained.src = try backend_owned.retainSource(arena, given.src);
    retained.source_path = try arena.dupe(u8, given.source_path);
    retained.main.parameters = try backend_owned.retainNames(arena, given.main.parameters);
    retained.main.capabilities = try arena.dupe(u8, given.main.capabilities);
    return retained;
}

/// The back half of `build`: run the selected passes on `module`, emit LLVM IR, and
/// link the executable. `mylang-core test` reaches it with a module of its own making
/// and keys its execution receipts by the answer, the linked program's exact key
/// (`driver.Outcome.program_key`, EXEC-RECEIPT-1).
pub fn finish(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!?[32]u8 {
    const outcome = try linkEmitted(init, module, unit, options, report);
    return outcome.program_key;
}

fn linkEmitted(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!driver.Outcome {
    var stages: stage_metrics.Report = .{};
    return linkEmittedCached(init, module, unit, options, .{ .storage = null, .io = init.io, .lanes = 1, .metrics = &stages }, report);
}

fn linkEmittedCached(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, cache: StageContext, report: *std.ArrayList(u8)) Error!driver.Outcome {
    const allocator = init.arena.allocator();
    const stages = cache.metrics;
    const identity_tool = try prepareCallables(init, module, unit, options, cache);
    const emission = try emittedCached(.{ .result = allocator, .scratch = init.gpa }, module, unit, options, cache, report);
    if (options.show.llvm) |where| std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = where, .data = emission.whole.? }) catch return error.WriteFailed;
    const native_start = stage_metrics.now(init.io);
    var outcome = driver.linkWithScratch(allocator, init.gpa, init.io, init.environ_map, .{
        .zig = options.zig,
        .work = options.cache,
        .output = options.output,
        .mode = options.mode,
        .links = options.links,
        .units = emission.units,
        .verify = options.show.verify_cache,
    }, report) catch |err| return err;
    if (identity_tool) |expected| if (!sameIdentityTool(expected, outcome.tool)) return error.ToolFailed;
    stages.nanoseconds.native = stage_metrics.elapsed(init.io, native_start);
    stages.nanoseconds.linker = outcome.counts.link_ns;
    if (emission.cost_report) |measured| {
        var final = measured;
        const remarks = try driver.optimizationRemarks(allocator, init.io, init.environ_map, .{
            .zig = options.zig,
            .work = options.cache,
            .output = "",
            .mode = options.mode,
            .links = &.{},
            .units = emission.units,
            .verify = options.show.verify_cache,
        });
        if (remarks.yaml) |yaml| cost_remarks.apply(&final, yaml);
        try cost.llvmStats(allocator, report, final.totals, remarks);
        outcome.counts.processes += remarks.processes;
    }
    return outcome;
}

/// Arena-owned native units and optional compatibility LLVM from one pass run.
pub const Emission = struct { units: []const emit_units.Unit, whole: ?[]const u8 = null, cost_report: ?cost.Report = null };

/// Run the same passes and emission used for linking, without invoking a tool.
/// Test receipts hash this exact reachable program.
pub fn emitted(allocator: std.mem.Allocator, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!Emission {
    return emittedWithScratch(allocator, allocator, module, unit, options, report);
}

/// Keep IR and finished artifacts on `allocator`; reclaim pass and emission work
/// through `scratch`, which production callers supply independently of the build arena.
pub fn emittedWithScratch(allocator: std.mem.Allocator, scratch: std.mem.Allocator, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!Emission {
    return emittedCached(.{ .result = allocator, .scratch = scratch }, module, unit, options, null, report);
}

/// Use existing checked compiler stages and exact static queries without a build receipt.
pub fn emittedQuery(memory: QueryMemory, module: *ir.Module, unit: Unit, options: Options, query: QueryContext, report: *std.ArrayList(u8)) Error!Emission {
    return emittedCached(.{ .result = memory.arena, .scratch = memory.backing }, module, unit, options, .{
        .storage = if (query.fresh) null else query.store,
        .io = query.io,
        .lanes = 1,
        .metrics = query.metrics,
        .queries = query.cost,
    }, report);
}
/// Returned IR lives in arena; transient work uses backing.
pub const QueryMemory = struct { arena: std.mem.Allocator, backing: std.mem.Allocator };
/// Borrowed compiler stores and current invocation counters.
pub const QueryContext = struct { store: *stage_store.Store, io: std.Io, metrics: *stage_metrics.Report, cost: *@import("cost_query.zig").Cache, fresh: bool = false };

const StageContext = struct { queries: ?*@import("cost_query.zig").Cache = null, storage: ?*stage_store.Store, io: std.Io, lanes: usize, metrics: *stage_metrics.Report, demand: ?*@import("demand_ir.zig").Context = null };

const Memory = struct { result: std.mem.Allocator, scratch: std.mem.Allocator };

fn prepareCallables(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, cache: StageContext) Error!?tool_identity.Identity {
    if (!callable_digest.needed(module)) return null;
    const a = init.arena.allocator();
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = options.zig, .cache = options.cache };
    const tool = tool_identity.capture(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ToolFailed;
    };
    const settings = try std.json.Stringify.valueAlloc(a, .{
        .mode = options.mode,
        .facts = options.facts,
        .codegen = options.show.codegen,
        .target = targetFor(options.show),
        .layout = init.environ_map.get("MYLANG_CORE_LAYOUT"),
        .sanitize = init.environ_map.get("MYLANG_CORE_SANITIZE"),
        .number_runtime = @import("number_runtime.zig").digest(),
    }, .{});
    const context: callable_digest.Context = .{ .tool = if (tool.cacheable and options.links.len == 0) tool.digest else null, .cpu = tool.native_target, .build = settings };
    try callable_digest.prepare(a, module, locator(&unit.src), context, cache.demand);
    const unchanged = tool_identity.unchanged(request, tool) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ToolFailed;
    };
    if (!unchanged) return error.ToolFailed;
    return if (context.tool != null) tool else null;
}

fn sameIdentityTool(expected: tool_identity.Identity, actual: tool_identity.Identity) bool {
    if (!actual.cacheable or !std.mem.eql(u8, &expected.digest, &actual.digest)) return false;
    return std.mem.eql(u8, &expected.generation, &actual.generation) and std.mem.eql(u8, &expected.native_target, &actual.native_target);
}

fn verifyOwnership(allocator: std.mem.Allocator, module: *const ir.Module, src: language.source.Source, diagnostics: @FieldType(@FieldType(Options, "show"), "diagnostics"), report: *std.ArrayList(u8)) Error!void {
    var failure: single_owner_contract.Failure = .{};
    single_owner_contract.verifyLowered(module, &failure) catch {
        try single_owner_contract.render(allocator, src, failure, if (diagnostics == .json) .json else .text, report);
        return error.SourceError;
    };
}

fn emittedCached(memory: Memory, module: *ir.Module, unit: Unit, options: Options, stage: ?StageContext, report: *std.ArrayList(u8)) Error!Emission {
    const allocator = memory.result;
    const scratch = memory.scratch;
    // IR-only callers lack actual toolchain authority; unresolved identities refuse reuse.
    try callable_digest.prepare(allocator, module, locator(&unit.src), .{}, if (stage) |s| s.demand else null);
    // A debug build of the compiler checks the IR it built, and again after optimization.
    if (verify_ir.enabled) try verify_ir.check(allocator, module, &.{}, report);
    // Optimized modes compute facts; ordinary debug keeps every check.
    const verify = options.facts != .on and options.facts != .off;
    const mode: passes.Mode = switch (options.facts) {
        .on => .trusted,
        .off => .off,
        .verify => .verify,
        .sabotage => .sabotage,
        .sabotage_widening => .sabotage_widening,
        .sabotage_length => .sabotage_length,
        .sabotage_overflow => .sabotage_overflow,
        .sabotage_index => .sabotage_index,
        .sabotage_field => .sabotage_field,
        .sabotage_version => .sabotage_version,
    };
    const optimized = options.mode != .debug;
    const ordinary_optimized = options.mode == .optimized_debug and options.facts == .on;
    const defer_analysis = ordinary_optimized and !options.show.stats and options.show.llvm == null;
    var deferred: deferred_facts.Table = .{};
    const optimizer_start = if (stage) |s| stage_metrics.now(s.io) else std.Io.Timestamp.zero;
    var optimizer_context: ?*optimization_cache.Context = null;
    var result = if (stage != null and stage.?.storage != null) cached: {
        const context = try allocator.create(optimization_cache.Context);
        context.* = optimization_cache.Context.init(stage.?.storage.?, try ir_snapshot.Context.init(allocator, module, unit.src), locator(&unit.src));
        optimizer_context = context;
        context.lazy.raw = stage.?.demand;
        const result = if (defer_analysis)
            try passes.runCachedDeferred(allocator, scratch, module, mode, context, &deferred)
        else if (optimized)
            try passes.runCached(allocator, scratch, module, mode, context)
        else
            try passes.debugCached(allocator, scratch, module, context);
        stage.?.metrics.optimizer = context.statistics;
        break :cached result;
    } else if (optimized) try passes.runWithScratch(allocator, scratch, module, mode) else try passes.debugWithScratch(allocator, scratch, module);
    if (stage) |s| s.metrics.nanoseconds.optimizer = stage_metrics.elapsed(s.io, optimizer_start);
    if (options.show.codegen.single_owner) try verifyOwnership(allocator, module, unit.src, options.show.diagnostics, report);
    if (verify_ir.enabled) try verify_ir.check(allocator, module, result.plans, report);
    const measured = if (!options.show.stats) null else if (stage != null and stage.?.queries != null)
        stage.?.queries.?.measure(allocator, module, &result, locator(&unit.src)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidQuery => {
                try report.appendSlice(allocator, "error[E_CORE_CACHE]: cached static cost differs from fresh measurement\n");
                return error.InvalidIr;
            },
        }
    else
        try cost.measure(allocator, module, &result, null);
    if (measured) |snapshot| try cost.stats(allocator, report, snapshot.totals);
    // One summary of the final IR serves every unit a debug build emits.
    const summaries = result.emission.effects orelse try @import("effects.zig").analyze(allocator, module);
    const emission: emit_llvm.Options = .{
        .locator = locator(&unit.src),
        .source_path = unit.source_path,
        .main = unit.main,
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance, .effects = &summaries },
        .verify = verify and optimized,
        .target = targetFor(options.show),
        .counters = options.show.codegen.counters,
    };
    // S4-1a: a release build is one unit, so LLVM optimizes across every module
    // boundary; development modes keep module units and reuse unchanged text.
    var final_restorer: FinalRestorer = .{ .arena = allocator, .backing = scratch, .context = optimizer_context, .result = &result };
    const emission_start = if (stage) |s| stage_metrics.now(s.io) else std.Io.Timestamp.zero;
    const split = if (options.mode == .release) emit_units.wholeWithScratch(allocator, scratch, module, emission) else if (stage != null and stage.?.storage != null) emit_units.emitCached(allocator, scratch, module, emission, .{
        .store = stage.?.storage.?,
        .lanes = stage.?.lanes,
        .memory_budget_bytes = stage_metrics.workerBudget(stage.?.io),
        .counts = &stage.?.metrics.emission,
        .deferred = if (defer_analysis) &deferred else null,
        .receipts = final_restorer.receipts(&unit.src),
        .native_handles = final_restorer.receipts(&unit.src) != null,
    }) else emit_units.emitWithScratch(allocator, scratch, module, emission);
    const units = split catch |err| switch (err) {
        error.CacheMiss => return error.CacheMiss,
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try report.print(allocator, "error[E_CORE_UNSUPPORTED]: LLVM emission failed: {s}\n", .{@errorName(err)});
            return error.Unsupported;
        },
    };
    if (stage) |s| {
        s.metrics.nanoseconds.emission = stage_metrics.elapsed(s.io, emission_start);
        if (optimizer_context) |ctx| s.metrics.optimizer = ctx.statistics;
    }
    if (options.show.llvm == null) return .{ .units = units, .cost_report = measured };
    if (options.mode == .release) return .{ .units = units, .whole = units[0].llvm, .cost_report = measured };
    const whole = emit_llvm.emitModuleWithScratch(allocator, scratch, module, emission) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Unsupported,
    };
    return .{ .units = units, .whole = whole, .cost_report = measured };
}

const FinalRestorer = struct {
    arena: std.mem.Allocator,
    backing: std.mem.Allocator,
    context: ?*optimization_cache.Context,
    result: *passes.Result,

    fn receipts(self: *FinalRestorer, source: *const language.source.Source) ?@import("emission_cache.zig").ReceiptContext {
        const ctx = self.context orelse return null;
        const raw = ctx.lazy.raw orelse return null;
        if (raw.force_eager) return null;
        return .{
            .finals = ctx.lazy.finals,
            .source = source,
            .layout = ctx.layoutDigest() orelse return null,
            .loader = .{ .pointer = self, .ensure_fn = ensure },
        };
    }

    fn ensure(pointer: *anyopaque, index: u32) @import("demand_ir.zig").Error!void {
        const self: *FinalRestorer = @ptrCast(@alignCast(pointer));
        const context = self.context orelse return;
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        try passes.restoreDeferredFinal(self.arena, scratch.allocator(), context, index, self.result);
    }
};

/// How emission finds a span's file, line and column in the merged source `src`.
pub fn locator(src: *const language.source.Source) emit_llvm.Locator {
    return .{ .context = src, .locate = locate };
}

fn locate(context: *const anyopaque, offset: u32) emit_llvm.Location {
    const src: *const language.source.Source = @ptrCast(@alignCast(context));
    const at = frontend.position(src.*, .{ .start = offset, .end = offset });
    return .{ .line = at.line, .column = at.column, .path = at.path };
}

/// The `Ok` and `Err` tags of `main`'s return type when it is a `Result`.
fn mainResult(program: language.typed.Program) ?emit_llvm.MainResult {
    const main = program.functions[@backingInt(program.main)];
    const shape = language.typed.resultShape(main.signature.return_type, program.records) orelse return null;
    return .{ .ok_tag = @intCast(shape.ok_tag), .error_tag = @intCast(shape.error_tag) };
}

/// The names of `main`'s parameters, which pick stdout or stderr for a `Stream`.
fn mainParameters(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const names = try allocator.alloc([]const u8, main.signature.parameter_count);
    for (names, main.scope.locals[0..names.len]) |*name, local| name.* = local.name;
    return names;
}

/// The target description a build uses: the generic vector fallback when asked for,
/// and the trap-frame mechanism `--trap-frames` picks.
fn targetFor(show: Show) target_description.Target {
    var target = if (show.codegen.generic_vectors) target_description.generic_256 else target_description.current;
    if (show.codegen.trap_frames) |frames| target.traps = frames;
    return target;
}

/// The path reports show for a module-headed entry file, as the front end names it and
/// the old core prints it: relative to its module root.
pub fn shownPath(src: language.source.Source, program: language.typed.Program) []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const start: u32 = @intCast(main.declaration.start);
    return frontend.position(src, .{ .start = start, .end = start }).path;
}

/// Checked entry capability families distinguish Host from Stream and provider tokens.
fn mainCapabilities(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const u8 {
    const main = program.functions[@backingInt(program.main)];
    const families = try allocator.alloc(u8, main.signature.parameter_count);
    for (families, main.scope.locals[0..families.len]) |*family, local| family.* = if (local.ty.capabilityIndex()) |index| @as(u8, index) else 255;
    return families;
}

// spec-case: FUNCTION-DIGEST-1
test "prepareCallables function_digest refuses missing native tool authority and changed linking context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const missing = try std.fs.path.join(a, &.{ directory, "missing-guest-tool" });
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    const init: std.process.Init = .{ .minimal = undefined, .arena = &arena, .gpa = std.testing.allocator, .io = std.testing.io, .environ_map = &environment, .preopens = undefined };
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = callable_digest.prefix ++ "test", .signature = .{ .params = &.{}, .ret = .str, .linkage = .runtime_c } });
    const unit: Unit = .{ .src = .{ .path = "fixture.my", .bytes = "", .line_starts = &.{} }, .source_path = "fixture.my", .main = .{} };
    var metrics: stage_metrics.Report = .{};
    const cache: StageContext = .{ .storage = null, .io = std.testing.io, .lanes = 1, .metrics = &metrics };
    try std.testing.expectError(error.ToolFailed, prepareCallables(init, &module, unit, .{ .zig = missing, .cache = directory }, cache));
    const expected: tool_identity.Identity = .{ .path = "tool", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 1, .memo_hit = false, .cacheable = true };
    var changed = expected;
    changed.generation = @splat(4);
    try std.testing.expect(sameIdentityTool(expected, expected));
    try std.testing.expect(!sameIdentityTool(expected, changed));
}
