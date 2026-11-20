//! One `selka-core build`: check, build the Core IR, compute facts (optimized modes),
//! emit LLVM IR and link. Every failure is rendered into `report`.
const std = @import("std");
const product = @import("selka").product;
const record_names = @import("record_names.zig");
const process_exit = @import("selka").process_exit;
const cache_miss = @import("selka").cache_miss;
const shadow_rules = @import("frontend_shadow.zig");
const facts_shadow = @import("program_facts_shadow.zig");
const optimizer_shadow = @import("optimizer_shadow.zig");
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build_ir = @import("build.zig");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");
const driver = @import("driver.zig");
const ram_image = @import("ram_image.zig");
const passes = @import("passes.zig");
const own = @import("own.zig");
const refusal_text = @import("ownership_refusal_text.zig");
const cost = @import("cost.zig");
const clause_report = @import("clause_report.zig");
const cost_remarks = @import("cost_remarks.zig");
const verify_ir = @import("verify_ir.zig");
const target_description = @import("target.zig");
const build_replay = @import("build_replay.zig");
const demand_generation = @import("demand_generation.zig");
const inputs_handle = @import("inputs.zig");
const run_budget = @import("run_budget.zig");
const stage_roots = @import("stage_roots.zig");
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
const certificate = @import("ownership_certificate.zig");
const certificate_export = @import("ownership_export.zig");
const facts = @import("facts.zig");
const fact_export = @import("fact_export.zig");
const fact_text = @import("fact_text.zig");
const validate_facts = @import("validate_facts.zig");
const validate_ownership = @import("validate_ownership.zig");
const op_log = @import("op_log.zig");
const reachable_holes = @import("reachable_holes.zig");
const stage_verify = @import("stage_verify.zig");

/// What the command line asked for.
pub const Options = struct {
    zig: []const u8,
    output: []const u8 = "",
    /// The build mode. This default is Core's passes and LLVM `-O0`, the build of `selka test` and of the tests of the compiler;
    /// the command line of `build` and `run` starts from `Mode.plain`, the lean debug build (`cli_args.parse`).
    mode: @import("build_mode.zig").Mode = .optimized_debug,
    links: []const []const u8 = &.{},
    /// What to show besides the executable.
    show: Show = .{},
    cache: []const u8 = product.core_work_dir,
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
    /// `verify_written` is facts verification plus rule C's refusal of an unmarked copy site in the
    /// final module (`verify_ir.writtenCopies`). Facts verification (`--verify-facts`) selects it by default
    /// (CX-6); `SELKA_VERIFY_WRITTEN_COPIES=0` keeps `--verify-facts` at `verify`, and `--verify-written-copies` selects it
    /// explicitly. Since N5 every validating build runs the refusal anyway (`checksWrittenCopies`); this mode also runs it
    /// under `--no-validate`.
    facts: enum { on, off, verify, verify_written, sabotage, sabotage_widening, sabotage_length, sabotage_overflow, sabotage_index, sabotage_field, sabotage_version } = .on,
};

/// Whether rule C joins facts verification (CX-6): on by default under `--verify-facts`. The value `0` of
/// `SELKA_VERIFY_WRITTEN_COPIES` turns it off; any other value, or none, leaves it on.
pub fn writtenCopiesOn(value: ?[]const u8) bool {
    const text = value orelse return true;
    return !std.mem.eql(u8, text, "0");
}

/// The validators `--verify-ownership` and `--verify-facts-static` ask for, and `--no-validate`, which turns off the ones no flag asks for.
pub const Verify = struct {
    /// `--verify-ownership`: validate the ownership certificate and check the IR of every function the passes finish, in any compiler,
    /// with no demand bodies (`validatesEagerly`). A debug guest build, `--verify-facts` and a debug compiler validate them by default
    /// (`checksOwnership`).
    ownership: bool = false,
    /// `--verify-facts-static`: validate the fact tables of the finished build against its final IR (docs/design/fact-certificates.md
    /// §7), in any compiler, and say how many functions and `proven` checks it validated. A debug compiler whenever the build
    /// computed facts, and `--verify-facts`, always do (`checksFacts`).
    facts_static: bool = false,
    /// `--verify-names`: record the op log of lowering and check it by replay (`op_log.zig`), in any compiler. A debug
    /// compiler always does. A build that restores a lowering artifact is not checked: the log does not describe it.
    names: bool = false,
    /// `--verify-cutoff`: every deferred function that reads a recomputed one is derived afresh and compared with its entry (the verify
    /// mode of the optimizer's early cutoff, `optimizer_cutoff.zig`), in any compiler. A debug compiler does so on a fraction of builds.
    cutoff: bool = false,
    /// `--no-validate`: the build runs no validator that no flag asks for, in any compiler: the way out of a validator fault
    /// (`E_OWNERSHIP_VALIDATION`, `E_FACT_VALIDATION` name it). The records it writes say they were not validated.
    skip: bool = false,
    /// What only tests ask for.
    testing: Testing = .{},

    /// Take `arg` when it is one of the verification flags; false for any other.
    pub fn ask(self: *Verify, arg: []const u8) bool {
        if (std.mem.eql(u8, arg, "--verify-ownership")) {
            self.ownership = true;
        } else if (std.mem.eql(u8, arg, "--verify-facts-static")) {
            self.facts_static = true;
        } else if (std.mem.eql(u8, arg, "--verify-names")) {
            self.names = true;
        } else if (std.mem.eql(u8, arg, "--no-validate")) {
            self.skip = true;
        } else if (std.mem.eql(u8, arg, "--eager-attempt")) {
            self.testing.eager_attempt = true;
        } else if (std.mem.eql(u8, arg, "--verify-cutoff")) {
            self.cutoff = true;
        } else if (std.mem.eql(u8, arg, "--sabotage-instance-keys")) {
            self.testing.sabotage_instance_keys = true;
        } else if (std.mem.eql(u8, arg, "--validate-like-optimised")) {
            self.testing.like_optimised = true;
        } else return false;
        return true;
    }
};

/// The verification knobs only tests set.
pub const Testing = struct {
    /// `--eager-attempt`: take the eager attempt a lost demand artifact retries, without losing one. The build's receipts are stored
    /// all the same, so the next build serves its units from them.
    eager_attempt: bool = false,
    /// `--sabotage-instance-keys`: key a generic instance by the records its type arguments reach through their fields alone, the way
    /// every build did until 5 November 2026, so a test can make the stale instance the key fix removed and see `--verify-cache`
    /// report it. The key of any other function is unchanged.
    sabotage_instance_keys: bool = false,
    /// Set by the stage-served pass of `--verify-cache` (`servedUnits`), never by a flag: the pass keeps the text of every unit, so it
    /// asks for no native handles, which stand for a unit's stored text without loading it.
    serving: bool = false,
    /// `--validate-like-optimised`: a debug compiler validates as an optimised one does (`validatesByDefault`, with demand bodies),
    /// not every build of every mode with every body (`compilerValidates`), so the gate's compiler can test the shipped path.
    like_optimised: bool = false,
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
    /// (`selka-core`), or every diagnostic, warnings included, as the `selka` CLI
    /// prints them in `text` or `json` (`--diagnostics=json`, NEW-CORE-S5-CLI-1).
    diagnostics: Diagnostics = .errors,
    /// `--no-cache` (every command that takes it): the build neither reads nor publishes the shared stage store (`sharedStageRoot`),
    /// and a test run forwards the flag to its compiler children. The shared compiler-artifact tier is switched off by the command
    /// (`compiler_sharing.prepare`), and the object store, whose keys cover the text they were built from, stays on.
    compiler_cache_disabled: bool = false,
    /// `--emit-certificates DIR`: write the ownership certificates of the final IR there, one file per unit
    /// (docs/design/ownership-certificates.md). Such a build runs the passes itself, with no cached stage.
    certificates: ?[]const u8 = null,
    /// The validators a build asks for with a flag, in any compiler (`--verify-ownership`, `--verify-facts-static`).
    verify: Verify = .{},
};

/// Compilation choices controlling generated code.
pub const Codegen = struct {
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
    /// `--local-stdlib`: a development source-resolution switch, grouped here to
    /// keep `Options` under its field cap.
    local_stdlib: bool = false,
    /// Internal native harness: charge steps once and read each trial ceiling at startup.
    harness_steps: bool = false,
    /// The target the build is for (`--target NAME`; default: the host).
    target: *const target_description.Target = &target_description.host,
    /// What a build for a device names beyond its target: the linker script, the include folders of its C, its image.
    device: Device = .{},
};

/// The device settings of a build (MCU-C1), from the command line or the project's `selka.json` (`device_build.apply`).
pub const Device = struct {
    /// The linker script that lays out a bare target's image (`--linker-script PATH`); a bare build needs one and a hosted
    /// build takes none (`cli_args.linkerScriptRefusal`).
    linker_script: ?[]const u8 = null,
    /// The text of the script the compiler wrote from the device's `memory` description (`device_build`), used when no script is named.
    linker_text: ?[]const u8 = null,
    /// Folders added to the include path of every linked C source (`--include DIR`, `include`); inputs of their cache keys.
    include: []const []const u8 = &.{},
    /// The image a bare build writes when the output's name does not say (`.elf`, `.bin`, `.uf2`): a device's `image`.
    image: @import("device_image.zig").Form = .elf,
    /// The UF2 family id a `.uf2` image carries: a device's `uf2_family`.
    uf2_family: ?u32 = null,
    /// The platform hooks the device binds to Selka functions (`hooks`, MCU-NOC4A).
    hooks: []const Hook = &.{},
};

/// One bound hook, as the device's `hooks` spells it, with where a refusal of it is reported: the configuration and the device.
pub const Hook = struct { name: []const u8, function: []const u8, device: []const u8, config: []const u8 };

/// What `Show.diagnostics` selects.
pub const Diagnostics = enum { errors, text, json };

/// What `Show.cache_report` selects: no report, the `selka-core: cache:` line, or one
/// `cache-report-v1` JSON line.
pub const CacheReport = enum { off, text, json };

/// Why a build stopped after its report was written.
pub const Error = error{ SourceError, Unsupported, ToolFailed, WriteFailed, OutOfMemory, InvalidIr, PolicyDenied, ConfigurationFailed, CacheMiss };

/// Build `path` into `options.output`. An unchanged build replays its last
/// identical build's executable (`build_replay.zig`) before checking anything.
pub fn build(init: std.process.Init, path: []const u8, options: Options, report: *std.ArrayList(u8)) Error!u8 {
    const budget: ?run_budget.RunBudget = if (options.show.codegen.harness_steps) .{ .harness_steps = true, .memory = @import("memory_budget").test_default } else null;
    return buildWith(init, path, options, budget, report);
}

/// `build` for `selka run`: the program also installs `budget` when `main` starts
/// (NEW-CORE-S5-RUN-1). The budget is part of the replay key.
pub fn buildRun(init: std.process.Init, path: []const u8, options: Options, budget: run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    return buildWith(init, path, options, budget, report);
}

/// The project entry `path` resolves to, with its configuration (`selka.json`).
pub fn resolveEntry(init: std.process.Init, path: []const u8, report: *std.ArrayList(u8)) Error!project_entry.Entry {
    return project_entry.resolve(init.arena.allocator(), init.io, path, report);
}

fn buildWith(init: std.process.Init, path: []const u8, requested: Options, budget: ?run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    // The project's `links` come first, then the command line's: one list, keyed and replayed as `--link` files are.
    var options = requested;
    const entry = try resolveEntry(init, path, report);
    options.links = try entry.linkSources(init.arena.allocator(), init.io, requested.links, report);
    // So are its `include` folders, before the command line's.
    options.show.codegen.device.include = try entry.includeFolders(init.arena.allocator(), requested.show.codegen.device.include);
    const prepared = try @import("compiler_sharing.zig").prepare(init, options.show.verify_cache or options.show.compiler_cache_disabled);
    var request: BuildRequest = .{ .init = prepared, .path = path, .options = options, .budget = budget, .report = report };
    // The work directory is held while the build's stores are open, and the bounded collector runs once they are closed.
    const retention = @import("work_retention.zig");
    const allocator = init.arena.allocator();
    const hold = try retention.hold(allocator, init.io, options.cache);
    const status = status: {
        defer hold.release();
        // `--verify-cache` first builds what the stage records serve, so the uncached build below can be compared with it.
        if (options.show.verify_cache) request.probe = .{ .compare = try servedUnits(request) };
        if (options.show.verify.testing.eager_attempt) break :status try request.attempt(false);
        break :status try @import("build_retry.zig").run(request, report, BuildRequest.attempt);
    };
    retention.automatic(allocator, init.gpa, init.io, options.cache, init.environ_map);
    return status;
}

const BuildRequest = struct {
    init: std.process.Init,
    path: []const u8,
    options: Options,
    budget: ?run_budget.RunBudget,
    report: *std.ArrayList(u8),
    /// What a pass of a `--verify-cache` build does with the units it emits (`stage_verify.zig`); null for every other build.
    probe: ?stage_verify.Probe = null,

    fn attempt(self: BuildRequest, lazy: bool) Error!u8 {
        return buildAttempt(self, lazy);
    }
};

/// `--verify-cache`, first pass: build the way an ordinary build does, serving the work directory's stage records and the shared
/// stage store, up to the emitted units, and keep the digest of each unit's text. The build neither links nor records a replay.
/// Its diagnostics go to a report of their own, which a failure adds to `request.report`: the uncached pass that follows repeats
/// the warnings of a build that succeeds.
fn servedUnits(request: BuildRequest) Error!*const stage_verify.Served {
    const allocator = request.init.arena.allocator();
    const served = try allocator.create(stage_verify.Served);
    served.* = .{};
    var served_report: std.ArrayList(u8) = .empty;
    var pass = request;
    pass.options.show.verify_cache = false;
    pass.options.show.llvm = null;
    pass.options.show.certificates = null;
    pass.options.show.cache_report = .off;
    pass.options.show.verify.testing.serving = true;
    pass.report = &served_report;
    pass.probe = .{ .collect = served };
    const outcome = @import("build_retry.zig").run(pass, &served_report, BuildRequest.attempt);
    if (outcome) |_| return served else |err| {
        try request.report.appendSlice(allocator, served_report.items);
        return err;
    }
}

/// Link the units a build emitted, except in the stage-served pass of `--verify-cache` (`stage_verify.zig`): that pass keeps their digests and
/// stops before the link (null). The fresh pass compares its own units with them, fails when one differs, and goes on to the link. Any other
/// build has no probe and links.
fn linkUnlessProbed(request: BuildRequest, unit: Unit, built: Emitted, cache: StageContext, report: *std.ArrayList(u8)) Error!?driver.Outcome {
    const allocator = request.init.arena.allocator();
    const units = built.emission.units;
    if (request.probe) |probe| switch (probe) {
        .collect => |served| {
            served.* = try stage_verify.collect(allocator, units);
            return null;
        },
        .compare => |served| {
            const found = try stage_verify.differences(allocator, report, served.*, units);
            if (found.differing != 0) {
                try stage_verify.closing(allocator, report, found.differing, request.options.cache);
                return error.ToolFailed;
            }
            cache.metrics.emission.work.units_compared = found.compared;
        },
    };
    const linked = try linkEmission(request.init, unit, request.options, built, cache, report);
    return linked;
}

fn buildAttempt(request: BuildRequest, allow_lazy: bool) Error!u8 {
    const init = request.init;
    const path = request.path;
    const options = request.options;
    const budget = request.budget;
    const report = request.report;
    const allocator = init.arena.allocator();
    const compression = @import("stage_compression.zig").Policy.parse(init.environ_map.get("SELKA_STAGE_CACHE_COMPRESSION")) catch {
        try report.appendSlice(allocator, "selka-core: SELKA_STAGE_CACHE_COMPRESSION must be 'zlib' or 'none'\n");
        return error.ConfigurationFailed;
    };
    var entry = try project_entry.resolve(allocator, init.io, path, report);
    entry.prefer_standard_sources = options.show.codegen.local_stdlib;
    // A bare image is never replayed: its linker script is an input the replay record does not hold.
    const replaying = options.show.llvm == null and options.show.certificates == null and options.show.codegen.target.runsHere();
    var handle = inputs_handle.Handle.init(allocator, init.io, init.environ_map);
    // The shadowed-standard-module warnings come from the entry directory's listing, an input of
    // the handle: a replay prints them from its record while the listing is unchanged, a build prints
    // them itself, and either way they come before everything the record's report holds.
    const shadowed = try entry.shadowedStandard(&handle);
    entry.shadowed = shadowed;
    const record_start = report.items.len;
    const context: build_replay.Context = .{ .arena = allocator, .io = init.io, .handle = &handle, .cache = options.cache, .zig = options.zig, .flags = try flags(init, path, options, budget), .entry = entry };
    if (try replayBuild(context, options, request.probe != null, report)) return 0;
    try project_entry.appendShadowedStandardWarnings(shadowed, allocator, report);
    // This build reads the demand state of the generation its settings scope names, and publishes its own generation (`demand_generation.zig`).
    const scope_name = try demand_generation.scopeName(allocator, demand_generation.demandScope(options.cache, entry.path, context.flags));
    const generations = try demand_generation.begin(allocator, init.io, demand_generation.demandScope(options.cache, entry.path, context.flags));
    // The check's path is the entry the ownership proofs are keyed by; ownership proofs are records of their own inputs, so they name no generation.
    const check_path = if (options.show.diagnostics == .errors) entry.path else path;
    // The per-scope counts are reported only when a report or a profile archive asks for them (`cacheReport`).
    const observing = options.show.cache_report != .off or language.profile_history.enabled();
    // A `--no-validate` build reads the shared half but publishes nothing to it (`publishesShared`).
    var storage = try stage_store.Store.initWithOptions(init.gpa, init.io, options.cache, .{ .compression = compression, .shared = try sharedStageRoot(allocator, init, options), .publish = publishesShared(options), .observe = observing });
    defer storage.deinit();
    storage.generations = generations;
    var stages: stage_metrics.Report = .{};
    if (!allow_lazy) try noteRetry(allocator, &stages, 1);
    var lowered_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer releaseLowered(&lowered_arena);
    var demand_enabled = !options.show.verify_cache and options.show.certificates == null and reusesLowering(options);
    const lazy_allowed = useDemandBodies(options, budget);
    const Prepared = struct { module: ir.Module, unit: Unit, sources: bool, lazy: ?*lowering_cache.Deferred };
    // The engine's shadow outlives the front-end session that began it: the optimizer's joins are observed after the session is gone.
    var backend_shadow: ?*shadow_rules.Shadow = null;
    defer endShadow(&backend_shadow);
    var prepared: Prepared = while (true) {
        const checked_start = stage_metrics.now(init.io);
        const report_start = report.items.len;
        // The profile covers the whole front-end stage: session setup, the check, and the
        // report, so its exclusive phases account for the stage's time.
        var frontend_profile = language.timings.Profile.init(init.io, options.show.cache_report != .off or language.profile_history.enabled(), .compiler);
        const setup_mark = frontend_profile.mark();
        var session = frontend.Session.init(init.gpa, init.io, entry.root);
        defer session.deinit();
        entry.configure(&session);
        // The entry's cache key name: its realpath under the project root (`entry_name.zig`), never the spelling it was given.
        // It lives in the command's arena, which outlives every re-check and every lowering retry.
        session.files.entry_key = try @import("entry_name.zig").of(allocator, init.io, entry.keyRoot(), entry.path);
        // Every build keeps a typed hole as a located trap (`R_TYPED_HOLE`). A release build then refuses the holes `main` can reach, once
        // the functions it builds are known (`refuseReachableHoles`); one in a function nothing calls is no obstacle.
        session.setHoleTraps(true);
        if (options.show.diagnostics != .errors) session.setFormat(if (options.show.diagnostics == .json) .json else .text);
        // A release build drops the output of `debug(...)` lines, not their arguments: lowering still evaluates those (`build_cap.evaluateDroppedDebug`).
        const drop_debug = options.mode == .release and budget == null;
        var demand = try lowering_demand.Context.init(lowered_arena.allocator(), &storage, drop_debug);
        demand.sources.entry_name = session.files.entry_key;
        if (!options.show.verify_cache) {
            try session.enableCache(init.gpa, options.cache);
            try session.enableSharedCache(init.environ_map);
        }
        session.setProfile(&frontend_profile);
        if (demand_enabled) session.configureDemand(demand.callback());
        frontend_profile.addMark("frontend_session_setup", setup_mark, false);
        // Every exclusive phase inside the check is subtracted, so this records only the check's untimed steps.
        const check_mark = frontend_profile.mark();
        const checked = session.checkFile(allocator, check_path, report) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.SourceError,
        };
        frontend_profile.addMark("check_file_other", check_mark, false);
        const report_mark = frontend_profile.mark();
        if (options.show.diagnostics != .errors) try report.appendSlice(allocator, try session.warnings(allocator));
        const sources = if (replaying) try build_replay.inputs(context, &session) else false;
        try entry.validate(allocator, &session, report);
        // `main`'s capabilities against the target: a family the target does not provide is refused at its parameter.
        try refuseUnprovided(allocator, checked, options.show.codegen.target, options.show.diagnostics, report);
        const hooked = try resolveHooks(allocator, checked, options.show.codegen.device.hooks, report);
        frontend_profile.addMark("frontend_report", report_mark, false);
        stages.nanoseconds.frontend += stage_metrics.elapsed(init.io, checked_start);
        stages.frontend = session.statistics();
        stages.nanoseconds.frontend_phases = try stage_metrics.frontendPhases(allocator, &frontend_profile);
        frontendMetrics(&stages, &session);
        if (session.demandState()) |state| demand.attach(state.prepared, state.omitted);
        const lowering_start = stage_metrics.now(init.io);
        var refusal: build_ir.Refusal = .{};
        var names: op_log.Summary = .{};
        const pointer_bytes = options.show.codegen.target.pointerBytes();
        const input: build_ir.Input = .{ .program = checked.program, .source = checked.src, .drop_debug = drop_debug, .names = namesRequest(options, &names), .pointer_bytes = pointer_bytes, .hooks = hooked.ids };
        var lowering = lowering_cache.Cache.init(&storage);
        lowering.demand = &demand;
        lowering.strict_fit = options.show.verify.testing.serving;
        // The engine's shadow, when it is on, is told what this lowering did (`lowering_shadow.zig`).
        var observed: lowering_cache.Observed = .{ .arena = lowered_arena.allocator() };
        lowering.engine = engineHooks(&session, &observed, init.environ_map, options.show.verify.testing.sabotage_instance_keys);
        const a = lowered_arena.allocator();
        const lazy = if (lazy_allowed) try a.create(lowering_cache.Deferred) else null;
        // The complete-tree retry also replays complete raw bodies, so it defers none and cannot miss again.
        if (lazy) |state| state.* = .{ .arena = a, .store = &storage, .force_eager = !(allow_lazy and demand_enabled) };
        lowering.lazy = lazy;
        const uncached = options.show.verify_cache or !reusesLowering(options);
        const lowered = if (uncached) build_ir.buildExecutable(a, input, &refusal) else build_ir.buildExecutableCached(a, input, &refusal, &lowering);
        var module = lowered catch |err| switch (err) {
            error.CacheMiss => {
                // A cache can disappear after admission. Discard partial IR and
                // diagnostics, then check complete trees exactly once.
                stages.nanoseconds.lowering += stage_metrics.elapsed(init.io, lowering_start);
                try noteRetry(allocator, &stages, stages.lowering.fallbacks + 1);
                demand_enabled = false;
                report.shrinkRetainingCapacity(report_start);
                _ = lowered_arena.reset(.free_all);
                continue;
            },
            error.Unsupported => {
                try reportBuildRefusal(allocator, checked.src, refusal, options.show.diagnostics, report);
                return error.Unsupported;
            },
            else => |other| return other,
        };
        try refuseReachableHoles(allocator, checked.src, &module, options, report);
        stages.lowering.reused = lowering.counts.reused;
        stages.lowering.lowered = lowering.counts.lowered;
        stages.lowering.unfit = lowering.counts.unfit;
        session.observeLowering(.{ .program = checked.program, .src = checked.src, .observed = observed.entries.items, .drop_debug = drop_debug, .entry = "", .built = lowering.counts.lowered + lowering.counts.reused });
        keepShadow(&backend_shadow, &session);
        stages.lowering.deferred = demand.count();
        try reportNames(allocator, options, names, report);
        if (!options.show.verify_cache) try demand.finish();
        if (budget) |installed| try run_budget.instrumentRun(a, &module, installed);
        var made = try unitFor(a, checked, entry.path, session.single != null);
        made.main.hooks = hooked.names;
        const unit = try retainUnit(a, &module, made);
        stages.nanoseconds.lowering += stage_metrics.elapsed(init.io, lowering_start);
        if (lazy) |state| try state.prepare(&module, unit.src);
        break .{ .module = module, .unit = unit, .sources = sources, .lazy = lazy };
    };
    const module = &prepared.module;
    if (prepared.lazy) |state| state.input.module = module;
    const caches: StageContext = .{
        .storage = if (options.show.verify_cache or options.show.certificates != null) null else &storage,
        .io = init.io,
        .lanes = @import("unit_cache.zig").width(init.environ_map, module.functions.items.len),
        .metrics = &stages,
        .demand = if (prepared.lazy) |state| &state.context else null,
        .shadow = backend_shadow,
    };
    const built = try emitUnits(init, module, prepared.unit, options, caches, report);
    const outcome = try linkUnlessProbed(request, prepared.unit, built, caches, report);
    materializationMetrics(&stages, prepared.lazy);
    const flush_start = stage_metrics.now(init.io);
    const flushed = try storage.flush();
    const publication: stage_metrics.Storage = .{
        .flush_nanoseconds = stage_metrics.elapsed(init.io, flush_start),
        .flush_succeeded = flushed,
        .reads = storage.statistics(),
        .compression = @tagName(compression),
        .scopes = try storage.tallies(allocator),
    };
    // The state this build wrote becomes the scope's current generation, so the next build reads it, and a replay of this
    const published = try publishDemand(context, scope_name, generations, options.show.verify_cache);
    retainRoots(&storage, allocator, init.io, scope_name, published);
    // The shared namespace learns this build's live root, and collects when its interval has passed (`stage_collector.zig`).
    storage.publishShared(allocator);
    // A record that cannot be written costs the next build its replay, nothing more.
    const published_generations = published;
    const linked = outcome orelse return 0;
    if (replaying) try remember(context, prepared.sources, linked, report.items[record_start..], published_generations);
    if (options.show.cache_report != .off or language.profile_history.enabled()) try cacheReport(allocator, options.show.cache_report, linked, &stages, &publication, report);
    return 0;
}

/// Record the build for replay; a record that cannot be written costs the next build its replay, nothing more.
fn remember(context: build_replay.Context, sources: anytype, linked: driver.Outcome, record: []const u8, published: build_replay.Published) Error!void {
    build_replay.remember(context, sources, linked.tool, .{ .program = linked.program, .foreign = linked.foreign }, record, published) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => {},
    };
}

/// The keys a build touched are the roots of the generation it published: compaction keeps what they name (`stage_roots.zig`).
/// An uncached build published no generation and keeps no roots.
fn retainRoots(storage: *const stage_store.Store, a: std.mem.Allocator, io: std.Io, scope_name: []const u8, published: build_replay.Published) void {
    if (published.demand == 0) return;
    stage_roots.retain(storage, a, io, scope_name, published.demand);
}

/// Publish the demand generation a build wrote (`demand_generation.zig`) and return the generation and scope its record names.
/// An uncached build writes no demand state, so it publishes nothing and names generation 0.
fn publishDemand(context: build_replay.Context, scope_name: []const u8, generations: stage_store.Generations, uncached: bool) Error!build_replay.Published {
    if (uncached) return .{};
    try demand_generation.publish(context.arena, context.io, demand_generation.demandScope(context.cache, context.entry.path, context.flags), generations);
    return .{ .demand = generations.write, .scope = scope_name };
}

fn replayBuild(context: build_replay.Context, options: Options, probing: bool, report: *std.ArrayList(u8)) Error!bool {
    if (probing or options.show.verify_cache) return false;
    if (options.show.llvm != null or options.show.certificates != null or options.show.verify.names) return false;
    if (!try build_replay.replay(context, options.output, report)) return false;
    if (options.show.cache_report != .off or language.profile_history.enabled()) try cacheReport(context.arena, options.show.cache_report, null, null, null, report);
    return true;
}

/// Whether the compiler validates every build it makes, of every mode and with every body: a debug compiler does, unless a test
/// asks it to validate as an optimised one (`--validate-like-optimised`) or the build asks for no default validation (`--no-validate`).
fn compilerValidates(options: Options) bool {
    return verify_ir.enabled and !options.show.verify.testing.like_optimised and !options.show.verify.skip;
}

/// Whether a build validates its IR, its ownership certificates and the fact tables it computed when no flag asks: every guest
/// build does (`build`, `run`, `build --run`, `run-project` and `test`, `--release` included), in every compiler, unless
/// `--no-validate` turns it off. A debug build defers its facts, so it has no fact tables to validate (`factWork`).
pub fn validatesByDefault(options: Options) bool {
    return !options.show.verify.skip;
}

/// Whether this build checks its IR: by default (`validatesByDefault`, `compilerValidates`), and in every compiler under
/// `--verify-ownership` (whose validator assumes it, and whose records say both were checked), `--verify-facts` (X6, DECISIONS F8)
/// and `--verify-facts-static` (docs/design/fact-certificates.md, A9).
pub fn checksIr(options: Options) bool {
    return checksOwnership(options) or options.show.verify.facts_static;
}

/// Whether this build validates the ownership certificate of each function (design §5): by default (`validatesByDefault`,
/// `compilerValidates`), and in every compiler under `--verify-facts` and `--verify-ownership`.
pub fn checksOwnership(options: Options) bool {
    if (compilerValidates(options) or validatesByDefault(options)) return true;
    return options.facts == .verify or options.facts == .verify_written or options.show.verify.ownership;
}

/// Whether this build validates its fact tables against the final IR (docs/design/fact-certificates.md §7): every build that
/// computed them does by default (`validatesByDefault`, `compilerValidates`), every compiler does under `--verify-facts` and
/// `--verify-written-copies`, and `--verify-facts-static` asks for it. The sabotage modes state false facts for the runtime checks
/// to catch, so they skip it.
pub fn checksFacts(options: Options) bool {
    return switch (options.facts) {
        .on => compilerValidates(options) or validatesByDefault(options) or options.show.verify.facts_static,
        .verify, .verify_written => true,
        else => false,
    };
}

/// Whether this build validates every function it finishes with every body present, so it takes no demand bodies: a debug
/// compiler does (`compilerValidates`), and so do `--verify-ownership` and `--verify-facts-static`. A build that validates by
/// default keeps its demand bodies: what it does not bring in was validated by the build that made it (`passes.validatedFinal`).
fn validatesEagerly(options: Options) bool {
    return compilerValidates(options) or options.show.verify.ownership or options.show.verify.facts_static;
}

/// Whether this build may reuse stored lowerings and the summaries that let the front end leave bodies unbuilt: they are
/// keyed by source, not by target, and hold the host's sizes, so a target of another pointer width lowers every body afresh.
fn reusesLowering(options: Options) bool {
    return options.show.codegen.target.pointerBytes() == 8;
}

fn useDemandBodies(options: Options, budget: ?run_budget.RunBudget) bool {
    if (budget != null or validatesEagerly(options)) return false;
    if (!options.mode.developmentOptimized() or options.facts != .on) return false;
    if (!reusesLowering(options)) return false;
    return !options.show.stats and options.show.llvm == null and !options.show.verify_cache and options.show.certificates == null;
}

fn frontendMetrics(stages: *stage_metrics.Report, session: *const frontend.Session) void {
    const cache = session.caches.frontend orelse return;
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

/// Entry metadata shared by ordinary builds and cost's identical LLVM emission.
/// The unit's `source_path` never names the checkout: a header-less `entry` file
/// goes by its basename, its path relative to its own directory (the root its
/// receipts key it under), and a module-headed entry by its module-root-relative
/// path (`shownPath`), so the program's bytes do not depend on where the tree sits
/// (ENTRY-PATH-1).
pub fn unitFor(a: std.mem.Allocator, checked: frontend.Checked, entry: []const u8, single: bool) std.mem.Allocator.Error!Unit {
    return .{
        .src = checked.src,
        .source_path = if (single) std.fs.path.basename(entry) else shownPath(checked.src, checked.program),
        .identity = entry,
        .main = .{
            .parameters = try mainParameters(a, checked.program),
            .result = mainResult(checked.program),
            .capabilities = try mainCapabilities(a, checked.program),
            .runtime_options = true,
        },
    };
}

/// Report the new core's refusal of a construct at `refusal`, as text or as a
/// `diagnostic-v1` record.
pub fn reportBuildRefusal(allocator: std.mem.Allocator, src: language.source.Source, refusal: build_ir.Refusal, diagnostics: Diagnostics, report: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const message = if (refusal.hint.len == 0)
        try std.fmt.allocPrint(allocator, "the new core does not support {s} yet", .{refusal.reason})
    else
        try std.fmt.allocPrint(allocator, "the new core does not support {s} yet: {s}", .{ refusal.reason, refusal.hint });
    const item: language.diagnostic.Diagnostic = .{ .severity = .err, .code = "E_CORE_UNSUPPORTED", .span = .{ .start = refusal.span, .end = refusal.span }, .message = message, .provenance = .{ .rule = refusal.rule } };
    language.friction_session.note(item);
    if (diagnostics == .json) return report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, src, .json));
    const at = frontend.position(src, .{ .start = refusal.span, .end = refusal.span });
    try report.print(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: {s}\n", .{ at.path, at.line, at.column, message });
    if (refusal.rule) |rule| try report.print(allocator, "  note: ownership rule {s}\n", .{@tagName(rule)});
}

/// A release build cannot ship a typed hole `main` reaches; every other mode builds it as a trap. The build lowered only the functions
/// `main` can reach, a function value counting as a call, so each hole left in `module` is reachable: report every one as
/// `E_TYPED_HOLE` and refuse the build.
fn refuseReachableHoles(allocator: std.mem.Allocator, src: language.source.Source, module: *const ir.Module, options: Options, report: *std.ArrayList(u8)) Error!void {
    if (options.mode != .release) return;
    const diagnostics = options.show.diagnostics;
    const holes = try reachable_holes.find(allocator, module);
    if (holes.len == 0) return;
    for (holes) |hole| {
        const message = try std.fmt.allocPrint(
            allocator,
            "unresolved implementation obligation in `{s}`, which main can reach; a release build cannot ship it: fill the hole, or stop calling the function that holds it",
            .{hole.function},
        );
        const item: language.diagnostic.Diagnostic = .{ .severity = .err, .code = language.diagnostic.typed_hole_code, .span = .{ .start = hole.span, .end = hole.span }, .message = message };
        language.friction_session.note(item);
        if (diagnostics == .json) {
            try report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, src, .json));
            continue;
        }
        const at = frontend.position(src, item.span);
        try report.print(allocator, "{s}:{d}:{d}: error[E_TYPED_HOLE]: {s}\n", .{ at.path, at.line, at.column, message });
    }
    return error.SourceError;
}

/// When the ownership validator rejected a function the passes produced, report it and answer `InvalidIr`: an
/// internal compiler error (exit 2) that names the function, the place, the check and the nearest rule, never a
/// refusal of the user's program. Null when the validator rejected nothing.
/// The note under a validator's rejection: the rejection is the compiler's fault, and `--no-validate` builds without the validators
/// no flag asks for.
const way_out = "  note: this is an internal compiler error, not a fault of the program; `--no-validate` builds without the default " ++
    "validators (docs/tooling/native-build.md#certificate-validators)\n";

fn validationRejection(allocator: std.mem.Allocator, refusal: *const own.Refusal, report: *std.ArrayList(u8)) ?Error {
    const sink = refusal.certificates orelse return null;
    const message = sink.rejection orelse return null;
    report.print(allocator, "error[E_OWNERSHIP_VALIDATION]: {s}\n" ++ way_out, .{message}) catch return error.OutOfMemory;
    return error.InvalidIr;
}

/// Return `err`, first rendering a located `E_CORE_UNSUPPORTED` when the
/// ownership pass could not place an operation. Every other failure is the
/// caller's to report.
fn passFailure(allocator: std.mem.Allocator, unit: Unit, refusal: *const own.Refusal, report: *std.ArrayList(u8), diagnostics: Diagnostics, err: Error) Error {
    if (err == error.Unsupported) if (validationRejection(allocator, refusal, report)) |internal| return internal;
    if (err == error.Unsupported) {
        if (unit.refusal) |retained| retained.* = .{ .span = refusal.span, .reason = ownershipMessage(allocator, unit.src, refusal.*) catch return error.OutOfMemory, .rule = refusal.rule };
        reportOwnershipRefusal(allocator, unit.src, refusal.*, diagnostics, report) catch return error.OutOfMemory;
    }
    return err;
}

/// Render the ownership refusal: the function, the operation and its source
/// site, so a build never exits non-zero with nothing on standard error. When the
/// pass named the other place the operation conflicts with, a note points at it.
pub fn reportOwnershipRefusal(allocator: std.mem.Allocator, src: language.source.Source, refusal: own.Refusal, diagnostics: Diagnostics, report: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const message = try ownershipMessage(allocator, src, refusal);
    const related = try refusal_text.note(allocator, src, refusal);
    const item: language.diagnostic.Diagnostic = .{ .code = "E_CORE_UNSUPPORTED", .span = .{ .start = refusal.span, .end = refusal.span }, .message = message, .related = related, .provenance = .{ .rule = refusal.rule } };
    language.friction_session.note(item);
    if (diagnostics == .json) return report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, src, .json));
    if (refusal.span == 0) {
        try report.print(allocator, "error[E_CORE_UNSUPPORTED]: {s}\n", .{message});
    } else {
        const at = frontend.position(src, .{ .start = refusal.span, .end = refusal.span });
        try report.print(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: {s}\n", .{ at.path, at.line, at.column, message });
    }
    if (refusal.rule) |rule| try report.print(allocator, "  note: ownership rule {s}\n", .{@tagName(rule)});
    if (related) |other| {
        const at = frontend.position(src, other.span);
        try report.print(allocator, "  note: {s}:{d}:{d}: {s}\n", .{ at.path, at.line, at.column, other.message });
    }
}

fn ownershipMessage(allocator: std.mem.Allocator, src: language.source.Source, refusal: own.Refusal) std.mem.Allocator.Error![]const u8 {
    return refusal_text.message(allocator, src, refusal);
}

/// The canonical encoding of every build flag that changes the executable or the
/// report: `--link` sources by absolute path, and both the entry and each `--link`
/// source again as the command line spelled them.
/// The lowering cache's record of what it lowered or restored, when the engine's shadow is watching this session's lowering.
/// What the optimizer hands the engine's shadow: the facts it joined, and what it made of each function.
const Watched = struct { joined: *facts_shadow.Observed, made: *optimizer_shadow.Observed };

/// Ask the optimizer to hand over the facts it joins and what it makes of each function, when the engine's shadow is watching.
fn watchJoins(context: *optimization_cache.Context, stage: StageContext, watched: Watched) void {
    const shadow = stage.shadow orelse return;
    // A shadow that only decides the front end's keys compares nothing here, and noting every function's final body is not free.
    if (!shadow.comparing()) return;
    context.lazy.facts = watched.joined;
    context.lazy.optimized = watched.made;
}

/// What the shadow is told about the optimizer's output besides the output itself.
const Settings = struct { mode: []const u8, facts_on: bool, entry: []const u8 };

/// Let the engine's shadow compare its answers about the program's facts and the optimized units with what the optimizer made.
fn judgeJoins(stage: StageContext, watched: Watched, settings: Settings) void {
    const shadow = stage.shadow orelse return;
    if (!shadow.comparing()) return;
    shadow.observeFacts(.{ .observed = watched.joined, .mode = settings.mode, .facts_on = settings.facts_on, .entry = settings.entry });
    shadow.observeOptimized(.{ .observed = watched.made, .mode = settings.mode, .entry = settings.entry });
}

/// Let the engine's shadow compare its answers about the emitted units with what the emitter made.
fn judgeEmitted(stage: StageContext, units: []const emit_units.Unit, module: *const ir.Module, settings: Settings) void {
    const shadow = stage.shadow orelse return;
    if (!shadow.comparing()) return;
    shadow.observeEmitted(.{ .units = units, .module = module, .mode = settings.mode, .entry = settings.entry });
}

/// Keep the engine's shadow of `session`, which the session gives up, for the stages after the front end; an earlier one is ended.
fn keepShadow(held: *?*shadow_rules.Shadow, session: *frontend.Session) void {
    if (held.*) |earlier| earlier.end();
    held.* = session.detachShadow();
}

/// Free the lowered program's arena, unless a `selka build` that ends the process leaves it to the kernel (`process_exit.zig`).
fn releaseLowered(arena: *std.heap.ArenaAllocator) void {
    if (!process_exit.leavesMemory()) arena.deinit();
}

/// End the engine's shadow the build kept, writing its summary line.
fn endShadow(held: *?*shadow_rules.Shadow) void {
    if (held.*) |shadow| shadow.end();
    held.* = null;
}

/// What the engine gives a lowering cache: the notes for its comparing shadow, and the checked-body parts that key a function when
/// it decides the session's modules and `SELKA_ENGINE_DECIDE_LOWERING` is not off.
fn engineHooks(session: *const frontend.Session, observed: *lowering_cache.Observed, environment: *const std.process.Environ.Map, sabotage_instance_keys: bool) lowering_cache.EngineHooks {
    const parts = if (shadow_rules.decidesLowering(environment)) session.bodyParts() else null;
    return .{
        .observed = observedBy(session, observed),
        .parts = parts,
        .assembly = parts != null,
        .field_reach_arguments = sabotage_instance_keys,
    };
}

fn observedBy(session: *const frontend.Session, observed: *lowering_cache.Observed) ?*lowering_cache.Observed {
    return if (session.shadowsLowering()) observed else null;
}

/// Count the build's retries as `count` and name the place that lost the stored record that made it start again.
fn noteRetry(allocator: std.mem.Allocator, stages: *stage_metrics.Report, count: usize) std.mem.Allocator.Error!void {
    stages.lowering.fallbacks = count;
    stages.lowering.retry = try cache_miss.take(allocator);
}

/// The per-user shared stage store this build reads and publishes to, or null when `--no-cache` or `--verify-cache`
/// disables it, or when no root is selected (`shared_cache_policy`, tier `stages`). An unusable root is handled by the store.
/// Whether a build publishes its records to the stage store's shared half. A `--no-validate` build does not: the shared half keeps
/// the first record of a key, so its unvalidated final records would make every validating build of another work directory refuse
/// them and make those bodies again on each build. It still reads the shared half.
fn publishesShared(options: Options) bool {
    return !options.show.verify.skip;
}

fn sharedStageRoot(a: std.mem.Allocator, init: std.process.Init, options: Options) std.mem.Allocator.Error!?[]const u8 {
    if (options.show.verify_cache or options.show.compiler_cache_disabled) return null;
    const selection = try @import("selka").shared_cache_policy.resolve(a, init.environ_map, .stages, null) orelse return null;
    return selection.path;
}

fn flags(init: std.process.Init, path: []const u8, options: Options, budget: ?run_budget.RunBudget) Error![]const u8 {
    const allocator = init.arena.allocator();
    const links = try allocator.alloc([]const u8, options.links.len);
    for (options.links, links) |link, *absolute| absolute.* = std.Io.Dir.cwd().realPathFileAlloc(init.io, link, allocator) catch link;
    const text = std.json.Stringify.valueAlloc(allocator, .{
        .mode = options.mode,
        .compile = options.mode.keyed(),
        .single_owner = "zero-rc",
        .zero_rc = "zero-rc",
        .facts = options.facts,
        .local_stdlib = options.show.codegen.local_stdlib,
        .stats = options.show.stats,
        .vectors = options.show.codegen.generic_vectors,
        .frames = options.show.codegen.trap_frames,
        .counters = options.show.codegen.counters,
        .verify_ownership = checksOwnership(options),
        .verify_facts = checksFacts(options),
        .links = links,
        // The program embeds the entry's and each C source's path as the command line spelled it
        // (trap sites, debug information), which the resolved paths above do not tell apart.
        .entry_spelling = path,
        .link_spellings = options.links,
        .diagnostics = options.show.diagnostics,
        .run = budget,
    }, .{}) catch return error.OutOfMemory;
    return withTarget(allocator, text, options.show.codegen.target);
}

/// The replay key's flags text for `target`. A host build's flags are the single-target compiler's, so its stage keys keep their
/// values; another target is named after them, and a host build for a CPU model other than the machine's (`--cpu`) is named by
/// the model: a replay record holds the built program, and the record of a `native` build must not answer for an `x86-64-v3` one.
fn withTarget(allocator: std.mem.Allocator, text: []const u8, target: *const target_description.Target) Error![]const u8 {
    if (std.mem.eql(u8, target.name, target_description.host.name)) {
        const model = target.cpuModel();
        if (model == .native) return text;
        return std.fmt.allocPrint(allocator, "{s}\x00cpu={s}", .{ text, model.spelling() }) catch return error.OutOfMemory;
    }
    return std.fmt.allocPrint(allocator, "{s}\x00target={s}", .{ text, target.name }) catch return error.OutOfMemory;
}

test "the replay key's flags name a host build's CPU model unless it is the machine's, and keep a native host build's text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const native = try withTarget(a, "flags", &target_description.host);
    try std.testing.expectEqualStrings("flags", native);
    const v3 = try withTarget(a, "flags", target_description.host.forCpu(.x86_64_v3).?);
    try std.testing.expectEqualStrings("flags\x00cpu=x86-64-v3", v3);
    try std.testing.expectEqualStrings("flags\x00target=thumbv6m-none", try withTarget(a, "flags", &target_description.thumbv6m_none));
}

/// Say what the caches served: for a replayed build (`outcome` null) that it replayed,
/// else the units linked, reused, compiled and verified, whether the program store
/// served the executable, and the tool processes started. `shared_mismatches`
/// counts shared program records that disagreed with this build's bytes; the
/// text line names it only when it is not zero.
fn cacheReport(allocator: std.mem.Allocator, form: CacheReport, outcome: ?driver.Outcome, stages: ?*const stage_metrics.Report, storage: ?*const stage_metrics.Storage, report: *std.ArrayList(u8)) Error!void {
    const c = if (outcome) |built| built.counts else driver.Counts{};
    const program = if (outcome) |built| (if (built.reuse.local) "reused" else "linked") else "replayed";
    if (form == .json or language.profile_history.enabled()) {
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
            .program_shared = if (outcome) |built| built.reuse.shared else false,
            .shared_mismatches = c.shared_mismatches,
            .link = c.link,
            .unit_timings = if (outcome) |built| built.unit_timings else &.{},
        }, .{}) catch {
            if (form != .off) return error.OutOfMemory;
            language.profile_history.markIncomplete();
            return;
        };
        language.profile_history.captureJson(record);
        if (form == .json) {
            try report.print(allocator, "{s}\n", .{record});
            return;
        }
    }
    if (form == .off) return;
    if (outcome == null) return report.appendSlice(allocator, "selka-core: cache: replayed the last identical build\n");
    // One line per front-end miss reason that occurred, by name, in MissReason order. They come
    // before the summary: a native run keeps only what follows the first `selka-core: cache:`
    // line (`native_execute.afterBuild`), so a miss line after it would reach the program's stderr.
    if (stages) |built| for (std.meta.tags(language.semantic_cache.MissReason), built.frontend_misses.total) |reason, count| {
        if (count != 0) try report.print(allocator, "selka-core: front-end miss {s}: {d}\n", .{ language.semantic_cache.missReasonName(reason), count });
    };
    const format = "selka-core: cache: {d} units, {d} reused, {d} compiled, {d} verified; program {s}; {d} processes{s}\n";
    const mismatches = if (c.shared_mismatches == 0) "" else try std.fmt.allocPrint(allocator, "; {d} shared mismatches", .{c.shared_mismatches});
    try report.print(allocator, format, .{ c.units, c.reused, c.compiled, c.verified, program, c.processes, mismatches });
}

/// What the back half of a build needs to know about the checked source.
pub const Unit = struct {
    /// The merged source trap positions are located in.
    src: language.source.Source,
    /// The entry file's path as LLVM's `source_filename` and the entry's `DIFile`
    /// name it: root-relative, never absolute (`unitFor`, ENTRY-PATH-1).
    source_path: []const u8,
    /// The entry function's parameter names (which pick stdout or stderr for a
    /// `Stream`) and, when it returns a `Result`, its case tags.
    main: emit_llvm.Main,
    /// Optional structured failure retained by test-runner classification.
    refusal: ?*build_ir.Refusal = null,
    /// The program's entry identity for its family in the work directory (`driver.Family.entry`): the entry a
    /// build names, or a test program's file and case. Empty when the caller has none.
    identity: []const u8 = "",
};

/// Detach the backend's remaining frontend views onto its result arena. The
/// caller may release checked trees after success; partial copies on failure
/// remain in that arena and leave the frontend safe to release exactly once.
pub fn retainUnit(arena: std.mem.Allocator, module: *ir.Module, given: Unit) std.mem.Allocator.Error!Unit {
    try backend_owned.retainModule(arena, module);
    var retained = given;
    retained.src = try backend_owned.retainSource(arena, given.src);
    retained.source_path = try arena.dupe(u8, given.source_path);
    retained.identity = try arena.dupe(u8, given.identity);
    retained.main.parameters = try backend_owned.retainNames(arena, given.main.parameters);
    retained.main.capabilities = try arena.dupe(u8, given.main.capabilities);
    retained.main.hooks = try backend_owned.retainNames(arena, given.main.hooks);
    return retained;
}

/// The back half of `build`: run the selected passes on `module`, emit LLVM IR, and
/// link the executable. `selka-core test` reaches it with a module of its own making
/// and keys its execution receipts by the answer, the linked program's exact key
/// (`driver.Outcome.program_key`, EXEC-RECEIPT-1).
pub fn finish(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!?[32]u8 {
    const outcome = try linkEmitted(init, module, unit, options, report);
    return outcome.program_key;
}

fn linkEmitted(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!driver.Outcome {
    var stages: stage_metrics.Report = .{};
    const outcome = try linkEmittedCached(init, module, unit, options, .{ .storage = null, .io = init.io, .lanes = 1, .metrics = &stages }, report);
    // Guest-test lowering/checking is outside this boundary. Do not expose the
    // default zero frontend fields as if we had measured them here.
    if (language.profile_history.enabled()) {
        try cacheReport(init.arena.allocator(), .off, outcome, null, null, report);
        inline for (.{ "optimizer", "emission", "native", "linker" }) |phase| language.profile_history.capture(.{
            .version = "phase-timings-v1",
            .kind = "timing",
            .tool = "compiler",
            .name = "core." ++ phase,
            .duration_ns = @field(stages.nanoseconds, phase),
            .inclusive = comptime std.mem.eql(u8, phase, "native"),
        });
    }
    return outcome;
}

fn linkEmittedCached(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, cache: StageContext, report: *std.ArrayList(u8)) Error!driver.Outcome {
    const built = try emitUnits(init, module, unit, options, cache, report);
    return linkEmission(init, unit, options, built, cache, report);
}

/// What the front half of the back end made: the emitted units, and the identity of the C compiler the callables' digests were
/// made under (null when no callable needed one), which the link must find unchanged.
const Emitted = struct { emission: Emission, tool: ?tool_identity.Identity };

/// Run the passes and emit the units of `module`, writing the certificates and the LLVM file the options ask for.
fn emitUnits(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, cache: StageContext, report: *std.ArrayList(u8)) Error!Emitted {
    const allocator = init.arena.allocator();
    const identity_tool = try prepareCallables(init, module, unit, options, cache);
    const emission = try emittedCached(.{ .result = allocator, .scratch = init.gpa }, module, unit, options, cache, report);
    if (options.show.certificates) |directory| {
        try writeCertificates(init.io, directory, emission.certificates);
        if (emission.certificate_problems != 0) return error.InvalidIr;
    }
    if (options.show.llvm) |where| {
        // A bare program that starts the second core shows the text its units compile as (`driver.emittedText`).
        const text = driver.emittedText(allocator, options.show.codegen.target, emission.units, emission.whole.?) catch |err|
            return if (err == error.OutOfMemory) error.OutOfMemory else error.ToolFailed;
        std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = where, .data = text }) catch return error.WriteFailed;
    }
    return .{ .emission = emission, .tool = identity_tool };
}

/// Refuse a bare build whose program needs the prebuilt number-text object (`number_runtime.zig`): float text, a format
/// specification or BLAKE3. The object is built for the host, so a bare image could only link a trap in its place (the
/// runtime's `R_BARE_UNSUPPORTED`, which stays as the backstop). A hosted build is never refused here.
fn refuseNumberText(allocator: std.mem.Allocator, units: []const emit_units.Unit, target: *const target_description.Target, report: *std.ArrayList(u8)) Error!void {
    const used = driver.bareNumberUse(allocator, target, units) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ToolFailed;
    const symbol = used orelse return;
    const what = @import("number_runtime.zig").describe(symbol);
    try report.print(allocator, "error[E_TARGET_NUMBER_TEXT]: the program uses {s} (`{s}`), which the target `{s}` does not provide: " ++
        "its number-text runtime is built for the host only; leave it out of a program for this target\n", .{ what, symbol, target.name });
    return error.SourceError;
}

/// Refuse a bare build whose program calls a `registers` or `cpu` function only a simulated bank has
/// (`registers.simulated()`, `poke32`, `script32`, `pin32`, the log readers, `cpu`'s event log readers): the device's registers are real, its `main` receives them, and the
/// bare runtime has no bank, so the link would fail on the symbol. A hosted build is never refused here.
fn refuseSimulatedRegisters(allocator: std.mem.Allocator, units: []const emit_units.Unit, target: *const target_description.Target, report: *std.ArrayList(u8)) Error!void {
    const used = driver.bareSimulatedRegisters(allocator, target, units) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ToolFailed;
    const name = used orelse return;
    try report.print(allocator, "error[E_TARGET_SIMULATED_REGISTERS]: the program calls `{s}`, which only a simulated register bank has; " ++
        "on the target `{s}` `main(reg: Registers)` receives the device's registers: keep the simulated bank to tests on the host\n", .{ name, target.name });
    return error.SourceError;
}

/// The `@freestanding(ram)` functions of a bare build's units and the source paths their faults name (`ram_image.zig`):
/// empty for a hosted build and for a program with none.
fn ramInputs(allocator: std.mem.Allocator, units: []const emit_units.Unit, target: *const target_description.Target) Error!RamInputs {
    var inputs: RamInputs = .{};
    if (target.system.runtime != .bare) return inputs;
    for (units) |unit| {
        const text = driver.unitText(allocator, unit) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ToolFailed;
        try ram_image.ramSymbols(allocator, text, &inputs.functions, &inputs.helpers);
        try ram_image.faultPaths(allocator, text, &inputs.paths);
    }
    // The `registers` helpers are checked after the functions the source declared.
    try inputs.functions.appendSlice(allocator, inputs.helpers.items);
    return inputs;
}

/// What the image check of a bare build reads besides the image: the `ram` functions' symbols (then the helpers placed
/// beside them) and the fault paths.
const RamInputs = struct { functions: std.ArrayList([]const u8) = .empty, helpers: std.ArrayList([]const u8) = .empty, paths: std.ArrayList([]const u8) = .empty };

/// After a bare link, check that the code of every `@freestanding(ram)` function in the image reaches nothing in flash
/// (`ram_image.zig`). A broken promise is refused with `E_FREESTANDING_RAM` and the image is removed, so no `.bin` or
/// `.uf2` is made of it; the check runs on every build, a stored program's too.
fn checkRamImage(init: std.process.Init, inputs: RamInputs, output: []const u8, report: *std.ArrayList(u8)) Error!void {
    if (inputs.functions.items.len == 0) return;
    const allocator = init.arena.allocator();
    const elf = std.Io.Dir.cwd().readFileAlloc(init.io, output, allocator, .limited(1 << 28)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try report.print(allocator, "error[{s}]: cannot read the image {s} to check its @freestanding(ram) functions: {t}\n", .{ ram_image.diagnostic_code, output, err });
        return error.SourceError;
    };
    const found = try ram_image.check(allocator, .{ .elf = elf, .functions = inputs.functions.items, .paths = inputs.paths.items }) orelse return;
    try report.appendSlice(allocator, try ram_image.message(allocator, found));
    std.Io.Dir.cwd().deleteFile(init.io, output) catch {};
    return error.SourceError;
}

/// Refuse a hosted build whose program calls a `registers` function only a device has (`registers.start_core1`, MCU-CORE1):
/// the hosted runtime has no second core, and Linux gives `main` no `Registers`. A bare build is never refused here.
fn refuseDeviceRegisters(allocator: std.mem.Allocator, units: []const emit_units.Unit, target: *const target_description.Target, report: *std.ArrayList(u8)) Error!void {
    const used = driver.hostedDeviceRegisters(allocator, target, units) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ToolFailed;
    const name = used orelse return;
    try report.print(allocator, "error[E_TARGET_DEVICE_REGISTERS]: the program calls `{s}`, which only a device has; " ++
        "the target `{s}` has no second core to start: build it with `--target thumbv6m-none`, and keep it out of tests on the host\n", .{ name, target.name });
    return error.SourceError;
}

/// Compile the emitted units and link them into `options.output`.
fn linkEmission(init: std.process.Init, unit: Unit, options: Options, built: Emitted, cache: StageContext, report: *std.ArrayList(u8)) Error!driver.Outcome {
    const allocator = init.arena.allocator();
    const stages = cache.metrics;
    const emission = built.emission;
    const identity_tool = built.tool;
    try refuseNumberText(allocator, emission.units, options.show.codegen.target, report);
    try refuseSimulatedRegisters(allocator, emission.units, options.show.codegen.target, report);
    const ram = try ramInputs(allocator, emission.units, options.show.codegen.target);
    try refuseDeviceRegisters(allocator, emission.units, options.show.codegen.target, report);
    const native_start = stage_metrics.now(init.io);
    var outcome = driver.linkWithScratch(allocator, init.gpa, init.io, init.environ_map, .{
        .zig = options.zig,
        .work = options.cache,
        .output = options.output,
        .family = .{
            .mode = options.mode,
            .entry = unit.identity,
            .target = options.show.codegen.target,
            .linker_script = options.show.codegen.device.linker_script,
            .linker_text = options.show.codegen.device.linker_text,
            .include = options.show.codegen.device.include,
            .symbols = ram.functions.items.len != 0,
        },
        .links = options.links,
        .units = emission.units,
        // A target with no vector plans keeps every loop scalar, so its `@vectorize` loops are not checked.
        .inspection = .{ .verify = options.show.verify_cache, .measure_units = options.show.cache_report != .off or language.profile_history.enabled(), .check_vectorize = options.facts == .on and options.show.codegen.target.vector.plans },
    }, report) catch |err| return switch (err) {
        error.VectorizeFailed => error.SourceError,
        error.OutOfMemory => error.OutOfMemory,
        error.ToolFailed => error.ToolFailed,
        error.WriteFailed => error.WriteFailed,
        error.CacheMiss => error.CacheMiss,
    };
    if (identity_tool) |expected| if (!sameIdentityTool(expected, outcome.tool)) return error.ToolFailed;
    try checkRamImage(init, ram, options.output, report);
    stages.nanoseconds.native = stage_metrics.elapsed(init.io, native_start);
    stages.nanoseconds.linker = outcome.counts.link.ns;
    if (emission.cost_report) |measured| {
        var final = measured;
        const remarks = try driver.optimizationRemarks(allocator, init.io, init.environ_map, .{
            .zig = options.zig,
            .work = options.cache,
            .output = "",
            .family = .{ .mode = options.mode, .entry = unit.identity, .target = options.show.codegen.target },
            .links = &.{},
            .units = emission.units,
            .inspection = .{ .verify = options.show.verify_cache },
        });
        if (remarks.yaml) |yaml| cost_remarks.apply(&final, yaml);
        try cost.llvmStats(allocator, report, final.totals, remarks);
        outcome.counts.processes += remarks.processes;
    }
    return outcome;
}

/// The final module, its pass result and its unit: what the reports after the passes read.
const Final = struct { module: *const ir.Module, result: *const passes.Result, unit: Unit };

/// The `--stats` cost lines and the clause report, which reads the same final bodies and facts and is computed
/// wherever the cost totals are (`--stats`, `selka cost`); nothing without them.
fn statsLines(allocator: std.mem.Allocator, final: Final, measured: ?cost.Report, report: *std.ArrayList(u8)) Error!clause_report.Report {
    const snapshot = measured orelse return .{};
    try cost.stats(allocator, report, snapshot.totals);
    const where: clause_report.Where = .{ .locator = locator(&final.unit.src), .fallback_path = final.unit.source_path, .text = final.unit.src.bytes };
    const clauses = try clause_report.collect(allocator, final.module, final.result, where);
    try clause_report.stats(allocator, report, clauses);
    return clauses;
}

/// Arena-owned native units and optional compatibility LLVM from one pass run.
pub const Emission = struct {
    units: []const emit_units.Unit,
    whole: ?[]const u8 = null,
    cost_report: ?cost.Report = null,
    sites: []const cost.Site = &.{},
    /// What the facts made of every clause and `assert` (`clause_report.zig`); empty unless `--stats` or `cost` asked.
    clauses: clause_report.Report = .{},
    /// The certificate files `--emit-certificates` asked for, and how many functions they could not describe.
    certificates: []const CertificateFile = &.{},
    certificate_problems: u32 = 0,
};

/// One unit's ownership certificates: the file name (without extension) and its text.
pub const CertificateFile = struct {
    name: []const u8,
    text: []const u8,
    /// `certificate` (ownership), `fact-certificate` (docs/design/fact-certificates.md) or `core-ir` (the final IR, `ir_text.zig`):
    /// the extension after the name.
    kind: []const u8 = "certificate",
};

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
    return emittedCached(.{ .result = memory.arena, .scratch = memory.backing, .sites = query.sites }, module, unit, options, .{
        .storage = if (query.fresh) null else query.store,
        .io = query.io,
        .lanes = 1,
        .metrics = query.metrics,
        .queries = query.cost,
    }, report);
}

/// Cost `--sites`: the same pass run, also enumerating the final static allocation and copy sites.
pub fn emittedCost(allocator: std.mem.Allocator, scratch: std.mem.Allocator, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!Emission {
    return emittedCached(.{ .result = allocator, .scratch = scratch, .sites = true }, module, unit, options, null, report);
}
/// Returned IR lives in arena; transient work uses backing.
pub const QueryMemory = struct { arena: std.mem.Allocator, backing: std.mem.Allocator };
/// Borrowed compiler stores and current invocation counters.
pub const QueryContext = struct { store: *stage_store.Store, io: std.Io, metrics: *stage_metrics.Report, cost: *@import("cost_query.zig").Cache, fresh: bool = false, sites: bool = false };

const StageContext = struct {
    queries: ?*@import("cost_query.zig").Cache = null,
    storage: ?*stage_store.Store,
    io: std.Io,
    lanes: usize,
    metrics: *stage_metrics.Report,
    demand: ?*@import("demand_ir.zig").Context = null,
    shadow: ?*shadow_rules.Shadow = null,
};

const Memory = struct { result: std.mem.Allocator, scratch: std.mem.Allocator, sites: bool = false };

fn prepareCallables(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, cache: StageContext) Error!?tool_identity.Identity {
    if (!callable_digest.needed(module)) return null;
    const a = init.arena.allocator();
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = options.zig, .cache = options.cache };
    const tool = tool_identity.capture(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ToolFailed;
    };
    const settings = try std.json.Stringify.valueAlloc(a, .{
        .family = .{ .mode = options.mode, .entry = unit.identity },
        .compile = options.mode.keyed(),
        .facts = options.facts,
        // The fields `Codegen` had before it carried the target, in their order: `.target` below hashes the target.
        .codegen = .{
            .generic_vectors = options.show.codegen.generic_vectors,
            .trap_frames = options.show.codegen.trap_frames,
            .counters = options.show.codegen.counters,
            .local_stdlib = options.show.codegen.local_stdlib,
            .harness_steps = options.show.codegen.harness_steps,
        },
        .ownership = "zero-rc",
        .target = targetFor(options.show),
        .layout = init.environ_map.get("SELKA_CORE_LAYOUT"),
        .sanitize = init.environ_map.get("SELKA_CORE_SANITIZE"),
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

fn resetRefusal(refusal: ?*build_ir.Refusal) void {
    if (refusal) |retained| retained.* = .{};
}

fn verifyWrittenCopies(allocator: std.mem.Allocator, module: *const ir.Module, src: *const language.source.Source, options: Options, known: []const ?@import("facts.zig").Facts, report: *std.ArrayList(u8)) Error!void {
    var census: @import("copy_sites.zig").Census = .{};
    const enabled = checksWrittenCopies(options);
    verify_ir.writtenCopiesWithOptions(allocator, module, locator(src), .{
        .enabled = enabled,
        .source = src.*,
        .format = if (options.show.diagnostics == .json) .json else .text,
        .known = known,
        .census = &census,
    }, report) catch |err| {
        // A hidden copy is the compiler's fault: no source spells one. The note names the way out, as every validator's does.
        if (err == error.InvalidIr and options.show.diagnostics != .json) try report.appendSlice(allocator, way_out);
        return err;
    };
    // The check's census (W4): the same list and readings `cost --sites` prints.
    if (options.show.stats and enabled) try reportCopyCensus(allocator, census, report);
}

/// Whether this build runs the hidden-copy check (`verify_ir.writtenCopies`, `E_CORE_HIDDEN_COPY`): every guest build does by
/// default, under the policy of the ownership validator (`checksOwnership`; N5, the user's decision of 12 November 2026), and every
/// compiler under `--verify-written-copies` and `--verify-facts`. `--no-validate` turns the default off. The bodies a build serves
/// from a record alone passed it in the build that made the record (`passes.validatedFinal`).
pub fn checksWrittenCopies(options: Options) bool {
    return checksOwnership(options) or options.facts == .verify_written;
}

/// The `--stats` line of the hidden-copy check: every listed copy site by its reading. Frame blocks and
/// dictionary-key copies are counted and accepted; an unwritten copy would have been refused.
pub fn reportCopyCensus(allocator: std.mem.Allocator, census: @import("copy_sites.zig").Census, report: *std.ArrayList(u8)) Error!void {
    try report.print(allocator, "selka-core: hidden-copy check: written {d}, named operations {d}, implicit {d} " ++
        "(frame blocks {d}, dictionary keys {d}, old captures {d}); implicit copies are counted, not refused\n", .{
        census.written,      census.named,           census.frame_blocks + census.dictionary_keys + census.old_captures + census.unwritten,
        census.frame_blocks, census.dictionary_keys, census.old_captures,
    });
}

fn sameIdentityTool(expected: tool_identity.Identity, actual: tool_identity.Identity) bool {
    if (!actual.cacheable or !std.mem.eql(u8, &expected.digest, &actual.digest)) return false;
    return std.mem.eql(u8, &expected.generation, &actual.generation) and std.mem.eql(u8, &expected.native_target, &actual.native_target);
}

/// The table the ownership pass keeps: it validates when the options ask for it and keeps going after a rejection when
/// the certificates are being written.
fn ownershipSink(options: Options) certificate.Sink {
    return .{ .check = checksOwnership(options), .keep_going = options.show.certificates != null };
}

/// The passes kept going after a rejection so that the certificates could be written; the build fails once they are.
fn keptGoing(allocator: std.mem.Allocator, sink: certificate.Sink, files: *CertificateFiles, report: *std.ArrayList(u8)) Error!void {
    const message = sink.rejection orelse return;
    try report.print(allocator, "error[E_OWNERSHIP_VALIDATION]: {s}\n" ++ way_out, .{message});
    files.problems += 1;
}

/// Where lowering says what its op log replay checked: `summary` when `--verify-names` asks, else nowhere.
fn namesRequest(options: Options, summary: *op_log.Summary) ?*op_log.Summary {
    return if (options.show.verify.names) summary else null;
}

/// One summary line of what the op log replay checked, when `--verify-names` asked for it.
fn reportNames(allocator: std.mem.Allocator, options: Options, summary: op_log.Summary, report: *std.ArrayList(u8)) Error!void {
    if (!options.show.verify.names) return;
    if (!summary.checked) return report.print(allocator, "selka: names: not checked, the build restored lowering artifacts\n", .{});
    try report.print(allocator, "selka: names: {d} segments replayed, {d} types, {d} functions, {d} strings; ", .{ summary.segments, summary.types, summary.functions, summary.strings });
    try report.print(allocator, "{d} ambiguous records, {d} ambiguous functions\n", .{ summary.ambiguous_records, summary.ambiguous_functions });
}

/// How the optimizer's early cutoff runs: verified when `--verify-cutoff` asks, and in a debug compiler for one build in four, chosen by a
/// hash of the lowering keys, so the same program and edit are always checked or never.
fn cutoffMode(verify: Verify, demand: ?*const @import("demand_ir.zig").Context) @import("optimizer_cutoff.zig").Mode {
    if (verify.cutoff) return .verify;
    if (!verify_ir.enabled) return .cutoff;
    const keys = (demand orelse return .cutoff).keys;
    var hasher = std.hash.Wyhash.init(0);
    for (keys) |maybe| if (maybe) |key| hasher.update(key[0..8]);
    return if (hasher.final() % 4 == 0) .verify else .cutoff;
}

/// The `--stats` line of the union-tag rule: how many payload reads of the final IR the rule does not justify. A build counts
/// them and refuses nothing; the gate's `verify-ir-proof` action refuses them.
pub fn reportUnionTags(allocator: std.mem.Allocator, unjustified: usize, report: *std.ArrayList(u8)) Error!void {
    try report.print(allocator, "selka: union-tags: {d} payload reads not justified by a tag test (counted in builds, refused by the gate)\n", .{unjustified});
}

/// The `--stats` line of the construct-read rule (lane VAL): how many constructors of the functions this build validated read
/// a borrow they neither take the owner of nor list as a loan. A build counts them and refuses nothing; the gate's
/// `ownership-proof` action refuses them. A body served from a record was counted by the build that made it.
pub fn reportConstructReads(allocator: std.mem.Allocator, counted: u32, report: *std.ArrayList(u8)) Error!void {
    try report.print(allocator, "selka: construct-reads: {d} constructors read a borrow they neither own nor lend (counted in builds, refused by the gate)\n", .{counted});
}

/// The ownership validator's lines: what the construct-read rule counted, under `--stats` in a build that validated (the rule
/// counts in builds and refuses in the gate, `validate_ownership.build_mode`, lane VAL), and one summary line of what the
/// validator checked, when `--verify-ownership` asked for it.
fn reportOwnership(allocator: std.mem.Allocator, options: Options, sink: certificate.Sink, report: *std.ArrayList(u8)) Error!void {
    if (options.show.stats and sink.check) try reportConstructReads(allocator, sink.construct_reads, report);
    if (!options.show.verify.ownership) return;
    try report.print(allocator, "selka: ownership: {d} functions validated, {d} unchecked\n", .{ sink.validated, sink.unchecked });
}

/// Which raw bodies a demand build holds before its passes (`demand_ir.Context.loaded`); every body for any other build.
fn rawPresent(stage: ?StageContext) []const bool {
    const context = stage orelse return &.{};
    const demand = context.demand orelse return &.{};
    return demand.loaded;
}

/// Which final bodies the passes left in the module (`optimization_cache.Context.lazy.loaded`); every body for a build that took
/// no demand bodies.
fn finalPresent(context: ?*const optimization_cache.Context) []const bool {
    const cache = context orelse return &.{};
    if (cache.lazy.raw == null) return &.{};
    return cache.lazy.loaded;
}

fn emittedCached(memory: Memory, module: *ir.Module, unit: Unit, options: Options, stage: ?StageContext, report: *std.ArrayList(u8)) Error!Emission {
    const allocator = memory.result;
    const scratch = memory.scratch;
    resetRefusal(unit.refusal);
    // Where the ownership pass stopped, when it has no safe schedule: the
    // failure then carries a located E_CORE_UNSUPPORTED (REGRESSION-R2, F8).
    var sink = ownershipSink(options);
    var refusal: own.Refusal = .{ .certificates = certificateSink(options, &sink) };
    const reporting: passes.Reporting = .{ .arena = allocator, .backing = scratch, .module = module, .refusal = &refusal };
    // IR-only callers lack actual toolchain authority; unresolved identities refuse reuse.
    try callable_digest.prepare(allocator, module, locator(&unit.src), .{}, if (stage) |s| s.demand else null);
    // A debug build of the compiler checks the IR it built, and again after
    // optimization; `--verify-facts` makes every compiler check it (X6, F8).
    // A demand build checks the raw bodies it brought in, and the tables once they are complete; the other bodies are checked in their
    // final form, or were by their maker.
    if (checksIr(options)) try verify_ir.checkPresent(allocator, module, .{ .present = rawPresent(stage), .tables = rawPresent(stage).len == 0 }, report);
    // Optimized modes compute facts; ordinary debug keeps every check.
    const verify = options.facts != .on and options.facts != .off;
    const mode: passes.Mode = switch (options.facts) {
        .on => .trusted,
        .off => .off,
        .verify, .verify_written => .verify,
        .sabotage => .sabotage,
        .sabotage_widening => .sabotage_widening,
        .sabotage_length => .sabotage_length,
        .sabotage_overflow => .sabotage_overflow,
        .sabotage_index => .sabotage_index,
        .sabotage_field => .sabotage_field,
        .sabotage_version => .sabotage_version,
    };
    const optimized = options.mode != .debug;
    const ordinary_optimized = options.mode.developmentOptimized() and options.facts == .on;
    const defer_analysis = ordinary_optimized and !options.show.stats and options.show.llvm == null and options.show.certificates == null and !options.show.verify.facts_static;
    var deferred: deferred_facts.Table = .{};
    var joined: facts_shadow.Observed = .{ .arena = allocator };
    var made: optimizer_shadow.Observed = .{ .arena = allocator };
    const optimizer_start = if (stage) |s| stage_metrics.now(s.io) else std.Io.Timestamp.zero;
    var optimizer_context: ?*optimization_cache.Context = null;
    var result = if (stage != null and stage.?.storage != null) cached: {
        const context = try allocator.create(optimization_cache.Context);
        context.* = optimization_cache.Context.init(stage.?.storage.?, try ir_snapshot.Context.init(allocator, module, unit.src), locator(&unit.src));
        optimizer_context = context;
        context.lazy.raw = stage.?.demand;
        context.lazy.cutoff = cutoffMode(options.show.verify, stage.?.demand);
        watchJoins(context, stage.?, .{ .joined = &joined, .made = &made });
        const result = if (defer_analysis)
            reporting.runCachedDeferred(mode, context, &deferred) catch |err| return passFailure(allocator, unit, &refusal, report, options.show.diagnostics, err)
        else if (optimized)
            reporting.runCached(mode, context) catch |err| return passFailure(allocator, unit, &refusal, report, options.show.diagnostics, err)
        else
            reporting.debugCached(context) catch |err| return passFailure(allocator, unit, &refusal, report, options.show.diagnostics, err);
        stage.?.metrics.optimizer = context.statistics;
        judgeJoins(stage.?, .{ .joined = &joined, .made = &made }, .{ .mode = @tagName(mode), .facts_on = options.facts == .on, .entry = unit.identity });
        break :cached result;
    } else if (optimized)
        reporting.runWithScratch(mode) catch |err| return passFailure(allocator, unit, &refusal, report, options.show.diagnostics, err)
    else
        reporting.debugWithScratch() catch |err| return passFailure(allocator, unit, &refusal, report, options.show.diagnostics, err);
    if (stage) |s| s.metrics.nanoseconds.optimizer = stage_metrics.elapsed(s.io, optimizer_start);
    // A body the passes served by its metadata alone is absent; the build that made its record checked it (`passes.validatedFinal`).
    // The union-tag rule counts in builds and refuses in the gate (`verify_union_tags.build_mode`, D-VL-18); `--stats` prints
    // the count of the final IR.
    var unjustified_reads: usize = 0;
    if (checksIr(options)) try verify_ir.checkPresent(allocator, module, .{ .plans = result.plans, .present = finalPresent(optimizer_context), .union_tags = .{ .counted = &unjustified_reads } }, report);
    if (options.show.stats and checksIr(options)) try reportUnionTags(allocator, unjustified_reads, report);
    try reportOwnership(allocator, options, sink, report);
    // Every copy site of the final module must be written (rule C) in every build that validates (`checksWrittenCopies`); a
    // `--no-validate` build leaves the census (`cost --sites`) to report them.
    try verifyWrittenCopies(allocator, module, &unit.src, options, result.known, report);
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
    const clause_rows = try statsLines(allocator, .{ .module = module, .result = &result, .unit = unit }, measured, report);
    // `cost --sites` enumerates the final body's static sites after the same pass run.
    const site_rows = if (memory.sites) try cost.sites(allocator, module, &result, locator(&unit.src), unit.source_path, unit.src.bytes) else &.{};
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
        // An optimized debug build's helpers are ordinary functions (emit_llvm.zig `forced_inline`).
        .forced_inline = !options.mode.developmentOptimized(),
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
        .native_handles = !options.show.verify.testing.serving and final_restorer.nativeHandles(&unit.src),
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
        judgeEmitted(s, units, module, .{ .mode = @tagName(mode), .facts_on = options.facts == .on, .entry = unit.identity });
    }
    const fact_work = try factWork(allocator, scratch, module, .{ .known = result.known, .fields = result.emission.fields }, options);
    var files = try certificateFiles(allocator, module, .{ .requested = options.show.certificates != null, .sink = &sink, .emission = emission, .whole_program = options.mode == .release, .fact_text = fact_work.text }, report);
    try keptGoing(allocator, sink, &files, report);
    try reportFacts(allocator, options, fact_work, &files, report);
    if (options.show.llvm == null) return .{ .units = units, .cost_report = measured, .sites = site_rows, .clauses = clause_rows, .certificates = files.files, .certificate_problems = files.problems };
    if (options.mode == .release) return .{ .units = units, .whole = units[0].llvm, .cost_report = measured, .sites = site_rows, .clauses = clause_rows, .certificates = files.files, .certificate_problems = files.problems };
    const whole = emit_llvm.emitModuleWithScratch(allocator, scratch, module, emission) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Unsupported,
    };
    return .{ .units = units, .whole = whole, .cost_report = measured, .sites = site_rows, .clauses = clause_rows, .certificates = files.files, .certificate_problems = files.problems };
}

const CertificateFiles = struct { files: []const CertificateFile = &.{}, problems: u32 = 0 };

/// What `certificateFiles` reads: whether certificates were asked for, the tables the ownership pass kept, the
/// emission options (they locate the functions in their source modules) and whether the build is one whole-program unit.
const CertificateInput = struct { requested: bool, sink: *const certificate.Sink, emission: emit_llvm.Options, whole_program: bool, fact_text: ?[]const u8 = null };

/// Where the ownership pass keeps its tables: the sink when `--emit-certificates` or the validator asked for them,
/// else nowhere.
fn certificateSink(options: Options, sink: *certificate.Sink) ?*certificate.Sink {
    return if (options.show.certificates != null or sink.check) sink else null;
}

/// Render the ownership certificates of `module`'s final IR, one file per unit; a function the exporter cannot
/// describe is named in `report` and counted. Nothing is rendered unless the build asked for certificates.
fn certificateFiles(a: std.mem.Allocator, module: *const ir.Module, input: CertificateInput, report: *std.ArrayList(u8)) Error!CertificateFiles {
    if (!input.requested) return .{};
    const members = emit_units.members(a, module, input.emission, input.whole_program) catch return error.OutOfMemory;
    var files: std.ArrayList(CertificateFile) = .empty;
    var problems: std.ArrayList(certificate_export.Problem) = .empty;
    var counts: certificate_export.Counts = .{};
    for (members) |member| {
        const text = try certificate_export.render(a, .{ .module = module, .sink = input.sink, .problems = &problems }, member.functions, &counts);
        try files.append(a, .{ .name = member.name, .text = text });
    }
    for (problems.items) |problem| try report.print(a, "error[E_CERTIFICATE]: cannot describe {s}: {s}\n", .{ problem.function, problem.reason });
    if (input.fact_text) |text| try files.append(a, .{ .name = "program", .text = text, .kind = "fact-certificate" });
    // The final IR itself, for the Lean copy of the IR verifier (`proofs/verify_ir`, the gate action `verify-ir-proof`).
    try files.append(a, .{ .name = "program", .text = try @import("ir_text.zig").render(a, module), .kind = "core-ir" });
    return .{ .files = files.items, .problems = counts.problems };
}

/// What the build did with its fact tables (docs/design/fact-certificates.md): the certificate text when `--emit-certificates`
/// asked for it, and the validator's verdict when `checksFacts` says to validate.
const FactWork = struct {
    /// The `fact-certificate-v1` text, when it was asked for and the build computed facts at all.
    text: ?[]const u8 = null,
    /// Whether the fact tables were validated: false for a build that computed none (an unoptimized or deferred one).
    validated: bool = false,
    /// The first function the validator rejected, as an error message.
    rejection: ?[]const u8 = null,
    /// How many functions the validator accepted.
    functions: u32 = 0,
    /// Its totals over the accepted functions.
    stats: validate_facts.Stats = .{},
};

/// Describe the module's final fact tables and, as the options ask, write them as a certificate and validate them against the
/// final IR. Nothing happens when neither is asked for or the build computed no facts (a debug build, deferred analysis). The
/// description lives in a private arena over `scratch` and is freed on return; only the text and the message outlive it.
fn factWork(allocator: std.mem.Allocator, scratch: std.mem.Allocator, module: *const ir.Module, tables: fact_export.Tables, options: Options) Error!FactWork {
    var work: FactWork = .{};
    const writing = options.show.certificates != null;
    const checking = checksFacts(options);
    if (!writing and !checking) return work;
    var any = false;
    for (tables.known) |slot| any = any or slot != null;
    if (!any) return work;
    var arena = std.heap.ArenaAllocator.init(scratch);
    defer arena.deinit();
    const a = arena.allocator();
    const described = try fact_export.describe(a, a, module, tables);
    if (writing) {
        var out: std.ArrayList(u8) = .empty;
        try fact_text.write(allocator, &out, described);
        work.text = out.items;
    }
    if (!checking) return work;
    work.validated = true;
    const verdicts = try validate_facts.validate(a, scratch, described, null);
    for (verdicts, described.functions) |verdict, function| switch (verdict) {
        .accepted => |stats| {
            work.functions += 1;
            work.stats.derived += stats.derived;
            work.stats.assumed += stats.assumed;
            work.stats.proven += stats.proven;
            for (stats.unchecked, &work.stats.unchecked) |count, *total| total.* += count;
        },
        .rejected => |failure| {
            if (work.rejection == null) work.rejection = try validate_facts.describe(allocator, function.header.name, failure);
        },
    };
    return work;
}

/// Report what `factWork` found: a rejection is an internal compiler error (`E_FACT_VALIDATION`, exit 2), kept going past when
/// the certificates are being written so that they exist to inspect; `--verify-facts-static` also says what it validated.
fn reportFacts(allocator: std.mem.Allocator, options: Options, work: FactWork, files: *CertificateFiles, report: *std.ArrayList(u8)) Error!void {
    if (work.rejection) |message| {
        try report.print(allocator, "error[E_FACT_VALIDATION]: {s}\n" ++ way_out, .{message});
        if (options.show.certificates == null) return error.InvalidIr;
        files.problems += 1;
        return;
    }
    if (!options.show.verify.facts_static) return;
    if (!work.validated) return report.appendSlice(allocator, "selka: facts: this build computed none\n");
    var unchecked: u32 = 0;
    for (work.stats.unchecked) |count| unchecked += count;
    try report.print(allocator, "selka: facts: {d} functions validated, {d} proven checks validated, {d} unchecked, {d} intervals assumed\n", .{ work.functions, work.stats.proven, unchecked, work.stats.assumed });
}

/// Write `files` to `directory` as `NAME.certificate` (or `NAME.fact-certificate`), creating the directory.
fn writeCertificates(io: std.Io, directory: []const u8, files: []const CertificateFile) Error!void {
    std.Io.Dir.cwd().createDirPath(io, directory) catch return error.WriteFailed;
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    for (files) |file| {
        const path = std.fmt.bufPrint(&buffer, "{s}/{s}.{s}", .{ directory, file.name, file.kind }) catch return error.WriteFailed;
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = file.text }) catch return error.WriteFailed;
    }
    try removeStaleCertificates(io, directory, files);
}

/// `directory` holds the certificates of this build and no other: a `.certificate`, `.fact-certificate` or `.core-ir` file of an earlier
/// build that is not among `files` (a unit whose text changed has a new name) is removed, so that whoever reads the directory
/// sees what the last build wrote.
fn removeStaleCertificates(io: std.Io, directory: []const u8, files: []const CertificateFile) Error!void {
    var opened = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return error.WriteFailed;
    defer opened.close(io);
    var entries = opened.iterate();
    while (entries.next(io) catch return error.WriteFailed) |entry| {
        const written = std.mem.endsWith(u8, entry.name, ".certificate") or std.mem.endsWith(u8, entry.name, ".fact-certificate") or std.mem.endsWith(u8, entry.name, ".core-ir");
        if (entry.kind != .file or !written) continue;
        if (!certificateListed(files, entry.name)) opened.deleteFile(io, entry.name) catch return error.WriteFailed;
    }
}

fn certificateListed(files: []const CertificateFile, entry: []const u8) bool {
    for (files) |file| {
        if (entry.len == file.name.len + 1 + file.kind.len and std.mem.startsWith(u8, entry, file.name) and entry[file.name.len] == '.' and std.mem.endsWith(u8, entry, file.kind)) return true;
    }
    return false;
}

const FinalRestorer = struct {
    arena: std.mem.Allocator,
    backing: std.mem.Allocator,
    context: ?*optimization_cache.Context,
    result: *passes.Result,

    /// The receipt context of this unit. An eager build (a fallback retry, `force_eager`) has every body and its final metadata,
    /// so it keeps its receipts: they are stored for the next build, which serves its units from them (`nativeHandles` is
    /// the only thing an eager build gives up).
    fn receipts(self: *FinalRestorer, source: *const language.source.Source) ?@import("emission_cache.zig").ReceiptContext {
        const ctx = self.context orelse return null;
        _ = ctx.lazy.raw orelse return null;
        // Receipts need the optimizer's records to be prepared; their keys no longer hold the catalog's layout.
        _ = ctx.layoutDigest() orelse return null;
        return .{
            .finals = ctx.lazy.finals,
            .source = source,
            .loader = .{ .pointer = self, .ensure_fn = ensure },
        };
    }

    /// Native handles name stored artifacts, which only a lazy build's receipts guarantee; an eager build emits its text.
    fn nativeHandles(self: *FinalRestorer, source: *const language.source.Source) bool {
        const ctx = self.context orelse return false;
        const raw = ctx.lazy.raw orelse return false;
        return !raw.force_eager and self.receipts(source) != null;
    }

    fn ensure(pointer: *anyopaque, index: u32) @import("demand_ir.zig").Error!void {
        const self: *FinalRestorer = @ptrCast(@alignCast(pointer));
        const context = self.context orelse return;
        // Every body of an eager build is present: nothing is restored lazily.
        if (context.lazy.raw) |raw| if (raw.force_eager) return;
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        passes.restoreDeferredFinal(self.arena, scratch.allocator(), context, index, self.result) catch |err| switch (err) {
            error.Unsupported => return cache_miss.at(@src()),
            error.OutOfMemory => return error.OutOfMemory,
            error.CacheMiss => return error.CacheMiss,
        };
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

/// The target description a build uses: the one `--target` named, with the generic vector
/// fallback when asked for and the trap-frame mechanism `--trap-frames` picks.
fn targetFor(show: Show) target_description.Target {
    var target = show.codegen.target.*;
    if (show.codegen.generic_vectors) target.vector.x86_avx2 = false;
    // `--trap-frames=posix_exit` measures what the line tables cost, so it drops them too.
    if (show.codegen.trap_frames) |frames| {
        target.system.traps = frames;
        target.system.lines = frames == .dwarf_lines;
    }
    return target;
}

/// The path reports show for a module-headed entry file, as the front end names it and
/// the old core prints it: relative to its module root.
pub fn shownPath(src: language.source.Source, program: language.typed.Program) []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const start: u32 = @intCast(main.declaration.start);
    return frontend.position(src, .{ .start = start, .end = start }).path;
}

/// Checked entry capability families distinguish Host from Stream and provider tokens. A parameter written `T?` (CAP-OPT)
/// is its capability's family with `emit_llvm.optional_family` set.
fn mainCapabilities(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const u8 {
    const main = program.functions[@backingInt(program.main)];
    const families = try allocator.alloc(u8, main.signature.parameter_count);
    for (families, main.scope.locals[0..families.len]) |*family, local| family.* = entryFamily(program, local.ty);
    return families;
}

/// The checked functions a device's hooks name, and the hooks' names in the same order: the extra roots of the lowering.
const Hooked = struct { ids: []const language.typed.FunctionId = &.{}, names: []const []const u8 = &.{} };

/// Whether the module key path `path` is module `module`, as an `import` writes it: `a.b` is `a/b.selka`, at the start of the path or after a `/`.
fn modulePath(path: []const u8, module: []const u8) bool {
    var wanted: [256]u8 = undefined;
    if (module.len + product.source_suffix.len > wanted.len or !product.isSource(path)) return false;
    for (module, 0..) |byte, at| wanted[at] = if (byte == '.') '/' else byte;
    @memcpy(wanted[module.len..][0..product.source_suffix.len], product.source_suffix);
    const suffix = wanted[0 .. module.len + product.source_suffix.len];
    if (!std.mem.endsWith(u8, path, suffix)) return false;
    return path.len == suffix.len or path[path.len - suffix.len - 1] == '/';
}

/// Find the function each of the device's `hooks` names, in the program's modules, and refuse a hook that is missing (its module
/// not imported, or no such function), not `@freestanding`, or of the wrong signature (`E_DEVICE_HOOK`, one line each, naming the
/// device, the hook, the function and what to change). Two hooks may not name one function.
fn resolveHooks(allocator: std.mem.Allocator, checked: frontend.Checked, hooks: []const Hook, report: *std.ArrayList(u8)) Error!Hooked {
    if (hooks.len == 0) return .{};
    const device_hooks = language.device_hooks;
    var ids: std.ArrayList(language.typed.FunctionId) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var refused = false;
    for (hooks) |bound| {
        const spec = device_hooks.named(bound.name) orelse continue;
        const dot = std.mem.lastIndexOfScalar(u8, bound.function, '.') orelse continue;
        const module = bound.function[0..dot];
        const wanted = bound.function[dot + 1 ..];
        var found: ?language.typed.Function = null;
        var module_seen = false;
        for (checked.program.functions) |function| {
            if (function.policy.builtin or function.type_arguments.len != 0) continue;
            if (!modulePath(record_names.moduleOf(checked.src, function.declaration.start), module)) continue;
            module_seen = true;
            if (std.mem.eql(u8, checked.src.text(function.declaration), wanted)) found = function;
        }
        var signature_buffer: [320]u8 = undefined;
        const expected = device_hooks.signature(&signature_buffer, spec);
        const why: ?[]const u8 = if (found) |function| try hookProblem(allocator, function, spec, expected) else if (module_seen)
            try std.fmt.allocPrint(allocator, "the module {s} has no function {s}", .{ module, wanted })
        else
            try std.fmt.allocPrint(allocator, "the program does not import {s}: add `import {s}` to it", .{ module, module });
        if (why == null) for (ids.items) |taken| if (taken == found.?.id) {
            refused = true;
            try report.print(allocator, "{s}: error[E_DEVICE_HOOK]: device \"{s}\": hook \"{s}\" binds {s}, which another hook binds\n", .{ bound.config, bound.device, bound.name, bound.function });
        };
        if (why) |text| {
            refused = true;
            try report.print(allocator, "{s}: error[E_DEVICE_HOOK]: device \"{s}\": hook \"{s}\" binds {s}: {s}\n", .{ bound.config, bound.device, bound.name, bound.function, text });
        } else {
            try ids.append(allocator, found.?.id);
            try names.append(allocator, bound.name);
        }
    }
    if (refused) return error.SourceError;
    return .{ .ids = ids.items, .names = names.items };
}

/// Why `function` cannot be hook `spec`, or null when it can: it must be `@freestanding` and have the hook's signature, `Registers` first
/// and then `Host` or not (`device_hooks.fits`).
fn hookProblem(allocator: std.mem.Allocator, function: language.typed.Function, spec: *const language.device_hooks.Hook, expected: []const u8) Error!?[]const u8 {
    if (function.policy.freestanding == null) return try std.fmt.allocPrint(allocator, "it is not @freestanding (a hook runs where the runtime cannot): add `@freestanding` above it", .{});
    var shapes: [8]language.device_hooks.Shape = undefined;
    const count = function.signature.parameter_count;
    if (count <= shapes.len) {
        for (shapes[0..count], function.scope.locals[0..count]) |*shape, local| shape.* = hookShape(local.ty);
        if (language.device_hooks.fits(spec, shapes[0..count], hookShape(function.signature.return_type))) return null;
    }
    return try std.fmt.allocPrint(allocator, "its signature is not the hook's: {s}", .{expected});
}

/// The shape of a checked type for a hook's signature check.
fn hookShape(ty: language.typed.Type) language.device_hooks.Shape {
    if (ty == .i64) return .int;
    if (ty == .u32) return .u32;
    if (ty == .bool) return .bool;
    if (ty == .unit) return .unit;
    return switch (ty.capabilityIndex() orelse return .other) {
        10 => .registers,
        6 => .host,
        else => .other,
    };
}

/// Refuse every parameter of `main` that asks for a capability family the build's target does not provide
/// (`Target.provides`): a bare target's program has no system to hand it one, and a hosted one has no registers to map
/// (MCU-B1D: the check accepts `main(reg: Registers)` on every target, so the host refuses it here). `T?` counts as its family.
fn refuseUnprovided(allocator: std.mem.Allocator, checked: frontend.Checked, target: *const target_description.Target, diagnostics: Diagnostics, report: *std.ArrayList(u8)) Error!void {
    const program = checked.program;
    const main = program.functions[@backingInt(program.main)];
    var refused = false;
    for (main.scope.locals[0..main.signature.parameter_count]) |local| {
        const ty = entryCapabilityType(program, local.ty) orelse continue;
        const family = std.enums.fromInt(target_description.Capability, ty.capabilityIndex().?);
        if (family != null and target.provides(family.?)) continue;
        refused = true;
        const name = if (family) |known| known.typeName() else "capability";
        const message = if (family == .registers)
            try std.fmt.allocPrint(allocator, "a `Registers` is provided only on a device target (`--target thumbv6m-none`), not on the target `{s}`; a test makes one with `registers.simulated()`", .{target.name})
        else
            try std.fmt.allocPrint(allocator, "`{s}` is not provided on the target `{s}`, which provides {s}; remove the parameter, or build for a target that provides it", .{ name, target.name, try target.providedNames(allocator) });
        const item: language.diagnostic.Diagnostic = .{ .severity = .err, .code = "E_TARGET_CAPABILITY", .span = local.declaration, .message = message };
        language.friction_session.note(item);
        try report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, checked.src, if (diagnostics == .json) .json else .text));
    }
    if (refused) return error.SourceError;
}

/// The capability type of an entry parameter: `T`, or the `T` of a `T?`; null for `args` and any other parameter.
fn entryCapabilityType(program: language.typed.Program, ty: language.typed.Type) ?language.typed.Type {
    if (ty.capabilityIndex() != null) return ty;
    const option = language.reference_tables.prelude.optionShape(ty, program.records) orelse return null;
    return if (option.element.capabilityIndex() != null) option.element else null;
}

fn entryFamily(program: language.typed.Program, ty: language.typed.Type) u8 {
    if (ty.capabilityIndex()) |index| return index;
    const option = language.reference_tables.prelude.optionShape(ty, program.records) orelse return 255;
    const index = option.element.capabilityIndex() orelse return 255;
    return emit_llvm.optional_family | @as(u8, index);
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
    const unit: Unit = .{ .src = .{ .path = "fixture.selka", .bytes = "", .line_starts = &.{} }, .source_path = "fixture.selka", .main = .{} };
    var metrics: stage_metrics.Report = .{};
    const cache: StageContext = .{ .storage = null, .io = std.testing.io, .lanes = 1, .metrics = &metrics };
    try std.testing.expectError(error.ToolFailed, prepareCallables(init, &module, unit, .{ .zig = missing, .cache = directory }, cache));
    const expected: tool_identity.Identity = .{ .path = "tool", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 1, .memo_hit = false, .cacheable = true };
    var changed = expected;
    changed.generation = @splat(4);
    try std.testing.expect(sameIdentityTool(expected, expected));
    try std.testing.expect(!sameIdentityTool(expected, changed));
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "a rejection by the ownership validator is an internal error that names the function, the place and the check" {
    var sink: certificate.Sink = .{ .check = true, .rejection = "ownership validation rejected f at block b0, instruction 2: J3 (used only while live; rules B3): %2 is used after it was consumed" };
    const refusal: own.Refusal = .{ .certificates = &sink };
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?Error, error.InvalidIr), validationRejection(std.testing.allocator, &refusal, &report));
    try std.testing.expectEqualStrings("error[E_OWNERSHIP_VALIDATION]: ownership validation rejected f at block b0, instruction 2: J3 (used only while live; rules B3): %2 is used after it was consumed\n" ++ way_out, report.items);
    const quiet: own.Refusal = .{};
    try std.testing.expectEqual(@as(?Error, null), validationRejection(std.testing.allocator, &quiet, &report));
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "--verify-cutoff verifies the optimizer's early cutoff, and a build with no lowering handles just runs it" {
    try std.testing.expectEqual(@import("optimizer_cutoff.zig").Mode.verify, cutoffMode(.{ .cutoff = true }, null));
    try std.testing.expectEqual(@import("optimizer_cutoff.zig").Mode.cutoff, cutoffMode(.{}, null));
    var verify: Verify = .{};
    try std.testing.expect(verify.ask("--verify-cutoff"));
    try std.testing.expect(verify.cutoff);
}

test "a debug compiler, --verify-facts and --verify-ownership validate the certificates, and the sink follows" {
    const plain: Options = .{ .zig = "zig", .mode = .release, .show = .{ .verify = .{ .skip = true } } };
    const asked: Options = .{ .zig = "zig", .mode = .release, .show = .{ .verify = .{ .ownership = true, .skip = true } } };
    const verified: Options = .{ .zig = "zig", .mode = .release, .facts = .verify, .show = .{ .verify = .{ .skip = true } } };
    const written: Options = .{ .zig = "zig", .show = .{ .certificates = "out" } };
    try std.testing.expect(!checksOwnership(plain));
    try std.testing.expect(checksOwnership(asked));
    try std.testing.expect(checksOwnership(verified));
    try std.testing.expect(ownershipSink(asked).check);
    try std.testing.expect(!ownershipSink(plain).keep_going);
    try std.testing.expect(ownershipSink(written).keep_going);
}

// spec-case: OWNERSHIP-PROOF-1
test "a debug compiler, --verify-facts and --verify-facts-static validate the fact tables, the sabotage modes do not" {
    const plain: Options = .{ .zig = "zig" };
    const asked: Options = .{ .zig = "zig", .show = .{ .verify = .{ .facts_static = true } } };
    const verified: Options = .{ .zig = "zig", .facts = .verify };
    const sabotaged: Options = .{ .zig = "zig", .facts = .sabotage, .show = .{ .verify = .{ .facts_static = true } } };
    try std.testing.expect(checksFacts(plain));
    try std.testing.expect(!checksFacts(.{ .zig = "zig", .show = .{ .verify = .{ .skip = true } } }));
    // The validator assumes of the IR what the verifier checks, so wherever it runs the verifier runs.
    try std.testing.expect(checksIr(asked) and checksIr(verified));
    try std.testing.expect(checksIr(plain));
    try std.testing.expect(checksFacts(asked));
    try std.testing.expect(checksFacts(verified));
    try std.testing.expect(!checksFacts(sabotaged));
}

test "every guest build validates its IR, ownership and computed facts by default in every compiler, and --no-validate does not" {
    const like: Testing = .{ .like_optimised = true };
    // The default is a function of the options: every mode, `--release` included, unless `--no-validate`.
    try std.testing.expect(validatesByDefault(.{ .zig = "zig", .mode = .lean_debug }));
    try std.testing.expect(validatesByDefault(.{ .zig = "zig", .mode = .optimized_debug }));
    try std.testing.expect(validatesByDefault(.{ .zig = "zig", .mode = .optimized_o2 }));
    try std.testing.expect(validatesByDefault(.{ .zig = "zig", .mode = .debug }));
    try std.testing.expect(validatesByDefault(.{ .zig = "zig", .mode = .release }));
    try std.testing.expect(!validatesByDefault(.{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .skip = true } } }));
    // A compiler that validates as an optimised one does: the IR, ownership and the facts a build computes, with demand bodies.
    const lean: Options = .{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .testing = like } } };
    try std.testing.expect(checksOwnership(lean) and checksIr(lean) and checksFacts(lean));
    try std.testing.expect(useDemandBodies(lean, null));
    const release: Options = .{ .zig = "zig", .mode = .release, .show = .{ .verify = .{ .testing = like } } };
    try std.testing.expect(checksOwnership(release) and checksIr(release) and checksFacts(release));
    const skipped: Options = .{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .skip = true, .testing = like } } };
    try std.testing.expect(!checksOwnership(skipped) and !checksIr(skipped) and !checksFacts(skipped) and useDemandBodies(skipped, null));
    // A flag outranks the way out, and `--verify-ownership` checks every function with every body.
    const flagged: Options = .{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .skip = true, .ownership = true, .testing = like } } };
    try std.testing.expect(checksOwnership(flagged) and checksIr(flagged) and !useDemandBodies(flagged, null));
    // A debug compiler validates every build with every body, `--release` included, unless `--no-validate` asks it not to.
    try std.testing.expectEqual(verify_ir.enabled, checksOwnership(.{ .zig = "zig", .mode = .release }));
    try std.testing.expect(!checksOwnership(.{ .zig = "zig", .mode = .release, .show = .{ .verify = .{ .skip = true } } }));
    try std.testing.expectEqual(!verify_ir.enabled, useDemandBodies(.{ .zig = "zig", .mode = .lean_debug }, null));
    // The way out reads the shared stage half and publishes nothing to it.
    try std.testing.expect(publishesShared(lean) and !publishesShared(skipped));
    var verify: Verify = .{};
    try std.testing.expect(verify.ask("--no-validate") and verify.ask("--validate-like-optimised"));
    try std.testing.expect(verify.skip and verify.testing.like_optimised);
}

test "N5 verifyWrittenCopies refuses a hidden copy in a build with no flag, names the way out, and --no-validate builds it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    var hand = try @import("test_support.zig").Hand.init(a, &module, "copy_list", .{ .params = try a.dupe(ir.Type, &.{list}), .ret = list });
    // An unmarked list copy: the hidden copy no source can spell.
    const copied = try hand.emit(.{ .op = .list_copy, .ty = list, .a = try hand.param(0), .span = 1 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = copied });
    _ = try hand.finish();
    const src = try language.source.Source.init(a, "copies.selka", "func copy_list(xs: int[]) -> int[]:\n    return xs\n");
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.InvalidIr, verifyWrittenCopies(a, &module, &src, .{ .zig = "zig", .mode = .lean_debug }, &.{}, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "E_CORE_HIDDEN_COPY") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "`--no-validate` builds without the default validators") != null);
    var quiet: std.ArrayList(u8) = .empty;
    try verifyWrittenCopies(a, &module, &src, .{ .zig = "zig", .mode = .lean_debug, .show = .{ .verify = .{ .skip = true } } }, &.{}, &quiet);
    try std.testing.expectEqualStrings("", quiet.items);
}

const fact_program =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(10))
    \\    return 0
    \\
;

/// State every interval the tables hold as the point 0, which no program's facts are.
fn falsify(known: []const ?facts.Facts) void {
    for (known) |slot| for (slot.?.ranges) |*range| {
        if (range.* != null) range.* = .point(0);
    };
}

test "the fact tables of a compiled program are validated and counted, and false ones are rejected by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build_ir.Refusal = .{};
    var module = try @import("test_support.zig").buildSource(a, fact_program, &refusal);
    const result = try @import("test_support.zig").runPasses(a, &module, .trusted);
    const asked: Options = .{ .zig = "zig", .show = .{ .verify = .{ .facts_static = true } } };
    const sound = try factWork(a, std.testing.allocator, &module, .{ .known = result.known, .fields = result.emission.fields }, asked);
    try std.testing.expect(sound.validated and sound.rejection == null);
    try std.testing.expect(sound.functions == 2 and sound.stats.proven > 0);
    falsify(result.known);
    const false_tables = try factWork(a, std.testing.allocator, &module, .{ .known = result.known, .fields = result.emission.fields }, asked);
    try std.testing.expect(std.mem.startsWith(u8, false_tables.rejection.?, "fact validation rejected "));
    const off: Options = .{ .zig = "zig", .facts = .off };
    const unasked = try factWork(a, std.testing.allocator, &module, .{ .known = result.known, .fields = result.emission.fields }, off);
    try std.testing.expect(!unasked.validated and unasked.text == null);
}

test "a fact rejection is an internal error, kept going past while the certificates are written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    var files: CertificateFiles = .{};
    const rejected: FactWork = .{ .validated = true, .rejection = "fact validation rejected f" };
    try std.testing.expectError(error.InvalidIr, reportFacts(a, .{ .zig = "zig" }, rejected, &files, &report));
    try std.testing.expectEqualStrings("error[E_FACT_VALIDATION]: fact validation rejected f\n" ++ way_out, report.items);
    try reportFacts(a, .{ .zig = "zig", .show = .{ .certificates = "out" } }, rejected, &files, &report);
    try std.testing.expectEqual(@as(u32, 1), files.problems);
    report.clearRetainingCapacity();
    try reportFacts(a, .{ .zig = "zig", .show = .{ .verify = .{ .facts_static = true } } }, .{ .validated = true, .functions = 2, .stats = .{ .proven = 3 } }, &files, &report);
    try std.testing.expectEqualStrings("selka: facts: 2 functions validated, 3 proven checks validated, 0 unchecked, 0 intervals assumed\n", report.items);
}

test "writing a build's certificates removes the stale ones and leaves every other file" {
    var directory = @import("stable_dir.zig").tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const io = std.testing.io;
    const root = try directory.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try directory.dir.writeFile(io, .{ .sub_path = "old.certificate", .data = "ownership-certificate-v2\n" });
    try directory.dir.writeFile(io, .{ .sub_path = "notes.txt", .data = "kept" });
    try directory.dir.writeFile(io, .{ .sub_path = "old.core-ir", .data = "core-ir-v1\n" });
    try writeCertificates(io, root, &.{.{ .name = "new", .text = "ownership-certificate-v2\n" }});
    try std.testing.expectError(error.FileNotFound, directory.dir.statFile(io, "old.certificate", .{}));
    try std.testing.expectError(error.FileNotFound, directory.dir.statFile(io, "old.core-ir", .{}));
    _ = try directory.dir.statFile(io, "new.certificate", .{});
    _ = try directory.dir.statFile(io, "notes.txt", .{});
    try std.testing.expect(certificateListed(&.{.{ .name = "new", .text = "" }}, "new.certificate"));
    try std.testing.expect(!certificateListed(&.{.{ .name = "new", .text = "" }}, "old.certificate"));
    try std.testing.expect(!certificateListed(&.{.{ .name = "new", .text = "" }}, "new.fact-certificate"));
    try std.testing.expect(certificateListed(&.{.{ .name = "program", .text = "", .kind = "fact-certificate" }}, "program.fact-certificate"));
}

// spec-case: SHARED-STORE-3
test "cache reports carry shared program mismatches and name them in text only when present" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var outcome: driver.Outcome = .{ .tool = .{ .path = "zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = false } };
    outcome.counts = .{ .units = 2, .reused = 2, .processes = 0 };
    var clean: std.ArrayList(u8) = .empty;
    try cacheReport(a, .text, outcome, null, null, &clean);
    try std.testing.expectEqualStrings("selka-core: cache: 2 units, 2 reused, 0 compiled, 0 verified; program linked; 0 processes\n", clean.items);
    outcome.counts.shared_mismatches = 1;
    var text: std.ArrayList(u8) = .empty;
    try cacheReport(a, .text, outcome, null, null, &text);
    try std.testing.expectEqualStrings("selka-core: cache: 2 units, 2 reused, 0 compiled, 0 verified; program linked; 0 processes; 1 shared mismatches\n", text.items);
    var json: std.ArrayList(u8) = .empty;
    try cacheReport(a, .json, outcome, null, null, &json);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, json.items, .{});
    try std.testing.expectEqual(@as(i64, 1), parsed.object.get("shared_mismatches").?.integer);
    try std.testing.expectEqualStrings("cache-report-v1", parsed.object.get("version").?.string);
    // The scopes a build's store counted appear under `storage` in the JSON only; the text line is unchanged.
    const counted: stage_metrics.Storage = .{ .flush_nanoseconds = 0, .flush_succeeded = true, .reads = .{}, .scopes = &.{.{ .scope = "final", .hits = 2, .misses = 1, .saves = 0 }} };
    var scoped: std.ArrayList(u8) = .empty;
    try cacheReport(a, .json, outcome, null, &counted, &scoped);
    const scoped_json = try std.json.parseFromSliceLeaky(std.json.Value, a, scoped.items, .{});
    const scope = scoped_json.object.get("storage").?.object.get("scopes").?.array.items[0];
    try std.testing.expectEqualStrings("final", scope.object.get("scope").?.string);
    try std.testing.expectEqual(@as(i64, 2), scope.object.get("hits").?.integer);
    var scoped_text: std.ArrayList(u8) = .empty;
    try cacheReport(a, .text, outcome, null, &counted, &scoped_text);
    try std.testing.expectEqualStrings(text.items, scoped_text.items);
}

test "cache text reports name each front-end miss reason that occurred" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var outcome: driver.Outcome = .{ .tool = .{ .path = "zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = false } };
    outcome.counts = .{ .units = 1, .reused = 1, .processes = 0 };
    var stages: stage_metrics.Report = .{};
    stages.frontend_misses.total[@backingInt(language.semantic_cache.MissReason.missing_record)] = 85;
    stages.frontend_misses.total[@backingInt(language.semantic_cache.MissReason.context_changed)] = 2;
    var text: std.ArrayList(u8) = .empty;
    try cacheReport(a, .text, outcome, &stages, null, &text);
    try std.testing.expectEqualStrings(
        "selka-core: front-end miss dependencies-changed: 2\n" ++
            "selka-core: front-end miss missing-record-identity: 85\n" ++
            "selka-core: cache: 1 units, 1 reused, 0 compiled, 0 verified; program linked; 0 processes\n",
        text.items,
    );
}

fn noRestore(_: *anyopaque, _: u32) @import("demand_ir.zig").Error!void {
    return error.CacheMiss;
}

test "an eager build keeps the receipts its units are keyed by, and serves no native handles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try @import("stage_store.zig").Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    const text = "func leaf() -> int:\n    return 1\n\nfunc main() -> int:\n    return leaf()\n";
    var refusal: @import("build.zig").Refusal = .{};
    var module = try @import("test_support.zig").buildSource(a, text, &refusal);
    const source = try language.source.Source.init(a, "main.selka", text);
    var context = optimization_cache.Context.init(&storage, try ir_snapshot.Context.init(a, &module, source), locator(&source));
    try context.prepare(a);
    // A lazy build has `lazy.raw` set and may serve native handles; an eager build (`force_eager`) has every body, so it keeps its
    // receipts for the next build but must not name stored artifacts as native handles, and restores nothing lazily.
    var demand: @import("demand_ir.zig").Context = .{ .keys = &.{}, .force_eager = true, .loaded = &.{}, .pointer = undefined, .ensure_fn = noRestore };
    context.lazy.raw = &demand;
    var restorer: FinalRestorer = .{ .arena = a, .backing = std.testing.allocator, .context = &context, .result = undefined };
    try std.testing.expect(restorer.receipts(&source) != null);
    try std.testing.expect(!restorer.nativeHandles(&source));
    try FinalRestorer.ensure(@ptrCast(&restorer), 0);
    demand.force_eager = false;
    try std.testing.expect(restorer.nativeHandles(&source));
}
