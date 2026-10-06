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
const v = @import("property_value.zig");

/// The old runner's stub, appended to a file that defines no `main` of its own.
pub const check_stub = "\n\ndef main() -> int:\n    return 0\n";

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = property.Error;

/// What the command line asked for.
pub const Options = struct {
    path: []const u8,
    /// `--filter`: a substring of the qualified name, or a glob.
    filter: []const u8 = "",
    json: bool = false,
    /// The build flags of the test executable (release, facts mode, `zig`, cache directory).
    build: pipeline.Options,
    /// Explicit entropy/property seed; null derives it from the qualified name.
    seed: ?u64 = null,
    /// Generated inputs every property must pass.
    property_runs: u32 = property.default_runs,
};

/// One selected test and its place in the report. `ready` tests have no verdict yet:
/// their `verdict` is filled in by building and running them.
const Selected = struct { case: discover.Case, verdict: report.Verdict, ready: bool };

/// Check, discover, build and run the tests of `options.path`, print the report, and return
/// the process exit status: 0 ok, 1 a test failed or the file does not check, 2 unreadable, 3 nothing selected.
pub fn run(init: std.process.Init, options: Options) Error!u8 {
    const allocator = init.arena.allocator();
    const located = frontend.entryOf(options.path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, options.path, allocator, .limited(64 << 20)) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "error: cannot read {s}: {s}\n", .{ options.path, @errorName(err) });
        try writeAll(init, std.Io.File.stderr(), message);
        return 2;
    };
    var session = frontend.Session.init(init.gpa, init.io, located.root);
    defer session.deinit();
    if (!definesMain(bytes)) session.entry_suffix = check_stub;
    var problems: std.ArrayList(u8) = .empty;
    const checked = session.checkFile(allocator, options.path, &problems) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try writeAll(init, std.Io.File.stderr(), problems.items);
            return 1;
        },
    };
    var chosen: std.ArrayList(Selected) = .empty;
    const entry_module = moduleName(checked.program, located.module);
    const modules = try moduleSources(init, allocator, checked.program, located.root, .{ .name = entry_module, .text = bytes });
    for (try discover.discover(allocator, checked.program, entry_module, modules)) |case| {
        if (!discover.matches(options.filter, case.name)) continue;
        const refused = try classify(init.gpa, allocator, checked, case);
        try chosen.append(allocator, .{ .case = case, .verdict = refused orelse .{ .name = case.name, .status = .failed, .reason = "not run" }, .ready = refused == null });
    }
    try execute(init, options, checked, chosen.items);
    const verdicts = try allocator.alloc(report.Verdict, chosen.items.len);
    for (chosen.items, verdicts) |item, *verdict| verdict.* = item.verdict;
    const out = if (options.json) try report.json(allocator, verdicts) else try report.text(allocator, verdicts);
    try writeAll(init, std.Io.File.stdout(), out);
    return report.exitStatus(verdicts);
}

fn writeAll(init: std.process.Init, file: std.Io.File, text: []const u8) Error!void {
    file.writeStreamingAll(init.io, text) catch return error.WriteFailed;
}

/// The `unsupported` verdict of a test the builder cannot build, or null when it can be built and run.
fn classify(gpa: std.mem.Allocator, keep: std.mem.Allocator, checked: frontend.Checked, case: discover.Case) Error!?report.Verdict {
    if (case.other_parameters != 0) {
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
    if (case.shape == .other) return refusal(case, "test result type is not bool", "");
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
    if (!entry.readable(&module, module.functions.items[0].signature.ret)) return refusal(case, "the runner's entry cannot read this test's result type yet (Result[bool, E])", "");
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

/// The entry module's text and the source of every other module a function belongs to,
/// read from `root` (a module `a.b` is `root/a/b.my`); a module without a file is left out.
fn moduleSources(init: std.process.Init, allocator: std.mem.Allocator, program: typed.Program, root: []const u8, entry_module: discover.Module) std.mem.Allocator.Error![]const discover.Module {
    var modules: std.ArrayList(discover.Module) = .empty;
    try modules.append(allocator, entry_module);
    for (program.functions) |function| {
        const split = std.mem.lastIndexOf(u8, function.name, "::") orelse continue;
        const name = function.name[0..split];
        var known = false;
        for (modules.items) |module| known = known or std.mem.eql(u8, module.name, name);
        if (known) continue;
        const relative = try std.fmt.allocPrint(allocator, "{s}.my", .{name});
        std.mem.replaceScalar(u8, relative[0..name.len], '.', '/');
        const path = try std.fs.path.join(allocator, &.{ root, relative });
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(64 << 20)) catch "";
        try modules.append(allocator, .{ .name = name, .text = text });
    }
    return modules.toOwnedSlice(allocator);
}

fn definesMain(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "def main(") or std.mem.startsWith(u8, line, "public def main(")) return true;
    }
    return false;
}

/// Build the pending tests together (isolating any the backend rejects) and run each.
fn execute(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []Selected) Error!void {
    const allocator = init.arena.allocator();
    var live: std.ArrayList(usize) = .empty;
    for (chosen, 0..) |item, position| if (item.ready) try live.append(allocator, position);
    if (live.items.len == 0) return;
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
        .built => |executable| for (live.items, 0..) |position, table_index| {
            chosen[position].verdict = try runSelected(init, options, checked.program, executable, table_index, chosen[position].case);
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
    const roots = try rootsFor(allocator, checked.program, cases);
    var why: build.Refusal = .{};
    var module = build.buildRootsSource(allocator, checked.program, roots, checked.src, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = why.reason } },
    };
    const targets = try allocator.alloc(entry.Target, positions.len);
    for (targets, positions, 0..) |*target, position, table_index| {
        const case = chosen[position].case;
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
    batch_entry.add(allocator, &module, targets, schema) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = "property copied-value adapter type" } },
    };
    const flavor = if (options.build.release) "release" else "debug";
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, allocator) catch options.path;
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash(absolute, &digest, .{});
    const directory = try std.fs.path.join(allocator, &.{ options.build.cache, "tests" });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return error.WriteFailed;
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

fn runSelected(init: std.process.Init, options: Options, program: typed.Program, executable: []const u8, table_index: usize, case: discover.Case) Error!report.Verdict {
    const a = init.arena.allocator();
    const function = try functionValue(a, program, case);
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    const directory = try std.fmt.allocPrint(a, "{s}/tests/private-{s}", .{ options.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return error.WriteFailed;
    defer removePrivate(init.io, directory);
    const context: property_execute.Context = .{ .arena = a, .backing = init.gpa, .io = init.io };
    const source_path = std.Io.Dir.cwd().realPathFileAlloc(init.io, options.path, a) catch options.path;
    const executor: property_execute.Executor = .{ .context = context, .types = try property_schema.definitions(a, program), .executable = executable, .table_index = table_index, .directory = directory, .source_path = source_path };
    if (case.other_parameters != 0) {
        const setup = try property.Property.bind(context, &executor, function, .{}, .{ .seed = entropySeed(options.seed, case.name), .runs = options.property_runs, .entry = options.path });
        var bound = switch (setup) {
            .invalid => |reason| return .{ .name = case.name, .status = .failed, .reason = reason },
            .ready => |ready| ready,
        };
        var search: property.Search = .{};
        const first = try bound.first(&search);
        const answers = try property_execute.executeBatches(context, &.{first}, .{}, 1);
        const verdict = try bound.finish(&search, answers[0]);
        return .{ .name = case.name, .status = if (verdict.passed) .passed else .failed, .reason = verdict.reason, .property = verdict.evidence };
    }
    const answered = try property_execute.executeBatches(context, &.{.{ .executor = &executor, .function = function, .inputs = &.{&.{}} }}, .{}, 1);
    if (answered[0].outcomes.len != 1) return .{ .name = case.name, .status = .failed, .reason = if (answered[0].timed_out) "timed out after 60 s" else answered[0].ending };
    const outcome = answered[0].outcomes[0];
    const passed = outcome.status.len != 0 and std.mem.eql(u8, outcome.status, "value") and truth(outcome.actual);
    return .{ .name = case.name, .status = if (passed) .passed else .failed, .reason = if (passed) "" else try ordinaryReason(a, outcome) };
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
