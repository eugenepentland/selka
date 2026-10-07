//! `mylang-core test FILE.my [--release] [--filter S] [--json]` (docs/design/new-core-s1.md §9).
//!
//! The file is checked with the old runner's stub `main` appended (so a library checks as a
//! program), its tests are discovered by the old rule, and the supported ones are built into
//! **one executable** whose entry dispatches on `argv[1]` (`test_runner_entry.zig`). Each test
//! runs as its own process, so a trap or a hang ends one test, not the file.
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
const property_execute = @import("property_execute.zig");
const batch_entry = @import("test_runner_batch.zig");
const directory_runner = @import("test_runner_directory.zig");
const receipt = @import("test_runner_receipt.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const case_settings = @import("test_runner_cases.zig");
const v = @import("property_value.zig");

/// The old runner's stub, appended to a file that defines no `main` of its own.
pub const check_stub = "\n\ndef main() -> int:\n    return 0\n";

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = property.Error;

/// What the command line asked for.
pub const Options = @import("test_runner_options.zig").Options;

/// One selected test and its place in the report. `ready` tests have no verdict yet:
/// their `verdict` is filled in by building and running them.
const Selected = struct { case: discover.Case, verdict: report.Verdict, ready: bool, identity: ?[32]u8 = null, settings: std.json.Value = .null };
const case_expectation = "expected";
const IdentityResources = struct { backing: std.mem.Allocator, io: std.Io };
const ExecutionResources = struct { arena: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io };
const SelectionContext = struct { receipt: receipt.Context, base: [32]u8 };

/// Check, discover, build and run the tests of `options.path`, print the report, and return
/// the process exit status: 0 ok, 1 a test failed or the file does not check, 2 unreadable, 3 nothing selected.
pub fn run(init: std.process.Init, requested: Options) Error!u8 {
    if (directory_runner.selected(init.io, requested.path)) return directory_runner.run(init, requested);
    var options = requested;
    const allocator = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, options.path, allocator, .limited(64 << 20)) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "error: cannot read {s}: {s}\n", .{ options.path, @errorName(err) });
        try writeAll(init, std.Io.File.stderr(), message);
        return 2;
    };
    const located = project_entry.resolve(allocator, init.io, options.path, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return 1;
    };
    const configured_cases = try configuredCases(init, &options, located) orelse return 1;
    options.controls.cases = configured_cases.path;
    if (try cachedReplay(init, options, located, configured_cases.bytes)) |cached| {
        try writeAll(init, std.Io.File.stdout(), cached);
        return 0;
    }
    const guest = try guestTool(init, options) orelse return 1;
    // Spawn the exact executable whose content and library tree were captured.
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = allocator, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = configured_cases.bytes, .tool = guest };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    const base = try receipt.settings(context, &native_inputs);
    if (try receipt.replay(context, base)) |cached| {
        try writeAll(init, std.Io.File.stdout(), cached);
        return 0;
    }
    var session = frontend.Session.init(init.gpa, init.io, located.root);
    defer session.deinit();
    located.configure(&session);
    try session.enableCache(init.gpa, options.build.cache);
    if (!definesMain(bytes)) session.entry_suffix = check_stub;
    const checked = session.checkFile(allocator, options.path, &problems) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try writeAll(init, std.Io.File.stderr(), problems.items);
            return 1;
        },
    };
    var before: std.ArrayList(receipt.Dependency) = .empty;
    try before.appendSlice(allocator, try receipt.captured(context, &session, &.{}));
    try before.appendSlice(allocator, native_inputs.items);
    located.validate(allocator, &session, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), problems.items);
        return 1;
    };
    const entry_module = moduleName(checked.program, located.name);
    const modules = try moduleSources(allocator, &session, entry_module);
    const all_cases = try discover.discover(allocator, checked.program, entry_module, modules);
    case_settings.validate(configured_cases, all_cases) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(allocator, "error: test cases: {s}\n", .{@errorName(err)}));
        return 1;
    };
    var selected_cases: std.ArrayList(discover.Case) = .empty;
    for (all_cases) |case| if (discover.matches(options.filter, case.name)) {
        try selected_cases.append(allocator, case);
    };
    const groups = case_settings.groups(allocator, configured_cases, selected_cases.items) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try writeAll(init, std.Io.File.stderr(), try std.fmt.allocPrint(allocator, "error: test providers: {s}\n", .{@errorName(err)}));
        return 1;
    };
    var chosen: std.ArrayList(Selected) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;
    try addSources(allocator, &sources, context, &session);
    for (groups) |group| {
        var provider_session = frontend.Session.init(init.gpa, init.io, located.root);
        defer provider_session.deinit();
        var selected_program = checked;
        var grouped_cases = group.cases;
        if (group.providers.len != 0) {
            case_settings.available(group.providers, &session, located.name) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try writeAll(init, std.Io.File.stderr(), "error: invalid test provider dependencies\n");
                return 1;
            };
            located.configure(&provider_session);
            try provider_session.enableCache(init.gpa, options.build.cache);
            provider_session.setProviders(group.providers);
            if (!definesMain(bytes)) provider_session.entry_suffix = check_stub;
            selected_program = provider_session.checkFile(allocator, located.path, &problems) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try writeAll(init, std.Io.File.stderr(), problems.items);
                return 1;
            };
            try before.appendSlice(allocator, try receipt.captured(context, &provider_session, group.providers));
            located.validate(allocator, &provider_session, &problems) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try writeAll(init, std.Io.File.stderr(), problems.items);
                return 1;
            };
            const provider_modules = try moduleSources(allocator, &provider_session, entry_module);
            const discovered = try discover.discover(allocator, selected_program.program, entry_module, provider_modules);
            case_settings.compatible(allocator, &session, &provider_session, checked, selected_program) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try writeAll(init, std.Io.File.stderr(), "error: ProviderSignatureChanged: test providers changed the exported type graph\n");
                return 1;
            };
            grouped_cases = try remap(allocator, checked.program, selected_program.program, group.cases, discovered);
            try addSources(allocator, &sources, context, &provider_session);
        }
        const items = try select(init, options, selected_program, grouped_cases, configured_cases, .{ .receipt = context, .base = base });
        try execute(init, options, selected_program, items);
        try chosen.appendSlice(allocator, items);
    }
    const unchanged = try receipt.unchanged(context, before.items) and try receipt.toolUnchanged(context);
    if (!unchanged) {
        try writeAll(init, std.Io.File.stderr(), "error: SourceChanged: a test input changed during checking or execution\n");
        return 1;
    }
    const verdicts = try allocator.alloc(report.Verdict, chosen.items.len);
    var successful = chosen.items.len != 0;
    for (chosen.items, verdicts) |item, *verdict| {
        verdict.* = item.verdict;
        successful = successful and item.identity != null and (item.verdict.status == .passed or item.verdict.status == .cached);
        if (unchanged and item.verdict.status == .passed) if (item.identity) |identity| try receipt.save(context, identity);
    }
    const json = try report.jsonSources(allocator, verdicts, sources.items);
    if (successful and unchanged) try receipt.remember(context, base, before.items, json);
    const out = if (options.json) json else try report.text(allocator, verdicts);
    try writeAll(init, std.Io.File.stdout(), out);
    return report.exitStatus(verdicts);
}

fn cachedReplay(init: std.process.Init, options: Options, located: project_entry.Entry, case_bytes: []const u8) Error!?[]const u8 {
    const borrowed = try borrowedReplay(init, options, located, case_bytes);
    // The private transport never reaches native guests or a persistent key.
    _ = init.environ_map.swapRemove(tool_ticket.hint);
    return borrowed orelse try localReplay(init, options, located, case_bytes);
}

fn borrowedReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8) Error!?[]const u8 {
    const a = init.arena.allocator();
    const resources: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = requested.build.zig, .cache = requested.build.cache };
    const guest = try tool_ticket.borrow(.{ .tool = resources, .compiler_identity = frontend.compiler_identity }) orelse return null;
    var options = requested;
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = a, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = case_bytes, .tool = guest };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    return receipt.replayProvisional(context, try receipt.settings(context, &native_inputs));
}

fn localReplay(init: std.process.Init, requested: Options, located: project_entry.Entry, case_bytes: []const u8) Error!?[]const u8 {
    const a = init.arena.allocator();
    const resources: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = requested.build.zig, .cache = requested.build.cache };
    const guest = tool_identity.lookupReplayCandidate(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    } orelse return null;
    var options = requested;
    options.build.zig = guest.path;
    const context: receipt.Context = .{ .arena = a, .io = init.io, .environment = init.environ_map, .options = options, .entry = located, .case_bytes = case_bytes, .tool = guest };
    var native_inputs: std.ArrayList(receipt.Dependency) = .empty;
    const base = try receipt.settings(context, &native_inputs);
    // Buffer the candidate without publishing anything under its unverified key.
    _ = try receipt.replayProvisional(context, base) orelse return null;
    if (!try receipt.toolUnchanged(context)) return null;
    // Source/dependency bytes must still agree after the full tool validation.
    return receipt.replayProvisional(context, base);
}

fn configuredCases(init: std.process.Init, options: *Options, located: project_entry.Entry) Error!?case_settings.File {
    if (!try applyLimits(init, options, located)) return null;
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

fn applyLimits(init: std.process.Init, options: *Options, located: project_entry.Entry) Error!bool {
    if (located.configuration) |configured| {
        const limits = configured.document.limits.tests;
        if (!options.controls.explicit_steps) if (limits.max_steps) |steps| {
            options.controls.max_steps = steps;
        };
        if (limits.max_frames != null or limits.max_memory != null) {
            try writeAll(init, std.Io.File.stderr(), "error[E_CORE_UNSUPPORTED]: configured test frame and memory limits are not implemented in the new core\n");
            return false;
        }
    }
    return true;
}

fn programIdentity(resources: IdentityResources, options: Options, checked: frontend.Checked, case: discover.Case, base: [32]u8) Error!?[32]u8 {
    // The shared checker propagates effects through calls. Host calls have
    // mutable external inputs and cannot publish persistent result receipts.
    const function = checked.program.functions[@backingInt(case.function)];
    const effects = @import("mylang").effect_set;
    if (function.policy.host != null or function.policy.effects & effects.bit(.host) != 0) return null;
    var scratch = std.heap.ArenaAllocator.init(resources.backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    var why: build.Refusal = .{};
    var module = programFor(a, options, checked, &.{case}, &why) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    var log: std.ArrayList(u8) = .empty;
    const llvm = pipeline.emitted(a, &module, .{ .src = checked.src, .source_path = std.Io.Dir.cwd().realPathFileAlloc(resources.io, options.path, a) catch options.path, .main = .{} }, options.build, &log) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return receipt.key(base, case.name, llvm);
}

fn select(init: std.process.Init, options: Options, checked: frontend.Checked, cases: []const discover.Case, settings: case_settings.File, selection: SelectionContext) Error![]Selected {
    const a = init.arena.allocator();
    const chosen = try a.alloc(Selected, cases.len);
    const context = selection.receipt;
    for (cases, chosen) |case, *item| {
        const configured = v.get(settings.document, case.name);
        const skip = v.get(configured, "skip");
        const refused = if (skip == .string and skip.string.len != 0) report.Verdict{ .name = case.name, .status = .skipped, .reason = skip.string } else try classify(init.gpa, a, checked, case, configured);
        item.* = .{ .case = case, .verdict = refused orelse .{ .name = case.name, .status = .failed, .reason = "not run" }, .ready = refused == null, .settings = configured };
        if (!item.ready) continue;
        if (try programIdentity(.{ .backing = init.gpa, .io = init.io }, options, checked, case, selection.base)) |identity| {
            item.identity = receipt.key(identity, "case-settings", try std.json.Stringify.valueAlloc(a, configured, .{}));
            if (try receipt.hit(context, item.identity.?)) {
                item.verdict = .{ .name = case.name, .status = .cached };
                item.ready = false;
            }
        }
    }
    return chosen;
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

/// The `unsupported` verdict of a test the builder cannot build, or null when it can be built and run.
fn classify(gpa: std.mem.Allocator, keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case, settings: std.json.Value) Error!?report.Verdict {
    const arguments = v.get(settings, "arguments");
    const fixed = arguments == .object and arguments.object.count() != 0;
    const expected = settings == .object and settings.object.contains(case_expectation);
    if (case.other_parameters != 0 and !fixed) {
        if (expected) return .{ .name = case.name, .status = .failed, .reason = "a property test's verdict is its bool result; remove `expected` or supply `arguments`" };
        const function = checked.program.functions[@backingInt(case.function)];
        const definitions = try property_schema.definitions(keep, checked.program);
        const schema = try property_types.Schema.init(keep, definitions);
        for (function.scope.locals[0..function.signature.parameter_count], case.parameters) |parameter, family| {
            if (family != 255 and family <= 5) continue;
            const name = typed.typeName(parameter.ty, checked.program.records);
            if (try property_types.refused(schema, name)) |found| {
                const reason = try std.fmt.allocPrint(keep, "property test parameter `{s}: {s}` cannot be generated: {s}", .{ parameter.name, name, found.reason });
                return .{ .name = case.name, .status = .failed, .reason = reason };
            }
        }
    }
    if (case.shape == .other and !expected) return refusal(case, "test result type is not bool", "");
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var why: build.Refusal = .{};
    const selected_roots = try rootsFor(scratch.allocator(), checked.program, &.{case});
    const module = build.buildRootsSource(scratch.allocator(), checked.program, selected_roots, checked.src, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => {
            const at = frontend.position(checked.src, .{ .start = why.span, .end = why.span });
            return refusal(case, try keep.dupe(u8, why.reason), try std.fmt.allocPrint(keep, "{d}:{d}", .{ at.line, at.column }));
        },
    };
    if (!expected and !entry.readable(&module, module.functions.items[0].signature.ret)) return refusal(case, "the runner's entry cannot read this test's result type yet (Result[bool, E])", "");
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
fn moduleSources(a: std.mem.Allocator, session: *const frontend.Session, entry_module: []const u8) Error![]const discover.Module {
    if (session.single) |unit| return a.dupe(discover.Module, &.{.{ .name = entry_module, .text = unit.src.bytes }});
    const modules = try a.alloc(discover.Module, session.project.modules.items.len);
    for (session.project.modules.items, modules) |source, *module| module.* = .{ .name = source.name, .text = source.src.bytes };
    return modules;
}

fn addSources(a: std.mem.Allocator, paths: *std.ArrayList([]const u8), context: receipt.Context, session: *const frontend.Session) Error!void {
    if (session.single != null) {
        try paths.append(a, context.entry.path);
        return;
    }
    for (session.project.modules.items) |module| {
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
        if (std.mem.startsWith(u8, line, "def main(") or std.mem.startsWith(u8, line, "public def main(")) return true;
    }
    return false;
}

/// Build the pending tests together (isolating any the backend rejects) and run each.
fn execute(init: std.process.Init, requested: Options, checked: frontend.Checked, chosen: []Selected) Error!void {
    const allocator = init.arena.allocator();
    var live: std.ArrayList(usize) = .empty;
    for (chosen, 0..) |item, position| if (item.ready) try live.append(allocator, position);
    if (live.items.len == 0) return;
    var options = requested;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    options.build.output = try std.fmt.allocPrint(allocator, "{s}/tests/program-{s}", .{ requested.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, options.build.output) catch return error.WriteFailed;
    defer removePrivate(init.io, options.build.output);
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
        .built => |executable| try executeWorkers(init, options, checked.program, executable, chosen, live.items),
    }
}

const Work = struct {
    resources: ExecutionResources,
    options: Options,
    program: typed.Program,
    executable: []const u8,
    table_index: usize,
    selected: *Selected,
    failure: ?Error = null,

    fn run(self: *Work) void {
        self.selected.verdict = runSelected(self.resources, self.options, self.program, self.executable, self.table_index, self.selected.*) catch |err| {
            self.failure = err;
            return;
        };
    }
};

fn executeWorkers(init: std.process.Init, options: Options, program: typed.Program, executable: []const u8, chosen: []Selected, positions: []const usize) Error!void {
    const a = init.arena.allocator();
    const width = @import("test_runner_options.zig").width(options.controls, init.environ_map, positions.len);
    // The pinned Zig arena is thread-safe with Init's thread-safe backing.
    const resources: ExecutionResources = .{ .arena = a, .backing = init.gpa, .io = init.io };
    const work = try a.alloc(Work, positions.len);
    for (positions, work, 0..) |position, *item, table_index| item.* = .{ .resources = resources, .options = options, .program = program, .executable = executable, .table_index = table_index, .selected = &chosen[position] };
    if (width == 1) {
        for (work) |*item| {
            item.run();
            if (item.failure) |err| return err;
        }
        return;
    }
    const threads = try a.alloc(std.Thread, width);
    var begin: usize = 0;
    while (begin < work.len) : (begin += width) {
        var started: usize = 0;
        for (work[begin..@min(work.len, begin + width)]) |*item| {
            threads[started] = std.Thread.spawn(.{}, Work.run, .{item}) catch {
                item.run();
                continue;
            };
            started += 1;
        }
        for (threads[0..started]) |thread| thread.join();
        for (work[begin..@min(work.len, begin + width)]) |item| if (item.failure) |err| return err;
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
    const flavor = if (options.build.release) "release" else "debug";
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
    var module = try build.buildRootsSource(allocator, checked.program, roots, checked.src, why);
    const targets = try allocator.alloc(entry.Target, cases.len);
    for (targets, cases, 0..) |*target, case, table_index| {
        const function = checked.program.functions[@backingInt(case.function)];
        const result = typed.resultShape(function.signature.return_type, checked.program.records);
        const parameters = try allocator.alloc([]const u8, function.signature.parameter_count);
        for (parameters, function.scope.locals[0..function.signature.parameter_count]) |*name_slot, parameter| name_slot.* = typed.typeName(parameter.ty, checked.program.records);
        target.* = .{
            .function = @intCast(table_index),
            .streams = case.streams,
            .parameters = case.parameters,
            .seed = entropySeed(options.seed, case.name),
            .data = .{ .parameters = parameters, .result = typed.typeName(function.signature.return_type, checked.program.records) },
            .result = if (result) |shape| .{ .ok_tag = @intCast(shape.ok_tag), .error_tag = @intCast(shape.error_tag) } else null,
        };
    }
    const schema = try property_types.Schema.init(allocator, try property_schema.definitions(allocator, checked.program));
    const originals = module.functions.items.len;
    try batch_entry.add(allocator, &module, targets, schema);
    try @import("test_runner_budget.zig").instrument(allocator, &module, originals, options.controls);
    return module;
}

fn firstLine(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return allocator.dupe(u8, std.mem.sliceTo(std.mem.trim(u8, text, "\n"), '\n'));
}

/// Stable stand-in/property seed, identical to native_test_wire.entropySeed.
fn entropySeed(explicit: ?u64, name: []const u8) u64 {
    if (explicit) |seed| return seed;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .little);
}

fn rootsFor(a: std.mem.Allocator, program: typed.Program, cases: []const discover.Case) Error![]const typed.FunctionId {
    var roots: std.ArrayList(typed.FunctionId) = .empty;
    for (cases) |case| try roots.append(a, case.function);
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

fn functionValue(a: std.mem.Allocator, program: typed.Program, case: discover.Case) Error!std.json.Value {
    const f = program.functions[@backingInt(case.function)];
    var out: std.json.ObjectMap = .empty;
    try out.put(a, "name", .{ .string = case.name });
    try out.put(a, "result", .{ .string = typed.typeName(f.signature.return_type, program.records) });
    var parameters: std.json.Array = .init(a);
    for (f.scope.locals[0..f.signature.parameter_count]) |parameter| {
        var item: std.json.ObjectMap = .empty;
        try item.put(a, "name", .{ .string = parameter.name });
        try item.put(a, "type", .{ .string = typed.typeName(parameter.ty, program.records) });
        try item.put(a, "mode", .{ .string = "value" });
        try parameters.append(.{ .object = item });
    }
    try out.put(a, "parameters", .{ .array = parameters });
    return .{ .object = out };
}

fn runSelected(resources: ExecutionResources, options: Options, program: typed.Program, executable: []const u8, table_index: usize, selected: Selected) Error!report.Verdict {
    const case = selected.case;
    const a = resources.arena;
    const function = try functionValue(a, program, case);
    var nonce: [16]u8 = undefined;
    std.Io.random(resources.io, &nonce);
    const directory = try std.fmt.allocPrint(a, "{s}/tests/private-{s}", .{ options.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(resources.io, directory) catch return error.WriteFailed;
    defer removePrivate(resources.io, directory);
    const context: property_execute.Context = .{ .arena = a, .backing = resources.backing, .io = resources.io };
    const source_path = std.Io.Dir.cwd().realPathFileAlloc(resources.io, options.path, a) catch options.path;
    const executor: property_execute.Executor = .{ .context = context, .types = try property_schema.definitions(a, program), .executable = executable, .table_index = table_index, .directory = directory, .source_path = source_path };
    const arguments = v.get(selected.settings, "arguments");
    const fixed = arguments == .object and arguments.object.count() != 0;
    if (case.other_parameters != 0 and !fixed) {
        const setup = try property.Property.bind(context, &executor, function, .{ .timeout_ms = options.controls.timeout_ms }, .{ .seed = entropySeed(options.seed, case.name), .runs = options.property_runs, .entry = options.path });
        var bound = switch (setup) {
            .invalid => |reason| return .{ .name = case.name, .status = .failed, .reason = reason },
            .ready => |ready| ready,
        };
        var search: property.Search = .{};
        const first = try bound.first(&search);
        const answers = try property_execute.executeBatches(context, &.{first}, .{ .timeout_ms = options.controls.timeout_ms }, 1);
        const verdict = try bound.finish(&search, answers[0]);
        return .{ .name = case.name, .status = if (verdict.passed) .passed else .failed, .reason = verdict.reason, .property = verdict.evidence };
    }
    const words = if (fixed) executor.encode(function, arguments) catch return .{ .name = case.name, .status = .failed, .reason = "invalid cases-file arguments" } else &.{};
    const answered = try property_execute.executeBatches(context, &.{.{ .executor = &executor, .function = function, .inputs = &.{words} }}, .{ .timeout_ms = options.controls.timeout_ms }, 1);
    if (answered[0].outcomes.len != 1) return .{ .name = case.name, .status = .failed, .reason = if (answered[0].timed_out) try std.fmt.allocPrint(a, "timed out after {d} ms", .{options.controls.timeout_ms}) else answered[0].ending };
    const outcome = answered[0].outcomes[0];
    const explicit = selected.settings == .object and selected.settings.object.contains(case_expectation);
    const returned = std.mem.eql(u8, outcome.status, "value");
    const matches = if (!returned) false else if (explicit) try expectedResult(a, program, case, v.get(selected.settings, case_expectation), outcome.actual) else truth(outcome.actual);
    const passed = returned and matches;
    if (explicit and !passed and std.mem.eql(u8, outcome.status, "value")) {
        const expected_text = try std.json.Stringify.valueAlloc(a, v.get(selected.settings, case_expectation), .{});
        const actual_text = try std.json.Stringify.valueAlloc(a, outcome.actual, .{});
        return .{ .name = case.name, .status = .failed, .reason = try std.fmt.allocPrint(a, "expected {s}, got {s}", .{ expected_text, actual_text }) };
    }
    return .{ .name = case.name, .status = if (passed) .passed else .failed, .reason = if (passed) "" else try ordinaryReason(a, outcome) };
}

fn expectedResult(a: std.mem.Allocator, program: typed.Program, case: discover.Case, expected: std.json.Value, actual: std.json.Value) Error!bool {
    const schema = try property_types.Schema.init(a, try property_schema.definitions(a, program));
    const function = program.functions[@backingInt(case.function)];
    const name = typed.typeName(function.signature.return_type, program.records);
    var wanted: @import("property_codec.zig").Codec = .{ .allocator = a, .schema = schema };
    wanted.encode(name, expected) catch return false;
    var observed: @import("property_codec.zig").Codec = .{ .allocator = a, .schema = schema };
    observed.encode(name, actual) catch return false;
    return std.mem.eql(u64, wanted.words.items, observed.words.items);
}
fn truth(value: std.json.Value) bool {
    if (value == .bool) return value.bool;
    return std.mem.eql(u8, v.text(v.get(value, "case")), "ok") and v.get(value, "value") == .bool and v.get(value, "value").bool;
}

/// Best-effort retirement only touches the selected test's owned directory.
fn removePrivate(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch return;
}

// spec-case: NEW-CORE-S3-RUNNER-1
test "removePrivate retires trial files and accepts an already absent directory" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const a = std.testing.allocator;
    const root = try temp.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    const directory = try std.fs.path.join(a, &.{ root, "private" });
    defer a.free(directory);
    const file = try std.fs.path.join(a, &.{ directory, "trial.input" });
    defer a.free(file);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(std.testing.io, directory);
    try cwd.writeFile(std.testing.io, .{ .sub_path = file, .data = "owned trial" });
    removePrivate(std.testing.io, directory);
    try std.testing.expectError(error.FileNotFound, cwd.openDir(std.testing.io, directory, .{}));
    removePrivate(std.testing.io, directory);
}
fn ordinaryReason(a: std.mem.Allocator, outcome: property_execute.Outcome) Error![]const u8 {
    var reason = outcome.diagnostics;
    if (std.mem.eql(u8, outcome.status, "value")) {
        const actual = outcome.actual;
        const text = if (actual == .bool) (if (actual.bool) "true" else "false") else try std.json.Stringify.valueAlloc(a, actual, .{});
        const expected = if (actual == .bool) "true" else "{\"case\":\"ok\",\"value\":true}";
        reason = try std.fmt.allocPrint(a, "expected {s}, got {s}", .{ expected, text });
        if (outcome.trace.len != 0) reason = try std.fmt.allocPrint(a, "{s}\n{s}", .{ reason, std.mem.trimEnd(u8, outcome.trace, "\n") });
    }
    if (outcome.output.len != 0) reason = try std.fmt.allocPrint(a, "{s}\n{s}", .{ reason, outcome.output });
    return reason;
}

// spec-case: NEW-CORE-S4-TEST-3
test "programIdentity propagates allocation failure instead of inventing a reusable success" {
    const resources: IdentityResources = .{ .backing = std.testing.failing_allocator, .io = std.testing.io };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = "module app\n\npublic def test_value() -> bool:\n    return True\n\ndef main() -> int:\n    return 0\n";
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
