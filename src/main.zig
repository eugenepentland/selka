//! Host I/O and process policy stay outside the compiler and VM.
const lowering_phase = "bytecode_lowering";
const inputs_prefix = "--inputs=";
const policy_prefix = "--policy=";
const cache_directory_prefix = "--cache-dir=";
const select_file_prefix = "--select-file=";
/// `lint --profile=NAME` prefix.
const lint_profile_prefix = "--profile=";
/// `lint --against=REF` prefix.
const lint_against_prefix = "--against=";
/// `api-diff --write=FILE` prefix.
const api_write_prefix = "--write=";
/// `context --symbol=NAME` prefix.
const context_symbol_prefix = "--symbol=";
/// `context --at=PATH:LINE:COLUMN` prefix.
const context_at_prefix = "--at=";
/// `context --context-bytes=N` prefix.
const context_bytes_prefix = "--context-bytes=";
/// `context --symbol NAME` spelling, which takes the next argument.
const context_symbol_flag = "--symbol";
/// `context --at PATH:LINE:COLUMN` spelling, which takes the next argument.
const context_at_flag = "--at";
/// `context --context-bytes N` spelling, which takes the next argument.
const context_bytes_flag = "--context-bytes";
/// `context --against FILE` spelling, which takes the next argument.
const context_against_flag = "--against";
/// Wall-clock ceiling forwarded to the guest runtime, which parses the same flag.
const timeout_prefix = "--timeout=";
/// Shared internal session failure name for an over-long request line.
const request_too_long = "RequestTooLong";
/// Phase label and default cache-directory leaf, shared so the literal is not
/// repeated across the timer and the persistent-cache path join.
const frontend_label = "frontend";
/// Located `mylang.json` failure rendering shared by every loading command.
const config_error_format = "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n";
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
    "       mylang invoke <entry.my> --function 'module::name' (--describe | --input=FILE) [--format=json]\n" ++
    "       mylang build <file.my> (-o <output> | --run) [--help]\n" ++
    "       mylang doc-coverage [<repo-root>] (every implemented feature and standard export needs a documented example)\n       mylang " ++
    "doctest [<repo-root>] [--filter GLOB] [--report PATH] [--jobs N] [--verbose] (run every fenced documentation example)\n       mylang " ++
    "reference --query TERM [--format=text|json] (compiler-derived facts from this executable)\n       mylang " ++
    "invoke <entry.my> --function='module::name' (--describe | --input=FILE) (call one exported function natively)\n       mylang " ++
    "<schema-project|input-module|check|run|dump-bytecode|di" ++
    "scover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fm" ++
    "t-module|fmt-project|emit-qbe|emit-project-qbe|list-modules|list-interfaces|list-" ++
    "declarations|check" ++
    "-project|run-project|check-policy> <file.my>\n  schema-project: --schema-report (include " ++
    "checked source and compiler identities)\n  " ++
    "input-module: reads a typed JSON manifest and writes generated " ++
    "module source\n  run: builds the program natively and runs it; it loads the reachable module graph when the entry " ++
    "file opens with a module header or an import/export directive, including a headerless script that imports embedded " ++
    "standard modules, and stays single-unit otherwise; " ++
    "run-project is the explicit project-entry alias\n  run/run-project: unbounded in instructions and frames by default; " ++
    "--max-steps=N and --max-frames=N impose a ceiling and --timeout=SECONDS caps elapsed time; " ++
    "--max-memory=BYTES --gc-stress --print-result --cache-dir=DIR --qbe=PATH --zig=PATH " ++
    "(native objects default to .mylang-cache/qbe, shared with build)\n  " ++
    "run/run-project: --max-memory takes K/M/G suffixes and caps the guest process's address space; " ++
    "MYLANG_MEMORY_LIMIT names the same ceiling and MYLANG_HOST_MEMORY_LIMIT replaces the " ++
    "compiler's own 8G ceiling (0 removes it)\n  " ++
    "run/run-project authority: every capability is granted by default; --restrict denies them " ++
    "and enables --allow-read=DIR --allow-write=DIR --allow-endpoint=IP:PORT (repeatable) " ++
    "--allow-clock --allow-random[=SEED] " ++
    "--allow-env[=NAME,...] --allow-host --allow-all. An endpoint grant is a literal numeric address, " ++
    "never a DNS name. Under --restrict an entry point requesting an ungranted " ++
    "capability exits 2 before execution; --allow-random=SEED pins the seed in either mode\n  " ++
    "run/run-project: -- ends compiler options; every later value is a guest argument\n  " ++
    "run: --timings (native execution nanoseconds on stderr; excludes compilation and linking)\n  " ++
    "schema-project: --inputs=manifest.json (repeat for up to 16 modules)\n  " ++
    "discover-duplicates/discover-project-duplicates: --min-nodes=N " ++
    "--population=production|tests|generated|reference|intentional --timings --approximate " ++
    "--max-work=N\n  report-quality/report-project-quality: --max-function-lines=N " ++
    "--max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a " ++
    "signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  " ++
    "lint: --gate --accept --json --profile=agent|strict|safety --against=REF (blocking findings exit 3)\n  " ++
    "tests-for: <entry.my> <qualified-name> lists the tests that reach a declaration\n  " ++
    "api-diff: <entry.my> --write=FILE | --against=FILE [--json] (classified interface changes)\n  " ++
    "context: <entry.my> --symbol=NAME | --at=PATH:LINE:COLUMN [--context-bytes=N] [--format=json] " ++
    "[--against=FILE] (one bounded agent-context-v1 answer about one declaration)\n  " ++
    "fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: " ++
    "--check (otherwise writes formatted source to " ++
    "stdout)\n" ++
    "  list-declarations: parse-only declarations-v1 JSON with byte ranges\n" ++
    "  index-project: JSON symbols, references and pinned source snapshot\n  project-dependencies: checked module graph and hashes; --inputs supported\n" ++
    "  one-shot commands: --timings=json (phase-timings-v1 JSON Lines on stderr)\n" ++
    "  build: --timings=json records the frontend, codegen, link and native phases it already measures for --report\n" ++
    "    --report prints work-report-v1 actual work/reuse plus a frontend-cache-v1 comparison receipt on stderr; --timings=json also adds them; --cache-dir=DIR selects their root; --no-cache disables reuse\n" ++
    "    --explain-invalidation prints an invalidation-report-v1 comparison on stderr for project-dependencies, check-project, run-project and module-syntax run; --no-cache explains against no baseline\n" ++
    "  all commands: --diagnostics=text|json (stderr JSON Lines; stdout unchanged)\n" ++
    "  check/run/run-project: --mutation-markers enables the opt-in call-site `&` marker against `mutates(...)`\n" ++
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
const native_build = @import("qbe_build.zig");
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
    /// Opt-in friction record for this command, or null when neither
    /// `--friction-log` nor `MYLANG_FRICTION_LOG` asked for one. Every write is
    /// best effort: a failure drops information rather than failing the command.
    friction: ?*language.friction_log.Recorder = null,
    fn text(self: Context, bytes: []const u8) !void {
        if (self.diagnostics == .text) return std.Io.File.stderr().writeStreamingAll(self.io, bytes);
        const rendered = try diagnostic_output.message(self.gpa, bytes, self.diagnostics);
        defer self.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(self.io, rendered);
    }
};

/// Run one native build. `--timings=json` is an observation request the driver
/// answers with its measured phase durations, so this command records them
/// through the same `phase-timings-v1` writer `run` and `run-project` use and
/// the JSON Lines shape cannot drift between commands. A build that named no
/// such request takes the driver path unchanged and records nothing.
fn buildCommand(process: std.process.Init, args: []const []const u8) !u8 {
    const asked = native_options.timingsJson(args);
    var timings = language.timings.Profile.init(process.io, asked, .compiler);
    var phases: native_build.PhaseTimings = .{};
    const status = try native_build.runMeasured(process, args, if (asked) &phases else null);
    addBuildPhases(&timings, phases);
    try timings.report(status);
    return status;
}

/// Record each phase a native build actually measured. A phase that never ran
/// stays absent rather than reporting a zero it did not observe.
fn addBuildPhases(timings: *language.timings.Profile, phases: native_build.PhaseTimings) void {
    const names = [_][]const u8{ "frontend", "codegen", "link", "native" };
    const seconds = [_]?f64{ phases.frontend, phases.codegen, phases.link, phases.native };
    for (names, seconds) |name, measured| {
        if (measured) |value| timings.add(name, @intFromFloat(@max(0, value) * std.time.ns_per_s), false);
    }
}
fn dispatch(process: std.process.Init) !u8 {
    const args = try process.minimal.args.toSlice(process.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--features")) {
        try featureReport(process);
        return 0;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return buildCommand(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "emit-runtime")) return @import("qbe_build.zig").emitRuntime(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "test")) return @import("native_test_command.zig").run(process, args[2..]) catch |err| switch (err) {
        // `run` already rendered the child compiler's located diagnostic; exit 1
        // rather than wrapping it in the generic "host failure" line.
        error.SourceRejected => 1,
        else => |problem| return problem,
    };
    if (args.len >= 2 and std.mem.eql(u8, args[1], "invoke")) return @import("invoke_command.zig").run(process, args[2..]) catch |err| switch (err) {
        // `run` already published a `native-invocation-v1` refusal when it could;
        // a check that failed before that still rendered its own diagnostic.
        error.SourceRejected => 1,
        else => |problem| return problem,
    };
    if (args.len >= 2 and std.mem.eql(u8, args[1], "bench-promote")) return @import("native_bench_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "doc-coverage")) return @import("doc_coverage_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "doctest")) return @import("doctest_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "reference")) return @import("reference_command.zig").run(@import("mylang"), process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "invoke")) return @import("invoke_command.zig").run(process, args[2..]);
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
    // One optional record per command, built before any work so the wall time it
    // carries covers the whole command. `init` returns null unless the flag or
    // `MYLANG_FRICTION_LOG` asked for a log, so an ordinary run pays one check.
    var friction_storage: language.friction_log.Recorder = undefined;
    const friction = startFriction(init, parsed, &friction_storage);
    const friction_start = if (friction != null) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    defer if (friction) |recorder| recorder.deinit();
    var frontend_cache = openFrontendCache(init, parsed);
    var semantic_store = openSemanticStore(init, parsed);
    var observation: RunObservation = .{ .executed = executedStages(parsed.command) };
    observation.work.command = @tagName(parsed.command);
    var command_init = init;
    command_init.observation = &observation;
    command_init.friction = friction;
    var with_frontend = parsed;
    with_frontend.frontend = if (frontend_cache) |*cache| cache else null;
    with_frontend.semantic = if (semantic_store) |*store| store else null;
    const status = runCommand(command_init, with_frontend) catch |err| {
        best_effort: {
            reportMeasured(init, parsed, if (frontend_cache) |*cache| cache else null, &observation) catch break :best_effort;
        }
        if (frontend_cache) |*cache| cache.deinit();
        if (semantic_store) |*store| store.deinit();
        if (friction) |recorder| recorder.finish(2, frictionElapsedNs(friction_start, init.io));
        return err;
    };
    try reportMeasured(init, parsed, if (frontend_cache) |*cache| cache else null, &observation);
    if (frontend_cache) |*cache| cache.deinit();
    if (semantic_store) |*store| store.deinit();
    if (friction) |recorder| recorder.finish(status, frictionElapsedNs(friction_start, init.io));
    return status;
}

/// Start this command's friction record, or return null when no log was asked
/// for. The compiler identity and the entry file's snapshot digest come from the
/// same receipt machinery every other command receipt uses, so a record names
/// exactly the build and the source it judged. A failed identity, allocation or
/// read leaves the destination null: logging never fails the command.
fn startFriction(init: Context, parsed: Parsed, storage: *language.friction_log.Recorder) ?*language.friction_log.Recorder {
    if (parsed.friction_path == null and init.environ.get(language.friction_log.variable) == null) return null;
    const identity = compilerIdentity(init.io) catch return null;
    const compiler = language.source_receipt.implementation(init.gpa, identity) catch return null;
    storage.* = language.friction_log.Recorder.init(init.gpa, init.io, init.environ, .{
        .flag = parsed.friction_path,
        .command = @tagName(parsed.command),
        .path = parsed.path,
        .snapshot = entrySnapshot(init, parsed.path),
        .compiler = compiler,
    }) orelse return null;
    return storage;
}

/// The command's elapsed monotonic nanoseconds, clamped at zero so a clock that
/// never steps backwards still cannot produce a negative duration.
fn frictionElapsedNs(start: std.Io.Timestamp, io: std.Io) u64 {
    const nanoseconds = start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
    return @intCast(@max(nanoseconds, 0));
}

/// Lowercase SHA-256 of the entry file as the command was given it, or the empty
/// string when it cannot be read. Only the digest is ever recorded, never bytes.
fn entrySnapshot(init: Context, path: []const u8) []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 * 1024 * 1024)) catch return "";
    defer init.gpa.free(bytes);
    return language.friction_log.snapshotHex(init.gpa, bytes) catch "";
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
        .lint,
        .@"tests-for",
        .@"api-diff",
        .context,
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
    const unit_deny_warnings = validateUnitConfiguredPolicy(init, parsed) catch |err| return policyFailureStatus(err);
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
    compilation.src.mutation_markers = parsed.mutation_markers;
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
    if (unit_deny_warnings and deniesOneShotWarnings(parsed.command) and hasWarning(compilation.diagnostics.items)) return 1;
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
        .lint,
        .@"tests-for",
        .@"api-diff",
        .context,
        .@"discover-project-duplicates",
        .@"report-project-quality",
        => unreachable,
        .@"emit-qbe" => {
            const generated = emitMeasuredNative(init, &compilation, parsed.drop_debug, !parsed.drop_step_checks, !parsed.drop_frame_checks) catch |err| switch (err) {
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
    const manifest = emitMeasuredNative(init, compilation, false, parsed.saw_steps, parsed.saw_frames) catch |err| switch (err) {
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
        if (init.friction) |recorder| recorder.addDiagnostic(diagnostic);
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
    lint,
    @"tests-for",
    @"api-diff",
    context,
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

/// Which `context` selector a space-separated flag is waiting for.
const ContextSelectorField = enum { symbol, at };

/// `mylang context` selection and budget. Grouped so `Parsed` gains one field
/// rather than four, and shared with the parser that validates the switches.
const ContextOptions = struct {
    /// `--symbol=NAME`: the module-qualified declaration to describe.
    symbol: ?[]const u8 = null,
    /// `--at=PATH:LINE:COLUMN`: the one-based position to describe.
    at: ?[]const u8 = null,
    /// `--context-bytes=N`: total response budget, metadata included.
    bytes: usize = language.context.default_context_bytes,
    /// `--against=FILE`: an `api-diff` baseline to classify the selection against.
    against: ?[]const u8 = null,
};

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
    /// `lint` switches; ignored by every other command.
    lint: language.lint.Options,
    /// `tests-for` subject: the qualified declaration name to query.
    subject: ?[]const u8,
    /// `context` selector, budget and optional baseline.
    context: ContextOptions,
    /// `api-diff` baseline to compare against, or the path to write.
    api_against: ?[]const u8,
    api_write: ?[]const u8,
    api_json: bool,
    max_memory: ?u64,
    /// Internal selective native emission input; one qualified function per line.
    select_file: ?[]const u8,
    /// Internal `--drop-debug`: a ReleaseFast build omits `debug` lines.
    drop_debug: bool,
    /// Internal `--drop-step-checks`: this build carries no instruction ceiling.
    drop_step_checks: bool,
    /// Internal `--drop-frame-checks`: this build carries no call-depth ceiling.
    drop_frame_checks: bool,
    /// True when the command was asked for a runtime instruction ceiling, so the
    /// program it compiles must carry the accounting that enforces it.
    saw_steps: bool,
    /// True when the command was asked for a runtime frame ceiling, so the program
    /// it compiles must carry the depth accounting that enforces it.
    saw_frames: bool,
    /// Opt-in D3 experiment: accept and enforce call-site `&` mutation markers.
    mutation_markers: bool,
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
    /// `--friction-log=PATH` as typed, or null when the flag was not passed.
    /// `MYLANG_FRICTION_LOG` names the same destination when the flag is absent.
    friction_path: ?[]const u8 = null,
};
fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) ArgError!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var parser: ArgumentParser = .{ .command = command, .allocator = allocator };
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
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
        if (try parseSwitchFlag(arg, &parser)) continue;
        if (try parseFrictionFlag(arg, &parser)) continue;
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
        // `context` also accepts its `--flag value` spelling, which consumes the
        // next argument; every other flag keeps the `--flag=value` form.
        if (try parser.contextSeparateValue(args, &index)) continue;
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
    lint: language.lint.Options = .{},
    subject: ?[]const u8 = null,
    context_symbol: ?[]const u8 = null,
    context_at: ?[]const u8 = null,
    /// The `context` selector whose value is the next argument, for the
    /// `--symbol NAME` spelling the documented usage writes with a space.
    context_pending: ?ContextSelectorField = null,
    context_bytes: usize = language.context.default_context_bytes,
    context_against: ?[]const u8 = null,
    api_against: ?[]const u8 = null,
    api_write: ?[]const u8 = null,
    api_json: bool = false,
    no_cache: bool = false,
    friction_path: ?[]const u8 = null,
    mutation_markers: bool = false,
    cache_dir: ?[]const u8 = null,
    select_file: ?[]const u8 = null,
    drop_debug: bool = false,
    drop_step_checks: bool = false,
    drop_frame_checks: bool = false,
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

    /// A `tests-for` subject is its second positional argument; the first is
    /// the entry file. Any other command rejects a second positional.
    fn subjectOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .@"tests-for" or self.subject != null) return false;
        if (self.path == null or std.mem.startsWith(u8, arg, "-")) return false;
        self.subject = arg;
        return true;
    }

    fn surfaceOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (try self.subjectOption(arg)) return true;
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
            self.native.codegen = .{ .qbe = try self.value(arg, "--qbe=") };
        } else if (std.mem.startsWith(u8, arg, "--zig=")) {
            self.native.zig = try self.value(arg, "--zig=");
        } else if (std.mem.startsWith(u8, arg, select_file_prefix)) {
            if (self.command != .@"emit-project-qbe" or self.select_file != null or arg.len == select_file_prefix.len) return error.Usage;
            self.select_file = arg[select_file_prefix.len..];
        } else if (std.mem.eql(u8, arg, "--drop-debug")) {
            if ((self.command != .@"emit-qbe" and self.command != .@"emit-project-qbe") or self.drop_debug) return error.Usage;
            self.drop_debug = true;
        } else if (std.mem.eql(u8, arg, "--drop-step-checks")) {
            if ((self.command != .@"emit-qbe" and self.command != .@"emit-project-qbe") or self.drop_step_checks) return error.Usage;
            self.drop_step_checks = true;
        } else if (std.mem.eql(u8, arg, "--drop-frame-checks")) {
            if ((self.command != .@"emit-qbe" and self.command != .@"emit-project-qbe") or self.drop_frame_checks) return error.Usage;
            self.drop_frame_checks = true;
        } else return false;
        return true;
    }

    fn discoveryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (try self.lintOption(arg)) return true;
        if (try self.apiDiffOption(arg)) return true;
        if (try self.contextOption(arg)) return true;
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

    /// `lint` switches: `--gate`, `--accept`, `--json`, `--profile=NAME` and
    /// `--against=REF`. Only `lint` accepts them; a repeat is a usage error.
    fn lintOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .lint) return false;
        if (std.mem.eql(u8, arg, "--gate")) {
            if (self.lint.gate) return error.Usage;
            self.lint.gate = true;
        } else if (std.mem.eql(u8, arg, "--accept")) {
            if (self.lint.accept) return error.Usage;
            self.lint.accept = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            if (self.lint.json) return error.Usage;
            self.lint.json = true;
        } else if (std.mem.startsWith(u8, arg, lint_profile_prefix)) {
            if (self.lint.profile != null or arg.len == lint_profile_prefix.len) return error.Usage;
            self.lint.profile = std.meta.stringToEnum(language.lint_config.Profile, arg[lint_profile_prefix.len..]) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, lint_against_prefix)) {
            if (self.lint.against != null or arg.len == lint_against_prefix.len) return error.Usage;
            self.lint.against = arg[lint_against_prefix.len..];
        } else return false;
        return true;
    }
    /// `api-diff` switches: exactly one of `--write=FILE` or `--against=FILE`,
    /// plus an optional `--json`.
    fn apiDiffOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .@"api-diff") return false;
        if (std.mem.startsWith(u8, arg, api_write_prefix)) {
            if (self.api_write != null or arg.len == api_write_prefix.len) return error.Usage;
            self.api_write = arg[api_write_prefix.len..];
        } else if (std.mem.startsWith(u8, arg, lint_against_prefix)) {
            if (self.api_against != null or arg.len == lint_against_prefix.len) return error.Usage;
            self.api_against = arg[lint_against_prefix.len..];
        } else if (std.mem.eql(u8, arg, "--json")) {
            if (self.api_json) return error.Usage;
            self.api_json = true;
        } else return false;
        return true;
    }

    /// `context` switches, in both `--flag=value` and `--flag value` spellings:
    /// exactly one of `--symbol=NAME` or `--at=PATH:LINE:COLUMN`, an optional
    /// total byte budget, and an optional `api-diff` baseline. `--format`
    /// accepts only the JSON the command publishes today, so an unsupported
    /// format is a usage error rather than a silently different rendering.
    fn contextOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .context) return false;
        if (std.mem.startsWith(u8, arg, context_symbol_prefix)) {
            return contextValue(&self.context_symbol, arg[context_symbol_prefix.len..]);
        } else if (std.mem.startsWith(u8, arg, context_at_prefix)) {
            return contextValue(&self.context_at, arg[context_at_prefix.len..]);
        } else if (std.mem.startsWith(u8, arg, context_bytes_prefix)) {
            return self.setContextBytes(arg[context_bytes_prefix.len..]);
        } else if (std.mem.startsWith(u8, arg, lint_against_prefix)) {
            return contextValue(&self.context_against, arg[lint_against_prefix.len..]);
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            if (!std.mem.eql(u8, arg["--format=".len..], "json")) return error.Usage;
        } else return false;
        return true;
    }

    /// Store one `context` selector or baseline value; a repeat or an empty
    /// value is a usage error.
    fn contextValue(slot: *?[]const u8, text: []const u8) error{Usage}!bool {
        if (text.len == 0 or slot.* != null) return error.Usage;
        slot.* = text;
        return true;
    }

    /// The `--context-bytes` value: a decimal count at or above the documented
    /// minimum.
    fn setContextBytes(self: *ArgumentParser, text: []const u8) error{Usage}!bool {
        const requested = std.fmt.parseInt(usize, text, 10) catch return error.Usage;
        if (requested < language.context.minimum_context_bytes) return error.Usage;
        self.context_bytes = requested;
        return true;
    }

    /// Consume the value that follows a `context` switch written with a space
    /// instead of `=`. Returns false when `args[index.*]` is not one of those
    /// switches, so the caller keeps parsing it as an ordinary argument, and
    /// reports usage when the switch has no value left to take.
    fn contextSeparateValue(self: *ArgumentParser, args: []const []const u8, index: *usize) error{Usage}!bool {
        const flag = args[index.*];
        const which: enum { symbol, at, bytes, against } = if (std.mem.eql(u8, flag, context_symbol_flag))
            .symbol
        else if (std.mem.eql(u8, flag, context_at_flag))
            .at
        else if (std.mem.eql(u8, flag, context_bytes_flag))
            .bytes
        else if (std.mem.eql(u8, flag, context_against_flag))
            .against
        else
            return false;
        if (self.command != .context or index.* + 1 >= args.len) return error.Usage;
        index.* += 1;
        const text = args[index.*];
        return switch (which) {
            .symbol => contextValue(&self.context_symbol, text),
            .at => contextValue(&self.context_at, text),
            .bytes => self.setContextBytes(text),
            .against => contextValue(&self.context_against, text),
        };
    }

    fn finish(self: *ArgumentParser) ArgError!Parsed {
        if (self.saw_work and !self.discovery.approximate) return error.Usage;
        if (self.command == .@"fmt-project" and !self.format_check) return error.Usage;
        if (self.command == .@"check-policy" and self.policy == null) return error.Usage;
        if (self.command == .@"tests-for" and self.subject == null) return error.Usage;
        if (self.command == .@"api-diff" and (self.api_against == null) == (self.api_write == null)) return error.Usage;
        if (self.command == .context and (self.context_symbol == null) == (self.context_at == null)) return error.Usage;
        if (self.context_pending != null) return error.Usage;
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
            .lint = self.lint,
            .subject = self.subject,
            .context = .{
                .symbol = self.context_symbol,
                .at = self.context_at,
                .bytes = self.context_bytes,
                .against = self.context_against,
            },
            .api_against = self.api_against,
            .api_write = self.api_write,
            .api_json = self.api_json,
            .max_memory = self.max_memory,
            .no_cache = self.no_cache,
            .mutation_markers = self.mutation_markers,
            .cache_dir = self.cache_dir,
            .select_file = self.select_file,
            .drop_debug = self.drop_debug,
            .drop_step_checks = self.drop_step_checks,
            .drop_frame_checks = self.drop_frame_checks,
            .saw_steps = self.saw_steps,
            .saw_frames = self.saw_frames,
            .friction_path = self.friction_path,
        };
    }
};

/// Consume the value-less switches that may appear at most once: `--no-cache`
/// and `--mutation-markers`. A repeat is a usage error; an argument that is
/// neither is left for the caller's other branches.
fn parseSwitchFlag(arg: []const u8, parser: *ArgumentParser) ArgError!bool {
    if (std.mem.eql(u8, arg, "--no-cache")) {
        if (parser.no_cache) return error.Usage;
        parser.no_cache = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--mutation-markers")) {
        if (parser.mutation_markers) return error.Usage;
        parser.mutation_markers = true;
        return true;
    }
    return false;
}

/// Consume `--friction-log=PATH`, the opt-in friction destination for this
/// command. A repeated or empty destination is a usage error; an argument that
/// is not this flag is left for the caller's other branches.
fn parseFrictionFlag(arg: []const u8, parser: *ArgumentParser) ArgError!bool {
    if (!std.mem.startsWith(u8, arg, "--friction-log=")) return false;
    if (parser.friction_path != null) return error.Usage;
    const destination_path = arg["--friction-log=".len..];
    if (destination_path.len == 0) return error.Usage;
    parser.friction_path = destination_path;
    return true;
}

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
/// Returns whether the project asks for `lint.warnings: "deny"`, which makes a
/// `W_*` diagnostic rejecting in the inner loop.
fn validateUnitConfiguredPolicy(init: Context, parsed: Parsed) !bool {
    const config_path = project_config.discover(init.gpa, init.io, parsed.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try init.text("mylang: cannot inspect the entry directory for mylang.json\n");
        return error.HostConfiguration;
    } orelse return false;
    defer init.gpa.free(config_path);
    var failure: project_config.Failure = .{};
    var config = project_config.load(init.gpa, init.io, config_path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(init.gpa, config_error_format, .{
                failure.path, failure.location.line, failure.location.column, failure.detail,
            });
            defer init.gpa.free(message);
            try init.text(message);
            return error.HostConfiguration;
        },
    };
    defer config.deinit();
    const policy_file = config.policy orelse {
        const denied = try configWarningsDeny(init, &config);
        return denied;
    };
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
    const denied = try configWarningsDeny(init, &config);
    return denied;
}

/// Whether a loaded configuration sets `lint.warnings: "deny"`. A malformed
/// `lint` object leaves enforcement off here; `mylang lint` is what reports it.
fn configWarningsDeny(init: Context, config: *const project_config.Config) !bool {
    if (!config.document.lint) return false;
    var failure: language.lint_config.Failure = .{};
    var parsed_lint = language.lint_config.parseConfig(init.gpa, config.bytes, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    defer parsed_lint.deinit(init.gpa);
    return parsed_lint.warnings == .deny;
}

/// Commands whose inner loop a `warnings: "deny"` project makes rejecting.
fn deniesOneShotWarnings(command: Command) bool {
    return command == .check or command == .run;
}

/// Finish a `check-project` run: refuse an opted-in `warnings: "deny"` project
/// whose checked program has a warning, otherwise remember the green verdict.
/// The diagnostics were already printed by the caller.
fn finishCheckProject(
    init: Context,
    project: *language.project.Project,
    compilation: *language.project_compile.Compilation,
    verdict: ?*language.check_cache.Cache,
    frontend: ?*language.frontend_cache.Cache,
    configured: *const ConfiguredPolicy,
) !u8 {
    if (try projectWarningsDenied(init, compilation, configured)) return 1;
    try rememberFrontendVerdict(init, .@"check-project", project, compilation, frontend);
    return rememberCheck(verdict, project, compilation);
}

/// Whether an opted-in `warnings: "deny"` project makes this checked program
/// rejecting. The caller has already reported the diagnostics.
fn projectWarningsDenied(init: Context, compilation: *language.project_compile.Compilation, configured: *const ConfiguredPolicy) !bool {
    const denied = try configuredWarningsDeny(init, configured);
    if (!denied) return false;
    return hasWarning(compilation.diagnostics.items.items);
}

/// Extract the effective warnings policy from a loaded project configuration.
fn configuredWarningsDeny(init: Context, configured: *const ConfiguredPolicy) !bool {
    const config = if (configured.config) |*value| value else return false;
    return configWarningsDeny(init, config);
}

/// Whether any collected diagnostic is a warning.
fn hasWarning(items: []const language.diagnostic.Diagnostic) bool {
    for (items) |item| if (item.severity == .warning) return true;
    return false;
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
            const message = try std.fmt.allocPrint(init.gpa, config_error_format, .{
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
        // A lint-only configuration still changes acceptance, so its identity
        // must reach the verdict caches; otherwise a green cached under one
        // rule mode could replay under another.
        var identity: [64]u8 = undefined;
        const has_identity = config.cacheIdentity(&identity);
        setPolicyIdentity(frontend, verdict, if (has_identity) identity[0..] else null);
        config_transferred = true;
        return .{ .config = config, .identity = if (has_identity) identity else null };
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

/// Run `mylang lint` over the checked project. Compiler warnings are reported
/// first so one run shows both families; lint findings follow on stderr and the
/// one-line summary on stdout.
fn lintProject(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, configured: *const ConfiguredPolicy) !u8 {
    try reportProject(init, compilation);
    var parsed_lint: ?language.lint_config.Config = null;
    defer if (parsed_lint) |*value| value.deinit(init.gpa);
    if (configured.config) |*config| {
        if (config.document.lint) {
            var failure: language.lint_config.Failure = .{};
            parsed_lint = language.lint_config.parseConfig(init.gpa, config.bytes, &failure) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    const message = try std.fmt.allocPrint(init.gpa, config_error_format, .{
                        config.path, failure.line, failure.column, failure.detail,
                    });
                    defer init.gpa.free(message);
                    try init.text(message);
                    return 2;
                },
            };
        }
    }
    const settings: ?*const language.lint_config.Config = if (parsed_lint) |*value| value else null;
    return language.lint.run(.{
        .memory = init.gpa,
        .io = init.io,
        .compilation = compilation,
        .config = settings,
        .entry_path = parsed.path,
        .options = parsed.lint,
        .diagnostics = init.diagnostics,
    });
}

/// Print the discovered tests that reach one qualified declaration.
fn testsFor(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation) !u8 {
    const subject = parsed.subject orelse return 2;
    const rendered = (language.navigation.renderTestsFor(init.gpa, compilation, subject) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    }) orelse {
        try init.text("tests-for: no checked declaration has that qualified name\n");
        return 2;
    };
    defer init.gpa.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
    return 0;
}

/// `api-diff`: write a baseline snapshot, or classify the current project
/// against one. A malformed or unreadable baseline is a usage failure (2).
fn apiDiff(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation) !u8 {
    if (parsed.api_write) |path| {
        const bytes = language.api_diff.snapshot(init.gpa, compilation) catch |err| return apiDiffError(init, err);
        defer init.gpa.free(bytes);
        std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes }) catch return 2;
        return 0;
    }
    const against = parsed.api_against orelse return 2;
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, against, init.gpa, .limited(64 * 1024 * 1024)) catch return 2;
    defer init.gpa.free(bytes);
    const baseline = language.api_diff.parseBaseline(init.gpa, bytes) catch |err| return apiDiffError(init, err);
    defer language.api_diff.freeEntries(init.gpa, baseline);
    const diff_report = language.api_diff.compare(init.gpa, baseline, compilation) catch |err| return apiDiffError(init, err);
    defer language.api_diff.freeChanges(init.gpa, diff_report);
    const rendered = language.api_diff.render(init.gpa, diff_report, parsed.api_json) catch |err| return apiDiffError(init, err);
    defer init.gpa.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
    return 0;
}

/// Map an api-diff failure to a status: allocation propagates, everything else
/// is a usage or baseline failure.
fn apiDiffError(init: Context, err: language.api_diff.Error) !u8 {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try init.text("api-diff: cannot read or classify the baseline\n");
            return 2;
        },
    }
}

/// What one failed body check means for the command that asked for it. A gate
/// reports the diagnostics and stops; `context` keeps going with the
/// declarations it recovered, so the caller learns why the relationships it
/// cannot see are missing instead of seeing nothing at all.
fn checkFailure(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, inputs: []const GeneratedInput) !?u8 {
    try reportProject(init, compilation);
    if (parsed.command == .context) return null;
    if (parsed.reporting.explain_invalidation) try reportFailedInvalidation(init, parsed, compilation, inputs);
    return 1;
}

/// The selector `finish` already proved is present: exactly one of `--symbol`
/// and `--at` survives parsing, so the unwrap cannot observe a usage error.
fn contextSelector(parsed: Parsed) language.context.Selector {
    return if (parsed.context.symbol) |name| .{ .symbol = name } else .{ .at = parsed.context.at.? };
}

/// `context`: one bounded `agent-context-v1` answer about one declaration. A
/// compilation that did not check still answers — `unavailable` carries the
/// reason the resolved relationships are missing. The answer goes to stdout
/// alone so it stays parseable; diagnostics keep going to stderr. The files are
/// re-read through the provider the project was loaded from before the answer is
/// published, so a source that changed while it was assembled is rejected
/// instead of contributing facts from two versions.
/// An unreadable `--against` file is a usage-level failure: the request named a
/// baseline this process cannot read, so no answer can be classified against it.
fn baselineFailure(init: Context) !u8 {
    try init.text("context: cannot read or classify the baseline\n");
    return 2;
}

fn contextCommand(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, unavailable: ?[]const u8, files: *ModuleFiles) !u8 {
    var request = contextOptions(init, parsed, files) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BaselineUnreadable => return baselineFailure(init),
    };
    defer request.release(init.gpa);
    request.options.unavailable_reason = unavailable;
    const answer = language.context.render(init.gpa, compilation, try compilerIdentity(init.io), request.options) catch |err| return contextError(init, err);
    const status = try emitContext(init, answer);
    return status;
}

/// `context` when body syntax failed before any declaration merged: the lexical
/// candidates answer names its selector and publishes no resolved relationship.
fn contextPartial(init: Context, parsed: Parsed, project: *language.project.Project, files: ?*ModuleFiles) !u8 {
    var request = contextOptions(init, parsed, files) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BaselineUnreadable => return baselineFailure(init),
    };
    defer request.release(init.gpa);
    request.options.unavailable_reason = "body syntax failed; only lexical top-level candidates were recovered";
    const answer = language.context.renderPartial(init.gpa, project, try compilerIdentity(init.io), request.options) catch |err| return contextError(init, err);
    const status = try emitContext(init, answer);
    return status;
}

/// The baseline bytes a `--against` request needs, kept beside the options so
/// the caller can release them once the answer is rendered.
const ContextRequest = struct {
    options: language.context.Options,
    baseline_bytes: ?[]u8 = null,

    fn release(self: ContextRequest, allocator: std.mem.Allocator) void {
        if (self.baseline_bytes) |owned| allocator.free(owned);
    }
};

fn contextOptions(init: Context, parsed: Parsed, files: ?*ModuleFiles) error{ OutOfMemory, BaselineUnreadable }!ContextRequest {
    var request: ContextRequest = .{
        .options = .{
            .entry = parsed.path,
            .selector = contextSelector(parsed),
            .context_bytes = parsed.context.bytes,
            // The provider the project was loaded from, so the answer re-reads the
            // same files before it is published. `null` when the caller had none:
            // the answer is then confirmed only against the bytes it holds.
            .sources = if (files) |provider| .{ .context = provider, .read = ModuleFiles.read } else null,
        },
    };
    const path = parsed.context.against orelse return request;
    const loaded = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(64 * 1024 * 1024)) catch return error.BaselineUnreadable;
    request.baseline_bytes = loaded;
    request.options.baseline = .{ .path = path, .bytes = loaded };
    return request;
}

fn emitContext(init: Context, answer: language.context.Answer) !u8 {
    defer init.gpa.free(answer.bytes);
    try std.Io.File.stdout().writeStreamingAll(init.io, answer.bytes);
    return switch (answer.status) {
        .ok, .partial => 0,
        else => 2,
    };
}

/// Map a context failure to a status: allocation propagates, a rejected budget,
/// an unreadable baseline or an unconfirmable source snapshot is a usage
/// failure, and anything else is internal.
fn contextError(init: Context, err: language.context.Error) !u8 {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BudgetTooSmall => {
            try init.text("context: --context-bytes is below the documented minimum\n");
            return 2;
        },
        error.InvalidBaseline => {
            try init.text("context: cannot read or classify the baseline\n");
            return 2;
        },
        error.RecheckUnavailable => {
            try init.text("context: cannot re-read every source to confirm the answer\n");
            return 2;
        },
        else => return error.InternalError,
    }
}

/// Entry module name and import root for one project command. A standalone
/// `*_test.my` under a subdirectory resolves both from its enclosing project
/// root, so `tests/parser_test.my` is module `tests.parser_test`; `owned` holds
/// the slices to release once the command has loaded its graph.
const EntryLocation = struct {
    root: []const u8,
    name: []const u8,
    owned: ?project_config.TestEntry = null,
    fn deinit(self: EntryLocation, allocator: std.mem.Allocator) void {
        if (self.owned) |location| {
            allocator.free(location.root);
            allocator.free(location.relative);
            allocator.free(location.name);
        }
    }
};

fn entryLocation(init: Context, path: []const u8) !EntryLocation {
    if (try project_config.testEntryLocation(init.gpa, init.io, path)) |location| {
        return .{ .root = location.root, .name = location.name, .owned = location };
    }
    const basename = std.fs.path.basename(path);
    return .{ .root = std.fs.path.dirname(path) orelse ".", .name = basename[0 .. basename.len - 3] };
}

/// The stages a receipt pass actually executes. Selective emission lowers only
/// its closure, while an ordinary project run defers lowering until after its
/// manifest-cache lookup. Invalidation explanation still requests the complete
/// fragment receipt it compares.
fn receiptStages(parsed: Parsed, executed: [std.meta.tags(invalidation.Stage).len]bool) [std.meta.tags(invalidation.Stage).len]bool {
    var stages = executed;
    const deferred_project_run = parsed.command == .@"run-project" and !parsed.reporting.explain_invalidation;
    if ((parsed.command == .@"emit-project-qbe" and parsed.select_file != null) or deferred_project_run) {
        stages[@backingInt(invalidation.Stage.lower_function)] = false;
        stages[@backingInt(invalidation.Stage.emit_fragment)] = false;
    }
    return stages;
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
    const location = try entryLocation(init, path);
    defer location.deinit(init.gpa);
    var files: ModuleFiles = .{ .io = init.io, .root = location.root };
    files.inputs = (try prepareInputs(init, parsed, location.name)) orelse return 2;
    var project = language.project.Project.init(init.gpa);
    defer project.deinit();
    if (try loadModules(init, &project, &files, location.name, try projectLimits(init, parsed))) |status| return status;
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
        var index = (try buildIndex(init, &project, cache, frontend)) orelse return partialNavigation(init, &project, parsed, &files);
        init.timings.begin("source_merge", false);
        var compilation = try language.project_compile.Compilation.init(&index);
        init.timings.end();
        if (parsed.command == .@"index-project") break :result try renderNavigation(init, &compilation, functions);
        const semantic_before = if (functions) |f| f.statistics else null;
        // `context` answers about a project that does not check: it publishes the
        // declarations and diagnostics it did recover and names the reason the
        // resolved relationships are missing, rather than failing like a gate.
        var unchecked_reason: ?[]const u8 = null;
        compilation.checkWithCache(functions) catch |err| switch (err) {
            error.SourceError => {
                recordCheckWork(init, functions, semantic_before, compilation.program);
                if (try checkFailure(init, parsed, &compilation, files.inputs)) |status| return status;
                unchecked_reason = "bodies did not check; declarations and diagnostics only";
            },
            else => return err,
        };
        recordCheckWork(init, functions, semantic_before, compilation.program);
        if (parsed.command == .context) return contextCommand(init, parsed, &compilation, unchecked_reason, &files);
        init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
        init.timings.counts.typed_nodes = compilation.program.?.nodes.len + compilation.program.?.statements.len;
        // The internal native-test compile session keeps this one checked
        // compilation alive and serves facts plus selective lowering from it, so
        // a provider graph is never checked again just to emit its closure.
        switch (parsed.command) {
            .lint => return lintProject(init, parsed, &compilation, &configured),
            .@"tests-for" => return testsFor(init, parsed, &compilation),
            .@"api-diff" => return apiDiff(init, parsed, &compilation),
            .@"native-test-compile" => return nativeTestCompileSession(init, &compilation),
            else => {},
        }
        const executed = executedStages(parsed.command);
        // A selective `emit-project-qbe --select-file` lowers only its closure in
        // the emission helper; the whole-project receipt pass must not lower first.
        const receipt_stages = receiptStages(parsed, executed);
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
        if (parsed.command == .@"check-project") return finishCheckProject(init, &project, &compilation, verdict, frontend, &configured);
        if (parsed.command == .@"discover-project-duplicates") return discoverProject(init, parsed, &project, &compilation, frontend_start);
        if (parsed.command == .@"check-policy") return checkProjectPolicy(init, parsed, &project);
        return runProjectProgram(init, &compilation, parsed, &configured);
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
fn runProjectProgram(init: Context, compilation: *language.project_compile.Compilation, parsed: Parsed, configured: *const ConfiguredPolicy) !u8 {
    if (grants.ungranted(compilation.program.?, parsed.grants)) |flag| return reportUngranted(init, flag);
    if (try projectWarningsDenied(init, compilation, configured)) return 1;
    const sources = try init.gpa.alloc(native_run.manifest_cache.Source, compilation.src.origins.len);
    defer init.gpa.free(sources);
    for (compilation.src.origins, sources) |origin, *source| source.* = .{ .path = origin.original.path, .bytes = origin.original.bytes };
    const identity: native_run.manifest_cache.Identity = .{
        .sources = sources,
        .policy = if (configured.identity) |*value| value else null,
        .mutation_markers = parsed.mutation_markers,
        .step_checks = parsed.saw_steps,
    };
    if (!parsed.no_cache) {
        if (try native_run.manifest_cache.load(init.gpa, init.io, init.environ, parsed.native, identity)) |entry| {
            defer init.gpa.free(entry.manifest);
            // `--explain-invalidation` deliberately lowered above to construct
            // its complete fragment receipt. Preserve that observed work while
            // still recording that QBE emission itself was reused.
            if (compilation.code == null) setWork(init, .lowered_functions, 0, entry.fragments);
            setWork(init, .emitted_fragments, 0, entry.fragments);
            return runNative(init, parsed, entry.manifest);
        }
    }
    const manifest = emitMeasuredNative(init, compilation, false, parsed.saw_steps, true) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return 1;
        },
        else => return err,
    };
    defer init.gpa.free(manifest);
    if (!parsed.no_cache) native_run.manifest_cache.store(init.gpa, init.io, init.environ, parsed.native, identity, manifest) catch return runNative(init, parsed, manifest);
    return runNative(init, parsed, manifest);
}

fn emitProjectNative(init: Context, compilation: *language.project_compile.Compilation, select_file: ?[]const u8, drop_debug: bool, step_checks: bool, frame_checks: bool) !?[]u8 {
    const generated = (if (select_file) |path| emitMeasuredSelectedNative(init, compilation, path) else emitMeasuredNative(init, compilation, drop_debug, step_checks, frame_checks)) catch |err| switch (err) {
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
        .@"emit-project-qbe" => (try emitProjectNative(init, compilation, parsed.select_file, parsed.drop_debug, !parsed.drop_step_checks, !parsed.drop_frame_checks)) orelse error.SourceError,
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

fn partialNavigation(init: Context, project: *language.project.Project, parsed: Parsed, files: ?*ModuleFiles) !u8 {
    if (parsed.command == .context) return contextPartial(init, parsed, project, files);
    if (parsed.command != .@"index-project") return 1;
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
    // The marker policy is a compiler option, not a budget; it must survive a
    // missing or unreadable `mylang.json` so `--mutation-markers` still applies.
    var options: language.project.Options = .{ .mutation_markers = parsed.mutation_markers };
    const discovered = project_config.discover(init.gpa, init.io, parsed.path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return options,
    };
    const config_path = discovered orelse return options;
    defer init.gpa.free(config_path);
    var failure: project_config.Failure = .{};
    var config = project_config.load(init.gpa, init.io, config_path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return options,
    };
    defer config.deinit();
    const budgets = config.document.budgets;
    if (budgets.max_modules) |value| options.max_modules = value;
    if (budgets.max_imports) |value| options.max_imports = value;
    if (budgets.max_file_bytes) |value| options.max_file_bytes = value;
    if (budgets.max_total_bytes) |value| options.max_total_bytes = value;
    return options;
}

fn loadModules(init: Context, project: *language.project.Project, files: *ModuleFiles, entry_name: []const u8, options: language.project.Options) !?u8 {
    project.load(.{ .context = files, .read = ModuleFiles.read }, entry_name, options) catch |err| switch (err) {
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
    var index = (try buildIndex(init, project, cache, frontend)) orelse return partialNavigation(init, project, parsed, null);
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
    // Attach checked bodies when they are available so the default listing can
    // publish each function's inferred `effects(...)`. A body that fails to
    // check is ignored: the interface gate lists declarations whether or not
    // bodies type-check, and it never reports body diagnostics.
    var attached: ?language.project_compile.Compilation = language.project_compile.Compilation.init(&index) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => null,
    };
    if (attached) |*compilation| {
        // Body checking may record a project problem; the interface gate owns
        // only declaration diagnostics, so restore the pre-check problem.
        const saved_problem = project.problem;
        compilation.check() catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.SourceError, error.InternalError => {},
        };
        project.problem = saved_problem;
        index.program = compilation.program;
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
        if (init.friction) |recorder| recorder.addDiagnostic(problem);
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
        compilation.src.mutation_markers = src.mutation_markers;
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

fn prepareInputs(init: Context, parsed: Parsed, entry_name: []const u8) !?[]GeneratedInput {
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
        if (std.mem.eql(u8, module, entry_name)) {
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
    // Parsed syntax differs between marker modes, so the flag partitions entries.
    cache.contract.flags = if (parsed.mutation_markers) "mutation-markers" else "";
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
fn semanticCacheContractValue(init: Context, mutation_markers: bool) !language.semantic_cache.Contract {
    const allocator = init.arena.allocator();
    var contract = language.semantic_cache.Contract.default;
    const compiler_hex = std.fmt.bytesToHex(build_identity, .lower);
    contract.compiler_identity = try allocator.dupe(u8, &compiler_hex);
    // A marker-dependent check verdict must not be reused across the flag, even
    // when the source bytes are identical.
    contract.flags = if (mutation_markers) "mutation-markers" else "";
    return contract;
}

fn semanticCacheContract(init: Context, mutation_markers: bool) ![]const u8 {
    const allocator = init.arena.allocator();
    const contract = try semanticCacheContractValue(init, mutation_markers);
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
    const contract = semanticCacheContractValue(init, parsed.mutation_markers) catch return null;
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
    const contract = try semanticCacheContract(init, parsed.mutation_markers);
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
    const contract_fingerprint = try semanticCacheContract(init, parsed.mutation_markers);
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

fn emitMeasuredNative(init: Context, compilation: anytype, drop_debug: bool, step_checks: bool, frame_checks: bool) ![]u8 {
    init.timings.begin(lowering_phase, false);
    try compilation.emitWithOptions(drop_debug);
    if (compilation.code) |code| recordLoweredCount(init, code.functions.len);
    init.timings.begin("native_emission", false);
    const generated = try compilation.emitQbeWithOptions(init.gpa, drop_debug, step_checks, frame_checks);
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
