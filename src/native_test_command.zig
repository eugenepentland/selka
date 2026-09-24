//! Native guest tests with transitive semantic result caching.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const cases = @import("native_test_cases.zig");
const snapshot = @import("native_test_snapshot.zig");
const sessions = @import("native_test_session.zig");
const planner = @import("native_test_plan.zig");
const receipts = @import("native_test_receipts.zig");
const contracts = @import("native_test_contracts.zig");
const fanout = @import("native_test_directory.zig");
const language = @import("mylang");
const graph_store = @import("native_test_graph.zig");
const invalidation = @import("invalidation.zig");
const build_options = @import("qbe_build_options.zig");
const budget = @import("memory_budget");
const execute = @import("native_test_execute.zig");
const property = @import("native_test_property.zig");
const generator = @import("property_generate.zig");
const wire = @import("native_test_wire.zig");
const bench = @import("native_bench.zig");
const builtin = @import("builtin");
/// Setup failures never produce a cached green test run.
pub const Error = sessions.Error || cases.Error || planner.Error || receipts.Error || fanout.Error || contracts.Error || graph_store.Error || bench.Error;

/// One fully checked and (when needed) prepared project graph. Cases that
/// select the same provider replacement set share it, including the native
/// library executor; execution itself remains one isolated process per case.
const Graph = struct {
    project: sessions.Project,
    provider_identity: []const u8,
    source_identity: []const u8,
    /// Name and symbol tables over the graph, built on first use.
    tables: ?*Tables = null,

    /// The graph's lookup tables, built once: planning a selection then costs
    /// each test's closure instead of a scan of the whole graph per test.
    fn lookup(self: *Graph, allocator: std.mem.Allocator) Error!*Tables {
        if (self.tables) |built| return built;
        const tables = try allocator.create(Tables);
        tables.* = .{ .plan = try planner.Index.init(allocator, self.project.manifest) };
        for (v.array(v.get(self.project.manifest, contracts.functions_key))) |function| {
            const exported = v.text(v.get(v.get(function, "export"), "name"));
            if (exported.len != 0) _ = try tables.exports.getOrPutValue(allocator, exported, v.text(v.get(function, "symbol")));
        }
        for (v.array(v.get(self.project.schema, contracts.functions_key))) |function| {
            _ = try tables.checked.getOrPutValue(allocator, v.text(v.get(function, "name")), function);
        }
        self.tables = tables;
        return tables;
    }
};
/// One graph's lookup tables: the planner's symbol index, exported name to
/// symbol, and checked schema entry by qualified name. The first entry of a
/// repeated name wins, as the linear scans these replace found it first.
const Tables = struct {
    plan: planner.Index,
    exports: std.StringHashMapUnmanaged([]const u8) = .empty,
    checked: std.StringHashMapUnmanaged(std.json.Value) = .empty,

    /// The native symbol of an exported test name.
    fn symbol(self: *const Tables, name: []const u8) Error![]const u8 {
        return self.exports.get(name) orelse error.UnknownFunction;
    }
};

/// Invocation-local memoization of declaration validation and checked project
/// preparation keyed by the selected provider graph identity. The baseline
/// graph (no replacement sources) is represented by the empty identity.
const Graphs = struct {
    allocator: std.mem.Allocator,
    session: sessions.Session,
    captured: snapshot.Snapshot,
    production: std.json.Value,
    /// Durable reduced-graph directory; empty when the invocation is uncached.
    directory: []const u8,
    entries: std.StringHashMapUnmanaged(*Graph) = .empty,
    /// The production graph's preparation begun before discovery, if any.
    early: ?Early = null,

    fn deinit(self: *Graphs) void {
        abandon(self.early);
        self.early = null;
        self.finishSessions();
        self.entries.deinit(self.allocator);
    }

    /// Reap every retained checked-compilation session and fold its work report.
    /// Call this before the invocation's own report so child counters are complete.
    fn finishSessions(self: *Graphs) void {
        var iterator = self.entries.valueIterator();
        while (iterator.next()) |entry| {
            const project = &entry.*.project;
            if (project.compile) |compile| {
                compile.finish(self.session);
                project.compile = null;
            }
        }
    }

    fn get(self: *Graphs, case: cases.Case) Error!*Graph {
        const has_providers = case.providers == .object and case.providers.object.count() != 0;
        const provider_identity = if (has_providers) try contracts.providerIdentity(self.allocator, case.providers) else "";
        if (self.entries.get(provider_identity)) |existing| return existing;
        const graph = try self.allocator.create(Graph);
        errdefer self.allocator.destroy(graph);
        if (has_providers) {
            // The unselected production module passed declaration-first
            // validation above. Validate this replacement graph's declarations
            // before checking any selected implementation body, then share the
            // checked project across every case selecting the same graph.
            const copied = try snapshot.replace(self.session.context, self.captured, case.providers, try self.session.context.temporary(self.session.temporary));
            const replacement = try self.session.interfaceCheck(copied.entry_path);
            const modules = try contracts.moduleNames(self.allocator, case.providers);
            try contracts.validate(self.allocator, self.production, replacement, modules);
            graph.* = .{
                .project = try self.prepare(copied.entry_path, copied.identity, provider_identity),
                .provider_identity = provider_identity,
                .source_identity = copied.identity,
            };
        } else {
            graph.* = .{
                .project = try self.prepare(self.captured.entry_path, self.captured.identity, provider_identity),
                .provider_identity = provider_identity,
                .source_identity = self.captured.identity,
            };
        }
        self.entries.put(self.allocator, provider_identity, graph) catch |err| {
            // The graph map is the owner of a successful graph; if publishing the
            // entry fails, its retained checked compilation must still be reaped.
            if (graph.project.compile) |compile| compile.finish(self.session);
            return err;
        };
        return graph;
    }

    /// Admit durable checked facts only after the project passes the shared query
    /// cache; otherwise check once through the retained `native-test-compile`
    /// session, which performs no lowering or QBE emission on the facts request.
    fn prepare(self: *Graphs, entry_path: []const u8, source_identity: []const u8, provider_identity: []const u8) Error!sessions.Project {
        const session = self.session;
        const key = try graphKey(session, source_identity, provider_identity);
        // The production graph's preparation may already be under way.
        if (provider_identity.len == 0) if (self.early) |early| {
            self.early = null;
            return switch (early) {
                .stored => |facts| admit(session, entry_path, facts),
                .compiling => |compile| self.compiled(entry_path, key, compile),
            };
        };
        if (storedFacts(session, self.directory, key)) |facts| return admit(session, entry_path, facts);
        const compile = try sessions.Compile.begin(session, entry_path);
        return self.compiled(entry_path, key, compile);
    }

    /// Take the checked facts of a session whose facts request was sent, keep
    /// the session for selective lowering and publish the durable graph. Any
    /// failure reaps the session; a successful return transfers it to the graph.
    fn compiled(self: *Graphs, entry_path: []const u8, key: []const u8, compile: *sessions.Compile) Error!sessions.Project {
        const session = self.session;
        errdefer compile.finish(session);
        try compile.awaitFacts();
        const facts = try compile.facts(session);
        var project = try session.projectFromManifest(entry_path, facts);
        project.compile = compile;
        if (!session.options.flags.no_cache and session.environment.cacheable) {
            graph_store.store(session.context, self.directory, key, facts) catch |err| ignoreStoreFailure(err);
        }
        return project;
    }
};
/// The production graph's preparation begun before the interface check, so the
/// compiler child checks the project while this process validates
/// declarations: the stored checked facts, or a session already checking.
const Early = union(enum) { stored: std.json.Value, compiling: *sessions.Compile };
/// Every input that can change one graph's checked facts, as its store key.
fn graphKey(session: sessions.Session, source_identity: []const u8, provider_identity: []const u8) Error![]const u8 {
    return graph_store.key(session.context.allocator, .{
        .compiler_identity = session.hashes[0],
        .zig_stamp = session.hashes[1],
        .qbe_stamp = session.hashes[2],
        .mode = session.options.mode,
        .environment_hash = session.environment.hash,
        .source_identity = source_identity,
        .provider_identity = provider_identity,
    });
}
/// Durable checked facts for `key`, when reuse is allowed and they verify. A
/// forced run must re-check and re-emit fresh facts; a `--no-cache` run reads
/// and writes no durable entry at all.
fn storedFacts(session: sessions.Session, directory: []const u8, key: []const u8) ?std.json.Value {
    if (!durableReuseAllowed(session.options, session.environment.cacheable)) return null;
    return graph_store.load(session.context, directory, key);
}
/// Admit durable checked facts only after the project passes the shared query cache.
fn admit(session: sessions.Session, entry_path: []const u8, facts: std.json.Value) Error!sessions.Project {
    try session.validate(entry_path);
    return session.projectFromValue(entry_path, facts);
}
/// Begin the production graph's preparation when every case will select it:
/// no case configuration names a provider fixture. A stored graph is loaded,
/// otherwise the compile session starts checking now. Null when a fixture may
/// select another graph, so nothing is checked before its declarations are.
fn speculate(session: sessions.Session, captured: snapshot.Snapshot, directory: []const u8) ?Early {
    if (session.options.cases) |path| if (!providerFree(session.context, path)) return null;
    const key = graphKey(session, captured.identity, "") catch return null;
    if (storedFacts(session, directory, key)) |facts| return .{ .stored = facts };
    const compile = sessions.Compile.begin(session, captured.entry_path) catch return null;
    return .{ .compiling = compile };
}
/// Whether a case configuration file parses and names no provider fixture.
/// Anything else answers false, leaving the ordinary ordered preparation to
/// report it.
fn providerFree(context: fs.Context, path: []const u8) bool {
    const bytes = context.read(path) catch return false;
    const parsed = std.json.parseFromSlice(std.json.Value, context.allocator, bytes, .{}) catch return false;
    if (parsed.value == .null) return true;
    if (parsed.value != .object) return false;
    for (parsed.value.object.values()) |case| {
        const providers = v.get(case, "providers");
        if (providers == .object and providers.object.count() != 0) return false;
    }
    return true;
}
/// Release a begun preparation the run never consumed.
fn abandon(early: ?Early) void {
    const begun = early orelse return;
    switch (begun) {
        .stored => {},
        .compiling => |compile| compile.discard(),
    }
}
/// A materialized snapshot and, when it sits at the project's stable root,
/// the claim the run releases on exit.
const Staged = struct { captured: snapshot.Snapshot, stable: ?snapshot.Stable };
/// Materialize the run's snapshot at the project's stable root when this run
/// can claim it (`snapshot.claimStable`), so the compiler children see the same
/// source paths on every run and their path-keyed caches answer; otherwise, or
/// when writing there fails, at a fresh private path under the session.
fn stage(context: fs.Context, session: sessions.Session, prepared: snapshot.Snapshot) Error!Staged {
    const seed = try std.mem.join(context.allocator, "\x00", &.{ session.directory, session.source.root, session.source.entry });
    if (snapshot.claimStable(context, try context.absolute(context.scratchRoot()), seed)) |claimed| {
        if (snapshot.materialize(context, prepared, claimed.directory)) |captured| {
            return .{ .captured = captured, .stable = claimed };
        } else |_| claimed.release(context);
    }
    return .{ .captured = try snapshot.materialize(context, prepared, try context.temporary(session.temporary)), .stable = null };
}
/// The fan-out width asked for: `--jobs` first, then `MYLANG_JOBS`, then none,
/// which leaves the default derived from cores and free memory.
fn requested(flag: ?usize, environ: *const std.process.Environ.Map) budget.Error!?usize {
    if (flag) |value| return value;
    const text = environ.get(budget.jobs_variable) orelse return null;
    if (text.len == 0) return null;
    const width = try budget.jobs(text);
    return width;
}
/// Discover, check, selectively execute, and report native application tests.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(process.io, options.usage);
        return 0;
    }
    // RELEASE-CHECKED-1: `--unchecked` is refused by name rather than as an
    // unknown flag, with the same reason every build gives.
    if (build_options.uncheckedRequested(args)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang test: " ++ build_options.unchecked_removed);
        return 2;
    }
    var opts = options.parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, options.usage);
        return 2;
    };
    var context = try fs.Context.init(process.arena.allocator(), process.io, process.environ_map);
    defer context.deinit();
    // Resolve the ceiling once, before any child or receipt key observes it:
    // the flag wins, then MYLANG_MEMORY_LIMIT, then the per-test default.
    opts.limits.max_memory = budget.resolve(opts.limits.max_memory, context.environ, budget.variable, budget.test_default) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, options.usage);
        return 2;
    };
    opts.jobs = requested(opts.jobs, context.environ) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, options.usage);
        return 2;
    };
    // A directory names many independent projects, so each one runs as its own child.
    if (fanout.selected(context, opts.source)) return fanout.run(context, opts);
    var session = try sessions.Session.init(context, opts);
    defer context.remove(session.temporary);
    var work: invalidation.Work = .{ .command = "test" };
    if (opts.flags.output.report) session.work = &work;
    const prepared = try snapshot.withTestEntry(context, session.source);
    const staged = try stage(context, session, prepared);
    defer if (staged.stable) |claimed| claimed.release(context);
    const captured = staged.captured;
    const directory = try std.fs.path.join(context.allocator, &.{ session.directory, "results" });
    const graphs_directory = if (opts.flags.no_cache) "" else try std.fs.path.join(context.allocator, &.{ session.directory, "graphs" });
    // When every case selects the production graph, its check starts now and
    // runs beside the declaration check below instead of after it.
    var early = speculate(session, captured, graphs_directory);
    defer abandon(early);
    // Resolve configuration first. `list-interfaces --contracts` parses every
    // module and validates exported signatures and explicit ceilings without
    // checking any body, so an unfinished replacement target cannot block
    // selection while its public declarations stay valid.
    const production = session.interfaceCheckCached(captured.entry_path, captured.identity) catch |err| switch (err) {
        error.ProjectConfigurationFailed => return 2,
        error.ProjectPolicyRejected => return 3,
        else => return err,
    };
    var graphs: Graphs = .{ .allocator = context.allocator, .session = session, .captured = captured, .production = production, .directory = graphs_directory, .early = early };
    early = null;
    defer graphs.deinit();
    const config_bytes = if (opts.cases) |path| try context.read(path) else "null";
    const config = (try std.json.parseFromSlice(std.json.Value, context.allocator, config_bytes, .{ .allocate = .alloc_always })).value;
    const declared_schema = try contracts.testSchema(context.allocator, production);
    var selected: []const cases.Case = if (opts.bench.only) &.{} else try cases.discover(context.allocator, declared_schema, config, opts.filter);
    // `--affected` narrows the discovered set to the tests that reach a
    // declaration changed since its reference. It is a selection, never a
    // verdict: an empty derivation still flows through the ordinary report and
    // exits 3, and a derivation that cannot be made runs the whole set.
    if (opts.flags.affected) {
        const source_absolute = try context.absolute(opts.source);
        const git_root = std.fs.path.dirname(source_absolute) orelse ".";
        const names = try context.allocator.alloc([]const u8, selected.len);
        for (selected, names) |case, *name| name.* = case.name;
        const selection = language.affected_tests.select(.{
            .memory = context.allocator,
            .io = context.io,
            .load_root = captured.root,
            .git_root = git_root,
            .entry = captured.entry,
            .reference = opts.against.?,
            .discovered = names,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.GitFailed => {
                try std.Io.File.stderr().writeStreamingAll(context.io, "mylang test: --against names a revision git cannot resolve\n");
                return 2;
            },
            error.InvalidEntry => {
                try std.Io.File.stderr().writeStreamingAll(context.io, options.usage);
                return 2;
            },
        };
        var kept: std.ArrayList(cases.Case) = .empty;
        for (selected, selection.keep) |case, keep| if (keep) try kept.append(context.allocator, case);
        selected = kept.items;
        try reportAffected(context, selection, opts.against.?);
    }
    const benches: []const bench.Selection = if (opts.bench.pattern) |pattern| try bench.discover(context.allocator, declared_schema, config, pattern) else &.{};
    const results = try context.allocator.alloc(receipts.Result, selected.len);
    const pure = try context.allocator.alloc(bool, selected.len);
    @memset(pure, false);
    const replayed = try context.allocator.alloc(bool, selected.len);
    @memset(replayed, false);
    const bench_states = try context.allocator.alloc(Bench, benches.len);
    for (benches, bench_states) |selection, *state| state.* = .{ .plan = .{ .selection = selection } };
    try context.mkdir(directory);
    var pending: std.ArrayList(Pending) = .empty;
    defer pending.deinit(context.allocator);

    const outcomes: Outcomes = .{ .results = results, .pure = pure, .replayed = replayed };
    planSelectedCases(context, &graphs, directory, selected, outcomes, &pending) catch |err| switch (err) {
        error.ProjectConfigurationFailed => return 2,
        error.ProjectPolicyRejected => return 3,
        else => return err,
    };
    try planSelectedBenches(context, &graphs, bench_states, &pending);
    try prepareSelectedGraphs(context, session, pending.items);
    try executeSelectedCases(context, session, selected, results, pending.items);
    var bench_context = try initBenchContext(context, opts, session);
    // Benchmarks always execute freshly and never reuse receipts or timings;
    // a failing correctness test blocks measurement entirely.
    const test_failed = anyFailed(results);
    if (!test_failed) try executeSelectedBenches(context, session, opts, bench_states, pending.items, bench_context.run());
    // Reap any retained checked-compilation sessions before the invocation's own
    // work report so their child counters are folded into it.
    graphs.finishSessions();
    try session.verify();
    if (opts.cases) |path| {
        if (!std.mem.eql(u8, config_bytes, try context.read(path))) return error.SourceChanged;
    }
    if (!opts.flags.no_cache) for (results, pure) |result, is_pure| {
        try receipts.write(context, directory, result);
        if (opts.flags.pure_skip and is_pure) try receipts.writeOutcome(context, directory, result);
    };
    if (opts.flags.output.report) try emitWorkReport(context, &work, results, replayed);
    const loaded = try snapshot.sourcesOf(context, prepared, production);
    const test_status = try report(context, .{ .results = results, .replayed = replayed, .loaded = loaded }, opts.flags.output.json);
    return finish(context, opts, bench_states, &bench_context, test_status, test_failed);
}

/// Benchmark policy, baseline, identity and provenance for one invocation. The
/// `run` view borrows this value, so it must outlive every comparison.
const BenchContext = struct {
    policy: bench.Policy = .{},
    baseline: ?bench.Baseline = null,
    identity: bench.Identity = .{},
    provenance: bench.Provenance = .{},

    fn run(self: *BenchContext) bench.Run {
        const approved: ?*const bench.Baseline = if (self.baseline) |*value| value else null;
        return .{ .policy = &self.policy, .baseline = approved, .identity = self.identity };
    }
};
/// Readable prefix of a tool stamp: path and size, without the NUL-separated
/// modification-time bytes. Provenance is diagnostic and never gates a comparison.
fn stampText(value: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, value, 0)) |at| value[0..at] else value;
}
/// Environment variable carrying a source revision for provenance; empty when absent.
const revision_variable = "MYLANG_BENCH_REVISION";
/// Load the approved policy and baseline; absent artifacts use safe defaults.
fn initBenchContext(context: fs.Context, opts: options.Options, session: sessions.Session) Error!BenchContext {
    var result: BenchContext = .{
        .identity = .{
            .mode = session.options.mode,
            .runner_profile = opts.bench.profile,
            .boundary_version = 1,
            .warmup_iterations = opts.bench.tuning.sampling.warmup_iterations,
            .batch_count = opts.bench.tuning.sampling.batch_count,
            .target_batch_ns = opts.bench.tuning.sampling.target_batch_ns,
        },
    };
    result.provenance = .{
        .revision = context.environ.get(revision_variable) orelse "",
        .identity = result.identity,
        .tools = .{ .compiler = session.hashes[0], .zig = stampText(session.hashes[1]), .qbe = stampText(session.hashes[2]) },
        .platform = .{ .os = @tagName(builtin.os.tag), .arch = @tagName(builtin.cpu.arch) },
    };
    result.policy = if (opts.bench.policy) |path| try bench.parsePolicy(context.allocator, try context.read(path)) else .{ .runner_profile = opts.bench.profile };
    if (opts.bench.baseline) |path| result.baseline = try bench.parseBaseline(context.allocator, try context.read(path));
    return result;
}
/// A measured benchmark's identity, function, dependency closure and samples.
const BenchPlan = struct { selection: bench.Selection, function: std.json.Value = .null, dependencies: []const []const u8 = &.{} };
const BenchSample = struct { status: []const u8 = "skipped", diagnostics: []const u8 = "", raw: []const execute.Batch = &.{}, stats: bench.Stats = .{} };
const Bench = struct { plan: BenchPlan, sample: BenchSample = .{}, measurement: ?bench.Measurement = null, comparison: ?bench.Comparison = null };
/// Whether a required benchmark ID was selected in this invocation.
fn isRequired(policy: bench.Policy, id: []const u8) bool {
    for (policy.required) |required| if (std.mem.eql(u8, required, id)) return true;
    return false;
}
/// Whether any correctness test failed; a failed test blocks measurement.
fn anyFailed(results: []const receipts.Result) bool {
    for (results) |result| if (std.mem.eql(u8, result.status, "failed")) return true;
    return false;
}
/// Plan each discovered benchmark exactly like a test: resolve its provider
/// graph and semantic dependency closure so selective lowering includes it.
fn planSelectedBenches(context: fs.Context, graphs: *Graphs, benches: []Bench, pending: *std.ArrayList(Pending)) Error!void {
    for (benches, 0..) |*state, index| {
        const selection = state.plan.selection;
        if (selection.case.declared.skip) |reason| {
            state.sample.status = "skipped";
            state.sample.diagnostics = reason;
            continue;
        }
        const graph = try graphs.get(selection.case);
        const tables = try graph.lookup(context.allocator);
        const checked = tables.checked.get(selection.case.name) orelse selection.case.function;
        state.plan.function = checked;
        const plan = try tables.plan.plan(context.allocator, try tables.symbol(selection.case.name), try graphs.session.key(selection.case.settings, checked));
        state.plan.dependencies = plan.dependencies;
        try pending.append(context.allocator, .{ .graph = graph, .selected = checked, .dependencies = plan.dependencies, .kind = .benchmarks, .slot = index });
    }
}
/// Sample every planned benchmark and, when a comparison is near a limit or
/// noisy, run the single predefined confirmation and evaluate all batches.
fn executeSelectedBenches(
    context: fs.Context,
    session: sessions.Session,
    opts: options.Options,
    benches: []Bench,
    pending: []const Pending,
    gate: bench.Run,
) Error!void {
    for (pending) |entry| {
        if (entry.kind != .benchmarks) continue;
        const state = &benches[entry.slot];
        const executor = entry.graph.project.executor orelse return error.InvalidGraph;
        const config: execute.BenchConfig = .{ .limits = session.options.limits, .sampling = opts.bench.tuning.sampling, .timeout_ms = opts.bench.tuning.timeout_ms };
        try recordSample(context, session, state, entry.graph.project.source, try executor.benchmark(entry.selected, state.plan.selection.case.arguments, config));
        if (gate.baseline == null or !std.mem.eql(u8, state.sample.status, "passed")) continue;
        const first = state.measurement.?;
        const comparison = bench.compare(gate, first);
        if (gate.policy.noise.confirmation_runs < 1 or !bench.needsConfirmation(gate.policy, first, comparison)) continue;
        const second = try executor.benchmark(entry.selected, state.plan.selection.case.arguments, config);
        if (std.mem.eql(u8, second.status, "value") and snapshot.equivalent(second.actual, state.plan.selection.case.expected)) {
            state.sample.raw = try bench.combinedRaw(context.allocator, state.sample.raw, second.raw);
            state.sample.stats = try bench.summarize(context.allocator, state.sample.raw, second.calibrated_iterations);
            state.measurement = measurementOf(state.*);
        } else {
            try recordSample(context, session, state, entry.graph.project.source, second);
        }
    }
}
/// Fold one native outcome into a benchmark's observable result and statistics.
fn recordSample(context: fs.Context, session: sessions.Session, state: *Bench, project_source: []const u8, outcome: execute.BenchOutcome) Error!void {
    const selection = state.plan.selection;
    state.sample.status = outcome.status;
    state.sample.raw = outcome.raw;
    state.sample.diagnostics = try failureReason(context, .{
        .status = outcome.status,
        .expected = selection.case.expected,
        .actual = outcome.actual,
        .diagnostics = outcome.diagnostics,
        .output = "",
        .project_source = project_source,
        .root = session.source.root,
    });
    state.sample.stats = bench.summarize(context.allocator, outcome.raw, outcome.calibrated_iterations) catch |err| switch (err) {
        error.InvalidBenchReport => bench.Stats{},
        else => return err,
    };
    if (std.mem.eql(u8, outcome.status, "value") and !snapshot.equivalent(outcome.actual, selection.case.expected)) {
        state.sample.status = "failed";
        if (state.sample.diagnostics.len == 0) state.sample.diagnostics = "actual value does not match expected value";
    }
    if (std.mem.eql(u8, state.sample.status, "value")) state.sample.status = "passed";
    if (std.mem.eql(u8, state.sample.status, "passed")) state.measurement = measurementOf(state.*);
}
/// The baseline measurement view of a successfully sampled benchmark.
fn measurementOf(state: Bench) bench.Measurement {
    const selection = state.plan.selection;
    return .{
        .id = selection.id,
        .workload_version = selection.workload_version,
        .fixture_identity = selection.fixture_identity,
        .median_ns_per_op = state.sample.stats.median_ns_per_op,
        .spread_percent = state.sample.stats.spread_percent,
        .raw = state.sample.raw,
    };
}
/// Print, compare and publish benchmark results; never mutate the approved baseline.
fn emitBenchmarks(context: fs.Context, opts: options.Options, benches: []const Bench, ctx: *BenchContext) Error!u8 {
    var measurements: std.ArrayList(bench.Measurement) = .empty;
    var comparisons: std.ArrayList(bench.Comparison) = .empty;
    var failures: std.ArrayList(bench.Failure) = .empty;
    // Asking for benchmarks and selecting none is incomplete coverage, not a
    // green performance run.
    var complete = benches.len != 0;
    const compared = ctx.run().baseline != null;
    for (benches) |state| {
        if (std.mem.eql(u8, state.sample.status, "passed")) {
            const measurement = state.measurement orelse {
                complete = false;
                continue;
            };
            try measurements.append(context.allocator, measurement);
            if (compared) {
                const comparison = bench.applyNoiseBudget(&ctx.policy, measurement, bench.compare(ctx.run(), measurement));
                if (comparison.verdict == .unbaselined or comparison.verdict == .incompatible or comparison.verdict == .inconclusive) complete = false;
                try comparisons.append(context.allocator, comparison);
            }
        } else {
            try failures.append(context.allocator, .{ .id = state.plan.selection.id, .status = state.sample.status, .reason = state.sample.diagnostics });
            if (isRequired(ctx.policy, state.plan.selection.id)) complete = false;
            if (!std.mem.eql(u8, state.sample.status, "skipped")) complete = false;
        }
    }
    if (!bench.coversRequired(&ctx.policy, measurements.items)) complete = false;
    const passed = complete and (!compared or bench.allPassed(comparisons.items, true));
    try printBenchmarks(context, benches, comparisons.items, compared);
    if (opts.bench.output) |path| {
        const rendered = try bench.renderReport(context.allocator, .{
            .provenance = ctx.provenance,
            .measurements = measurements.items,
            .comparisons = comparisons.items,
            .failures = failures.items,
            .complete = complete,
            .passed = passed,
        });
        try context.atomic(path, rendered);
    }
    try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "benchmarks: {d} measured, {d} compared, {s}\n", .{ measurements.items.len, comparisons.items.len, if (passed) "passed" else "failed" }));
    return if (passed) 0 else 1;
}
fn printBenchmarks(context: fs.Context, benches: []const Bench, comparisons: []const bench.Comparison, compared: bool) Error!void {
    for (benches) |state| {
        const id = state.plan.selection.id;
        if (!std.mem.eql(u8, state.sample.status, "passed")) {
            const reason = state.sample.diagnostics;
            try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "bench {s} {s}{s}{s}\n", .{ id, state.sample.status, if (reason.len != 0) ": " else "", reason }));
            continue;
        }
        var verdict: []const u8 = "measured";
        var reason: []const u8 = "";
        for (comparisons) |comparison| if (std.mem.eql(u8, comparison.id, id)) {
            verdict = bench.verdictName(comparison.verdict);
            reason = comparison.reason;
        };
        try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "bench {s} {s} median={d:.2} ns/op spread={d:.2}% samples={d}{s}{s}\n", .{
            id,
            verdict,
            state.measurement.?.median_ns_per_op,
            state.measurement.?.spread_percent,
            state.sample.stats.sample_count,
            if (compared and reason.len != 0) ": " else "",
            if (compared) reason else "",
        }));
    }
}
/// Fold benchmark status into the command status: a failed benchmark gate
/// fails the invocation, while passing benchmarks keep a bench-only run green.
fn finish(context: fs.Context, opts: options.Options, benches: []const Bench, ctx: *BenchContext, test_status: u8, test_failed: bool) Error!u8 {
    if (opts.bench.pattern == null) return test_status;
    if (test_failed) {
        try std.Io.File.stderr().writeStreamingAll(context.io, "benchmarks skipped: correctness tests failed\n");
        return test_status;
    }
    const status = try emitBenchmarks(context, opts, benches, ctx);
    return if (status != 0) status else 0;
}

/// Record the native test outcome as real performed/reused work. Parser, body
/// check, lowering, emission and link counts come from the compiler children's
/// own `work-report-v1` lines, which `Session.observe` folded in.
fn emitWorkReport(context: fs.Context, work: *invalidation.Work, results: []const receipts.Result, replayed: []const bool) Error!void {
    var executed: usize = 0;
    var cached: usize = 0;
    for (results, replayed) |result, was_replayed| {
        // A replayed pure outcome never ran a process, even when its recorded
        // status is `failed`, so it counts as reused rather than executed.
        if (was_replayed) {
            cached += 1;
            continue;
        }
        if (std.mem.eql(u8, result.status, "cached")) cached += 1;
        if (std.mem.eql(u8, result.status, "passed") or std.mem.eql(u8, result.status, "failed")) executed += 1;
    }
    if (results.len != 0) work.set(.executed_tests, executed, cached);
    const rendered = invalidation.renderWork(context.allocator, work.*) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCurrent => return error.InvalidGraph,
    };
    try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "{s}\n", .{rendered}));
}
/// A refused graph-store write must never fail a test run; the graph is an
/// optional acceleration reused on the next unchanged invocation.
fn ignoreStoreFailure(err: graph_store.Error) void {
    // The graph is an optional acceleration; name the ignored cause explicitly.
    _ = @errorName(err);
}
/// Durable graph and result receipts are reusable only when neither force nor
/// `--no-cache` asked for fresh work and persistence is allowed.
fn durableReuseAllowed(opts: options.Options, cacheable: bool) bool {
    if (opts.flags.force) return false;
    if (opts.flags.no_cache) return false;
    return cacheable;
}
// spec-case: PURE-SKIP-1
test "force and no-cache disable durable outcome replay for a pure test" {
    const enabled: options.Options = .{ .source = "main.my" };
    try std.testing.expect(durableReuseAllowed(enabled, true));
    try std.testing.expect(!durableReuseAllowed(.{ .source = "main.my", .flags = .{ .force = true } }, true));
    try std.testing.expect(!durableReuseAllowed(.{ .source = "main.my", .flags = .{ .no_cache = true } }, true));
    try std.testing.expect(!durableReuseAllowed(enabled, false));
}
fn planSelectedCases(
    context: fs.Context,
    graphs: *Graphs,
    directory: []const u8,
    selected: []const cases.Case,
    outcomes: Outcomes,
    pending: *std.ArrayList(Pending),
) Error!void {
    // Tests of one module share its contract identity; compute it once.
    var module_contracts: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (selected, 0..) |case, case_index| {
        const result = &outcomes.results[case_index];
        result.* = .{ .name = case.name, .status = "skipped", .expected = case.expected };
        if (case.declared.skip) |reason| {
            result.reason = reason;
            continue;
        }
        // An undefaultable declared shape is one failed case, never a host
        // failure that aborts the selection before any result is reported.
        if (case.declared.invalid) |reason| {
            result.status = "failed";
            result.reason = reason;
            continue;
        }
        const has_providers = case.providers == .object and case.providers.object.count() != 0;
        const graph = try graphs.get(case);
        const contract_identity = if (has_providers) blk: {
            const modules = try contracts.moduleNames(context.allocator, case.providers);
            break :blk try contracts.contractIdentity(context.allocator, graphs.production, modules);
        } else try moduleContract(context, graphs.production, &module_contracts, try testModuleName(context.allocator, case.name));
        const identity: receipts.Identity = .{ .contract = contract_identity, .provider = graph.provider_identity, .source = graph.source_identity };
        const tables = try graph.lookup(context.allocator);
        const checked = tables.checked.get(case.name) orelse case.function;
        const session = graphs.session;
        const settings = if (case.declared.property) try propertyIdentity(context, session.options, case) else case.settings;
        const plan = try tables.plan.plan(context.allocator, try tables.symbol(case.name), try session.key(settings, checked));
        result.key = try context.allocator.dupe(u8, &plan.key);
        result.dependencies = plan.dependencies;
        result.cacheable = plan.cacheable and session.environment.cacheable;
        result.context = .{ .reasons = plan.reasons, .identity = identity };
        const pure_candidate = result.cacheable and plan.pure;
        outcomes.pure[case_index] = pure_candidate;
        const path = try receipts.path(context, directory, result.key);
        // The opt-in signature-pure path replays a recorded pass or failure by
        // the same semantic identity, without depending on the positive-only
        // receipt. It is checked first so a recorded failure is never mistaken
        // for a miss and silently re-run as a pass.
        if (pure_candidate and session.options.flags.pure_skip and durableReuseAllowed(session.options, result.cacheable)) {
            if (receipts.outcome(context, path, result.key, case.name, case.expected, identity)) |recorded| {
                outcomes.replayed[case_index] = true;
                result.status = if (std.mem.eql(u8, recorded.status, "passed")) "cached" else "failed";
                result.actual = recorded.actual;
                result.reason = recorded.reason;
                continue;
            }
        }
        if (durableReuseAllowed(session.options, result.cacheable) and receipts.hit(context, path, result.key, case.name, case.expected, identity)) {
            result.status = "cached";
            result.actual = case.expected;
            continue;
        }
        // Evict any older pass before a forced or repaired execution can fail.
        if (!session.options.flags.no_cache) try receipts.invalidate(context, path);
        try pending.append(context.allocator, .{ .graph = graph, .selected = checked, .dependencies = plan.dependencies, .kind = .tests, .slot = case_index });
    }
}

/// A property test's receipt identity: its case settings plus the seed its
/// inputs are drawn from, how many must pass and the generator version, so a
/// pass is reused only for the very inputs it passed (PROPERTY-TEST-4).
fn propertyIdentity(context: fs.Context, opts: options.Options, case: cases.Case) Error!std.json.Value {
    var drawn: std.json.ObjectMap = .empty;
    try drawn.put(context.allocator, "generator", .{ .string = generator.version });
    try drawn.put(context.allocator, "runs", .{ .integer = opts.determinism.property_runs });
    try drawn.put(context.allocator, "seed", .{ .string = try std.fmt.allocPrint(context.allocator, "{d}", .{wire.entropySeed(opts.determinism.seed, case.name)}) });
    var identity: std.json.ObjectMap = .empty;
    try identity.put(context.allocator, "cases", case.settings);
    try identity.put(context.allocator, "property", .{ .object = drawn });
    return .{ .object = identity };
}

fn prepareSelectedGraphs(
    context: fs.Context,
    session: sessions.Session,
    pending: []const Pending,
) Error!void {
    var groups: std.ArrayList(*Group) = .empty;
    defer {
        for (groups.items) |group| {
            group.symbols.deinit(context.allocator);
            group.names.deinit(context.allocator);
            context.allocator.destroy(group);
        }
        groups.deinit(context.allocator);
    }
    for (pending) |entry| {
        var group = for (groups.items) |candidate| {
            if (std.mem.eql(u8, candidate.graph.provider_identity, entry.graph.provider_identity)) break candidate;
        } else null;
        if (group == null) {
            const created = try context.allocator.create(Group);
            created.* = .{ .graph = entry.graph };
            try groups.append(context.allocator, created);
            group = created;
        }
        for (entry.dependencies) |dependency| {
            _ = try group.?.symbols.getOrPut(context.allocator, dependency);
        }
    }
    for (groups.items) |group| {
        for (v.array(v.get(group.graph.project.manifest, contracts.functions_key))) |function| {
            const symbol_text = v.text(v.get(function, "symbol"));
            if (group.symbols.contains(symbol_text)) try group.names.append(context.allocator, v.text(v.get(function, "name")));
        }
        if (group.names.items.len != group.symbols.count()) return error.InvalidGraph;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(context.allocator);
        for (group.names.items) |name| {
            try text.appendSlice(context.allocator, name);
            try text.append(context.allocator, '\n');
        }
        const select_path = try std.fs.path.join(context.allocator, &.{ group.graph.project.directory, "native-test-select.txt" });
        try context.write(select_path, text.items);
        _ = try session.executor(&group.graph.project, select_path);
    }
}

/// How many test processes one invocation keeps running at once: `--jobs` or
/// `MYLANG_JOBS` when given, otherwise the cores this process may use, capped
/// by how many per-test memory ceilings the machine's free memory holds.
fn executionWidth(context: fs.Context, opts: options.Options, calls: usize) usize {
    return budget.workers(.{
        .jobs = opts.jobs,
        .programs = calls,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = budget.available(context.io),
        .ceiling = opts.limits.max_memory orelse budget.test_default,
    });
}
/// Execute every pending test case, each in its own fresh bounded process,
/// concurrently across the execution width. Outcomes land in their case's
/// slot, so the report order never depends on which child finished first.
fn executeSelectedCases(
    context: fs.Context,
    session: sessions.Session,
    selected: []const cases.Case,
    results: []receipts.Result,
    pending: []const Pending,
) Error!void {
    var calls: std.ArrayList(execute.Call) = .empty;
    for (pending) |entry| {
        if (entry.kind != .tests or selected[entry.slot].declared.property) continue;
        const executor = if (entry.graph.project.executor) |*prepared| prepared else return error.InvalidGraph;
        try calls.append(context.allocator, .{ .executor = executor, .function = entry.selected, .arguments = selected[entry.slot].arguments });
    }
    const width = executionWidth(context, session.options, calls.items.len);
    const outcomes = try execute.executeAll(context, calls.items, session.options.limits, width);
    var next: usize = 0;
    for (pending) |entry| {
        if (entry.kind != .tests or selected[entry.slot].declared.property) continue;
        const case = selected[entry.slot];
        const result = &results[entry.slot];
        const outcome = outcomes[next];
        next += 1;
        result.actual = outcome.actual;
        result.steps = outcome.steps;
        const passed = std.mem.eql(u8, outcome.status, "value") and snapshot.equivalent(outcome.actual, case.expected);
        result.status = if (passed) "passed" else "failed";
        result.reason = try failureReason(context, .{
            .status = outcome.status,
            .expected = case.expected,
            .actual = outcome.actual,
            .diagnostics = outcome.diagnostics,
            .output = outcome.output,
            .trace = outcome.trace,
            .project_source = entry.graph.project.source,
            .root = session.source.root,
        });
        if (!passed and result.reason.len == 0) result.reason = "actual value does not match expected value";
    }
    try executeProperties(context, session, selected, results, pending);
}

/// One property test in flight: its result slot, its bound run and its search.
const PropertyRun = struct { slot: usize, run: property.Property, source: []const u8, search: property.Search = .{} };

/// Finishes properties on several threads: drawing replacements and
/// shrinking are one process at a time for each property, so failing
/// properties shrink side by side instead of one after another.
const Finisher = struct {
    runs: []PropertyRun,
    answers: []const execute.BatchOutcome,
    verdicts: []Error!property.Verdict,
    next: std.atomic.Value(usize) = .init(0),

    fn all(self: *Finisher, width: usize) void {
        var threads: [16]?std.Thread = @splat(null);
        const extra = @min(threads.len, @max(1, @min(width, self.runs.len)) - 1);
        for (threads[0..extra]) |*thread| thread.* = std.Thread.spawn(.{}, work, .{self}) catch null;
        self.work();
        for (threads[0..extra]) |thread| if (thread) |started| started.join();
    }
    fn work(self: *Finisher) void {
        while (true) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.runs.len) return;
            const bound = &self.runs[index];
            self.verdicts[index] = bound.run.finish(&bound.search, self.answers[index]);
        }
    }
};

/// Run every pending property test: bind each to its library (a signature
/// that cannot be generated fails that test alone), execute every property's
/// first batch concurrently, then finish each — drawing replacements for
/// discarded inputs and shrinking a failure — one after another.
fn executeProperties(
    context: fs.Context,
    session: sessions.Session,
    selected: []const cases.Case,
    results: []receipts.Result,
    pending: []const Pending,
) Error!void {
    const a = context.allocator;
    var runs: std.ArrayList(PropertyRun) = .empty;
    for (pending) |entry| {
        if (entry.kind != .tests or !selected[entry.slot].declared.property) continue;
        const executor = if (entry.graph.project.executor) |*prepared| prepared else return error.InvalidGraph;
        const settings: property.Settings = .{
            .seed = wire.entropySeed(session.options.determinism.seed, selected[entry.slot].name),
            .runs = session.options.determinism.property_runs,
            .entry = session.options.source,
        };
        switch (try property.Property.bind(context, executor, entry.selected, session.options.limits, settings)) {
            .invalid => |reason| {
                results[entry.slot].status = "failed";
                results[entry.slot].reason = reason;
            },
            .ready => |bound| try runs.append(a, .{ .slot = entry.slot, .run = bound, .source = entry.graph.project.source }),
        }
    }
    const batches = try a.alloc(execute.BatchCall, runs.items.len);
    for (runs.items, batches) |*bound, *batch| batch.* = try bound.run.first(&bound.search);
    const width = executionWidth(context, session.options, batches.len);
    const answers = try execute.executeBatches(context, batches, session.options.limits, width);
    var finisher: Finisher = .{ .runs = runs.items, .answers = answers, .verdicts = try a.alloc(Error!property.Verdict, runs.items.len) };
    finisher.all(width);
    for (runs.items, finisher.verdicts) |*bound, finished| {
        const verdict = try finished;
        const result = &results[bound.slot];
        result.status = if (verdict.passed) "passed" else "failed";
        result.actual = .{ .bool = verdict.passed };
        result.reason = try stripRoot(a, verdict.reason, bound.source, session.source.root);
        const text = try std.json.Stringify.valueAlloc(a, verdict.evidence, .{});
        result.context.property = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
    }
}

/// One executed case's failure inputs, grouped to keep the renderer signature small.
const Failure = struct {
    status: []const u8,
    expected: std.json.Value,
    actual: std.json.Value,
    diagnostics: []const u8,
    output: []const u8,
    /// The error return trace the child rendered, shown when the value is an `Err`.
    trace: []const u8 = "",
    project_source: []const u8,
    root: []const u8,
};

/// Render one executed case's failure text: trap diagnostics, or both sides of
/// a typed expectation mismatch, followed by any guest stdout the child
/// captured. A passing case returns an empty string.
fn failureReason(context: fs.Context, failure: Failure) Error![]const u8 {
    if (std.mem.eql(u8, failure.status, "value") and snapshot.equivalent(failure.actual, failure.expected)) return "";
    var reason: []const u8 = "";
    if (std.mem.eql(u8, failure.status, "value")) {
        reason = try std.fmt.allocPrint(context.allocator, "expected {s}, got {s}", .{
            try describeValue(context.allocator, failure.expected),
            try describeValue(context.allocator, failure.actual),
        });
        // ERROR-TRACE-3: a test that returned an `Err` says where it came from.
        if (errorValue(failure.actual) and failure.trace.len != 0) {
            const trace = try stripRoot(context.allocator, std.mem.trimEnd(u8, failure.trace, "\n"), failure.project_source, failure.root);
            reason = try std.fmt.allocPrint(context.allocator, "{s}\n{s}", .{ reason, trace });
        }
    } else {
        reason = try stripRoot(context.allocator, failure.diagnostics, failure.project_source, failure.root);
    }
    if (failure.output.len == 0) return reason;
    const captured = try stripRoot(context.allocator, failure.output, failure.project_source, failure.root);
    if (reason.len == 0) return captured;
    return std.fmt.allocPrint(context.allocator, "{s}\n{s}", .{ reason, captured });
}

/// Whether a decoded test value is the error case of a `Result`.
fn errorValue(value: std.json.Value) bool {
    if (value != .object) return false;
    const case = value.object.get("case") orelse return false;
    return case == .string and std.ascii.eqlIgnoreCase(case.string, "err");
}

/// Render one typed JSON expectation value for a failure line: a string keeps
/// its source spelling, a Boolean is `true`/`false`, and an aggregate is compact JSON.
fn describeValue(allocator: std.mem.Allocator, value: std.json.Value) Error![]const u8 {
    return switch (value) {
        .string => |text| allocator.dupe(u8, text),
        .bool => |flag| if (flag) "true" else "false",
        else => std.json.Stringify.valueAlloc(allocator, value, .{}),
    };
}

/// Rewrite the materialized project directory back to the user's source root in
/// diagnostic text; a source path with no directory is returned unchanged.
fn stripRoot(allocator: std.mem.Allocator, text: []const u8, project_source: []const u8, root: []const u8) Error![]const u8 {
    const directory = std.fs.path.dirname(project_source) orelse return allocator.dupe(u8, text);
    return std.mem.replaceOwned(u8, allocator, text, directory, root);
}

// spec: NATIVE-TEST-8
// spec-case: NATIVE-TEST-10
test "a failed expectation reports both values and any captured guest output" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const mismatch = try failureReason(context, .{
        .status = "value",
        .expected = .{ .bool = true },
        .actual = .{ .bool = false },
        .diagnostics = "",
        .output = "",
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expectEqualStrings("expected true, got false", mismatch);
    const typed = try failureReason(context, .{
        .status = "value",
        .expected = .{ .string = "9" },
        .actual = .{ .string = "3" },
        .diagnostics = "",
        .output = "",
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expectEqualStrings("expected 9, got 3", typed);
    const trapped = try failureReason(context, .{
        .status = "trap",
        .expected = .null,
        .actual = .null,
        .diagnostics = "R_ASSERT: x should be two\n  in main::test_x at main.my:3:5\n",
        .output = "debug-marker\n",
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expect(std.mem.indexOf(u8, trapped, "R_ASSERT: x should be two") != null);
    try std.testing.expect(std.mem.indexOf(u8, trapped, "in main::test_x at main.my:3:5") != null);
    try std.testing.expect(std.mem.indexOf(u8, trapped, "debug-marker") != null);
    const passed = try failureReason(context, .{
        .status = "value",
        .expected = .{ .bool = true },
        .actual = .{ .bool = true },
        .diagnostics = "",
        .output = "",
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expectEqualStrings("", passed);
}

// spec: ERROR-TRACE-3
test "a test that returned an Err reports its error return trace after the values" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var failed: std.json.ObjectMap = .empty;
    try failed.put(context.allocator, "case", .{ .string = "err" });
    try failed.put(context.allocator, "value", .{ .string = "empty" });
    const trace = "  /snapshot/project/main.my:3:16  main::parse  Err(...) created\n  /snapshot/project/main.my:7:9   main::test_parse  ? propagated\n";
    const reported = try failureReason(context, .{
        .status = "value",
        .expected = .{ .bool = true },
        .actual = .{ .object = failed },
        .diagnostics = "",
        .output = "",
        .trace = trace,
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expectEqualStrings(
        \\expected true, got {"case":"err","value":"empty"}
        \\  /work/project/main.my:3:16  main::parse  Err(...) created
        \\  /work/project/main.my:7:9   main::test_parse  ? propagated
    , reported);
    // A value that is not an `Err` leaves a stale trace out of the report.
    const mismatch = try failureReason(context, .{
        .status = "value",
        .expected = .{ .bool = true },
        .actual = .{ .bool = false },
        .diagnostics = "",
        .output = "",
        .trace = trace,
        .project_source = "/snapshot/project/main.my",
        .root = "/work/project",
    });
    try std.testing.expectEqualStrings("expected true, got false", mismatch);
}

/// Per-case outcome slots bundled for planning. `pure` marks a case that is both
/// effect-cacheable and signature-pure; `replayed` marks a case whose outcome was
/// served from the opt-in pure record without executing. Both live beside the
/// reported results instead of inside `receipts.Result` to preserve its wire shape.
const Outcomes = struct { results: []receipts.Result, pure: []bool, replayed: []bool };

const Pending = struct {
    graph: *Graph,
    selected: std.json.Value,
    dependencies: []const []const u8,
    kind: Kind,
    slot: usize,
};
/// A planned case either runs once as a correctness test or is sampled.
const Kind = enum { tests, benchmarks };

const Group = struct {
    graph: *Graph,
    symbols: std.StringHashMapUnmanaged(void) = .empty,
    names: std.ArrayList([]const u8) = .empty,
};

/// The contract identity of one test module, memoized for the tests that share it.
fn moduleContract(context: fs.Context, production: std.json.Value, memo: *std.StringHashMapUnmanaged([]const u8), module: []const u8) Error![]const u8 {
    if (memo.get(module)) |known| return known;
    const identity = try contracts.contractIdentity(context.allocator, production, &.{module});
    try memo.put(context.allocator, module, identity);
    return identity;
}
/// The module part of a `module::name` qualified test identity.
fn testModuleName(allocator: std.mem.Allocator, qualified: []const u8) Error![]const u8 {
    const at = std.mem.indexOf(u8, qualified, "::") orelse return error.UnknownFunction;
    return allocator.dupe(u8, qualified[0..at]);
}
// spec-case: MEMORY-CEILING-3
test "an explicit fan-out width outranks the environment, which outranks the derived default" {
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try std.testing.expectEqual(@as(?usize, null), try requested(null, &environ));
    try environ.put(budget.jobs_variable, "4");
    try std.testing.expectEqual(@as(?usize, 4), try requested(null, &environ));
    try std.testing.expectEqual(@as(?usize, 9), try requested(9, &environ));
    try environ.put(budget.jobs_variable, "");
    try std.testing.expectEqual(@as(?usize, null), try requested(null, &environ));
    try environ.put(budget.jobs_variable, "0");
    try std.testing.expectError(error.InvalidMemoryLimit, requested(null, &environ));
}
/// Declaration contracts the stand-in compiler reports.
const fake_contracts = "{\"version\":\"interface-contracts-v2\",\"modules\":[{\"name\":\"production\",\"declarations\":[{\"name\":\"value\",\"kind\":\"function\",\"generics\":\"\",\"signature\":\"def() -> i64 effects()\"," ++
    "\"permissions\":\"effects=;mutates=;origin=unknown\"}]}]}";
/// Checked facts the stand-in compiler's session writes.
const fake_graph =
    "{\"abi\":\"test-abi\"," ++
    "\"schema\":\"{\\\"functions\\\":[],\\\"types\\\":[]}\"," ++
    "\"functions\":[{\"name\":\"main::x\",\"symbol\":\"sym\"," ++
    "\"test_dependencies\":{\"implementation_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\"," ++
    "\"dependencies\":[],\"cacheable\":true,\"reasons\":[]}}]}";
/// A stand-in compiler that logs every call to `log`, answers
/// `list-interfaces` with `fake_contracts` and serves a `native-test-compile`
/// session that writes `fake_graph` for facts and lowering requests.
fn fakeCompiler(context: fs.Context, root: []const u8, log: []const u8) ![]const u8 {
    const script = try std.fs.path.join(context.allocator, &.{ root, "fake-compiler" });
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(context.allocator, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"");
    try text.appendSlice(context.allocator, log);
    try text.appendSlice(context.allocator, "\"\ncase \"$1\" in\n  list-interfaces) printf '%s\\n' '");
    try text.appendSlice(context.allocator, fake_contracts);
    try text.appendSlice(context.allocator, "' ;;\n  native-test-compile)\n" ++
        "    while read -r action first second; do\n" ++
        "      case \"$action\" in\n" ++
        "        facts) printf '%s' '" ++ fake_graph ++ "' > \"$first\" ;;\n" ++
        "        lower) printf '%s' '" ++ fake_graph ++ "' > \"$second\" ;;\n" ++
        "        quit) exit 0 ;;\n" ++
        "      esac\n" ++
        "      printf '%s\\n' '{\"version\":\"native-test-compile-v1\",\"action\":\"ok\",\"status\":0,\"failure\":null,\"lowered_functions\":0,\"emitted_fragments\":0}'\n" ++
        "    done\n    ;;\nesac\n");
    var file = try std.Io.Dir.createFileAbsolute(context.io, script, .{ .permissions = .executable_file });
    defer file.close(context.io);
    try file.writeStreamingAll(context.io, text.items);
    return script;
}
// spec-case: NATIVE-TEST-5
test "one prepared project graph is shared per selected provider identity" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const production_path = try std.fs.path.join(context.allocator, &.{ root, "production.my" });
    try context.write(entry, "module main;\n");
    try context.write(production_path, "module production;\n");
    const captured = try snapshot.capture(context, entry);
    const log = try std.fs.path.join(context.allocator, &.{ root, "compiler.log" });
    const script = try fakeCompiler(context, root, log);
    var parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, fake_contracts, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const session: sessions.Session = .{
        .context = context,
        .options = .{ .source = entry, .flags = .{ .no_cache = true } },
        .compiler = script,
        .tools = .{ .zig = "/bin/true", .qbe = "/bin/true" },
        .hashes = .{ "", "", "" },
        .environment = .{ .hash = "", .cacheable = true },
        .directory = root,
        .temporary = root,
        .source = captured,
    };
    var graphs: Graphs = .{ .allocator = context.allocator, .session = session, .captured = captured, .production = parsed.value, .directory = "" };
    defer graphs.deinit();
    const ordinary: cases.Case = .{ .name = "main::test_ordinary", .function = .null, .arguments = .null, .expected = .null, .providers = .null, .settings = .null };
    const ordinary_first = try graphs.get(ordinary);
    const ordinary_second = try graphs.get(ordinary);
    try std.testing.expectEqual(ordinary_first, ordinary_second);
    var first_providers: std.json.ObjectMap = .empty;
    try first_providers.put(context.allocator, "production.my", .{ .string = "module production; // one" });
    const first_provider: cases.Case = .{ .name = "main::test_provider_one", .function = .null, .arguments = .null, .expected = .null, .providers = .{ .object = first_providers }, .settings = .null };
    const provider_first = try graphs.get(first_provider);
    const provider_second = try graphs.get(first_provider);
    try std.testing.expectEqual(provider_first, provider_second);
    var second_providers: std.json.ObjectMap = .empty;
    try second_providers.put(context.allocator, "production.my", .{ .string = "module production; // two" });
    const second_provider: cases.Case = .{ .name = "main::test_provider_two", .function = .null, .arguments = .null, .expected = .null, .providers = .{ .object = second_providers }, .settings = .null };
    const provider_distinct = try graphs.get(second_provider);
    try std.testing.expect(provider_first != provider_distinct);
    const calls = try context.read(log);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, calls, "native-test-compile"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, calls, "list-interfaces"));
}

// spec-case: NATIVE-TEST-PLAN-2
test "a module's contract identity is computed once for all of its tests" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const production = (try std.json.parseFromSlice(std.json.Value, context.allocator, fake_contracts, .{ .allocate = .alloc_always })).value;
    var memo: std.StringHashMapUnmanaged([]const u8) = .empty;
    const first = try moduleContract(context, production, &memo, "production");
    const second = try moduleContract(context, production, &memo, "production");
    try std.testing.expectEqual(first.ptr, second.ptr);
    try std.testing.expectEqualStrings(try contracts.contractIdentity(context.allocator, production, &.{"production"}), first);
    try std.testing.expectEqual(@as(u32, 1), memo.count());
    try std.testing.expectError(error.InvalidContracts, moduleContract(context, production, &memo, "absent"));
    try std.testing.expectEqual(@as(u32, 1), memo.count());
}
// spec: NATIVE-TEST-OVERLAP-1
test "the production check starts beside the declaration check unless a fixture can select another graph" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    try context.write(entry, "module main;\n");
    const captured = try snapshot.capture(context, entry);
    const log = try std.fs.path.join(context.allocator, &.{ root, "compiler.log" });
    const session: sessions.Session = .{
        .context = context,
        .options = .{ .source = entry, .flags = .{ .no_cache = true } },
        .compiler = try fakeCompiler(context, root, log),
        .tools = .{ .zig = "/bin/true", .qbe = "/bin/true" },
        .hashes = .{ "", "", "" },
        .environment = .{ .hash = "", .cacheable = true },
        .directory = root,
        .temporary = root,
        .source = captured,
    };
    const early = speculate(session, captured, "") orelse return error.TestUnexpectedResult;
    const production = try session.interfaceCheck(captured.entry_path);
    var graphs: Graphs = .{ .allocator = context.allocator, .session = session, .captured = captured, .production = production, .directory = "", .early = early };
    defer graphs.deinit();
    const ordinary: cases.Case = .{ .name = "main::test_ordinary", .function = .null, .arguments = .null, .expected = .null, .providers = .null, .settings = .null };
    _ = try graphs.get(ordinary);
    const calls = try context.read(log);
    // One session, started before the declaration check, prepared the graph.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, calls, "native-test-compile"));
    try std.testing.expect(std.mem.indexOf(u8, calls, "native-test-compile").? < std.mem.indexOf(u8, calls, "list-interfaces").?);
    // A session the selection never used is killed without a word.
    abandon(speculate(session, captured, ""));
    // Only a configuration that names no provider fixture lets the check start early.
    const cases_path = try std.fs.path.join(context.allocator, &.{ root, "cases.json" });
    try context.write(cases_path, "{\"main::test_x\":{\"expected\":\"true\"}}");
    try std.testing.expect(providerFree(context, cases_path));
    try context.write(cases_path, "{\"main::test_x\":{\"providers\":{\"production.my\":\"module production\\n\"}}}");
    try std.testing.expect(!providerFree(context, cases_path));
    try context.write(cases_path, "{not json");
    try std.testing.expect(!providerFree(context, cases_path));
}

/// Print the `--affected` selection: how many tests it kept, and every
/// discovered test it dropped as unchanged since the reference. The text goes
/// to stderr so `--json`'s stdout report stays machine-readable.
fn reportAffected(context: fs.Context, selection: language.affected_tests.Selection, reference: []const u8) Error!void {
    const stderr = std.Io.File.stderr();
    var kept: usize = 0;
    for (selection.keep) |keep| kept += @intFromBool(keep);
    const summary = if (selection.derived)
        try std.fmt.allocPrint(context.allocator, "affected: {d} selected, {d} skipped against {s}\n", .{ kept, selection.skipped.len, reference })
    else
        try std.fmt.allocPrint(context.allocator, "affected: project could not be checked; running all {d} discovered tests\n", .{kept});
    try stderr.writeStreamingAll(context.io, summary);
    for (selection.skipped) |name| {
        try stderr.writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "skipped {s}: no changed declaration is reachable\n", .{name}));
    }
}

/// What one invocation's report prints: each case's result, whether it was
/// replayed from a receipt, and the project sources the check loaded, which a
/// directory run uses to prove no test-declaring source went unloaded.
const Report = struct { results: []const receipts.Result, replayed: []const bool, loaded: []const []const u8 };
fn report(context: fs.Context, printed: Report, json: bool) Error!u8 {
    const results = printed.results;
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var cached: usize = 0;
    var executed: usize = 0;
    for (results, printed.replayed) |result, was_replayed| {
        const was_passed = std.mem.eql(u8, result.status, "passed");
        const was_failed = std.mem.eql(u8, result.status, "failed");
        if (was_passed) passed += 1;
        if (was_failed) failed += 1;
        if (std.mem.eql(u8, result.status, "skipped")) skipped += 1;
        if (std.mem.eql(u8, result.status, "cached")) cached += 1;
        if ((was_passed or was_failed) and !was_replayed) executed += 1;
        if (!json) try std.Io.File.stdout().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "{s} {s}{s}{s}\n", .{
            result.status, result.name, if (result.reason.len != 0) ": " else "", result.reason,
        }));
    }
    const output = if (json) try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = "native-tests-v1",
        .tests = results,
        .passed = passed,
        .failed = failed,
        .skipped = skipped,
        .cached = cached,
        .executed = executed,
        .modules = printed.loaded,
    }, .{}) else try std.fmt.allocPrint(context.allocator, "{d} passed, {d} cached, {d} failed, {d} skipped", .{ passed, cached, failed, skipped });
    try std.Io.File.stdout().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "{s}\n", .{output}));
    if (failed != 0) return 1;
    return if (passed + cached != 0) 0 else 3;
}
