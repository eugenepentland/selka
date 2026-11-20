//! `selka-core test FILE.selka [--release] [--filter S] [--json]` (docs/design/new-core-s1.md §9).
//!
//! The file is checked with the old runner's stub `main` appended (so a library checks as a
//! program), its tests are discovered by the old rule, and the supported ones are built into
//! **one executable** whose entry serves a request naming each trial's table row
//! (`test_runner_batch.zig`). Tests share its processes, each in its own forked trial, so
//! a trap or a hang ends one test, not the file (`test_runner_execute.zig`).
//!
//! Grading is per test function. Before the real build every test is built *alone* from its
//! own root (`build.buildRoots`), which follows exactly the functions that test can reach: a
//! test that reaches a construct the new core refuses is reported `unsupported`, with the
//! refusal's reason and position, and left out of the executable. The tests that survive
//! are built together. If the backend (emission or the C toolchain) then rejects the
//! combined module, each test is built alone again to find the culprits, which are reported
//! (`unsupported` for an emission refusal, `failed` for a toolchain error) while the rest
//! still run.
const std = @import("std");
const product = @import("selka").product;
const fast_blake3 = @import("fast_blake3.zig");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const pipeline = @import("pipeline.zig");
const discover = @import("test_runner_discover.zig");
const examples = @import("selka").docstring_example_source;
const language = @import("selka");
const entry = @import("test_runner_entry.zig");
const report = @import("test_runner_report.zig");
const typed = @import("selka").typed;
const property = @import("test_runner_property.zig");
const property_types = @import("property_types.zig");
const property_schema = @import("property_schema.zig");
const run_tests = @import("test_runner_execute.zig");
const root_share = @import("test_runner_shared.zig");
const batch_entry = @import("test_runner_batch.zig");
const directory_runner = @import("test_runner_directory.zig");
const receipt = @import("test_runner_receipt.zig");
const shared_store = @import("test_shared_store.zig");
const test_keys = @import("test_runner_identity.zig");
const callable_digest = @import("callable_digest.zig");
const tool_identity = @import("tool_identity.zig");
const zig_lookup = @import("zig_lookup.zig");
const tool_ticket = @import("tool_ticket.zig");
const planner = @import("selka").cache_plan_adapter;
const case_settings = @import("test_runner_cases.zig");
const affected = @import("test_runner_affected.zig");
const v = @import("property_value.zig");
const test_contracts = @import("test_runner_contracts.zig");
const graph_cache = @import("test_runner_graph.zig");
const canonical_facts = @import("test_runner_facts.zig");
const key_work = @import("test_runner_work.zig");
const stage_store = @import("stage_store.zig");
const stage_metrics = @import("stage_metrics.zig");
const lowering_cache = @import("lowering_cache.zig");
const engine_run = @import("test_runner_engine.zig");
const decide = @import("test_runner_decide.zig");
const portable = @import("test_runner_portable.zig");

/// The old runner's stub, appended to a file that defines no `main` of its own.
pub const check_stub = language.check_directory.test_stub;

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = property.Error;

/// What the command line asked for.
pub const Options = options_module.Options;
const options_module = @import("test_runner_options.zig");

const Selected = run_tests.Selected;
const case_expectation = run_tests.expectation;
/// A test's identity work: `scratch` is an arena it may leave allocations in,
/// `prebuilt` the test's reachable functions when `classify` already built them, and
/// `source_path` the entry's root-relative path its key names (RECEIPT-PATHS-1).
const IdentityResources = struct { scratch: std.mem.Allocator, io: std.Io, prebuilt: ?@import("ir.zig").Module = null, program: ?*portable.Program = null };
/// What selection and execution share: the run's context, its base key, a directory run's test process permits when the entry
/// runs in its process, and whether the group's records stay out of the shared tier (provider overlays and docstring examples).
const SelectionContext = struct { receipt: receipt.Context, base: [32]u8, permits: ?*root_share.Permits = null, keys: root_share.KeySources = .{}, private: bool = false, rule: ?*key_work.RuleCounters = null };

/// Check, discover, build and run the tests of `options.path`, print the report, and return
/// the process exit status: 0 ok, 1 a test failed or the file does not check, 2 unreadable
/// or an invalid cases file or provider fixture, 3 nothing selected or every selected test skipped.
pub fn run(init: std.process.Init, requested: Options) Error!u8 {
    @import("selka").profile_history.setEntry(requested.path);
    @import("selka").friction_session.setEntry(requested.path);
    var options = requested;
    options.shared_cache = try options_module.resolveShared(init, requested.shared_cache);
    const engine_shadow = engine_run.begin(init.gpa, init.io, init.environ_map, options.build.cache, options.shared_cache);
    if (engine_shadow) |state| @import("selka").engine_session.attach(state);
    defer if (engine_shadow) |state| engine_run.end(state, init.io);
    const compilation_init = try @import("compiler_sharing.zig").prepare(init, requested.build.show.verify_cache or requested.build.show.compiler_cache_disabled);
    // Each entry's check holds the work directory while its stores are open (`finishHeld`), so no retirement of a compiler's
    // ownership store runs under it; once the run has released its holds, the identities no build keeps are retired.
    const outcome = runRequested(compilation_init, options);
    const retention = @import("work_retention.zig");
    _ = retention.removeLegacyOwnership(init.arena.allocator(), init.io, options.build.cache);
    return outcome catch |err| {
        if (err == error.ComponentUnavailable) return 2;
        if (err == error.SourceChanged) {
            try writeAll(init, std.Io.File.stderr(), "error: SourceChanged: a property campaign input changed during execution\n");
            return 1;
        }
        return err;
    };
}

fn runRequested(init: std.process.Init, requested: Options) Error!u8 {
    if (directory_runner.selected(init.io, requested.path)) return directory_runner.run(init, requested, runRoot);
    // A child a directory run started carries its parent's tool ticket hint (`test_runner_directory.zig`).
    const child = if (init.environ_map.get(tool_ticket.hint)) |value| value.len != 0 else false;
    return (try runEntry(init, requested, .{ .directory_child = child })).?;
}

/// A directory run's root, run in the directory run's process (NEW-CORE-TEST-UNION-1):
/// the JSON report a child would print, and the child's exit status.
fn runRoot(init: std.process.Init, requested: Options, directed: root_share.Directed) Error!?root_share.Outcome {
    var report_bytes: std.ArrayList(u8) = .empty;
    var options = requested;
    options.json = true;
    const code = try runEntry(init, options, .{ .directed = directed, .report = &report_bytes }) orelse return null;
    return .{ .code = code, .bytes = report_bytes.items };
}

/// What a directory run handed an entry's run, and where its report goes: stdout
/// unless a buffer is given.
const Setup = struct {
    directed: ?root_share.Directed = null,
    report: ?*std.ArrayList(u8) = null,
    /// Whether a directory run started this entry's process as one of its roots.
    directory_child: bool = false,

    /// The directory run's test process permits, for an entry it runs in process.
    fn permits(self: Setup) ?*root_share.Permits {
        const directed = self.directed orelse return null;
        return directed.permits;
    }

    /// The module paths whose examples this entry owns in a directory run; null owns every module.
    fn exampleModules(self: Setup) ?[]const []const u8 {
        const directed = self.directed orelse return null;
        return directed.example_modules;
    }

    /// The entry's share of its directory run's shared check, when it has one.
    fn view(self: Setup) ?root_share.View {
        const directed = self.directed orelse return null;
        return directed.view;
    }

    /// What key derivation takes from the check this entry's tests come from (stage 4 of the test-loop plan): the declaration
    /// prefix and the engine's checked-body parts of this entry's share of a shared check, or of `session`, its own check.
    /// The parts key each function's lowering by its `module-check` record, as a build's do, so no body tree is hashed;
    /// `SELKA_ENGINE_DECIDE_LOWERING=0` turns them off and keys every function by its tree (the oracle).
    fn keySources(self: Setup, session: *const frontend.Session, environment: *const std.process.Environ.Map) root_share.KeySources {
        if (self.view()) |shared_view| return .{ .catalog = shared_view.catalog, .parts = shared_view.parts };
        if (!@import("frontend_shadow.zig").decidesLowering(environment)) return .{};
        return .{ .parts = session.bodyParts() };
    }
};

/// Print `text` as the run's report.
fn emit(init: std.process.Init, setup: Setup, text: []const u8) Error!void {
    if (setup.report) |buffer| return buffer.appendSlice(init.arena.allocator(), text);
    try writeAll(init, std.Io.File.stdout(), text);
}

/// An entry read, resolved and configured, its cases loaded, its toolchain known and
/// its receipts keyed: what checking it needs.
const Ready = struct { context: receipt.Context, base: [32]u8, native_inputs: []const receipt.Dependency, bytes: []const u8, cases: case_settings.File };

/// How an entry's setup and replay end: with its exit status (null for a
/// `replay_only` run that found nothing to replay), or ready to check.
const Started = union(enum) { done: ?u8, ready: Ready };

/// Read, resolve and configure the entry and replay its recorded report when one
/// holds.
fn start(init: std.process.Init, requested: Options, setup: Setup) Error!Started {
    try validateShared(init, requested);
    var options = requested;
    const allocator = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, options.path, allocator, .limited(64 << 20)) catch |err| return .{ .done = try unreadable(init, options.path, @errorName(err)) };
    var located = project_entry.resolveUnder(allocator, init.io, options.path, options.controls.scope.importRoot(options.path), &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return .{ .done = project_entry.status(err) };
    };
    located.prefer_standard_sources = options.build.show.codegen.local_stdlib;
    // The local files a standard module hides are named once, before anything else a test prints (not under `--json`).
    located.shadowed = if (located.prefer_standard_sources) &.{} else try project_entry.shadowedIn(allocator, init.io, located.root);
    if (!options.json and located.shadowed.len != 0) {
        var warned: std.ArrayList(u8) = .empty;
        try project_entry.appendShadowedStandardWarnings(located.shadowed, allocator, &warned);
        std.Io.File.stderr().writeStreamingAll(init.io, warned.items) catch return error.WriteFailed;
    }
    // A malformed byte ceiling or a frame budget it cannot back is refused like a usage error.
    if (!try applyLimits(init, &options, located)) return .{ .done = 2 };
    // The project's `links` come first, then the command line's (`Entry.linkSources`).
    options.build.links = located.linkSources(allocator, init.io, options.build.links, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return .{ .done = project_entry.status(err) };
    };
    // So are its `include` folders, on the include path of that C as a build puts them (`Entry.includeFolders`).
    options.build.show.codegen.device.include = try located.includeFolders(allocator, options.build.show.codegen.device.include);
    // An invalid cases file or provider fixture is a setup failure, status 2 (the old core's).
    const configured_cases = try configuredCases(init, &options, located) orelse return .{ .done = 2 };
    options.controls.cases = configured_cases.path;
    const cache_plan = if (setup.directed) |directed| directed.cache_plan orelse try bindPlan(init) else try bindPlan(init);
    const scoped_examples = if (setup.directed) |directed| directed.example_modules != null else false;
    const replayed = if (scoped_examples) null else if (setup.directed) |directed|
        try directedReplay(init, options, located, configured_cases.bytes, directed.guest, cache_plan)
    else
        try cachedReplay(init, options, located, configured_cases.bytes, cache_plan);
    if (replayed) |cached| return .{ .done = try emitted(init, setup, cached) };
    const guest = if (setup.directed) |directed| directed.guest else try guestTool(init, options) orelse return .{ .done = 1 };
    // Spawn the exact executable whose content and library tree were captured.
    options.build.zig = guest.path;
    const context: receipt.Context = .{
        .arena = allocator,
        .io = init.io,
        .environment = init.environ_map,
        .options = options,
        .entry = located,
        .case_bytes = configured_cases.bytes,
        .identity = .{ .tool = guest, .cache_plan = cache_plan },
    };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    const base = if (options.properties.policy == .indexed_v1) (try receipt.campaignSettings(context, &native_inputs)).? else try receipt.settings(context, &native_inputs);
    if (!scoped_examples) if (try replayRun(context, base)) |cached| return .{ .done = try emitted(init, setup, cached) };
    if (setup.directed) |directed| if (directed.replay_only) return .{ .done = null };
    return .{ .ready = .{ .context = context, .base = base, .native_inputs = native_inputs.items, .bytes = bytes, .cases = configured_cases } };
}

/// Print a replayed report and answer its status, 0.
fn emitted(init: std.process.Init, setup: Setup, cached: receipt.Replay) Error!u8 {
    decide.observeReplay(cached);
    try writeAll(init, std.Io.File.stderr(), cached.warnings);
    try emit(init, setup, cached.report);
    return 0;
}

/// `run` for one entry. A directed entry takes the toolchain its directory run
/// identified and, when given, its share of the run's shared check instead of
/// checking alone.
fn runEntry(init: std.process.Init, requested: Options, setup: Setup) Error!?u8 {
    return switch (try start(init, requested, setup)) {
        .done => |status| status,
        .ready => |ready| try finishHeld(init, ready, setup),
    };
}

/// `finish` under a hold of the work directory, kept while the entry's stores (the ownership store among them) are open. The
/// hold follows `start`, so an entry that is refused by name (unreadable, missing, a directory) creates no cache directory.
fn finishHeld(init: std.process.Init, ready: Ready, setup: Setup) Error!u8 {
    const retention = @import("work_retention.zig");
    const hold = try retention.hold(init.arena.allocator(), init.io, ready.context.options.build.cache);
    defer hold.release();
    return finish(init, ready, setup);
}

/// Check the ready entry (or take its share of a shared check), then discover,
/// select, build and run its tests, and report them.
fn finish(init: std.process.Init, ready: Ready, setup: Setup) Error!u8 {
    const options = ready.context.options;
    const located = ready.context.entry;
    const context = ready.context;
    const base = ready.base;
    const bytes = ready.bytes;
    const configured_cases = ready.cases;
    const allocator = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    const view = setup.view();
    var session = frontend.Session.init(init.gpa, init.io, located.root);
    defer session.deinit();
    defer observeSession(&session, located.path);
    located.configure(&session);
    if (view == null) {
        try session.enableCache(init.gpa, options.build.cache);
        try session.enableSharedCache(init.environ_map);
    }
    const entry_text: EntryText = .{ .overlay = try headerlessTest(allocator, located, bytes), .stub = !definesMain(bytes) };
    entry_text.apply(&session, entry_text.overlay);
    const provider_sets = case_settings.providerSets(allocator, configured_cases, options.filter) catch |err| return casesFailure(init, err);
    if (provider_sets.len != 0) if (try validateProviders(init, options, located, entry_text, provider_sets)) |status| return status;
    // NATIVE-TEST-5: with providers, an unselected production body is never checked; the
    // first provider graph then answers discovery, and a case without providers fails.
    var first_provider = frontend.Session.init(init.gpa, init.io, located.root);
    defer first_provider.deinit();
    const base_checked: ?frontend.Checked = if (view) |share| share.checked else checkEntry(&session, allocator, located, &problems) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => if (provider_sets.len == 0) return failWith(init, problems.items, 1) else null,
    };
    const checked = base_checked orelse try providerGraph(init, options, located, entry_text, provider_sets[0], &first_provider) orelse return failWith(init, problems.items, 1);
    if (base_checked != null) try writeAll(init, std.Io.File.stderr(), problems.items);
    const loaded: Loaded = if (view) |share| .{ .modules = share.modules } else try Loaded.of(allocator, &session);
    var before: std.ArrayList(receipt.Dependency) = .empty;
    try before.appendSlice(allocator, try checkedInputs(context, loaded, entry_text.overlay, bytes));
    try before.appendSlice(allocator, ready.native_inputs);
    // A shared check takes only roots whose configuration names no policy and no
    // interface files, for which validation has nothing to check.
    if (view == null) located.validate(allocator, &session, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return project_entry.status(err);
    };
    const entry_module = if (view != null) located.name else moduleName(checked.program, located.name);
    const blocks = try exampleBlocks(allocator, loaded, entry_module, setup.exampleModules());
    const all_cases = try discoverLoaded(allocator, checked, entry_module, loaded);
    case_settings.validate(configured_cases, try exampleCaseNames(allocator, all_cases, blocks)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(allocator, "error: test cases: {s}\n", .{@errorName(err)}));
        return 2;
    };
    const scoped = try ownedCases(allocator, all_cases, .{ .loaded = loaded, .entry_module = entry_module, .entry_path = try receipt.entryPath(context), .cases = configured_cases, .skipped = options.controls.scope.skipped });
    const selection = switch (try chooseCases(init, options, located, checked, scoped)) {
        .kept => |kept| kept,
        .exit => |status| return status,
    };
    const groups = case_settings.groups(allocator, configured_cases, selection) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(allocator, "error: test providers: {s}\n", .{@errorName(err)}));
        return 2;
    };
    var collected: Collected = .{ .before = before };
    try collected.warnings.appendSlice(allocator, checked.allocation_warnings);
    try addSources(allocator, &collected.sources, context, loaded);
    const rule = try allocator.create(key_work.RuleCounters);
    rule.* = .{};
    const selection_context: SelectionContext = .{ .receipt = context, .base = base, .permits = setup.permits(), .keys = setup.keySources(&session, init.environ_map), .rule = rule };
    const shared: GroupRun = .{ .init = init, .selection = selection_context, .session = &session, .base_checked = base_checked, .discovery = checked, .entry = entry_text, .cases = configured_cases };
    for (groups) |group| {
        if (base_checked == null and group.providers.len == 0) return failWith(init, problems.items, 1);
        if (try shared.runGroup(group, entry_module, &collected)) |status| return status;
    }
    if (try runExamples(shared, blocks, &collected)) |status| return status;
    before = collected.before;
    const chosen = collected.chosen;
    const sources = collected.sources;
    try receipt.validatePlan(context);
    const unchanged = try receipt.unchanged(context, before.items) and try receipt.toolUnchanged(context);
    if (!unchanged) {
        try writeAll(init, std.Io.File.stderr(), "error: SourceChanged: a test input changed during checking or execution\n");
        return 1;
    }
    const verdicts = try allocator.alloc(report.Verdict, chosen.items.len);
    var successful = chosen.items.len != 0;
    for (chosen.items, verdicts) |item, *verdict| {
        verdict.* = item.verdict;
        verdict.cache = try cacheExplanation(allocator, item, context);
        successful = successful and item.identity != null and (item.verdict.status == .passed or item.verdict.status == .cached);
    }
    try attachExecutionKeys(allocator, verdicts, collected.executions.items);
    const replayable = setup.directed == null or setup.directed.?.example_modules == null;
    const storable = replayable and options.controls.scope.against == null and options.properties.policy == .legacy and successful and unchanged;
    attachWork(verdicts, collected.works.items);
    // The stored report is rendered before the entry publishes; a replay keeps none of its work (`receipt.renderReplay`).
    const stored = if (storable) try report.jsonSources(allocator, verdicts, sources.items) else "";
    decide.observeAttached(.{
        .context = context,
        .base = base,
        .dependencies = before.items,
        .chosen = chosen.items,
        .verdicts = verdicts,
        .executions = collected.executions.items,
        .report = if (storable) .{ .json = stored, .warnings = collected.warnings.items, .diagnostics = if (view) |share| share.diagnostics else problems.items, .examples = try exampleModules(allocator, blocks) } else null,
    });
    const json = try publishedJson(allocator, options.json, .{ .verdicts = verdicts, .sources = sources.items, .works = collected.works.items, .rule = rule.snapshot() });
    // The `work:` line is a plain listing's observation (NEW-CORE-TEST-WORK-1): a
    // `--json` process only reports the counts, so a directory run's children never
    // consume the previous values its parent compares against.
    if (!options.json) @import("test_runner_counts.zig").compare(allocator, init.io, options.build.cache, @tagName(options.build.mode), verdicts);
    const out = if (options.json) json else try report.text(allocator, verdicts);
    try emit(init, setup, out);
    try siblingHint(init, loaded, located, verdicts.len, setup);
    return report.exitStatus(verdicts);
}

/// The files of the modules whose docstring examples a run tested, as `name:` lines: their report reads them by their bytes
/// (D-TL6-8 of experiments/test-loop-20261109/DECISIONS.md), since an example's key holds the lines it maps back to.
fn exampleModules(a: std.mem.Allocator, blocks: []const examples.Block) error{OutOfMemory}![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (blocks) |block| try text.print(a, "{s}:\n", .{std.fs.path.basename(block.src.path)});
    return text.items;
}

/// The docstring example blocks of the modules a check loaded, as `selka test`
/// runs them. A directory run gives each entry the module paths it owns, so one
/// module's examples run once; null owns every module.
pub fn exampleBlocks(a: std.mem.Allocator, loaded: Loaded, entry_module: []const u8, owners: ?[]const []const u8) Error![]const examples.Block {
    var found: std.ArrayList(examples.Block) = .empty;
    if (loaded.single()) {
        const src = loaded.session.?.single.?.src;
        if (std.mem.indexOf(u8, src.bytes, ">>> ") == null) return &.{};
        return examples.extract(a, entry_module, try exampleSource(a, src, loaded.session.?));
    }
    for (loaded.modules) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        if (std.mem.indexOf(u8, module.src.bytes, ">>> ") == null) continue;
        if (owners) |paths| {
            var owned = false;
            for (paths) |path| owned = owned or std.mem.eql(u8, path, module.src.path);
            if (!owned) continue;
        }
        try found.appendSlice(a, try examples.extract(a, module.name, if (loaded.session) |session| try exampleSource(a, module.src, session) else module.src));
    }
    return found.items;
}

fn exampleSource(a: std.mem.Allocator, src: @import("selka").source.Source, session: *const frontend.Session) Error!@import("selka").source.Source {
    if (session.entry.suffix.len == 0) return src;
    if (session.single == null and !std.mem.eql(u8, src.path, session.entry.file)) return src;
    if (!std.mem.endsWith(u8, src.bytes, session.entry.suffix)) return src;
    return @import("selka").source.Source.init(a, src.path, src.bytes[0 .. src.bytes.len - session.entry.suffix.len]);
}

fn exampleCase(a: std.mem.Allocator, block: examples.Block) Error!discover.Case {
    return .{ .name = try examples.name(a, block), .function = @fromBackingInt(0), .shape = .boolean, .other_parameters = 0, .streams = &.{} };
}

fn exampleCaseNames(a: std.mem.Allocator, cases: []const discover.Case, blocks: []const examples.Block) Error![]const discover.Case {
    if (blocks.len == 0) return cases;
    const result = try a.alloc(discover.Case, cases.len + blocks.len);
    @memcpy(result[0..cases.len], cases);
    for (blocks, result[cases.len..]) |block, *slot| slot.* = try exampleCase(a, block);
    return result;
}

fn exampleSession(shared: GroupRun, session: *frontend.Session, overlays: []const frontend.Provider, problems: *std.ArrayList(u8)) Error!?frontend.Checked {
    const init = shared.init;
    const a = init.arena.allocator();
    const context = shared.selection.receipt;
    context.entry.configure(session);
    try session.enableCache(init.gpa, context.options.build.cache);
    try session.enableSharedCache(init.environ_map);
    shared.entry.apply(session, overlays);
    return checkEntry(session, a, context.entry, problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

fn failedExample(a: std.mem.Allocator, block: examples.Block, overlay: examples.Overlay, problems: []const u8, collected: *Collected) Error!void {
    const name = try examples.name(a, block);
    const reason = try examples.diagnosticText(a, problems, block, overlay);
    try collected.chosen.append(a, .{
        .case = try exampleCase(a, block),
        .ready = false,
        .verdict = .{ .name = name, .status = .failed, .reason = reason, .at = try exampleFailureAt(a, block, reason) },
    });
}

fn exampleFailureAt(a: std.mem.Allocator, block: examples.Block, reason: []const u8) Error![]const u8 {
    const prefix = try std.fmt.allocPrint(a, "{s}:", .{block.src.path});
    var lines = std.mem.splitScalar(u8, reason, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, ": error[") == null) continue;
        const position = std.mem.indexOf(u8, line, prefix) orelse continue;
        const line_start = position + prefix.len;
        const end = std.mem.indexOfScalarPos(u8, line, line_start, ':') orelse continue;
        if (end > line_start) return line[position..end];
    }
    return std.fmt.allocPrint(a, "{s}:{d}", .{ block.src.path, block.examples[0].line });
}

test "docstring exampleFailureAt chooses the failed prompt after earlier warnings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const block: examples.Block = .{ .module = "app", .function = "value", .generated = "test_generated", .src = try @import("selka").source.Source.init(a, "app.selka", ""), .examples = &.{.{ .lines = &.{}, .expected = "", .line = 4 }} };
    const reason = "app.selka:2:1: warning[W_UNUSED]: unused\napp.selka:9:5: error[E_UNKNOWN]: unresolved";
    try std.testing.expectEqualStrings("app.selka:9", try exampleFailureAt(a, block, reason));
    try std.testing.expectEqualStrings("app.selka:4", try exampleFailureAt(a, block, "unlocated diagnostic"));
}

fn runExamples(shared: GroupRun, blocks: []const examples.Block, collected: *Collected) Error!?u8 {
    const a = shared.init.arena.allocator();
    const options = shared.selection.receipt.options;
    for (blocks) |block| {
        const case = try exampleCase(a, block);
        if (!discover.matches(options.filter, case.name)) continue;
        const configured = v.get(shared.cases.document, case.name);
        const skip = v.get(configured, "skip");
        if (skip == .string and skip.string.len != 0) {
            try collected.chosen.append(a, .{ .case = case, .ready = false, .settings = configured, .verdict = .{ .name = case.name, .status = .skipped, .reason = skip.string } });
            continue;
        }
        if (try runExample(shared, block, collected)) |status| return status;
    }
    return null;
}

fn runExample(shared: GroupRun, block: examples.Block, collected: *Collected) Error!?u8 {
    const init = shared.init;
    const a = init.arena.allocator();
    const context = shared.selection.receipt;
    const groups = case_settings.groups(a, shared.cases, &.{try exampleCase(a, block)}) catch |err| {
        const status = try casesFailure(init, err);
        return status;
    };
    const group = groups[0];
    for (group.providers) |provider| if (std.mem.eql(u8, provider.path, block.src.path)) {
        const status = try failWith(init, "error: InvalidTestProviders: an example provider cannot replace its defining module\n", 2);
        return status;
    };
    const transcript = try examples.transcriptOf(a, block);
    const probe = try examples.render(a, block, null, transcript);
    var probe_session = frontend.Session.init(init.gpa, init.io, context.entry.root);
    defer probe_session.deinit();
    var problems: std.ArrayList(u8) = .empty;
    const probe_sources = try std.mem.concat(a, frontend.Provider, &.{ &.{.{ .path = block.src.path, .text = probe.text }}, group.providers, shared.entry.overlay });
    const probed = try exampleSession(shared, &probe_session, probe_sources, &problems) orelse {
        try failedExample(a, block, probe, problems.items, collected);
        return null;
    };
    const display = try examples.displaysOf(a, probed.program, probed.src, block, probe);
    const overlay = try examples.render(a, block, display, transcript);
    var session = frontend.Session.init(init.gpa, init.io, context.entry.root);
    defer session.deinit();
    problems.clearRetainingCapacity();
    const overlays = try std.mem.concat(a, frontend.Provider, &.{ &.{.{ .path = block.src.path, .text = overlay.text }}, group.providers, shared.entry.overlay });
    var checked = try exampleSession(shared, &session, overlays, &problems) orelse {
        try failedExample(a, block, overlay, problems.items, collected);
        return null;
    };
    if (group.providers.len != 0) if (shared.base_checked) |production| {
        const dependencies: case_settings.Group = .{ .providers = group.providers, .cases = &.{} };
        case_settings.compatible(a, shared.session, &session, production, checked, dependencies) catch |err|
            return checkFailure(init, err, "error: ProviderSignatureChanged: example providers changed the exported type graph\n", 1);
    };
    try collected.before.appendSlice(a, try receipt.captured(context, &session, overlays));
    try addSources(a, &collected.sources, context, try Loaded.of(a, &session));
    const found = try discover.discover(a, checked.program, context.entry.name, try moduleSources(a, try Loaded.of(a, &session), context.entry.name));
    const internal = try std.fmt.allocPrint(a, "{s}::{s}", .{ block.module, block.generated });
    var case = for (found) |candidate| {
        if (std.mem.eql(u8, candidate.name, internal)) break candidate;
    } else {
        try failedExample(a, block, overlay, "generated example was not discovered", collected);
        return null;
    };
    case.name = try examples.name(a, block);
    case.example = transcript;
    checked.program = try examples.remap(a, checked.program, checked.src, block, overlay);
    const narrowed = switch (try chooseCases(init, context.options, context.entry, checked, &.{case})) {
        .kept => |kept| kept,
        .exit => |status| return status,
    };
    var selection = shared.selection;
    selection.keys = .{};
    selection.private = true;
    const selected = try select(init, context.options, checked, narrowed, shared.cases, selection);
    const items = selected.items;
    const executed = try execute(init, context.options, checked, items, selection.permits, .{ .campaign = .{ .context = context, .inputs = collected.before.items, .backing = init.gpa }, .private = true, .program = selected.program });
    if (executed) |found_execution| try collected.executions.append(a, try shifted(a, found_execution, collected.chosen.items.len));
    if (group.providers.len != 0) {
        const identity = try providerIdentities(a, shared.session, group.providers, selection.base);
        for (items) |*item| item.verdict.identity = identity;
    }
    if (items.len != 0) if (selected.work) |work| try collected.works.append(a, .{ .first = collected.chosen.items.len, .work = work });
    try collected.chosen.appendSlice(a, items);
    return null;
}

/// The entry file as every session of a run reads it: its header-less overlay
/// (`headerlessTest`) and whether the old runner's stub `main` is appended.
pub const EntryText = struct {
    overlay: []const frontend.Provider,
    stub: bool,

    /// Read the entry this way in `session`, with `providers` replacing dependencies.
    pub fn apply(self: EntryText, session: *frontend.Session, providers: []const frontend.Provider) void {
        session.setProviders(providers);
        if (self.stub) session.entry.suffix = check_stub;
    }
};

/// What a run's provider groups add up: the inputs their verdicts depend on, the
/// sources the report lists and the selected tests.
const Collected = struct {
    warnings: std.ArrayList(u8) = .empty,
    before: std.ArrayList(receipt.Dependency),
    sources: std.ArrayList([]const u8) = .empty,
    chosen: std.ArrayList(Selected) = .empty,
    works: std.ArrayList(WorkRange) = .empty,
    /// Each built program's execution-tier keys, positions into `chosen`.
    executions: std.ArrayList(run_tests.Executed) = .empty,
};

/// `executed` with its positions moved `offset` places on, where its group's
/// tests start in the run's selection.
fn shifted(a: std.mem.Allocator, executed: run_tests.Executed, offset: usize) Error!run_tests.Executed {
    const positions = try a.alloc(usize, executed.positions.len);
    for (executed.positions, positions) |position, *moved| moved.* = position + offset;
    return .{ .positions = positions, .program_key = executed.program_key, .settings = executed.settings };
}

/// Name the key of the program each consulted test was linked into in its verdict's explanation (`cache.execution_key`).
fn attachExecutionKeys(a: std.mem.Allocator, verdicts: []report.Verdict, executions: []const run_tests.Executed) Error!void {
    for (executions) |executed| for (executed.positions) |position| {
        verdicts[position].cache.?.execution_key = try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(executed.program_key, .lower)});
    };
}
const WorkRange = struct { first: usize, work: *const key_work.Work };

/// What every provider group of one run shares: the base session (fully checked, or
/// only declared when providers replace an unfinished production body), the program
/// that answered discovery, and the entry's text and cases.
const GroupRun = struct {
    init: std.process.Init,
    selection: SelectionContext,
    session: *frontend.Session,
    base_checked: ?frontend.Checked,
    discovery: frontend.Checked,
    entry: EntryText,
    cases: case_settings.File,

    /// Check `group`'s provider graph (the base graph when it has none), select, build
    /// and run its cases into `out`; the exit status of a refusal, or null.
    fn runGroup(self: *const GroupRun, group: case_settings.Group, entry_module: []const u8, out: *Collected) Error!?u8 {
        const init = self.init;
        const a = init.arena.allocator();
        const context = self.selection.receipt;
        const located = context.entry;
        var provider_session = frontend.Session.init(init.gpa, init.io, located.root);
        defer provider_session.deinit();
        var program = self.base_checked orelse self.discovery;
        var cases = group.cases;
        var identity: ?report.Identity = null;
        if (group.providers.len != 0) {
            var problems: std.ArrayList(u8) = .empty;
            const overlays = try std.mem.concat(a, frontend.Provider, &.{ group.providers, self.entry.overlay });
            located.configure(&provider_session);
            try provider_session.enableCache(init.gpa, context.options.build.cache);
            try provider_session.enableSharedCache(init.environ_map);
            self.entry.apply(&provider_session, overlays);
            program = checkEntry(&provider_session, a, located, &problems) catch |err| return checkFailure(init, err, problems.items, 1);
            try writeAll(init, std.Io.File.stderr(), problems.items);
            try out.warnings.appendSlice(a, program.allocation_warnings);
            try out.before.appendSlice(a, try receipt.captured(context, &provider_session, overlays));
            located.validate(a, &provider_session, &problems) catch |err| return checkFailure(init, err, problems.items, project_entry.status(err));
            const discovered = try discover.discover(a, program.program, entry_module, try moduleSources(a, try Loaded.of(a, &provider_session), entry_module));
            // A replacement's declarations were validated before any body was checked;
            // with a checked production graph its exported type graph must agree too.
            if (self.base_checked) |production| case_settings.compatible(a, self.session, &provider_session, production, program, group) catch |err|
                return checkFailure(init, err, "error: ProviderSignatureChanged: test providers changed the exported type graph\n", 1);
            cases = try remap(a, self.discovery.program, program.program, group.cases, discovered);
            try addSources(a, &out.sources, context, try Loaded.of(a, &provider_session));
            identity = try providerIdentities(a, self.session, group.providers, self.selection.base);
        }
        // A group that replaces modules with providers keeps its records out of the shared tier, and its program is not the
        // one the base check's parts describe: its functions are keyed by their trees.
        var selection = self.selection;
        selection.private = group.providers.len != 0;
        if (group.providers.len != 0) selection.keys.parts = null;
        const selected = try select(init, context.options, program, cases, self.cases, selection);
        const items = selected.items;
        const campaign: run_tests.Campaign = .{ .context = context, .inputs = out.before.items, .backing = init.gpa };
        const executed = try execute(init, context.options, program, items, self.selection.permits, .{ .campaign = campaign, .private = selection.private, .program = selected.program });
        if (executed) |found| try out.executions.append(a, try shifted(a, found, out.chosen.items.len));
        if (identity) |known| for (items) |*item| {
            item.verdict.identity = known;
        };
        if (items.len != 0) if (selected.work) |work| try out.works.append(a, .{ .first = out.chosen.items.len, .work = work });
        try out.chosen.appendSlice(a, items);
        return null;
    }
};

fn validateShared(init: std.process.Init, options: Options) Error!void {
    const directory = options_module.sharedCache(options.shared_cache, init.environ_map) orelse return;
    _ = shared_store.Store.open(init.arena.allocator(), init.io, directory) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const message = try std.fmt.allocPrint(init.arena.allocator(), "error: shared test cache {s}: {s}\n", .{ directory, @errorName(err) });
        try writeAll(init, std.Io.File.stderr(), message);
        return err;
    };
}

/// NATIVE-TEST-5: the identities a provider test's report carries: the production
/// declarations its providers replace, the providers' sources, and the run's inputs.
fn providerIdentities(a: std.mem.Allocator, production: *frontend.Session, providers: []const frontend.Provider, base: [32]u8) Error!report.Identity {
    var replaced: std.ArrayList(test_contracts.Module) = .empty;
    for (providers) |provider| if (try declaredModule(production, try moduleOfPath(a, provider.path))) |module| try replaced.append(a, module);
    return .{
        .contract = try test_contracts.identity(a, replaced.items),
        .provider = try test_contracts.providerIdentity(a, providers),
        .source = try a.dupe(u8, &std.fmt.bytesToHex(base, .lower)),
    };
}

/// Module `name`'s exported declarations in `session`'s declared graph; null when it
/// has none or they cannot be rendered.
fn declaredModule(session: *frontend.Session, name: []const u8) Error!?test_contracts.Module {
    return test_contracts.declarations(session, name) catch |err| if (err == error.OutOfMemory) return error.OutOfMemory else null;
}

/// `dir/name.selka` is module `dir.name`.
fn moduleOfPath(a: std.mem.Allocator, path: []const u8) Error![]const u8 {
    const module = try a.dupe(u8, product.chopSource(path));
    std.mem.replaceScalar(u8, module, '/', '.');
    return module;
}

/// NATIVE-TEST-5: before any body is checked, every provider set the selection uses
/// must replace only modules the entry imports and keep each one's exported
/// declarations (`test_runner_contracts.zig`). The exit status of a refusal, or null.
fn validateProviders(init: std.process.Init, options: Options, located: project_entry.Entry, entry_text: EntryText, sets: []const []const frontend.Provider) Error!?u8 {
    const a = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    var production = frontend.Session.init(init.gpa, init.io, located.root);
    defer production.deinit();
    located.configure(&production);
    try production.enableCache(init.gpa, options.build.cache);
    try production.enableSharedCache(init.environ_map);
    entry_text.apply(&production, entry_text.overlay);
    production.declare(a, located.name, &problems) catch |err| return checkFailure(init, err, problems.items, 1);
    for (sets) |set| {
        case_settings.available(set, &production, located.name) catch |err|
            return checkFailure(init, err, "error: InvalidTestProviders: invalid test provider dependencies: a provider may replace only a module the entry imports, never the entry\n", 2);
        var replacement = frontend.Session.init(init.gpa, init.io, located.root);
        defer replacement.deinit();
        located.configure(&replacement);
        try replacement.enableCache(init.gpa, options.build.cache);
        try replacement.enableSharedCache(init.environ_map);
        entry_text.apply(&replacement, try std.mem.concat(a, frontend.Provider, &.{ set, entry_text.overlay }));
        replacement.declare(a, located.name, &problems) catch |err| return checkFailure(init, err, problems.items, 2);
        for (set) |provider| if (try keeps(a, &production, &replacement, provider.path)) |refused| return checkFailure(init, error.IncompatibleProvider, refused, 2);
    }
    return null;
}

/// Whether the replacement graph keeps the declarations module `path` exports in
/// production: null when it does, else the refusal to print.
fn keeps(a: std.mem.Allocator, production: *frontend.Session, replacement: *frontend.Session, path: []const u8) Error!?[]const u8 {
    const name = try moduleOfPath(a, path);
    const refused = try std.fmt.allocPrint(a, "error: IncompatibleProvider: provider {s} does not keep the exported declarations of module {s}\n", .{ path, name });
    // Declarations the production graph cannot render (a test's private parameter type)
    // leave the comparison to the checked type graph (`case_settings.compatible`).
    const before = try declaredModule(production, name) orelse return null;
    const after = try declaredModule(replacement, name) orelse return refused;
    test_contracts.validate(before, after) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else refused;
    return null;
}

/// Check the entry of `session` as a run does. Test discovery uses path-qualified
/// module identities for every valid entry, so a valid module name loads its module
/// graph and anything else is a header-less file; diagnostics go to `problems`.
pub fn checkEntry(session: *frontend.Session, allocator: std.mem.Allocator, located: project_entry.Entry, problems: *std.ArrayList(u8)) (frontend.Error || error{ReadFailed})!frontend.Checked {
    if (@import("selka").project.validName(located.name)) return session.check(allocator, located.name, problems);
    return session.checkFile(allocator, located.path, problems);
}

/// The first provider graph, fully checked, which answers discovery when the
/// production graph's bodies are not checked; null after printing nothing when it
/// does not check (its diagnostics are the production check's concern).
fn providerGraph(init: std.process.Init, options: Options, located: project_entry.Entry, entry_text: EntryText, set: []const frontend.Provider, session: *frontend.Session) Error!?frontend.Checked {
    const a = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    located.configure(session);
    try session.enableCache(init.gpa, options.build.cache);
    try session.enableSharedCache(init.environ_map);
    entry_text.apply(session, try std.mem.concat(a, frontend.Provider, &.{ set, entry_text.overlay }));
    if (checkEntry(session, a, located, &problems)) |checked| {
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return checked;
    } else |err| _ = try checkFailure(init, err, problems.items, 1);
    return null;
}

/// A check's failure as an exit status: memory runs out of the run itself; any other
/// error was already rendered into `text`, which goes to stderr.
fn checkFailure(init: std.process.Init, err: anyerror, text: []const u8, status: u8) Error!?u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    try writeAll(init, std.Io.File.stderr(), text);
    return status;
}

/// Print `text` on stderr and answer `status`.
fn failWith(init: std.process.Init, text: []const u8, status: u8) Error!u8 {
    try writeAll(init, std.Io.File.stderr(), text);
    return status;
}

fn casesFailure(init: std.process.Init, err: case_settings.Error) Error!u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return failWith(init, try std.fmt.allocPrint(init.arena.allocator(), "error: test providers: {s}\n", .{@errorName(err)}), 2);
}

/// The sources a check read, as receipts record them. A header-less test entry is
/// overlaid with its header (`headerlessTest`), so its own bytes are its input.
fn checkedInputs(context: receipt.Context, loaded: Loaded, overlay: []const frontend.Provider, bytes: []const u8) Error![]const receipt.Dependency {
    const inputs = if (loaded.session) |session| try receipt.captured(context, session, overlay) else try receipt.capturedModules(context, loaded.modules);
    const captured = if (overlay.len == 0) inputs else blk: {
        var digest: [32]u8 = undefined;
        fast_blake3.hash(bytes, &digest);
        break :blk try std.mem.concat(context.arena, receipt.Dependency, &.{ inputs, &.{.{ .path = context.entry.path, .digest = digest }} });
    };
    if (context.options.properties.policy != .indexed_v1) return captured;
    var guarded: std.ArrayList(receipt.Dependency) = .empty;
    try guarded.appendSlice(context.arena, captured);
    if (context.options.controls.cases == null) {
        const path = context.entry.path;
        const stem = product.sourceStem(path);
        try guarded.append(context.arena, .{ .path = try std.fmt.allocPrint(context.arena, "{s}.cases.json", .{stem}), .digest = null });
    }
    var directory = std.fs.path.dirname(context.entry.path) orelse return guarded.items;
    while (true) {
        const candidate = try std.fs.path.join(context.arena, &.{ directory, @import("selka").project_config.config_name });
        if (context.entry.configuration) |configured| if (std.mem.eql(u8, candidate, configured.path)) break;
        try guarded.append(context.arena, .{ .path = candidate, .digest = null });
        const parent = std.fs.path.dirname(directory) orelse break;
        if (std.mem.eql(u8, parent, directory)) break;
        directory = parent;
    }
    return guarded.items;
}

/// CLI-INPUT-REFUSED-1: refuse an entry that cannot be read, naming it and the reason
/// as the old CLI words them, with the usage status.
fn unreadable(init: std.process.Init, path: []const u8, name: []const u8) Error!u8 {
    const reason = if (std.mem.eql(u8, name, "FileNotFound")) "no such file or directory" else if (std.mem.eql(u8, name, "AccessDenied") or std.mem.eql(u8, name, "PermissionDenied")) "permission denied" else name;
    try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(init.arena.allocator(), "selka test: cannot read '{s}': {s}\n", .{ path, reason }));
    return 2;
}

/// TEST-SIBLING-HINT-1: when nothing is selected and `FILE_test.selka` beside the entry
/// exists outside the loaded graph, say so on stderr and how to run it.
/// A root of a directory run is not a person's one entry: the run tests the sibling too, so it says nothing (FR18).
fn siblingHint(init: std.process.Init, loaded: Loaded, located: project_entry.Entry, selected: usize, setup: Setup) Error!void {
    const a = init.arena.allocator();
    if (setup.directed != null or setup.directory_child) return;
    if (selected != 0 or !product.isSource(located.path)) return;
    const sibling = try std.fmt.allocPrint(a, "{s}_test" ++ product.source_suffix, .{product.sourceStem(located.path)});
    std.Io.Dir.cwd().access(init.io, sibling, .{}) catch return;
    if (!loaded.single()) for (loaded.modules) |module| {
        const path = try std.fs.path.join(a, &.{ located.root, module.src.path });
        if (std.mem.eql(u8, path, sibling)) return;
    };
    try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(a, "selka test: no tests selected; sibling test file {s} is not included by this entry. Run that file explicitly with selka test, or test its directory.\n", .{sibling}));
}

/// FMT-TEST-MODULE-1: preserve headerless test bytes in the provider overlay.
/// The project loader obtains module identity from the overlay path.
pub fn headerlessTest(a: std.mem.Allocator, located: project_entry.Entry, bytes: []const u8) Error![]const frontend.Provider {
    if (!product.isTestSource(located.path)) return &.{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const opening = while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len != 0 and line[0] != '#') break line;
    } else return &.{};
    if (!std.mem.startsWith(u8, opening, "import ")) return &.{};
    const relative = try std.mem.concat(a, u8, &.{ try std.mem.replaceOwned(u8, a, located.name, ".", "/"), product.source_suffix });
    return a.dupe(frontend.Provider, &.{.{ .path = relative, .text = bytes }});
}

/// The cases `--filter` selects and, with `--against`, the ones `--affected` keeps of
/// them (NEW-CORE-S5-AFFECTED-1), or the exit status of a reference git cannot resolve.
fn chooseCases(init: std.process.Init, options: Options, located: project_entry.Entry, checked: frontend.Checked, all_cases: []const discover.Case) Error!affected.Narrowed {
    const allocator = init.arena.allocator();
    var filtered: std.ArrayList(discover.Case) = .empty;
    for (all_cases) |case| if (discover.matches(options.filter, case.name)) {
        try filtered.append(allocator, case);
    };
    const reference = options.controls.scope.against orelse return .{ .kept = filtered.items };
    const request: affected.Request = .{
        .arena = allocator,
        .backing = init.gpa,
        .io = init.io,
        .root = located.root,
        .entry = located.path,
        .reference = reference,
    };
    return affected.narrow(request, checked, filtered.items);
}

/// Describe this invocation's admission decision alongside its result and key.
fn cacheExplanation(a: std.mem.Allocator, item: Selected, context: receipt.Context) Error!report.Cache {
    const status = item.verdict.status;
    const admission = receipt.reuseReason(context);
    const prefix = if (item.verdict.details.property) |evidence| evidence.campaign else null;
    const range_replay = if (prefix) |progress| status == .passed and progress.submitted == 0 and progress.fresh_classified == 0 and progress.reused != 0 else false;
    const reason = if (range_replay) "property-prefix-hit" else switch (status) {
        .cached => item.cache_reason orelse "receipt-hit",
        .skipped => "configured-skip",
        .unsupported => "unsupported",
        else => if (!std.mem.eql(u8, admission, "no-success-receipt")) admission else item.cache_reason orelse if (item.identity == null) "uncacheable-metadata" else "no-success-receipt",
    };
    return .{
        .action = if (range_replay) "reuse" else switch (status) {
            .cached => "reuse",
            .skipped => "skip",
            .unsupported => "refuse",
            else => "execute",
        },
        .reason = reason,
        .key = if (item.identity) |identity| try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(identity, .lower)}) else null,
        .component = try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(context.identity.cache_plan.?.identity, .lower)}),
        .key_method = item.key_method,
    };
}

fn bindPlan(init: std.process.Init) Error!planner.Bound {
    return planner.bind(init.arena.allocator(), init.io, init.environ_map) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(init.arena.allocator(), "error: cache-plan component: {s}\n", .{@errorName(err)}));
        return error.ComponentUnavailable;
    };
}

/// The whole run's recorded report, unless `--affected` selects by unrecorded git state: the engine serves it, while every
/// file the check read is as it was and the toolchain is the one the settings name.
fn replayRun(context: receipt.Context, base: [32]u8) Error!?receipt.Replay {
    if (context.options.controls.scope.against != null or context.options.properties.policy == .indexed_v1) return null;
    const found = try decide.replay(context, base) orelse return null;
    if (!try receipt.toolUnchanged(context)) return null;
    return found;
}

fn cachedReplay(init: std.process.Init, options: Options, located: project_entry.Entry, case_bytes: []const u8, cache_plan: planner.Bound) Error!?receipt.Replay {
    if (options.controls.scope.against != null or options.properties.policy == .indexed_v1) return null;
    const borrowed = try borrowedReplay(init, options, located, case_bytes, cache_plan);
    // The private transport never reaches native guests or a persistent key.
    _ = init.environ_map.swapRemove(tool_ticket.hint);
    return borrowed orelse try localReplay(init, options, located, case_bytes, cache_plan);
}

fn borrowedReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8, cache_plan: planner.Bound) Error!?receipt.Replay {
    const a = init.arena.allocator();
    const resources: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = requested.build.zig, .cache = requested.build.cache };
    const guest = try tool_ticket.borrow(.{ .tool = resources, .compiler_identity = frontend.compiler_identity, .component_identity = cache_plan.identity }) orelse return null;
    return directedReplay(init, requested, located, case_bytes, guest, cache_plan);
}

/// The recorded report of an entry under `guest`, the toolchain its directory run identified and validates once for every
/// root.
fn directedReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8, guest: tool_identity.Identity, cache_plan: planner.Bound) Error!?receipt.Replay {
    if (requested.controls.scope.against != null or requested.properties.policy == .indexed_v1) return null;
    const a = init.arena.allocator();
    var options = requested;
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = a, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = case_bytes, .identity = .{ .tool = guest, .cache_plan = cache_plan } };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    return decide.replay(context, try receipt.settings(context, &native_inputs));
}

fn localReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8, cache_plan: planner.Bound) Error!?receipt.Replay {
    const a = init.arena.allocator();
    const resources: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = requested.build.zig, .cache = requested.build.cache };
    const guest = tool_identity.lookupReplayCandidate(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    } orelse return null;
    var options = requested;
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = a, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = case_bytes, .identity = .{ .tool = guest, .cache_plan = cache_plan } };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    const base = try receipt.settings(context, &native_inputs);
    // Buffer the candidate without publishing anything under its unverified key.
    _ = try decide.replay(context, base) orelse return null;
    if (!try receipt.toolUnchanged(context)) return null;
    // Source/dependency bytes must still agree after the full tool validation.
    return decide.replay(context, base);
}

fn configuredCases(init: std.process.Init, options: *const Options, located: project_entry.Entry) Error!?case_settings.File {
    return case_settings.load(init.arena.allocator(), init.io, located.path, options.controls.cases) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(init.arena.allocator(), "error: test cases: {s}\n", .{@errorName(err)}));
        return null;
    };
}

fn guestTool(init: std.process.Init, options: Options) Error!?tool_identity.Identity {
    const a = init.arena.allocator();
    return tool_identity.capture(.{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = options.build.zig, .cache = options.build.cache }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cannot identify guest toolchain: {s}\n{s}", .{ @errorName(err), zig_lookup.hintFor(err) }));
        return null;
    };
}

/// Settle the step, frame and byte ceilings: a flag, then (memory only) `SELKA_MEMORY_LIMIT`,
/// then the project's `limits.test`, then the defaults. A frame budget the byte ceiling
/// cannot back is refused before anything is built, as the old core refuses it.
fn applyLimits(init: std.process.Init, options: *Options, located: project_entry.Entry) Error!bool {
    var frames: ?u64 = null;
    var memory: ?u64 = null;
    if (located.configuration) |configured| {
        const limits = configured.document.limits.tests;
        if (!options.controls.ceilings.explicit_steps) if (limits.max_steps) |steps| {
            options.controls.max_steps = steps;
        };
        frames = limits.max_frames;
        memory = limits.max_memory;
    }
    const a = init.arena.allocator();
    options.controls.ceilings = options_module.resolve(options.controls.ceilings, init.environ_map, frames, memory) catch {
        try writeAll(init, std.Io.File.stderr(), "error: SELKA_MEMORY_LIMIT is not a byte count with an optional K, M or G suffix\n");
        return false;
    };
    if (try options_module.frameRefusal(a, init.environ_map, options.controls.ceilings)) |refused| {
        try writeAll(init, std.Io.File.stderr(), refused);
        return false;
    }
    return true;
}

/// Whether `case` may publish a receipt. The shared checker propagates effects through
/// calls; Host calls have mutable external inputs and cannot publish persistent results.
/// `program`, the run's reading of `checked`, makes the proof once for each test.
fn publishes(a: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, program: ?*portable.Program) error{OutOfMemory}!bool {
    return (try proof(a, checked, case, program)) == null;
}

/// The receipt proof of `case`: from the run's reading of the program when there is one (each test walked once), else
/// walked here.
fn proof(a: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, program: ?*portable.Program) error{OutOfMemory}!?portable.Refusal {
    if (program) |read| return read.refusal(a, case.function);
    return portable.refusal(a, checked.program, case.function, null);
}

/// The cache reason of a test that may not publish a receipt: `live-effects`, a colon, and what stopped the proof
/// (a host function, a Host capability in some function, an extern, a callback beside `function_digest`). Null when
/// the test may publish. `program` is the run's reading of `checked`.
fn liveEffects(a: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, program: ?*portable.Program) error{OutOfMemory}!?[]const u8 {
    const refused = try proof(a, checked, case, program) orelse return null;
    const finding = try refused.describe(a, checked.program);
    const reason = try std.fmt.allocPrint(a, "live-effects: {s}", .{finding});
    return reason;
}

fn programIdentity(resources: IdentityResources, options: Options, checked: frontend.Checked, case: discover.Case, base: [32]u8) Error!?[32]u8 {
    if (!try publishes(resources.scratch, checked, case, resources.program)) return null;
    const a = resources.scratch;
    var why: build.Refusal = .{};
    const built = if (resources.prebuilt) |prebuilt| withEntry(a, options, checked, &.{case}, prebuilt) else programFor(a, options, checked, &.{case}, &why);
    const module = built catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    // Identity queries observe final live-module membership and conservative
    // indirect candidates, beyond this pre-finalization receipt closure.
    if (callable_digest.needed(&module)) return null;
    const identity = receipt.programKey(base, case.name, .{ .module = &module, .locator = pipeline.locator(&checked.src), .positions = false });
    return identity;
}

/// What `select` chose: every case's verdict so far, the work its key derivation did, and the shared tier rule's reading of
/// the program, which the execution of the same cases goes on using.
const Chosen = struct { items: []Selected, work: ?*const key_work.Work = null, program: ?*portable.Program = null };

/// Choose each case's starting verdict: refused and skipped cases have theirs, the others are ready, keyed by the IR of what
/// they reach (derived once for the whole program, or from each test's own lowering), and a ready test the engine serves under
/// its key is `cached` with the work its record holds.
fn select(init: std.process.Init, options: Options, checked: frontend.Checked, cases: []const discover.Case, settings: case_settings.File, selection: SelectionContext) Error!Chosen {
    const a = init.arena.allocator();
    const chosen = try a.alloc(Selected, cases.len);
    const context = selection.receipt;
    const source_path = try receipt.entryPath(context);
    // One reading of the program for the run: its tables, its paths and each test's proof are made once (stage 1).
    const program = try a.create(portable.Program);
    program.* = .init(context, checked, selection.rule);
    for (cases, chosen) |case, *item| {
        const configured = v.get(settings.document, case.name);
        const skip = v.get(configured, "skip");
        const refused = if (skip == .string and skip.string.len != 0) report.Verdict{ .name = case.name, .status = .skipped, .reason = skip.string } else try screen(a, checked, case, configured, options.controls.scope.allow_host);
        item.* = .{
            .case = case,
            .verdict = refused orelse .{ .name = case.name, .status = .failed, .reason = "not run" },
            .ready = refused == null,
            .cache_reason = if (refused == null) try liveEffects(a, checked, case, program) else null,
            .settings = configured,
        };
    }
    const asked = engineAsker(context, checked, !selection.private, program);
    if (!perTestKeys(init.environ_map)) if (try sharedKeys(init, options, checked, chosen, selection.base, .{ .planner = context.identity.cache_plan.?, .keys = selection.keys, .source_path = source_path })) |keys| {
        for (chosen, keys.tests, keys.bare) |*item, key, bare| if (item.ready) {
            item.key_method = keys.method;
            item.identity = key;
            if (options.properties.policy == .legacy) consult(a, asked, item, bare);
        };
        return .{ .items = chosen, .work = keys.work, .program = program };
    };
    for (chosen) |*item| {
        item.key_method = "per-test-ir-fallback";
        if (!item.ready) continue;
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        var built: ?@import("ir.zig").Module = null;
        if (try classify(scratch.allocator(), a, checked, item.case, item.settings, &built)) |refused| {
            item.verdict = refused;
            item.ready = false;
            continue;
        }
        if (try programIdentity(.{ .scratch = scratch.allocator(), .io = init.io, .prebuilt = built, .program = program }, options, checked, item.case, selection.base)) |identity| {
            item.identity = receipt.configuredKey(identity, try std.json.Stringify.valueAlloc(a, item.settings, .{}));
            if (options.properties.policy == .legacy) consult(a, asked, item, null);
        }
    }
    return .{ .items = chosen, .program = program };
}

/// Ask the engine about `item`, whose IR key is its identity, and reuse it when a valid record serves the key. Without an
/// engine that decides the run (it is forced, or the engine is off) the test stays ready.
fn consult(a: std.mem.Allocator, asked: ?decide.Asker, item: *Selected, bare: ?bool) void {
    const engine = asked orelse return;
    if (engine.irKnown(a, item.case, item.identity.?, bare)) |hit| reuseWith(item, hit);
}

/// The engine's questions for this run's execution settings, when the engine decides it; `program` is the shared tier
/// rule's reading of `checked` for the run.
fn engineAsker(context: receipt.Context, checked: frontend.Checked, shareable: bool, program: ?*portable.Program) ?decide.Asker {
    const settings = receipt.executionSettings(context) catch return null;
    return decide.asker(context, settings, if (shareable) checked else null, program);
}

/// `item` is reused: its verdict is the engine's served pass, with the work the record holds.
fn reuseWith(item: *Selected, hit: run_tests.Hit) void {
    item.verdict = .{ .name = item.case.name, .status = .cached, .details = .{ .counts = hit.counts } };
    item.ready = false;
    item.cache_reason = hit.reason;
}

/// Whether `SELKA_TEST_KEYS=per-test` asks for every test's key from its own lowering
/// (NEW-CORE-S4-TEST-6) instead of the shared one: the oracle the derived keys are
/// checked against. As a `SELKA_` variable it also separates the two modes' receipts.
fn perTestKeys(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("SELKA_TEST_KEYS") orelse "", "per-test");
}

/// Every ready test's configured key (null for the others), and whether every function it reaches is `bare` (D-T2-5).
const Keys = struct { tests: []const ?[32]u8, work: *const key_work.Work, method: []const u8, bare: []const ?bool };
/// How `sharedKeys` plans: the bound planner, a borrowed declaration catalog, and the
/// entry's root-relative path every key names (RECEIPT-PATHS-1).
const KeyPlanning = struct { planner: planner.Bound, keys: root_share.KeySources = .{}, source_path: []const u8 };

/// NEW-CORE-TEST-KEYS-1 and NEW-CORE-TEST-WHOLE-1: lower every ready test of the
/// program once, digest each function canonically, and key each test on the functions
/// it reaches (`test_runner_identity.zig`).
/// Null when no test is ready, one may call `Host`, the builder refuses a function or
/// a result, or the lowering carries metadata the digests do not know, so each test is
/// keyed and reported from its own lowering.
fn sharedKeys(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []const Selected, base: [32]u8, planning_input: KeyPlanning) Error!?Keys {
    const cache_plan = planning_input.planner;
    const a = init.arena.allocator();
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    const s = scratch.allocator();
    var cases: std.ArrayList(discover.Case) = .empty;
    for (chosen) |item| if (item.ready) {
        // `select` gave every ready test its `liveEffects` finding as its cache reason (null when it may publish): the same proof
        // `publishes` makes, which walks the test's whole call tree, so it is read here instead of made again.
        if (item.cache_reason != null) return null;
        try cases.append(s, item.case);
    };
    if (cases.items.len == 0) return null;
    const started = stage_metrics.now(init.io);
    const work = try a.create(key_work.Work);
    work.* = .{ .scope = try workScope(a, options.path, cases.items) };
    // The store's place stays per absolute entry; the keys name the relative one.
    const located_path = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, s) catch options.path;
    const source_path = planning_input.source_path;
    var source_scope: test_keys.Digest = undefined;
    fast_blake3.hash(located_path, &source_scope);
    // Each directory root opens its own store, including child processes. Bound
    // catalog scans to that root instead of indexing every other root's facts.
    const cache_root = try std.fs.path.join(s, &.{ options.build.cache, "test-keys", &std.fmt.bytesToHex(source_scope, .lower) });
    const compression = @import("stage_compression.zig").Policy.parse(init.environ_map.get("SELKA_STAGE_CACHE_COMPRESSION")) catch return null;
    var store = try stage_store.Store.initWithOptions(init.gpa, init.io, cache_root, .{ .compression = compression, .observe = @import("selka").profile_history.enabled() });
    defer store.deinit();
    defer observeKeys(s, &store, source_path);
    const roots = try rootsFor(s, checked.program, cases.items);
    const produced = try sharedFacts(s, .{ .options = options, .checked = checked, .roots = roots, .keys = planning_input.keys, .grouped = canonical_facts.groupsFacts(init.environ_map) }, &store, cache_plan.mode, work) orelse return null;
    const reachable = produced.module;
    const shared = produced.shared;
    if (!keyableRoots(&reachable, chosen)) return null;
    var schema: ?property_types.Schema = null;
    const tests = try a.alloc(?[32]u8, chosen.len);
    const requests = try s.alloc(test_keys.Test, chosen.len);
    const root_sets = try s.alloc([]const u32, chosen.len);
    for (chosen, requests, root_sets) |item, *request, *root_set| {
        root_set.* = &.{};
        request.* = .{ .base = base, .name = item.case.name, .source_path = source_path, .entry = @splat(0), .schema = null, .roots = &.{} };
        if (!item.ready) continue;
        const target = try testTarget(s, options, checked, item.case, 0);
        if (needsSchema(target) and schema == null) schema = try property_types.Schema.init(s, try property_schema.definitions(s, checked.program));
        // Only generated parameters add invariant roots, and finding them reads the schema.
        const generated = std.mem.indexOfScalar(u8, item.case.parameters, 255) != null;
        const own = if (generated) try rootsFor(s, checked.program, &.{item.case}) else &.{item.case.function};
        const indices = try s.alloc(u32, own.len);
        for (own, indices) |function, *index| index.* = @intCast(std.mem.indexOfScalar(typed.FunctionId, roots, function) orelse return null);
        root_set.* = indices;
        request.* = .{ .base = base, .name = item.case.name, .source_path = source_path, .entry = entryDigest(target), .schema = if (needsSchema(target)) try schemaDigest(s, schema.?, target) else null, .roots = indices };
    }
    const graph_start = stage_metrics.now(init.io);
    var saved: ?graph_cache.Prepared = if (produced.identities) |ids| graph_cache.prepare(s, .{ .store = &store, .records = engine_run.planning() }, shared, ids, requests, &work.graph) catch |err| blk: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        break :blk null;
    } else null;
    work.nanoseconds.graph = stage_metrics.elapsed(init.io, graph_start);
    const derived = try s.alloc(?test_keys.Digest, chosen.len);
    @memset(derived, null);
    if (saved) |*cached| {
        const planning = stage_metrics.now(init.io);
        var planned = cache_plan.incremental(s, cached.request(shared, root_sets)) catch |err| return planFailure(init, err);
        defer planned.deinit();
        work.nanoseconds.planner = stage_metrics.elapsed(init.io, planning);
        work.planner = planned.work;
        work.transport = planned.transport;
        const hashing = stage_metrics.now(init.io);
        for (chosen, requests, derived, 0..) |item, request, *key, index| {
            if (!item.ready) continue;
            key.* = if (planned.reused[index]) cached.keys[index] orelse return planFailure(init, error.ComponentProtocol) else test_keys.plannedKey(shared, request, planned.batches[index]) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return null;
            };
        }
        work.nanoseconds.keys = stage_metrics.elapsed(init.io, hashing);
        if (cache_plan.mode == .shadow) try verifyShared(init, checked, roots, requests, derived);
        const publication = stage_metrics.now(init.io);
        @memcpy(cached.keys, derived);
        cached.publish(s, .{ .store = &store, .records = engine_run.planning() }, planned.indexes, &work.graph) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return planFailure(init, error.ComponentProtocol);
        };
        _ = try store.flush();
        work.nanoseconds.publication = stage_metrics.elapsed(init.io, publication);
    } else {
        if (!try deriveLegacy(init, cache_plan, .{ .shared = shared, .requests = requests, .roots = root_sets }, derived, work)) return null;
        if (cache_plan.mode == .shadow) try verifyShared(init, checked, roots, requests, derived);
    }

    const bare = try a.alloc(?bool, chosen.len);
    try configureKeys(s, .{ .chosen = chosen, .derived = derived, .roots = root_sets }, .{ .shared = shared, .bare = produced.bare }, tests, bare);
    work.storage = store.statistics();
    work.nanoseconds.total = stage_metrics.elapsed(init.io, started);
    return .{ .tests = tests, .work = work, .method = if (saved != null) "canonical-facts" else "reachable-ir", .bare = bare };
}

/// The keyed tests of a shared derivation: what was chosen, each test's derived key and its roots in the shared lowering.
const Derived = struct { chosen: []const Selected, derived: []const ?test_keys.Digest, roots: []const []const u32 };
/// The shared lowering's call graph and each function's `bare` answer.
const Reach = struct { shared: test_keys.Shared, bare: []const bool };

/// Each test's configured key (its derived key and its cases-file settings) and whether its reach is `bare`.
fn configureKeys(s: std.mem.Allocator, input: Derived, reach: Reach, tests: []?[32]u8, bare: []?bool) Error!void {
    for (input.chosen, tests, input.derived, input.roots, bare) |item, *slot, key, root_set, *own| {
        slot.* = null;
        own.* = null;
        const value = key orelse continue;
        slot.* = receipt.configuredKey(value, try std.json.Stringify.valueAlloc(s, item.settings, .{}));
        own.* = try reachedBare(s, reach.shared, reach.bare, root_set);
    }
}

/// Whether every function `roots` reach in the shared lowering is `bare`, or null when the lowering does not say.
fn reachedBare(a: std.mem.Allocator, shared: test_keys.Shared, bare: []const bool, roots: []const u32) std.mem.Allocator.Error!?bool {
    if (bare.len != shared.callees.len) return null;
    const seen = try a.alloc(bool, bare.len);
    @memset(seen, false);
    var pending: std.ArrayList(u32) = .empty;
    for (roots) |root| {
        if (root >= bare.len) return null;
        try pending.append(a, root);
    }
    while (pending.pop()) |node| {
        if (seen[node]) continue;
        seen[node] = true;
        if (!bare[node]) return false;
        for (shared.callees[node]) |callee| {
            if (callee >= bare.len) return null;
            try pending.append(a, callee);
        }
    }
    return true;
}

/// Record one entry's front-end counts (`frontend-session-v1`) in the active profile archive, when one records. The counts are
/// the session's own (`frontend.Session.statistics`): checked and reused bodies, summaries, and syntax hits and misses.
fn observeSession(session: *const frontend.Session, entry_path: []const u8) void {
    if (!@import("selka").profile_history.enabled()) return;
    @import("selka").profile_history.capture(.{ .version = "frontend-session-v1", .entry = entry_path, .statistics = session.statistics() });
}

/// Record one entry's test-keys store counts by scope (`stage-scopes-v1`) in the active profile archive, when one records.
/// The store holds the test-planning facts (`core-test-function-facts-v3`), the graph and the planner records; each scope is
/// listed with its loads (hits), misses and saves.
fn observeKeys(a: std.mem.Allocator, store: *const stage_store.Store, entry_path: []const u8) void {
    if (!@import("selka").profile_history.enabled()) return;
    const scopes = store.tallies(a) catch return;
    @import("selka").profile_history.capture(.{ .version = "stage-scopes-v1", .store = "test-keys", .entry = entry_path, .scopes = scopes });
}

/// `rootsFor` lists cases first, so ready case `i` is physical function `i`.
fn keyableRoots(module: *const @import("ir.zig").Module, chosen: []const Selected) bool {
    // Fall back per test so unaffected roots keep their ordinary receipts.
    if (callable_digest.needed(module)) return false;
    var root: usize = 0;
    for (chosen) |item| if (item.ready) {
        if (!expects(item.settings) and !entry.readable(module, module.functions.items[root].signature.ret)) return false;
        root += 1;
    };
    return true;
}

const LegacyInput = struct { shared: test_keys.Shared, requests: []const test_keys.Test, roots: []const []const u32 };

fn deriveLegacy(init: std.process.Init, bound: planner.Bound, input: LegacyInput, derived: []?test_keys.Digest, work: *key_work.Work) Error!bool {
    const planning = stage_metrics.now(init.io);
    var planned = bound.batch(init.arena.allocator(), .{ .digests = input.shared.digests, .callees = input.shared.callees }, input.roots) catch |err| return planFailure(init, err);
    defer planned.deinit();
    work.nanoseconds.planner = stage_metrics.elapsed(init.io, planning);
    work.transport = planned.transport;
    const hashing = stage_metrics.now(init.io);
    for (input.requests, derived, planned.batches) |request, *key, reached| {
        if (request.roots.len == 0) continue;
        key.* = test_keys.plannedKey(input.shared, request, reached) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        work.planner.planned_tests += 1;
        work.planner.closure_nodes += reached.len;
        for (reached) |node| work.planner.closure_edges += input.shared.callees[node].len;
        for (request.roots, 0..) |root, index| {
            if (std.mem.indexOfScalar(u32, request.roots[0..index], root) != null) continue;
            work.planner.closure_nodes += 1;
            work.planner.closure_edges += input.shared.callees[root].len;
        }
    }
    work.nanoseconds.keys = stage_metrics.elapsed(init.io, hashing);
    return true;
}

fn attachWork(verdicts: []report.Verdict, ranges: []const WorkRange) void {
    for (ranges) |range| if (verdicts[range.first].cache) |*explanation| {
        explanation.work = range.work;
    };
}

/// An entry's verdicts as its JSON report renders them once it has published.
const Published = struct { verdicts: []report.Verdict, sources: []const []const u8, works: []const WorkRange, rule: key_work.Rule };

/// The JSON report of an entry that has published, when the run prints it or the profile history keeps it (else empty).
/// Publishing decides the shared tier's rule for the records it offers, so the rule's counts are complete only now.
fn publishedJson(a: std.mem.Allocator, json: bool, published: Published) Error![]const u8 {
    try attachRule(a, published.verdicts, published.works, published.rule);
    const history = @import("selka").profile_history.enabled();
    if (!json and !history) return "";
    const rendered = try report.jsonSources(a, published.verdicts, published.sources);
    if (history) @import("selka").profile_history.captureJson(rendered);
    return rendered;
}

/// Give the entry's first group's work the counts of the shared tier's rule (`rule` of the work report).
fn attachRule(a: std.mem.Allocator, verdicts: []report.Verdict, ranges: []const WorkRange, counted: key_work.Rule) Error!void {
    if (ranges.len == 0) return;
    const explanation = if (verdicts[ranges[0].first].cache) |*found| found else return;
    const work = try a.create(key_work.Work);
    work.* = ranges[0].work.*;
    work.rule = counted;
    explanation.work = work;
}

/// `bare` holds each function's `test_runner_facts.bare` answer, by index.
const Produced = struct { module: @import("ir.zig").Module, shared: test_keys.Shared, identities: ?[]const ?test_keys.Digest = null, bare: []const bool };
/// What a root's facts are made from: the run's options, its check, the roots, where lowering keys come from, and whether the
/// facts are read by group records (`canonical_facts.groupsFacts`).
const FactInput = struct { options: Options, checked: frontend.Checked, roots: []const typed.FunctionId, keys: root_share.KeySources = .{}, grouped: bool = true };

/// Header discovery validates raw input receipts before individual canonical fact lookup.
fn sharedFacts(a: std.mem.Allocator, input: FactInput, store: *const stage_store.Store, mode: planner.Mode, work: *key_work.Work) Error!?Produced {
    const checked = input.checked;
    const roots = input.roots;
    if (mode == .reference) return eagerFacts(a, input, store.io, work);
    var deferred: lowering_cache.Deferred = .{ .arena = a, .store = store };
    var cache: lowering_cache.Cache = .{ .store = store, .lazy = &deferred, .catalog = .{ .known = input.keys.catalog }, .engine = .{ .parts = input.keys.parts } };
    var why: build.Refusal = .{};
    const lowering_start = stage_metrics.now(store.io);
    var module = build.buildRootsCached(a, roots, loweringInput(checked), &why, &cache) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        work.nanoseconds.lowering += stage_metrics.elapsed(store.io, lowering_start);
        work.producer.lowering.fresh = cache.counts.lowered;
        work.producer.lowering.reused = cache.counts.reused;
        work.producer.lowering.by_part = cache.counts.by_part;
        work.producer.facts.fallback += 1;
        work.producer.refused = @errorName(err);
        return eagerFacts(a, input, store.io, work);
    };
    try deferred.prepare(&module, checked.src);
    work.nanoseconds.lowering = stage_metrics.elapsed(store.io, lowering_start);
    work.producer.lowering.fresh = cache.counts.lowered;
    work.producer.lowering.reused = cache.counts.reused;
    work.producer.lowering.by_part = cache.counts.by_part;
    const fact_start = stage_metrics.now(store.io);
    const fact_input: canonical_facts.Input = .{ .module = &module, .locator = pipeline.locator(&checked.src), .deferred = &deferred, .records = engine_run.planning(), .grouped = input.grouped };
    const facts = canonical_facts.buildWith(a, fact_input, &work.producer.facts) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        work.producer.lowering.materialized = deferred.restored;
        work.nanoseconds.facts += stage_metrics.elapsed(store.io, fact_start);
        work.producer.facts.fallback += 1;
        work.producer.refused = @errorName(err);
        return eagerFacts(a, input, store.io, work);
    };
    work.producer.lowering.materialized = deferred.restored;
    work.nanoseconds.facts = stage_metrics.elapsed(store.io, fact_start);
    return .{ .module = module, .shared = facts.shared, .identities = facts.identities, .bare = facts.bare };
}

fn workScope(a: std.mem.Allocator, path: []const u8, cases: []const discover.Case) Error![]const u8 {
    var hash = fast_blake3.Blake3.init(.{});
    for (cases) |case| {
        hash.update(case.name);
        hash.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(a, "{s}#{s}", .{ path, std.fmt.bytesToHex(digest, .lower) });
}

/// Complete independent lowering remains the conservative path for unknown facts.
fn eagerFacts(a: std.mem.Allocator, input: FactInput, io: std.Io, work: *key_work.Work) Error!?Produced {
    const checked = input.checked;
    const roots = input.roots;
    var why: build.Refusal = .{};
    const lowering_start = stage_metrics.now(io);
    const module = build.buildRootsCached(a, roots, loweringInput(checked), &why, null) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    work.nanoseconds.lowering += stage_metrics.elapsed(io, lowering_start);
    for (module.functions.items) |function| if (function.signature.linkage == .internal) {
        work.producer.lowering.fresh += 1;
    };
    const facts_start = stage_metrics.now(io);
    const shared = test_keys.Shared.plain(a, &module, pipeline.locator(&checked.src)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    work.producer.facts.fresh += shared.digests.len;
    work.nanoseconds.facts += stage_metrics.elapsed(io, facts_start);
    const bare = try a.alloc(bool, module.functions.items.len);
    for (module.functions.items, bare) |function, *own| own.* = canonical_facts.bare(function);
    return .{ .module = module, .shared = shared, .bare = bare };
}

/// Shadow keys come from independent eager lowering with all new metadata disabled.
fn verifyShared(init: std.process.Init, checked: frontend.Checked, roots: []const typed.FunctionId, requests: []const test_keys.Test, derived: []const ?test_keys.Digest) Error!void {
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var why: build.Refusal = .{};
    const module = build.buildRootsCached(a, roots, loweringInput(checked), &why, null) catch |err| return planFailure(init, err);
    const shared = test_keys.Shared.plain(a, &module, pipeline.locator(&checked.src)) catch |err| return planFailure(init, err);
    for (requests, derived) |request, cached| if (cached) |key| {
        const expected = test_keys.key(shared, a, request) catch |err| return planFailure(init, err);
        if (!std.mem.eql(u8, &expected, &key)) return planFailure(init, error.ComponentShadowMismatch);
    };
}

fn planFailure(init: std.process.Init, err: anyerror) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    writeAll(init, std.Io.File.stderr(), std.fmt.allocPrint(init.arena.allocator(), "error: cache-plan component: {s}\n", .{@errorName(err)}) catch return error.OutOfMemory) catch return error.WriteFailed;
    return error.ComponentUnavailable;
}

/// Whether a test's entry reads or writes values through the copied-value adapters,
/// whose code follows the type schema: a generated or cases-file data parameter, or a
/// result other than `bool`.
fn needsSchema(target: entry.Target) bool {
    for (target.parameters) |family| if (family > 5 and !discover.standIn(family)) return true;
    const data = target.data orelse return true;
    return !std.mem.eql(u8, data.result, "bool");
}

/// The type schema the adapters are generated from, as one digest.
fn byName(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The digest of the schema of the types `target`'s parameters and result reach,
/// which is all its generated inputs and decoded result depend on. A type it cannot
/// reach, added in the same file or in another root sharing a directory run's check
/// (NEW-CORE-TEST-UNION-1), keeps its key.
fn schemaDigest(a: std.mem.Allocator, schema: property_types.Schema, target: entry.Target) Error![32]u8 {
    const data = target.data orelse return @splat(0);
    var reached: std.array_hash_map.String(void) = .empty;
    var pending: std.ArrayList([]const u8) = .empty;
    try pending.appendSlice(a, data.parameters);
    try pending.append(a, data.result);
    while (pending.pop()) |name| {
        if ((try reached.getOrPut(a, name)).found_existing) continue;
        try pending.appendSlice(a, try property_types.parts(schema, name));
    }
    const names = try a.dupe([]const u8, reached.keys());
    std.mem.sort([]const u8, names, {}, byName);
    var hash = fast_blake3.Blake3.init(.{});
    for (names) |name| {
        const definition = schema.definition(name) orelse continue;
        hash.update(try std.json.Stringify.valueAlloc(a, definition, .{}));
        hash.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest;
}

/// Everything a test's generated entry is built from besides its functions and schema.
fn entryDigest(target: entry.Target) [32]u8 {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update("core-test-entry-v1");
    hash.update(std.mem.asBytes(&@as(u64, target.streams.len)));
    for (target.streams) |stream| hash.update(std.mem.asBytes(&@as(i64, stream)));
    hash.update(std.mem.asBytes(&@as(u64, target.parameters.len)));
    hash.update(target.parameters);
    hash.update(std.mem.asBytes(&target.seed));
    if (target.data) |data| {
        hash.update(std.mem.asBytes(&@as(u64, data.parameters.len)));
        for (data.parameters) |name| {
            hash.update(std.mem.asBytes(&@as(u64, name.len)));
            hash.update(name);
        }
        hash.update(std.mem.asBytes(&@as(u64, data.result.len)));
        hash.update(data.result);
    }
    if (target.result) |shape| {
        hash.update(std.mem.asBytes(&shape.ok_tag));
        hash.update(std.mem.asBytes(&shape.error_tag));
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest;
}

/// Whether a case's configured entry states the value it must return.
fn expects(settings: std.json.Value) bool {
    return settings == .object and settings.object.contains(case_expectation);
}

fn remap(a: std.mem.Allocator, before: typed.Program, after: typed.Program, original: []const discover.Case, discovered: []const discover.Case) Error![]const discover.Case {
    const result = try a.alloc(discover.Case, original.len);
    for (original, result) |case, *slot| {
        const found = for (discovered) |candidate| {
            if (std.mem.eql(u8, candidate.name, case.name)) break candidate;
        } else return error.InvalidTestValue;
        const old = before.functions[@backingInt(case.function)];
        const new = after.functions[@backingInt(found.function)];
        if (old.signature.parameter_count != new.signature.parameter_count) return error.InvalidTestValue;
        if (!std.mem.eql(u16, old.signature.mutates, new.signature.mutates)) return error.InvalidTestValue;
        if (!old.signature.return_origin.eql(new.signature.return_origin)) return error.InvalidTestValue;
        const old_result = typed.typeName(old.signature.return_type, before.records);
        const new_result = typed.typeName(new.signature.return_type, after.records);
        if (!std.mem.eql(u8, old_result, new_result)) return error.InvalidTestValue;
        for (old.scope.locals[0..old.signature.parameter_count], new.scope.locals[0..new.signature.parameter_count]) |left, right| {
            if (!std.mem.eql(u8, left.name, right.name)) return error.InvalidTestValue;
            if (!std.mem.eql(u8, typed.typeName(left.ty, before.records), typed.typeName(right.ty, after.records))) return error.InvalidTestValue;
        }
        slot.* = found;
    }
    return result;
}

fn writeAll(init: std.process.Init, file: std.Io.File, text: []const u8) Error!void {
    // Standard error carries the check's warnings: some of them are counted, not printed (`warning_display.zig`).
    if (file.handle == std.Io.File.stderr().handle) return language.warning_display.write(init.io, text) catch error.WriteFailed;
    file.writeStreamingAll(init.io, text) catch return error.WriteFailed;
}

/// Why a test that declares `host: Host` fails without `--allow-host` (D-FFI-7).
pub const host_refusal = "a test that declares `host: Host` calls C: the Host capability is handed to a test only under `selka test --allow-host`";

/// The verdict of a test that fails before anything is built (a property test that
/// cannot be generated, a result type no test may return), or null.
fn screen(keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, settings: std.json.Value, allow_host: bool) Error!?report.Verdict {
    if (!allow_host and std.mem.indexOfScalar(u8, case.parameters, discover.host_family) != null)
        return .{ .name = case.name, .status = .failed, .reason = host_refusal };
    const arguments = v.get(settings, "arguments");
    const fixed = arguments == .object and arguments.object.count() != 0;
    const expected = expects(settings);
    if (case.other_parameters != 0 and !fixed) {
        if (expected) return .{ .name = case.name, .status = .failed, .reason = "a property test's verdict is its bool result; remove `expected` or supply `arguments`" };
        const function = checked.program.functions[@backingInt(case.function)];
        const definitions = try property_schema.definitions(keep, checked.program);
        const schema = try property_types.Schema.init(keep, definitions);
        for (function.scope.locals[0..function.signature.parameter_count], case.parameters) |parameter, family| {
            if (family != 255 and (family <= 5 or discover.standIn(family))) continue;
            const name = typed.typeName(parameter.ty, checked.program.records);
            if (try property_types.refused(schema, name)) |found| {
                return .{ .name = case.name, .status = .failed, .reason = try property.refusedText(keep, parameter.name, name, found) };
            }
        }
    }
    // NEW-CORE-S5-TEST-1: an exported `test_*` with another result is a failed case, as the old runner reports it.
    if (case.shape == .other and !expected) {
        if (case.other_parameters == 0) return .{ .name = case.name, .status = .failed, .reason = "test result type is not bool" };
        const result = typed.typeName(checked.program.functions[@backingInt(case.function)].signature.return_type, checked.program.records);
        return .{ .name = case.name, .status = .failed, .reason = try property.nonBoolResultText(keep, result) };
    }
    return null;
}

/// The `unsupported` verdict of a screened test the builder cannot build, or null when
/// it can be built and run; then `built` holds its reachable functions, allocated in `scratch`.
fn classify(scratch: std.mem.Allocator, keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, settings: std.json.Value, built: *?@import("ir.zig").Module) Error!?report.Verdict {
    const expected = expects(settings);
    var why: build.Refusal = .{};
    const selected_roots = try rootsFor(scratch, checked.program, &.{case});
    const module = build.buildRootsCached(scratch, selected_roots, loweringInput(checked), &why, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CacheMiss => unreachable,
        error.Unsupported => {
            const at = frontend.position(checked.src, .{ .start = why.span, .end = why.span });
            var verdict = refusal(case, try keep.dupe(u8, why.reason), try std.fmt.allocPrint(keep, "{d}:{d}", .{ at.line, at.column }));
            verdict.details.rule = why.rule;
            return verdict;
        },
    };
    if (!expected and !entry.readable(&module, module.functions.items[0].signature.ret)) return refusal(case, "the runner's entry cannot read this test's result type yet (Result[bool, E])", "");
    built.* = module;
    return null;
}

fn refusal(case: discover.Case, reason: []const u8, at: []const u8) report.Verdict {
    return .{ .name = case.name, .status = .unsupported, .reason = reason, .at = at };
}

/// The entry module's name, which qualifies its tests: the prefix of the (stub) `main`'s
/// own name, since a `module` header may differ from the file's stem; the stem for a header-less file.
pub fn moduleName(program: typed.Program, stem: []const u8) []const u8 {
    const main = program.functions[@backingInt(program.main)].name;
    const split = std.mem.lastIndexOf(u8, main, "::") orelse return stem;
    return main[0..split];
}

/// Discover declarations from the immutable sources the checker actually used.
fn moduleSources(a: std.mem.Allocator, loaded: Loaded, entry_module: []const u8) Error![]const discover.Module {
    if (loaded.session) |session| if (session.single) |unit| return a.dupe(discover.Module, &.{.{ .name = entry_module, .text = unit.src.bytes }});
    const modules = try a.alloc(discover.Module, loaded.modules.len);
    for (loaded.modules, modules) |source, *module| module.* = .{ .name = source.name, .text = source.src.bytes };
    return modules;
}

/// The tests of `loaded`'s modules. A root's share of a shared check discovers only the
/// functions of its own graph's modules, which are all its own check would have held.
fn discoverLoaded(a: std.mem.Allocator, checked: frontend.Checked, entry_module: []const u8, loaded: Loaded) Error![]const discover.Case {
    const modules = try moduleSources(a, loaded, entry_module);
    return discover.within(a, checked.program, entry_module, modules, if (loaded.session == null) modules else null);
}

/// What decides which discovered tests a directory run left a root: the modules its check loaded (and the entry module of a
/// header-less root), the entry's root-relative path, its cases file, and the modules whose tests another root runs (null
/// for a single-file run, which keeps every test).
const Ownership = struct { loaded: Loaded, entry_module: []const u8, entry_path: []const u8, cases: case_settings.File, skipped: ?[]const []const u8 };

/// The tests of `all` this root runs (D-TL2-3 of experiments/test-loop-20261109/DECISIONS.md, the user's D1): all but those
/// of the modules another root of the directory run owns, keeping every one its own cases file names (its verdict under
/// those cases is its own). A module is left out only when the run named it, so a test no root claimed still runs.
fn ownedCases(a: std.mem.Allocator, all: []const discover.Case, ownership: Ownership) Error![]const discover.Case {
    const skipped = ownership.skipped orelse return all;
    var paths: std.StringHashMapUnmanaged(void) = .empty;
    for (skipped) |path| try paths.put(a, path, {});
    var names: std.StringHashMapUnmanaged(void) = .empty;
    if (ownership.loaded.single()) {
        if (paths.contains(ownership.entry_path)) try names.put(a, ownership.entry_module, {});
    } else for (ownership.loaded.modules) |module| if (paths.contains(module.src.path)) try names.put(a, module.name, {});
    var kept: std.ArrayList(discover.Case) = .empty;
    for (all) |case| {
        const split = std.mem.lastIndexOf(u8, case.name, "::") orelse 0;
        const named = v.get(ownership.cases.document, case.name) != .null;
        if (named or !names.contains(case.name[0..split])) try kept.append(a, case);
    }
    return kept.items;
}

/// The modules a root's check loaded, as receipts, discovery and the report read
/// them: its own session's, or its share of a directory run's shared check.
pub const Loaded = struct {
    session: ?*const frontend.Session = null,
    modules: []const *const frontend.Module = &.{},

    /// The modules `session` loaded, in load order.
    pub fn of(a: std.mem.Allocator, session: *const frontend.Session) Error!Loaded {
        const list = try a.alloc(*const frontend.Module, session.project.modules.items.len);
        for (session.project.modules.items, list) |*module, *slot| slot.* = module;
        return .{ .session = session, .modules = list };
    }

    /// Whether the check read one header-less file.
    pub fn single(self: Loaded) bool {
        const session = self.session orelse return false;
        return session.single != null;
    }
};

fn addSources(a: std.mem.Allocator, paths: *std.ArrayList([]const u8), context: receipt.Context, loaded: Loaded) Error!void {
    if (loaded.single()) {
        try paths.append(a, context.entry.path);
        return;
    }
    for (loaded.modules) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const path = try std.fs.path.join(a, &.{ context.entry.root, module.src.path });
        var present = false;
        for (paths.items) |known| present = present or std.mem.eql(u8, known, path);
        if (!present) try paths.append(a, path);
    }
}

/// Whether a file's own text declares `main`, so a run need not append the stub one.
pub fn definesMain(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "func main(") or std.mem.startsWith(u8, line, "public func main(") or std.mem.startsWith(u8, line, "def main(") or std.mem.startsWith(u8, line, "public def main(")) return true;
    }
    return false;
}

/// Build the pending tests together (isolating any the backend rejects) and run each,
/// after the execution tier answered what it could (EXEC-RECEIPT-1). The built
/// program's execution keys, or null when nothing was built or the tier refused.
fn execute(init: std.process.Init, requested: Options, checked: frontend.Checked, chosen: []Selected, permits: ?*root_share.Permits, execution: Execution) Error!?run_tests.Executed {
    const allocator = init.arena.allocator();
    const campaign = execution.campaign;
    var live: std.ArrayList(usize) = .empty;
    var pending = false;
    for (chosen, 0..) |item, position| {
        pending = pending or item.ready;
        // Keep the linked program stable when another root already reused some
        // members through IR receipts. Cached members retain their dispatch row
        // but run no trial; a wholly cached selection still builds nothing.
        if (item.ready or item.verdict.status == .cached) try live.append(allocator, position);
    }
    if (!pending) return null;
    var options = requested;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    options.build.output = try std.fmt.allocPrint(allocator, "{s}/tests/program-{s}", .{ requested.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, options.build.output) catch return error.WriteFailed;
    defer run_tests.removePrivate(init.io, options.build.output);
    const source_path = try receipt.entryPath(execution.campaign.context);
    var attempt = try buildExecutable(init, options, checked, chosen, live.items, .{ .source_path = source_path });
    if (attempt == .failed and live.items.len > 1) {
        // Find which tests the backend rejects by building each alone, then rebuild the rest.
        var good: std.ArrayList(usize) = .empty;
        for (live.items) |position| {
            const alone = try buildExecutable(init, options, checked, chosen, &.{position}, .{ .tag = "-probe", .source_path = source_path });
            switch (alone) {
                .built => try good.append(allocator, position),
                .failed => |failure| chosen[position].verdict = failure,
            }
        }
        live = good;
        if (live.items.len == 0) return null;
        attempt = try buildExecutable(init, options, checked, chosen, live.items, .{ .source_path = source_path });
    }
    switch (attempt) {
        .failed => |failure| {
            for (live.items) |position| {
                chosen[position].verdict = failure;
                chosen[position].verdict.name = chosen[position].case.name;
            }
            return null;
        },
        .built => |executable| {
            const positions = try publishing(allocator, checked, chosen, live.items, execution.program);
            if (!try campaign.unchanged()) return error.SourceChanged;
            const asked = engineAsker(campaign.context, checked, !execution.private, execution.program);
            if (asked) |engine| if (executable.program_key) |program_key| engine.declarePrograms(allocator, chosen, positions, program_key);
            const decider: ?run_tests.Decider = if (asked) |*engine| decide.decider(engine) else null;
            const executed = if (executable.program_key) |program_key| try run_tests.reuse(.{ .context = campaign.context, .program_key = program_key }, chosen, positions, decider) else null;
            if (!try campaign.unchanged()) return error.SourceChanged;
            const width = options_module.width(options.controls, init.environ_map, live.items.len, @import("memory_budget").available(init.io));
            // The pinned Zig arena is thread-safe with Init's thread-safe backing.
            var child_environment = try options_module.childEnvironment(allocator, init.environ_map, options.controls.ceilings.threads);
            // The test processes get the caller's address space back; this process keeps its ceiling.
            const address_space = @import("memory_budget").guestAddressSpaceLimit(init.environ_map) orelse std.math.maxInt(u64);
            const resources: run_tests.Resources = .{ .arena = allocator, .backing = init.gpa, .io = init.io, .environment = .{ .map = &child_environment }, .campaign = &campaign, .address_space = address_space };
            const workers: run_tests.Workers = .{ .width = width, .batch = if (run_tests.isolated(init.environ_map)) 1 else std.math.maxInt(usize), .permits = permits };
            try run_tests.run(resources, options, .{ .path = executable.path, .program = checked.program }, chosen, live.items, workers);
            return executed;
        },
    }
}

/// What an execution needs besides the selection: the campaign guard that rejects a range if its checked inputs changed,
/// and the shared tier rule's reading of the program `select` made for the same cases.
const Execution = struct { campaign: run_tests.Campaign, private: bool = false, program: ?*portable.Program = null };

/// The positions of `live` whose tests may publish receipts (no live effects).
fn publishing(a: std.mem.Allocator, checked: frontend.Checked, chosen: []const Selected, live: []const usize, program: ?*portable.Program) Error![]const usize {
    var found: std.ArrayList(usize) = .empty;
    for (live) |position| if (try publishes(a, checked, chosen[position].case, program)) try found.append(a, position);
    return found.items;
}

/// A built test executable and its linked program's exact key.
const Executable = struct { path: []const u8, program_key: ?[32]u8 };
const Built = union(enum) { built: Executable, failed: report.Verdict };

/// Build the executable for `chosen[positions]`; its dispatch table lists them in order. The build's working memory (the
/// lowered module, the passes, the emission, its log) lives in an arena of its own, freed when the build ends, and only the
/// executable's path and a failure's text are copied into `init.arena`: the runner builds the whole selection and, when the
/// backend rejects one test, each test alone and the rest again, so a build that left its compile in `init.arena` (which
/// lives to the end of the process) cost the process one compile per rebuild.
fn buildExecutable(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []const Selected, positions: []const usize, label: Label) Error!Built {
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    var working = init;
    working.arena = &scratch;
    const built = try buildWithin(working, options, checked, chosen, positions, label);
    const keep = init.arena.allocator();
    return switch (built) {
        .built => |executable| .{ .built = .{ .path = try keep.dupe(u8, executable.path), .program_key = executable.program_key } },
        .failed => |failure| .{ .failed = blk: {
            var kept = failure;
            kept.reason = try keep.dupe(u8, failure.reason);
            kept.at = try keep.dupe(u8, failure.at);
            break :blk kept;
        } },
    };
}

/// What one executable build is for: the suffix its output name takes (`tag`), and the entry's root-relative path
/// (`source_path`, RECEIPT-PATHS-1) that its linked programs' family names with the case. Two files with one basename
/// in different directories therefore keep separate budgets, and the same project keys alike at any checkout.
const Label = struct { tag: []const u8 = "", source_path: []const u8 };

fn buildWithin(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []const Selected, positions: []const usize, label: Label) Error!Built {
    const allocator = init.arena.allocator();
    const name = chosen[positions[0]].case.name;
    const cases = try allocator.alloc(discover.Case, positions.len);
    for (positions, cases) |position, *case| case.* = chosen[position].case;
    var why: build.Refusal = .{};
    var module = programFor(allocator, options, checked, cases, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = if (why.reason.len != 0) why.reason else "property copied-value adapter type", .details = .{ .rule = why.rule } } },
    };
    const flavor = @tagName(options.build.mode);
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, allocator) catch options.path;
    var digest: [8]u8 = undefined;
    fast_blake3.hash(absolute, &digest);
    const directory = options.build.output;
    var request = options.build;
    request.output = try std.fmt.allocPrint(allocator, "{s}/{s}-{x}-{s}{s}", .{ directory, frontend.entryOf(options.path).module, digest, flavor, label.tag });
    // `--emit-certificates DIR`: each built program's certificates go in a directory of its own named by its module.
    if (options.build.show.certificates) |root| request.show.certificates = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, frontend.entryOf(options.path).module });
    var log: std.ArrayList(u8) = .empty;
    // ENTRY-PATH-1: the program names its entry by basename, so its bytes and
    // execution keys do not depend on the checkout's location.
    // The program's family is its entry's root-relative path and its case, portable across checkouts: one test program
    // keeps its newest four links, whatever its bytes.
    const identity = try std.fmt.allocPrint(allocator, "{s}#{s}{s}", .{ label.source_path, name, label.tag });
    const unit: pipeline.Unit = .{ .src = checked.src, .source_path = std.fs.path.basename(options.path), .main = .{}, .refusal = &why, .identity = identity };
    const program_key = pipeline.finish(init, &module, unit, request, &log) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return .{ .failed = try pipelineRefusal(allocator, name, checked.src, why, log.items) },
        else => return .{ .failed = .{ .name = name, .status = .failed, .reason = try std.fmt.allocPrint(allocator, "build error ({s}): {s}", .{ @errorName(err), try failureLine(allocator, log.items) }) } },
    };
    return .{ .built = .{ .path = request.output, .program_key = program_key } };
}

fn pipelineRefusal(allocator: std.mem.Allocator, name: []const u8, src: @import("selka").source.Source, why: build.Refusal, log: []const u8) Error!report.Verdict {
    var verdict: report.Verdict = .{ .name = name, .status = .unsupported, .reason = try firstLine(allocator, log) };
    if (why.rule) |rule| {
        const at = frontend.position(src, .{ .start = why.span, .end = why.span });
        verdict.reason = why.reason;
        verdict.at = try std.fmt.allocPrint(allocator, "{d}:{d}", .{ at.line, at.column });
        verdict.details.rule = rule;
    }
    return verdict;
}

test "ownership pipeline test verdict preserves structured refusal instead of truncating its rule note" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = try @import("selka").source.Source.init(arena.allocator(), "test.selka", "name\n");
    const owned = try pipelineRefusal(arena.allocator(), "m::test_one", src, .{ .reason = "borrowed storage", .span = 1, .rule = .Z3 }, "error[E_CORE_UNSUPPORTED]: borrowed storage\n  note: ownership rule Z3\n");
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.Z3, owned.details.rule.?);
    try std.testing.expectEqualStrings("borrowed storage", owned.reason);
    try std.testing.expectEqualStrings("1:2", owned.at);
    const ordinary = try pipelineRefusal(arena.allocator(), "m::test_one", src, .{}, "ordinary backend refusal\nmore context\n");
    try std.testing.expect(ordinary.details.rule == null);
    try std.testing.expectEqualStrings("ordinary backend refusal", ordinary.reason);
    try std.testing.expectEqualStrings("", ordinary.at);
}

fn programFor(allocator: std.mem.Allocator, options: Options, checked: frontend.Checked, cases: []const discover.Case, why: *build.Refusal) (Error || build.CachedError || batch_entry.Error)!@import("ir.zig").Module {
    const roots = try rootsFor(allocator, checked.program, cases);
    // A test that returns one comparison names its operands when it fails (`build.Input.compared_returns`); a property test,
    // whose inputs a search generates, reports as it did.
    var plain: std.ArrayList(typed.FunctionId) = .empty;
    for (cases) |case| if (std.mem.indexOfScalar(u8, case.parameters, 255) == null) try plain.append(allocator, case.function);
    var input = loweringInput(checked);
    input.compared_returns = plain.items;
    const reachable = try build.buildRootsCached(allocator, roots, input, why, null);
    return withEntry(allocator, options, checked, cases, reachable);
}

/// Case `case`'s row of the runner's dispatch table, at `table_index`.
fn testTarget(allocator: std.mem.Allocator, options: Options, checked: frontend.Checked, case: discover.Case, table_index: u32) Error!entry.Target {
    const function = checked.program.functions[@backingInt(case.function)];
    const result = typed.resultShape(function.signature.return_type, checked.program.records);
    const parameters = try allocator.alloc([]const u8, function.signature.parameter_count);
    for (parameters, function.scope.locals[0..function.signature.parameter_count]) |*name_slot, parameter| name_slot.* = typed.typeName(parameter.ty, checked.program.records);
    return .{
        .function = table_index,
        .streams = case.streams,
        .parameters = case.parameters,
        .seed = run_tests.entropySeed(options.properties.seed, case.name),
        .data = .{ .parameters = parameters, .result = typed.typeName(function.signature.return_type, checked.program.records) },
        .result = if (result) |shape| .{ .ok_tag = @intCast(shape.ok_tag), .error_tag = @intCast(shape.error_tag) } else null,
    };
}

/// `reachable` (the cases' functions) with the runner's entry and step budget added.
fn withEntry(allocator: std.mem.Allocator, options: Options, checked: frontend.Checked, cases: []const discover.Case, reachable: @import("ir.zig").Module) (Error || batch_entry.Error)!@import("ir.zig").Module {
    var module = reachable;
    try qualifyHeaderless(allocator, &module, checked.program, cases);
    const targets = try allocator.alloc(entry.Target, cases.len);
    for (targets, cases, 0..) |*target, case, table_index| target.* = try testTarget(allocator, options, checked, case, @intCast(table_index));
    const schema = try property_types.Schema.init(allocator, try property_schema.definitions(allocator, checked.program));
    const originals = module.functions.items.len;
    try batch_entry.add(allocator, &module, targets, schema);
    try @import("test_runner_budget.zig").instrument(allocator, &module, originals, options.controls);
    return module;
}

fn firstLine(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return allocator.dupe(u8, std.mem.sliceTo(std.mem.trim(u8, text, "\n"), '\n'));
}

/// The line of a failed build's report that says why it failed: the first error line (`error[...]`, located or an internal error),
/// else the first line. A validator's summary or a warning can come before the error (`selka: ownership: N functions validated`).
fn failureLine(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const located = std.mem.indexOf(u8, line, ": error[") != null;
        if (located or std.mem.startsWith(u8, line, "error[") or std.mem.startsWith(u8, line, "internal error[")) return allocator.dupe(u8, line);
    }
    return firstLine(allocator, text);
}

test "a failed test build names its error line, not a summary printed before it" {
    const a = std.testing.allocator;
    const named = try failureLine(a, "selka: ownership: 1342 functions validated, 0 unchecked\nerror[E_FACT_VALIDATION]: fact validation rejected f\n  note: x\n");
    defer a.free(named);
    try std.testing.expectEqualStrings("error[E_FACT_VALIDATION]: fact validation rejected f", named);
    const internal = try failureLine(a, "warning: w\ninternal error[E_CORE_INVALID_IR]: f: bad\n");
    defer a.free(internal);
    try std.testing.expectEqualStrings("internal error[E_CORE_INVALID_IR]: f: bad", internal);
    const plain = try failureLine(a, "\nselka: build failed (ToolFailed): a build tool failed\n");
    defer a.free(plain);
    try std.testing.expectEqualStrings("selka: build failed (ToolFailed): a build tool failed", plain);
}

fn rootsFor(a: std.mem.Allocator, program: typed.Program, cases: []const discover.Case) Error![]const typed.FunctionId {
    var roots: std.ArrayList(typed.FunctionId) = .empty;
    var generated = false;
    for (cases) |case| {
        try roots.append(a, case.function);
        generated = generated or std.mem.indexOfScalar(u8, case.parameters, 255) != null;
    }
    if (!generated) return roots.toOwnedSlice(a);
    const schema = try property_types.Schema.init(a, try property_schema.definitions(a, program));
    for (program.functions) |candidate| {
        const prefix = "@invariant:";
        if (!std.mem.startsWith(u8, candidate.name, prefix)) continue;
        var needed = false;
        for (cases) |case| {
            const f = program.functions[@backingInt(case.function)];
            for (f.scope.locals[0..f.signature.parameter_count], case.parameters) |parameter, family| {
                if (family != 255) continue;
                needed = needed or try property_types.reaches(schema, typed.typeName(parameter.ty, program.records), candidate.name[prefix.len..]);
            }
        }
        if (needed) try roots.append(a, candidate.id);
    }
    return roots.toOwnedSlice(a);
}

/// ERROR-TRACE-3: a header-less file is checked alone, so its functions carry bare
/// names; the old runner checked it as the module its stem names, and its error
/// traces and trap frames say `module::name`. Qualify the file's own functions so the
/// new core's say the same. A module entry's functions are already qualified.
fn qualifyHeaderless(allocator: std.mem.Allocator, module: *@import("ir.zig").Module, program: typed.Program, cases: []const discover.Case) Error!void {
    if (std.mem.indexOf(u8, program.functions[@backingInt(program.main)].name, "::") != null or cases.len == 0) return;
    const split = std.mem.lastIndexOf(u8, cases[0].name, "::") orelse return;
    const prefix = cases[0].name[0 .. split + 2];
    for (module.functions.items) |*function| {
        if (function.signature.linkage != .internal or function.name.len == 0) continue;
        if (!std.ascii.isAlphabetic(function.name[0]) or std.mem.indexOf(u8, function.name, "::") != null) continue;
        function.name = try std.mem.concat(allocator, u8, &.{ prefix, function.name });
    }
}

// spec-case: NEW-CORE-TEST-KEYS-1
// spec-case: PROPERTY-TEST-2
test "rootsFor preserves plain root order and duplicates and includes only reachable generated invariants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\@invariant(self.low <= self.high)
        \\record Interval:
        \\    low: int
        \\    high: int
        \\
        \\@invariant(self.value >= 0)
        \\record Unrelated:
        \\    value: int
        \\
        \\public func test_generated(value: Interval) -> bool:
        \\    return value.low <= value.high
        \\
        \\public func test_plain() -> bool:
        \\    return True
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    var unit = try @import("selka").Compilation.init(a, "roots.selka", text);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    const cases = try discover.discover(a, program, "roots", &.{.{ .name = "roots", .text = text }});
    try std.testing.expectEqual(@as(usize, 2), cases.len);
    try std.testing.expectEqual(@as(usize, 0), (try rootsFor(a, program, &.{})).len);
    const plain = try rootsFor(a, program, &.{ cases[1], cases[1] });
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ cases[1].function, cases[1].function }, plain);
    const generated = try rootsFor(a, program, &.{ cases[0], cases[1] });
    try std.testing.expectEqual(@as(usize, 3), generated.len);
    try std.testing.expectEqualSlices(typed.FunctionId, &.{ cases[0].function, cases[1].function }, generated[0..2]);
    try std.testing.expectEqualStrings("@invariant:Interval", program.functions[@backingInt(generated[2])].name);
}

// spec-case: NEW-CORE-S4-TEST-3
test "programIdentity propagates allocation failure instead of inventing a reusable success" {
    const resources: IdentityResources = .{ .scratch = std.testing.failing_allocator, .io = std.testing.io };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = "\npublic func test_value() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    const path = try std.fs.path.join(a, &.{ root, "app.selka" });
    var diagnostics: std.ArrayList(u8) = .empty;
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    const checked = try session.checkFile(a, path, &diagnostics);
    const cases = try discover.discover(a, checked.program, "app", &.{.{ .name = "app", .text = source }});
    try std.testing.expectEqual(@as(usize, 1), cases.len);
    try std.testing.expectError(error.OutOfMemory, programIdentity(resources, .{ .path = path, .build = .{ .zig = "zig" } }, checked, cases[0], @splat(0)));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed campaign checkedInputs guard records absent default cases and rejects their appearance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.selka" });
    const context: receipt.Context = .{
        .arena = a,
        .io = std.testing.io,
        .environment = &environment,
        .options = .{ .path = path, .build = .{ .zig = "unselected-tool" }, .properties = .{ .policy = .indexed_v1 } },
        .entry = .{ .path = path, .root = root, .name = "app" },
        .identity = .{ .tool = .{ .path = "unselected-tool", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false } },
    };
    const inputs = try checkedInputs(context, .{ .modules = &.{} }, &.{}, "");
    try std.testing.expect(inputs.len >= 1);
    try std.testing.expectEqualStrings(try case_settings.defaultPath(a, path), inputs[0].path);
    try std.testing.expect(inputs[0].digest == null);
    try std.testing.expect(try receipt.unchanged(context, inputs));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.cases.json", .data = "{}" });
    const guard: run_tests.Campaign = .{ .context = context, .inputs = inputs, .backing = std.testing.allocator };
    try std.testing.expect(!try guard.unchanged());
}

fn configurationGuard(a: std.mem.Allocator, path: []const u8, environment: *const std.process.Environ.Map) !run_tests.Campaign {
    var problems: std.ArrayList(u8) = .empty;
    const located = try project_entry.resolve(a, std.testing.io, path, &problems);
    const context: receipt.Context = .{
        .arena = a,
        .io = std.testing.io,
        .environment = environment,
        .options = .{ .path = located.path, .build = .{ .zig = "unselected-tool" }, .properties = .{ .policy = .indexed_v1 } },
        .entry = located,
        .identity = .{ .tool = .{ .path = "unselected-tool", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false } },
    };
    return .{ .context = context, .inputs = try checkedInputs(context, .{ .modules = &.{} }, &.{}, ""), .backing = a };
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed campaign checkedInputs guard rejects configuration appearing before the nearest existing config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try temporary.dir.createDir(std.testing.io, "inner", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "inner/app.selka", .data = "func main() -> int:\n    return 0\n" });
    const path = try temporary.dir.realPathFileAlloc(std.testing.io, "inner/app.selka", a);
    const absent = try configurationGuard(a, path, &environment);
    try std.testing.expect(try receipt.unchanged(absent.context, absent.inputs));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try std.testing.expect(!try absent.unchanged());
    const configured = try configurationGuard(a, path, &environment);
    try std.testing.expect(configured.context.entry.configuration != null);
    try std.testing.expect(try receipt.unchanged(configured.context, configured.inputs));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "inner/selka.json", .data = "{\"version\":2}" });
    try std.testing.expect(!try configured.unchanged());
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "cacheExplanation reports execution after partial property reuse and unanswered trials" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const context: receipt.Context = .{
        .arena = a,
        .io = std.testing.io,
        .environment = &environment,
        .options = .{ .path = "app.selka", .build = .{ .zig = "unselected-tool" }, .properties = .{ .policy = .indexed_v1 } },
        .entry = .{ .path = "app.selka", .root = ".", .name = "app" },
        .identity = .{
            .tool = .{ .path = "unselected-tool", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false, .cacheable = true },
            .cache_plan = .{ .identity = @splat(11), .mode = .reference, .io = std.testing.io, .environ = &environment, .directory = null, .artifact = null },
        },
    };
    var item: Selected = .{
        .case = .{ .name = "app::test_generated", .function = @fromBackingInt(@intCast(0)), .shape = .boolean, .other_parameters = 1, .streams = &.{} },
        .ready = true,
        .identity = @splat(7),
        .verdict = .{
            .name = "app::test_generated",
            .status = .failed,
            .reason = "native process ended before answering",
            .details = .{ .property = .{
                .seed = 42,
                .counts = .{ .runs = 64, .passed = 32, .processes = 1 },
                .campaign = .{ .generated = 32, .submitted = 32, .observed = 0, .fresh_classified = 0, .reused = 32, .next_ordinal = 32 },
            } },
        },
    };
    const unanswered = try cacheExplanation(a, item, context);
    try std.testing.expectEqualStrings("execute", unanswered.action);
    try std.testing.expectEqualStrings("no-success-receipt", unanswered.reason);
    item.verdict.status = .passed;
    const submitted = try cacheExplanation(a, item, context);
    try std.testing.expectEqualStrings("execute", submitted.action);
    item.verdict.details.property.?.counts.processes = 0;
    item.verdict.details.property.?.counts.passed = 64;
    item.verdict.details.property.?.campaign.?.generated = 0;
    item.verdict.details.property.?.campaign.?.submitted = 0;
    item.verdict.details.property.?.campaign.?.reused = 64;
    item.verdict.details.property.?.campaign.?.next_ordinal = 64;
    const restored = try cacheExplanation(a, item, context);
    try std.testing.expectEqualStrings("reuse", restored.action);
    try std.testing.expectEqualStrings("property-prefix-hit", restored.reason);
    item.verdict.status = .failed;
    const failed = try cacheExplanation(a, item, context);
    try std.testing.expectEqualStrings("execute", failed.action);
}

/// Every discovery, key and executable lowering uses the same checked program.
fn loweringInput(checked: frontend.Checked) build.Input {
    return .{
        .program = checked.program,
        .source = checked.src,
    };
}

// spec-case: TEST-RUNNER-ARENA-1
test "a failed build leaves its working memory behind it: only the failure's text stays in the process arena" {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const text = "public func test_value() -> bool:\n    const value = \"x-\" + str(7)\n    return value == \"x-7\"\n\nfunc main() -> int:\n    return 0\n";
    var unit = try @import("selka").Compilation.init(a, "owned.selka", text);
    defer unit.deinit();
    try unit.check();
    const checked: frontend.Checked = .{ .program = unit.program.?, .src = unit.src };
    const cases = try discover.discover(a, checked.program, "owned", &.{.{ .name = "owned", .text = text }});
    const chosen = [_]Selected{.{ .case = cases[0], .verdict = .{ .name = cases[0].name, .status = .unsupported }, .ready = true }};
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    var process_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer process_arena.deinit();
    const init: std.process.Init = .{ .minimal = undefined, .arena = &process_arena, .gpa = std.testing.allocator, .io = std.testing.io, .environ_map = &environment, .preopens = undefined };
    // No toolchain: each build lowers the module and fails when it looks for the tool, as a backend refusal does.
    const options: Options = .{ .path = "owned.selka", .build = .{ .zig = "/nonexistent/zig", .output = "/nonexistent/out", .cache = "/nonexistent/cache" } };
    var held: usize = 0;
    for (0..3) |round| {
        const built = try buildExecutable(init, options, checked, &chosen, &.{0}, .{ .tag = "-probe", .source_path = "owned.selka" });
        try std.testing.expect(built == .failed);
        try std.testing.expect(built.failed.reason.len != 0);
        if (round == 0) held = process_arena.queryCapacity();
    }
    // Three more builds add nothing to what the first kept (a retained compile would add its module each time).
    try std.testing.expect(process_arena.queryCapacity() <= held + 4096);
    try std.testing.expect(held < 64 * 1024);
}

// spec: NEW-CORE-ZERO-RC-TEST-1
test "owned guest test adapter keeps its reachable entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "public func test_value() -> bool:\n    const value = \"x-\" + str(7)\n    return value == \"x-7\"\n\nfunc main() -> int:\n    return 0\n";
    var unit = try @import("selka").Compilation.init(a, "owned.selka", text);
    defer unit.deinit();
    try unit.check();
    const checked: frontend.Checked = .{ .program = unit.program.?, .src = unit.src };
    const cases = try discover.discover(a, checked.program, "owned", &.{.{ .name = "owned", .text = text }});
    try std.testing.expectEqual(@as(usize, 1), cases.len);
    var why: build.Refusal = .{};
    const options: Options = .{ .path = "owned.selka", .build = .{ .zig = "zig" } };
    const module = try programFor(a, options, checked, cases, &why);
    try std.testing.expectEqualStrings(entry.entry_name, module.functions.items[module.entry].name);
}
