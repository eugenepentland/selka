//! The engine's shadow of the front end (part 2, G2a-G2f; spec `docs/design/incremental-engine.md` §17): the compiler's own
//! queries computed beside the front end that decides, and compared with it.
//!
//! A `Shadow` belongs to one front-end session. After the session has loaded the project and parsed every module, `observe`
//! hands the engine what the front end computed (the parts of each module's syntax, the graph of modules) through the
//! kinds' data, asks the engine for each query, and compares what the engine answers with what the front end computed:
//!
//! - an answer the engine **served** from a record that disagrees with what the front end just computed is a stale record,
//!   the one failure the shadow exists to find. It is logged as a finding, the record is forgotten, and the query is asked
//!   again so the store is healed;
//! - an answer the engine served where the front end's own cache missed (`ahead`) is counted: the engine keys on less, so a
//!   compiler edit outside a kind's closure keeps its records;
//! - an answer the engine recomputed is the front end's own answer by construction.
//!
//! The engine decides (G2g) unless `SELKA_ENGINE_DECIDE_COMPILER` is `0` or `off`: `beginDeciding` gives the front end's per-module
//! plan a decider that answers, module by module, from the engine's `module-check` record when it is valid, and `settleDecided`
//! records the keys the front end computed for the other modules once they are prepared. The kinds then compute from the front
//! end's parse and declaration graph on demand (`lazySyntax`, `lazyInterface`), so nothing is computed that a valid record serves.
//! With the decision off the front end computes every module's keys and keeps none.
//!
//! Nothing here changes what the compiler produces. The comparison of the other queries (the graph, the interfaces, the passes
//! and the program's diagnostics) is off unless `SELKA_ENGINE_SHADOW_COMPILER` is set (to anything but `0`, `off` or nothing):
//! computing them beside the front end costs time that ordinary builds do not pay. A session that overlays sources (the test
//! runner's providers, the stub `main` it appends to an entry) is observed like any other: the engine's world reads the overlaid
//! modules as the session does (`os_world.Overlay`), so a record over one is valid exactly while its overlaid bytes are.
const std = @import("std");
const language = @import("selka");
const engine = @import("engine/engine.zig");
const engine_digest = @import("engine/digest.zig");
const fast_blake3 = @import("fast_blake3.zig");
const engine_command = @import("engine/command.zig");
const engine_kinds = @import("engine/kinds.zig");
const context_rules = @import("engine/context.zig");
const os_world = @import("engine/os_world.zig");
const engine_sharing = @import("engine_sharing.zig");
const compiler_records = @import("engine/compiler_records.zig");
const record = @import("engine/record.zig");
const syntax_kind = @import("engine/kinds/module_syntax.zig");
const graph_kind = @import("engine/kinds/project_graph.zig");
const interface_kind = @import("engine/kinds/module_interface.zig");
const interface_facts = @import("module_interface_facts.zig");
const check_kind = @import("engine/kinds/module_check.zig");
const check_facts = @import("module_check_facts.zig");
const noalloc_kind = @import("engine/kinds/noalloc_closure.zig");
const noalloc_facts = @import("noalloc_closure_facts.zig");
const passes_kind = @import("engine/kinds/module_passes.zig");
const passes_facts = @import("module_passes_facts.zig");
const program_kind = @import("engine/kinds/program_diagnostics.zig");
const program_facts = @import("program_diagnostics_facts.zig");
const module_parts = @import("module_parts.zig");
const graph_answer = @import("project_graph_answer.zig");
const unit_kind = @import("engine/kinds/unit_lower.zig");
const lowering_shadow = @import("lowering_shadow.zig");
const lowering_cache = @import("lowering_cache.zig");
const facts_kind = @import("engine/kinds/program_facts.zig");
const facts_shadow = @import("program_facts_shadow.zig");
const optimize_kind = @import("engine/kinds/unit_optimize.zig");
const emit_kind = @import("engine/kinds/unit_emit.zig");
const emit_shadow = @import("emit_shadow.zig");
const emit_units = @import("emit_units.zig");
const optimize_shadow = @import("optimize_shadow.zig");
const optimizer_shadow = @import("optimizer_shadow.zig");

/// The variable that turns the compiler's shadow on. Placement: it checks results and never changes one.
pub const switch_variable = "SELKA_ENGINE_SHADOW_COMPILER";
/// The variable that switches the engine's decision off (G2g): by default the front end takes each module's prepared keys from the
/// engine's `module-check` records when they are valid; `0` or `off` makes it compute them all and keep none. Placement: the program
/// is the same either way.
pub const decide_variable = "SELKA_ENGINE_DECIDE_COMPILER";
/// The variable that switches the engine's passes decision off (G2k): by default a function whose summary cannot stand in whole but
/// whose module-local inputs are unchanged has its passes taken from the stored summary; `0` or `off` runs them all. Placement: the
/// diagnostics and the program are the same either way.
pub const passes_variable = "SELKA_ENGINE_DECIDE_PASSES";
/// The variable naming the file findings are appended to; unset, `<cache-dir>/engine-v1/shadow.jsonl` (the file the test
/// runner's shadow writes).
pub const log_variable = "SELKA_ENGINE_SHADOW_LOG";
/// The variable naming the run, carried on every line as `tag`.
pub const tag_variable = "SELKA_ENGINE_SHADOW_TAG";
/// The variable that samples served queries for verify mode, as for every engine.
pub const verify_variable = "SELKA_ENGINE_VERIFY";
/// A process writes at most this many finding lines; the rest are counted.
pub const line_limit = 4000;

/// What the shadow counts, per session.
pub const Tally = enum {
    /// Modules observed.
    modules,
    /// Module queries the engine served from a valid record.
    syntax_served,
    /// Module queries answered again within the session.
    syntax_memo,
    /// Module queries the engine computed.
    syntax_recomputed,
    /// Module queries the engine served where the front end's syntax cache missed.
    syntax_ahead,
    /// Graph queries served.
    graph_served,
    /// Graph queries computed.
    graph_recomputed,
    /// Graph queries answered again.
    graph_memo,
    /// Module interface queries served from a valid record.
    interface_served,
    /// Module interface queries answered again within the session.
    interface_memo,
    /// Module interface queries the engine computed.
    interface_recomputed,
    /// Module check queries served from a valid record.
    check_served,
    /// Module check queries answered again within the session.
    check_memo,
    /// Module check queries the engine computed.
    check_recomputed,
    /// `@noalloc` promise queries served from a valid record.
    noalloc_served,
    /// `@noalloc` promise queries answered again within the session.
    noalloc_memo,
    /// `@noalloc` promise queries the engine computed.
    noalloc_recomputed,
    /// `@noalloc` promises that are not recorded (one that is broken, or whose closure no declaration owns).
    noalloc_unrecorded,
    /// Module passes queries served from a valid record.
    passes_served,
    /// Module passes queries answered again within the session.
    passes_memo,
    /// Module passes queries the engine computed.
    passes_recomputed,
    /// Modules whose passes are not recorded (a promise of the module, or one the engine cannot place, is not recorded).
    passes_unrecorded,
    /// Program diagnostics queries served from a valid record.
    program_served,
    /// Program diagnostics queries answered again within the session.
    program_memo,
    /// Program diagnostics queries the engine computed.
    program_recomputed,
    /// Programs whose diagnostics are not recorded (a module's passes are not).
    program_unrecorded,
    /// Lowering units (modules and generic instances) observed.
    lower_units,
    /// Lowering queries the engine served from a valid record.
    lower_served,
    /// Lowering queries answered again within the session.
    lower_memo,
    /// Lowering queries the engine computed.
    lower_recomputed,
    /// Units the engine served where the old cache lowered at least one of their functions again.
    lower_ahead,
    /// Units the engine computed where the old cache restored every function.
    lower_behind,
    /// Functions in the units observed that the old cache restored.
    lower_restored,
    /// Functions in the units observed that the old cache lowered.
    lower_lowered,
    /// Functions in the units the engine computed: what a recompute of whole units costs against the functions that changed.
    lower_recomputed_functions,
    /// Lowerings not observed (a session with overlaid sources, or a program whose check was not observed).
    lower_skipped,
    /// Program facts queries the engine served from a valid record.
    facts_served,
    /// Program facts queries answered again within the session.
    facts_memo,
    /// Program facts queries the engine computed.
    facts_recomputed,
    /// Optimization units (the lowering units, by their optimized functions) observed.
    optimize_units,
    /// Optimization queries the engine served from a valid record.
    optimize_served,
    /// Optimization queries answered again within the session.
    optimize_memo,
    /// Optimization queries the engine computed.
    optimize_recomputed,
    /// Units the engine served where the optimizer analysed a function of the unit afresh.
    optimize_ahead,
    /// Units the engine computed where the optimizer restored or bypassed every function of the unit.
    optimize_behind,
    /// Functions of the units observed that the optimizer analysed afresh in this build, and those it restored or bypassed.
    optimize_fresh,
    optimize_kept,
    /// Functions of the units the engine computed: what recomputing whole units costs against the functions that changed.
    optimize_recomputed_functions,
    /// Functions the optimizer made final that no lowering unit claims.
    optimize_unowned,
    /// Units of the emitter (modules, instances, helpers and the entry) observed, and the engine's answers about them: served from a valid
    /// record, answered again within the session, or computed.
    emit_units,
    emit_served,
    emit_memo,
    emit_recomputed,
    /// Functions of an emitted unit that no optimizer unit claims.
    emit_unowned,
    /// Builds whose optimizer joined no facts to observe (the ownership-only passes), or whose lowering was not observed.
    facts_unobserved,
    /// Functions lowering built or restored that no artifact describes (one it could not store), so no unit holds them.
    lower_unobserved,
    /// Served answers that were not what the front end computed: stale records.
    findings,
    /// Modules whose prepared keys the front end took from a valid `module-check` record (the engine decides).
    decide_served,
    /// Modules whose prepared keys the front end computed, because no record was valid; their records are published after.
    decide_computed,
    /// Valid records withheld by the verify sampling: the front end computed them and they were compared.
    decide_withheld,
    /// Pass stand-ins withheld by the verify sampling: the passes ran for them and the result was compared with the summary.
    passes_verified,
    /// Records the engine could not use (a payload that does not describe the module's functions).
    decide_rejected,
    /// Queries the engine could not answer.
    errors,
    /// Microseconds spent observing.
    spent_us,
};

const tally_count = std.enums.values(Tally).len;

/// The kinds, as this session registers them (their data is this session's answers).
const Kinds = struct {
    syntax: context_rules.Kind,
    graph: context_rules.Kind,
    interface: context_rules.Kind,
    check: context_rules.Kind,
    noalloc: context_rules.Kind,
    passes: context_rules.Kind,
    program: context_rules.Kind,
    lower: context_rules.Kind,
    facts: context_rules.Kind,
    optimize: context_rules.Kind,
    emit: context_rules.Kind,
};

/// What the kinds read their answers from: the front end's, by argument.
const Maps = struct {
    syntax: std.StringHashMapUnmanaged(syntax_kind.Answer) = .empty,
    graph: std.StringHashMapUnmanaged(graph_kind.Answer) = .empty,
    interface: std.StringHashMapUnmanaged(interface_kind.Answer) = .empty,
    check: std.StringHashMapUnmanaged(check_kind.Answer) = .empty,
    noalloc: std.StringHashMapUnmanaged(noalloc_kind.Answer) = .empty,
    passes: std.StringHashMapUnmanaged(passes_kind.Answer) = .empty,
    program: std.StringHashMapUnmanaged(program_kind.Answer) = .empty,
    lower: std.StringHashMapUnmanaged(unit_kind.Answer) = .empty,
    facts: std.StringHashMapUnmanaged(facts_kind.Answer) = .empty,
    optimize: std.StringHashMapUnmanaged(optimize_kind.Answer) = .empty,
    emit: std.StringHashMapUnmanaged(emit_kind.Answer) = .empty,
};

/// What the session has described to the engine, and the arena it lives in.
const Answers = struct {
    arena: std.heap.ArenaAllocator,
    maps: Maps = .{},
    /// The units the lowering shadow described, for the optimizer's to be grouped by.
    units: []const lowering_shadow.Unit = &.{},
    /// The argument the program's facts were asked under, and the function key of the program's entry as the optimizer's facts
    /// name it: what a unit's optimization takes the facts' values and the entry from.
    facts: struct { argument: []const u8 = "", entry: []const u8 = "" } = .{},
    /// What was observed already: a session that checks a library entry with a `main` merges twice.
    done: struct { interfaces: bool = false, checks: bool = false } = .{},
    /// The loaded project and its index, for the lowering shadow to name and cut the modules (valid while the session is).
    loaded: ?struct { project: *const language.project.Project, index: *const language.interfaces.Index } = null,
    /// The declaration graph of the merged program, made once for the interfaces and the checks.
    surface: ?language.semantic_key.Surface = null,
    /// What the engine decides for the session's modules, when it decides (`decide_variable`).
    decision: Decision = .{},
};

/// How a module's prepared keys were decided.
const Fate = enum {
    /// The front end computes them; the engine records them after the check.
    computed,
    /// A valid `module-check` record gave them.
    served,
    /// A valid record exists but the verify sampling withheld it: the front end computes them and they are compared.
    withheld,
};

/// One module of the project as the decision sees it: its query, how it was decided, and the record a withheld one is compared with.
/// `name` is the module's name as checked names spell it, `parts` the parts of its `module-check` answer (served or computed; sorted
/// by name), which lowering keys its functions by, and `settled` whether the check has recorded the module.
const Slot = struct { argument: []const u8, fate: Fate = .computed, expected: ?check_kind.Answer = null, name: []const u8 = "", parts: []const record.Part = &.{}, settled: bool = false };

/// The engine's decision on a session's modules (G2g). Set up by `observe` (the loaded project) and `beginDeciding` (the merged
/// program); the kinds compute what they are asked from them, so nothing is computed that a valid record serves.
const Decision = struct {
    /// Whether the environment asked the engine to decide.
    enabled: bool = false,
    /// One valid record in this many is withheld from the front end and compared with what it computes (0: none).
    sample_every: u32 = 0,
    /// The text every check query ends with: the contracts its contexts are taken under.
    contract: []const u8 = "",
    loaded: ?Shadow.Loaded = null,
    over: ?Shadow.Merged = null,
    /// The module of each project-relative path.
    ids: std.StringHashMapUnmanaged(usize) = .empty,
    slots: []Slot = &.{},
};

/// The declaration graph of the merged program `program` over `src`, made once and kept in the session's arena.
fn surfaceOf(answers: *Answers, src: language.source.Source, program: language.ast.Program, index: *language.interfaces.Index) std.mem.Allocator.Error!*language.semantic_key.Surface {
    if (answers.surface == null) answers.surface = try language.semantic_key.Surface.initRecording(answers.arena.allocator(), src, program, index);
    return &answers.surface.?;
}

/// The data the kinds are registered with.
const Sources = struct {
    syntax: syntax_kind.Source,
    graph: graph_kind.Data,
    interface: interface_kind.Data,
    check: check_kind.Data,
    noalloc: noalloc_kind.Data,
    passes: passes_kind.Data,
    program: program_kind.Data,
    lower: unit_kind.Data,
    facts: facts_kind.Data,
    optimize: optimize_kind.Data,
    emit: emit_kind.Data,
};

/// The machine and the allocators the shadow runs on.
const Machine = struct { gpa: std.mem.Allocator, io: std.Io, os: os_world.OsWorld, records: ?compiler_records.Records = null };

/// Where findings go.
const Sink = struct {
    path: []const u8,
    tag: []const u8,
    work: []const u8,
    /// Whether the session ends with a summary line: only when someone asked to see the engine's work (the comparison, the verify
    /// sampling or a log of their own), so an ordinary build writes nothing.
    summary: bool,
    tallies: [tally_count]u64 = @splat(0),
};

/// Where a finding was made: the entry, the kind and what the query was about.
const Where = struct { entry: []const u8, kind: []const u8, subject: []const u8 };

/// One side of a finding: the parts and the payload of a record.
const Side = struct { parts: []const record.Part, payload: []const u8 };

/// ` (served: LINE; computed: LINE)` for the first payload line on which two payloads differ, so a finding says what moved and
/// not only which part did.
fn payloadHint(a: std.mem.Allocator, served: []const u8, computed: []const u8) std.mem.Allocator.Error![]const u8 {
    var left = std.mem.splitScalar(u8, served, '\n');
    var right = std.mem.splitScalar(u8, computed, '\n');
    while (true) {
        const was = left.next();
        const is = right.next();
        if (was == null and is == null) return "";
        const first = was orelse "(absent)";
        const second = is orelse "(absent)";
        if (!std.mem.eql(u8, first, second)) return std.fmt.allocPrint(a, " (served: {s}; computed: {s})", .{ first[0..@min(first.len, 300)], second[0..@min(second.len, 300)] });
    }
}

/// The shadow of one session. Heap-allocated: the engine points into it and must not move.
pub const Shadow = struct {
    machine: Machine,
    runner: engine.Engine,
    kinds: Kinds,
    sources: Sources,
    answers: Answers,
    sink: Sink,
    strings: std.heap.ArenaAllocator,

    /// What an observation is told about the session that loaded the project.
    pub const Loaded = struct {
        project: *const language.project.Project,
        index: *const language.interfaces.Index,
        entry: []const u8,
        options: language.project.Options,
    };

    /// What an observation of the interfaces is told: the project, its index, and the merged program built over them.
    pub const Merged = struct {
        index: *language.interfaces.Index,
        src: language.source.Source,
        syntax: language.ast.Program,
        entry: []const u8,
    };

    /// Count one `which`.
    pub fn count(self: *Shadow, which: Tally) void {
        self.sink.tallies[@backingInt(which)] += 1;
    }

    /// How many `which` the session counted.
    pub fn tally(self: *const Shadow, which: Tally) u64 {
        return self.sink.tallies[@backingInt(which)];
    }

    /// Observe a loaded project: ask the engine for every module's syntax and for the project's graph, and compare each answer
    /// with the front end's. A failure of the engine to answer is counted and the observation goes on; nothing is ever raised.
    pub fn observe(self: *Shadow, loaded: Loaded) void {
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        _ = self.answers.arena.reset(.retain_capacity);
        self.answers.maps.syntax = .empty;
        self.answers.maps.graph = .empty;
        self.answers.maps.interface = .empty;
        self.answers.maps.check = .empty;
        self.answers.maps.noalloc = .empty;
        self.answers.maps.passes = .empty;
        self.answers.maps.program = .empty;
        self.answers.maps.lower = .empty;
        self.answers.maps.facts = .empty;
        self.answers.maps.optimize = .empty;
        self.answers.maps.emit = .empty;
        self.answers.units = &.{};
        self.answers.facts = .{};
        self.answers.loaded = .{ .project = loaded.project, .index = loaded.index };
        self.answers.surface = null;
        const decision = &self.answers.decision;
        decision.* = .{ .enabled = decision.enabled, .sample_every = decision.sample_every };
        if (decision.enabled) {
            // The engine decides: nothing is computed until a query needs it.
            decision.loaded = loaded;
            return;
        }
        const a = self.answers.arena.allocator();
        for (loaded.project.modules.items, 0..) |module, id| {
            const parts = module_parts.compute(a, module, loaded.index.units[id].syntax) catch return self.count(.errors);
            self.answers.maps.syntax.put(a, module.src.path, .{ .source_digest = parts.source_digest, .payload = parts.payload, .parts = parts.parts }) catch return self.count(.errors);
        }
        for (loaded.project.modules.items, 0..) |module, id| {
            self.count(.modules);
            self.compareSyntax(module.src.path, loaded.index.units[id].replayed, loaded.entry);
        }
        self.observeGraph(loaded);
    }

    /// Observe the interfaces of a loaded project, after the merged program is built: ask the engine for every module's
    /// interface and compare each answer with the front end's. Call after `observe`, which describes the modules' syntax.
    pub fn observeInterfaces(self: *Shadow, merged: Merged) void {
        if (self.answers.done.interfaces or self.answers.decision.enabled) return;
        self.answers.done.interfaces = true;
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        const a = self.answers.arena.allocator();
        const surface = surfaceOf(&self.answers, merged.src, merged.syntax, merged.index) catch return self.count(.errors);
        const computed = interface_facts.compute(a, surface, merged.index) catch return self.count(.errors);
        for (computed) |module| self.answers.maps.interface.put(a, module.path, module.answer) catch return self.count(.errors);
        for (computed) |module| self.compareInterface(module.path, module.answer, merged.entry);
    }

    /// What an observation of the checks is told: the merged program a successful check checked and what the front end prepared
    /// for it.
    pub const Checked = struct {
        index: *language.interfaces.Index,
        src: language.source.Source,
        syntax: language.ast.Program,
        prepared: language.semantic_key.Prepared,
        outputs: Outputs,
        entry: []const u8,
        /// The contracts the front end prepared the contexts under.
        contracts: language.semantic_key.Contracts,
    };

    /// What the check produced besides its bodies: its summaries (when it published any), its diagnostics in the front end's
    /// order, and what they are rendered under.
    pub const Outputs = struct {
        produced: ?language.semantic_summary.Table = null,
        diagnostics: []const language.diagnostic.Diagnostic = &.{},
        rendering: program_facts.Settings,
        /// The checked program, whose `@noalloc` promises are judged over Core.
        program: ?language.typed.Program = null,
    };

    /// Observe the checks of a project whose bodies the front end has just checked: ask the engine for every module's check
    /// and compare each answer with the keys the front end prepared. Call after `observeInterfaces`.
    pub fn observeChecks(self: *Shadow, checked: Checked) void {
        if (self.answers.done.checks or self.answers.decision.enabled) return;
        self.answers.done.checks = true;
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        const a = self.answers.arena.allocator();
        const surface = surfaceOf(&self.answers, checked.src, checked.syntax, checked.index) catch return self.count(.errors);
        const flags = check_facts.flagsOf(a, checked.index.project, checked.contracts) catch return self.count(.errors);
        const computed = check_facts.compute(a, surface, checked.syntax, checked.index, checked.prepared, flags) catch return self.count(.errors);
        for (computed) |module| self.answers.maps.check.put(a, module.argument, module.answer) catch return self.count(.errors);
        for (computed) |module| self.compareCheck(module.argument, module.answer, checked.entry);
        const produced = checked.outputs.produced orelse return;
        const program = checked.outputs.program orelse return;
        const roots = noalloc_facts.compute(a, .{ .program = program, .src = checked.src, .syntax = checked.syntax, .surface = surface, .index = checked.index, .regions = checked.prepared.regions }, flags) catch return self.count(.errors);
        for (roots) |root| if (root.answer) |answer| self.answers.maps.noalloc.put(a, root.argument, answer) catch return self.count(.errors);
        for (roots) |root| self.compareNoalloc(root.argument, root.answer, checked.entry);
        const passes = passes_facts.compute(a, checked.index, .{ .produced = produced, .items = checked.outputs.diagnostics, .flags = flags, .roots = roots, .src = checked.src }) catch return self.count(.errors);
        for (passes) |module| if (module.answer) |answer| self.answers.maps.passes.put(a, module.argument, answer) catch return self.count(.errors);
        for (passes) |module| self.comparePasses(module.argument, module.answer, checked.entry);
        const rendered = program_facts.render(a, checked.src, checked.outputs.diagnostics, checked.outputs.rendering.format) catch return self.count(.errors);
        const assembled = program_facts.compute(a, rendered, passes, roots) catch return self.count(.errors);
        const argument = program_facts.argumentOf(a, checked.entry, checked.outputs.rendering.options) catch return self.count(.errors);
        const wanted = assembled orelse return self.count(.program_unrecorded);
        self.answers.maps.program.put(a, argument, wanted) catch return self.count(.errors);
        self.compareProgram(argument, wanted, checked.entry);
    }

    /// What a build knows of its lowering once it is done: the checked program and its merged source, the functions lowered or
    /// restored with their artifacts, and whether debug information is dropped.
    pub const Lowered = struct {
        program: language.typed.Program,
        src: language.source.Source,
        observed: []const lowering_cache.Observed.Entry,
        drop_debug: bool,
        entry: []const u8,
        /// The functions the build lowered or restored in all, to tell the ones no artifact describes.
        built: usize = 0,
    };

    /// Observe the lowering of a program whose check was observed: group what lowering did into units, ask the engine for each
    /// and compare. Call after `observeChecks`; a lowering whose check was not observed is counted and left alone.
    pub fn observeLowering(self: *Shadow, lowered: Lowered) void {
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        self.sink.tallies[@backingInt(Tally.lower_unobserved)] += lowered.built -| lowered.observed.len;
        const loaded = self.answers.loaded orelse return self.count(.lower_skipped);
        if (!self.answers.done.checks) return self.count(.lower_skipped);
        const a = self.answers.arena.allocator();
        const modules = a.alloc(lowering_shadow.Module, loaded.project.modules.items.len) catch return self.count(.errors);
        for (loaded.project.modules.items, modules, 0..) |module, *slot, id| {
            var check: []const u8 = "";
            var arguments = self.answers.maps.check.keyIterator();
            while (arguments.next()) |argument| {
                if (std.mem.eql(u8, check_kind.pathOf(argument.*), module.src.path)) check = argument.*;
            }
            const regions = module_parts.regionsOf(a, module, loaded.index.units[id].syntax) catch return self.count(.errors);
            slot.* = .{ .name = module.name, .path = module.src.path, .key_path = module.src.keyPath(), .check = check, .regions = regions };
        }
        const units = lowering_shadow.compute(a, .{ .program = lowered.program, .src = lowered.src, .modules = modules, .observed = lowered.observed, .drop_debug = lowered.drop_debug }) catch return self.count(.errors);
        self.answers.units = units;
        for (units) |unit| self.answers.maps.lower.put(a, unit.argument, unit.answer) catch return self.count(.errors);
        for (units) |unit| self.compareLower(unit, lowered.entry);
    }

    /// What the build knows once the optimizer has joined its facts: what it joined, the settings the facts depend on, the entry.
    pub const Joined = struct {
        observed: *const facts_shadow.Observed,
        mode: []const u8,
        facts_on: bool,
        entry: []const u8,
    };

    /// Observe the facts the optimizer joined: ask the engine for the program's facts, which read the lowered result of every unit
    /// the lowering shadow described, and compare. Call after `observeLowering` and the optimizer.
    pub fn observeFacts(self: *Shadow, joined: Joined) void {
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        if (!joined.observed.collected or self.answers.maps.lower.count() == 0) return self.count(.facts_unobserved);
        const a = self.answers.arena.allocator();
        var units: std.ArrayList([]const u8) = .empty;
        var arguments = self.answers.maps.lower.keyIterator();
        while (arguments.next()) |argument| units.append(a, argument.*) catch return self.count(.errors);
        std.mem.sort([]const u8, units.items, {}, bytesLess);
        var unit_hash = fast_blake3.Blake3.init(.{});
        for (units.items) |unit| {
            unit_hash.update(unit);
            unit_hash.update("\x00");
        }
        var units_digest: [32]u8 = undefined;
        unit_hash.final(&units_digest);
        const argument = facts_kind.argumentOf(a, joined.entry, joined.mode, joined.facts_on, units_digest) catch return self.count(.errors);
        const expected = facts_shadow.answer(a, joined.observed, units.items) catch return self.count(.errors);
        self.answers.facts.argument = argument;
        self.answers.facts.entry = a.dupe(u8, joined.observed.entry) catch return self.count(.errors);
        self.answers.maps.facts.put(a, argument, expected) catch return self.count(.errors);
        const answered = self.runner.answer(&self.kinds.facts, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.facts_memo),
            .recomputed => return self.count(.facts_recomputed),
            .served => self.count(.facts_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = joined.entry, .kind = "program-facts", .subject = joined.entry }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.facts, argument);
        _ = self.runner.answer(&self.kinds.facts, argument) catch self.count(.errors);
    }

    /// What the build knows once the optimizer has made every function final: what it made, with the settings and the program-facts
    /// argument the units' records read.
    pub const Optimized = struct {
        observed: *const optimizer_shadow.Observed,
        mode: []const u8,
        entry: []const u8,
    };

    /// Observe what the optimizer made of each unit: ask the engine for every unit's optimized functions, which read the lowered
    /// results of the units inlined into it and the program's facts, and compare. Call after `observeFacts`.
    pub fn observeOptimized(self: *Shadow, made: Optimized) void {
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        if (!made.observed.collected or self.answers.units.len == 0 or self.answers.facts.argument.len == 0) return self.count(.facts_unobserved);
        const a = self.answers.arena.allocator();
        const held = self.answers.maps.facts.get(self.answers.facts.argument) orelse return self.count(.facts_unobserved);
        const grouped = optimize_shadow.compute(a, made.observed, self.answers.units, .{ .mode = made.mode, .entry = self.answers.facts.entry, .facts = held.parts }) catch return self.count(.errors);
        self.sink.tallies[@backingInt(Tally.optimize_unowned)] += grouped.unowned;
        for (grouped.units) |unit| self.answers.maps.optimize.put(a, unit.argument, unit.answer) catch return self.count(.errors);
        for (grouped.units) |unit| self.compareOptimized(unit, made.entry);
    }

    fn compareOptimized(self: *Shadow, unit: optimize_shadow.Unit, entry: []const u8) void {
        self.count(.optimize_units);
        self.sink.tallies[@backingInt(Tally.optimize_fresh)] += unit.fresh;
        self.sink.tallies[@backingInt(Tally.optimize_kept)] += unit.kept;
        const answered = self.runner.answer(&self.kinds.optimize, unit.argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.optimize_memo),
            .recomputed => {
                self.count(.optimize_recomputed);
                self.sink.tallies[@backingInt(Tally.optimize_recomputed_functions)] += unit.fresh + unit.kept;
                if (unit.fresh == 0) self.count(.optimize_behind);
                return;
            },
            .served => {
                self.count(.optimize_served);
                if (unit.fresh != 0) self.count(.optimize_ahead);
            },
        }
        const expected = unit.answer;
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "unit-optimize", .subject = unit.argument }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.optimize, unit.argument);
        _ = self.runner.answer(&self.kinds.optimize, unit.argument) catch self.count(.errors);
    }

    /// What the build knows once the emitter has made every unit: the units, with the module whose functions they hold and the settings
    /// the optimizer's units were asked under.
    pub const Emitted = struct {
        units: []const emit_units.Unit,
        module: *const @import("ir.zig").Module,
        mode: []const u8,
        entry: []const u8,
    };

    /// Observe what the emitter made of each unit: ask the engine for every unit's text, which reads the optimized functions it holds,
    /// and compare. Call after `observeOptimized`.
    pub fn observeEmitted(self: *Shadow, made: Emitted) void {
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        if (self.answers.maps.optimize.count() == 0) return self.count(.facts_unobserved);
        const a = self.answers.arena.allocator();
        const keys = facts_shadow.keysOf(a, made.module) catch return self.count(.errors);
        var owner: std.StringHashMapUnmanaged([]const u8) = .empty;
        var held = self.answers.maps.optimize.iterator();
        while (held.next()) |unit| for (unit.value_ptr.parts) |part| {
            if (!std.mem.startsWith(u8, part.name, optimize_shadow.function_prefix)) continue;
            owner.put(a, part.name[optimize_shadow.function_prefix.len..], unit.key_ptr.*) catch return self.count(.errors);
        };
        const described = emit_shadow.compute(a, made.units, keys, &owner, made.mode) catch return self.count(.errors);
        self.sink.tallies[@backingInt(Tally.emit_unowned)] += described.unowned;
        for (described.units) |unit| self.answers.maps.emit.put(a, unit.argument, unit.answer) catch return self.count(.errors);
        for (described.units) |unit| self.compareEmitted(unit, made.entry);
    }

    fn compareEmitted(self: *Shadow, unit: emit_shadow.Unit, entry: []const u8) void {
        self.count(.emit_units);
        const answered = self.runner.answer(&self.kinds.emit, unit.argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.emit_memo),
            .recomputed => return self.count(.emit_recomputed),
            .served => self.count(.emit_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, unit.answer.payload)) return;
        self.finding(.{ .entry = entry, .kind = "unit-emit", .subject = unit.argument }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = &.{}, .payload = unit.answer.payload });
        self.runner.forget(&self.kinds.emit, unit.argument);
        _ = self.runner.answer(&self.kinds.emit, unit.argument) catch self.count(.errors);
    }

    fn compareLower(self: *Shadow, unit: lowering_shadow.Unit, entry: []const u8) void {
        self.count(.lower_units);
        self.sink.tallies[@backingInt(Tally.lower_restored)] += unit.restored;
        self.sink.tallies[@backingInt(Tally.lower_lowered)] += unit.lowered;
        const answered = self.runner.answer(&self.kinds.lower, unit.argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.lower_memo),
            .recomputed => {
                self.count(.lower_recomputed);
                self.sink.tallies[@backingInt(Tally.lower_recomputed_functions)] += unit.restored + unit.lowered;
                if (unit.lowered == 0) self.count(.lower_behind);
                return;
            },
            .served => {
                self.count(.lower_served);
                if (unit.lowered != 0) self.count(.lower_ahead);
            },
        }
        const expected = unit.answer;
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "unit-lower", .subject = unit.argument }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.lower, unit.argument);
        _ = self.runner.answer(&self.kinds.lower, unit.argument) catch self.count(.errors);
    }

    /// What `beginDeciding` is told: the merged program the checks run over, and the contracts its contexts are taken under.
    pub const Deciding = struct { merged: Merged, contracts: language.semantic_key.Contracts };

    /// What `settleDecided` is told: the merged program and what the front end prepared for it.
    pub const Settled = struct { merged: Merged, prepared: language.semantic_key.Prepared, contracts: language.semantic_key.Contracts };

    /// Whether this shadow compares the engine's answers with what the compiler computes (the comparison switch is on and the engine
    /// does not decide the session's keys). The stages after the front end note what they do for it only then.
    pub fn comparing(self: *const Shadow) bool {
        return !self.answers.decision.enabled;
    }

    /// The checked-body parts lowering keys its functions by (G3g), when the engine decides this session's modules: null otherwise.
    pub fn partSource(self: *Shadow) ?lowering_cache.PartSource {
        if (!self.answers.decision.enabled) return null;
        return .{ .context = self, .digest = bodyDigestOf };
    }

    /// Whether the engine decides this session's prepared keys (`decide_variable`).
    pub fn deciding(self: *const Shadow) bool {
        return self.answers.decision.enabled;
    }

    /// Let the engine decide which modules' prepared keys hold, once the merged program is built: the decider the front end
    /// asks while it opens its per-module plan. Null when the decision is off or the project was not loaded under this shadow, so the
    /// front end computes every module's keys.
    pub fn beginDeciding(self: *Shadow, request: Deciding) ?language.module_records.Decider {
        const decision = &self.answers.decision;
        if (!decision.enabled) return null;
        const loaded = decision.loaded orelse return null;
        const a = self.answers.arena.allocator();
        const modules = loaded.project.modules.items;
        const flags = check_facts.flagsOf(a, loaded.project, request.contracts) catch return self.fault();
        const slots = a.alloc(Slot, modules.len) catch return self.fault();
        decision.ids = .empty;
        for (modules, slots, 0..) |module, *slot, id| {
            slot.* = .{ .argument = check_facts.moduleArgument(a, loaded.index, id, flags) catch return self.fault(), .name = a.dupe(u8, module.name) catch return self.fault() };
            decision.ids.put(a, module.src.path, id) catch return self.fault();
        }
        decision.slots = slots;
        decision.over = request.merged;
        self.sink.tallies[@backingInt(Tally.modules)] += modules.len;
        return .{ .context = self, .restore = deciderRestore, .reject = deciderReject };
    }

    fn fault(self: *Shadow) ?language.module_records.Decider {
        self.count(.errors);
        return null;
    }

    /// The parts of module `path`'s syntax, computed from the parse the front end holds when the engine asks for them: only when
    /// the engine decides, and only for a module whose record is not valid.
    fn lazySyntax(self: *Shadow, path: []const u8) ?syntax_kind.Answer {
        const decision = &self.answers.decision;
        const loaded = decision.loaded orelse return null;
        const id = decision.ids.get(path) orelse return null;
        const a = self.answers.arena.allocator();
        const parts = module_parts.compute(a, loaded.project.modules.items[id], loaded.index.units[id].syntax) catch return null;
        const answer: syntax_kind.Answer = .{ .source_digest = parts.source_digest, .payload = parts.payload, .parts = parts.parts };
        putOwned(&self.answers.maps.syntax, a, path, answer) catch return null;
        return answer;
    }

    /// The interface of module `path`, computed over the merged program's declaration graph when the engine asks for it.
    fn lazyInterface(self: *Shadow, path: []const u8) ?interface_kind.Answer {
        const decision = &self.answers.decision;
        const over = decision.over orelse return null;
        const id = decision.ids.get(path) orelse return null;
        const a = self.answers.arena.allocator();
        const surface = surfaceOf(&self.answers, over.src, over.syntax, over.index) catch return null;
        const answer = interface_facts.interfaceOf(a, surface, over.index, id) catch return null;
        putOwned(&self.answers.maps.interface, a, path, answer) catch return null;
        return answer;
    }

    fn errored(self: *Shadow) ?[]u8 {
        self.count(.errors);
        return null;
    }

    /// A valid record whose payload cannot be read (its object is gone or damaged): the record goes, so the module's answer is computed
    /// and recorded afresh instead of failing the same way in every session that decides.
    fn unreadable(self: *Shadow, slot: *const Slot) ?[]u8 {
        self.runner.forget(&self.kinds.check, slot.argument);
        return self.errored();
    }

    /// Record, after the check, the `module-check` answer of every module the front end computed the keys of (a module whose
    /// record was valid is already recorded), and compare the ones the sampling withheld with the valid record they stood against.
    /// Call it once the keys are prepared, whether the bodies then checked or not.
    pub fn settleDecided(self: *Shadow, settled: Settled) void {
        const decision = &self.answers.decision;
        if (!decision.enabled or decision.slots.len == 0 or decision.slots[0].settled) return;
        const slots = decision.slots;
        const began = std.Io.Timestamp.now(self.machine.io, .awake);
        defer self.spend(began);
        const merged = settled.merged;
        const a = self.answers.arena.allocator();
        const surface = surfaceOf(&self.answers, merged.src, merged.syntax, merged.index) catch return self.count(.errors);
        for (slots, 0..) |*slot, id| {
            slot.settled = true;
            if (slot.fate == .served) {
                self.count(.decide_served);
                continue;
            }
            // A module the engine computes is recorded from the names `prepare` recorded; one it compares against the record it stood against
            // is walked, so the comparison still tests a record written that way.
            const answer = check_facts.checkOf(a, surface, merged.syntax, merged.index, settled.prepared, .{ .module = id, .recalled = slot.fate == .computed }) catch return self.count(.errors);
            slot.parts = answer.parts;
            switch (slot.fate) {
                .computed => self.publishCheck(slot.argument, answer),
                .withheld => self.compareWithheld(slot.*, answer, merged.entry),
                .served => unreachable,
            }
        }
    }

    fn publishCheck(self: *Shadow, argument: []const u8, answer: check_kind.Answer) void {
        const a = self.answers.arena.allocator();
        self.answers.maps.check.put(a, argument, answer) catch return self.count(.errors);
        _ = self.runner.answer(&self.kinds.check, argument) catch return self.count(.errors);
        self.count(.decide_computed);
    }

    fn compareWithheld(self: *Shadow, slot: Slot, computed: check_kind.Answer, entry: []const u8) void {
        self.count(.decide_withheld);
        const expected = slot.expected orelse return;
        if (std.mem.eql(u8, expected.payload, computed.payload) and sameParts(expected.parts, computed.parts)) return;
        self.finding(.{ .entry = entry, .kind = "module-check", .subject = check_kind.pathOf(slot.argument) }, .{ .parts = expected.parts, .payload = expected.payload }, .{ .parts = computed.parts, .payload = computed.payload });
        self.runner.forget(&self.kinds.check, slot.argument);
        self.publishCheck(slot.argument, computed);
    }

    fn compareProgram(self: *Shadow, argument: []const u8, expected: program_kind.Answer, entry: []const u8) void {
        const answered = self.runner.answer(&self.kinds.program, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.program_memo),
            .recomputed => return self.count(.program_recomputed),
            .served => self.count(.program_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "program-diagnostics", .subject = entry }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.program, argument);
        _ = self.runner.answer(&self.kinds.program, argument) catch self.count(.errors);
    }

    fn compareNoalloc(self: *Shadow, argument: []const u8, expected: ?noalloc_kind.Answer, entry: []const u8) void {
        const wanted = expected orelse return self.count(.noalloc_unrecorded);
        const answered = self.runner.answer(&self.kinds.noalloc, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.noalloc_memo),
            .recomputed => return self.count(.noalloc_recomputed),
            .served => self.count(.noalloc_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, wanted.payload) and sameParts(answered.result.parts, wanted.parts)) return;
        const subject = argument[0..std.mem.indexOfScalar(u8, argument, 0).?];
        self.finding(.{ .entry = entry, .kind = "noalloc-closure", .subject = subject }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = wanted.parts, .payload = wanted.payload });
        self.runner.forget(&self.kinds.noalloc, argument);
        _ = self.runner.answer(&self.kinds.noalloc, argument) catch self.count(.errors);
    }

    fn comparePasses(self: *Shadow, argument: []const u8, expected: ?passes_kind.Answer, entry: []const u8) void {
        const wanted = expected orelse return self.count(.passes_unrecorded);
        const answered = self.runner.answer(&self.kinds.passes, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.passes_memo),
            .recomputed => return self.count(.passes_recomputed),
            .served => self.count(.passes_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, wanted.payload) and sameParts(answered.result.parts, wanted.parts)) return;
        self.finding(.{ .entry = entry, .kind = "module-passes", .subject = check_kind.pathOf(argument) }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = wanted.parts, .payload = wanted.payload });
        self.runner.forget(&self.kinds.passes, argument);
        _ = self.runner.answer(&self.kinds.passes, argument) catch self.count(.errors);
    }

    fn compareCheck(self: *Shadow, argument: []const u8, expected: check_kind.Answer, entry: []const u8) void {
        const answered = self.runner.answer(&self.kinds.check, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.check_memo),
            .recomputed => return self.count(.check_recomputed),
            .served => self.count(.check_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "module-check", .subject = check_kind.pathOf(argument) }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.check, argument);
        _ = self.runner.answer(&self.kinds.check, argument) catch self.count(.errors);
    }

    fn compareInterface(self: *Shadow, path: []const u8, expected: interface_kind.Answer, entry: []const u8) void {
        const answered = self.runner.answer(&self.kinds.interface, path) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.interface_memo),
            .recomputed => return self.count(.interface_recomputed),
            .served => self.count(.interface_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "module-interface", .subject = path }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.interface, path);
        _ = self.runner.answer(&self.kinds.interface, path) catch self.count(.errors);
    }

    fn compareSyntax(self: *Shadow, path: []const u8, old_replayed: bool, entry: []const u8) void {
        const expected = self.answers.maps.syntax.get(path).?;
        const answered = self.runner.answer(&self.kinds.syntax, path) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => self.count(.syntax_memo),
            .recomputed => self.count(.syntax_recomputed),
            .served => {
                self.count(.syntax_served);
                if (!old_replayed) self.count(.syntax_ahead);
            },
        }
        if (answered.origin != .served) return;
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = entry, .kind = "module-syntax", .subject = path }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.syntax, path);
        _ = self.runner.answer(&self.kinds.syntax, path) catch self.count(.errors);
    }

    fn observeGraph(self: *Shadow, loaded: Loaded) void {
        const a = self.answers.arena.allocator();
        const argument = graph_answer.argumentOf(a, loaded.entry, loaded.options) catch return self.count(.errors);
        const expected = graph_answer.build(a, loaded.project, loaded.entry) catch return self.count(.errors);
        self.answers.maps.graph.put(a, argument, expected) catch return self.count(.errors);
        const answered = self.runner.answer(&self.kinds.graph, argument) catch return self.count(.errors);
        switch (answered.origin) {
            .memo => return self.count(.graph_memo),
            .recomputed => return self.count(.graph_recomputed),
            .served => self.count(.graph_served),
        }
        const served = answered.result.payload() catch return self.count(.errors);
        if (std.mem.eql(u8, served, expected.payload) and sameParts(answered.result.parts, expected.parts)) return;
        self.finding(.{ .entry = loaded.entry, .kind = "project-graph", .subject = loaded.entry }, .{ .parts = answered.result.parts, .payload = served }, .{ .parts = expected.parts, .payload = expected.payload });
        self.runner.forget(&self.kinds.graph, argument);
        _ = self.runner.answer(&self.kinds.graph, argument) catch self.count(.errors);
    }

    fn spend(self: *Shadow, began: std.Io.Timestamp) void {
        const spent = began.durationTo(std.Io.Timestamp.now(self.machine.io, .awake));
        self.sink.tallies[@backingInt(Tally.spent_us)] += @intCast(@max(0, @divTrunc(spent.nanoseconds, std.time.ns_per_us)));
    }

    /// Count what the verify sampling of the pass stand-in compared, and log a finding when a withheld stand-in differs from the passes.
    pub fn notePassesVerified(self: *Shadow, compared: u32, mismatched: u32, first: []const u8, entry: []const u8) void {
        self.sink.tallies[@backingInt(Tally.passes_verified)] += compared;
        if (mismatched == 0) return;
        var scratch: std.heap.ArenaAllocator = .init(self.machine.gpa);
        defer scratch.deinit();
        const detail = std.fmt.allocPrint(scratch.allocator(), "{d} of {d} sampled stand-ins differ from what they would have replaced; the first is {s}", .{ mismatched, compared, first }) catch return;
        self.count(.findings);
        const line: Line = .{ .class = "compiler", .kind = "pass-stand-in", .entry = entry, .detail = detail, .tag = if (self.sink.tag.len != 0) self.sink.tag else null };
        const text = std.json.Stringify.valueAlloc(scratch.allocator(), line, .{ .emit_null_optional_fields = false }) catch return;
        write(self, scratch.allocator(), text);
    }

    /// Log a stale record: the kind, the subject, the first part that differs and the first payload line that does.
    fn finding(self: *Shadow, where: Where, served: Side, computed: Side) void {
        self.count(.findings);
        var scratch: std.heap.ArenaAllocator = .init(self.machine.gpa);
        defer scratch.deinit();
        const a = scratch.allocator();
        const wrong = "the engine served a record that is not what the front end computed; first differing part";
        const lines = payloadHint(a, served.payload, computed.payload) catch "";
        const detail = std.fmt.allocPrint(a, "{s} {s}: {s}: {s}{s}", .{ where.kind, where.subject, wrong, firstDifference(served.parts, computed.parts), lines }) catch return;
        const tag: ?[]const u8 = if (self.sink.tag.len != 0) self.sink.tag else null;
        const line: Line = .{ .class = "compiler", .kind = where.kind, .entry = where.entry, .detail = detail, .tag = tag };
        const text = std.json.Stringify.valueAlloc(a, line, .{ .emit_null_optional_fields = false }) catch return;
        write(self, a, text);
    }

    /// End the session's shadow: write its summary line and free it.
    pub fn end(self: *Shadow) void {
        self.summarize();
        const gpa = self.machine.gpa;
        self.runner.deinit();
        if (self.machine.records) |*records| records.deinit();
        self.answers.arena.deinit();
        self.strings.deinit();
        gpa.destroy(self);
    }

    /// Per kind the shadow asks for after the front end, how many of its recomputations ended in the digest they had, so the
    /// queries that read them stayed valid (`<kind>_cutoffs`).
    fn cutoffs(self: *Shadow, a: std.mem.Allocator, text: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        const asked = [_]struct { name: []const u8, kind: *const context_rules.Kind }{
            .{ .name = "lower", .kind = &self.kinds.lower },
            .{ .name = "facts", .kind = &self.kinds.facts },
            .{ .name = "optimize", .kind = &self.kinds.optimize },
            .{ .name = "emit", .kind = &self.kinds.emit },
        };
        for (asked) |one| {
            const numbers = self.runner.snapshot(one.kind) orelse continue;
            try text.print(a, ",\"{s}_cutoffs\":{d}", .{ one.name, numbers.count(.early_cutoffs) });
        }
    }

    fn summarize(self: *Shadow) void {
        if (!self.sink.summary or self.tally(.modules) == 0) return;
        var scratch: std.heap.ArenaAllocator = .init(self.machine.gpa);
        defer scratch.deinit();
        const a = scratch.allocator();
        var text: std.ArrayList(u8) = .empty;
        text.print(a, "{{\"v\":1,\"class\":\"compiler-summary\",\"pid\":{d},\"work\":{f}", .{ std.os.linux.getpid(), std.json.fmt(self.sink.work, .{}) }) catch return;
        for (std.enums.values(Tally)) |which| text.print(a, ",\"{s}\":{d}", .{ @tagName(which), self.tally(which) }) catch return;
        self.cutoffs(a, &text) catch return;
        if (self.sink.tag.len != 0) text.print(a, ",\"tag\":{f}", .{std.json.fmt(self.sink.tag, .{})}) catch return;
        text.append(a, '}') catch return;
        const line = std.fmt.allocPrint(a, "{s}\n", .{text.items}) catch return;
        appendLine(self.machine.io, self.sink.path, line, log_limit_bytes);
    }
};

/// One finding line.
const Line = struct {
    v: u8 = 1,
    class: []const u8,
    kind: []const u8,
    entry: []const u8,
    detail: []const u8,
    tag: ?[]const u8 = null,
};

/// A log that has grown past this many bytes takes no more lines.
pub const log_limit_bytes = 64 << 20;

fn write(self: *Shadow, a: std.mem.Allocator, text: []const u8) void {
    if (!language.engine_session.claimCompilerLine(line_limit)) return;
    const line = std.fmt.allocPrint(a, "{s}\n", .{text}) catch return;
    appendLine(self.machine.io, self.sink.path, line, log_limit_bytes);
}

/// Append `line` to `path` under an advisory lock, creating the file and its directory, unless the file already holds `limit`
/// bytes.
pub fn appendLine(io: std.Io, path: []const u8, line: []const u8, limit: u64) void {
    if (std.fs.path.dirname(path)) |directory| std.Io.Dir.cwd().createDirPath(io, directory) catch return;
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false, .read = true }) catch return;
    defer file.close(io);
    const locked = if (file.lock(io, .exclusive)) true else |_| false;
    defer if (locked) file.unlock(io);
    const offset = file.length(io) catch return;
    if (offset >= limit) return;
    file.writePositionalAll(io, line, offset) catch return;
}

fn bytesLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn sameParts(left: []const record.Part, right: []const record.Part) bool {
    if (left.len != right.len) return false;
    for (left, right) |was, is| {
        if (!std.mem.eql(u8, was.name, is.name)) return false;
        if (!std.mem.eql(u8, &was.digest, &is.digest)) return false;
    }
    return true;
}

/// The name of the first part on which two tables differ, or `(payload)` when only the payload does.
fn firstDifference(left: []const record.Part, right: []const record.Part) []const u8 {
    const common = @min(left.len, right.len);
    for (left[0..common], right[0..common]) |was, is| {
        if (!std.mem.eql(u8, was.name, is.name)) return was.name;
        if (!std.mem.eql(u8, &was.digest, &is.digest)) return was.name;
    }
    if (left.len != right.len) return if (left.len > common) left[common].name else right[common].name;
    return "(payload)";
}

/// Whether the environment turns the compiler's shadow on: the variable is set to something other than `0`, `off` or nothing.
pub fn enabled(environment: *const std.process.Environ.Map) bool {
    return variableOn(environment, switch_variable);
}

/// The variable that turns off the engine's keying of lowering by checked-body parts (G3g): `0` or `off` keys every function as
/// before. Placement: it changes how a function is found in the cache, never what it lowers to.
pub const lowering_variable = "SELKA_ENGINE_DECIDE_LOWERING";

/// Whether the engine keys lowering by its checked-body parts: unless `lowering_variable` is `0` or `off`.
pub fn decidesLowering(environment: *const std.process.Environ.Map) bool {
    const value = environment.get(lowering_variable) orelse return true;
    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

/// Whether the engine decides: unless `decide_variable` is `0` or `off`.
pub fn decides(environment: *const std.process.Environ.Map) bool {
    const value = environment.get(decide_variable) orelse return true;
    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

/// The verify sampling of the pass stand-in: the engine's own (`verify_variable`, else 64 in a Debug compiler and none in a release one).
pub fn passesVerifyEvery(environment: *const std.process.Environ.Map) u32 {
    return engine_command.verifyEvery(environment);
}

/// Whether the passes stand in for what the summaries hold: unless `passes_variable` is `0` or `off`.
pub fn decidesPasses(environment: *const std.process.Environ.Map) bool {
    const value = environment.get(passes_variable) orelse return true;
    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

fn variableOn(environment: *const std.process.Environ.Map, name: []const u8) bool {
    const value = environment.get(name) orelse return false;
    return value.len != 0 and !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

/// The engine's verify sampling the environment asks for, one served query in N, none when unset or malformed.
pub fn verifyEvery(environment: *const std.process.Environ.Map) u32 {
    const value = environment.get(verify_variable) orelse return 0;
    return std.fmt.parseInt(u32, value, 10) catch 0;
}

/// The log's path: the variable's value, else `<work>/engine-v1/shadow.jsonl`.
pub fn logPath(a: std.mem.Allocator, environment: *const std.process.Environ.Map, work: []const u8) std.mem.Allocator.Error![]const u8 {
    if (environment.get(log_variable)) |named| if (named.len != 0 and !std.mem.eql(u8, named, "@user")) return a.dupe(u8, named);
    return std.fmt.allocPrint(a, "{s}/engine-v1/shadow.jsonl", .{work});
}

/// Start the shadow of a session whose project root is `root` and whose work directory is `work`, or null when the
/// environment leaves it off or it cannot start. The caller ends it with `Shadow.end`.
pub fn begin(gpa: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, work: []const u8, root: []const u8) ?*Shadow {
    const decide = decides(environment);
    if (!enabled(environment) and !decide) return null;
    const self = gpa.create(Shadow) catch return null;
    var strings: std.heap.ArenaAllocator = .init(gpa);
    const kept_work = strings.allocator().dupe(u8, work) catch return fail(gpa, self, &strings);
    const kept_root = strings.allocator().dupe(u8, root) catch return fail(gpa, self, &strings);
    const path = logPath(strings.allocator(), environment, work) catch return fail(gpa, self, &strings);
    const tag = strings.allocator().dupe(u8, environment.get(tag_variable) orelse "") catch return fail(gpa, self, &strings);
    self.* = .{
        .machine = .{ .gpa = gpa, .io = io, .os = .{ .io = io, .environment = environment, .work = kept_work, .root = kept_root } },
        .runner = undefined,
        .kinds = .{
            .syntax = engine_kinds.module_syntax,
            .graph = engine_kinds.project_graph,
            .interface = engine_kinds.module_interface,
            .check = engine_kinds.module_check,
            .noalloc = engine_kinds.noalloc_closure,
            .passes = engine_kinds.module_passes,
            .program = engine_kinds.program_diagnostics,
            .lower = engine_kinds.unit_lower,
            .facts = engine_kinds.program_facts,
            .optimize = engine_kinds.unit_optimize,
            .emit = engine_kinds.unit_emit,
        },
        .sources = .{
            .syntax = .{ .context = self, .answer = syntaxAnswer },
            .graph = .{ .source = .{ .context = self, .answer = graphAnswer }, .syntax = undefined },
            .interface = .{ .source = .{ .context = self, .answer = interfaceAnswer }, .syntax = undefined },
            .check = .{ .source = .{ .context = self, .answer = checkAnswer }, .syntax = undefined, .interface = undefined },
            .noalloc = .{ .source = .{ .context = self, .answer = noallocAnswer }, .check = undefined },
            .passes = .{ .source = .{ .context = self, .answer = passesAnswer }, .check = undefined, .syntax = undefined, .noalloc = undefined },
            .program = .{ .source = .{ .context = self, .answer = programAnswer }, .graph = undefined, .passes = undefined, .noalloc = undefined },
            .lower = .{ .source = .{ .context = self, .answer = lowerAnswer }, .check = undefined, .interface = undefined, .syntax = undefined },
            .facts = .{ .source = .{ .context = self, .answer = factsAnswer }, .lower = undefined },
            .optimize = .{ .source = .{ .context = self, .answer = optimizeAnswer }, .lower = undefined },
            .emit = .{ .source = .{ .context = self, .answer = emitAnswer }, .optimize = undefined },
        },
        .answers = .{ .arena = .init(gpa), .decision = .{ .enabled = decide, .sample_every = engine_command.verifyEvery(environment) } },
        .sink = .{ .path = path, .tag = tag, .work = kept_work, .summary = enabled(environment) or verifyEvery(environment) != 0 or environment.get(log_variable) != null },
        .strings = strings,
    };
    self.sources.graph.syntax = &self.kinds.syntax;
    self.sources.interface.syntax = &self.kinds.syntax;
    self.sources.check.syntax = &self.kinds.syntax;
    self.sources.check.interface = &self.kinds.interface;
    self.sources.noalloc.check = &self.kinds.check;
    self.sources.passes.check = &self.kinds.check;
    self.sources.passes.syntax = &self.kinds.syntax;
    self.sources.passes.noalloc = &self.kinds.noalloc;
    self.sources.program.graph = &self.kinds.graph;
    self.sources.program.passes = &self.kinds.passes;
    self.sources.program.noalloc = &self.kinds.noalloc;
    self.sources.lower.check = &self.kinds.check;
    self.sources.lower.interface = &self.kinds.interface;
    self.sources.lower.syntax = &self.kinds.syntax;
    self.sources.facts.lower = &self.kinds.lower;
    self.sources.optimize.lower = &self.kinds.lower;
    self.sources.emit.optimize = &self.kinds.optimize;
    self.kinds.syntax.data = &self.sources.syntax;
    self.kinds.graph.data = &self.sources.graph;
    self.kinds.interface.data = &self.sources.interface;
    self.kinds.check.data = &self.sources.check;
    self.kinds.noalloc.data = &self.sources.noalloc;
    self.kinds.passes.data = &self.sources.passes;
    self.kinds.program.data = &self.sources.program;
    self.kinds.lower.data = &self.sources.lower;
    self.kinds.facts.data = &self.sources.facts;
    self.kinds.optimize.data = &self.sources.optimize;
    self.kinds.emit.data = &self.sources.emit;

    self.machine.records = engine_sharing.open(gpa, io, engine_sharing.explicit(environment));
    self.runner = engine.Engine.init(gpa, io, self.machine.os.world(), .{
        .work = kept_work,
        .verify_every = if (decide) 0 else verifyEvery(environment),
        .shared = if (self.machine.records) |*records| records.tier() else null,
    }) catch {
        if (self.machine.records) |*records| records.deinit();
        self.answers.arena.deinit();
        return fail(gpa, self, &self.strings);
    };
    self.runner.register(&self.kinds.syntax) catch return discard(self);
    self.runner.register(&self.kinds.graph) catch return discard(self);
    self.runner.register(&self.kinds.interface) catch return discard(self);
    self.runner.register(&self.kinds.check) catch return discard(self);
    self.runner.register(&self.kinds.noalloc) catch return discard(self);
    self.runner.register(&self.kinds.passes) catch return discard(self);
    self.runner.register(&self.kinds.program) catch return discard(self);
    self.runner.register(&self.kinds.lower) catch return discard(self);
    self.runner.register(&self.kinds.facts) catch return discard(self);
    self.runner.register(&self.kinds.optimize) catch return discard(self);
    self.runner.register(&self.kinds.emit) catch return discard(self);
    // The kinds whose records name no path of this tree and hold no program position share them across worktrees (G4c).
    // The unit kinds (`lower`, `facts`, `optimize`) join when lowering's keys are position-free (G3g).
    for ([_]*const context_rules.Kind{ &self.kinds.syntax, &self.kinds.graph, &self.kinds.interface, &self.kinds.check, &self.kinds.noalloc, &self.kinds.passes, &self.kinds.program }) |kind| self.runner.share(kind, null);
    return self;
}

fn fail(gpa: std.mem.Allocator, self: *Shadow, strings: *std.heap.ArenaAllocator) ?*Shadow {
    strings.deinit();
    gpa.destroy(self);
    return null;
}

fn discard(self: *Shadow) ?*Shadow {
    self.runner.deinit();
    if (self.machine.records) |*records| records.deinit();
    self.answers.arena.deinit();
    return fail(self.machine.gpa, self, &self.strings);
}

/// Put `answer` in `map` under a copy of `path`. The engine lends its argument to one query and then reuses the memory, while the
/// map is read and rehashed until the shadow ends, so a key that borrowed the argument would dangle.
pub fn putOwned(map: anytype, arena: std.mem.Allocator, path: []const u8, answer: anytype) std.mem.Allocator.Error!void {
    if (map.contains(path)) return map.put(arena, path, answer);
    return map.put(arena, try arena.dupe(u8, path), answer);
}

fn syntaxAnswer(raw: *anyopaque, argument: []const u8) ?syntax_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    if (self.answers.maps.syntax.get(argument)) |known| return known;
    return self.lazySyntax(argument);
}

fn emitAnswer(raw: *anyopaque, argument: []const u8) ?emit_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.emit.get(argument);
}

fn optimizeAnswer(raw: *anyopaque, argument: []const u8) ?optimize_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.optimize.get(argument);
}

fn factsAnswer(raw: *anyopaque, argument: []const u8) ?facts_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.facts.get(argument);
}

fn lowerAnswer(raw: *anyopaque, argument: []const u8) ?unit_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.lower.get(argument);
}

fn programAnswer(raw: *anyopaque, argument: []const u8) ?program_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.program.get(argument);
}

fn noallocAnswer(raw: *anyopaque, argument: []const u8) ?noalloc_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.noalloc.get(argument);
}

fn passesAnswer(raw: *anyopaque, argument: []const u8) ?passes_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.passes.get(argument);
}

fn checkAnswer(raw: *anyopaque, argument: []const u8) ?check_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.check.get(argument);
}

fn interfaceAnswer(raw: *anyopaque, argument: []const u8) ?interface_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    if (self.answers.maps.interface.get(argument)) |known| return known;
    return self.lazyInterface(argument);
}

fn graphAnswer(raw: *anyopaque, argument: []const u8) ?graph_kind.Answer {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    return self.answers.maps.graph.get(argument);
}

/// Whether the record of `argument` is one the sampling withholds from the front end to compare with what it computes.
fn withheld(every: u32, argument: []const u8) bool {
    return every != 0 and engine_digest.sample(engine_digest.hash(argument)) % every == 0;
}

/// The digest of the `body:` part of `function` in its module's `module-check` answer, or null when its module's answer is not held
/// or names no such body (a name the module does not prefix, an instance). The module is the one whose text holds the declaration.
fn bodyDigestOf(raw: *anyopaque, src: ?language.source.Source, function: language.typed.Function) ?[32]u8 {
    const self: *Shadow = @ptrCast(@alignCast(raw));
    const merged = src orelse return null;
    if (merged.origins.len == 0) return null;
    const at = merged.originalSpan(.{ .start = function.declaration.start, .end = function.declaration.start }) catch return null;
    const slots = self.answers.decision.slots;
    if (at.input >= slots.len or !slots[at.input].settled) return null;
    const slot = slots[at.input];
    // The functions of the entry module carry no module prefix; the part is looked up under the module that holds the declaration.
    const prefixed = std.mem.startsWith(u8, function.name, slot.name) and std.mem.startsWith(u8, function.name[slot.name.len..], "::");
    const rest = if (prefixed) function.name[slot.name.len + 2 ..] else function.name;
    var buffer: [512]u8 = undefined;
    const wanted = std.fmt.bufPrint(&buffer, "body:{s}", .{rest[0 .. std.mem.indexOfScalar(u8, rest, '[') orelse rest.len]}) catch return null;
    var low: usize = 0;
    var high: usize = slot.parts.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        switch (std.mem.order(u8, slot.parts[middle].name, wanted)) {
            .eq => return slot.parts[middle].digest,
            .lt => low = middle + 1,
            .gt => high = middle,
        }
    }
    return null;
}

/// `parts` with each name copied into `a`: the engine's parts are valid until its next revision, the slot's must outlive it.
fn ownedParts(a: std.mem.Allocator, parts: []const record.Part) std.mem.Allocator.Error![]const record.Part {
    const copy = try a.alloc(record.Part, parts.len);
    for (parts, copy) |part, *slot| slot.* = .{ .name = try a.dupe(u8, part.name), .digest = part.digest };
    return copy;
}

fn deciderRestore(raw: ?*anyopaque, a: std.mem.Allocator, module: usize) ?[]u8 {
    const self: *Shadow = @ptrCast(@alignCast(raw.?));
    const decision = &self.answers.decision;
    if (module >= decision.slots.len) return null;
    const began = std.Io.Timestamp.now(self.machine.io, .awake);
    defer self.spend(began);
    const slot = &decision.slots[module];
    const answered = (self.runner.peek(&self.kinds.check, slot.argument) catch return self.errored()) orelse return null;
    if (withheld(decision.sample_every, slot.argument)) {
        // The whole record is built before the slot says it holds one. Reading the payload can fail (a stored object that is gone is
        // computed again, and a deciding session cannot), and so can a copy; a slot left withheld with half a record is compared against
        // memory that was never written.
        const kept = self.answers.arena.allocator();
        const payload = answered.result.payload() catch return self.unreadable(slot);
        const expected: check_kind.Answer = .{
            .payload = kept.dupe(u8, payload) catch return self.errored(),
            .parts = ownedParts(kept, answered.result.parts) catch return self.errored(),
            .lookups = &.{},
            .files = &.{},
        };
        slot.expected = expected;
        slot.fate = .withheld;
        return null;
    }
    const stored = answered.result.payload() catch return self.unreadable(slot);
    const copy = a.dupe(u8, stored) catch return self.errored();
    const parts = ownedParts(self.answers.arena.allocator(), answered.result.parts) catch return self.errored();
    slot.fate = .served;
    slot.parts = parts;
    return copy;
}

fn deciderReject(raw: ?*anyopaque, module: usize) void {
    const self: *Shadow = @ptrCast(@alignCast(raw.?));
    const decision = &self.answers.decision;
    if (module >= decision.slots.len) return;
    const slot = &decision.slots[module];
    // The valid record did not describe the module's functions: it is wrong, so it goes, and the front end's keys replace it.
    slot.fate = .computed;
    self.count(.decide_rejected);
    self.runner.forget(&self.kinds.check, slot.argument);
}
