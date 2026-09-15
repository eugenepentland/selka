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
const budget = @import("memory_budget");
/// Setup failures never produce a cached green test run.
pub const Error = sessions.Error || cases.Error || planner.Error || receipts.Error || fanout.Error || contracts.Error;
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
    const session = try sessions.Session.init(context, opts);
    defer context.remove(session.temporary);
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
    const config_bytes = if (opts.cases) |path| try context.read(path) else "null";
    const config = (try std.json.parseFromSlice(std.json.Value, context.allocator, config_bytes, .{ .allocate = .alloc_always })).value;
    const declared_schema = try contracts.testSchema(context.allocator, production);
    const selected = try cases.discover(context.allocator, declared_schema, config, opts.filter);
    const results = try context.allocator.alloc(receipts.Result, selected.len);
    const directory = try std.fs.path.join(context.allocator, &.{ session.directory, "results" });
    try context.mkdir(directory);
    for (selected, results) |case, *result| result.* = perform(session, captured, production, case, directory) catch |err| switch (err) {
        error.ProjectConfigurationFailed => return 2,
        error.ProjectPolicyRejected => return 3,
        else => return err,
    };
    try session.verify();
    if (opts.cases) |path| {
        if (!std.mem.eql(u8, config_bytes, try context.read(path))) return error.SourceChanged;
    }
    for (results) |result| try receipts.write(context, directory, result);
    return report(context, results, opts.json);
}
fn perform(session: sessions.Session, captured: snapshot.Snapshot, production: std.json.Value, case: cases.Case, directory: []const u8) Error!receipts.Result {
    var result: receipts.Result = .{ .name = case.name, .status = "skipped", .expected = case.expected };
    if (case.skip) |reason| {
        result.reason = reason;
        return result;
    }
    var checked: sessions.Project = undefined;
    var contract_identity: []const u8 = "";
    var provider_identity: []const u8 = "";
    var source_identity: []const u8 = captured.identity;
    if (case.providers == .object and case.providers.object.count() != 0) {
        // Select and validate the replacement graph before any production body
        // is checked. The unselected production module still had to parse and
        // pass its exported-signature contract above.
        const copied = try snapshot.replace(session.context, captured, case.providers, try session.context.temporary(session.temporary));
        const replacement = try session.interfaceCheck(copied.entry_path);
        const modules = try contracts.moduleNames(session.context.allocator, case.providers);
        try contracts.validate(session.context.allocator, production, replacement, modules);
        provider_identity = try contracts.providerIdentity(session.context.allocator, case.providers);
        contract_identity = try contracts.contractIdentity(session.context.allocator, production, modules);
        source_identity = copied.identity;
        checked = try session.check(copied.entry_path);
    } else {
        const modules = [_][]const u8{try testModuleName(session.context.allocator, case.name)};
        contract_identity = try contracts.contractIdentity(session.context.allocator, production, &modules);
        checked = try session.check(captured.entry_path);
    }
    const project = &checked;
    const identity: receipts.Identity = .{ .contract = contract_identity, .provider = provider_identity, .source = source_identity };
    const selected = checkedFunction(project.schema, case.name) orelse case.function;
    const plan = try planner.plan(session.context.allocator, project.manifest, try symbol(project.manifest, case.name), try session.key(case.settings, selected));
    result.key = try session.context.allocator.dupe(u8, &plan.key);
    result.dependencies = plan.dependencies;
    result.cacheable = plan.cacheable and session.environment.cacheable;
    result.context = .{ .reasons = plan.reasons, .identity = identity };
    const path = try receipts.path(session.context, directory, result.key);
    if (!session.options.force and result.cacheable and receipts.hit(session.context, path, result.key, case.name, case.expected, identity)) {
        result.status = "cached";
        result.actual = case.expected;
        return result;
    }
    // Evict any older pass before a forced or repaired execution can fail.
    try receipts.invalidate(session.context, path);
    const executor = try session.executor(project);
    const outcome = try executor.execute(selected, case.arguments, session.options.limits);
    result.actual = outcome.actual;
    result.steps = outcome.steps;
    result.reason = try std.mem.replaceOwned(u8, session.context.allocator, outcome.diagnostics, std.fs.path.dirname(project.source).?, session.source.root);
    const passed = std.mem.eql(u8, outcome.status, "value") and snapshot.equivalent(outcome.actual, case.expected);
    result.status = if (passed) "passed" else "failed";
    if (!passed and result.reason.len == 0) result.reason = "actual value does not match expected value";
    return result;
}
/// The checked schema entry for one qualified test name, when present.
fn checkedFunction(schema: std.json.Value, name: []const u8) ?std.json.Value {
    for (v.array(v.get(schema, "functions"))) |function| {
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
    for (v.array(v.get(manifest, "functions"))) |function| {
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
