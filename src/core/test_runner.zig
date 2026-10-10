//! `mylang-core test FILE.my [--release] [--filter S] [--json]` (docs/design/new-core-s1.md §9).
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
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const pipeline = @import("pipeline.zig");
const discover = @import("test_runner_discover.zig");
const entry = @import("test_runner_entry.zig");
const report = @import("test_runner_report.zig");
const typed = @import("mylang").typed;
const property = @import("test_runner_property.zig");
const property_types = @import("property_types.zig");
const property_schema = @import("property_schema.zig");
const run_tests = @import("test_runner_execute.zig");
const root_share = @import("test_runner_shared.zig");
const batch_entry = @import("test_runner_batch.zig");
const directory_runner = @import("test_runner_directory.zig");
const receipt = @import("test_runner_receipt.zig");
const test_keys = @import("test_runner_identity.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const planner = @import("mylang").cache_plan_adapter;
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

/// The old runner's stub, appended to a file that defines no `main` of its own.
pub const check_stub = "\n\nfunc main() -> int:\n    return 0\n";

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = property.Error;

/// What the command line asked for.
pub const Options = options_module.Options;
const options_module = @import("test_runner_options.zig");

const Selected = run_tests.Selected;
const case_expectation = run_tests.expectation;
/// A test's identity work: `scratch` is an arena it may leave allocations in, and
/// `prebuilt` the test's reachable functions when `classify` already built them.
const IdentityResources = struct { scratch: std.mem.Allocator, io: std.Io, prebuilt: ?@import("ir.zig").Module = null };
/// What selection and execution share: the receipts, their base key, and a directory
/// run's test process permits when the entry runs in its process.
const SelectionContext = struct { receipt: receipt.Context, base: [32]u8, permits: ?*root_share.Permits = null, catalog: ?*const lowering_cache.Catalog = null };

/// Check, discover, build and run the tests of `options.path`, print the report, and return
/// the process exit status: 0 ok, 1 a test failed or the file does not check, 2 unreadable
/// or an invalid cases file or provider fixture, 3 nothing selected or every selected test skipped.
pub fn run(init: std.process.Init, requested: Options) Error!u8 {
    return runRequested(init, requested) catch |err| {
        if (err == error.ComponentUnavailable) return 2;
        return err;
    };
}

fn runRequested(init: std.process.Init, requested: Options) Error!u8 {
    if (directory_runner.selected(init.io, requested.path)) return directory_runner.run(init, requested, runRoot);
    return (try runEntry(init, requested, .{})).?;
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

    /// The directory run's test process permits, for an entry it runs in process.
    fn permits(self: Setup) ?*root_share.Permits {
        const directed = self.directed orelse return null;
        return directed.permits;
    }

    /// The entry's share of its directory run's shared check, when it has one.
    fn view(self: Setup) ?root_share.View {
        const directed = self.directed orelse return null;
        return directed.view;
    }

    /// The declaration prefix borrowed from this entry's shared checked snapshot.
    fn catalog(self: Setup) ?*const lowering_cache.Catalog {
        return if (self.view()) |shared_view| shared_view.catalog else null;
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
    var options = requested;
    const allocator = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, options.path, allocator, .limited(64 << 20)) catch |err| return .{ .done = try unreadable(init, options.path, @errorName(err)) };
    const located = project_entry.resolve(allocator, init.io, options.path, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return .{ .done = project_entry.status(err) };
    };
    // A malformed byte ceiling or a frame budget it cannot back is refused like a usage error.
    if (!try applyLimits(init, &options, located)) return .{ .done = 2 };
    // An invalid cases file or provider fixture is a setup failure, status 2 (the old core's).
    const configured_cases = try configuredCases(init, &options, located) orelse return .{ .done = 2 };
    options.controls.cases = configured_cases.path;
    const cache_plan = if (setup.directed) |directed| directed.cache_plan orelse try bindPlan(init) else try bindPlan(init);
    const replayed = if (setup.directed) |directed| try directedReplay(init, options, located, configured_cases.bytes, directed.guest, cache_plan) else try cachedReplay(init, options, located, configured_cases.bytes, cache_plan);
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
    const base = try receipt.settings(context, &native_inputs);
    if (try replayRun(context, base)) |cached| return .{ .done = try emitted(init, setup, cached) };
    if (setup.directed) |directed| if (directed.replay_only) return .{ .done = null };
    return .{ .ready = .{ .context = context, .base = base, .native_inputs = native_inputs.items, .bytes = bytes, .cases = configured_cases } };
}

/// Print a replayed report and answer its status, 0.
fn emitted(init: std.process.Init, setup: Setup, cached: receipt.Replay) Error!u8 {
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
        .ready => |ready| try finish(init, ready, setup),
    };
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
    located.configure(&session);
    if (view == null) try session.enableCache(init.gpa, options.build.cache);
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
    const all_cases = try discoverLoaded(allocator, checked, entry_module, loaded);
    case_settings.validate(configured_cases, all_cases) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(allocator, "error: test cases: {s}\n", .{@errorName(err)}));
        return 2;
    };
    const selection = switch (try chooseCases(init, options, located, checked, all_cases)) {
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
    const selection_context: SelectionContext = .{ .receipt = context, .base = base, .permits = setup.permits(), .catalog = setup.catalog() };
    const shared: GroupRun = .{ .init = init, .selection = selection_context, .session = &session, .base_checked = base_checked, .discovery = checked, .entry = entry_text, .cases = configured_cases };
    for (groups) |group| {
        if (base_checked == null and group.providers.len == 0) return failWith(init, problems.items, 1);
        if (try shared.runGroup(group, entry_module, &collected)) |status| return status;
    }
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
        if (unchanged and item.verdict.status == .passed) if (item.identity) |identity| try receipt.save(context, identity);
    }
    for (collected.wholes.items) |range| if (unchanged and wholePassed(range.whole, chosen.items[range.start..][0..range.len])) try receipt.save(context, range.whole.key);
    attachWork(verdicts, collected.works.items);
    const json = try report.jsonSources(allocator, verdicts, sources.items);
    if (successful and unchanged and options.controls.against == null) try receipt.remember(context, base, before.items, json, collected.warnings.items);
    const out = if (options.json) json else try report.text(allocator, verdicts);
    try emit(init, setup, out);
    try siblingHint(init, loaded, located, verdicts.len);
    return report.exitStatus(verdicts);
}

/// The entry file as every session of a run reads it: its header-less overlay
/// (`headerlessTest`) and whether the old runner's stub `main` is appended.
const EntryText = struct {
    overlay: []const frontend.Provider,
    stub: bool,

    /// Read the entry this way in `session`, with `providers` replacing dependencies.
    fn apply(self: EntryText, session: *frontend.Session, providers: []const frontend.Provider) void {
        session.setProviders(providers);
        if (self.stub) session.entry_suffix = check_stub;
    }
};

/// What a run's provider groups add up: the inputs their verdicts depend on, the
/// sources the report lists and the selected tests.
const Collected = struct {
    warnings: std.ArrayList(u8) = .empty,
    before: std.ArrayList(receipt.Dependency),
    sources: std.ArrayList([]const u8) = .empty,
    chosen: std.ArrayList(Selected) = .empty,
    /// Each provider group's whole-file key and the range of `chosen` it covers.
    wholes: std.ArrayList(WholeRange) = .empty,
    works: std.ArrayList(WorkRange) = .empty,
};
const WorkRange = struct { first: usize, work: *const key_work.Work };
/// A whole-file key and the slice of a run's chosen tests it was computed for.
const WholeRange = struct { whole: Whole, start: usize, len: usize };

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
        const selected = try select(init, context.options, program, cases, self.cases, self.selection);
        const items = selected.items;
        try execute(init, context.options, program, items, self.selection.permits);
        if (identity) |known| for (items) |*item| {
            item.verdict.identity = known;
        };
        if (selected.whole) |whole| try out.wholes.append(a, .{ .whole = whole, .start = out.chosen.items.len, .len = items.len });
        if (items.len != 0) if (selected.work) |work| try out.works.append(a, .{ .first = out.chosen.items.len, .work = work });
        try out.chosen.appendSlice(a, items);
        return null;
    }
};

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

/// `dir/name.my` is module `dir.name`.
fn moduleOfPath(a: std.mem.Allocator, path: []const u8) Error![]const u8 {
    const module = try a.dupe(u8, path[0 .. path.len - ".my".len]);
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
    entry_text.apply(&production, entry_text.overlay);
    production.declare(a, located.name, &problems) catch |err| return checkFailure(init, err, problems.items, 1);
    for (sets) |set| {
        case_settings.available(set, &production, located.name) catch |err|
            return checkFailure(init, err, "error: InvalidTestProviders: invalid test provider dependencies: a provider may replace only a module the entry imports, never the entry\n", 2);
        var replacement = frontend.Session.init(init.gpa, init.io, located.root);
        defer replacement.deinit();
        located.configure(&replacement);
        try replacement.enableCache(init.gpa, options.build.cache);
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

/// Test discovery uses path-qualified module identities for every valid entry.
fn checkEntry(session: *frontend.Session, allocator: std.mem.Allocator, located: project_entry.Entry, problems: *std.ArrayList(u8)) (frontend.Error || error{ReadFailed})!frontend.Checked {
    if (@import("mylang").project.validName(located.name)) return session.check(allocator, located.name, problems);
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
    if (overlay.len == 0) return inputs;
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return std.mem.concat(context.arena, receipt.Dependency, &.{ inputs, &.{.{ .path = context.entry.path, .digest = digest }} });
}

/// CLI-INPUT-REFUSED-1: refuse an entry that cannot be read, naming it and the reason
/// as the old CLI words them, with the usage status.
fn unreadable(init: std.process.Init, path: []const u8, name: []const u8) Error!u8 {
    const reason = if (std.mem.eql(u8, name, "FileNotFound")) "no such file or directory" else if (std.mem.eql(u8, name, "AccessDenied") or std.mem.eql(u8, name, "PermissionDenied")) "permission denied" else name;
    try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(init.arena.allocator(), "mylang test: cannot read '{s}': {s}\n", .{ path, reason }));
    return 2;
}

/// TEST-SIBLING-HINT-1: when nothing is selected and `FILE_test.my` beside the entry
/// exists outside the loaded graph, say so on stderr and how to run it.
fn siblingHint(init: std.process.Init, loaded: Loaded, located: project_entry.Entry, selected: usize) Error!void {
    const a = init.arena.allocator();
    if (selected != 0 or !std.mem.endsWith(u8, located.path, ".my")) return;
    const sibling = try std.fmt.allocPrint(a, "{s}_test.my", .{located.path[0 .. located.path.len - ".my".len]});
    std.Io.Dir.cwd().access(init.io, sibling, .{}) catch return;
    if (!loaded.single()) for (loaded.modules) |module| {
        const path = try std.fs.path.join(a, &.{ located.root, module.src.path });
        if (std.mem.eql(u8, path, sibling)) return;
    };
    try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(a, "mylang test: no tests selected; sibling test file {s} is not included by this entry. Run that file explicitly with mylang test, or test its directory.\n", .{sibling}));
}

/// FMT-TEST-MODULE-1: preserve headerless test bytes in the provider overlay.
/// The project loader obtains module identity from the overlay path.
fn headerlessTest(a: std.mem.Allocator, located: project_entry.Entry, bytes: []const u8) Error![]const frontend.Provider {
    if (!std.mem.endsWith(u8, located.path, "_test.my")) return &.{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const opening = while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len != 0 and line[0] != '#') break line;
    } else return &.{};
    if (!std.mem.startsWith(u8, opening, "import ")) return &.{};
    const relative = try std.mem.concat(a, u8, &.{ try std.mem.replaceOwned(u8, a, located.name, ".", "/"), ".my" });
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
    const reference = options.controls.against orelse return .{ .kept = filtered.items };
    const request: affected.Request = .{ .arena = allocator, .backing = init.gpa, .io = init.io, .root = located.root, .entry = located.path, .reference = reference };
    return affected.narrow(request, checked, filtered.items);
}

/// Describe this invocation's admission decision alongside its result and key.
fn cacheExplanation(a: std.mem.Allocator, item: Selected, context: receipt.Context) Error!report.Cache {
    const status = item.verdict.status;
    const admission = receipt.reuseReason(context);
    const reason = switch (status) {
        .cached => item.cache_reason orelse "receipt-hit",
        .skipped => "configured-skip",
        .unsupported => "unsupported",
        else => if (!std.mem.eql(u8, admission, "no-success-receipt")) admission else item.cache_reason orelse if (item.identity == null) "uncacheable-metadata" else "no-success-receipt",
    };
    return .{
        .action = switch (status) {
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

/// The whole run's recorded report, unless `--affected` selects by unrecorded git state.
fn replayRun(context: receipt.Context, base: [32]u8) Error!?receipt.Replay {
    if (context.options.controls.against != null) return null;
    return receipt.replay(context, base);
}

fn cachedReplay(init: std.process.Init, options: Options, located: project_entry.Entry, case_bytes: []const u8, cache_plan: planner.Bound) Error!?receipt.Replay {
    if (options.controls.against != null) return null;
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

/// The recorded report of an entry under `guest`, the toolchain its directory run
/// identified and validates once for every root.
fn directedReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8, guest: tool_identity.Identity, cache_plan: planner.Bound) Error!?receipt.Replay {
    if (requested.controls.against != null) return null;
    const a = init.arena.allocator();
    var options = requested;
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = a, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = case_bytes, .identity = .{ .tool = guest, .cache_plan = cache_plan } };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    return receipt.replayProvisional(context, try receipt.settings(context, &native_inputs));
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
    _ = try receipt.replayProvisional(context, base) orelse return null;
    if (!try receipt.toolUnchanged(context)) return null;
    // Source/dependency bytes must still agree after the full tool validation.
    return receipt.replayProvisional(context, base);
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
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cannot identify guest toolchain: {s}\n", .{@errorName(err)}));
        return null;
    };
}

/// Settle the step, frame and byte ceilings: a flag, then (memory only) `MYLANG_MEMORY_LIMIT`,
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
        try writeAll(init, std.Io.File.stderr(), "error: MYLANG_MEMORY_LIMIT is not a byte count with an optional K, M or G suffix\n");
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
fn publishes(checked: frontend.Checked, case: discover.Case) bool {
    const function = checked.program.functions[@backingInt(case.function)];
    const effects = @import("mylang").effect_set;
    return function.policy.host == null and function.policy.effects & effects.bit(.host) == 0;
}

fn programIdentity(resources: IdentityResources, options: Options, checked: frontend.Checked, case: discover.Case, base: [32]u8) Error!?[32]u8 {
    if (!publishes(checked, case)) return null;
    const a = resources.scratch;
    var why: build.Refusal = .{};
    const built = if (resources.prebuilt) |prebuilt| withEntry(a, options, checked, &.{case}, prebuilt) else programFor(a, options, checked, &.{case}, &why);
    const module = built catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const source_path = std.Io.Dir.cwd().realPathFileAlloc(resources.io, options.path, a) catch options.path;
    const identity = receipt.programKey(base, case.name, .{ .module = &module, .source_path = source_path, .locator = pipeline.locator(&checked.src) });
    return identity;
}

/// What `select` chose: every case's verdict so far, and the whole-file key to save
/// when every ready test passes (null when it hit or there is none).
const Chosen = struct { items: []Selected, whole: ?Whole = null, work: ?*const key_work.Work = null };
/// A program's whole-file key and how many ready tests it covers (NEW-CORE-TEST-WHOLE-1).
const Whole = struct { key: [32]u8, ready: usize };

fn select(init: std.process.Init, options: Options, checked: frontend.Checked, cases: []const discover.Case, settings: case_settings.File, selection: SelectionContext) Error!Chosen {
    const a = init.arena.allocator();
    const chosen = try a.alloc(Selected, cases.len);
    const context = selection.receipt;
    for (cases, chosen) |case, *item| {
        const configured = v.get(settings.document, case.name);
        const skip = v.get(configured, "skip");
        const refused = if (skip == .string and skip.string.len != 0) report.Verdict{ .name = case.name, .status = .skipped, .reason = skip.string } else try screen(a, checked, case, configured);
        item.* = .{
            .case = case,
            .verdict = refused orelse .{ .name = case.name, .status = .failed, .reason = "not run" },
            .ready = refused == null,
            .cache_reason = if (refused == null and !publishes(checked, case)) "live-effects" else null,
            .settings = configured,
        };
    }
    if (!perTestKeys(init.environ_map)) if (try sharedKeys(init, options, checked, chosen, selection.base, .{ .planner = context.identity.cache_plan.?, .catalog = selection.catalog })) |keys| {
        if (try receipt.hit(context, keys.whole.key)) {
            for (chosen, keys.tests) |*item, key| if (item.ready) {
                item.* = .{ .case = item.case, .verdict = .{ .name = item.case.name, .status = .cached }, .ready = false, .identity = key, .cache_reason = "whole-receipt-hit", .settings = item.settings, .key_method = keys.method };
            };
            return .{ .items = chosen, .work = keys.work };
        }
        for (chosen, keys.tests) |*item, key| if (item.ready) {
            item.key_method = keys.method;
            item.identity = key;
            if (try receipt.hit(context, key.?)) {
                item.verdict = .{ .name = item.case.name, .status = .cached };
                item.ready = false;
            }
        };
        return .{ .items = chosen, .whole = keys.whole, .work = keys.work };
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
        if (try programIdentity(.{ .scratch = scratch.allocator(), .io = init.io, .prebuilt = built }, options, checked, item.case, selection.base)) |identity| {
            item.identity = receipt.configuredKey(identity, try std.json.Stringify.valueAlloc(a, item.settings, .{}));
            if (try receipt.hit(context, item.identity.?)) {
                item.verdict = .{ .name = item.case.name, .status = .cached };
                item.ready = false;
            }
        }
    }
    return .{ .items = chosen };
}

/// Whether `MYLANG_TEST_KEYS=per-test` asks for every test's key from its own lowering
/// (NEW-CORE-S4-TEST-6) instead of the shared one: the oracle the derived keys are
/// checked against. As a `MYLANG_` variable it also separates the two modes' receipts.
fn perTestKeys(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("MYLANG_TEST_KEYS") orelse "", "per-test");
}

/// Every ready test's configured key (null for the others), and the whole-file key.
const Keys = struct { tests: []const ?[32]u8, whole: Whole, work: *const key_work.Work, method: []const u8 };
const KeyPlanning = struct { planner: planner.Bound, catalog: ?*const lowering_cache.Catalog = null };

/// NEW-CORE-TEST-KEYS-1 and NEW-CORE-TEST-WHOLE-1: lower every ready test of the
/// program once, digest each function canonically, and key each test on the functions
/// it reaches (`test_runner_identity.zig`); the whole-file key joins those keys.
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
        if (!publishes(checked, item.case)) return null;
        try cases.append(s, item.case);
    };
    if (cases.items.len == 0) return null;
    const started = stage_metrics.now(init.io);
    const work = try a.create(key_work.Work);
    work.* = .{ .scope = try workScope(a, options.path, cases.items) };
    const source_path = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, s) catch options.path;
    var source_scope: test_keys.Digest = undefined;
    std.crypto.hash.Blake3.hash(source_path, &source_scope, .{});
    // Each directory root opens its own store, including child processes. Bound
    // catalog scans to that root instead of indexing every other root's facts.
    const cache_root = try std.fs.path.join(s, &.{ options.build.cache, "test-keys", &std.fmt.bytesToHex(source_scope, .lower) });
    const compression = @import("stage_compression.zig").Policy.parse(init.environ_map.get("MYLANG_STAGE_CACHE_COMPRESSION")) catch return null;
    var store = try stage_store.Store.initWithOptions(init.gpa, init.io, cache_root, .{ .compression = compression });
    defer store.deinit();
    const roots = try rootsFor(s, checked.program, cases.items);
    const produced = try sharedFacts(s, .{ .checked = checked, .roots = roots, .catalog = planning_input.catalog }, &store, cache_plan.mode, work) orelse return null;
    const reachable = produced.module;
    const shared = produced.shared;
    if (!readableRoots(&reachable, chosen)) return null;
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
    var saved: ?graph_cache.Prepared = if (produced.identities) |ids| graph_cache.prepare(s, &store, shared, ids, requests, &work.graph) catch |err| blk: {
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
        cached.publish(s, &store, planned.indexes, &work.graph) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return planFailure(init, error.ComponentProtocol);
        };
        _ = try store.flush();
        work.nanoseconds.publication = stage_metrics.elapsed(init.io, publication);
    } else {
        if (!try deriveLegacy(init, cache_plan, .{ .shared = shared, .requests = requests, .roots = root_sets }, derived, work)) return null;
        if (cache_plan.mode == .shadow) try verifyShared(init, checked, roots, requests, derived);
    }

    var whole = std.crypto.hash.Blake3.init(.{});
    whole.update("core-test-whole-v2");
    for (chosen, tests, derived) |item, *slot, key| {
        slot.* = null;
        if (key) |value| {
            slot.* = receipt.configuredKey(value, try std.json.Stringify.valueAlloc(s, item.settings, .{}));
            whole.update(&slot.*.?);
        }
    }
    var key: [32]u8 = undefined;
    whole.final(&key);
    work.storage = store.statistics();
    work.nanoseconds.total = stage_metrics.elapsed(init.io, started);
    return .{ .tests = tests, .whole = .{ .key = key, .ready = cases.items.len }, .work = work, .method = if (saved != null) "canonical-facts" else "reachable-ir" };
}

/// `rootsFor` lists cases first, so ready case `i` is physical function `i`.
fn readableRoots(module: *const @import("ir.zig").Module, chosen: []const Selected) bool {
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

const Produced = struct { module: @import("ir.zig").Module, shared: test_keys.Shared, identities: ?[]const ?test_keys.Digest = null };
const FactInput = struct { checked: frontend.Checked, roots: []const typed.FunctionId, catalog: ?*const lowering_cache.Catalog = null };

/// Header discovery validates raw input receipts before individual canonical fact lookup.
fn sharedFacts(a: std.mem.Allocator, input: FactInput, store: *const stage_store.Store, mode: planner.Mode, work: *key_work.Work) Error!?Produced {
    const checked = input.checked;
    const roots = input.roots;
    if (mode == .reference) return eagerFacts(a, checked, roots, store.io, work);
    var deferred: lowering_cache.Deferred = .{ .arena = a, .store = store };
    var cache: lowering_cache.Cache = .{ .store = store, .lazy = &deferred, .catalog = input.catalog };
    var why: build.Refusal = .{};
    const lowering_start = stage_metrics.now(store.io);
    var module = build.buildRootsCached(a, roots, .{ .program = checked.program, .source = checked.src }, &why, &cache) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        work.nanoseconds.lowering += stage_metrics.elapsed(store.io, lowering_start);
        work.producer.lowering.fresh = cache.lowered;
        work.producer.lowering.reused = cache.reused;
        work.producer.facts.fallback += 1;
        return eagerFacts(a, checked, roots, store.io, work);
    };
    try deferred.prepare(&module, checked.src);
    work.nanoseconds.lowering = stage_metrics.elapsed(store.io, lowering_start);
    work.producer.lowering.fresh = cache.lowered;
    work.producer.lowering.reused = cache.reused;
    const fact_start = stage_metrics.now(store.io);
    const facts = canonical_facts.build(a, &module, pipeline.locator(&checked.src), &deferred, &work.producer.facts) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        work.producer.lowering.materialized = deferred.restored;
        work.nanoseconds.facts += stage_metrics.elapsed(store.io, fact_start);
        work.producer.facts.fallback += 1;
        return eagerFacts(a, checked, roots, store.io, work);
    };
    work.producer.lowering.materialized = deferred.restored;
    work.nanoseconds.facts = stage_metrics.elapsed(store.io, fact_start);
    return .{ .module = module, .shared = facts.shared, .identities = facts.identities };
}

fn workScope(a: std.mem.Allocator, path: []const u8, cases: []const discover.Case) Error![]const u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    for (cases) |case| {
        hash.update(case.name);
        hash.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(a, "{s}#{s}", .{ path, std.fmt.bytesToHex(digest, .lower) });
}

/// Complete independent lowering remains the conservative path for unknown facts.
fn eagerFacts(a: std.mem.Allocator, checked: frontend.Checked, roots: []const typed.FunctionId, io: std.Io, work: *key_work.Work) Error!?Produced {
    var why: build.Refusal = .{};
    const lowering_start = stage_metrics.now(io);
    const module = build.buildRootsSource(a, checked.program, roots, checked.src, &why) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    work.nanoseconds.lowering += stage_metrics.elapsed(io, lowering_start);
    for (module.functions.items) |function| if (function.signature.linkage == .internal) {
        work.producer.lowering.fresh += 1;
    };
    const facts_start = stage_metrics.now(io);
    const shared = test_keys.Shared.build(a, &module, pipeline.locator(&checked.src)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    work.producer.facts.fresh += shared.digests.len;
    work.nanoseconds.facts += stage_metrics.elapsed(io, facts_start);
    return .{ .module = module, .shared = shared };
}

/// Shadow keys come from independent eager lowering with all new metadata disabled.
fn verifyShared(init: std.process.Init, checked: frontend.Checked, roots: []const typed.FunctionId, requests: []const test_keys.Test, derived: []const ?test_keys.Digest) Error!void {
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var why: build.Refusal = .{};
    const module = build.buildRootsSource(a, checked.program, roots, checked.src, &why) catch |err| return planFailure(init, err);
    const shared = test_keys.Shared.build(a, &module, pipeline.locator(&checked.src)) catch |err| return planFailure(init, err);
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
    for (target.parameters) |family| if (family > 5) return true;
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
    var hash = std.crypto.hash.Blake3.init(.{});
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
    var hash = std.crypto.hash.Blake3.init(.{});
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

/// Whether every test a whole-file key covers passed or was reused: each keeps its own
/// identity, and refused or skipped tests (which have none) are outside the key.
fn wholePassed(whole: Whole, items: []const Selected) bool {
    var covered: usize = 0;
    for (items) |item| if (item.identity != null) {
        if (item.verdict.status != .passed and item.verdict.status != .cached) return false;
        covered += 1;
    };
    return covered == whole.ready;
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
    file.writeStreamingAll(init.io, text) catch return error.WriteFailed;
}

/// The verdict of a test that fails before anything is built (a property test that
/// cannot be generated, a result type no test may return), or null.
fn screen(keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, settings: std.json.Value) Error!?report.Verdict {
    const arguments = v.get(settings, "arguments");
    const fixed = arguments == .object and arguments.object.count() != 0;
    const expected = expects(settings);
    if (case.other_parameters != 0 and !fixed) {
        if (expected) return .{ .name = case.name, .status = .failed, .reason = "a property test's verdict is its bool result; remove `expected` or supply `arguments`" };
        const function = checked.program.functions[@backingInt(case.function)];
        const definitions = try property_schema.definitions(keep, checked.program);
        const schema = try property_types.Schema.init(keep, definitions);
        for (function.scope.locals[0..function.signature.parameter_count], case.parameters) |parameter, family| {
            if (family != 255 and family <= 5) continue;
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
        return .{ .name = case.name, .status = .failed, .reason = try std.fmt.allocPrint(keep, property.non_bool_result, .{result}) };
    }
    return null;
}

/// The `unsupported` verdict of a screened test the builder cannot build, or null when
/// it can be built and run; then `built` holds its reachable functions, allocated in `scratch`.
fn classify(scratch: std.mem.Allocator, keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, settings: std.json.Value, built: *?@import("ir.zig").Module) Error!?report.Verdict {
    const expected = expects(settings);
    var why: build.Refusal = .{};
    const selected_roots = try rootsFor(scratch, checked.program, &.{case});
    const module = build.buildRootsSource(scratch, checked.program, selected_roots, checked.src, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => {
            const at = frontend.position(checked.src, .{ .start = why.span, .end = why.span });
            return refusal(case, try keep.dupe(u8, why.reason), try std.fmt.allocPrint(keep, "{d}:{d}", .{ at.line, at.column }));
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
fn moduleName(program: typed.Program, stem: []const u8) []const u8 {
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

/// The modules a root's check loaded, as receipts, discovery and the report read
/// them: its own session's, or its share of a directory run's shared check.
const Loaded = struct {
    session: ?*const frontend.Session = null,
    modules: []const *const frontend.Module = &.{},

    fn of(a: std.mem.Allocator, session: *const frontend.Session) Error!Loaded {
        const list = try a.alloc(*const frontend.Module, session.project.modules.items.len);
        for (session.project.modules.items, list) |*module, *slot| slot.* = module;
        return .{ .session = session, .modules = list };
    }

    /// Whether the check read one header-less file.
    fn single(self: Loaded) bool {
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

fn definesMain(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "func main(") or std.mem.startsWith(u8, line, "public func main(") or std.mem.startsWith(u8, line, "def main(") or std.mem.startsWith(u8, line, "public def main(")) return true;
    }
    return false;
}

/// Build the pending tests together (isolating any the backend rejects) and run each.
fn execute(init: std.process.Init, requested: Options, checked: frontend.Checked, chosen: []Selected, permits: ?*root_share.Permits) Error!void {
    const allocator = init.arena.allocator();
    var live: std.ArrayList(usize) = .empty;
    for (chosen, 0..) |item, position| if (item.ready) try live.append(allocator, position);
    if (live.items.len == 0) return;
    var options = requested;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    options.build.output = try std.fmt.allocPrint(allocator, "{s}/tests/program-{s}", .{ requested.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, options.build.output) catch return error.WriteFailed;
    defer run_tests.removePrivate(init.io, options.build.output);
    var attempt = try buildExecutable(init, options, checked, chosen, live.items, "");
    if (attempt == .failed and live.items.len > 1) {
        // Find which tests the backend rejects by building each alone, then rebuild the rest.
        var good: std.ArrayList(usize) = .empty;
        for (live.items) |position| {
            const alone = try buildExecutable(init, options, checked, chosen, &.{position}, "-probe");
            switch (alone) {
                .built => try good.append(allocator, position),
                .failed => |failure| chosen[position].verdict = failure,
            }
        }
        live = good;
        if (live.items.len == 0) return;
        attempt = try buildExecutable(init, options, checked, chosen, live.items, "");
    }
    switch (attempt) {
        .failed => |failure| for (live.items) |position| {
            chosen[position].verdict = .{ .name = chosen[position].case.name, .status = failure.status, .reason = failure.reason };
        },
        .built => |executable| {
            const width = options_module.width(options.controls, init.environ_map, live.items.len, @import("memory_budget").available(init.io));
            // The pinned Zig arena is thread-safe with Init's thread-safe backing.
            const resources: run_tests.Resources = .{ .arena = allocator, .backing = init.gpa, .io = init.io, .environment = .{ .block = init.minimal.environ.block } };
            const workers: run_tests.Workers = .{ .width = width, .batch = if (run_tests.isolated(init.environ_map)) 1 else std.math.maxInt(usize), .permits = permits };
            try run_tests.run(resources, options, .{ .path = executable, .program = checked.program }, chosen, live.items, workers);
        },
    }
}

const Built = union(enum) { built: []const u8, failed: report.Verdict };

/// Build the executable for `chosen[positions]`; its dispatch table lists them in order.
fn buildExecutable(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []const Selected, positions: []const usize, tag: []const u8) Error!Built {
    const allocator = init.arena.allocator();
    const name = chosen[positions[0]].case.name;
    const cases = try allocator.alloc(discover.Case, positions.len);
    for (positions, cases) |position, *case| case.* = chosen[position].case;
    var why: build.Refusal = .{};
    var module = programFor(allocator, options, checked, cases, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = if (why.reason.len != 0) why.reason else "property copied-value adapter type" } },
    };
    const flavor = @tagName(options.build.mode);
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, allocator) catch options.path;
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash(absolute, &digest, .{});
    const directory = options.build.output;
    var request = options.build;
    request.output = try std.fmt.allocPrint(allocator, "{s}/{s}-{x}-{s}{s}", .{ directory, frontend.entryOf(options.path).module, digest, flavor, tag });
    var log: std.ArrayList(u8) = .empty;
    const unit: pipeline.Unit = .{ .src = checked.src, .source_path = absolute, .main = .{} };
    _ = pipeline.finish(init, &module, unit, request, &log) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = try firstLine(allocator, log.items) } },
        else => return .{ .failed = .{ .name = name, .status = .failed, .reason = try std.fmt.allocPrint(allocator, "build error ({s}): {s}", .{ @errorName(err), try firstLine(allocator, log.items) }) } },
    };
    return .{ .built = request.output };
}

fn programFor(allocator: std.mem.Allocator, options: Options, checked: frontend.Checked, cases: []const discover.Case, why: *build.Refusal) (Error || build.Error || batch_entry.Error)!@import("ir.zig").Module {
    const roots = try rootsFor(allocator, checked.program, cases);
    const reachable = try build.buildRootsSource(allocator, checked.program, roots, checked.src, why);
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
        .seed = run_tests.entropySeed(options.seed, case.name),
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
    var unit = try @import("mylang").Compilation.init(a, "roots.my", text);
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = source });
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    var diagnostics: std.ArrayList(u8) = .empty;
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    const checked = try session.checkFile(a, path, &diagnostics);
    const cases = try discover.discover(a, checked.program, "app", &.{.{ .name = "app", .text = source }});
    try std.testing.expectEqual(@as(usize, 1), cases.len);
    try std.testing.expectError(error.OutOfMemory, programIdentity(resources, .{ .path = path, .build = .{ .zig = "zig" } }, checked, cases[0], @splat(0)));
}
