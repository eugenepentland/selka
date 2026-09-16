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
const graph_store = @import("native_test_graph.zig");
const invalidation = @import("invalidation.zig");
const budget = @import("memory_budget");
/// Setup failures never produce a cached green test run.
pub const Error = sessions.Error || cases.Error || planner.Error || receipts.Error || fanout.Error || contracts.Error || graph_store.Error;

/// One fully checked and (when needed) prepared project graph. Cases that
/// select the same provider replacement set share it, including the native
/// library executor; execution itself remains one isolated process per case.
const Graph = struct {
    project: sessions.Project,
    provider_identity: []const u8,
    source_identity: []const u8,
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

    fn deinit(self: *Graphs) void {
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
        const key = try graph_store.key(self.allocator, .{
            .compiler_identity = session.hashes[0],
            .zig_stamp = session.hashes[1],
            .qbe_stamp = session.hashes[2],
            .mode = session.options.mode,
            .environment_hash = session.environment.hash,
            .source_identity = source_identity,
            .provider_identity = provider_identity,
        });
        // A forced run must re-check and re-emit fresh facts; a `--no-cache` run
        // reads and writes no durable entry at all.
        if (durableReuseAllowed(session.options, session.environment.cacheable)) {
            if (graph_store.load(session.context, self.directory, key)) |facts| {
                try session.validate(entry_path);
                return session.projectFromValue(entry_path, facts);
            }
        }
        const compile = try sessions.Compile.start(session, entry_path);
        // Any failure after the session starts must reap it; a successful return
        // transfers the retained compilation to the graph.
        errdefer compile.finish(session);
        const facts = try compile.facts(session);
        var project = try session.projectFromManifest(entry_path, facts);
        project.compile = compile;
        if (!session.options.flags.no_cache and session.environment.cacheable) {
            const payload = std.json.Stringify.valueAlloc(self.allocator, project.manifest, .{}) catch return error.OutOfMemory;
            graph_store.store(session.context, self.directory, key, payload) catch |err| ignoreStoreFailure(err);
        }
        return project;
    }
};
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
    if (opts.flags.report) session.work = &work;
    const captured = try snapshot.materialize(context, session.source, try context.temporary(session.temporary));
    // Resolve configuration first. `list-interfaces --contracts` parses every
    // module and validates exported signatures and explicit ceilings without
    // checking any body, so an unfinished replacement target cannot block
    // selection while its public declarations stay valid.
    const production = session.interfaceCheck(captured.entry_path) catch |err| switch (err) {
        error.ProjectConfigurationFailed => return 2,
        error.ProjectPolicyRejected => return 3,
        else => return err,
    };
    const directory = try std.fs.path.join(context.allocator, &.{ session.directory, "results" });
    const graphs_directory = if (opts.flags.no_cache) "" else try std.fs.path.join(context.allocator, &.{ session.directory, "graphs" });
    var graphs: Graphs = .{ .allocator = context.allocator, .session = session, .captured = captured, .production = production, .directory = graphs_directory };
    defer graphs.deinit();
    const config_bytes = if (opts.cases) |path| try context.read(path) else "null";
    const config = (try std.json.parseFromSlice(std.json.Value, context.allocator, config_bytes, .{ .allocate = .alloc_always })).value;
    const declared_schema = try contracts.testSchema(context.allocator, production);
    const selected = try cases.discover(context.allocator, declared_schema, config, opts.filter);
    const results = try context.allocator.alloc(receipts.Result, selected.len);
    try context.mkdir(directory);
    var pending: std.ArrayList(Pending) = .empty;
    defer pending.deinit(context.allocator);

    planSelectedCases(context, &graphs, directory, selected, results, &pending) catch |err| switch (err) {
        error.ProjectConfigurationFailed => return 2,
        error.ProjectPolicyRejected => return 3,
        else => return err,
    };
    try prepareSelectedGraphs(context, session, results, pending.items);
    try executeSelectedCases(context, session, selected, results, pending.items);
    // Reap any retained checked-compilation sessions before the invocation's own
    // work report so their child counters are folded into it.
    graphs.finishSessions();
    try session.verify();
    if (opts.cases) |path| {
        if (!std.mem.eql(u8, config_bytes, try context.read(path))) return error.SourceChanged;
    }
    if (!opts.flags.no_cache) for (results) |result| try receipts.write(context, directory, result);
    if (opts.flags.report) try emitWorkReport(context, &work, results);
    return report(context, results, opts.flags.json);
}

/// Record the native test outcome as real performed/reused work. Parser, body
/// check, lowering, emission and link counts come from the compiler children's
/// own `work-report-v1` lines, which `Session.observe` folded in.
fn emitWorkReport(context: fs.Context, work: *invalidation.Work, results: []const receipts.Result) Error!void {
    var executed: usize = 0;
    var cached: usize = 0;
    for (results) |result| {
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
fn planSelectedCases(
    context: fs.Context,
    graphs: *Graphs,
    directory: []const u8,
    selected: []const cases.Case,
    results: []receipts.Result,
    pending: *std.ArrayList(Pending),
) Error!void {
    for (selected, 0..) |case, case_index| {
        const result = &results[case_index];
        result.* = .{ .name = case.name, .status = "skipped", .expected = case.expected };
        if (case.skip) |reason| {
            result.reason = reason;
            continue;
        }
        const has_providers = case.providers == .object and case.providers.object.count() != 0;
        const graph = try graphs.get(case);
        const contract_identity = if (has_providers) blk: {
            const modules = try contracts.moduleNames(context.allocator, case.providers);
            break :blk try contracts.contractIdentity(context.allocator, graphs.production, modules);
        } else blk: {
            const modules = [_][]const u8{try testModuleName(context.allocator, case.name)};
            break :blk try contracts.contractIdentity(context.allocator, graphs.production, &modules);
        };
        const project = &graph.project;
        const identity: receipts.Identity = .{ .contract = contract_identity, .provider = graph.provider_identity, .source = graph.source_identity };
        const checked = checkedFunction(project.schema, case.name) orelse case.function;
        const session = graphs.session;
        const plan = try planner.plan(context.allocator, project.manifest, try symbol(project.manifest, case.name), try session.key(case.settings, checked));
        result.key = try context.allocator.dupe(u8, &plan.key);
        result.dependencies = plan.dependencies;
        result.cacheable = plan.cacheable and session.environment.cacheable;
        result.context = .{ .reasons = plan.reasons, .identity = identity };
        const path = try receipts.path(context, directory, result.key);
        if (durableReuseAllowed(session.options, result.cacheable) and receipts.hit(context, path, result.key, case.name, case.expected, identity)) {
            result.status = "cached";
            result.actual = case.expected;
            continue;
        }
        // Evict any older pass before a forced or repaired execution can fail.
        if (!session.options.flags.no_cache) try receipts.invalidate(context, path);
        try pending.append(context.allocator, .{ .case_index = case_index, .graph = graph, .selected = checked });
    }
}

fn prepareSelectedGraphs(
    context: fs.Context,
    session: sessions.Session,
    results: []receipts.Result,
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
        for (results[entry.case_index].dependencies) |dependency| {
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

fn executeSelectedCases(
    context: fs.Context,
    session: sessions.Session,
    selected: []const cases.Case,
    results: []receipts.Result,
    pending: []const Pending,
) Error!void {
    for (pending) |entry| {
        const case = selected[entry.case_index];
        const result = &results[entry.case_index];
        const executor = entry.graph.project.executor orelse return error.InvalidGraph;
        const outcome = try executor.execute(entry.selected, case.arguments, session.options.limits);
        result.actual = outcome.actual;
        result.steps = outcome.steps;
        result.reason = try std.mem.replaceOwned(u8, context.allocator, outcome.diagnostics, std.fs.path.dirname(entry.graph.project.source).?, session.source.root);
        const passed = std.mem.eql(u8, outcome.status, "value") and snapshot.equivalent(outcome.actual, case.expected);
        result.status = if (passed) "passed" else "failed";
        if (!passed and result.reason.len == 0) result.reason = "actual value does not match expected value";
    }
}

const Pending = struct {
    case_index: usize,
    graph: *Graph,
    selected: std.json.Value,
};

const Group = struct {
    graph: *Graph,
    symbols: std.StringHashMapUnmanaged(void) = .empty,
    names: std.ArrayList([]const u8) = .empty,
};

/// The checked schema entry for one qualified test name, when present.
fn checkedFunction(schema: std.json.Value, name: []const u8) ?std.json.Value {
    for (v.array(v.get(schema, contracts.functions_key))) |function| {
        if (std.mem.eql(u8, name, v.text(v.get(function, "name")))) return function;
    }
    return null;
}
/// The module part of a `module::name` qualified test identity.
fn testModuleName(allocator: std.mem.Allocator, qualified: []const u8) Error![]const u8 {
    const at = std.mem.indexOf(u8, qualified, "::") orelse return error.UnknownFunction;
    return allocator.dupe(u8, qualified[0..at]);
}
fn symbol(manifest: std.json.Value, name: []const u8) Error![]const u8 {
    for (v.array(v.get(manifest, contracts.functions_key))) |function| {
        if (std.mem.eql(u8, name, v.text(v.get(v.get(function, "export"), "name")))) return v.text(v.get(function, "symbol"));
    }
    return error.UnknownFunction;
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
    const script = try std.fs.path.join(context.allocator, &.{ root, "fake-compiler" });
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(context.allocator, "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"");
    try text.appendSlice(context.allocator, log);
    try text.appendSlice(context.allocator, "\"\ncase \"$1\" in\n  list-interfaces) printf '%s\\n' '");
    const contracts_json = "{\"version\":\"interface-contracts-v2\",\"modules\":[{\"name\":\"production\",\"declarations\":[{\"name\":\"value\",\"kind\":\"function\",\"generics\":\"\",\"signature\":\"def() -> i64 effects()\"," ++
        "\"permissions\":\"effects=;mutates=;origin=unknown\"}]}]}";
    try text.appendSlice(context.allocator, contracts_json);
    const graph_manifest =
        "{\"abi\":\"test-abi\"," ++
        "\"schema\":\"{\\\"functions\\\":[],\\\"types\\\":[]}\"," ++
        "\"functions\":[{\"name\":\"main::x\",\"symbol\":\"sym\"," ++
        "\"test_dependencies\":{\"implementation_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\"," ++
        "\"dependencies\":[],\"cacheable\":true,\"reasons\":[]}}]}";
    try text.appendSlice(context.allocator, "' ;;\n  native-test-compile)\n" ++
        "    while read -r action first second; do\n" ++
        "      case \"$action\" in\n" ++
        "        facts) printf '%s' '" ++ graph_manifest ++ "' > \"$first\" ;;\n" ++
        "        lower) printf '%s' '" ++ graph_manifest ++ "' > \"$second\" ;;\n" ++
        "        quit) exit 0 ;;\n" ++
        "      esac\n" ++
        "      printf '%s\\n' '{\"version\":\"native-test-compile-v1\",\"action\":\"ok\",\"status\":0,\"failure\":null,\"lowered_functions\":0,\"emitted_fragments\":0}'\n" ++
        "    done\n    ;;\nesac\n");
    var file = try std.Io.Dir.createFileAbsolute(context.io, script, .{ .permissions = .executable_file });
    try file.writeStreamingAll(context.io, text.items);
    file.close(context.io);
    var parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, contracts_json, .{ .allocate = .alloc_always });
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
    const ordinary: cases.Case = .{ .name = "main::test_ordinary", .function = .null, .arguments = .null, .expected = .null, .skip = null, .providers = .null, .settings = .null };
    const ordinary_first = try graphs.get(ordinary);
    const ordinary_second = try graphs.get(ordinary);
    try std.testing.expectEqual(ordinary_first, ordinary_second);
    var first_providers: std.json.ObjectMap = .empty;
    try first_providers.put(context.allocator, "production.my", .{ .string = "module production; // one" });
    const first_provider: cases.Case = .{ .name = "main::test_provider_one", .function = .null, .arguments = .null, .expected = .null, .skip = null, .providers = .{ .object = first_providers }, .settings = .null };
    const provider_first = try graphs.get(first_provider);
    const provider_second = try graphs.get(first_provider);
    try std.testing.expectEqual(provider_first, provider_second);
    var second_providers: std.json.ObjectMap = .empty;
    try second_providers.put(context.allocator, "production.my", .{ .string = "module production; // two" });
    const second_provider: cases.Case = .{ .name = "main::test_provider_two", .function = .null, .arguments = .null, .expected = .null, .skip = null, .providers = .{ .object = second_providers }, .settings = .null };
    const provider_distinct = try graphs.get(second_provider);
    try std.testing.expect(provider_first != provider_distinct);
    const calls = try context.read(log);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, calls, "native-test-compile"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, calls, "list-interfaces"));
}

fn report(context: fs.Context, results: []const receipts.Result, json: bool) Error!u8 {
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var cached: usize = 0;
    for (results) |result| {
        if (std.mem.eql(u8, result.status, "passed")) passed += 1;
        if (std.mem.eql(u8, result.status, "failed")) failed += 1;
        if (std.mem.eql(u8, result.status, "skipped")) skipped += 1;
        if (std.mem.eql(u8, result.status, "cached")) cached += 1;
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
        .executed = passed + failed,
    }, .{}) else try std.fmt.allocPrint(context.allocator, "{d} passed, {d} cached, {d} failed, {d} skipped", .{ passed, cached, failed, skipped });
    try std.Io.File.stdout().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "{s}\n", .{output}));
    if (failed != 0) return 1;
    return if (passed + cached != 0) 0 else 3;
}
