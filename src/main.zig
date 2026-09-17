//! Host I/O and process policy stay outside the compiler and VM.
const lowering_phase = "bytecode_lowering";
const inputs_prefix = "--inputs=";
const policy_prefix = "--policy=";
const cache_directory_prefix = "--cache-dir=";
const select_file_prefix = "--select-file=";
/// Wall-clock ceiling forwarded to the guest runtime, which parses the same flag.
const timeout_prefix = "--timeout=";
/// Shared internal session failure name for an over-long request line.
const request_too_long = "RequestTooLong";
/// Phase label and default cache-directory leaf, shared so the literal is not
/// repeated across the timer and the persistent-cache path join.
const frontend_label = "frontend";
const std = @import("std");
const language = @import("mylang");
const invalidation = @import("invalidation.zig");
const diagnostic_output = language.diagnostic_output;
const Reporting = struct {
    print_result: bool = false,
    timings: bool = false,
    timings_json: bool = false,
    /// `--report` asks one-shot commands for an actual-work/reuse receipt.
    report: bool = false,
    /// `--explain-invalidation` asks for a stage-by-stage baseline comparison.
    explain_invalidation: bool = false,
    diagnostics: ?diagnostic_output.Format = null,
    /// Whether any timing/reporting sink asked for a machine-readable receipt.
    fn measured(self: Reporting) bool {
        return self.timings_json or self.report;
    }
};
const usage = "usage: mylang test <entry.my> [--filter GLOB] [--cases FILE] [--json] [--force]\n" ++
    "       mylang test <entry.my|directory> --bench GLOB [--bench-output FILE] [--bench-baseline FILE] [--bench-policy FILE]\n" ++
    "       mylang bench-promote --candidate FILE --approver NAME --reason TEXT [--baseline FILE] [--output FILE] [--revision REV]\n" ++
    "       mylang build <file.my> (-o <output> | --run) [--help]\n" ++
    "       mylang doc-coverage [<repo-root>] (every implemented feature and standard export needs a documented example)\n       mylang " ++
    "doctest [<repo-root>] [--filter GLOB] [--report PATH] [--verbose] (run every fenced documentation example)\n       mylang " ++
    "<schema-project|input-module|check|run|dump-bytecode|di" ++
    "scover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fm" ++
    "t-module|fmt-project|emit-qbe|emit-project-qbe|list-modules|list-interfaces|list-" ++
    "declarations|check" ++
    "-project|run-project|check-policy> <file.my>\n  schema-project: --schema-report (include " ++
    "checked source and compiler identities)\n  " ++
    "input-module: reads a typed JSON manifest and writes generated " ++
    "module source\n  run: builds the program natively and runs it; it loads the whole project when the entry " ++
    "file opens with a module header (or a module-only import/export), and stays single-unit otherwise; " ++
    "run-project is the explicit project-entry alias\n  run/run-project: unbounded in instructions and frames by default; " ++
    "--max-steps=N and --max-frames=N impose a ceiling and --timeout=SECONDS caps elapsed time; " ++
    "--max-memory=BYTES --gc-stress --print-result --cache-dir=DIR --qbe=PATH --zig=PATH " ++
    "(native objects default to .mylang-cache/qbe, shared with build)\n  " ++
    "run/run-project: --max-memory takes K/M/G suffixes and caps the guest process's address space; " ++
    "MYLANG_MEMORY_LIMIT names the same ceiling and MYLANG_HOST_MEMORY_LIMIT replaces the " ++
    "compiler's own 8G ceiling (0 removes it)\n  " ++
    "run/run-project authority: every capability is granted by default; --restrict denies them " ++
    "and enables --allow-read=DIR --allow-write=DIR (repeatable) --allow-clock --allow-random[=SEED] " ++
    "--allow-env[=NAME,...] --allow-all. Under --restrict an entry point requesting an ungranted " ++
    "capability exits 2 before execution; --allow-random=SEED pins the seed in either mode\n  " ++
    "run/run-project: -- ends compiler options; every later value is a guest argument\n  " ++
    "run: --timings (native execution nanoseconds on stderr; excludes compilation and linking)\n  " ++
    "schema-project: --inputs=manifest.json (repeat for up to 16 modules)\n  " ++
    "discover-duplicates/discover-project-duplicates: --min-nodes=N " ++
    "--population=production|tests|generated|reference|intentional --timings --approximate " ++
    "--max-work=N\n  report-quality/report-project-quality: --max-function-lines=N " ++
    "--max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a " ++
    "signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  " ++
    "fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: " ++
    "--check (otherwise writes formatted source to " ++
    "stdout)\n" ++
    "  list-declarations: parse-only declarations-v1 JSON with byte ranges\n" ++
    "  index-project: JSON symbols, references and pinned source snapshot\n  project-dependencies: checked module graph and hashes; --inputs supported\n" ++
    "  one-shot commands: --timings=json (phase-timings-v1 JSON Lines on stderr)\n" ++
    "    --report prints work-report-v1 actual work/reuse plus a frontend-cache-v1 comparison receipt on stderr; --timings=json also adds them; --cache-dir=DIR selects their root; --no-cache disables reuse\n" ++
    "    --explain-invalidation prints an invalidation-report-v1 comparison on stderr for project-dependencies, check-project, run-project and module-syntax run; --no-cache explains against no baseline\n" ++
    "  all commands: --diagnostics=text|json (stderr JSON Lines; stdout unchanged)\n" ++
    "  check-session: persistent check/clear/quit lines on stdin; JSON status on stdout; --inputs supported\n";

/// Byte ceilings for guest execution, shared by every command that runs one.
const budget = @import("memory_budget");

/// Dispatch compiler commands, reporting usage/source/IO failures through process exit status.
/// The compiler bounds its own address space first, so a compiler defect fails
/// loudly instead of taking the machine into swap, and the `zig cc` and QBE
/// children a native build spawns inherit that ceiling and still finish.
pub fn main(init: std.process.Init) void {
    _ = budget.guardHost(init.environ_map);
    const status = dispatch(init) catch |err| status: {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: host failure: {s}\n", .{@errorName(err)}) catch "mylang: host failure\n";
        std.Io.File.stderr().writeStreamingAll(init.io, message) catch break :status @as(u8, 2);
        break :status @as(u8, 2);
    };
    if (status != 0) std.process.exit(status);
}

const grants = @import("cli_grants.zig");
const project_config = @import("project_config.zig");
const module_syntax = @import("module_syntax.zig");
const native_run = @import("native_run.zig");
const native_options = @import("qbe_build_options.zig");
/// Per-stage observations collected when an invalidation explanation ran.
const StageTally = struct { hits: usize = 0, misses: usize = 0, skipped: usize = 0 };
const RunObservation = struct {
    stages: [std.meta.tags(invalidation.Stage).len]StageTally = @splat(.{}),
    /// Which stages this command actually executed. Skipped stages are never
    /// reported as reuse.
    executed: [std.meta.tags(invalidation.Stage).len]bool = @splat(true),
    has_invalidation: bool = false,
    /// Actual executions and true reuse observed at the work sites. The
    /// comparison result (`fingerprint_unchanged`) travels on `work` so the
    /// rendered report keeps the two facts distinct.
    work: invalidation.Work = .{},
};

/// Record `performed` fresh executions and `reused` actual cache hits for one
/// work stage. `executed` becomes true so a stage the command reached but did
/// no per-item work for still reports `miss` rather than `skipped`.
fn recordWork(init: Context, which: invalidation.WorkStage, performed: usize, reused: usize) void {
    if (init.observation) |observation| observation.work.note(which, performed, reused);
}

/// Record a whole-command stage whose count is replaced rather than accumulated.
fn setWork(init: Context, which: invalidation.WorkStage, performed: usize, reused: usize) void {
    if (init.observation) |observation| observation.work.set(which, performed, reused);
}

/// Record a disabled optimization and its reason on the current observation.
fn recordBypass(init: Context, reason: []const u8, count: usize) void {
    if (init.observation) |observation| observation.work.addBypass(reason, count);
}

/// Stages a command actually runs. Lowering/emission/linking only happen for
/// commands that produce or execute a native artifact.
fn executedStages(command: Command) [std.meta.tags(invalidation.Stage).len]bool {
    var out: [std.meta.tags(invalidation.Stage).len]bool = @splat(true);
    const lowers = command == .run or command == .@"run-project" or command == .@"emit-project-qbe";
    const links = command == .run or command == .@"run-project";
    out[@backingInt(invalidation.Stage.lower_function)] = lowers;
    out[@backingInt(invalidation.Stage.emit_fragment)] = lowers;
    out[@backingInt(invalidation.Stage.link)] = links;
    return out;
}
const Context = struct {
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    diagnostics: diagnostic_output.Format,
    timings: *language.timings.Profile,
    /// Populated by a command that produced an invalidation explanation so the
    /// frontend-cache receipt can report the same per-stage counts.
    observation: ?*RunObservation = null,
    fn text(self: Context, bytes: []const u8) !void {
        if (self.diagnostics == .text) return std.Io.File.stderr().writeStreamingAll(self.io, bytes);
        const rendered = try diagnostic_output.message(self.gpa, bytes, self.diagnostics);
        defer self.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(self.io, rendered);
    }
};
fn dispatch(process: std.process.Init) !u8 {
    const args = try process.minimal.args.toSlice(process.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--features")) {
        try featureReport(process);
        return 0;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return @import("qbe_build.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "emit-runtime")) return @import("qbe_build.zig").emitRuntime(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "test")) return @import("native_test_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "bench-promote")) return @import("native_bench_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "doc-coverage")) return @import("doc_coverage_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "doctest")) return @import("doctest_command.zig").run(process, args[2..]);
    // The C backend is gone. Answer its command names with a migration that
    // points at the QBE replacements rather than a bare usage dump.
    if (args.len >= 2 and (std.mem.eql(u8, args[1], "emit-c") or std.mem.eql(u8, args[1], "emit-project-c"))) {
        const replacement = if (std.mem.eql(u8, args[1], "emit-c")) "emit-qbe" else "emit-project-qbe";
        var buffer: [192]u8 = undefined;
        const message = try std.fmt.bufPrint(&buffer, "mylang: {s} was removed with the C backend; use {s} instead\n", .{ args[1], replacement });
        try std.Io.File.stderr().writeStreamingAll(process.io, message);
        return 2;
    }
    const parsed = parseArgs(process.arena.allocator(), args[1..]) catch |err| switch (err) {
        error.Usage => {
            try std.Io.File.stderr().writeStreamingAll(process.io, usage);
            return 2;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    var timings = language.timings.Profile.init(process.io, parsed.reporting.timings_json, .compiler);
    const init: Context = .{
        .timings = &timings,
        .gpa = process.gpa,
        .arena = process.arena,
        .io = process.io,
        .environ = process.environ_map,
        .diagnostics = parsed.reporting.diagnostics orelse .text,
    };
    const status = run(init, parsed) catch |err| status: {
        const message = try std.fmt.allocPrint(init.gpa, "mylang: host failure: {s}\n", .{@errorName(err)});
        defer init.gpa.free(message);
        try init.text(message);
        break :status @as(u8, 2);
    };
    try timings.report(status);
    return status;
}
fn run(init: Context, parsed: Parsed) !u8 {
    if (parsed.command == .@"check-session") return checkSession(init, parsed);
    var frontend_cache = openFrontendCache(init, parsed);
    var semantic_store = openSemanticStore(init, parsed);
    var observation: RunObservation = .{ .executed = executedStages(parsed.command) };
    observation.work.command = @tagName(parsed.command);
    var command_init = init;
    command_init.observation = &observation;
    var with_frontend = parsed;
    with_frontend.frontend = if (frontend_cache) |*cache| cache else null;
    with_frontend.semantic = if (semantic_store) |*store| store else null;
    const status = runCommand(command_init, with_frontend) catch |err| {
        best_effort: {
            reportMeasured(init, parsed, if (frontend_cache) |*cache| cache else null, &observation) catch break :best_effort;
        }
        if (frontend_cache) |*cache| cache.deinit();
        if (semantic_store) |*store| store.deinit();
        return err;
    };
    try reportMeasured(init, parsed, if (frontend_cache) |*cache| cache else null, &observation);
    if (frontend_cache) |*cache| cache.deinit();
    if (semantic_store) |*store| store.deinit();
    return status;
}

/// Emit every requested machine-readable receipt after a command finishes.
/// `frontend-cache-v1` is only emitted when a persistent cache was opened (its
/// historical `--no-cache` behavior); `work-report-v1` is always emitted when
/// reporting was requested, including `--no-cache`, because it records work
/// actually performed rather than cache comparisons.
fn reportMeasured(init: Context, parsed: Parsed, cache: ?*language.frontend_cache.Cache, observation: *RunObservation) !void {
    if (!parsed.reporting.measured()) return;
    if (parsed.no_cache) observation.work.addBypass("cache-disabled", 1);
    if (cache) |opened| {
        if (opened.statistics.damaged != 0) observation.work.addBypass("damaged-entry", opened.statistics.damaged);
        if (opened.statistics.bypassed != 0) observation.work.addBypass("frontend-store-bypassed", opened.statistics.bypassed);
        try reportFrontendCounters(init, opened, parsed.reporting, observation.*);
    }
    const rendered = try invalidation.renderWork(init.gpa, observation.work);
    defer init.gpa.free(rendered);
    const line = try std.fmt.allocPrint(init.gpa, "{s}\n", .{rendered});
    defer init.gpa.free(line);
    try std.Io.File.stderr().writeStreamingAll(init.io, line);
}
/// Dispatch one command with `parsed.frontend` already resolved.
fn runCommand(init: Context, parsed: Parsed) !u8 {
    const allocator = init.gpa;
    switch (parsed.command) {
        .@"index-project",
        .@"project-dependencies",
        .@"check-session",
        .@"schema-project",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        .@"fmt-project",
        .@"emit-project-qbe",
        .@"native-test-graph",
        .@"native-test-compile",
        => return listModules(init, parsed),
        else => {},
    }
    init.timings.begin("source_load", false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    init.timings.counts.source_bytes = bytes.len;
    init.timings.counts.modules = 1;
    init.timings.end();
    // `run` and `check` accept a project entry: a file that opens with a module
    // header (or a module-only import/export) loads its reachable graph exactly as
    // `run-project`/`check-project` does. A plain single-file program skips this
    // and keeps the original one-unit path byte-for-byte.
    if (parsed.command == .run and module_syntax.usesModuleSyntax(bytes)) return listModules(init, parsed);
    if (parsed.command == .check and module_syntax.usesModuleSyntax(bytes)) {
        var project = parsed;
        project.command = .@"check-project";
        return listModules(init, project);
    }
    // A single-unit program has no import edges, but a configured project still
    // owns the same required configuration contract; validate it before checking.
    validateUnitConfiguredPolicy(init, parsed) catch |err| return policyFailureStatus(err);
    if (parsed.command == .run and parsed.reporting.explain_invalidation) {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    }
    if (parsed.command == .@"input-module") {
        var manifest = (try parseInputManifest(init, parsed.path, bytes)) orelse return 2;
        defer manifest.deinit();
        const generated = try manifest.generate(allocator);
        defer allocator.free(generated);
        try std.Io.File.stdout().writeStreamingAll(init.io, generated);
        return 0;
    }
    init.timings.begin(frontend_label, false);
    var compilation = try language.Compilation.init(allocator, parsed.path, bytes);
    defer compilation.deinit();
    if (parsed.command == .fmt or parsed.command == .@"fmt-module") {
        init.timings.begin("format_inclusive", true);
        const formatted = (if (parsed.command == .@"fmt-module") compilation.formatModule(allocator) else compilation.format(allocator)) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        init.timings.end();
        defer allocator.free(formatted);
        // Formatting lexes and parses the unit even when no cache is open.
        setWork(init, .parsed_modules, 1, 0);
        if (parsed.format_check) {
            if (std.mem.eql(u8, formatted, bytes)) return 0;
            try init.text("formatting differs\n");
            return 1;
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, formatted);
        return 0;
    }
    if (parsed.command == .@"list-declarations") {
        init.timings.begin("declaration_listing", true);
        const listing = compilation.listDeclarations(allocator) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        init.timings.end();
        defer allocator.free(listing);
        // Declaration listing parses the unit before rendering.
        setWork(init, .parsed_modules, 1, 0);
        try std.Io.File.stdout().writeStreamingAll(init.io, listing);
        return 0;
    }
    const check_start = if (parsed.reporting.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    // Parse through the persistent syntax cache, then check through the same
    // checked-body query path used by project commands. Reuse is recorded at the
    // copy site; `--no-cache` keeps a zero-retention counting cache.
    const disk_before: usize = if (parsed.frontend) |opened| opened.statistics.syntax.hits else 0;
    var counting = try openSemanticCache(init, parsed);
    defer counting.deinit();
    compilation.parseCached(parsed.frontend) catch |err| switch (err) {
        error.SourceError => {
            try report(init, &compilation);
            return 1;
        },
        else => return err,
    };
    const syntax_reused = (if (parsed.frontend) |opened| opened.statistics.syntax.hits else 0) - disk_before;
    setWork(init, .parsed_modules, 1 - @min(syntax_reused, 1), @min(syntax_reused, 1));
    compilation.checkWithCache(&counting) catch |err| switch (err) {
        error.SourceError => {
            recordCheckWork(init, &counting, null, compilation.program);
            recordSemanticBypass(init, &counting, null);
            try report(init, &compilation);
            return 1;
        },
        else => return err,
    };
    recordCheckWork(init, &counting, null, compilation.program);
    recordSemanticBypass(init, &counting, null);
    init.timings.counts.ast_nodes = compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len;
    init.timings.counts.typed_nodes = compilation.program.?.nodes.len + compilation.program.?.statements.len;
    init.timings.end();
    const check_ns = if (parsed.reporting.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    if (parsed.command != .@"emit-qbe") try report(init, &compilation);
    switch (parsed.command) {
        .@"index-project",
        .@"project-dependencies",
        .@"check-session",
        .@"schema-project",
        .@"input-module",
        .fmt,
        .@"fmt-module",
        .@"fmt-project",
        .@"list-declarations",
        .@"emit-project-qbe",
        .@"native-test-graph",
        .@"native-test-compile",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        => unreachable,
        .@"emit-qbe" => {
            const generated = emitMeasuredNative(init, &compilation) catch |err| switch (err) {
                error.SourceError => {
                    try report(init, &compilation);
                    return 1;
                },
                else => return err,
            };
            init.timings.end();
            defer allocator.free(generated);
            try report(init, &compilation);
            try std.Io.File.stdout().writeStreamingAll(init.io, generated);
        },
        .check => return 0,
        .@"report-quality" => {
            var analysis = try language.quality.analyze(allocator, compilation.program.?, compilation.src, parsed.quality);
            defer analysis.deinit();
            const text = try language.quality.render(allocator, analysis, compilation.program.?, compilation.src);
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
        },
        .@"discover-duplicates" => {
            const start = std.Io.Timestamp.now(init.io, .awake);
            init.timings.begin("discovery", false);
            var analysis = try language.duplicates.discover(allocator, compilation.program.?, parsed.discovery);
            init.timings.end();
            defer analysis.deinit();
            const analysis_ns = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
            const text = try language.duplicates.render(allocator, analysis, compilation.program.?, compilation.src);
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
            if (parsed.reporting.timings) {
                const counts = try std.fmt.allocPrint(allocator, "timings: frontend_ns={d} discovery_ns={d} source_bytes={d} ast_nodes={d} typed_nodes={d} " ++
                    "canonical_bytes={d} functions={d}" ++
                    "\n", .{
                    check_ns,
                    analysis_ns,
                    bytes.len,
                    compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len,
                    compilation.program.?.nodes.len + compilation.program.?.statements.len,
                    analysis.canonical_bytes,
                    analysis.functions_examined,
                });
                defer allocator.free(counts);
                try init.text(counts);
            }
        },
        .@"dump-bytecode" => {
            init.timings.begin("bytecode_dump_inclusive", true);
            const text = try compilation.dump(allocator);
            if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
            init.timings.end();
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
        },
        .run => return executeRun(init, &compilation, parsed),
    }
    return 0;
}

/// Report the flag that would grant an entry point the authority it asked for.
/// Only `--restrict` can withhold one, so the message names the active mode.
fn reportUngranted(init: Context, flag: []const u8) !u8 {
    const message = try std.fmt.allocPrint(
        init.gpa,
        "mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass {s}, or drop --restrict to grant every capability\n",
        .{flag},
    );
    defer init.gpa.free(message);
    try init.text(message);
    return 2;
}

/// Build the checked program with the native backend and run it, passing its
/// standard output and error through and adopting its exit status.
fn executeRun(init: Context, compilation: *language.Compilation, parsed: Parsed) !u8 {
    compilation.emit() catch |err| switch (err) {
        error.SourceError => {
            try report(init, compilation);
            return 1;
        },
        else => return err,
    };
    if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
    if (grants.ungranted(compilation.code.?, parsed.grants)) |flag| return reportUngranted(init, flag);
    const manifest = emitMeasuredNative(init, compilation) catch |err| switch (err) {
        error.SourceError => {
            try report(init, compilation);
            return 1;
        },
        else => return err,
    };
    defer init.gpa.free(manifest);
    return runNative(init, parsed, manifest);
}

/// Publish the emitted units as an executable, run it, and report execution timing.
fn runNative(init: Context, parsed: Parsed, manifest: []const u8) !u8 {
    init.timings.begin("native_execution", false);
    const start = std.Io.Timestamp.now(init.io, .awake);
    // `native_run` publishes or reuses the executable and executes it. The
    // conservative count here never claims link reuse: object-level reuse inside
    // the native build is D1's receipt, not this report's measurement.
    setWork(init, .links, 1, 0);
    var settings = parsed.native;
    settings.arguments = parsed.runtime;
    settings.max_memory = parsed.max_memory;
    const status = try native_run.execute(init.gpa, .{
        .io = init.io,
        .environ = init.environ,
        .manifest = manifest,
        .settings = settings,
        .diagnostics = if (init.diagnostics == .json) .json else .text,
    });
    init.timings.end();
    if (!parsed.reporting.timings) return status;
    const elapsed = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
    var buffer: [96]u8 = undefined;
    try init.text(try std.fmt.bufPrint(&buffer, "timings: native_ns={d}\n", .{elapsed}));
    return status;
}

fn report(init: Context, compilation: *const language.Compilation) !void {
    for (compilation.diagnostics.items) |diagnostic| {
        const rendered = try diagnostic_output.render(init.gpa, diagnostic, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
    }
}

const Command = enum {
    @"index-project",
    @"project-dependencies",
    @"check-session",
    @"schema-project",
    @"input-module",
    @"emit-project-qbe",
    @"native-test-graph",
    @"native-test-compile",
    @"fmt-project",
    @"fmt-module",
    @"report-project-quality",
    @"discover-project-duplicates",
    @"check-policy",
    @"check-project",
    @"run-project",
    @"list-interfaces",
    @"list-modules",
    @"emit-qbe",
    @"list-declarations",
    fmt,
    check,
    run,
    @"dump-bytecode",
    @"discover-duplicates",
    @"report-quality",
};
const ArgError = error{ Usage, OutOfMemory };

const Parsed = struct {
    schema_report: bool,
    inputs: [16][]const u8,
    input_count: usize,
    policy: ?[]const u8,
    format_check: bool,
    write: bool,
    /// `list-interfaces --contracts` emits declaration-level provider contracts.
    contracts: bool,
    quality: language.quality.Options,
    command: Command,
    path: []const u8,
    grants: grants.Config,
    native: native_options.Options,
    runtime: []const []const u8,
    discovery: language.duplicates.Options,
    reporting: Reporting,
    max_memory: ?u64,
    /// Internal selective native emission input; one qualified function per line.
    select_file: ?[]const u8,
    /// `--no-cache` disables all persistent frontend reuse for this command.
    no_cache: bool,
    /// `--cache-dir` selects the cache root; null uses the default location.
    cache_dir: ?[]const u8,
    /// Persistent frontend cache opened by `run` for commands that reuse frontend
    /// work; null for commands (or sessions) that do not.
    frontend: ?*language.frontend_cache.Cache = null,
    /// Persistent checked-body store opened by `run`. It shares the existing
    /// `--cache-dir` root and is null under `--no-cache`.
    semantic: ?*language.semantic_cache.Store = null,
};
fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) ArgError!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var parser: ArgumentParser = .{ .command = command, .allocator = allocator };
    for (args[1..]) |arg| {
        if (parser.after_delimiter) {
            try parser.appendRuntime(arg);
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            if (!parser.executes()) return error.Usage;
            try parser.appendRuntime("--");
            parser.after_delimiter = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--diagnostics=")) {
            if (parser.reporting.diagnostics != null) return error.Usage;
            parser.reporting.diagnostics = std.meta.stringToEnum(diagnostic_output.Format, arg["--diagnostics=".len..]) orelse return error.Usage;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-cache")) {
            if (parser.no_cache) return error.Usage;
            parser.no_cache = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--report")) {
            if (parser.reporting.report) return error.Usage;
            parser.reporting.report = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--explain-invalidation")) {
            if (parser.reporting.explain_invalidation) return error.Usage;
            switch (command) {
                .@"project-dependencies", .@"check-project", .@"run-project", .run => {},
                else => return error.Usage,
            }
            parser.reporting.explain_invalidation = true;
            continue;
        }
        if (try parser.cacheDirectoryOption(arg)) continue;
        if (try parser.surfaceOption(arg)) continue;
        if (try parser.qualityOption(arg)) continue;
        if (try parser.grantOption(arg)) continue;
        if (try parser.executionOption(arg)) continue;
        if (try parser.discoveryOption(arg)) continue;
        if (std.mem.startsWith(u8, arg, policy_prefix)) {
            if (command != .@"check-policy" or parser.policy != null or arg.len == policy_prefix.len) return error.Usage;
            parser.policy = arg[policy_prefix.len..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--") or parser.path != null) return error.Usage;
        parser.path = arg;
    }
    return parser.finish();
}
const ArgumentParser = struct {
    command: Command,
    schema_report: bool = false,
    contracts: bool = false,
    inputs: [16][]const u8 = @splat(""),
    input_count: usize = 0,
    quality: language.quality.Options = .{},
    quality_seen: u8 = 0,
    format_check: bool = false,
    write: bool = false,
    path: ?[]const u8 = null,
    policy: ?[]const u8 = null,
    grants: grants.Config = .{},
    native: native_options.Options = .{ .source = "", .run = true },
    allocator: std.mem.Allocator,
    runtime: std.ArrayList([]const u8) = .empty,
    after_delimiter: bool = false,
    saw_steps: bool = false,
    saw_frames: bool = false,
    gc_stress: bool = false,
    max_memory: ?u64 = null,
    discovery: language.duplicates.Options = .{},
    reporting: Reporting = .{},
    no_cache: bool = false,
    cache_dir: ?[]const u8 = null,
    select_file: ?[]const u8 = null,
    saw_min: bool = false,
    saw_population: bool = false,
    saw_work: bool = false,
    /// `--cache-dir` is shared by every frontend-caching command; the executing
    /// commands additionally hand the same directory to the native object cache.
    fn cacheDirectoryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (!std.mem.startsWith(u8, arg, cache_directory_prefix)) return false;
        if (self.cache_dir != null or arg.len == cache_directory_prefix.len) return error.Usage;
        self.cache_dir = arg[cache_directory_prefix.len..];
        if (self.executes()) self.native.cache = self.cache_dir.?;
        return true;
    }

    fn surfaceOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, arg, "--contracts")) {
            if (self.command != .@"list-interfaces" or self.contracts) return error.Usage;
            self.contracts = true;
            return true;
        }
        if (std.mem.eql(u8, arg, "--schema-report")) {
            if (self.command != .@"schema-project" or self.schema_report) return error.Usage;
            self.schema_report = true;
            return true;
        }
        if (std.mem.startsWith(u8, arg, inputs_prefix)) {
            switch (self.command) {
                .@"schema-project", .@"check-session", .@"project-dependencies" => {},
                else => return error.Usage,
            }
            if (self.input_count == self.inputs.len or arg.len == inputs_prefix.len) return error.Usage;
            const input = arg[inputs_prefix.len..];
            for (self.inputs[0..self.input_count]) |previous| if (std.mem.eql(u8, previous, input)) return error.Usage;
            self.inputs[self.input_count] = input;
            self.input_count += 1;
            return true;
        }
        return false;
    }

    fn qualityOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        inline for (.{
            "max_function_lines",
            "max_parameters",
            "max_nesting",
            "max_decisions",
            "max_line_bytes",
        }, .{
            "--max-function-lines=",
            "--max-parameters=",
            "--max-nesting=",
            "--max-decisions=",
            "--max-line-bytes=",
        }, 0..) |field, prefix, index| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                const bit: u8 = 1 << index;
                if ((self.command != .@"report-quality" and self.command != .@"report-project-quality") or self.quality_seen & bit != 0) return error.Usage;
                self.quality_seen |= bit;
                const digits = arg[prefix.len..];
                if (digits.len == 0) return error.Usage;
                for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                    return error.Usage;
                };
                @field(self.quality, field) = std.fmt.parseUnsigned(usize, digits, 10) catch return error.Usage;
                return true;
            }
        }
        return false;
    }

    fn checks(self: *const ArgumentParser) bool {
        return switch (self.command) {
            .fmt, .@"fmt-module", .@"fmt-project" => true,
            else => false,
        };
    }
    /// Authority options apply only to the commands that execute a program.
    fn grantOption(self: *ArgumentParser, arg: []const u8) ArgError!bool {
        if (!std.mem.startsWith(u8, arg, "--allow-") and !std.mem.eql(u8, arg, grants.restrict_flag)) return false;
        if (self.command != .run and self.command != .@"run-project") return error.Usage;
        if (!try self.grants.parse(arg)) return error.Usage;
        try self.forward(arg);
        return true;
    }
    /// Keep one option for the built program, which parses grants and budgets itself.
    fn forward(self: *ArgumentParser, arg: []const u8) ArgError!void {
        return self.appendRuntime(arg);
    }
    /// Whether an option with this prefix was already forwarded before the `--`
    /// guest delimiter, so a repeat cannot silently override the first value.
    fn forwarded(self: *const ArgumentParser, prefix: []const u8) bool {
        for (self.runtime.items) |existing| {
            if (std.mem.eql(u8, existing, "--")) break;
            if (std.mem.startsWith(u8, existing, prefix)) return true;
        }
        return false;
    }
    /// Append one raw child argument, including the `--` guest delimiter.
    fn appendRuntime(self: *ArgumentParser, arg: []const u8) ArgError!void {
        try self.runtime.append(self.allocator, arg);
    }
    fn executes(self: *const ArgumentParser) bool {
        return self.command == .run or self.command == .@"run-project";
    }
    /// Read one non-empty `--flag=value` that only an executing command accepts.
    fn value(self: *const ArgumentParser, arg: []const u8, flag: []const u8) error{Usage}![]const u8 {
        if (!self.executes() or arg.len == flag.len) return error.Usage;
        return arg[flag.len..];
    }
    fn executionOption(self: *ArgumentParser, arg: []const u8) ArgError!bool {
        if (std.mem.eql(u8, arg, "--check")) {
            if (!self.checks() or self.format_check) return error.Usage;
            self.format_check = true;
        } else if (std.mem.eql(u8, arg, "--gc-stress")) {
            if (!self.executes() or self.gc_stress) return error.Usage;
            self.gc_stress = true;
            try self.forward(arg);
        } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
            if (!self.executes() or self.saw_steps) return error.Usage;
            self.saw_steps = true;
            _ = try positive(arg["--max-steps=".len..]);
            try self.forward(arg);
        } else if (std.mem.startsWith(u8, arg, "--max-frames=")) {
            if (!self.executes() or self.saw_frames) return error.Usage;
            self.saw_frames = true;
            _ = try positive(arg["--max-frames=".len..]);
            try self.forward(arg);
        } else if (std.mem.startsWith(u8, arg, timeout_prefix)) {
            if (!self.executes() or self.forwarded(timeout_prefix)) return error.Usage;
            _ = try positive(arg[timeout_prefix.len..]);
            try self.forward(arg);
        } else if (std.mem.startsWith(u8, arg, "--max-memory=")) {
            if (!self.executes() or self.max_memory != null) return error.Usage;
            self.max_memory = budget.parse(arg["--max-memory=".len..]) catch return error.Usage;
        } else if (std.mem.eql(u8, arg, "--print-result")) {
            if (!self.executes() or self.reporting.print_result) return error.Usage;
            self.reporting.print_result = true;
            try self.forward(arg);
        } else if (std.mem.startsWith(u8, arg, "--qbe=")) {
            self.native.qbe = try self.value(arg, "--qbe=");
        } else if (std.mem.startsWith(u8, arg, "--zig=")) {
            self.native.zig = try self.value(arg, "--zig=");
        } else if (std.mem.startsWith(u8, arg, select_file_prefix)) {
            if (self.command != .@"emit-project-qbe" or self.select_file != null or arg.len == select_file_prefix.len) return error.Usage;
            self.select_file = arg[select_file_prefix.len..];
        } else return false;
        return true;
    }

    fn discoveryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.startsWith(u8, arg, "--min-nodes=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_min) return error.Usage;
            self.saw_min = true;
            self.discovery.min_nodes = std.math.cast(usize, try positive(arg["--min-nodes=".len..])) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--population=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_population) return error.Usage;
            self.saw_population = true;
            self.discovery.population = std.meta.stringToEnum(language.duplicates.Population, arg["--population=".len..]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--approximate")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.discovery.approximate) return error.Usage;
            self.discovery.approximate = true;
        } else if (std.mem.startsWith(u8, arg, "--max-work=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_work) return error.Usage;
            self.saw_work = true;
            self.discovery.near_options.max_work = std.math.cast(usize, try positive(arg["--max-work=".len..])) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--timings=json")) {
            if (self.command == .@"check-session" or self.reporting.timings or self.reporting.timings_json) return error.Usage;
            self.reporting.timings_json = true;
        } else if (std.mem.eql(u8, arg, "--timings")) {
            const supported = self.command == .run or self.command == .@"discover-duplicates" or self.command == .@"discover-project-duplicates";
            if (!supported or self.reporting.timings or self.reporting.timings_json) return error.Usage;
            self.reporting.timings = true;
        } else return false;
        return true;
    }
    fn finish(self: *ArgumentParser) ArgError!Parsed {
        if (self.saw_work and !self.discovery.approximate) return error.Usage;
        if (self.command == .@"fmt-project" and !self.format_check) return error.Usage;
        if (self.command == .@"check-policy" and self.policy == null) return error.Usage;
        return .{
            .schema_report = self.schema_report,
            .inputs = self.inputs,
            .input_count = self.input_count,
            .policy = self.policy,
            .format_check = self.format_check,
            .write = self.write,
            .contracts = self.contracts,
            .quality = self.quality,
            .command = self.command,
            .path = self.path orelse return error.Usage,
            .grants = self.grants,
            .native = self.native,
            .runtime = self.runtime.items,
            .discovery = self.discovery,
            .reporting = self.reporting,
            .max_memory = self.max_memory,
            .no_cache = self.no_cache,
            .cache_dir = self.cache_dir,
            .select_file = self.select_file,
        };
    }
};

fn positive(digits: []const u8) error{Usage}!u64 {
    if (digits.len == 0) return error.Usage;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) {
        return error.Usage;
    };
    const value = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
    if (value == 0) return error.Usage;
    return value;
}

const GeneratedInput = struct { module: []const u8, path: []const u8, source: []const u8, manifest_path: []const u8, manifest_sha256: []const u8 };
const ModuleFiles = struct {
    io: std.Io,
    root: []const u8,
    inputs: []const GeneratedInput = &.{},
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *ModuleFiles = @ptrCast(@alignCast(context.?));
        for (self.inputs) |input| if (std.mem.eql(u8, input.path, relative)) {
            if (input.source.len > limit) return error.TooLarge;
            return allocator.dupe(u8, input.source);
        };
        var files: language.project_files.Files = .{ .io = self.io, .root = self.root };
        return language.project_files.Files.read(&files, allocator, relative, limit);
    }
};
fn listModules(init: Context, parsed: Parsed) !u8 {
    // C2 shares the one checked-body query path with the frontend cache. The
    // cache hydrates only validated durable entries and records reuse at the
    // actual `checkFunction`/copy site; `--no-cache` gets zero retention.
    var functions = try openSemanticCache(init, parsed);
    functions.context.timing = init.timings;
    defer functions.deinit();
    const status = try listModulesWithCache(init, parsed, null, null, &functions);
    recordSemanticBypass(init, &functions, null);
    return status;
}

/// Report a semantic cache that could not be consulted for this invocation,
/// plus each exact conservative fresh-path reason observed since `before`.
fn recordSemanticBypass(init: Context, functions: *const language.semantic_cache.Cache, before: ?language.semantic_cache.Statistics) void {
    const prior = before orelse language.semantic_cache.Statistics{};
    if (init.observation) |observation| {
        observation.work.counters.semantic = .{
            .retained_bytes = functions.statistics.retained_bytes,
            .ordinary_bytes = functions.statistics.retention.ordinary_bytes,
            .symbolic_bytes = functions.statistics.retention.symbolic_bytes,
            .specialization_bytes = functions.statistics.retention.specialization_bytes,
            .evicted = functions.statistics.retention.evicted,
        };
    }
    const delta = functions.statistics.bypassed - prior.bypassed;
    if (delta != 0) recordBypass(init, "semantic-reuse-unavailable", delta);
    var index: usize = 0;
    while (index < language.semantic_cache.miss_reason_count) : (index += 1) {
        const count = functions.statistics.misses[index] - prior.misses[index];
        if (count == 0) continue;
        const why: language.semantic_cache.MissReason = @fromBackingInt(@intCast(index));
        if (why == .cache_disabled) continue;
        recordBypass(init, language.semantic_cache.missReasonName(why), count);
    }
    // C3 symbolic-template misses are reported with the same conservative-reason
    // discipline; a template is never counted as reused unless a direct result
    // was actually replayed.
    index = 0;
    while (index < language.semantic_cache.symbolic.miss_reason_count) : (index += 1) {
        const why: language.semantic_cache.symbolic.MissReason = @fromBackingInt(@intCast(index));
        if (why == .cache_disabled) continue;
        const count = functions.reuse.symbolic.statistics.misses[@backingInt(why)];
        if (count == 0) continue;
        recordBypass(init, language.semantic_cache.symbolic.missReasonName(why), count);
    }
    // C3 concrete-specialization misses must be reported too: the checked
    // program's `instantiated_specializations` counter is not body-replay work.
    index = 0;
    while (index < language.semantic_cache.specializations.miss_reason_count) : (index += 1) {
        const why: language.semantic_cache.specializations.MissReason = @fromBackingInt(@intCast(index));
        if (why == .cache_disabled) continue;
        const count = functions.reuse.specializations.statistics.misses[@backingInt(why)];
        if (count == 0) continue;
        recordBypass(init, language.semantic_cache.specializations.missReasonName(why), count);
    }
}

/// Result of the required-policy frontend gate. `status` means the command must
/// return that status immediately; `config` owns a validated configuration whose
/// `identity` participates in caches and receipts.
const ConfiguredPolicy = struct {
    config: ?project_config.Config = null,
    identity: ?[64]u8 = null,
    fn deinit(self: *ConfiguredPolicy) void {
        if (self.config) |*config| config.deinit();
    }
};

/// Validate a discovered `mylang.json` for a single-unit command. A unit has no
/// import edges, so the policy itself is trivially satisfied; this still rejects
/// a missing or malformed configuration or policy instead of skipping it.
fn validateUnitConfiguredPolicy(init: Context, parsed: Parsed) !void {
    const config_path = project_config.discover(init.gpa, init.io, parsed.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try init.text("mylang: cannot inspect the entry directory for mylang.json\n");
        return error.HostConfiguration;
    } orelse return;
    defer init.gpa.free(config_path);
    var failure: project_config.Failure = .{};
    var config = project_config.load(init.gpa, init.io, config_path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(init.gpa, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n", .{
                failure.path, failure.location.line, failure.location.column, failure.detail,
            });
            defer init.gpa.free(message);
            try init.text(message);
            return error.HostConfiguration;
        },
    };
    defer config.deinit();
    const policy_file = config.policy orelse return;
    var policy = language.import_policy.Policy.parse(init.gpa, policy_file.bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(init.gpa, "{s}: error[E_PROJECT_CONFIG]: invalid import policy: {s}\n", .{
                policy_file.path, @errorName(err),
            });
            defer init.gpa.free(message);
            try init.text(message);
            return error.HostConfiguration;
        },
    };
    policy.deinit();
}

/// Map the required-policy gate's sentinel errors back to host statuses. Any
/// other failure is a real host error and propagates unchanged.
fn policyFailureStatus(err: anyerror) anyerror!u8 {
    return switch (err) {
        error.HostConfiguration => 2,
        error.PolicyViolation => 3,
        else => err,
    };
}

/// Discover and enforce the entry project's configured `mylang.json` policy.
/// Discovery starts at the entry file's directory and never consults the shell
/// working directory. `check-policy` is exempt because it inspects an explicit
/// policy path. Missing or malformed configuration returns host status 2; a
/// resolved import that violates the policy returns status 3.
fn loadConfiguredPolicy(init: Context, parsed: Parsed, project: *const language.project.Project, frontend: ?*language.frontend_cache.Cache, verdict: ?*language.check_cache.Cache) !ConfiguredPolicy {
    if (parsed.command == .@"check-policy") return .{};
    const config_path = project_config.discover(init.gpa, init.io, parsed.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try init.text("mylang: cannot inspect the entry directory for mylang.json\n");
        return error.HostConfiguration;
    } orelse return .{};
    defer init.gpa.free(config_path);

    var failure: project_config.Failure = .{};
    var config = project_config.load(init.gpa, init.io, config_path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(init.gpa, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n", .{
                failure.path, failure.location.line, failure.location.column, failure.detail,
            });
            defer init.gpa.free(message);
            try init.text(message);
            return error.HostConfiguration;
        },
    };
    var config_transferred = false;
    errdefer if (!config_transferred) config.deinit();
    if (!config.hasPolicy()) {
        setPolicyIdentity(frontend, verdict, null);
        config_transferred = true;
        return .{ .config = config };
    }

    var policy = language.import_policy.Policy.parse(init.gpa, config.policy.?.bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(init.gpa, "{s}: error[E_PROJECT_CONFIG]: invalid import policy: {s}\n", .{
                config.policy.?.path, @errorName(err),
            });
            defer init.gpa.free(message);
            try init.text(message);
            return error.HostConfiguration;
        },
    };
    defer policy.deinit();
    var policy_report = language.import_policy.evaluate(init.gpa, project, policy) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try init.text("mylang: configured import policy cannot be evaluated because the project graph is incomplete\n");
            return error.HostConfiguration;
        },
    };
    defer policy_report.deinit();
    if (policy_report.denied != 0) {
        const text = try language.import_policy.render(init.gpa, policy_report, project, policy);
        defer init.gpa.free(text);
        try init.text(text);
        return error.PolicyViolation;
    }
    var identity: [64]u8 = undefined;
    const has_identity = config.cacheIdentity(&identity);
    setPolicyIdentity(frontend, verdict, if (has_identity) identity[0..] else null);
    config_transferred = true;
    return .{ .config = config, .identity = if (has_identity) identity else null };
}

/// Publish the required-policy identity to the caches whose verdict must not
/// outlive a policy change. Null restores today's behavior for unconfigured projects.
fn setPolicyIdentity(frontend: ?*language.frontend_cache.Cache, verdict: ?*language.check_cache.Cache, identity: ?[]const u8) void {
    if (frontend) |opened| opened.runtime.policy_identity = identity;
    if (verdict) |opened| opened.policy_identity = identity;
}

/// Build the policy identity recorded in `project-dependencies-v1` receipts.
/// Strings belong to the command arena and live until the process exits.
fn configuredPolicyReceipt(allocator: std.mem.Allocator, configured: *const ConfiguredPolicy) !?language.dependency_report.Policy {
    const config = if (configured.config) |*value| value else return null;
    if (!config.hasPolicy()) return null;
    const receipt = try config.receipt(allocator);
    return .{ .config_sha256 = receipt.config_sha256, .policy_sha256 = receipt.policy_sha256 };
}

fn listModulesWithCache(init: Context, parsed: Parsed, cache: ?*language.syntax_cache.Cache, verdict: ?*language.check_cache.Cache, functions: ?*language.semantic_cache.Cache) !u8 {
    const frontend = parsed.frontend;
    const frontend_start = if (parsed.reporting.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    const path = parsed.path;
    const basename = std.fs.path.basename(path);
    if (!validEntryBasename(basename)) {
        try init.text("list-modules: entry must be an identifier.my file; imports resolve beneath its directory\n");
        return 2;
    }
    init.timings.begin("source_load_parse", false);
    var files: ModuleFiles = .{ .io = init.io, .root = std.fs.path.dirname(path) orelse "." };
    files.inputs = (try prepareInputs(init, parsed, basename)) orelse return 2;
    var project = language.project.Project.init(init.gpa);
    defer project.deinit();
    if (try loadModules(init, &project, &files, basename, try projectLimits(init, parsed))) |status| return status;
    init.timings.counts.modules = project.modules.items.len;
    init.timings.counts.source_bytes = project.counts.bytes;
    init.timings.end();
    // Required architectural policy is a frontend gate: discover and evaluate
    // it after the resolved graph is loaded but before any cached success can be
    // replayed. A project without `mylang.json` keeps its previous behavior.
    var configured = loadConfiguredPolicy(init, parsed, &project, frontend, verdict) catch |err| return policyFailureStatus(err);
    defer configured.deinit();
    const policy_receipt = try configuredPolicyReceipt(init.arena.allocator(), &configured);
    if (try surfaceProject(init, &project, parsed)) |status| return status;
    if (try replayStoredVerdict(init, parsed, &project, verdict, frontend)) return 0;
    // `list-interfaces` is the declaration/interface gate: it parses every module
    // and checks exported signatures without checking bodies. `--contracts`
    // publishes those declared contracts for provider validation.
    if (parsed.command == .@"list-interfaces") return listInterfaces(init, &project, parsed, cache, frontend);
    const output = if (parsed.command != .@"list-modules") result: {
        var index = (try buildIndex(init, &project, cache, frontend)) orelse return partialNavigation(init, &project, parsed.command);
        init.timings.begin("source_merge", false);
        var compilation = try language.project_compile.Compilation.init(&index);
        init.timings.end();
        if (parsed.command == .@"index-project") break :result try renderNavigation(init, &compilation, functions);
        const semantic_before = if (functions) |f| f.statistics else null;
        compilation.checkWithCache(functions) catch |err| switch (err) {
            error.SourceError => {
                recordCheckWork(init, functions, semantic_before, compilation.program);
                try reportProject(init, &compilation);
                if (parsed.reporting.explain_invalidation) {
                    try reportFailedInvalidation(init, parsed, &compilation, files.inputs);
                }
                return 1;
            },
            else => return err,
        };
        recordCheckWork(init, functions, semantic_before, compilation.program);
        init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
        init.timings.counts.typed_nodes = compilation.program.?.nodes.len + compilation.program.?.statements.len;
        // The internal native-test compile session keeps this one checked
        // compilation alive and serves facts plus selective lowering from it, so
        // a provider graph is never checked again just to emit its closure.
        if (parsed.command == .@"native-test-compile") return nativeTestCompileSession(init, &compilation);
        const executed = executedStages(parsed.command);
        // A selective `emit-project-qbe --select-file` lowers only its closure in
        // the emission helper; the whole-project receipt pass must not lower first.
        var receipt_stages = executed;
        if (parsed.command == .@"emit-project-qbe" and parsed.select_file != null) {
            receipt_stages[@backingInt(invalidation.Stage.lower_function)] = false;
            receipt_stages[@backingInt(invalidation.Stage.emit_fragment)] = false;
        }
        // A command that lowers must do so before the receipt is built: emitted
        // fragments are real inputs to the lower/emit/link explanation, not an
        // empty table that can only compare equal.
        if (!try lowerForReceipt(init, &compilation, receipt_stages)) {
            try reportProject(init, &compilation);
            if (parsed.reporting.explain_invalidation) {
                try reportFailedInvalidation(init, parsed, &compilation, files.inputs);
            }
            return 1;
        }
        // One receipt serves both the invalidation comparison and, for
        // `project-dependencies`, the normal stdout payload.
        var dependency_receipt: ?[]u8 = null;
        defer if (dependency_receipt) |bytes| init.gpa.free(bytes);
        if (parsed.command == .@"project-dependencies" or parsed.reporting.explain_invalidation) {
            dependency_receipt = try dependencyReport(init, &compilation, files.inputs, policy_receipt);
        }
        if (parsed.reporting.explain_invalidation) try reportInvalidation(init, parsed, dependency_receipt.?, executed, true);
        const requested_output = emitRequestedOutput(init, &compilation, parsed) catch |err| switch (err) {
            error.SourceError => return 1,
            else => return err,
        };
        if (requested_output) |output| break :result output;
        try reportProject(init, &compilation);
        if (parsed.command == .@"project-dependencies") break :result try init.gpa.dupe(u8, dependency_receipt.?);
        if (parsed.command == .@"check-project") {
            try rememberFrontendVerdict(init, parsed.command, &project, &compilation, frontend);
            return rememberCheck(verdict, &project, &compilation);
        }
        if (parsed.command == .@"discover-project-duplicates") return discoverProject(init, parsed, &project, &compilation, frontend_start);
        if (parsed.command == .@"check-policy") return checkProjectPolicy(init, parsed, &project);
        init.timings.begin(lowering_phase, false);
        try compilation.emit();
        if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
        init.timings.end();
        return runProjectProgram(init, &compilation, parsed);
    } else try project.render(init.gpa);
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    return 0;
}

/// Record the `checkFunction` execution-site counters for one check, plus the
/// concrete specializations the fresh check instantiated.
fn recordCheckWork(init: Context, functions: ?*language.semantic_cache.Cache, before: ?language.semantic_cache.Statistics, program: anytype) void {
    if (functions) |f| {
        const prior = before orelse language.semantic_cache.Statistics{};
        recordWork(init, .checked_bodies, f.statistics.checked - prior.checked, f.statistics.reused - prior.reused);
        if (init.observation) |observation| {
            observation.work.counters.symbolic.checked +|= f.reuse.symbolic.statistics.checked;
            observation.work.counters.symbolic.reused +|= f.reuse.symbolic.statistics.reused;
            observation.work.counters.specializations.checked +|= f.reuse.specializations.statistics.checked;
            observation.work.counters.specializations.reused +|= f.reuse.specializations.statistics.reused;
        }
    }
    if (program) |checked| {
        var specializations: usize = 0;
        for (checked.functions) |function| {
            if (function.type_arguments.len != 0) specializations += 1;
        }
        setWork(init, .instantiated_specializations, specializations, 0);
    }
}

/// Record lowered functions from the retained bytecode program. Lowering is a
/// whole-program step that runs at most once, so the count replaces earlier
/// values rather than accumulating.
fn recordLoweredCount(init: Context, functions: usize) void {
    setWork(init, .lowered_functions, functions, 0);
}

/// A refused final flush cannot be reported once the guest program has ended.
fn flushOutput(stdout: *std.Io.File.Writer) void {
    stdout.interface.flush() catch |err| switch (err) {
        error.WriteFailed => return,
    };
}

/// Build the checked project with the native backend and run its entry point.
fn runProjectProgram(init: Context, compilation: *language.project_compile.Compilation, parsed: Parsed) !u8 {
    if (grants.ungranted(compilation.code.?, parsed.grants)) |flag| return reportUngranted(init, flag);
    const manifest = emitMeasuredNative(init, compilation) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return 1;
        },
        else => return err,
    };
    defer init.gpa.free(manifest);
    try reportProject(init, compilation);
    return runNative(init, parsed, manifest);
}

fn emitProjectNative(init: Context, compilation: *language.project_compile.Compilation, select_file: ?[]const u8) !?[]u8 {
    const generated = (if (select_file) |path| emitMeasuredSelectedNative(init, compilation, path) else emitMeasuredNative(init, compilation)) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return null;
        },
        else => return err,
    };
    errdefer init.gpa.free(generated);
    try reportProject(init, compilation);
    return generated;
}

/// `native-test-graph` is an internal checked-facts producer. It emits no
/// lowering/emission receipt because no QBE work occurred, and stdout stays a
/// pure graph payload for the native-test parent.
fn emitNativeTestFacts(init: Context, compilation: *language.project_compile.Compilation) ![]u8 {
    init.timings.begin(frontend_label, false);
    const facts = compilation.emitNativeTestFacts(init.gpa) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return error.SourceError;
        },
        else => return err,
    };
    init.timings.end();
    return facts;
}

/// Internal checked-compilation session. It keeps the one compilation already
/// checked by `listModulesWithCache` and serves facts plus selective lowering
/// requests from it, so a native-test provider graph is checked exactly once.
/// Requests are one line each: `facts <out>`, `lower <select> <out>`, `quit`.
fn nativeTestCompileSession(init: Context, compilation: *language.project_compile.Compilation) !u8 {
    var buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (true) {
        const raw = input.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => return nativeTestCompileReply(init, "invalid", 2, request_too_long, 0, 0),
            else => return err,
        } orelse return 0;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "quit")) return nativeTestCompileReply(init, "quit", 0, null, 0, 0);
        if (std.mem.startsWith(u8, line, "facts ")) {
            const path = std.mem.trim(u8, line["facts ".len..], " \t");
            if (path.len == 0) return nativeTestCompileReply(init, "facts", 2, "MissingOutput", 0, 0);
            const facts = emitNativeTestFacts(init, compilation) catch |err| switch (err) {
                error.SourceError => return nativeTestCompileReply(init, "facts", 1, "SourceError", 0, 0),
                else => return err,
            };
            defer init.gpa.free(facts);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = facts });
            _ = try nativeTestCompileReply(init, "facts", 0, null, 0, 0);
            continue;
        }
        if (std.mem.startsWith(u8, line, "lower")) {
            var fields = std.mem.splitScalar(u8, line, '\t');
            _ = fields.next();
            const select = std.mem.trim(u8, fields.next() orelse "", " \t");
            const output = std.mem.trim(u8, fields.next() orelse "", " \t");
            if (select.len == 0 or output.len == 0) return nativeTestCompileReply(init, "lower", 2, "MissingSelection", 0, 0);
            const names = selectionNames(init, select) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return nativeTestCompileReply(init, "lower", 1, "SelectionReadFailed", 0, 0),
            };
            defer {
                for (names) |name| init.gpa.free(name);
                init.gpa.free(names);
            }
            init.timings.begin(lowering_phase, false);
            var stats: language.project_compile.Compilation.SelectedStats = .{};
            const manifest = compilation.emitQbeSelected(init.gpa, names, &stats) catch |err| switch (err) {
                error.SourceError => return nativeTestCompileReply(init, "lower", 1, "SourceError", 0, 0),
                else => return err,
            };
            defer init.gpa.free(manifest);
            recordLoweredCount(init, stats.lowered_functions);
            setWork(init, .emitted_fragments, stats.emitted_fragments, 0);
            init.timings.end();
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output, .data = manifest });
            _ = try nativeTestCompileReply(init, "lower", 0, null, stats.lowered_functions, stats.emitted_fragments);
            continue;
        }
        return nativeTestCompileReply(init, "invalid", 2, "UnknownSessionCommand", 0, 0);
    }
}

/// One `native-test-compile-v1` reply line. The checked payload itself is
/// written to the request's output path so the session stream stays line-sized.
fn nativeTestCompileReply(init: Context, action: []const u8, status: u8, failure: ?[]const u8, lowered: usize, emitted: usize) !u8 {
    const text = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "native-test-compile-v1",
        .action = action,
        .status = status,
        .failure = failure,
        .lowered_functions = lowered,
        .emitted_fragments = emitted,
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
    return status;
}

fn emitRequestedOutput(init: Context, compilation: *language.project_compile.Compilation, parsed: Parsed) !?[]u8 {
    return switch (parsed.command) {
        .@"native-test-graph" => try emitNativeTestFacts(init, compilation),
        .@"emit-project-qbe" => (try emitProjectNative(init, compilation, parsed.select_file)) orelse error.SourceError,
        .@"schema-project" => blk: {
            try reportProject(init, compilation);
            break :blk if (parsed.schema_report)
                try language.schema_report.render(init.gpa, compilation, try compilerIdentity(init.io))
            else
                try language.schema.render(init.gpa, compilation);
        },
        .@"report-project-quality" => blk: {
            try reportProject(init, compilation);
            const roots = try compilation.exportRoots(init.gpa);
            defer init.gpa.free(roots);
            var analysis = try language.quality.analyzeWithExports(init.gpa, compilation.program.?, compilation.src, parsed.quality, roots);
            defer analysis.deinit();
            break :blk try language.quality.render(init.gpa, analysis, compilation.program.?, compilation.src);
        },
        else => null,
    };
}

fn partialNavigation(init: Context, project: *language.project.Project, command: Command) !u8 {
    if (command != .@"index-project") return 1;
    const output = try language.navigation_partial.render(init.gpa, project, try compilerIdentity(init.io));
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    return 0;
}

fn renderNavigation(init: Context, compilation: *language.project_compile.Compilation, functions: ?*language.semantic_cache.Cache) ![]u8 {
    const semantic_before = if (functions) |f| f.statistics else null;
    compilation.checkWithCache(functions) catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    recordCheckWork(init, functions, semantic_before, compilation.program);
    init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
    if (compilation.program) |program| init.timings.counts.typed_nodes = program.nodes.len + program.statements.len;
    init.timings.end();
    try reportProject(init, compilation);
    return language.navigation.render(init.gpa, compilation, try compilerIdentity(init.io), .{});
}

/// Source-loading limits from the entry project's `mylang.json`, or the
/// built-in defaults when no configuration exists or it cannot be read. Each
/// present `budgets` field overrides the matching default. A malformed
/// configuration is reported by `loadConfiguredPolicy` after the graph loads,
/// exactly as before.
fn projectLimits(init: Context, parsed: Parsed) !language.project.Options {
    const discovered = project_config.discover(init.gpa, init.io, parsed.path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{},
    };
    const config_path = discovered orelse return .{};
    defer init.gpa.free(config_path);
    var failure: project_config.Failure = .{};
    var config = project_config.load(init.gpa, init.io, config_path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{},
    };
    defer config.deinit();
    var options: language.project.Options = .{};
    const budgets = config.document.budgets;
    if (budgets.max_modules) |value| options.max_modules = value;
    if (budgets.max_imports) |value| options.max_imports = value;
    if (budgets.max_file_bytes) |value| options.max_file_bytes = value;
    if (budgets.max_total_bytes) |value| options.max_total_bytes = value;
    return options;
}

fn loadModules(init: Context, project: *language.project.Project, files: *ModuleFiles, basename: []const u8, options: language.project.Options) !?u8 {
    project.load(.{ .context = files, .read = ModuleFiles.read }, basename[0 .. basename.len - 3], options) catch |err| switch (err) {
        error.SourceError => {
            const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
            return 1;
        },
        else => return err,
    };
    if (!try checkImportedInputs(init, files.inputs, project)) return 2;
    return null;
}

fn listInterfaces(init: Context, project: *language.project.Project, parsed: Parsed, cache: ?*language.syntax_cache.Cache, frontend: ?*language.frontend_cache.Cache) !u8 {
    var index = (try buildIndex(init, project, cache, frontend)) orelse return partialNavigation(init, project, parsed.command);
    if (parsed.contracts) {
        const contracts = index.renderContracts(init.gpa) catch |err| switch (err) {
            error.SourceError, error.IncompleteProject => {
                const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
                defer init.gpa.free(message);
                try std.Io.File.stderr().writeStreamingAll(init.io, message);
                return 1;
            },
            else => return err,
        };
        defer init.gpa.free(contracts);
        try std.Io.File.stdout().writeStreamingAll(init.io, contracts);
        return 0;
    }
    const text = try index.render(init.gpa);
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return 0;
}

fn buildIndex(init: Context, project: *language.project.Project, cache: ?*language.syntax_cache.Cache, frontend: ?*language.frontend_cache.Cache) !?language.interfaces.Index {
    const syntax_before: usize = if (cache) |opened| opened.statistics.hits else 0;
    const disk_before: usize = if (frontend) |opened| opened.statistics.syntax.hits else 0;
    const index = language.interfaces.buildWithCacheTimed(project, cache, frontend, init.timings) catch |err| switch (err) {
        error.SourceError => {
            recordParsedModules(init, project, cache, frontend, syntax_before, disk_before);
            const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
            return null;
        },
        else => return err,
    };
    recordParsedModules(init, project, cache, frontend, syntax_before, disk_before);
    return index;
}

/// Record module bodies actually lexed/parsed versus returned by an in-process
/// or persistent syntax lookup. The hit deltas come from the lookup execution
/// sites themselves, never from comparing source digests after parsing.
fn recordParsedModules(
    init: Context,
    project: *const language.project.Project,
    cache: ?*language.syntax_cache.Cache,
    frontend: ?*language.frontend_cache.Cache,
    syntax_before: usize,
    disk_before: usize,
) void {
    if (init.observation == null) return;
    var reused: usize = 0;
    if (cache) |opened| reused += opened.statistics.hits - syntax_before;
    if (frontend) |opened| reused += opened.statistics.syntax.hits - disk_before;
    const total = project.modules.items.len;
    const performed = if (reused > total) 0 else total - reused;
    recordWork(init, .parsed_modules, performed, @min(reused, total));
}

fn rememberCheck(verdict: ?*language.check_cache.Cache, project: *const language.project.Project, compilation: *const language.project_compile.Compilation) !u8 {
    if (verdict) |saved| try saved.remember(project, compilation.src, compilation.diagnostics.items.items);
    return 0;
}

/// Replay an in-process or persistent stored verdict before any semantic work.
/// A requested explanation must compare receipts, so it never replays a stored
/// verdict before the checked compilation produces one.
fn replayStoredVerdict(
    init: Context,
    parsed: Parsed,
    project: *const language.project.Project,
    verdict: ?*language.check_cache.Cache,
    frontend: ?*language.frontend_cache.Cache,
) !bool {
    if (try replayCheck(init, parsed.command, project, verdict)) return true;
    if (parsed.reporting.explain_invalidation) return false;
    return replayFrontendVerdict(init, parsed.command, project, frontend);
}

fn replayCheck(init: Context, command: Command, project: *const language.project.Project, verdict: ?*language.check_cache.Cache) !bool {
    if (command != .@"check-project") return false;
    const cache = verdict orelse return false;
    const warnings = cache.lookup(project) orelse return false;
    try std.Io.File.stderr().writeStreamingAll(init.io, warnings);
    if (init.observation) |observation| {
        observation.executed = @splat(false);
        observation.executed[@backingInt(invalidation.Stage.load_source)] = true;
        observation.work.results.request += 1;
    }
    return true;
}

/// Replay a persistent successful verdict for an identical project. The loaded
/// project facts (every module name, path and byte) are the key, so a changed
/// file, graph or module name never reaches the stored text.
fn replayFrontendVerdict(init: Context, command: Command, project: *const language.project.Project, frontend: ?*language.frontend_cache.Cache) !bool {
    if (command != .@"check-project") return false;
    const cache = frontend orelse return false;
    const warnings = (try cache.lookupVerdict(init.gpa, project, init.diagnostics)) orelse return false;
    defer init.gpa.free(warnings);
    try std.Io.File.stderr().writeStreamingAll(init.io, warnings);
    if (init.observation) |observation| {
        // Only loading sources ran; every semantic stage was answered by the
        // stored verdict, so none of them may be reported as fresh work.
        observation.executed = @splat(false);
        observation.executed[@backingInt(invalidation.Stage.load_source)] = true;
        observation.work.results.request += 1;
        // No module body was parsed and no body was checked.
        for (std.meta.tags(invalidation.WorkStage)) |stage| observation.work.skip(stage);
    }
    return true;
}

/// Retain a successful check's rendered warnings under the project's content key.
fn rememberFrontendVerdict(init: Context, command: Command, project: *const language.project.Project, compilation: *const language.project_compile.Compilation, frontend: ?*language.frontend_cache.Cache) error{OutOfMemory}!void {
    if (command != .@"check-project") return;
    const cache = frontend orelse return;
    var writer: std.Io.Writer.Allocating = .init(init.gpa);
    defer writer.deinit();
    for (compilation.diagnostics.items.items) |problem| {
        const rendered = try diagnostic_output.render(init.gpa, problem, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        writer.writer.writeAll(rendered) catch return error.OutOfMemory;
    }
    const warnings = writer.toOwnedSlice() catch return error.OutOfMemory;
    defer init.gpa.free(warnings);
    try cache.rememberVerdict(project, init.diagnostics, warnings);
}

fn reportProject(init: Context, compilation: *language.project_compile.Compilation) !void {
    for (compilation.diagnostics.items.items) |problem| {
        const message = try diagnostic_output.render(init.gpa, problem, compilation.src, init.diagnostics);
        defer init.gpa.free(message);
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
    }
}

/// `compiler_sha256` is a build-time digest of the compiler's own source inputs, Zig
/// version and optimize mode, embedded by `build.zig`. Re-reading the installed
/// executable to hash it cost seconds per report on a Debug build and told receipts
/// nothing extra: two builds of the same sources share this identity, and any source,
/// toolchain or mode change still changes it.
fn compilerIdentity(io: std.Io) !language.source_receipt.Identity {
    _ = io;
    const builtin = @import("builtin");
    return .{ .compiler_sha256 = build_identity, .zig_version = builtin.zig_version_string, .architecture = @tagName(builtin.cpu.arch), .os = @tagName(builtin.os.tag), .abi = @tagName(builtin.abi), .optimize = @tagName(builtin.mode) };
}
const build_identity: [32]u8 = identity: {
    const text = @import("qbe_build_assets").compiler_identity;
    var decoded: [32]u8 = undefined;
    for (&decoded, 0..) |*byte, index| byte.* = nibble(text[index * 2]) << 4 | nibble(text[index * 2 + 1]);
    break :identity decoded;
};
fn nibble(character: u8) u8 {
    return if (character <= '9') character - '0' else character - 'a' + 10;
}

fn parseInputManifest(init: Context, path: []const u8, bytes: []const u8) !?language.input_manifest.Manifest {
    return language.input_manifest.Manifest.parse(init.gpa, bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid input manifest: {s}\n", .{ path, @errorName(err) });
        defer init.gpa.free(message);
        try init.text(message);
        return null;
    };
}

/// Dispatch the whole-graph source-surface commands that never lower or execute.
fn surfaceProject(init: Context, project: *language.project.Project, parsed: Parsed) !?u8 {
    if (parsed.command == .@"fmt-project") {
        const status = try formatProject(init, project);
        return status;
    }
    return null;
}

fn formatProject(init: Context, project: *language.project.Project) !u8 {
    var changed: std.ArrayList([]const u8) = .empty;
    defer changed.deinit(init.gpa);
    for (project.order.items) |module_id| {
        const src = project.modules.items[module_id].src;
        var compilation = try language.Compilation.init(init.gpa, src.path, src.bytes);
        defer compilation.deinit();
        const formatted = compilation.formatModule(init.gpa) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        defer init.gpa.free(formatted);
        recordWork(init, .parsed_modules, 1, 0);
        if (!std.mem.eql(u8, formatted, src.bytes)) try changed.append(init.gpa, src.path);
    }
    for (changed.items) |path_name| {
        const message = try std.fmt.allocPrint(init.gpa, "{s}: formatting differs\n", .{path_name});
        defer init.gpa.free(message);
        try init.text(message);
    }
    return if (changed.items.len == 0) 0 else 1;
}

fn discoverProject(init: Context, parsed: Parsed, project: *language.project.Project, compilation: *language.project_compile.Compilation, frontend_start: std.Io.Timestamp) !u8 {
    const start = std.Io.Timestamp.now(init.io, .awake);
    init.timings.begin("discovery", false);
    var analysis = try language.duplicates.discover(init.gpa, compilation.program.?, parsed.discovery);
    init.timings.end();
    defer analysis.deinit();
    const discovery_ns = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
    const text = try language.duplicates.render(init.gpa, analysis, compilation.program.?, compilation.src);
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "scope: reachable module graph; declaration visibility and dependency policy require separate review\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    if (parsed.reporting.timings) {
        const counts = try std.fmt.allocPrint(init.gpa, "timings: project_frontend_ns={d} discovery_ns={d} modules={d} source_bytes={d} " ++
            "ast_nodes={d} typed_nodes={d} canonical_bytes={d} functions={d}" ++
            "\n", .{
            frontend_start.durationTo(start).nanoseconds,
            discovery_ns,
            project.modules.items.len,
            project.counts.bytes,
            compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len,
            compilation.program.?.nodes.len + compilation.program.?.statements.len,
            analysis.canonical_bytes,
            analysis.functions_examined,
        });
        defer init.gpa.free(counts);
        try init.text(counts);
    }
    return 0;
}

fn checkProjectPolicy(init: Context, parsed: Parsed, project: *language.project.Project) !u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.policy.?, init.gpa, .limited(1024 * 1024));
    defer init.gpa.free(bytes);
    var policy = language.import_policy.Policy.parse(init.gpa, bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid import policy: {s}\n", .{ parsed.policy.?, @errorName(err) });
        defer init.gpa.free(message);
        try init.text(message);
        return 2;
    };
    defer policy.deinit();
    var policy_report = try language.import_policy.evaluate(init.gpa, project, policy);
    defer policy_report.deinit();
    const text = try language.import_policy.render(init.gpa, policy_report, project, policy);
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "language: valid\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return if (policy_report.denied == 0) 0 else 3;
}

fn prepareInputs(init: Context, parsed: Parsed, basename: []const u8) !?[]GeneratedInput {
    const input_allocator = init.arena.allocator();
    var generated_inputs: std.ArrayList(GeneratedInput) = .empty;
    defer generated_inputs.deinit(input_allocator);
    var manifest_bytes: usize = 0;
    for (parsed.inputs[0..parsed.input_count]) |manifest_path| {
        // This Zig snapshot rejects reads that reach the supplied limit.
        // Add one so the documented manifest byte budgets are inclusive.
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, manifest_path, init.gpa, .limited(@min(1024 * 1024, 8 * 1024 * 1024 - manifest_bytes) + 1)) catch |err| switch (err) {
            error.StreamTooLong => {
                try init.text("input manifest byte budget exceeded (1 MiB per file, 8 MiB combined)\n");
                return null;
            },
            else => return err,
        };
        manifest_bytes += bytes.len;
        defer init.gpa.free(bytes);
        var manifest = (try parseInputManifest(init, manifest_path, bytes)) orelse return null;
        defer manifest.deinit();
        const module = manifest.parsed.value.module;
        if (std.mem.eql(u8, module, basename[0 .. basename.len - 3])) {
            try init.text("input manifest must supply an imported module, not the entry module\n");
            return null;
        }
        for (generated_inputs.items) |previous| if (std.mem.eql(u8, previous.module, module)) {
            const message = try std.fmt.allocPrint(init.gpa, "{s}: duplicate input module {s}; already supplied by {s}\n", .{ manifest_path, module, previous.manifest_path });
            defer init.gpa.free(message);
            try init.text(message);
            return null;
        };
        try generated_inputs.append(input_allocator, .{
            .module = try input_allocator.dupe(u8, module),
            .path = try language.project.modulePath(input_allocator, module),
            .source = try manifest.generate(input_allocator),
            .manifest_path = manifest_path,
            .manifest_sha256 = try language.dependency_report.hashBytes(input_allocator, bytes),
        });
    }
    const inputs = try generated_inputs.toOwnedSlice(input_allocator);
    return inputs;
}

fn dependencyManifests(allocator: std.mem.Allocator, inputs: []const GeneratedInput) ![]language.dependency_report.Manifest {
    const manifests = try allocator.alloc(language.dependency_report.Manifest, inputs.len);
    for (manifests, inputs) |*manifest, input| manifest.* = .{ .module = input.module, .path = input.manifest_path, .sha256 = input.manifest_sha256 };
    return manifests;
}

fn dependencyReport(init: Context, compilation: *language.project_compile.Compilation, inputs: []const GeneratedInput, policy: ?language.dependency_report.Policy) ![]u8 {
    const manifests = try dependencyManifests(init.gpa, inputs);
    defer init.gpa.free(manifests);
    return language.dependency_report.render(init.gpa, compilation, try compilerIdentity(init.io), manifests, policy);
}

/// Lower a project before its receipt is built when the command will emit, so
/// the receipt's fragment table is populated with real inputs. Returns false
/// when lowering reported a source error; the caller reports diagnostics.
fn lowerForReceipt(init: Context, compilation: *language.project_compile.Compilation, executed: [std.meta.tags(invalidation.Stage).len]bool) !bool {
    if (!executed[@backingInt(invalidation.Stage.lower_function)]) return true;
    init.timings.begin(lowering_phase, false);
    defer init.timings.end();
    compilation.emit() catch |err| switch (err) {
        error.SourceError => return false,
        else => return err,
    };
    if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
    return true;
}

/// Explain a rejected edit against the previous baseline without publishing a
/// successful verdict. A project that failed to load has no receipt to compare,
/// so the explanation is simply omitted rather than fabricated.
fn reportFailedInvalidation(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, inputs: []const GeneratedInput) !void {
    const manifests = try dependencyManifests(init.gpa, inputs);
    defer init.gpa.free(manifests);
    const current = language.dependency_report.renderPartial(init.gpa, compilation, try compilerIdentity(init.io), manifests, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    defer init.gpa.free(current);
    try reportInvalidation(init, parsed, current, executedStages(parsed.command), false);
}

fn checkImportedInputs(init: Context, inputs: []const GeneratedInput, project: *const language.project.Project) !bool {
    for (inputs) |input| if (!project.names.contains(input.module)) {
        const message = try std.fmt.allocPrint(init.gpa, "{s}: declared input module {s} is not imported by the reachable project\n", .{ input.manifest_path, input.module });
        defer init.gpa.free(message);
        try init.text(message);
        return false;
    };
    return true;
}

/// Resolve the persistent frontend cache directory for this invocation.
/// Precedence: `--no-cache`, then an explicit `--cache-dir` (nested under
/// `frontend/`), then `MYLANG_FRONTEND_CACHE` from a parent build driver, then
/// the per-project default. The compiler identity partitions the directory.
fn frontendRoot(init: Context, parsed: Parsed) ?[]const u8 {
    if (parsed.no_cache) return null;
    const base = parsed.cache_dir orelse init.environ.get("MYLANG_FRONTEND_CACHE") orelse language.frontend_cache.default_directory;
    if (std.mem.eql(u8, base, language.frontend_cache.default_directory)) return base;
    return std.fs.path.join(init.gpa, &.{ base, frontend_label }) catch null;
}

/// Open the persistent cache on demand; a missing or unwritable directory simply
/// disables reuse, never failing the command.
fn openFrontendCache(init: Context, parsed: Parsed) ?language.frontend_cache.Cache {
    const root = frontendRoot(init, parsed) orelse return null;
    // `&build_identity` points at the immutable compile-time global, so the
    // cache's borrowed identity outlives this frame; a local copy would dangle.
    var cache = language.frontend_cache.Cache.init(init.gpa, init.io, root, &build_identity);
    // A joined path is freshly allocated and released by deinit; the default
    // constant is static storage and must not be freed.
    cache.root_owned = root.ptr != language.frontend_cache.default_directory.ptr;
    return cache;
}

/// Resolve the baseline file for invalidation observations.  The path is
/// deliberately independent of the compiler-identity partition so a rebuilt
/// compiler still explains against the previous build's receipt.
fn invalidationBaselinePath(init: Context, parsed: Parsed) ![]const u8 {
    const base = parsed.cache_dir orelse language.frontend_cache.default_directory;
    const basename = std.fs.path.basename(parsed.path);
    const stem = if (std.mem.endsWith(u8, basename, ".my")) basename[0 .. basename.len - 3] else basename;
    const file_name = try init.gpa.alloc(u8, stem.len + ".json".len);
    defer init.gpa.free(file_name);
    for (stem, 0..) |character, index| {
        file_name[index] = if (std.ascii.isAlphanumeric(character) or character == '_' or character == '-') character else '_';
    }
    @memcpy(file_name[stem.len..], ".json");
    return std.fs.path.join(init.gpa, &.{ base, "invalidation", file_name });
}

/// Read a baseline receipt; a missing or unreadable file is simply no baseline.
fn readInvalidationBaseline(init: Context, path: []const u8) !?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

/// Atomically replace the baseline receipt.  Every failure is swallowed: a
/// read-only or full cache directory must never fail the command.
fn writeInvalidationBaseline(init: Context, path: []const u8, current: []const u8) void {
    const directory = std.fs.path.dirname(path) orelse return;
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return;
    var nonce: [8]u8 = undefined;
    std.Io.random(init.io, &nonce);
    var staging_buffer: [std.fs.max_path_bytes + 32]u8 = undefined;
    const staging = std.fmt.bufPrint(&staging_buffer, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return;
    std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = staging, .data = current }) catch return;
    std.Io.Dir.rename(.cwd(), staging, .cwd(), path, init.io) catch {
        std.Io.Dir.cwd().deleteFile(init.io, staging) catch |err| switch (err) {
            error.FileNotFound => {},
            else => {},
        };
        return;
    };
}

/// Emit one `invalidation-report-v1` line and, when caching is enabled, advance
/// the baseline so the next run explains against this receipt.
fn reportInvalidation(init: Context, parsed: Parsed, current: []const u8, executed: [std.meta.tags(invalidation.Stage).len]bool, publish: bool) !void {
    const path = try invalidationBaselinePath(init, parsed);
    defer init.gpa.free(path);

    var previous: ?[]u8 = null;
    if (!parsed.no_cache) previous = try readInvalidationBaseline(init, path);
    defer if (previous) |bytes| init.gpa.free(bytes);

    var explanation = try invalidation.explain(init.gpa, previous, current, &executed);
    defer explanation.deinit(init.gpa);

    if (init.observation) |observation| {
        observation.has_invalidation = true;
        observation.executed = executed;
        observation.stages = @splat(.{});
        var compared = false;
        var unchanged = true;
        for (explanation.queries) |query| {
            const index = @backingInt(query.stage);
            if (index < executed.len and executed[index]) {
                compared = true;
                if (query.status != .hit) unchanged = false;
            }
            switch (query.status) {
                .hit => observation.stages[index].hits += 1,
                .miss => observation.stages[index].misses += 1,
                .skipped => observation.stages[index].skipped += 1,
            }
        }
        // Only an executed stage can make fingerprints "equal"; a skipped stage
        // says nothing about the input digest. Null keeps "not compared"
        // distinct from "compared and changed".
        observation.work.fingerprint_unchanged = if (compared) unchanged else null;
    }

    const rendered = try invalidation.render(init.gpa, explanation);
    defer init.gpa.free(rendered);
    const line = try std.fmt.allocPrint(init.gpa, "{s}\n", .{rendered});
    defer init.gpa.free(line);
    try std.Io.File.stderr().writeStreamingAll(init.io, line);

    if (publish and !parsed.no_cache) writeInvalidationBaseline(init, path, current);
}

/// Report persistent frontend reuse when the caller asked for `--report` or
/// `--timings=json`. Both emit one machine-readable `frontend-cache-v1` JSON line
/// on stderr; plain `--timings` is left untouched because its text protocol is
/// `timings: native_ns=<integer>`.
fn reportFrontendCounters(init: Context, cache: *const language.frontend_cache.Cache, reporting: Reporting, observation: RunObservation) !void {
    if (!reporting.measured()) return;
    const stats = cache.statistics;
    var stages: [std.meta.tags(invalidation.Stage).len]StageTally = @splat(.{});
    if (observation.has_invalidation) {
        stages = observation.stages;
    } else {
        for (&stages, 0..) |*tally, index| {
            if (!observation.executed[index]) {
                tally.skipped = 1;
            } else if (index == @backingInt(invalidation.Stage.lex_parse)) {
                tally.hits = stats.syntax.hits;
                tally.misses = stats.syntax.misses;
            } else if (index == @backingInt(invalidation.Stage.resolve_interface)) {
                tally.hits = stats.verdict.hits;
                tally.misses = stats.verdict.misses;
            } else {
                // Executed fresh with no dedicated cache instrumentation.
                tally.misses = 1;
            }
        }
    }
    const json = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "frontend-cache-v1",
        .syntax_hits = stats.syntax.hits,
        .syntax_misses = stats.syntax.misses,
        .syntax_stored = stats.syntax.stored,
        .verdict_hits = stats.verdict.hits,
        .verdict_misses = stats.verdict.misses,
        .verdict_stored = stats.verdict.stored,
        .damaged = stats.damaged,
        .bypassed = stats.bypassed,
        .evicted = stats.evicted,
        .retained_bytes = stats.retained_bytes,
        .stages = .{
            .load_source = stages[@backingInt(invalidation.Stage.load_source)],
            .lex_parse = stages[@backingInt(invalidation.Stage.lex_parse)],
            .collect_declarations = stages[@backingInt(invalidation.Stage.collect_declarations)],
            .resolve_interface = stages[@backingInt(invalidation.Stage.resolve_interface)],
            .check_body = stages[@backingInt(invalidation.Stage.check_body)],
            .instantiate_specialization = stages[@backingInt(invalidation.Stage.instantiate_specialization)],
            .lower_function = stages[@backingInt(invalidation.Stage.lower_function)],
            .emit_fragment = stages[@backingInt(invalidation.Stage.emit_fragment)],
            .link = stages[@backingInt(invalidation.Stage.link)],
        },
    }, .{});
    defer init.gpa.free(json);
    const line = try std.fmt.allocPrint(init.gpa, "{s}\n", .{json});
    defer init.gpa.free(line);
    // The receipt is protocol data, not a diagnostic: `--diagnostics=json` must
    // not wrap it in a message envelope.
    try std.Io.File.stderr().writeStreamingAll(init.io, line);
}

fn validEntryBasename(basename: []const u8) bool {
    if (!std.mem.endsWith(u8, basename, ".my")) return false;
    const name = basename[0 .. basename.len - 3];
    if (!language.project.validName(name)) return false;
    return std.mem.indexOfScalar(u8, name, '.') == null;
}

/// Bind the full Wave-3 contract plus the message the C2 persistence context
/// needs: compiler identity, bootstrap language, target, effects-v3, runtime ABI,
/// relevant flags and the mutation-contract version. Persistence itself is C2;
/// this fingerprint only partitions retained bodies inside the session.
fn semanticCacheContractValue(init: Context) !language.semantic_cache.Contract {
    const allocator = init.arena.allocator();
    var contract = language.semantic_cache.Contract.default;
    const compiler_hex = std.fmt.bytesToHex(build_identity, .lower);
    contract.compiler_identity = try allocator.dupe(u8, &compiler_hex);
    contract.flags = "";
    return contract;
}

fn semanticCacheContract(init: Context) ![]const u8 {
    const allocator = init.arena.allocator();
    const contract = try semanticCacheContractValue(init);
    return contract.fingerprint(allocator);
}

/// Resolve the durable checked-body store root from the same shared cache-root
/// option as the frontend cache. `--no-cache` returns null, an explicit
/// `--cache-dir=DIR` nests under `DIR/semantic`, and the default is the
/// per-project `.mylang-cache/semantic` leaf.
fn semanticRoot(init: Context, parsed: Parsed) ?[]const u8 {
    if (parsed.no_cache) return null;
    const default_directory = language.semantic_cache.default_store_directory;
    const base = parsed.cache_dir orelse default_directory;
    if (std.mem.eql(u8, base, default_directory)) return default_directory;
    return std.fs.path.join(init.gpa, &.{ base, "semantic" }) catch null;
}

/// Open the durable checked-body store on demand. A missing or unwritable
/// directory only disables reuse; a host command is never failed by caching.
fn openSemanticStore(init: Context, parsed: Parsed) ?language.semantic_cache.Store {
    const root = semanticRoot(init, parsed) orelse return null;
    const contract = semanticCacheContractValue(init) catch return null;
    var store = language.semantic_cache.Store.init(init.gpa, init.io, root, contract, language.semantic_cache.mutation_contract_version);
    store.root.owned = root.ptr != language.semantic_cache.default_store_directory.ptr;
    return store;
}

/// Measurement-only semantic retention cap. The default is the production
/// 16 MiB budget; `MYLANG_SEMANTIC_BUDGET` is an opt-in profiling control used
/// by the large-project harness and never changes language semantics.
fn semanticBudget(init: Context) usize {
    const raw = init.environ.get("MYLANG_SEMANTIC_BUDGET") orelse return 16 * 1024 * 1024;
    return std.fmt.parseInt(usize, raw, 10) catch 16 * 1024 * 1024;
}

/// Open the per-invocation semantic cache. `--no-cache` gets a zero-retention
/// counting cache so it never reads or writes the durable store. A persistent
/// store is attached before `begin`, which hydrates only exact key/context hits.
fn openSemanticCache(init: Context, parsed: Parsed) !language.semantic_cache.Cache {
    if (parsed.semantic == null) return language.semantic_cache.Cache.init(init.gpa, 0);
    const contract = try semanticCacheContract(init);
    var cache = language.semantic_cache.Cache.initWithContract(init.gpa, semanticBudget(init), contract);
    cache.context.persistent = parsed.semantic;
    return cache;
}

const SessionCache = struct {
    syntax: language.syntax_cache.Cache,
    semantic: language.check_cache.Cache,
    functions: language.semantic_cache.Cache,
    /// Cumulative actual reuse and specialization counts observed across the
    /// session; `parsed_modules` and `checked_bodies` come from the caches'
    /// own cumulative observations.
    verdict_reuses: usize = 0,
    specializations: usize = 0,
};
fn checkSession(init: Context, parsed: Parsed) !u8 {
    if (!validEntryBasename(std.fs.path.basename(parsed.path))) {
        try init.text("check-session: entry must be an identifier.my file\n");
        return 2;
    }
    const contract_fingerprint = try semanticCacheContract(init);
    var cache: SessionCache = .{
        .syntax = language.syntax_cache.Cache.init(init.gpa, .{}),
        .semantic = language.check_cache.Cache.init(init.gpa, 16 * 1024 * 1024),
        .functions = language.semantic_cache.Cache.initWithContract(init.gpa, semanticBudget(init), contract_fingerprint),
    };
    defer cache.syntax.deinit();
    defer cache.semantic.deinit();
    defer cache.functions.deinit();
    cache.semantic.format = init.diagnostics;
    var buffer: [256]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (true) {
        const line = input.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try sessionReply(init, .{ .action = "invalid", .status = 2, .failure = request_too_long }, cache.syntax.statistics, &cache, .{});
                return 2;
            },
            else => return err,
        } orelse return 0;
        if (line.len > 128) {
            try sessionReply(init, .{ .action = "invalid", .status = 2, .failure = request_too_long }, cache.syntax.statistics, &cache, .{});
            return 2;
        }
        const action = std.mem.trim(u8, line, " \t\r");
        const before = cache.syntax.statistics;
        if (std.mem.eql(u8, action, "quit")) {
            try sessionReply(init, .{ .action = "quit", .status = 0 }, before, &cache, .{});
            return 0;
        }
        if (std.mem.eql(u8, action, "clear")) {
            cache.syntax.clear();
            cache.semantic.clear();
            cache.functions.clear();
            try sessionReply(init, .{ .action = "clear", .status = 0 }, before, &cache, .{});
        } else if (std.mem.eql(u8, action, "check")) {
            try sessionCheck(init, parsed, &cache);
        } else {
            try sessionReply(init, .{ .action = "invalid", .status = 2, .failure = "UnknownSessionCommand" }, before, &cache, .{});
        }
    }
}
fn sessionCheck(init: Context, parsed: Parsed, cache: *SessionCache) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    var request_init = init;
    request_init.arena = &arena;
    var request = parsed;
    request.command = .@"check-project";
    var observation: RunObservation = .{ .executed = executedStages(request.command) };
    observation.work.command = @tagName(request.command);
    request_init.observation = &observation;
    const before = cache.syntax.statistics;
    const status = listModulesWithCache(request_init, request, &cache.syntax, &cache.semantic, &cache.functions) catch |err| {
        cache.verdict_reuses += observation.work.results.request;
        cache.specializations += observation.work.stages[@backingInt(invalidation.WorkStage.instantiated_specializations)].performed;
        const reported: u8 = switch (err) {
            error.PolicyViolation => 3,
            else => 2,
        };
        try sessionReply(init, .{ .action = "check", .status = reported, .failure = @errorName(err) }, before, cache, observation.work);
        return;
    };
    cache.verdict_reuses += observation.work.results.request;
    cache.specializations += observation.work.stages[@backingInt(invalidation.WorkStage.instantiated_specializations)].performed;
    try sessionReply(init, .{ .action = "check", .status = status }, before, cache, observation.work);
}

/// Cumulative session work counters. `parsed_modules` and `checked_bodies` are
/// the caches' own cumulative execution-site observations; the rest are
/// accumulated here from each request.
fn sessionStages(cache: *const SessionCache) [invalidation.work_stage_count]invalidation.StageCount {
    var stages: [invalidation.work_stage_count]invalidation.StageCount = @splat(.{});
    stages[@backingInt(invalidation.WorkStage.parsed_modules)] = .{
        .executed = true,
        .performed = cache.syntax.statistics.misses,
        .reused = cache.syntax.statistics.hits,
    };
    stages[@backingInt(invalidation.WorkStage.checked_bodies)] = .{
        .executed = true,
        .performed = cache.functions.statistics.checked,
        .reused = cache.functions.statistics.reused,
    };
    stages[@backingInt(invalidation.WorkStage.instantiated_specializations)] = .{
        .executed = cache.specializations != 0,
        .performed = cache.specializations,
    };
    return stages;
}

/// One check-session reply's action, exit status and optional failure name.
const SessionReply = struct { action: []const u8, status: u8, failure: ?[]const u8 = null };
const ReasonCount = struct { reason: []const u8, count: usize };

fn sessionReply(
    init: Context,
    reply: SessionReply,
    before: language.syntax_cache.Statistics,
    cache: *const SessionCache,
    request_work: invalidation.Work,
) !void {
    var work = request_work;
    work.session = sessionStages(cache);
    work.results.session = cache.verdict_reuses;
    const summary = invalidation.summarize(&work);
    var ordinary_misses: [language.semantic_cache.miss_reason_count]ReasonCount = undefined;
    var ordinary_len: usize = 0;
    for (std.meta.tags(language.semantic_cache.MissReason)) |why| {
        const count = cache.functions.statistics.misses[@backingInt(why)];
        if (count == 0) continue;
        ordinary_misses[ordinary_len] = .{ .reason = language.semantic_cache.missReasonName(why), .count = count };
        ordinary_len += 1;
    }
    var symbolic_misses: [language.semantic_cache.symbolic.miss_reason_count]ReasonCount = undefined;
    var symbolic_len: usize = 0;
    for (std.meta.tags(language.semantic_cache.symbolic.MissReason)) |why| {
        const count = cache.functions.reuse.symbolic.statistics.misses[@backingInt(why)];
        if (count == 0) continue;
        symbolic_misses[symbolic_len] = .{ .reason = language.semantic_cache.symbolic.missReasonName(why), .count = count };
        symbolic_len += 1;
    }
    var specialization_misses: [language.semantic_cache.specializations.miss_reason_count]ReasonCount = undefined;
    var specialization_len: usize = 0;
    for (std.meta.tags(language.semantic_cache.specializations.MissReason)) |why| {
        const count = cache.functions.reuse.specializations.statistics.misses[@backingInt(why)];
        if (count == 0) continue;
        specialization_misses[specialization_len] = .{ .reason = language.semantic_cache.specializations.missReasonName(why), .count = count };
        specialization_len += 1;
    }
    const text = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "check-session-v1",
        .action = reply.action,
        .status = reply.status,
        .failure = reply.failure,
        .reuse = .{ .hits = cache.syntax.statistics.hits - before.hits, .misses = cache.syntax.statistics.misses - before.misses },
        .cache = cache.syntax.statistics,
        .semantic = cache.semantic.statistics,
        .functions = cache.functions.statistics,
        .semantic_retention = .{
            .retained_bytes = cache.functions.statistics.retained_bytes,
            .ordinary_bytes = cache.functions.statistics.retention.ordinary_bytes,
            .symbolic_bytes = cache.functions.statistics.retention.symbolic_bytes,
            .specialization_bytes = cache.functions.statistics.retention.specialization_bytes,
            .evicted = cache.functions.statistics.retention.evicted,
        },
        .semantic_miss_reasons = .{
            .ordinary = ordinary_misses[0..ordinary_len],
            .symbolic = symbolic_misses[0..symbolic_len],
            .specializations = specialization_misses[0..specialization_len],
        },
        .symbolic_templates = .{
            .checked = cache.functions.reuse.symbolic.statistics.checked,
            .reused = cache.functions.reuse.symbolic.statistics.reused,
            .stored = cache.functions.reuse.symbolic.statistics.stored,
        },
        .specialization_bodies = .{
            .checked = cache.functions.reuse.specializations.statistics.checked,
            .reused = cache.functions.reuse.specializations.statistics.reused,
            .stored = cache.functions.reuse.specializations.statistics.stored,
        },
        // work-report-v1 request deltas and cumulative session counters. The
        // request values reconcile with `cache`/`functions` deltas by
        // construction: both are read from the same execution-site counters.
        .work = .{
            .version = "work-report-v1",
            .fingerprint_unchanged = summary.fingerprint_unchanged,
            .reused = summary.reused,
            .request = summary.request,
            .session = summary.session,
            .reused_results = summary.request_reused_results,
            .session_reused_results = summary.session_reused_results,
            .bypassed = summary.bypassed,
        },
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

/// Report the installed compiler identity and its versioned supported surface.
fn featureReport(init: std.process.Init) !void {
    const identity = try compilerIdentity(init.io);
    const manifest = try std.json.parseFromSlice(std.json.Value, init.gpa, @embedFile("features.json"), .{});
    defer manifest.deinit();
    const text = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "language-features-v1",
        .compiler_sha256 = std.fmt.bytesToHex(identity.compiler_sha256, .lower),
        .zig_version = identity.zig_version,
        .features = manifest.value,
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

fn emitMeasuredNative(init: Context, compilation: anytype) ![]u8 {
    init.timings.begin(lowering_phase, false);
    try compilation.emit();
    if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
    init.timings.begin("native_emission", false);
    const generated = try compilation.emitQbe(init.gpa);
    // `qbe-units-v1` emits one independently linkable fragment per lowered
    // function, so the fragment count is observed at the emission site.
    if (compilation.code) |code| setWork(init, .emitted_fragments, code.functions.len, 0);
    init.timings.end();
    return generated;
}

/// Lower and emit only functions named in `select_file`. The file contains one
/// qualified function name per line and is produced by the native-test planner's
/// closure, so the whole-project emission path is never entered for an affected
/// selection.
fn emitMeasuredSelectedNative(init: Context, compilation: *language.project_compile.Compilation, select_file: []const u8) ![]u8 {
    const names = try selectionNames(init, select_file);
    defer {
        for (names) |name| init.gpa.free(name);
        init.gpa.free(names);
    }
    init.timings.begin(lowering_phase, false);
    var stats: language.project_compile.Compilation.SelectedStats = .{};
    const generated = try compilation.emitQbeSelected(init.gpa, names, &stats);
    recordLoweredCount(init, stats.lowered_functions);
    setWork(init, .emitted_fragments, stats.emitted_fragments, 0);
    init.timings.end();
    return generated;
}

fn selectionNames(init: Context, path: []const u8) ![]const []const u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 * 1024 * 1024));
    defer init.gpa.free(bytes);
    var names: std.ArrayList([]const u8) = .empty;
    // UNTESTED-ERROR: cleanup on a failed read/append is covered by generic allocator-failure tests; a deterministic partial-read hook does not exist here.
    errdefer {
        for (names.items) |name| init.gpa.free(name);
        names.deinit(init.gpa);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        var duplicate = false;
        for (names.items) |existing| if (std.mem.eql(u8, existing, line)) {
            duplicate = true;
            break;
        };
        if (duplicate) continue;
        try names.append(init.gpa, try init.gpa.dupe(u8, line));
    }
    return names.toOwnedSlice(init.gpa);
}
