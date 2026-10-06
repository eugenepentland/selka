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

/// The old runner's stub, appended to a file that defines no `main` of its own.
pub const check_stub = "\n\ndef main() -> int:\n    return 0\n";

/// Seconds a single test may run before it is reported failed.
const test_timeout_seconds = 30;

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = error{ OutOfMemory, WriteFailed };

/// What the command line asked for.
pub const Options = struct {
    path: []const u8,
    /// `--filter`: a substring of the qualified name, or a glob.
    filter: []const u8 = "",
    json: bool = false,
    /// The build flags of the test executable (release, facts mode, `zig`, cache directory).
    build: pipeline.Options,
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
    if (case.other_parameters != 0) return refusal(case, "test parameters other than Stream (property test or capability stand-in; out of S1 scope)", "");
    if (case.shape == .other) return refusal(case, "test result type is not bool", "");
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var why: build.Refusal = .{};
    const module = build.buildRoots(scratch.allocator(), checked.program, &.{case.function}, &why) catch |err| switch (err) {
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
            chosen[position].verdict = try runTest(init, executable, table_index, chosen[position].case.name);
        },
    }
}

const Built = union(enum) { built: []const u8, failed: report.Verdict };

/// Build the executable for `chosen[positions]`; its dispatch table lists them in order.
fn buildExecutable(init: std.process.Init, options: Options, checked: frontend.Checked, chosen: []const Selected, positions: []const usize, tag: []const u8) Error!Built {
    const allocator = init.arena.allocator();
    const name = chosen[positions[0]].case.name;
    const roots = try allocator.alloc(typed.FunctionId, positions.len);
    for (positions, roots) |position, *root| root.* = chosen[position].case.function;
    var why: build.Refusal = .{};
    var module = build.buildRoots(allocator, checked.program, roots, &why) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return .{ .failed = .{ .name = name, .status = .unsupported, .reason = why.reason } },
    };
    const targets = try allocator.alloc(entry.Target, positions.len);
    for (targets, positions, 0..) |*target, position, table_index| {
        const case = chosen[position].case;
        const function = checked.program.functions[@backingInt(case.function)];
        const result = typed.resultShape(function.signature.return_type, checked.program.records);
        var seed: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(case.name, &seed, .{});
        target.* = .{
            .function = @intCast(table_index),
            .streams = case.streams,
            .parameters = case.parameters,
            .seed = std.mem.readInt(u64, seed[0..8], .little),
            .result = if (result) |shape| .{ .ok_tag = @intCast(shape.ok_tag), .error_tag = @intCast(shape.error_tag) } else null,
        };
    }
    try entry.addEntry(allocator, &module, targets);
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

/// Run test number `table_index` of `executable` as its own process and read the verdict
/// from its exit status and stderr.
fn runTest(init: std.process.Init, executable: []const u8, table_index: usize, name: []const u8) std.mem.Allocator.Error!report.Verdict {
    const allocator = init.arena.allocator();
    const argument = try std.fmt.allocPrint(allocator, "{d}", .{table_index});
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(test_timeout_seconds), .clock = .awake } };
    const result = std.process.run(init.gpa, init.io, .{ .argv = &.{ executable, argument }, .timeout = timeout }) catch |err| {
        const reason = if (err == error.Timeout) try std.fmt.allocPrint(allocator, "timed out after {d} s", .{test_timeout_seconds}) else try std.fmt.allocPrint(allocator, "cannot run the test: {s}", .{@errorName(err)});
        return .{ .name = name, .status = .failed, .reason = reason };
    };
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);
    // Under MYL_CORE_LEAKCHECK=1 a test that ends with blocks live says so: it fails.
    if (std.mem.indexOf(u8, result.stderr, leak_marker)) |at| {
        const line = std.mem.sliceTo(result.stderr[at..], '\n');
        return .{ .name = name, .status = .failed, .reason = try std.fmt.allocPrint(allocator, "leak: {s}", .{line[leak_marker.len..]}) };
    }
    return .{ .name = name, .status = if (result.term == .exited and result.term.exited == entry.status_pass) .passed else .failed, .reason = try failureReason(allocator, result.term, result.stderr) };
}

/// The start of the runtime's leak report (`runtime/core_rt.c`, `leak_report`).
const leak_marker = "myl-core leakcheck: ";

/// Why a run did not pass, in the old runner's words: `expected true, got false`, or a
/// trap's `R_CODE (detail)` followed by its `  in …` frames. Empty for a pass.
fn failureReason(allocator: std.mem.Allocator, term: std.process.Child.Term, stderr: []const u8) std.mem.Allocator.Error![]const u8 {
    switch (term) {
        .exited => |code| {
            if (code == entry.status_pass) return "";
            if (code == entry.status_false) return "expected true, got false";
            if (code == 1) if (try trapReason(allocator, stderr)) |reason| return reason;
            return std.fmt.allocPrint(allocator, "exited with status {d}", .{code});
        },
        .signal => |signal| return std.fmt.allocPrint(allocator, "terminated by signal {d}", .{@backingInt(signal)}),
        else => return "abnormal termination",
    }
}

/// `R_CODE (detail)` and the `  in …` frame lines of a trap report on stderr.
fn trapReason(allocator: std.mem.Allocator, stderr: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const marker = "error[";
    const start = std.mem.indexOf(u8, stderr, marker) orelse return null;
    const close = std.mem.indexOfScalarPos(u8, stderr, start, ']') orelse return null;
    const code = stderr[start + marker.len .. close];
    const head_end = std.mem.indexOfScalarPos(u8, stderr, close, '\n') orelse stderr.len;
    const failed = "native execution failed";
    const detail = if (std.mem.indexOf(u8, stderr[close..head_end], failed)) |at| std.mem.trim(u8, stderr[close + at + failed.len .. head_end], " ") else "";
    var out: std.ArrayList(u8) = .empty;
    try out.print(allocator, "{s}{s}{s}", .{ code, if (detail.len != 0) " " else "", detail });
    var lines = std.mem.splitScalar(u8, stderr[head_end..], '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "  in ")) try out.print(allocator, "\n{s}", .{line});
    const reason = try out.toOwnedSlice(allocator);
    return reason;
}
