//! The `selka` command line. Commands that build, run or test code go to the
//! new core (`selka_core`, `src/core/cli.zig`); this file owns the front-end
//! commands: checking, formatting, linting, navigation and project reports.
const selka_core = @import("selka_core");
const inputs_prefix = "--inputs=";
const policy_prefix = "--policy=";
const cache_directory_prefix = "--cache-dir=";
/// `lint --profile=NAME` prefix.
const lint_profile_prefix = "--profile=";
/// `lint --against=REF` prefix.
const lint_against_prefix = "--against=";
/// `lint --rule=NAME` prefix: turn on one rule the profile leaves off.
const lint_rule_prefix = "--rule=";
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
/// `index-project --module NAME` / `--module=NAME`.
const index_module_flag = "--module";
/// `index-project --kind KIND` / `--kind=KIND`.
const index_kind_flag = "--kind";
/// Shared internal session failure name for an over-long request line.
const request_too_long = "RequestTooLong";
/// Phase label and default cache-directory leaf, shared so the literal is not
/// repeated across the timer and the persistent-cache path join.
const frontend_label = "frontend";
/// Located `selka.json` failure rendering shared by every loading command.
const config_error_format = "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n";
const std = @import("std");
const product = language.product;
const language = @import("selka");
/// The compiler's language module, for command files the unit root also compiles.
pub const compiler_language = language;
const invalidation = language.invalidation;
const diagnostic_output = language.diagnostic_output;
const Reporting = struct {
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
/// The first screen of `selka --help`: the commands an everyday edit loop uses,
/// where the guides are, and the navigation commands a large project needs.
const everyday_help =
    \\selka: a Python-shaped, statically checked language compiled to native code.
    \\New here? `selka docs card` lists, in 6,000 characters, the rules to know before writing a program;
    \\`selka docs primer` prints the language on one page.
    \\
    \\Everyday commands:
    \\  selka check FILE.selka              type-check without building
    \\  selka fix FILE.selka [--check]     apply safe diagnostic repairs
    \\  selka run FILE.selka [-- ARGS...]   build natively and run; arguments after --
    \\  selka build FILE.selka -o OUT       native executable, lean debug (LLVM -O2 code generation, no IR pass; --debug-o0: -O0) one unit per module
    \\  selka build FILE.selka -o OUT --release   optimized whole-program LLVM build, for shipping or timing
    \\  selka test FILE.selka|DIR           run the public test_* functions
    \\  selka do [STEP] [ARGS...]         run the project's build.selka (found here or above) with STEP and ARGS
    \\  selka juice --help                      runtime work measurements and comparisons
    \\  selka profile on|off|history|trends      retain compiler measurements across commands
    \\  selka cost ENTRY.selka [FUNCTION] [--json] [--sites]   per-function checks, updates and allocation sites
    \\  selka fmt FILE.selka [--check|--write|--diff]   canonical formatting
    \\  selka docs [TOPIC]               the user guides built into this compiler
    \\  selka reference --query TERM     look up a feature or a diagnostic code such as E_TRY_POSITION
    \\  selka --version                  the commit, identity and toolchain of this compiler, on one line
    \\
    \\Development: --local-stdlib on run/build/check/test prefers a standard module source beside the entry over the embedded copy.
    \\
    \\Working in a large project:
    \\  selka context ENTRY.selka --symbol=module::name   one bounded answer about a declaration
    \\  selka context ENTRY.selka --at=FILE:LINE:COLUMN   the same for the declaration at a position
    \\  selka tests-for ENTRY.selka module::name          the tests that reach a declaration (also module.name)
    \\  selka list-interfaces ENTRY.selka [--cost]        public declarations and optional emitted-function costs
    \\  selka api ENTRY.selka --write|--check             the checked-in .api interface file beside each module
    \\  selka overview PROJECT --write|--check        generated public interface, examples and decisions
    \\  selka release check PROJECT                  check source, examples, documentation and decisions
    \\  selka review draft PROJECT --name SLUG       write a change note skeleton for this change
    \\  selka review PROJECT [--check]               plain-English change review against main
    \\  selka index-project ENTRY.selka                   declaration counts per module; --module=NAME, --symbol=NAME for records
    \\  selka test ENTRY.selka --affected --against REF   only the tests an edit since REF can reach
    \\
;
/// Every command and option, after `everyday_help`, and what a malformed front-end
/// command line prints. `build`, `run`, `run-project`, `test`, `dump-ir`,
/// `dump-typed` and `coverage` print their own usage (`src/core/cli.zig`).
const usage = "usage: selka build <file.selka> (-o <output> | --run [-- ARGS...]) [--release | --unoptimized | --optimize-debug] [--link FILE.c]... (native build; `selka build` prints the options)\n" ++
    "       selka run <file.selka> [options] [-- ARGS...] | run-project <entry.selka> [options] [-- ARGS...] (build and run; `selka run` prints the options)\n" ++
    "       selka test <entry.selka|directory> [--filter GLOB] [--json] [--release | --unoptimized | --optimize-debug] [--affected --against REF] (run the public test_* functions)\n" ++
    "       selka do [STEP] [ARGS...] (find build.selka here or in the nearest folder above and run it there with STEP and ARGS)\n" ++
    "       selka dump-ir <file.selka> [--facts] | dump-typed <file.selka> [FUNCTION] | coverage <file.selka>... (developer views of the new core)\n" ++
    "       selka juice <doctor|analyze|record|compare|validate|calibrate> (performance work proxy)\n" ++
    "       selka cost <entry.selka> [FUNCTION] [--json] [--sites] [--debug | --no-facts | --verify-facts] [--llvm-remarks FILE.opt.yaml] (per-function Core costs)\n" ++
    "       selka list-interfaces <entry.selka> [--contracts | --cost] (public declarations; --cost checks bodies and appends release costs)\n" ++
    "       selka fix [--check] [--imports] [--warnings] [--report] <entry.selka|directory>... (apply every structured diagnostic repair, docstring examples included;" ++
    " a file alone repairs its errors, its warnings too with --warnings, a directory both; a module or test file alone, its imports with --imports)\n" ++
    "       selka rename [--dry-run] [--json] <entry.selka|directory> <module::name | module::Type.member | FILE:LINE:COLUMN> <new-name> (rename a declaration and every resolved use; all or nothing, checked)\n" ++
    "       selka check <entry.selka> --examples [--diagnostics=text|json] (compile every docstring example as `selka test` does; run none)\n" ++
    "       selka overview PROJECT (--write | --check) [--json] (generated public project overview)\n" ++
    "       selka overview PROJECT --html FILE [--data FILE] [--back HREF] (the project page: one self-contained HTML file)\n" ++
    "       selka release check PROJECT [--step NAME,...] [--json] (complete or per-change release gate)\n" ++
    "       selka release init PROJECT [--adopt-comments [--dry-run]] (record the first public baseline and overview)\n" ++
    "       selka release draft PROJECT --name SLUG [--date YYYY-MM-DD] (explain uncovered public-interface changes)\n" ++
    "       selka release cut PROJECT --name NAME (check and record a release)\n" ++
    "       selka review draft PROJECT --name SLUG (write a change note skeleton for this change)\n" ++
    "       selka review index SITE_DIR (the review site's front page: projects, open changes and landings)\n" ++
    "       selka review PROJECT [--against REF] [--head REV | --range A..B] [--check] [--json FILE] [--html FILE] (plain-English change review; --check refuses by exit 3; --html writes one self-contained page)\n" ++
    "       selka doc-coverage [<repo-root>] (every implemented feature and standard export needs a documented example)\n       selka " ++
    "doctest [<repo-root>] [--filter GLOB] [--report PATH] [--jobs N] [--verbose] (run every fenced documentation example)\n       selka " ++
    "reference --query TERM [--format=text|json] (compiler-derived facts from this executable)\n       selka " ++
    "docs [TOPIC] (list the user guides built into this executable, or print one)\n       selka " ++
    "packages lock CONFIG.json --output LOCK.json | build ENTRY.selka|DIR --lock LOCK.json [--command C] [--receipt FILE] [-- FLAGS...] (offline locked local packages: check, run, build or test)\n       selka " ++
    "cache gc|configure --shared-cache-dir DIR --kind compiler|tests (shared native cache retention; cache --help for options)\n       selka " ++
    "dump-tokens <file.selka> | dump-tokens --tables (stage-0 `tokens-v1` JSON on stdout, lexical failures exit 1; the lexer's tag names and reserved spellings as text)\n       selka " ++
    "dump-syntax <file.selka> [--module | --program] [--trusted] | dump-syntax --layout | dump-syntax --diff REFERENCE CANDIDATE " ++
    "(the framed `StoredSyntax` payload and parser diagnostics on stdout; the payload layout; the first difference of two frames)\n       selka " ++
    "interfaces emit|check|oracle <entry.selka> | show <module.selkai> (per-module interface artifacts; `selka interfaces` prints the options)\n       selka " ++
    "<schema-project|input-module|check|di" ++
    "scover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fm" ++
    "t-module|fmt-project|list-modules|list-interfaces|list-" ++
    "declarations|check" ++
    "-project|check-module|check-policy> <file.selka>\n  schema-project: --schema-report (include " ++
    "checked source and compiler identities)\n  " ++
    "check: type-check a program; a file that declares no main is checked as a library, like check-module; " ++
    "imports, public declarations or project configuration select module-graph checking; " ++
    "a directory checks every module of the project beneath it, imported or not\n  " ++
    "check-module: type-check a library module and its imports without an executable main; the typed holes of other modules are counted on one note line, not listed (`check DIR` lists them)\n  " ++
    "input-module: reads a typed JSON manifest and writes generated " ++
    "module source\n  " ++
    "schema-project: --inputs=manifest.json (repeat for up to 16 modules)\n  " ++
    "discover-duplicates/discover-project-duplicates: --min-nodes=N " ++
    "--population=production|tests|generated|reference|intentional --timings --approximate " ++
    "--max-work=N\n  report-quality/report-project-quality: --max-function-lines=N " ++
    "--max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a " ++
    "signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  " ++
    "lint: --gate --accept --json --all --copies --profile=agent|strict|safety --against=REF --rule=NAME (blocking findings exit 3; " ++
    "--copies prints the copy(...) count per 1000 lines instead, and takes neither --gate nor --accept; " ++
    "--copies A.selka B.selka ... prints one count for the union of what several entries reach)\n  " ++
    "tests-for: <entry.selka> <qualified-name> lists the tests that reach a declaration\n  " ++
    "api-diff: <entry.selka> --write=FILE | --against=FILE [--json] (classified interface changes)\n  " ++
    "api: <entry.selka> --write | --check [--json] (the generated .api interface file beside every module; stale files exit 1)\n  " ++
    "context: <entry.selka> --symbol=NAME | --at=PATH:LINE:COLUMN [--context-bytes=N] [--format=json] " ++
    "[--against=FILE] (one bounded agent-context-v1 answer about one declaration)\n  " ++
    "fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: " ++
    "--check|--write|--diff (otherwise writes formatted source to " ++
    "stdout)\n" ++
    "  list-declarations: parse-only declarations-v1 JSON with byte ranges\n" ++
    "  index-project: navigation-summary-v1 per-module declaration counts by default; --module=NAME --symbol=NAME " ++
    "--kind=function|type|constraint|field|case|parameter|local select navigation-v1 records (navigation-selection-v1); " ++
    "--full prints the complete navigation-v1 document\n  project-dependencies: checked module graph and hashes; --inputs supported\n" ++
    "  one-shot commands: --timings=json (phase-timings-v1 JSON Lines on stderr)\n" ++
    "    --report prints work-report-v1 actual work/reuse plus a frontend-cache-v1 comparison receipt on stderr; --timings=json also adds them; --cache-dir=DIR selects their root; --no-cache disables reuse\n" ++
    "    --explain-invalidation prints an invalidation-report-v1 comparison on stderr for project-dependencies and check-project; --no-cache explains against no baseline\n" ++
    "  all commands: --diagnostics=text|json (stderr JSON Lines; stdout unchanged)\n" ++
    "  check, build, run, test: --warnings prints every warning (by default those of modules git tracks unmodified are counted in one line, and build, run and test leave out the hints\n" ++
    "    W_COPY_MOVE, W_MATCH_ELSE and W_MATCH_IS, and through `selka packages` those of a locked package are counted per package); SELKA_WARNINGS=all does the same\n" ++
    "  check-session: persistent check/clear/quit lines on stdin; JSON status on stdout; --inputs supported\n";

/// Byte ceilings for guest execution, shared by every command that runs one.
const budget = @import("memory_budget");

/// Start the process as Zig would, without a stack trace per allocation
/// (`wiring/process_start.zig`, SELKA-START-1), and run the command line.
pub fn main(minimal: std.process.Init.Minimal) void {
    process_start.run(minimal, dispatchCommandLine);
}

const process_start = @import("wiring/process_start.zig");

/// Dispatch compiler commands, reporting usage/source/IO failures through process exit status.
/// The compiler bounds its own address space first, so a compiler defect fails
/// loudly instead of taking the machine into swap, and the `zig cc` children a
/// native build spawns inherit that ceiling and still finish.
fn dispatchCommandLine(init: std.process.Init) void {
    _ = budget.guardHost(init.environ_map);
    const profile_args = init.minimal.args.toSlice(init.arena.allocator()) catch &.{};
    var profile = language.profile_history.Recorder.start(init, @import("build_identity").compiler_identity, profile_args);
    if (profile) |*recorder| language.profile_history.attach(recorder);
    // The warnings the command withholds (`warning_display.zig`); `--warnings` is consumed here, so no command parses it.
    var command_init = init;
    const display = language.warning_display.begin(init.arena.allocator(), init.io, init.environ_map, profile_args) catch null;
    if (display) |selection| if (selection.args.len != profile_args.len) {
        const vector = init.arena.allocator().alloc([*:0]const u8, selection.args.len) catch null;
        if (vector) |pointers| {
            for (selection.args, pointers) |arg, *pointer| pointer.* = arg.ptr;
            command_init.minimal.args = .{ .vector = pointers };
        }
    };
    const status = dispatch(command_init) catch |err| status: {
        if (componentDiagnostic(err)) |detail| {
            std.Io.File.stderr().writeStreamingAll(init.io, "selka: ") catch break :status @as(u8, 2);
            std.Io.File.stderr().writeStreamingAll(init.io, detail) catch break :status @as(u8, 2);
            std.Io.File.stderr().writeStreamingAll(init.io, "\n") catch break :status @as(u8, 2);
            break :status @as(u8, 2);
        }
        var buffer: [512]u8 = undefined;
        if (err == error.OutOfMemory) {
            std.Io.File.stderr().writeStreamingAll(init.io, budget.exhausted(&buffer, init.environ_map, budget.addressSpaceLimit())) catch break :status @as(u8, 2);
            break :status @as(u8, 2);
        }
        const message = std.fmt.bufPrint(&buffer, "selka: host failure: {s}\n", .{@errorName(err)}) catch "selka: host failure\n";
        std.Io.File.stderr().writeStreamingAll(init.io, message) catch break :status @as(u8, 2);
        break :status @as(u8, 2);
    };
    language.warning_display.finish(init.io, status);
    language.profile_history.attach(null);
    if (profile) |*recorder| {
        recorder.finish(status);
        recorder.deinit();
    }
    // A program a `run` command waited for that died of a signal this process was sent too ends this process the same way.
    language.run_signals.endLikeGuest();
    if (status != 0) std.process.exit(status);
}

/// One release of hints for what the language spelled differently before its rename (decision GH-D4, `crossing_hints.zig`): a
/// set old variable is mentioned once on standard error and the command goes on; an entry file or a project folder spelled the old
/// way ends the command with its one-line hint and the usage status, as it would have failed anyway.
fn crossingHints(process: std.process.Init, args: []const [:0]const u8) !?u8 {
    const allocator = process.arena.allocator();
    if (try crossing_hints.variableHint(allocator, process.environ_map)) |line| {
        try std.Io.File.stderr().writeStreamingAll(process.io, line);
    }
    const refusal = (try crossing_hints.entryHint(allocator, args)) orelse
        (try crossing_hints.projectFileHint(allocator, process.io, args)) orelse return null;
    try std.Io.File.stderr().writeStreamingAll(process.io, refusal);
    return 2;
}

/// Component failures remain recognizable at the public command boundary.
fn componentDiagnostic(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.ComponentMissing,
        error.ComponentManifest,
        error.ComponentDigest,
        error.ComponentProtocol,
        error.ComponentTimeout,
        error.ComponentFailed,
        error.ComponentIo,
        error.ComponentShadowMismatch,
        error.ComponentMode,
        => language.component_adapter.diagnostic(@errorCast(err)),
        else => null,
    };
}

const project_config = @import("selka").project_config;
const module_syntax = language.module_syntax;
const input_probe = @import("input_probe.zig");
const crossing_hints = @import("crossing_hints.zig");
const format_difference = @import("format_difference.zig");
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

/// Stages a front-end command actually runs: everything up to checking. The
/// lowering, emission and link stages belong to `selka build` and `run`, which
/// the new core answers, so these commands always report them skipped.
fn executedStages() [std.meta.tags(invalidation.Stage).len]bool {
    var out: [std.meta.tags(invalidation.Stage).len]bool = @splat(true);
    out[@backingInt(invalidation.Stage.lower_function)] = false;
    out[@backingInt(invalidation.Stage.emit_fragment)] = false;
    out[@backingInt(invalidation.Stage.link)] = false;
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
    /// Original process services for an opt-in Core cost analysis.
    process: ?*const std.process.Init = null,
    fn text(self: Context, bytes: []const u8) !void {
        if (self.diagnostics == .text) return std.Io.File.stderr().writeStreamingAll(self.io, bytes);
        const rendered = try diagnostic_output.message(self.gpa, bytes, self.diagnostics);
        defer self.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(self.io, rendered);
    }
};

/// `selka docs`: the generated operations table, or the guides the docs command lists or prints.
fn docsCommand(process: std.process.Init, args: []const []const u8) !u8 {
    // The operations table is generated from the compiler's own module table,
    // which lives in the compiler module; the guides stay in the root's.
    if (args.len == 3 and std.mem.eql(u8, args[2], "operations")) {
        const allocator = process.arena.allocator();
        const text = @import("selka").operations.render(allocator) catch return error.OutOfMemory;
        defer allocator.free(text);
        try std.Io.File.stdout().writeStreamingAll(process.io, text);
        return 0;
    }
    return @import("docs_command.zig").run(process, args[2..]);
}

/// The commands that run alone: each has its own argument grammar and returns before `parseArgs`.
const Standalone = enum { fix, rename, overview, release, review, @"dump-syntax", @"doc-coverage", doctest, reference, docs, interfaces, cache, packages };

/// `selka dump-tokens --tables`: the lexer's tag names and reserved spellings as text (`tokens-tables-v1`).
fn tokenTables(process: std.process.Init) !u8 {
    const text = try language.tokens_dump.renderTables(process.gpa);
    defer process.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(process.io, text);
    return 0;
}

/// Run the standalone command `args` names, or return null when it names none of them.
fn standaloneCommand(process: std.process.Init, args: []const []const u8) !?u8 {
    if (args.len < 2) return null;
    if (args.len == 3 and std.mem.eql(u8, args[1], "dump-tokens") and std.mem.eql(u8, args[2], "--tables")) {
        const status = try tokenTables(process);
        return status;
    }
    const which = std.meta.stringToEnum(Standalone, args[1]) orelse return null;
    const rest = args[2..];
    const identity = std.fmt.bytesToHex(build_identity, .lower);
    const status: u8 = switch (which) {
        .fix => @import("fix_command.zig").run(process, rest, null),
        .rename => @import("rename_command.zig").run(process, rest),
        .overview => language.overview_command.run(process, rest),
        .release => language.release_command.run(process, rest),
        .review => language.review_command.run(process, rest),
        .@"dump-syntax" => try @import("syntax_dump_command.zig").Command(language).run(process, rest),
        .@"doc-coverage" => try @import("doc_coverage_command.zig").run(process, rest),
        .doctest => @import("doctest_command.zig").run(process, rest),
        .reference => try @import("reference_command.zig").run(@import("selka"), process, rest),
        .docs => try docsCommand(process, args),
        .interfaces => try @import("module_interface_command.zig").run(process, rest),
        .cache => @import("cache_command.zig").run(process, rest),
        .packages => @import("packages_command.zig").run(process, rest, &identity),
    };
    return status;
}

/// `selka --version`: one line with the commit the install step recorded beside this executable (`selka.commit`, written
/// outside the compiler's identity so a commit that changes nothing it digests keeps every cached result), the identity,
/// the build mode, the toolchain and the target; `commit unknown` when the file is not there (D-FR22-4).
fn versionCommand(process: std.process.Init) !void {
    const allocator = process.arena.allocator();
    const builtin = @import("builtin");
    const version = @import("version_line.zig");
    const directory = std.process.executableDirPathAlloc(process.io, allocator) catch "";
    // A symbolic link to the executable (the watch build's) names the install directory by how it was run.
    const args = try process.minimal.args.toSlice(allocator);
    const named = if (args.len != 0) std.fs.path.dirname(args[0]) orelse "" else "";
    var commit = if (directory.len == 0) version.Commit.unknown else version.readCommit(allocator, process.io, directory);
    if (commit == .unknown and named.len != 0) commit = version.readCommit(allocator, process.io, named);
    const identity = std.fmt.bytesToHex(build_identity, .lower);
    const line = try version.render(allocator, .{
        .identity = &identity,
        .zig_version = builtin.zig_version_string,
        .mode = @tagName(builtin.mode),
        .architecture = @tagName(builtin.cpu.arch),
        .os = @tagName(builtin.os.tag),
        .commit = commit,
    });
    try std.Io.File.stdout().writeStreamingAll(process.io, try std.mem.concat(allocator, u8, &.{ line, "\n" }));
    // A compiler built with `-Dtest-system-root` keys another directory's libraries: it says so (GH-3b).
    const root = selka_core.builtSystemRoot();
    if (root.len != 0) try std.Io.File.stdout().writeStreamingAll(process.io, try std.mem.concat(allocator, u8, &.{ "test build: reads the system libraries below ", root, "\n" }));
}

fn dispatch(process: std.process.Init) !u8 {
    const raw_args = try process.minimal.args.toSlice(process.arena.allocator());
    if (try crossingHints(process, raw_args)) |status| return status;
    if (raw_args.len >= 2 and std.mem.eql(u8, raw_args[1], "profile"))
        return language.profile_history.command.run(process, raw_args[2..]);
    const args = try selka_core.prepareArguments(process, raw_args) orelse return 2;
    // Building, running and testing go to the new core, which also refuses the
    // retired commands and flags by name. Their compile failures belong in the
    // friction log as much as `check`'s do.
    var core_friction = CoreFriction{};
    const core_args = core_friction.begin(process, args) orelse return 2;
    defer core_friction.end();
    if (selka_core.dispatch(process, core_args)) |outcome| {
        if (outcome) |status| {
            core_friction.finish(status);
            return status;
        }
    } else |err| {
        core_friction.finish(2);
        return err;
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--features")) {
        try featureReport(process);
        return 0;
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "version"))) {
        try versionCommand(process);
        return 0;
    }
    // An explicit request for help is not a usage error: answer on stdout with
    // the everyday commands first, then the full reference, and exit 0.
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "help"))) {
        try std.Io.File.stdout().writeStreamingAll(process.io, everyday_help ++ "\nEvery command and option:\n" ++ usage);
        return 0;
    }
    if (try standaloneCommand(process, args)) |status| return status;
    // The `&` marker experiment is gone: `mut` is the spelling on both sides of a
    // call and the rule is always on, so the flag names no mode left to select.
    if (mutationMarkersFlag(args[1..])) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka: --mutation-markers was removed; mark each written parameter `mut name: T` and each argument bound to one `mut value`\n");
        return 2;
    }
    // The C backend is gone. Answer its command names with what replaces them
    // rather than a bare usage dump.
    if (args.len >= 2 and (std.mem.eql(u8, args[1], "emit-c") or std.mem.eql(u8, args[1], "emit-project-c"))) {
        var buffer: [192]u8 = undefined;
        const message = try std.fmt.bufPrint(&buffer, "selka: {s} was removed with the C backend; use `selka build FILE.selka -o OUT --emit-llvm PATH`\n", .{args[1]});
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
    if (parsed.copies and (parsed.lint.gate or parsed.lint.accept)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka lint: --copies prints a count and refuses nothing, so it takes neither --gate nor --accept\n");
        return 2;
    }
    language.profile_history.setEntry(parsed.path);
    // The project's `stores`, before any store opens (FR8); `check-session` reads its entries later, from its input.
    if (parsed.path.len != 0 and parsed.command != .@"check-session") if (try selka_core.applyStores(process, parsed.path, parsed.reporting.diagnostics == .json)) return 2;
    var timings = language.timings.Profile.init(process.io, parsed.reporting.timings_json or language.profile_history.enabled(), .compiler);
    const init: Context = .{
        .process = &process,
        .timings = &timings,
        .gpa = process.gpa,
        .arena = process.arena,
        .io = process.io,
        .environ = process.environ_map,
        .diagnostics = parsed.reporting.diagnostics orelse .text,
    };
    const status = (if (parsed.more_entries.len != 0) runEntries(init, parsed) else run(init, parsed)) catch |err| status: {
        // Running out of memory is the memory ceiling's, not a failure of the host: the caller names the ceiling (`budget.exhausted`).
        if (err == error.OutOfMemory) return err;
        const message = if (componentDiagnostic(err)) |detail|
            try std.fmt.allocPrint(init.gpa, "selka: {s}\n", .{detail})
        else
            try std.fmt.allocPrint(init.gpa, "selka: host failure: {s}\n", .{@errorName(err)});
        defer init.gpa.free(message);
        try init.text(message);
        break :status @as(u8, 2);
    };
    if (language.profile_history.enabled()) timings.end();
    const profile_total = if (language.profile_history.enabled()) @max(0, timings.started.durationTo(timings.now()).nanoseconds) else 0;
    if (parsed.reporting.timings_json) try timings.report(status);
    if (language.profile_history.enabled()) {
        for (timings.records.phases[0..timings.records.len]) |phase| language.profile_history.capture(.{
            .version = "phase-timings-v1",
            .kind = "timing",
            .tool = "compiler",
            .name = phase.name,
            .duration_ns = phase.duration_ns,
            .inclusive = phase.inclusive,
            .counts = timings.counts,
            .exit_code = status,
        });
        language.profile_history.capture(.{ .version = "phase-timings-v1", .kind = "timing", .tool = "compiler", .name = "total", .duration_ns = profile_total, .inclusive = true, .counts = timings.counts, .exit_code = status });
    }
    return status;
}
/// `selka lint --copies A.selka B.selka ...`: each entry is linted in turn as a lone entry is (`run`, the same check and the same
/// findings), its count added to one total that is printed once, after the last. An entry that gives no count (it does not
/// check, or is refused) ends the command with what it printed and its status, and one more line names it. A missing entry
/// is refused before any is linted. The project's `stores` are those of the first entry.
fn runEntries(init: Context, parsed: Parsed) !u8 {
    const entries = try std.mem.concat(init.gpa, []const u8, &.{ &.{parsed.path}, parsed.more_entries });
    defer init.gpa.free(entries);
    for (entries) |entry| {
        const unreadable = try input_probe.check(init.gpa, init.io, @tagName(parsed.command), entry, false) orelse continue;
        defer init.gpa.free(unreadable);
        try init.text(unreadable);
        return input_probe.refused_status;
    }
    var total = language.copy_count.Total.init(init.gpa);
    defer total.deinit();
    var one = parsed;
    one.more_entries = &.{};
    one.total = &total;
    for (entries) |entry| {
        one.path = entry;
        const status = try run(init, one);
        if (status == 0) continue;
        const message = try std.fmt.allocPrint(init.gpa, "selka lint: {s} gave no count (status {d}), so there is no total\n", .{ entry, status });
        defer init.gpa.free(message);
        try init.text(message);
        return status;
    }
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    try printCount(init, scratch.allocator(), try total.report(scratch.allocator()), parsed.lint.json);
    return 0;
}

/// The count on stdout, as text or as the one JSON line.
fn printCount(init: Context, memory: std.mem.Allocator, counted: language.copy_count.Report, json: bool) !void {
    const text = if (json) try language.copy_count.renderJson(memory, counted) else try language.copy_count.renderText(memory, counted);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
fn run(init: Context, given: Parsed) !u8 {
    var parsed = given;
    if (parsed.command == .@"check-session") return checkSession(init, parsed);
    // `selka check DIR` checks every module of the project beneath DIR, through one generated entry.
    var directory_plan: language.check_directory.Plan = undefined;
    if (parsed.command == .check and isDirectory(init.io, parsed.path)) {
        directory_plan = language.check_directory.plan(init.arena.allocator(), init.io, parsed.path) catch |err| return directoryRefused(init, parsed.path, err);
        try noteSkippedModules(init, directory_plan);
        parsed.path = directory_plan.entry_path;
        parsed.directory = &directory_plan;
    }
    // A missing, unreadable or directory entry is refused by name before any
    // cache opens, so it leaves no cache directory behind and prints no trace.
    const unreadable = if (parsed.directory == null) try input_probe.check(init.gpa, init.io, @tagName(parsed.command), parsed.path, false) else null;
    if (unreadable) |refusal| {
        defer init.gpa.free(refusal);
        try init.text(refusal);
        return input_probe.refused_status;
    }
    // One optional record per command, built before any work so the wall time it
    // carries covers the whole command. `init` returns null unless the flag or
    // `SELKA_FRICTION_LOG` asked for a log, so an ordinary run pays one check.
    var friction_storage: language.friction_log.Recorder = undefined;
    const friction = startFriction(init.process.?.*, .{ .flag = parsed.friction_path, .command = @tagName(parsed.command), .path = parsed.path }, &friction_storage);
    const friction_start = if (friction != null) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    defer if (friction) |recorder| recorder.deinit();
    // Diagnostics rendered below the front end (the ownership checker, module
    // discovery) reach the record through the attached sink, not through `Context`.
    language.friction_session.attach(friction);
    defer language.friction_session.attach(null);
    // A work directory this command makes keeps itself out of git (`work_markers`): marked once the command is over, so a
    // command that makes none leaves none, and a folder `--cache-dir` names is marked only when this command made it.
    const marked_base = requestedCacheBase(init, parsed) orelse language.frontend_cache.default_directory;
    const made_here = language.work_markers.fresh(init.io, marked_base);
    defer if (!parsed.no_cache) language.work_markers.mark(init.gpa, init.io, marked_base, made_here);
    // A project check runs on a front-end session, which opens its own stores; every other command opens its own.
    var session_storage: ?selka_core.frontend.Session = try sessionIf(init, parsed);
    defer if (session_storage) |*session| session.deinit();
    var shared_store: ?language.shared_artifact_store.Store = null;
    if (!parsed.no_cache and session_storage == null) {
        shared_store = language.shared_artifact_store.openSelected(init.gpa, init.io, init.environ) catch |err| {
            const message = try std.fmt.allocPrint(init.gpa, "error: shared compiler cache: {s}\n", .{@errorName(err)});
            defer init.gpa.free(message);
            try init.text(message);
            return err;
        };
    }
    defer if (shared_store) |*store| store.deinit();
    var frontend_cache: ?language.frontend_cache.Cache = if (session_storage == null) openFrontendCache(init, parsed) else null;
    var semantic_store: ?language.semantic_cache.Store = if (session_storage == null) openSemanticStore(init, parsed) else null;
    if (shared_store) |*store| {
        if (frontend_cache) |*cache| cache.setSharedStore(store);
        if (semantic_store) |*cache| cache.setSharedStore(store);
    }
    var observation: RunObservation = .{ .executed = executedStages() };
    observation.work.command = @tagName(parsed.command);
    var command_init = init;
    command_init.observation = &observation;
    var with_frontend = parsed;
    with_frontend.frontend = if (frontend_cache) |*cache| cache else null;
    with_frontend.semantic = if (semantic_store) |*store| store else null;
    if (session_storage) |*session| try openSession(init, parsed, session, &with_frontend);
    const status = runCommand(command_init, with_frontend) catch |err| {
        if (with_frontend.frontend) |cache| cache.finish();
        best_effort: {
            reportMeasured(init, parsed, with_frontend.frontend, &observation) catch break :best_effort;
        }
        releaseStores(&frontend_cache, &semantic_store);
        if (friction) |recorder| recorder.finish(2, frictionElapsedNs(friction_start, init.io));
        return err;
    };
    // FRONTEND-CACHE-RETAIN-1: trim once the whole working set is known, and
    // before the receipt, so it reports what this run evicted.
    if (with_frontend.frontend) |cache| cache.finish();
    try reportMeasured(init, parsed, with_frontend.frontend, &observation);
    releaseStores(&frontend_cache, &semantic_store);
    if (friction) |recorder| recorder.finish(status, frictionElapsedNs(friction_start, init.io));
    if (parsed.command == .check and status == 0 and init.diagnostics == .text) try reportCheckPassed(init, &observation, parsed.directory != null);
    return status;
}

/// Release the stores `run` opened itself; a session's stores are the session's, and are null here.
fn releaseStores(frontend_cache: *?language.frontend_cache.Cache, semantic_store: *?language.semantic_cache.Store) void {
    if (frontend_cache.*) |*cache| cache.deinit();
    if (semantic_store.*) |*store| store.deinit();
}

/// The front-end session a project check runs on, or null when this command runs its own driver.
fn sessionIf(init: Context, parsed: Parsed) !?selka_core.frontend.Session {
    if (!sessionRoute(init, parsed)) return null;
    return selka_core.frontend.Session.init(init.gpa, init.io, try sessionRootOf(init, parsed));
}

/// The one line a successful `selka check` writes to standard error, so a clean pass can be told
/// from a check that never ran: `check: ok (N modules, M cached)`. N is the modules the check
/// loaded. M is all of them when an identical project check was replayed from its stored verdict,
/// otherwise the modules whose syntax was served from the cache instead of being parsed again.
/// Standard output and the exit status are untouched, and `--diagnostics=json` stays machine
/// readable (the caller skips this line there).
fn reportCheckPassed(init: Context, observation: *RunObservation, generated_entry: bool) !void {
    const loaded = init.timings.counts.modules orelse return std.Io.File.stderr().writeStreamingAll(init.io, diagnostic_output.check_passed ++ "\n");
    // A directory check loads its generated entry too; the project's modules are the rest.
    const modules = if (generated_entry and loaded > 0) loaded - 1 else loaded;
    const cached = if (observation.work.results.request != 0) modules else @min(modules, observation.work.stage(.parsed_modules).reused);
    const line = try std.fmt.allocPrint(init.gpa, diagnostic_output.check_passed ++ " ({d} module{s}, {d} cached)\n", .{ modules, if (modules == 1) "" else "s", cached });
    defer init.gpa.free(line);
    try std.Io.File.stderr().writeStreamingAll(init.io, line);
}

/// The spelling of the friction-log destination option, up to its value.
const friction_flag_prefix = "--friction-log=";

/// What a command tells the friction log before it runs: the `--friction-log`
/// flag as typed, the command's spelling and the entry path (empty until a
/// command's own parser learns it).
const FrictionStart = struct { flag: ?[]const u8, command: []const u8, path: []const u8 };

/// Start this command's friction record, or return null when no log was asked
/// for. The compiler identity and the entry file's snapshot digest come from the
/// same receipt machinery every other command receipt uses, so a record names
/// exactly the build and the source it judged. A failed identity, allocation or
/// read leaves the destination null: logging never fails the command.
fn startFriction(process: std.process.Init, start: FrictionStart, storage: *language.friction_log.Recorder) ?*language.friction_log.Recorder {
    if (start.flag == null and process.environ_map.get(language.friction_log.variable) == null) return null;
    const identity = compilerIdentity(process.io) catch return null;
    const compiler = language.source_receipt.implementation(process.gpa, identity) catch return null;
    storage.* = language.friction_log.Recorder.init(process.gpa, process.io, process.environ_map, .{
        .flag = start.flag,
        .command = start.command,
        .path = start.path,
        .snapshot = entrySnapshot(process, start.path),
        .compiler = compiler,
    }) orelse return null;
    return storage;
}

/// The friction record of a command the new core answers (`build`, `run`,
/// `run-project`, `test`). It is started before the core's own parser runs, so the
/// entry path is filled in by `friction_session.setEntry` once that parser knows it;
/// a command that never reaches an entry (a usage error) writes no record.
const CoreFriction = struct {
    storage: language.friction_log.Recorder = undefined,
    recorder: ?*language.friction_log.Recorder = null,
    started: std.Io.Timestamp = std.Io.Timestamp.zero,
    process: ?std.process.Init = null,
    child: bool = false,

    /// Start the record for a core command and return the arguments to hand the
    /// core: `--friction-log=PATH` (before `--`) is consumed here because the core's
    /// parsers do not know it. Returns null, after printing the usage line, when the
    /// flag is repeated.
    fn begin(self: *CoreFriction, process: std.process.Init, args: []const []const u8) ?[]const []const u8 {
        if (args.len < 2 or !coreCommand(args[1])) return args;
        // `selka test DIR` starts a child compiler per root with this marker set. A
        // child writes a record only when it rendered a diagnostic, so the one record
        // per root that fails to compile carries its codes and a passing root adds none.
        self.child = std.mem.eql(u8, process.environ_map.get(selka_core.internal_child_hint) orelse "", "1");
        var flag: ?[]const u8 = null;
        var kept: std.ArrayList([]const u8) = .empty;
        for (args, 0..) |arg, position| {
            if (position >= 2 and std.mem.eql(u8, arg, "--")) {
                kept.appendSlice(process.arena.allocator(), args[position..]) catch return args;
                break;
            }
            if (position >= 2 and std.mem.startsWith(u8, arg, friction_flag_prefix)) {
                const destination = arg[friction_flag_prefix.len..];
                if (flag != null or destination.len == 0) {
                    std.Io.File.stderr().writeStreamingAll(process.io, "selka: --friction-log=PATH takes one non-empty path\n") catch return null;
                    return null;
                }
                flag = destination;
                continue;
            }
            kept.append(process.arena.allocator(), arg) catch return args;
        }
        self.recorder = startFriction(process, .{ .flag = flag, .command = args[1], .path = "" }, &self.storage);
        if (self.recorder == null) return kept.items;
        language.friction_session.attach(self.recorder);
        self.process = process;
        self.started = std.Io.Timestamp.now(process.io, .awake);
        return kept.items;
    }

    /// Append the record, once the core's parser has named an entry.
    fn finish(self: *CoreFriction, status: u8) void {
        const recorder = self.recorder orelse return;
        const process = self.process.?;
        if (recorder.invocation.path.len == 0) return;
        if (self.child and recorder.diagnostics.items.len == 0) return;
        recorder.snapshot = entrySnapshot(process, recorder.invocation.path);
        recorder.finish(status, frictionElapsedNs(self.started, process.io));
    }

    /// Detach the sink and release the record's buffers.
    fn end(self: *CoreFriction) void {
        const recorder = self.recorder orelse return;
        language.friction_session.attach(null);
        recorder.deinit();
    }
};

/// Whether `name` is a command the new core owns and whose failures the friction log records.
fn coreCommand(name: []const u8) bool {
    for ([_][]const u8{ "build", "run", "run-project", "test" }) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

/// The command's elapsed monotonic nanoseconds, clamped at zero so a clock that
/// never steps backwards still cannot produce a negative duration.
fn frictionElapsedNs(start: std.Io.Timestamp, io: std.Io) u64 {
    const nanoseconds = start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
    return @intCast(@max(nanoseconds, 0));
}

/// Lowercase SHA-256 of the entry file as the command was given it, or the empty
/// string when it cannot be read. Only the digest is ever recorded, never bytes.
fn entrySnapshot(process: std.process.Init, path: []const u8) []const u8 {
    if (path.len == 0) return "";
    const bytes = std.Io.Dir.cwd().readFileAlloc(process.io, path, process.gpa, .limited(16 * 1024 * 1024)) catch return "";
    defer process.gpa.free(bytes);
    return language.friction_log.snapshotHex(process.gpa, bytes) catch "";
}

/// Emit every requested machine-readable receipt after a command finishes.
/// `frontend-cache-v1` is only emitted when a persistent cache was opened (its
/// historical `--no-cache` behavior); `work-report-v1` is always emitted when
/// reporting was requested, including `--no-cache`, because it records work
/// actually performed rather than cache comparisons.
fn reportMeasured(init: Context, parsed: Parsed, cache: ?*language.frontend_cache.Cache, observation: *RunObservation) !void {
    if (!parsed.reporting.measured() and !language.profile_history.enabled()) return;
    if (parsed.no_cache) observation.work.addBypass("cache-disabled", 1);
    if (cache) |opened| {
        if (opened.statistics.damaged != 0) observation.work.addBypass("damaged-entry", opened.statistics.damaged);
        if (opened.statistics.bypassed != 0) observation.work.addBypass("frontend-store-bypassed", opened.statistics.bypassed);
        if (parsed.reporting.measured()) try reportFrontendCounters(init, opened, parsed.reporting, observation.*);
    }
    const rendered = try language.profile_history.renderWork(init.gpa, observation.work, parsed.reporting.measured()) orelse return;
    defer init.gpa.free(rendered);
    language.profile_history.captureJson(rendered);
    if (!parsed.reporting.measured()) return;
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
        .@"check-module",
        .@"check-policy",
        .lint,
        .@"tests-for",
        .@"api-diff",
        .api,
        .context,
        .@"discover-project-duplicates",
        .@"report-project-quality",
        .@"fmt-project",
        => return listModules(init, parsed),
        else => {},
    }
    if (parsed.directory != null) {
        var project = parsed;
        project.command = .@"check-project";
        return listModules(init, project);
    }
    init.timings.begin("source_load", false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    init.timings.counts.source_bytes = bytes.len;
    init.timings.counts.modules = 1;
    init.timings.end();
    // `dump-tokens` is a stage-0 oracle: it lexes one file and stops, never
    // loading imports, parsing, checking or lowering. It is the reference for
    // the differential self-host lexer.
    if (parsed.command == .@"dump-tokens") return dumpTokens(init, parsed, bytes);
    // Imports, public declarations and configured interface gates select the
    // same reachable graph as `check-project`. Private standalone programs
    // retain their single-unit checking path.
    if (parsed.command == .check and try checksProjectInterface(init, parsed.path, bytes)) {
        var project = parsed;
        project.command = .@"check-project";
        project.library_fallback = true;
        return listModules(init, project);
    }
    // A single-unit program has no import edges, but a configured project still
    // owns the same required configuration contract; validate it before checking.
    const unit_deny_warnings = validateUnitConfiguredPolicy(init, parsed) catch |err| return policyFailureStatus(err);
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
    // A single-file `check` judges every generic body at its declaration, as a project check does (W3 step 2).
    if (parsed.command == .check) compilation.checking.template_probes = .declaration;
    if (parsed.command == .fmt or parsed.command == .@"fmt-module") {
        init.timings.begin("format_inclusive", true);
        const formatted = (if (parsed.command == .@"fmt-module") compilation.formatModule(allocator) else compilation.format(allocator)) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            // The formatter's own output failed its check: a defect of the formatter, not of the source, so nothing is
            // written and the status is that of an internal error.
            error.FormatRejected => {
                try report(init, &compilation);
                return 2;
            },
            else => return err,
        };
        init.timings.end();
        defer allocator.free(formatted);
        // Formatting lexes and parses the unit even when no cache is open.
        setWork(init, .parsed_modules, 1, 0);
        return formatOutput(init, parsed, compilation.src, bytes, formatted, allocator);
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
    try attachEmbeds(init, &compilation, parsed.path);
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
    checkUnit(parsed, &compilation, &counting) catch |err| switch (err) {
        error.SourceError => {
            recordCheckWork(init, &counting, null, compilation.program);
            recordSemanticBypass(init, &counting, null);
            if (try mergeRecoveredUnit(init, parsed, &compilation)) {
                try report(init, &compilation);
                return 1;
            }
            try report(init, &compilation);
            try unitHoleOwnership(init, parsed, &compilation);
            return 1;
        },
        else => return err,
    };
    if (compilation.program) |program| {
        if (!try ownershipCheck(init, parsed, program, compilation.src)) return 1;
        try dropKeptCopyMoves(init.gpa, compilation.arena.allocator(), program, compilation.src, &compilation.diagnostics);
    }
    recordCheckWork(init, &counting, null, compilation.program);
    recordSemanticBypass(init, &counting, null);
    init.timings.counts.ast_nodes = compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len;
    recordUnitTypedNodes(init, &compilation);
    init.timings.end();
    const check_ns = if (parsed.reporting.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    try report(init, &compilation);
    if (unit_deny_warnings and deniesOneShotWarnings(parsed.command)) language.warning_display.deny();
    if (unit_deny_warnings and deniesOneShotWarnings(parsed.command) and hasWarning(compilation.diagnostics.items)) return 1;
    switch (parsed.command) {
        .@"index-project",
        .@"project-dependencies",
        .@"check-session",
        .@"schema-project",
        .@"input-module",
        .@"dump-tokens",
        .fmt,
        .@"fmt-module",
        .@"fmt-project",
        .@"list-declarations",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"check-module",
        .@"check-policy",
        .lint,
        .@"tests-for",
        .@"api-diff",
        .api,
        .context,
        .@"discover-project-duplicates",
        .@"report-project-quality",
        => unreachable,
        .check => {},
        .@"report-quality" => {
            var analysis = try language.quality.analyze(allocator, compilation.program.?, compilation.src, compilation.syntax.?, parsed.quality);
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
    }
    return 0;
}

/// Read the files a single-unit program's `embed_bytes`/`embed_str` calls name and
/// attach them to its source (`EMBED-1`). Paths resolve against the unit's own
/// directory and may not leave the nearest `selka.json` directory.
fn attachEmbeds(init: Context, compilation: *language.Compilation, path: []const u8) !void {
    const arena = compilation.arena.allocator();
    const found = try language.embed.scan(arena, compilation.src);
    if (found.len == 0) return;
    const import_root = std.fs.path.dirname(path) orelse ".";
    const roots: language.embed.Roots = .{ .io = init.io, .import_root = import_root, .root = (try embedRoot(init, path)) orelse import_root };
    try language.embed.resolve(arena, roots, std.fs.path.basename(path), found);
    compilation.src.embeds = found;
}

/// Public declarations and configured interface gates require a module index.
fn checksProjectInterface(init: Context, path: []const u8, bytes: []const u8) !bool {
    if (module_syntax.usesModuleSyntax(bytes)) return true;
    if (!validEntryBasename(std.fs.path.basename(path))) return false;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "public ")) return true;
    }
    const configured = try project_config.discover(init.gpa, init.io, path);
    defer if (configured) |found| init.gpa.free(found);
    return configured != null;
}

/// Record the checked node count of a single unit; a library check retains no program.
fn recordUnitTypedNodes(init: Context, compilation: *const language.Compilation) void {
    const program = compilation.program orelse return;
    init.timings.counts.typed_nodes = program.nodes.len + program.statements.len;
}

/// Check one parsed single-unit program. `check` of a unit with no `main` is a
/// library check (`CHECK-LIBRARY-2`): the bodies, effects and boundaries
/// `check-module` verifies, with no executable program retained. A declared
/// `main` of any signature is always checked as an entry point.
fn checkUnit(parsed: Parsed, compilation: *language.Compilation, semantic: *language.semantic_cache.Cache) language.diagnostic.Error!void {
    const as_library = parsed.command == .check and !compilation.declaresMain();
    if (as_library) {
        const program = try compilation.checkLibraryProgram();
        compilation.program = program;
    } else try compilation.checkWithCache(semantic);
}

fn report(init: Context, compilation: *const language.Compilation) !void {
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    // A refusal of a binding that hides a module-level name carries the `selka rename` line that repairs it (FR18).
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(init.io, ".", scratch.allocator()) catch ".";
    const paths: language.shadowing_repair.Paths = .{ .root = cwd, .cwd = cwd, .entry = compilation.src.path };
    const noted = try language.shadowing_repair.annotate(scratch.allocator(), compilation.diagnostics.items, compilation.src, paths);
    // A qualifier that is a module file beside the unit, which the unit does not import, gets the import as its repair (FR32).
    const root: language.project_module_import.Root = .{ .io = init.io, .path = std.fs.path.dirname(compilation.src.path) orelse "." };
    const items = try language.project_module_import.explain(scratch.allocator(), root, noted, compilation.src);
    for (items) |diagnostic| {
        language.friction_session.note(diagnostic);
        const rendered = try diagnostic_output.render(init.gpa, diagnostic, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        try language.warning_display.write(init.io, rendered);
    }
}

/// Lex exactly one file and write a `tokens-v1` JSON document.
/// A lexical failure writes diagnostics to stderr and returns exit status 1; no
/// partial document is printed.
fn dumpTokens(init: Context, parsed: Parsed, bytes: []const u8) !u8 {
    const src = try language.source.Source.init(init.arena.allocator(), parsed.path, bytes);
    var sink: language.diagnostic.Sink = .{ .allocator = init.gpa };
    defer sink.deinit();
    const tokens = language.lexer.lex(init.gpa, bytes, &sink) catch |err| switch (err) {
        error.SourceError => {
            for (sink.items.items) |item| {
                const rendered = try language.diagnostic_output.render(init.gpa, item, src, init.diagnostics);
                defer init.gpa.free(rendered);
                try language.warning_display.write(init.io, rendered);
            }
            return 1;
        },
        else => return err,
    };
    defer init.gpa.free(tokens);
    const document = try language.tokens_dump.render(init.gpa, parsed.path, src, tokens);
    defer init.gpa.free(document);
    try std.Io.File.stdout().writeStreamingAll(init.io, document);
    return 0;
}

const Command = enum {
    @"index-project",
    @"project-dependencies",
    @"check-session",
    @"schema-project",
    @"input-module",
    @"fmt-project",
    @"fmt-module",
    @"report-project-quality",
    @"discover-project-duplicates",
    @"check-policy",
    lint,
    @"tests-for",
    @"api-diff",
    api,
    context,
    @"check-project",
    @"check-module",
    @"list-interfaces",
    @"list-modules",
    @"list-declarations",
    fmt,
    check,
    @"dump-tokens",
    @"discover-duplicates",
    @"report-quality",
};
const ArgError = error{ Usage, OutOfMemory };

/// Which `context` selector a space-separated flag is waiting for.
const ContextSelectorField = enum { symbol, at };

/// `selka context` selection and budget. Grouped so `Parsed` gains one field
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

/// `index-project` view switches: `--full` for the complete `navigation-v1`
/// document, or the `--module`, `--symbol` and `--kind` filters of a
/// selection. None of them asks for the default bounded summary.
const IndexOptions = struct {
    full: bool = false,
    selection: language.navigation_views.Selection = .{},

    /// The document these switches ask for.
    fn view(self: IndexOptions) language.navigation_views.View {
        if (self.full) return .full;
        const selected = self.selection;
        if (selected.module != null or selected.symbol != null or selected.kind != null) return .{ .selection = selected };
        return .summary;
    }

    /// `--full` publishes everything, so it takes no filter, and `--kind` names
    /// one of the kinds a navigation symbol carries.
    fn validate(self: IndexOptions) error{Usage}!void {
        const selected = self.selection;
        if (self.full and (selected.module != null or selected.symbol != null or selected.kind != null)) return error.Usage;
        const kind = selected.kind orelse return;
        for (language.navigation.kinds) |known| if (std.mem.eql(u8, known, kind)) return;
        return error.Usage;
    }
};

const Parsed = struct {
    schema_report: bool,
    inputs: [16][]const u8,
    input_count: usize,
    policy: ?[]const u8,
    format_check: bool,
    format_write: bool,
    format_diff: bool,
    write: bool,
    /// `list-interfaces --contracts` emits declaration-level provider contracts.
    contracts: bool,
    /// Append release costs of the entry's emitted functions.
    cost: bool,
    quality: language.quality.Options,
    command: Command,
    path: []const u8,
    discovery: language.duplicates.Options,
    reporting: Reporting,
    /// `lint` switches; ignored by every other command.
    lint: language.lint.Options,
    /// `lint --copies`: print the copy count in place of the findings.
    copies: bool,
    /// `lint --copies A.selka B.selka ...`: the entries after the first, which `path` names; empty for every other run.
    more_entries: []const []const u8,
    /// Where one entry's count goes instead of the screen, while `runEntries` gathers a total over several.
    total: ?*language.copy_count.Total,
    /// `tests-for` subject: the qualified declaration name to query.
    subject: ?[]const u8,
    /// `context` selector, budget and optional baseline.
    context: ContextOptions,
    /// `index-project` view: summary, selection or `--full`.
    index: IndexOptions,
    /// `api-diff` baseline to compare against, or the path to write.
    api_against: ?[]const u8,
    api_write: ?[]const u8,
    api_json: bool,
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
    /// Per-function ownership proofs for the current checked project.
    ownership_cache: ?*selka_core.OwnershipCache = null,
    /// The front-end session a project check runs on (`sessionRoute`): it owns the project, the caches and the checked program,
    /// and `frontend` and `semantic` above are its stores. Null for every command that still runs its own driver.
    session: ?*selka_core.frontend.Session = null,
    /// `--friction-log=PATH` as typed, or null when the flag was not passed.
    /// `SELKA_FRICTION_LOG` names the same destination when the flag is absent.
    friction_path: ?[]const u8 = null,
    /// Set on the `check-project` a `selka check` of a module entry becomes: an
    /// entry that declares no `main` is then checked as a library (`CHECK-LIBRARY-2`)
    /// instead of failing `E_MAIN`. A plain `check-project` keeps requiring `main`.
    library_fallback: bool = false,
    /// The plan of a `selka check DIR`: `path` is then the generated entry's virtual path, which no file holds, and its
    /// source and module count come from here (`check_directory.zig`).
    directory: ?*const language.check_directory.Plan = null,
};
/// Whether any argument names the retired `--mutation-markers` switch. Every
/// command rejects it before its own parser sees it, because no command selects
/// a marker mode any more.
fn mutationMarkersFlag(args: []const []const u8) bool {
    for (args) |arg| if (std.mem.eql(u8, arg, "--mutation-markers")) return true;
    return false;
}
fn checksOwnership(command: Command) bool {
    return switch (command) {
        .check, .@"check-project", .@"check-module", .@"check-session", .lint => true,
        else => false,
    };
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) ArgError!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var parser: ArgumentParser = .{ .command = command, .allocator = allocator };
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--cache-dir")) {
            if (parser.cache_dir != null or index + 1 >= args.len) return error.Usage;
            index += 1;
            parser.cache_dir = args[index];
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
                .@"project-dependencies", .@"check-project" => {},
                else => return error.Usage,
            }
            parser.reporting.explain_invalidation = true;
            continue;
        }
        if (try parser.cacheDirectoryOption(arg)) continue;
        if (try parser.surfaceOption(arg)) continue;
        if (try parser.qualityOption(arg)) continue;
        if (try parser.checkOption(arg)) continue;
        if (try parser.formatOption(arg)) continue;
        // `context` and `index-project` also accept their `--flag value`
        // spelling, which consumes the next argument; every other flag keeps
        // the `--flag=value` form.
        if (try parser.separateValue(args, &index)) continue;
        if (try parser.discoveryOption(arg)) continue;
        if (std.mem.startsWith(u8, arg, policy_prefix)) {
            if (command != .@"check-policy" or parser.policy != null or arg.len == policy_prefix.len) return error.Usage;
            parser.policy = arg[policy_prefix.len..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) return error.Usage;
        if (parser.path != null) {
            if (command != .lint) return error.Usage;
            try parser.more_entries.append(allocator, arg);
            continue;
        }
        parser.path = arg;
    }
    return parser.finish();
}
const ArgumentParser = struct {
    command: Command,
    schema_report: bool = false,
    contracts: bool = false,
    cost: bool = false,
    inputs: [16][]const u8 = @splat(""),
    input_count: usize = 0,
    quality: language.quality.Options = .{},
    quality_seen: u8 = 0,
    format_check: bool = false,
    format_write: bool = false,
    format_diff: bool = false,
    write: bool = false,
    path: ?[]const u8 = null,
    policy: ?[]const u8 = null,
    allocator: std.mem.Allocator,
    discovery: language.duplicates.Options = .{},
    reporting: Reporting = .{},
    lint: language.lint.Options = .{},
    /// `lint --copies`.
    copies: bool = false,
    /// The entries after the first, which only `lint --copies` takes.
    more_entries: std.ArrayList([]const u8) = .empty,
    subject: ?[]const u8 = null,
    context_symbol: ?[]const u8 = null,
    context_at: ?[]const u8 = null,
    /// The `context` selector whose value is the next argument, for the
    /// `--symbol NAME` spelling the documented usage writes with a space.
    context_pending: ?ContextSelectorField = null,
    context_bytes: usize = language.context.default_context_bytes,
    context_against: ?[]const u8 = null,
    index: IndexOptions = .{},
    api_against: ?[]const u8 = null,
    api_write: ?[]const u8 = null,
    api_json: bool = false,
    no_cache: bool = false,
    friction_path: ?[]const u8 = null,
    cache_dir: ?[]const u8 = null,
    saw_min: bool = false,
    saw_population: bool = false,
    saw_work: bool = false,
    /// `--cache-dir` is shared by every frontend-caching command.
    fn cacheDirectoryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (!std.mem.startsWith(u8, arg, cache_directory_prefix)) return false;
        if (self.cache_dir != null or arg.len == cache_directory_prefix.len) return error.Usage;
        self.cache_dir = arg[cache_directory_prefix.len..];
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
        if (std.mem.eql(u8, arg, "--cost")) {
            if (self.command != .@"list-interfaces" or self.cost or self.contracts) return error.Usage;
            self.cost = true;
            return true;
        }
        if (std.mem.eql(u8, arg, "--contracts")) {
            if (self.command != .@"list-interfaces" or self.contracts or self.cost) return error.Usage;
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
            .fmt, .@"fmt-module", .@"fmt-project", .api => true,
            else => false,
        };
    }
    /// `--check` on the commands that compare rather than write.
    fn checkOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (!std.mem.eql(u8, arg, "--check")) return false;
        if (!self.checks() or self.format_check) return error.Usage;
        self.format_check = true;
        return true;
    }

    /// `fmt`/`fmt-module` output modes: print to stdout by default, or one of
    /// `--check`, `--write`/`-i` and `--diff`.
    fn formatOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .fmt and self.command != .@"fmt-module") return false;
        if (std.mem.eql(u8, arg, "--write") or std.mem.eql(u8, arg, "-i")) {
            if (self.format_write or self.format_check or self.format_diff) return error.Usage;
            self.format_write = true;
            return true;
        }
        if (std.mem.eql(u8, arg, "--diff")) {
            if (self.format_diff or self.format_write) return error.Usage;
            self.format_diff = true;
            return true;
        }
        return false;
    }

    fn discoveryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (try self.lintOption(arg)) return true;
        if (try self.apiDiffOption(arg)) return true;
        if (try self.apiOption(arg)) return true;
        if (try self.contextOption(arg)) return true;
        if (try self.indexOption(arg)) return true;
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
            const supported = self.command == .@"discover-duplicates" or self.command == .@"discover-project-duplicates";
            if (!supported or self.reporting.timings or self.reporting.timings_json) return error.Usage;
            self.reporting.timings = true;
        } else return false;
        return true;
    }

    /// `lint` switches: `--gate`, `--accept`, `--json`, `--all`, `--copies`,
    /// `--profile=NAME`, `--against=REF` and `--rule=NAME`. Only `lint` accepts
    /// them; a repeat, or a rule name the driver does not know, is a usage error.
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
        } else if (std.mem.eql(u8, arg, "--all")) {
            if (self.lint.all) return error.Usage;
            self.lint.all = true;
        } else if (std.mem.eql(u8, arg, "--copies")) {
            if (self.copies) return error.Usage;
            self.copies = true;
        } else if (std.mem.startsWith(u8, arg, lint_profile_prefix)) {
            if (self.lint.profile != null or arg.len == lint_profile_prefix.len) return error.Usage;
            self.lint.profile = std.meta.stringToEnum(language.lint_config.Profile, arg[lint_profile_prefix.len..]) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, lint_against_prefix)) {
            if (self.lint.against != null or arg.len == lint_against_prefix.len) return error.Usage;
            self.lint.against = arg[lint_against_prefix.len..];
        } else if (std.mem.startsWith(u8, arg, lint_rule_prefix)) {
            if (self.lint.rule != null or !language.lint.knownRule(arg[lint_rule_prefix.len..])) return error.Usage;
            self.lint.rule = arg[lint_rule_prefix.len..];
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

    /// `api` switches besides `--check`: `--write` and `--json`.
    fn apiOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .api) return false;
        if (std.mem.eql(u8, arg, "--write")) {
            if (self.write) return error.Usage;
            self.write = true;
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

    /// `index-project` switches in the `--flag=value` spelling: `--full`,
    /// `--module=NAME`, `--symbol=NAME` and `--kind=KIND`. A repeat or an empty
    /// value is a usage error.
    fn indexOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (self.command != .@"index-project") return false;
        if (std.mem.eql(u8, arg, "--full")) {
            if (self.index.full) return error.Usage;
            self.index.full = true;
            return true;
        }
        inline for (.{ .{ index_module_flag, "module" }, .{ context_symbol_flag, "symbol" }, .{ index_kind_flag, "kind" } }) |spelled| {
            if (std.mem.startsWith(u8, arg, spelled[0] ++ "=")) return contextValue(&@field(self.index.selection, spelled[1]), arg[spelled[0].len + 1 ..]);
        }
        return false;
    }

    /// A `context` or `index-project` switch written with a space instead of
    /// `=`, which takes the next argument.
    fn separateValue(self: *ArgumentParser, args: []const []const u8, index: *usize) ArgError!bool {
        if (try self.indexSeparateValue(args, index)) return true;
        return self.contextSeparateValue(args, index);
    }

    /// The `index-project` filters written with a space instead of `=`, which
    /// take the next argument, as `context --symbol NAME` does.
    fn indexSeparateValue(self: *ArgumentParser, args: []const []const u8, index: *usize) error{Usage}!bool {
        if (self.command != .@"index-project") return false;
        inline for (.{ .{ index_module_flag, "module" }, .{ context_symbol_flag, "symbol" }, .{ index_kind_flag, "kind" } }) |spelled| {
            if (std.mem.eql(u8, args[index.*], spelled[0])) {
                if (index.* + 1 >= args.len) return error.Usage;
                index.* += 1;
                return contextValue(&@field(self.index.selection, spelled[1]), args[index.*]);
            }
        }
        return false;
    }

    fn finish(self: *ArgumentParser) ArgError!Parsed {
        if (self.saw_work and !self.discovery.approximate) return error.Usage;
        if (self.command == .@"fmt-project" and !self.format_check) return error.Usage;
        if (self.format_write and (self.format_check or self.format_diff)) return error.Usage;
        if (self.command == .@"check-policy" and self.policy == null) return error.Usage;
        if (self.more_entries.items.len != 0 and !self.copies) return error.Usage;
        if (self.command == .@"tests-for" and self.subject == null) return error.Usage;
        if (self.command == .@"api-diff" and (self.api_against == null) == (self.api_write == null)) return error.Usage;
        if (self.command == .api and self.write == self.format_check) return error.Usage;
        if (self.command == .context and (self.context_symbol == null) == (self.context_at == null)) return error.Usage;
        if (self.context_pending != null) return error.Usage;
        try self.index.validate();
        return .{
            .schema_report = self.schema_report,
            .inputs = self.inputs,
            .input_count = self.input_count,
            .policy = self.policy,
            .format_check = self.format_check,
            .format_write = self.format_write,
            .format_diff = self.format_diff,
            .write = self.write,
            .contracts = self.contracts,
            .cost = self.cost,
            .quality = self.quality,
            .command = self.command,
            .path = self.path orelse return error.Usage,
            .discovery = self.discovery,
            .reporting = self.reporting,
            .lint = self.lint,
            .copies = self.copies,
            .more_entries = self.more_entries.items,
            .total = null,
            .subject = self.subject,
            .context = .{
                .symbol = self.context_symbol,
                .at = self.context_at,
                .bytes = self.context_bytes,
                .against = self.context_against,
            },
            .index = self.index,
            .api_against = self.api_against,
            .api_write = self.api_write,
            .api_json = self.api_json,
            .no_cache = self.no_cache,
            .cache_dir = self.cache_dir,
            .friction_path = self.friction_path,
        };
    }
};

/// Consume `--no-cache`, the one value-less switch that may appear at most
/// once. A repeat is a usage error; an argument that is not this flag is left
/// for the caller's other branches.
fn parseSwitchFlag(arg: []const u8, parser: *ArgumentParser) ArgError!bool {
    if (!std.mem.eql(u8, arg, "--no-cache")) return false;
    if (parser.no_cache) return error.Usage;
    parser.no_cache = true;
    return true;
}

/// Consume `--friction-log=PATH`, the opt-in friction destination for this
/// command. A repeated or empty destination is a usage error; an argument that
/// is not this flag is left for the caller's other branches.
fn parseFrictionFlag(arg: []const u8, parser: *ArgumentParser) ArgError!bool {
    if (!std.mem.startsWith(u8, arg, friction_flag_prefix)) return false;
    if (parser.friction_path != null) return error.Usage;
    const destination_path = arg[friction_flag_prefix.len..];
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
    /// The directory embedded files must stay inside (`EMBED-1`); the module root when null.
    embed_root: ?[]const u8 = null,
    /// Header records of the open frontend cache; null when there is none.
    records: ?language.module_records.Records = null,
    fn embed(context: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!language.embed.Read {
        const self: *ModuleFiles = @ptrCast(@alignCast(context.?));
        var files: language.project_files.Files = .{ .io = self.io, .root = self.root, .embed_root = self.embed_root };
        return language.project_files.Files.readEmbed(&files, allocator, module_path, path, limit);
    }
    fn provider(self: *ModuleFiles) language.project.Provider {
        return .{ .context = self, .read = ModuleFiles.read, .embed = ModuleFiles.embed, .records = self.records };
    }
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
/// Read the profile clock only when `--timings` is on; `addMark` ignores the mark otherwise.
fn timingMark(init: Context) language.timings.Mark {
    return init.timings.mark();
}

fn listModules(init: Context, parsed: Parsed) !u8 {
    // A session checks through its own checked-body cache, whose statistics count the bodies it checked or reused.
    const functions = if (parsed.session) |session| session.workCounter() else null;
    const status = try listModulesWithCache(init, parsed, null, functions);
    if (functions) |counter| recordSemanticBypass(init, counter, null);
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
        const count = functions.statistics.rejections.total[index] - prior.rejections.total[index];
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

/// Validate a discovered `selka.json` for a single-unit command. A unit has no
/// import edges, so the policy itself is trivially satisfied; this still rejects
/// a missing or malformed configuration or policy instead of skipping it.
/// Returns whether the project asks for `lint.warnings: "deny"`, which makes a
/// `W_*` diagnostic rejecting in the inner loop.
fn validateUnitConfiguredPolicy(init: Context, parsed: Parsed) !bool {
    const config_path = project_config.discover(init.gpa, init.io, parsed.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try init.text("selka: cannot inspect the entry directory for selka.json\n");
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
/// `lint` object leaves enforcement off here; `selka lint` is what reports it.
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
    return command == .check;
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
    const denied_start = timingMark(init);
    const denied = try projectWarningsDenied(init, compilation, configured);
    init.timings.addMark("warnings_policy", denied_start, false);
    if (denied) return 1;
    const frontend_start = timingMark(init);
    try rememberFrontendVerdict(init, .@"check-project", project, compilation, frontend);
    init.timings.addMark("remember_frontend_verdict", frontend_start, false);
    const verdict_start = timingMark(init);
    defer init.timings.addMark("remember_check", verdict_start, false);
    return rememberCheck(verdict, project, compilation);
}

/// Whether an opted-in `warnings: "deny"` project makes this checked program
/// rejecting. The caller has already reported the diagnostics.
fn projectWarningsDenied(init: Context, compilation: *language.project_compile.Compilation, configured: *const ConfiguredPolicy) !bool {
    const denied = try configuredWarningsDeny(init, configured);
    if (!denied) return false;
    language.warning_display.deny();
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

/// Discover and enforce the entry project's configured `selka.json` policy.
/// Discovery starts at the entry file's directory and never consults the shell
/// working directory. `check-policy` is exempt because it inspects an explicit
/// policy path. Missing or malformed configuration returns host status 2; a
/// resolved import that violates the policy returns status 3.
fn loadConfiguredPolicy(init: Context, parsed: Parsed, project: *const language.project.Project, frontend: ?*language.frontend_cache.Cache, verdict: ?*language.check_cache.Cache) !ConfiguredPolicy {
    // A session's caches outlive one request: forget the previous request's
    // identity so an unconfigured project never keys on a configuration it lacks.
    try setPolicyIdentity(frontend, verdict, null);
    if (parsed.command == .@"check-policy") return .{};
    const config_path = project_config.discover(init.gpa, init.io, parsed.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try init.text("selka: cannot inspect the entry directory for selka.json\n");
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
        try setPolicyIdentity(frontend, verdict, if (has_identity) identity[0..] else null);
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
            try init.text("selka: configured import policy cannot be evaluated because the project graph is incomplete\n");
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
    try setPolicyIdentity(frontend, verdict, if (has_identity) identity[0..] else null);
    config_transferred = true;
    return .{ .config = config, .identity = if (has_identity) identity else null };
}

/// API-FILE-3: fold every project module's checked-in interface file into the
/// configured identity the verdict caches key on, so a replayed success never
/// outlives an edit to, or the deletion of, one of those files. A project
/// without `interface_files` keeps its identity unchanged.
fn foldInterfaceFiles(init: Context, configured: *ConfiguredPolicy, project: *const language.project.Project, root: []const u8, stores: Replayed) !void {
    const config = if (configured.config) |*value| value else return;
    if (!config.document.interface_files) return;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("interface-files-identity-v1");
    hash.update(&config.digest);
    if (configured.identity) |*identity| hash.update(identity);
    for (project.order.items) |module| {
        const src = project.modules.items[module].src;
        if (!language.interface_files.needsFile(src)) continue;
        const path = try language.interface_files.apiPath(init.gpa, src.path);
        defer init.gpa.free(path);
        const absolute = try std.fs.path.join(init.gpa, &.{ root, path });
        defer init.gpa.free(absolute);
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, absolute, init.gpa, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
        defer if (bytes) |owned| init.gpa.free(owned);
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, path.len, .little);
        hash.update(&length);
        hash.update(path);
        std.mem.writeInt(u64, &length, if (bytes) |owned| owned.len + 1 else 0, .little);
        hash.update(&length);
        if (bytes) |owned| hash.update(owned);
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    configured.identity = std.fmt.bytesToHex(digest, .lower);
    try setPolicyIdentity(stores.frontend, stores.verdict, configured.identity.?[0..]);
}

/// EMBED-1: fold every embedded file the project's modules read into the
/// configured identity the verdict caches key on, exactly as interface files are
/// folded, so a replayed success, manifest or program never outlives an edit to,
/// or the deletion of, a file an `embed_bytes`/`embed_str` call names. A project
/// that embeds nothing keeps its identity unchanged.
fn foldEmbeds(configured: *ConfiguredPolicy, project: *const language.project.Project, stores: Replayed) !void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("embed-identity-v1");
    if (configured.identity) |*identity| hash.update(identity);
    var embedding = false;
    for (project.order.items) |module| {
        const src = project.modules.items[module].src;
        if (src.embeds.len == 0) continue;
        embedding = true;
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, src.path.len, .little);
        hash.update(&length);
        hash.update(src.path);
        language.embed.hashInto(&hash, src.embeds);
    }
    if (!embedding) return;
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    configured.identity = std.fmt.bytesToHex(digest, .lower);
    try setPolicyIdentity(stores.frontend, stores.verdict, configured.identity.?[0..]);
}

/// Publish the required-policy identity to the caches whose verdict must not
/// outlive a policy change. Each cache keeps its own copy, so `identity` may
/// point at a local buffer. Null restores today's behavior for unconfigured projects.
fn setPolicyIdentity(frontend: ?*language.frontend_cache.Cache, verdict: ?*language.check_cache.Cache, identity: ?[]const u8) error{OutOfMemory}!void {
    if (frontend) |opened| try opened.setPolicyIdentity(identity);
    if (verdict) |opened| try opened.setPolicyIdentity(identity);
}

/// Build the policy identity recorded in `project-dependencies-v1` receipts.
/// Strings belong to the command arena and live until the process exits.
fn configuredPolicyReceipt(allocator: std.mem.Allocator, configured: *const ConfiguredPolicy) !?language.dependency_report.Policy {
    const config = if (configured.config) |*value| value else return null;
    if (!config.hasPolicy()) return null;
    const receipt = try config.receipt(allocator);
    return .{ .config_sha256 = receipt.config_sha256, .policy_sha256 = receipt.policy_sha256 };
}

/// Run `selka lint` over the checked project. Compiler warnings are reported
/// first so one run shows both families; lint findings follow on stderr and the
/// one-line summary on stdout.
fn lintProject(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, configured: *const ConfiguredPolicy) !u8 {
    // `--copies` prints the count alone, but reads the same findings, so the hints are judged as a report would judge them.
    if (parsed.copies) try judgeCopyMoves(init, compilation) else try reportProject(init, compilation);
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
    // `L_ALLOC_IN_LOOP` and `L_COPY_IN_LOOP` read the `cost --sites` rows. The
    // copy rule reports in every declaration, so the analysis runs on every
    // lint. A project the Core cannot lower has no rows and the rules are advice,
    // never a build failure; the run says so (`noteUnjudged`), so no rows is not read as no findings.
    const collected = collectLintSites(init, parsed, compilation);
    const request: language.lint.Request = .{
        .memory = init.gpa,
        .io = init.io,
        .compilation = compilation,
        .config = settings,
        .entry_path = parsed.path,
        .options = parsed.lint,
        .data = .{ .diagnostics = init.diagnostics, .sites = collected.rows, .analysis_failed = collected.failed },
    };
    try noteUnjudged(init, request);
    const adapter = language.component_adapter.configured(init.io, init.environ);
    if (parsed.copies) return copyCount(init, request, adapter, parsed);
    return language.lint.runUsing(request, adapter);
}

/// One line on standard error when the analysis behind the loop rules failed: which rules were not judged, why, and that a gate
/// refuses for it. A run whose analysis ran says nothing.
fn noteUnjudged(init: Context, request: language.lint.Request) !void {
    const code = request.data.analysis_failed orelse return;
    const left = language.lint.unjudged(request);
    const which = if (left.alloc_in_loop and left.copy_in_loop) "L_ALLOC_IN_LOOP and L_COPY_IN_LOOP were" else if (left.copy_in_loop) "L_COPY_IN_LOOP was" else if (left.alloc_in_loop) "L_ALLOC_IN_LOOP was" else return;
    const message = try std.fmt.allocPrint(init.gpa, "selka lint: {s}: the analysis behind the loop rules failed ({s}), so {s} not judged{s}\n", .{
        request.entry_path, code, which, if (left.refuses) "; --gate refuses (status 3)" else "",
    });
    defer init.gpa.free(message);
    try init.text(message);
}

/// `selka lint --copies`: run the lint rules, print how many copies the program writes and which finding names each
/// (`copy_count.zig`) on stdout, and nothing else; one entry of several (`runEntries`) adds its count to the total instead.
/// It refuses nothing, so the status is 0.
fn copyCount(init: Context, request: language.lint.Request, adapter: language.component_adapter.Adapter, parsed: Parsed) !u8 {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const outcome = try language.lint.evaluateUsing(request, scratch, adapter);
    const program = request.compilation.program.?;
    const counted = try language.copy_count.count(scratch, .{
        .program = program,
        .src = request.compilation.src,
        .entry_path = request.entry_path,
        .findings = outcome.findings,
        .split_known = !language.lint.unjudged(request).copy_in_loop,
    });
    if (parsed.total) |total| {
        try total.add(counted);
        return 0;
    }
    try printCount(init, scratch, counted, parsed.lint.json);
    return 0;
}

/// The `cost --sites` rows one lint run reads, and why there are none when the analysis failed.
const LintSites = struct {
    rows: []const language.lint.AllocationSite = &.{},
    /// The first error code of a failed analysis; null when it ran, even to no rows.
    failed: ?[]const u8 = null,
};

/// The `cost --sites` rows one lint run reads: the same analysis `selka cost
/// --sites` renders, with LLVM left out, mapped into the lint rule's type. The
/// rows are those of the functions `main` reaches and, for the discovered tests
/// of the checked project, the copy rows of the functions each test reaches (a
/// test file has no `main`, so the first analysis gives it nothing). A failed
/// analysis leaves the rule with no rows and says why (`LintSites.failed`), except for a program with
/// no `main`, whose analysis cannot be made and has nothing to say.
fn collectLintSites(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation) LintSites {
    const process = init.process orelse return .{};
    const cache = requestedCacheBase(init, parsed) orelse language.frontend_cache.default_directory;
    const analysis = selka_core.analyzeCostSites(process.*, parsed.path, cache);
    const failed = if (compilation.declaresMain()) analysis.failed else null;
    const test_rows = testCopyRows(init, parsed, compilation);
    if (analysis.sites.len + test_rows.len == 0) return .{ .failed = failed };
    const sites = init.arena.allocator().alloc(language.lint.AllocationSite, analysis.sites.len + test_rows.len) catch return .{ .failed = failed };
    for (analysis.sites, sites[0..analysis.sites.len]) |row, *site| site.* = lintSite(row);
    for (test_rows, sites[analysis.sites.len..]) |row, *site| site.* = lintSite(row);
    return .{ .rows = sites, .failed = failed };
}

/// The copy rows of the functions the project's discovered tests reach; none when the project has no tests or the Core refuses them.
fn testCopyRows(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation) []const selka_core.CostSite {
    if (compilation.program == null) return &.{};
    const memory = init.arena.allocator();
    const roots = language.lint.discoveredTests(compilation, memory) catch return &.{};
    if (roots.len == 0) return &.{};
    const rows = selka_core.collectRootSites(memory, compilation.program.?, compilation.src, roots, parsed.path) catch return &.{};
    var copies: std.ArrayList(selka_core.CostSite) = .empty;
    for (rows) |row| if (row.kind == .copy) copies.append(memory, row) catch return &.{};
    return copies.items;
}

/// One `cost --sites` row in the lint rule's type.
fn lintSite(row: selka_core.CostSite) language.lint.AllocationSite {
    return .{
        .function = row.function,
        .path = row.path,
        .line = row.line,
        .column = row.column,
        .kind = switch (row.kind) {
            .copy => .copy,
            .construction => .construction,
            .conversion => .conversion,
            .growth => .growth,
            .@"unresolved call" => .unresolved_call,
        },
        .loop_depth = row.loop_depth,
        .hint = selka_core.costSiteHint(row.kind),
    };
}

/// Print the discovered tests that reach one declaration, spelled
/// `module::name` or, as code spells a call, `module.name`. A project whose
/// bodies did not check still answers, from the syntax call graph, with a
/// closing `basis: syntax` line.
fn testsFor(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation) !u8 {
    const subject = parsed.subject orelse return 2;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const navigation = language.navigation;
    const rendered = if (compilation.program) |program| checked: {
        const resolved = (try testsSubject(init, try navigation.resolveSpelling(scratch, subject, try navigation.functionNames(scratch, program)), "checked ")) orelse return 2;
        break :checked try navigation.renderTestsForUsing(init.gpa, compilation, resolved, language.component_adapter.configured(init.io, init.environ));
    } else syntax: {
        const graph = language.navigation_syntax.build(scratch, compilation) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InternalError => return error.InternalError,
        };
        const resolved = (try testsSubject(init, try navigation.resolveSpelling(scratch, subject, graph.names), "")) orelse return 2;
        break :syntax try language.navigation_syntax.renderTestsForUsing(init.gpa, graph, resolved, language.component_adapter.configured(init.io, init.environ));
    };
    const answer = rendered orelse {
        try init.text("tests-for: no checked declaration has that qualified name\n");
        return 2;
    };
    defer init.gpa.free(answer);
    try std.Io.File.stdout().writeStreamingAll(init.io, answer);
    return 0;
}

/// The declaration a `tests-for` spelling names, or null after reporting that
/// it names none or, for a dotted spelling, several.
fn testsSubject(init: Context, resolved: language.navigation.Resolved, checked: []const u8) !?[]const u8 {
    switch (resolved) {
        .found => |id| return id,
        .missing => {
            const message = try std.fmt.allocPrint(init.gpa, "tests-for: no {s}declaration has that qualified name\n", .{checked});
            defer init.gpa.free(message);
            try init.text(message);
            return null;
        },
        .ambiguous => |candidates| {
            const joined = try std.mem.join(init.gpa, " ", candidates);
            defer init.gpa.free(joined);
            const message = try std.fmt.allocPrint(init.gpa, "tests-for: several declarations match that dotted name; use one of: {s}\n", .{joined});
            defer init.gpa.free(message);
            try init.text(message);
            return null;
        },
    }
}

/// `api-diff`: write a baseline snapshot, or classify the current project
/// against one. A malformed, unreadable or obsolete baseline is a usage failure (2).
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
    if (language.api_diff.needsSourceUpgrade(bytes) catch |err| return apiDiffError(init, err)) return apiDiffUpgrade(init, parsed.path, against);
    const diff_report = language.api_diff.compare(init.gpa, baseline, compilation) catch |err| return apiDiffError(init, err);
    defer language.api_diff.freeChanges(init.gpa, diff_report);
    const rendered = language.api_diff.render(init.gpa, diff_report, parsed.api_json) catch |err| return apiDiffError(init, err);
    defer init.gpa.free(rendered);
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered);
    return 0;
}

/// Refuse one obsolete baseline without producing per-declaration comparisons.
fn apiDiffUpgrade(init: Context, source_path: []const u8, baseline_path: []const u8) !u8 {
    var message: std.Io.Writer.Allocating = .init(init.gpa);
    defer message.deinit();
    try message.writer.writeAll("api-diff: baseline predates declared borrow sources; re-record it with: selka api-diff ");
    try apiDiffArgument(&message.writer, source_path);
    try message.writer.writeByte(' ');
    const output = try std.fmt.allocPrint(init.gpa, "--write={s}", .{baseline_path});
    defer init.gpa.free(output);
    try apiDiffArgument(&message.writer, output);
    try message.writer.writeByte('\n');
    try init.text(message.written());
    return 2;
}

/// Quote one suggested command argument without letting a path become shell syntax.
fn apiDiffArgument(writer: *std.Io.Writer, argument: []const u8) !void {
    const safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-";
    if (argument.len != 0 and std.mem.findNone(u8, argument, safe) == null) return writer.writeAll(argument);
    try writer.writeByte('\'');
    for (argument) |byte| {
        if (byte == '\'') try writer.writeAll("'\\''") else try writer.writeByte(byte);
    }
    try writer.writeByte('\'');
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
/// The project form of `unitHoleOwnership`: the same ownership phase over a project whose checks failed only with typed holes.
fn projectHoleOwnership(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, library: bool) !void {
    if (try compilation.holeProgram(library)) |program| _ = try ownershipCheck(init, parsed, program, compilation.src);
}

fn checkFailure(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, inputs: []const GeneratedInput) !?u8 {
    const gate = parsed.command != .context and parsed.command != .@"tests-for";
    const library = parsed.command == .lint and !compilation.declaresMain();
    const merged = gate and try mergeRecoveredProject(init, parsed, compilation, library);
    try reportProject(init, compilation);
    if (!gate) return null;
    if (!merged) try projectHoleOwnership(init, parsed, compilation, library);
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
    const answer = language.context.renderUsing(init.gpa, compilation, try compilerIdentity(init.io), request.options, language.component_adapter.configured(init.io, init.environ)) catch |err| return contextError(init, err);
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
            .sources = if (files) |provider| provider.provider() else null,
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
    if (componentDiagnostic(err) != null) return err;
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
/// `*_test.selka` under a subdirectory resolves both from its enclosing project
/// root, so `tests/parser_test.selka` is module `tests.parser_test`; `owned` holds
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

/// The directory no embedded file may leave (`EMBED-1`): the one holding the
/// nearest `selka.json` above the entry, or null to use the entry's own
/// import root. The slice lives in the command arena.
fn embedRoot(init: Context, entry_path: []const u8) !?[]const u8 {
    const config = project_config.discover(init.arena.allocator(), init.io, entry_path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    return std.fs.path.dirname(config orelse return null);
}

fn entryLocation(init: Context, path: []const u8) !EntryLocation {
    if (try project_config.testEntryLocation(init.gpa, init.io, path)) |location| {
        return .{ .root = location.root, .name = location.name, .owned = location };
    }
    const basename = std.fs.path.basename(path);
    return .{ .root = std.fs.path.dirname(path) orelse ".", .name = product.chopSource(basename) };
}

/// The module records of an open frontend cache, or null when none is open.
fn recordsOf(cache: ?*language.frontend_cache.Cache) ?language.module_records.Records {
    const opened = cache orelse return null;
    return opened.records();
}

/// The local files beside the entry that a standard module hides (`options.selka` against the standard `options`), for the messages about a
/// standard module (`Options.standard.hidden`); a `check`, `check-project` or `project-dependencies` (the first stage of `packages
/// build`, whose standard error is shown only when it fails) in text also names each once, as a build does. A check of a
/// standard-named file itself reads that file, so it hides nothing.
fn noteShadowedStandard(init: Context, parsed: Parsed, root: []const u8, options: *language.project.Options) !void {
    if (options.standard.from_provider) return;
    options.standard.hidden = try selka_core.project_entry.shadowedIn(init.arena.allocator(), init.io, root);
    const names_it = parsed.command == .check or parsed.command == .@"check-project" or parsed.command == .@"project-dependencies";
    if (init.diagnostics != .text or !names_it) return;
    var warned: std.ArrayList(u8) = .empty;
    try selka_core.project_entry.appendShadowedStandardWarnings(options.standard.hidden, init.arena.allocator(), &warned);
    try std.Io.File.stderr().writeStreamingAll(init.io, warned.items);
}

fn listModulesWithCache(init: Context, parsed: Parsed, verdict: ?*language.check_cache.Cache, functions: ?*language.semantic_cache.Cache) !u8 {
    const frontend = parsed.frontend;
    const frontend_start = clockIf(init.io, parsed.reporting.timings);
    const path = parsed.path;
    const basename = std.fs.path.basename(path);
    if (!validEntryBasename(basename)) {
        return refuseEntryName(init, parsed.path);
    }
    init.timings.begin("source_load_parse", false);
    const location = try entryLocation(init, path);
    defer location.deinit(init.gpa);
    var files: ModuleFiles = .{ .io = init.io, .root = location.root, .embed_root = try embedRoot(init, path), .records = recordsOf(frontend) };
    files.inputs = (try prepareInputs(init, parsed, location.name)) orelse return 2;
    if (parsed.directory) |plan| files.inputs = try withGeneratedEntry(init, files.inputs, location.name, plan.source);
    const session = parsed.session.?;
    const project = &session.project;
    var load_options = try projectLimits(init, parsed);
    try noteShadowedStandard(init, parsed, location.root, &load_options);
    var verdict_replayed = false;
    defer finishSourceDigests(project, verdict_replayed);
    if (try loadModules(init, parsed, project, &files, .{ .entry = location.name, .options = load_options })) |status| return status;
    init.timings.counts.modules = project.modules.items.len;
    init.timings.counts.source_bytes = project.counts.bytes;
    init.timings.end();
    // Required architectural policy is a frontend gate: discover and evaluate
    // it after the resolved graph is loaded but before any cached success can be
    // replayed. A project without `selka.json` keeps its previous behavior.
    const policy_start = timingMark(init);
    var configured = loadConfiguredPolicy(init, parsed, project, frontend, verdict) catch |err| return policyFailureStatus(err);
    defer configured.deinit();
    try foldInterfaceFiles(init, &configured, project, files.root, .{ .verdict = verdict, .frontend = frontend });
    try foldEmbeds(&configured, project, .{ .verdict = verdict, .frontend = frontend });
    const policy_receipt = try configuredPolicyReceipt(init.arena.allocator(), &configured);
    init.timings.addMark("project_policy", policy_start, false);
    const surface_start = timingMark(init);
    if (try surfaceProject(init, project, parsed)) |status| return status;
    if (try replayStoredVerdict(init, parsed, project, .{ .verdict = verdict, .frontend = frontend })) {
        verdict_replayed = true;
        return 0;
    }
    init.timings.addMark("project_surface_and_verdict", surface_start, false);
    const digest_start = timingMark(init);
    project.ensureSourceDigests();
    init.timings.addMark("source_digests", digest_start, false);
    // `list-interfaces` is the declaration/interface gate: it parses every module
    // and checks exported signatures without checking bodies. `--contracts`
    // publishes those declared contracts for provider validation.
    const declaration_start = timingMark(init);
    if (try declarationCommand(init, project, parsed, files.root)) |status| return status;
    init.timings.addMark("declaration_command", declaration_start, false);
    if (checkFamily(parsed.command)) return checkOnSession(init, parsed, session, .{ .files = &files, .configured = &configured, .functions = functions.?, .policy_receipt = policy_receipt, .verdict = verdict });
    if (parsed.command == .@"list-modules") {
        const listing = try project.render(init.gpa);
        defer init.gpa.free(listing);
        try std.Io.File.stdout().writeStreamingAll(init.io, listing);
        return 0;
    }
    return commandOnProject(init, parsed, .{
        .project = project,
        .files = &files,
        .configured = &configured,
        .stores = .{ .verdict = verdict, .functions = functions },
        .times = .{ .policy_receipt = policy_receipt, .frontend_start = frontend_start },
    });
}

/// Whether a command is a check of the project: `check` (which becomes a `check-project` when its entry has imports), `check-project` and
/// `check-module`. They validate and print the warnings; every other command reads a checked program.
fn checkFamily(command: Command) bool {
    return command == .check or command == .@"check-project" or command == .@"check-module";
}

/// The stores a project command reads and writes: the verdict cache of a `check-session` and the semantic cache.
const Stores = struct {
    verdict: ?*language.check_cache.Cache,
    functions: ?*language.semantic_cache.Cache,
};

/// What a project command carries from its load into its work: the receipt of the policy it ran under and when its front end started.
const Times = struct { policy_receipt: ?language.dependency_report.Policy, frontend_start: std.Io.Timestamp };

/// What `commandOnProject` works on: the loaded project, the files and policy that bound it, and the stores and clocks around it.
const ProjectStage = struct {
    project: *language.project.Project,
    files: *ModuleFiles,
    configured: *const ConfiguredPolicy,
    stores: Stores,
    times: Times,
};

/// Index, merge and check a loaded project for every command that is not a `check`, then do what the command does with the checked program.
fn commandOnProject(init: Context, parsed: Parsed, stage: ProjectStage) !u8 {
    const project = stage.project;
    const files = stage.files;
    const functions = stage.stores.functions;
    const configured = stage.configured;
    const output = result: {
        const index_start = timingMark(init);
        _ = (try buildIndex(init, parsed, project)) orelse return partialNavigation(init, project, parsed, files);
        init.timings.addMark("index_build_wall", index_start, true);
        const compilation = try mergeProject(init, parsed);
        if (try earlyProjectCommand(init, parsed, .{ .compilation = compilation, .functions = functions })) |status| return status;
        const semantic_before = if (functions) |f| f.statistics else null;
        const ownership_cache = try openOwnershipCache(init, parsed);
        defer closeOwnershipCache(parsed, ownership_cache);
        var checked_parsed = parsed;
        checked_parsed.ownership_cache = ownership_cache;
        // `context` answers about a project that does not check: it publishes the
        // declarations and diagnostics it did recover and names the reason the
        // resolved relationships are missing, rather than failing like a gate.
        var unchecked_reason: ?[]const u8 = null;
        checkProgramFor(parsed, compilation) catch |err| switch (err) {
            error.SourceError => {
                recordCheckWork(init, functions, semantic_before, compilation.program);
                if (try checkFailure(init, parsed, compilation, files.inputs)) |status| return status;
                unchecked_reason = "bodies did not check; declarations and diagnostics only";
            },
            else => return err,
        };
        if (unchecked_reason == null and parsed.command == .lint) {
            if (!try ownershipCheck(init, checked_parsed, compilation.program.?, compilation.src)) return 1;
            try selka_core.checkAllocationContracts(compilation.diagnostics.allocator, compilation.program.?, compilation.src, &compilation.diagnostics);
        }
        recordCheckWork(init, functions, semantic_before, compilation.program);
        const finish_start = timingMark(init);
        const checked_status = try checkedCommand(init, checked_parsed, compilation, unchecked_reason, files, configured);
        init.timings.addMark("checked_command", finish_start, false);
        if (checked_status) |status| return status;
        init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
        recordTypedNodes(init, compilation);
        switch (parsed.command) {
            .lint => return lintProject(init, parsed, compilation, configured),
            // `tests-for` also answers a project that did not check, from its syntax.
            .@"tests-for" => return testsFor(init, parsed, compilation),
            else => {},
        }
        const executed = executedStages();
        // One receipt serves both the invalidation comparison and, for
        // `project-dependencies`, the normal stdout payload.
        var dependency_receipt: ?[]u8 = null;
        defer if (dependency_receipt) |bytes| init.gpa.free(bytes);
        if (parsed.command == .@"project-dependencies" or parsed.reporting.explain_invalidation) {
            dependency_receipt = try dependencyReport(init, compilation, files.inputs, stage.times.policy_receipt);
        }
        if (parsed.reporting.explain_invalidation) try reportInvalidation(init, parsed, dependency_receipt.?, executed, true);
        if (try requestedOutput(init, compilation, parsed)) |output| break :result output;
        try reportProject(init, compilation);
        if (parsed.command == .@"project-dependencies") break :result try init.gpa.dupe(u8, dependency_receipt.?);
        if (parsed.command == .@"discover-project-duplicates") return discoverProject(init, parsed, project, compilation, stage.times.frontend_start);
        if (parsed.command == .@"check-policy") return checkProjectPolicy(init, parsed, project);
        unreachable;
    };
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    return 0;
}

/// The clock's now when `on`, else zero: a timestamp that only a `--timings` report reads.
fn clockIf(io: std.Io, on: bool) std.Io.Timestamp {
    return if (on) std.Io.Timestamp.now(io, .awake) else std.Io.Timestamp.zero;
}

/// The work directory a project check uses when none is named: the build's, so a check and a build of one program share their
/// records (`--cache-dir` and `SELKA_FRONTEND_CACHE` still choose another).
const session_cache_directory = product.core_work_dir;

/// Whether a command runs on a front-end session: every project command but `check-session` (a long-lived process of its own caches) and
/// the single-file ones, when its entry file is named like a module. A `check` becomes a project check when its entry opens as a module or the
/// project asks for interface gates (`runCommand`).
fn sessionRoute(init: Context, parsed: Parsed) bool {
    if (!validEntryBasename(std.fs.path.basename(parsed.path))) return false;
    if (parsed.directory != null) return true;
    switch (parsed.command) {
        .check => {
            const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, init.gpa, .limited(16 * 1024 * 1024)) catch return false;
            defer init.gpa.free(bytes);
            return checksProjectInterface(init, parsed.path, bytes) catch false;
        },
        .@"index-project", .@"project-dependencies", .@"schema-project", .@"report-project-quality", .@"discover-project-duplicates" => return true,
        .@"check-policy", .lint, .@"tests-for", .@"api-diff", .api, .context, .@"list-interfaces", .@"list-modules", .@"fmt-project" => return true,
        .@"check-project", .@"check-module" => return true,
        else => return false,
    }
}

/// The directory the entry's imports resolve beneath, copied into the command arena for the session that outlives the lookup.
fn sessionRootOf(init: Context, parsed: Parsed) ![]const u8 {
    const location = try entryLocation(init, parsed.path);
    defer location.deinit(init.gpa);
    return init.arena.allocator().dupe(u8, location.root);
}

/// Configure a project check's session as `check` wants it (typed holes refused, validation only, no allocation contracts), open its
/// stores unless `--no-cache`, and hand its stores to the command layer through `into`.
fn openSession(init: Context, parsed: Parsed, session: *selka_core.frontend.Session, into: *Parsed) !void {
    session.setHoleTraps(false);
    session.setReportFormat(init.diagnostics);
    const open_start = timingMark(init);
    defer init.timings.addMark("semantic_cache_open", open_start, false);
    if (parsed.no_cache) {
        session.countWork(init.gpa);
        session.workCounter().?.context.timing = init.timings;
    } else {
        try session.enableCache(init.gpa, requestedCacheBase(init, parsed) orelse session_cache_directory);
        // The per-user compiler store is resolved into the environment the session reads, as every command of the core does.
        const sharing = if (init.process) |process| try selka_core.compilerSharing(process.*, false) else null;
        try session.enableSharedCache(if (sharing) |prepared| prepared.environ_map else init.environ);
    }
    // A check omits the bodies it can stand in; a command that reads every body's tree (the invalidation receipt, a report) omits none.
    if (checkFamily(parsed.command) and !parsed.reporting.explain_invalidation) session.validationOnly() else session.completeProgram();
    // `check` judges its `W_COPY_MOVE` hints against every caller, stood in or checked (`Session.judgeCopyMoves`).
    if (checkFamily(parsed.command)) session.judgeCopyMoves();
    session.discardTrees();
    session.setProfile(init.timings);
    into.session = session;
    if (session.caches.frontend) |*state| {
        into.frontend = &state.frontend;
        into.semantic = &state.store;
    }
}

/// What a session check needs of the command layer around it: the files and policy that bound the load, and the cache whose
/// statistics count the bodies the check checked or reused.
const SessionStage = struct {
    files: *ModuleFiles,
    configured: *const ConfiguredPolicy,
    functions: *language.semantic_cache.Cache,
    policy_receipt: ?language.dependency_report.Policy,
    verdict: ?*language.check_cache.Cache = null,
};

/// Check the project the session loaded: index, merge, then the library or the executable check, and the same output, exit status
/// and verdict the command's own driver produced. The command layer has already enforced the configured policy and replayed (or
/// missed) the stored verdict.
fn checkOnSession(init: Context, parsed: Parsed, session: *selka_core.frontend.Session, stage: SessionStage) !u8 {
    const project = &session.project;
    const frontend = parsed.frontend;
    const index_start = timingMark(init);
    const disk_before: usize = if (frontend) |opened| opened.statistics.syntax.hits else 0;
    const syntax = session.graph.resident.syntax;
    const syntax_before: usize = if (syntax) |opened| opened.statistics.hits else 0;
    session.indexModules() catch |err| switch (err) {
        error.SourceError => {
            recordParsedModules(init, project, syntax, frontend, syntax_before, disk_before);
            try session.explainProblem();
            try reportProblem(init, project);
            return 1;
        },
        else => return err,
    };
    recordParsedModules(init, project, syntax, frontend, syntax_before, disk_before);
    init.timings.addMark("index_build_wall", index_start, true);
    var rendered: std.ArrayList(u8) = .empty;
    defer rendered.deinit(init.gpa);
    session.mergeDeclared(init.gpa, &rendered) catch |err| return sessionRefused(init, &rendered, err);
    const compilation = &session.graph.compilation;
    if (parsed.command == .@"check-module" or (parsed.library_fallback and !compilation.declaresMain())) return checkLibraryOnSession(init, parsed, session, stage);
    const semantic_before = stage.functions.statistics;
    session.repairPublic(repairsPublic(stage.configured, project));
    _ = session.checkMerged(init.gpa, &rendered) catch |err| {
        recordCheckWork(init, stage.functions, semantic_before, compilation.program);
        const status = try sessionRefused(init, &rendered, err);
        // Only a body check that failed is explained; a program that checked and then failed the ownership validation is not.
        if (parsed.reporting.explain_invalidation and compilation.program == null) try reportFailedInvalidation(init, parsed, compilation, stage.files.inputs);
        return status;
    };
    recordCheckWork(init, stage.functions, semantic_before, compilation.program);
    // What the ownership validation printed, in the place the command's own driver printed it.
    try language.warning_display.write(init.io, rendered.items);
    const finish_start = timingMark(init);
    if (try enforceInterfaceFiles(init, parsed, stage.configured, compilation.index, stage.files.root)) |status| return status;
    init.timings.addMark("checked_command", finish_start, false);
    init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
    recordTypedNodes(init, compilation);
    if (parsed.reporting.explain_invalidation) try explainInvalidation(init, parsed, compilation, stage);
    try reportProject(init, compilation);
    return finishCheckProject(init, project, compilation, stage.verdict, frontend, stage.configured);
}

/// Print the `invalidation-report-v1` comparison of a checked project against the baseline the previous run left, and advance the baseline.
fn explainInvalidation(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, stage: SessionStage) !void {
    const receipt = try dependencyReport(init, compilation, stage.files.inputs, stage.policy_receipt);
    defer init.gpa.free(receipt);
    try reportInvalidation(init, parsed, receipt, executedStages(), true);
}

/// Whether `W_COPY_FOR_STORE` also repairs the project's `public` functions (COPY-A3d): its `selka.json` sets no `interface_files` and
/// no package root could hold its modules. A second project imports modules only through `selka packages`, which accepts a root only
/// when every source is `NAME.selka` or under `NAME/`, so a project whose modules have two top-level names has no caller it cannot see.
/// One namespace (a lone module too) may be a package, and a package keeps its public signatures.
fn repairsPublic(configured: *const ConfiguredPolicy, project: *const language.project.Project) bool {
    if (configured.config) |config| if (config.document.interface_files) return false;
    var namespaces: language.check_directory.Namespaces = .{};
    for (project.modules.items) |module| {
        if (language.interface_files.projectModule(module.src)) namespaces.add(module.name);
    }
    return namespaces.several;
}

/// Check the merged program as a library (`check-module`, and a `check` of an entry with no `main`): the session stands unchanged bodies in
/// from the entry's library summaries when it is a `check-project`, validates ownership, and the command layer prints what it
/// rendered, the warnings and the interface-file and warnings gates in the order the command's own driver did.
fn checkLibraryOnSession(init: Context, parsed: Parsed, session: *selka_core.frontend.Session, stage: SessionStage) !u8 {
    const compilation = &session.graph.compilation;
    var rendered: std.ArrayList(u8) = .empty;
    defer rendered.deinit(init.gpa);
    const retained: ?language.frontend_cache.SummarySlot = if (summariesWanted(parsed)) .{ .library = parsed.path } else null;
    if (parsed.command == .@"check-module") session.foldForeignHoles();
    _ = session.checkLibraryMerged(init.gpa, retained, &rendered) catch |err| return sessionRefused(init, &rendered, err);
    try language.warning_display.write(init.io, rendered.items);
    try reportProject(init, compilation);
    if (try enforceInterfaceFiles(init, parsed, stage.configured, compilation.index, stage.files.root)) |status| return status;
    return if (try projectWarningsDenied(init, compilation, stage.configured)) 1 else 0;
}

/// A session step the check refused: a source error prints what the session rendered and exits 1; anything else is a host failure.
fn sessionRefused(init: Context, rendered: *const std.ArrayList(u8), err: anyerror) !u8 {
    if (err != error.SourceError) return err;
    try language.warning_display.write(init.io, rendered.items);
    return 1;
}

/// What a project command's early stage works on: the compilation under check and the semantic cache it was loaded through.
const EarlyStage = struct {
    compilation: *language.project_compile.Compilation,
    functions: ?*language.semantic_cache.Cache,
};

/// Finish project commands that do not need an executable checked program.
fn earlyProjectCheck(init: Context, parsed: Parsed, stage: EarlyStage) !?u8 {
    return switch (parsed.command) {
        .@"index-project" => try indexProject(init, stage.compilation, stage.functions, parsed),
        else => null,
    };
}

/// After a failed unit check whose errors are not all typed holes, the ownership errors of the bodies that did check, placed
/// among the unit's diagnostics in source order before they are reported (F-RC-214); true when the check recovered a program,
/// so the hole phase (`unitHoleOwnership`, which recovers nothing more) is skipped.
fn mergeRecoveredUnit(init: Context, parsed: Parsed, compilation: *language.Compilation) !bool {
    if (!checksOwnership(parsed.command) or language.diagnostic.holesOnly(compilation.diagnostics.items)) return false;
    const library = parsed.command == .check and !compilation.declaresMain();
    const program = (try compilation.holeProgram(library)) orelse return true;
    if (!selka_core.recovered_ownership.recovered(program)) return true;
    const arena = compilation.arena.allocator();
    const found = try selka_core.recovered_ownership.collect(arena, init.gpa, program, compilation.src);
    compilation.diagnostics = .fromOwnedSlice(try selka_core.recovered_ownership.merged(arena, compilation.diagnostics.items, found));
    return true;
}

/// The project form of `mergeRecoveredUnit`.
fn mergeRecoveredProject(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, library: bool) !bool {
    if (!checksOwnership(parsed.command) or language.diagnostic.holesOnly(compilation.diagnostics.items.items)) return false;
    const program = (try compilation.holeProgram(library)) orelse return true;
    if (!selka_core.recovered_ownership.recovered(program)) return true;
    const arena = compilation.diagnostics.allocator;
    const found = try selka_core.recovered_ownership.collect(arena, init.gpa, program, compilation.src);
    compilation.diagnostics.items = .fromOwnedSlice(try selka_core.recovered_ownership.merged(arena, compilation.diagnostics.items.items, found));
    return true;
}

/// After a failed unit check whose only errors are typed holes, the ownership phase on the same unit with
/// its holes as typed nodes, so errors in finished code are reported beside the holes (F-G2b-17).
fn unitHoleOwnership(init: Context, parsed: Parsed, compilation: *language.Compilation) !void {
    const library = parsed.command == .check and !compilation.declaresMain();
    if (try compilation.holeProgram(library)) |program| _ = try ownershipCheck(init, parsed, program, compilation.src);
}

/// Open ownership proof storage only after an identical whole-project verdict misses. A session's cache is the session's: it is
/// scoped to the entry here and `closeOwnershipCache` leaves it open.
fn openOwnershipCache(init: Context, parsed: Parsed) !?*selka_core.OwnershipCache {
    if (!checksOwnership(parsed.command)) return null;
    if (parsed.no_cache or parsed.reporting.explain_invalidation) return null;
    if (parsed.session) |session| {
        const shared = session.caches.ownership orelse return null;
        try shared.open(try selka_core.ownershipScope(init.arena.allocator(), init.io, parsed.path));
        return shared;
    }
    const root = requestedCacheBase(init, parsed) orelse language.frontend_cache.default_directory;
    const cache = try init.arena.allocator().create(selka_core.OwnershipCache);
    cache.* = try selka_core.OwnershipCache.init(init.arena.allocator(), init.gpa, init.io, root);
    cache.verifyFrom(init.environ);
    cache.share(selka_core.engine_sharing.byPolicy(init.arena.allocator(), init.environ));
    cache.open(try selka_core.ownershipScope(init.arena.allocator(), init.io, parsed.path)) catch |err| {
        cache.deinit();
        return err;
    };
    return cache;
}

fn closeOwnershipCache(parsed: Parsed, cache: ?*selka_core.OwnershipCache) void {
    if (parsed.session != null) return;
    if (cache) |owned| owned.deinit();
}

/// Whether a command may use stored check summaries at all: `check-project`, except when it
/// explains an invalidation, which compares complete receipts and uses none.
fn summariesWanted(parsed: Parsed) bool {
    return parsed.command == .@"check-project" and !parsed.reporting.explain_invalidation;
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

/// The stdout document a project report command renders from the checked
/// program: `schema-project` and `report-project-quality`. Null for every other
/// command.
fn requestedOutput(init: Context, compilation: *language.project_compile.Compilation, parsed: Parsed) !?[]u8 {
    return switch (parsed.command) {
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
            var analysis = try language.quality.analyzeWithExports(init.gpa, compilation.program.?, compilation.src, compilation.syntax, parsed.quality, roots);
            defer analysis.deinit();
            break :blk try language.quality.render(init.gpa, analysis, compilation.program.?, compilation.src);
        },
        else => null,
    };
}

fn partialNavigation(init: Context, project: *language.project.Project, parsed: Parsed, files: ?*ModuleFiles) !u8 {
    if (parsed.command == .context) return contextPartial(init, parsed, project, files);
    if (parsed.command == .@"tests-for") {
        try init.text("tests-for: the project does not parse, so no call graph can be read; fix the syntax errors above\n");
        return 1;
    }
    if (parsed.command != .@"index-project") return 1;
    var buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const status = try language.navigation_views.writeLexical(&stdout.interface, init.gpa, project, try compilerIdentity(init.io), indexRequest(parsed));
    try stdout.interface.flush();
    return indexStatus(status);
}

/// `index-project`: check what checks, then publish the requested document —
/// the bounded `navigation-summary-v1` by default, a `navigation-selection-v1`
/// for a filter, or the complete `navigation-v1` on `--full` — streamed to
/// stdout rather than held whole. A body that fails to check still yields
/// its declarations; the diagnostics go to stderr.
fn indexProject(init: Context, compilation: *language.project_compile.Compilation, functions: ?*language.semantic_cache.Cache, parsed: Parsed) !u8 {
    const semantic_before = if (functions) |f| f.statistics else null;
    checkProgramFor(parsed, compilation) catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    recordCheckWork(init, functions, semantic_before, compilation.program);
    init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
    recordTypedNodes(init, compilation);
    init.timings.end();
    try reportProject(init, compilation);
    var buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const status = try language.navigation_views.writeChecked(&stdout.interface, init.gpa, compilation, try compilerIdentity(init.io), indexRequest(parsed));
    try stdout.interface.flush();
    return indexStatus(status);
}

/// Count the typed nodes a check produced; `tests-for` reaches here with
/// none when the bodies did not check.
fn recordTypedNodes(init: Context, compilation: *const language.project_compile.Compilation) void {
    const program = compilation.program orelse return;
    init.timings.counts.typed_nodes = program.nodes.len + program.statements.len;
}

/// The view and entry path one `index-project` run asks for.
fn indexRequest(parsed: Parsed) language.navigation_views.Request {
    return .{ .view = parsed.index.view(), .entry = parsed.path };
}

/// A selection that named nothing still printed a document saying why; it
/// exits 2 like any unresolved name.
fn indexStatus(status: language.navigation_views.Status) u8 {
    return switch (status) {
        .ok => 0,
        .missing, .ambiguous => 2,
    };
}

/// Source-loading limits from the entry project's `selka.json`, or the
/// built-in defaults when no configuration exists or it cannot be read. Each
/// present `budgets` field overrides the matching default. A malformed
/// configuration is reported by `loadConfiguredPolicy` after the graph loads,
/// exactly as before.
fn projectLimits(init: Context, parsed: Parsed) !language.project.Options {
    // The commands that publish a receipt (`project-dependencies`, `schema-project`, the navigation and context answers) record each
    // module's SHA-256 as it is read; the checks do not publish one, and `check-project`, whose verdict hashes the loaded bytes itself,
    // defers the digests until the verdict misses.
    var options: language.project.Options = .{ .digests = switch (parsed.command) {
        .check, .@"check-module" => .eager,
        .@"check-project" => .deferred,
        else => .with_sha256,
    } };
    // A standard-named file named directly as the checked entry is that file,
    // not the embedded module it shadows. The normal import path still uses the
    // embedded copy unless `--local-stdlib` selected it.
    if (parsed.command == .check or parsed.command == .@"check-module" or parsed.library_fallback) {
        if (language.standard_library.source(std.fs.path.basename(parsed.path)) != null) options.standard.from_provider = true;
    }
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

/// Keep error exits consistent with eager loading while successful verdict
/// replay can discard the per-module receipt hashes it never consumed.
fn finishSourceDigests(project: *language.project.Project, verdict_replayed: bool) void {
    if (!verdict_replayed) project.ensureSourceDigests();
}

/// The module a project load starts from and the budgets it loads under.
const LoadSpec = struct { entry: []const u8, options: language.project.Options };

fn loadModules(init: Context, parsed: Parsed, project: *language.project.Project, files: *ModuleFiles, spec: LoadSpec) !?u8 {
    const session = parsed.session.?;
    session.useProvider(files.provider());
    session.configureProject(spec.options, spec.entry);
    session.loadModules(init.gpa, spec.entry) catch |err| {
        if (err == error.SourceError) try session.explainProblem();
        return loadFailed(init, project, err);
    };
    if (!try checkImportedInputs(init, files.inputs, project)) {
        project.ensureSourceDigests();
        return 2;
    }
    return null;
}

/// A refused load: a source error prints the project's problem and exits 1, anything else is a host failure.
fn loadFailed(init: Context, project: *language.project.Project, err: anyerror) anyerror!?u8 {
    if (err != error.SourceError) return err;
    project.ensureSourceDigests();
    try reportProblem(init, project);
    return 1;
}

fn borrowDeclarationGate(init: Context, compilation: *language.project_compile.Compilation) !?u8 {
    compilation.checkBorrowDeclarations() catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return 1;
        },
        else => return err,
    };
    return null;
}

fn earlyProjectCommand(init: Context, parsed: Parsed, stage: EarlyStage) !?u8 {
    switch (parsed.command) {
        .@"api-diff", .@"index-project", .context, .@"tests-for" => {
            if (try borrowDeclarationGate(init, stage.compilation)) |status| return status;
        },
        else => {},
    }
    if (parsed.command == .@"api-diff") {
        const status = try apiDiff(init, parsed, stage.compilation);
        return status;
    }
    return earlyProjectCheck(init, parsed, stage);
}

fn listInterfaces(init: Context, project: *language.project.Project, parsed: Parsed) !u8 {
    const index = (try buildIndex(init, parsed, project)) orelse return partialNavigation(init, project, parsed, null);
    const compilation = try mergeProject(init, parsed);
    if (try borrowDeclarationGate(init, compilation)) |status| return status;
    if (parsed.contracts) {
        const contracts = index.renderContracts(init.gpa) catch |err| switch (err) {
            error.SourceError, error.IncompleteProject => {
                try reportProblem(init, project);
                return 1;
            },
            else => return err,
        };
        defer init.gpa.free(contracts);
        return interfaceListing(init, contracts, parsed);
    }
    // Attach checked bodies when they are available so the default listing can
    // publish each function's inferred `effects(...)`. A body that fails to
    // check is ignored: the interface gate lists declarations whether or not
    // bodies type-check, and it never reports body diagnostics.
    // Body checking may record a project problem; the interface gate owns
    // only declaration diagnostics, so restore the pre-check problem.
    const saved_problem = project.problem;
    compilation.check() catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.SourceError, error.InternalError => {},
    };
    project.problem = saved_problem;
    index.program = compilation.program;
    const text = try index.renderUsing(init.gpa, language.component_adapter.configured(init.io, init.environ));
    defer init.gpa.free(text);
    return interfaceListing(init, text, parsed);
}

/// Keep the declaration bytes intact and append the exact cost command output.
fn interfaceListing(init: Context, text: []const u8, parsed: Parsed) !u8 {
    var extra: []const u8 = "";
    if (parsed.cost) {
        const rendered = try selka_core.interfaceCost(init.process.?.*, parsed.path);
        if (rendered.status != 0) return rendered.status;
        extra = rendered.text;
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    if (parsed.cost) try std.Io.File.stdout().writeStreamingAll(init.io, extra);
    return 0;
}

/// The commands answered from the declaration index alone, without checking
/// bodies: `list-interfaces` and `api`. Null for every other command.
fn declarationCommand(init: Context, project: *language.project.Project, parsed: Parsed, root: []const u8) !?u8 {
    const status = switch (parsed.command) {
        .@"list-interfaces" => try listInterfaces(init, project, parsed),
        .api => try apiFiles(init, project, parsed, root),
        else => return null,
    };
    return status;
}

/// The first step after bodies check: `context` answers here (even from a
/// project that did not check), and a project that opted into interface files
/// rejects a stale one. Null lets the command continue.
fn checkedCommand(init: Context, parsed: Parsed, compilation: *language.project_compile.Compilation, unchecked_reason: ?[]const u8, files: *ModuleFiles, configured: *const ConfiguredPolicy) !?u8 {
    if (compilation.program) |program| if (!try ownershipCheck(init, parsed, program, compilation.src)) return 1;
    if (parsed.command == .context) {
        const status = try contextCommand(init, parsed, compilation, unchecked_reason, files);
        return status;
    }
    return enforceInterfaceFiles(init, parsed, configured, compilation.index, files.root);
}

/// `selka api --write | --check [--json]`: regenerate or compare the interface
/// file beside every project module. Declarations must resolve; bodies are
/// never checked. A file-system failure is a host failure (2).
fn apiFiles(init: Context, project: *language.project.Project, parsed: Parsed, root: []const u8) !u8 {
    const index = (try buildIndex(init, parsed, project)) orelse return 1;
    const compilation = try mergeProject(init, parsed);
    if (try borrowDeclarationGate(init, compilation)) |status| return status;
    const request: language.api_files.Request = .{
        .io = init.io,
        .root = root,
        .entry = parsed.path,
        .mode = if (parsed.write) .write else .check,
        .json = parsed.api_json,
        .staged = language.api_files.stagedRun(),
    };
    const outcome = language.api_files.run(init.gpa, request, index) catch |err| return apiFailure(init, project, err);
    defer init.gpa.free(outcome.report);
    try std.Io.File.stdout().writeStreamingAll(init.io, outcome.report);
    return outcome.status;
}

/// Report an `api` or interface-file enforcement failure: allocation
/// propagates, a declaration error prints the project diagnostics (1), and a
/// file-system failure is a host failure (2).
fn apiFailure(init: Context, project: *language.project.Project, err: language.api_files.Error) !u8 {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.HostIo => {
            try init.text("api: cannot read, write or delete an interface file\n");
            return 2;
        },
        else => {
            try reportProblem(init, project);
            return 1;
        },
    }
}

/// API-FILE-3: a project whose `selka.json` sets `interface_files` rejects a
/// missing or stale interface file with `E_INTERFACE_FILE_STALE` once its
/// bodies check. Only the commands that build or check the live project
/// enforce it; navigation, reports and native-test snapshots do not.
fn enforceInterfaceFiles(init: Context, parsed: Parsed, configured: *const ConfiguredPolicy, index: *language.interfaces.Index, root: []const u8) !?u8 {
    const config = if (configured.config) |*value| value else return null;
    if (!config.document.interface_files or !enforcesInterfaceFiles(parsed)) return null;
    // The bodies already checked, so rendering cannot fail on a declaration;
    // an unreadable interface file is a host failure.
    const text = (try language.api_files.staleDiagnostics(init.gpa, init.io, root, parsed.path, index, language.api_files.stagedRun())) orelse return null;
    defer init.gpa.free(text);
    try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return 1;
}

/// Whether a command checks or builds the live project, so a configured
/// `interface_files` gate applies to it.
fn enforcesInterfaceFiles(parsed: Parsed) bool {
    return switch (parsed.command) {
        .@"check-project", .@"check-module" => true,
        else => false,
    };
}

/// Parse the loaded modules and build their interface index through the command's session, null when a module does not parse (its problem is
/// reported).
fn buildIndex(init: Context, parsed: Parsed, project: *language.project.Project) !?*language.interfaces.Index {
    const session = parsed.session.?;
    const frontend = parsed.frontend;
    const cache = session.graph.resident.syntax;
    const syntax_before: usize = if (cache) |opened| opened.statistics.hits else 0;
    const disk_before: usize = if (frontend) |opened| opened.statistics.syntax.hits else 0;
    session.indexModules() catch |err| switch (err) {
        error.SourceError => {
            recordParsedModules(init, project, cache, frontend, syntax_before, disk_before);
            try session.explainProblem();
            try reportProblem(init, project);
            return null;
        },
        else => return err,
    };
    recordParsedModules(init, project, cache, frontend, syntax_before, disk_before);
    return session.interfaceIndex();
}

/// Merge the indexed modules into one program, the session's.
fn mergeProject(init: Context, parsed: Parsed) !*language.project_compile.Compilation {
    const session = parsed.session.?;
    var refusal: std.ArrayList(u8) = .empty;
    defer refusal.deinit(init.gpa);
    session.mergeDeclared(init.gpa, &refusal) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try std.Io.File.stderr().writeStreamingAll(init.io, refusal.items);
            return err;
        },
    };
    return session.mergedProgram();
}

/// The bodies check of the program a command works on, through its session (a `lint` of an entry with no `main` checks it as a library).
fn checkProgramFor(parsed: Parsed, compilation: *language.project_compile.Compilation) language.project_compile.CheckError!void {
    const session = parsed.session.?;
    if (parsed.command == .lint and !compilation.declaresMain()) return session.checkLibraryBodies();
    return session.checkBodies();
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

/// The stores an unchanged project's verdict may be replayed from.
const Replayed = struct {
    verdict: ?*language.check_cache.Cache,
    frontend: ?*language.frontend_cache.Cache,
};

/// Replay an in-process or persistent stored verdict before any semantic work.
/// A requested explanation must compare receipts, so it never replays a stored
/// verdict before the checked compilation produces one.
fn replayStoredVerdict(init: Context, parsed: Parsed, project: *const language.project.Project, stores: Replayed) !bool {
    if (try replayCheck(init, parsed.command, project, stores.verdict)) return true;
    if (parsed.reporting.explain_invalidation) return false;
    return replayFrontendVerdict(init, parsed.command, project, stores.frontend);
}

fn replayCheck(init: Context, command: Command, project: *const language.project.Project, verdict: ?*language.check_cache.Cache) !bool {
    if (command != .@"check-project") return false;
    const cache = verdict orelse return false;
    const warnings = cache.lookup(project) orelse return false;
    try language.warning_display.write(init.io, warnings);
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
    // The stored text keeps, behind a marker, which of its diagnostics `selka fix` repairs (`rememberFrontendVerdict`).
    try language.warning_display.write(init.io, language.fix_tally.detach(warnings));
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
    var fixed: std.Io.Writer.Allocating = .init(init.gpa);
    defer fixed.deinit();
    for (compilation.diagnostics.items.items) |problem| {
        const rendered = try diagnostic_output.render(init.gpa, problem, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        writer.writer.writeAll(rendered) catch return error.OutOfMemory;
        // The first lines of the diagnostics with a fix go behind the text, so a replay closes with the count a fresh check prints. They
        // are taken from the diagnostics, not from the tally, which is off in a command that does not cover its report.
        if (init.diagnostics == .text and diagnostic_output.carriesFix(problem, compilation.src)) {
            fixed.writer.writeAll(language.fix_tally.firstLine(rendered)) catch return error.OutOfMemory;
            fixed.writer.writeByte('\n') catch return error.OutOfMemory;
        }
    }
    const warnings = writer.toOwnedSlice() catch return error.OutOfMemory;
    defer init.gpa.free(warnings);
    const kept = try language.fix_tally.keep(init.gpa, warnings, fixed.written());
    defer if (kept.ptr != warnings.ptr) init.gpa.free(kept);
    try cache.rememberVerdict(project, init.diagnostics, kept);
}

/// Print the project loader's module-discovery problem and record it in the friction log.
fn reportProblem(init: Context, project: *language.project.Project) !void {
    language.friction_session.noteProject(project);
    const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
    defer init.gpa.free(message);
    try std.Io.File.stderr().writeStreamingAll(init.io, message);
}

fn reportProject(init: Context, compilation: *language.project_compile.Compilation) !void {
    try judgeCopyMoves(init, compilation);
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    var printed: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (compilation.diagnostics.items.items) |problem| {
        if (try reachedTwice(scratch.allocator(), init.io, compilation.src, problem, &printed)) continue;
        language.friction_session.note(problem);
        const message = try diagnostic_output.render(init.gpa, problem, compilation.src, init.diagnostics);
        defer init.gpa.free(message);
        try language.warning_display.write(init.io, message);
    }
}

/// A program that checked has its `W_COPY_MOVE` hints judged against its callers first (F-8): the hints a caller would
/// refuse leave `compilation.diagnostics`, which is what `lint` reads its `L_COPY_MOVE` findings from.
fn judgeCopyMoves(init: Context, compilation: *language.project_compile.Compilation) !void {
    const refused = for (compilation.diagnostics.items.items) |problem| {
        if (problem.severity == .err) break true;
    } else false;
    // A check that judged its hints itself (a session check, FR14b) has left out what a caller would refuse.
    if (compilation.program) |program| if (!refused and !compilation.copy_moves_judged) try dropKeptCopyMoves(init.gpa, compilation.diagnostics.allocator, program, compilation.src, &compilation.diagnostics.items);
}

/// Whether `problem` was already printed for the same file reached by another path (FR14): a project that imports one file
/// by two module names through a symbolic link (selka-protobuf's `protobuf/` links into `lib/`) loads it twice, and each
/// copy reports the same diagnostic under its own path. It is printed once, under the first path. Two diagnostics are
/// the same when their file's real path, line, column, code and message are; one under the same path as the first is
/// printed as it always was, and a path that does not resolve from the working directory is never merged.
fn reachedTwice(a: std.mem.Allocator, io: std.Io, src: language.source.Source, problem: language.diagnostic.Diagnostic, printed: *std.StringHashMapUnmanaged([]const u8)) !bool {
    const at = src.locate(problem.span.start);
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, at.path, a) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    const key = try std.fmt.allocPrint(a, "{s}\x00{d}\x00{d}\x00{s}\x00{s}", .{ real, at.line, at.column, problem.code, problem.message });
    const seen = try printed.getOrPut(a, key);
    if (!seen.found_existing) {
        seen.value_ptr.* = at.path;
        return false;
    }
    return !std.mem.eql(u8, seen.value_ptr.*, at.path);
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
/// The identity every compiler cache and receipt is keyed by: the compiler
/// build's own (`build_identity.zig`), decoded from hexadecimal.
const build_identity: [32]u8 = identity: {
    const text = @import("build_identity").compiler_identity;
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

/// Emit one formatter's result: write it in place, print a unified diff, report
/// the first check difference, or copy canonical bytes to stdout.
fn formatOutput(init: Context, parsed: Parsed, src: language.source.Source, bytes: []const u8, formatted: []const u8, allocator: std.mem.Allocator) !u8 {
    if (parsed.format_write) {
        if (std.mem.eql(u8, formatted, bytes)) return 0;
        try replaceFile(init, parsed.path, formatted);
        return 0;
    }
    if (parsed.format_diff) {
        if (std.mem.eql(u8, formatted, bytes)) return 0;
        const difference = try language.interface_files.unifiedDiff(allocator, parsed.path, bytes, formatted, 400);
        defer allocator.free(difference);
        try std.Io.File.stdout().writeStreamingAll(init.io, difference);
        return 1;
    }
    if (parsed.format_check) {
        if (std.mem.eql(u8, formatted, bytes)) return 0;
        const difference = try formattingDifference(allocator, src, formatted);
        defer allocator.free(difference);
        try init.text(difference);
        return 1;
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, formatted);
    return 0;
}

/// Replace a source file with canonical bytes through a sibling temporary and
/// rename, so a failed format never truncates the input.
fn replaceFile(init: Context, path: []const u8, bytes: []const u8) !void {
    var nonce: [8]u8 = undefined;
    std.Io.random(init.io, &nonce);
    var staging_buffer: [std.fs.max_path_bytes + 32]u8 = undefined;
    const staging = try std.fmt.bufPrint(&staging_buffer, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = staging, .data = bytes });
    std.Io.Dir.rename(.cwd(), staging, .cwd(), path, init.io) catch |err| {
        std.Io.Dir.cwd().deleteFile(init.io, staging) catch return err;
        return err;
    };
}

/// The line `fmt --check` prints for a file whose layout is not canonical: where the first difference is, what the
/// formatter wants there, and the command that repairs it.
fn formattingDifference(allocator: std.mem.Allocator, src: language.source.Source, formatted: []const u8) ![]u8 {
    const location = src.locate(format_difference.firstDifference(src.bytes, formatted));
    const wanted = try format_difference.reason(allocator, src.bytes, formatted);
    defer allocator.free(wanted);
    return std.fmt.allocPrint(allocator, "{s}:{d}:{d}: formatting differs: {s}; `selka fmt --write {s}` repairs it\n", .{
        location.path, location.line, location.column, wanted, location.path,
    });
}

fn formatProject(init: Context, project: *language.project.Project) !u8 {
    var changed: std.ArrayList([]const u8) = .empty;
    defer {
        for (changed.items) |message| init.gpa.free(message);
        changed.deinit(init.gpa);
    }
    for (project.order.items) |module_id| {
        const src = project.modules.items[module_id].src;
        var compilation = try language.Compilation.init(init.gpa, src.path, src.bytes);
        defer compilation.deinit();
        const formatted = compilation.formatModule(init.gpa) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            error.FormatRejected => {
                try report(init, &compilation);
                return 2;
            },
            else => return err,
        };
        defer init.gpa.free(formatted);
        recordWork(init, .parsed_modules, 1, 0);
        if (!std.mem.eql(u8, formatted, src.bytes)) {
            try changed.ensureUnusedCapacity(init.gpa, 1);
            const message = try formattingDifference(init.gpa, src, formatted);
            changed.appendAssumeCapacity(message);
        }
    }
    for (changed.items) |message| try init.text(message);
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

/// `inputs` and the generated entry of a directory check, which the loader reads as the module `name`.
fn withGeneratedEntry(init: Context, inputs: []const GeneratedInput, name: []const u8, source: []const u8) ![]const GeneratedInput {
    const arena = init.arena.allocator();
    const all = try arena.alloc(GeneratedInput, inputs.len + 1);
    @memcpy(all[0..inputs.len], inputs);
    all[inputs.len] = .{ .module = name, .path = try language.project.modulePath(arena, name), .source = source, .manifest_path = "", .manifest_sha256 = "" };
    return all;
}

/// Whether `path` names a directory.
fn isDirectory(io: std.Io, path: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return info.kind == .directory;
}

/// Say why a directory could not be checked, and the exit status of that refusal.
fn directoryRefused(init: Context, path: []const u8, err: language.check_directory.Error) !u8 {
    const message = switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReservedName => try std.fmt.allocPrint(init.gpa, "selka check: {s} holds a module named {s}, the name of the entry a directory check generates; rename that module\n", .{ path, language.check_directory.entry_name }),
        error.ReadFailed, error.NotInsideProject => try std.fmt.allocPrint(init.gpa, "selka check: cannot read the project directory '{s}'\n", .{path}),
    };
    defer init.gpa.free(message);
    try init.text(message);
    return 2;
}

/// Name, on standard error, the files a directory check left out because their names cannot be imported.
fn noteSkippedModules(init: Context, plan: language.check_directory.Plan) !void {
    if (plan.skipped.len == 0) return;
    const names = try std.mem.join(init.gpa, ", ", plan.skipped);
    defer init.gpa.free(names);
    const message = try std.fmt.allocPrint(init.gpa, "check: skipped {d} file{s} whose names are not module names: {s}\n", .{ plan.skipped.len, if (plan.skipped.len == 1) "" else "s", names });
    defer init.gpa.free(message);
    try std.Io.File.stderr().writeStreamingAll(init.io, message);
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
    try reportInvalidation(init, parsed, current, executedStages(), false);
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

/// The cache directory the invocation names, or null for the per-project
/// default: `--cache-dir` first, then `SELKA_FRONTEND_CACHE`. Every persistent
/// store this command opens (frontend entries, checked bodies, the invalidation
/// baseline) nests under it, so naming one directory keeps all of them out of
/// the working directory.
fn requestedCacheBase(init: Context, parsed: Parsed) ?[]const u8 {
    if (parsed.cache_dir) |directory| return directory;
    const variable = init.environ.get("SELKA_FRONTEND_CACHE") orelse return null;
    return if (variable.len == 0) null else variable;
}

/// Resolve the persistent frontend cache directory for this invocation.
/// Precedence: `--no-cache`, then an explicit `--cache-dir` (nested under
/// `frontend/`), then `SELKA_FRONTEND_CACHE` from a parent build driver, then
/// the per-project default. The compiler identity partitions the directory.
fn frontendRoot(init: Context, parsed: Parsed) ?[]const u8 {
    if (parsed.no_cache) return null;
    const base = requestedCacheBase(init, parsed) orelse language.frontend_cache.default_directory;
    if (std.mem.eql(u8, base, language.frontend_cache.default_directory)) return base;
    return std.fs.path.join(init.gpa, &.{ base, frontend_label }) catch null;
}

/// Open the persistent cache on demand; a missing or unwritable directory simply
/// disables reuse, never failing the command.
fn openFrontendCache(init: Context, parsed: Parsed) ?language.frontend_cache.Cache {
    const root = frontendRoot(init, parsed) orelse return null;
    // `&build_identity` points at a process-lifetime constant, so the cache's
    // borrowed identity outlives this frame; a local copy would dangle.
    var cache = language.frontend_cache.Cache.init(init.gpa, init.io, root, &build_identity);
    cache.contract.flags = selka_core.ownershipMode;
    // A joined path is freshly allocated and released by deinit; the default
    // constant is static storage and must not be freed.
    cache.root_owned = root.ptr != language.frontend_cache.default_directory.ptr;
    return cache;
}

/// Resolve the baseline file for invalidation observations.  The path is
/// deliberately independent of the compiler-identity partition so a rebuilt
/// compiler still explains against the previous build's receipt.
fn invalidationBaselinePath(init: Context, parsed: Parsed) ![]const u8 {
    const base = requestedCacheBase(init, parsed) orelse language.frontend_cache.default_directory;
    const basename = std.fs.path.basename(parsed.path);
    const stem = product.sourceStem(basename);
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

/// The entry name a module can have: `basename` with every byte that is not a letter, digit or `_` written as `_`, a `_` put before
/// a leading digit, and `.selka` ending it (`my-prog.selka` is `my_prog.selka`).
fn moduleEntryName(allocator: std.mem.Allocator, basename: []const u8) std.mem.Allocator.Error![]u8 {
    const stem = product.sourceStem(basename);
    const lead: usize = if (stem.len == 0 or std.ascii.isDigit(stem[0])) 1 else 0;
    const name = try allocator.alloc(u8, lead + stem.len + product.source_suffix.len);
    if (lead == 1) name[0] = '_';
    for (stem, 0..) |byte, at| name[lead + at] = if (std.ascii.isAlphanumeric(byte) or byte == '_') byte else '_';
    @memcpy(name[lead + stem.len ..], product.source_suffix);
    return name;
}

/// `E_ENTRY_NAME`: a command that resolves imports needs an entry named like a module (`validEntryBasename`). Says which file, the
/// name to give it, and why; the exit status is the usage status 2.
fn refuseEntryName(init: Context, path: []const u8) !u8 {
    const basename = std.fs.path.basename(path);
    const wanted = try moduleEntryName(init.gpa, basename);
    defer init.gpa.free(wanted);
    const message = try std.fmt.allocPrint(
        init.gpa,
        "{s}:1:1: error[E_ENTRY_NAME]: rename `{s}` to `{s}`: a file that imports must be named like a module " ++
            "(letters, digits and `_`, not starting with a digit, ending in `.selka`); its imports resolve beneath its directory\n",
        .{ path, basename, wanted },
    );
    defer init.gpa.free(message);
    try init.text(message);
    return 2;
}

fn validEntryBasename(basename: []const u8) bool {
    if (!product.isSource(basename)) return false;
    const name = product.chopSource(basename);
    if (!language.project.validName(name)) return false;
    return std.mem.indexOfScalar(u8, name, '.') == null;
}

/// Bind the full Wave-3 contract plus the message the C2 persistence context
/// needs: compiler identity, bootstrap language, target, effects-v3, runtime ABI
/// and the mutation-contract version. Persistence itself is C2; this fingerprint
/// only partitions retained bodies inside the session.
fn semanticCacheContractValue(init: Context) !language.semantic_cache.Contract {
    const allocator = init.arena.allocator();
    var contract = language.semantic_cache.Contract.default;
    const compiler_hex = std.fmt.bytesToHex(build_identity, .lower);
    contract.compiler_identity = try allocator.dupe(u8, &compiler_hex);
    return contract;
}

fn semanticCacheContract(init: Context) ![]const u8 {
    const allocator = init.arena.allocator();
    const contract = try semanticCacheContractValue(init);
    return contract.fingerprint(allocator);
}

/// Resolve the durable checked-body store root from the same shared cache-root
/// option as the frontend cache. `--no-cache` returns null, an explicit
/// `--cache-dir=DIR` (or `SELKA_FRONTEND_CACHE`) nests under `DIR/semantic`, and
/// the default is the per-project `.selka-cache/semantic` leaf.
fn semanticRoot(init: Context, parsed: Parsed) ?[]const u8 {
    if (parsed.no_cache) return null;
    const default_directory = language.semantic_cache.default_store_directory;
    const base = requestedCacheBase(init, parsed) orelse return default_directory;
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
/// 16 MiB budget; `SELKA_SEMANTIC_BUDGET` is an opt-in profiling control used
/// by the large-project harness and never changes language semantics.
fn semanticBudget(init: Context) usize {
    const raw = init.environ.get("SELKA_SEMANTIC_BUDGET") orelse return 16 * 1024 * 1024;
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
        return refuseEntryName(init, parsed.path);
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
    // One request is one session of the front end, over the caches the process keeps between requests.
    var session = selka_core.frontend.Session.init(init.gpa, init.io, try sessionRootOf(request_init, request));
    defer session.deinit();
    session.setHoleTraps(false);
    session.setReportFormat(init.diagnostics);
    session.validationOnly();
    session.judgeCopyMoves();
    session.setProfile(init.timings);
    session.lendCaches(&cache.syntax, &cache.functions);
    request.session = &session;
    var observation: RunObservation = .{ .executed = executedStages() };
    observation.work.command = @tagName(request.command);
    request_init.observation = &observation;
    const before = cache.syntax.statistics;
    const status = listModulesWithCache(request_init, request, &cache.semantic, &cache.functions) catch |err| {
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
        const count = cache.functions.statistics.rejections.total[@backingInt(why)];
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

/// Ownership proofs may omit only bodies the semantic planner has revalidated.
/// Drop each `W_COPY_MOVE` hint whose advice, a `from` result, a caller in the checked program would refuse because it
/// keeps the result (F-8): the copy that hint names is the one that caller needs. The hint names the function's
/// parameter; the function is the one whose body holds the hint.
/// A `W_COPY_FOR_STORE` warning that stays gains its callers' `own ` marks, allocated with `owner` (the diagnostics' arena).
fn dropKeptCopyMoves(gpa: std.mem.Allocator, owner: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, diagnostics: *std.ArrayList(language.diagnostic.Diagnostic)) !void {
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    const stores_marks = try storesKept(scratch.allocator(), program, source, diagnostics.items);
    const returns_kept = try returnsKept(scratch.allocator(), program, source, diagnostics.items);
    // The functions named as values: a `from` result is refused for one (`E_VIEW_FUNCTION_VALUE`), whatever its callers do.
    const named = try scratch.allocator().alloc(bool, program.functions.len);
    @memset(named, false);
    for (program.nodes) |node| switch (node.data) {
        .function_value => |function| if (@backingInt(function) < named.len) {
            named[@backingInt(function)] = true;
        },
        else => {},
    };
    var store: usize = 0;
    var returned: usize = 0;
    var index: usize = 0;
    while (index < diagnostics.items.len) {
        const item = diagnostics.items[index];
        const kept = if (std.mem.eql(u8, item.code, language.copy_for_store.code)) found: {
            store += 1;
            const marks = stores_marks[store - 1] orelse break :found true;
            if (item.provenance.fix) |fix| diagnostics.items[index].provenance.fix = try language.copy_for_store.withMarks(owner, fix, marks);
            break :found false;
        } else if (std.mem.eql(u8, item.code, language.copy_from_repair.code)) found: {
            returned += 1;
            break :found returns_kept[returned - 1];
        } else std.mem.eql(u8, item.code, "W_COPY_MOVE") and try copyMoveKept(scratch.allocator(), program, source, item, named);
        if (kept) {
            _ = diagnostics.orderedRemove(index);
            continue;
        }
        index += 1;
    }
    // A `W_COPY_RETURNED` warning that stays stands for the `W_COPY_MOVE` hint beside it.
    language.copy_from_repair.dropHintsBeside(diagnostics);
    // A `W_COPY_FOR_STORE` warning of a list parameter that stays stands for the loop hint at its copy.
    language.copy_loop_repair.dropHintsBeside(diagnostics);
}

/// For each `W_COPY_RETURNED` warning, in order, whether it is left out: a caller the ownership check refuses with the result
/// declared `from` the parameter, for any reason (`callerFacts` with a `strict` target, as a cached check asks).
fn returnsKept(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, items: []const language.diagnostic.Diagnostic) ![]const bool {
    var hints: std.ArrayList(language.semantic_summary.HintTarget) = .empty;
    var resolved: std.ArrayList(bool) = .empty;
    for (items) |item| {
        if (!std.mem.eql(u8, item.code, language.copy_from_repair.code)) continue;
        const target = storeTarget(program, item);
        try resolved.append(a, target != null);
        const found = target orelse continue;
        try hints.append(a, .{ .callee = found.callee, .result = true, .position = found.position, .strict = true });
    }
    const facts = try selka_core.callerFacts(a, program, source, hints.items);
    const kept = try a.alloc(bool, resolved.items.len);
    var at: usize = 0;
    for (resolved.items, kept) |found, *slot| {
        if (!found) {
            slot.* = true;
            continue;
        }
        slot.* = for (facts[at]) |fact| {
            if (fact.keeps) break true;
        } else false;
        at += 1;
    }
    return kept;
}

/// For each `W_COPY_FOR_STORE` warning, in order, the `own ` marks its repair writes in the callers, or null when it is left
/// out: no caller, a caller that passes anything but a new value or a markable name or names the function as a value
/// (`copy_for_store.acceptedByCallers`), or a caller the ownership check refuses with the parameter `own` (`callerFacts`, as
/// a cached check asks). All of them are judged in one pass over the program.
fn storesKept(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, items: []const language.diagnostic.Diagnostic) ![]const ?[]const u32 {
    var targets: std.ArrayList(language.copy_for_store.Target) = .empty;
    var hints: std.ArrayList(language.semantic_summary.HintTarget) = .empty;
    var resolved: std.ArrayList(bool) = .empty;
    for (items) |item| {
        if (!std.mem.eql(u8, item.code, language.copy_for_store.code)) continue;
        const target = storeTarget(program, item);
        try resolved.append(a, target != null);
        const found = target orelse continue;
        try targets.append(a, found);
        try hints.append(a, .{ .callee = found.callee, .result = false, .position = found.position, .store = true });
    }
    if (targets.items.len == 0) {
        // Nothing resolved: every warning (if any) is left out, and the program is not walked.
        const none = try a.alloc(?[]const u32, resolved.items.len);
        @memset(none, null);
        return none;
    }
    const accepted = try language.copy_for_store.acceptedByCallers(a, program, targets.items);
    const facts = try selka_core.callerFacts(a, program, source, hints.items);
    const kept = try a.alloc(?[]const u32, resolved.items.len);
    var at: usize = 0;
    for (resolved.items, kept) |found, *slot| {
        if (!found) {
            slot.* = null;
            continue;
        }
        const keeper = for (facts[at]) |fact| {
            if (fact.keeps) break true;
        } else false;
        slot.* = if (keeper) null else accepted[at];
        at += 1;
    }
    return kept;
}

/// The function and parameter of a `W_COPY_FOR_STORE` or `W_COPY_RETURNED` warning: the function declared last before it,
/// and its parameter the message names.
fn storeTarget(program: language.typed.Program, item: language.diagnostic.Diagnostic) ?language.copy_for_store.Target {
    const judged = language.copy_for_store.judged(item.code, item.message) orelse
        language.copy_from_repair.judged(item.code, item.message) orelse return null;
    var nearest: ?usize = null;
    for (program.functions, 0..) |function, index| {
        if (function.type_arguments.len != 0 or function.declaration.start > item.span.start) continue;
        if (nearest) |best| if (program.functions[best].declaration.start >= function.declaration.start) continue;
        nearest = index;
    }
    const callee = nearest orelse return null;
    const function = program.functions[callee];
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count], 0..) |local, slot| {
        if (std.mem.eql(u8, local.name, judged.parameter)) return .{ .callee = callee, .position = slot };
    }
    return null;
}

/// Whether a `W_COPY_MOVE` hint's repair would cost a caller in the program a copy, so the hint is left out: the hint
/// that asks for `from PARAMETER` when a caller keeps the function's result (F-8, F-15, F-24) or the function is one of the
/// `named` as a value, and the hint that asks for `for x in own PARAMETER` when a caller still needs the list it passes there
/// (F-27).
fn copyMoveKept(a: std.mem.Allocator, program: language.typed.Program, source: language.source.Source, item: language.diagnostic.Diagnostic, named: []const bool) !bool {
    const judged = language.needless_copy.judgedByCallers(item.code, item.message) orelse return false;
    const parameter = judged.parameter;
    // The hint's function is the one declared last before it (functions do not nest); its checked body's statement is not
    // always the source body, whose span missed eight such hints on the port (FR14b).
    var nearest: ?usize = null;
    for (program.functions, 0..) |function, index| {
        if (function.type_arguments.len != 0 or function.declaration.start > item.span.start) continue;
        if (nearest) |best| if (program.functions[best].declaration.start >= function.declaration.start) continue;
        nearest = index;
    }
    const callee = nearest orelse return false;
    // A function named as a value cannot declare its result `from` a parameter (`E_VIEW_FUNCTION_VALUE`).
    if (judged.form == .result and named[callee]) return true;
    const function = program.functions[callee];
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    const position = for (function.scope.locals[0..count], 0..) |local, slot| {
        if (std.mem.eql(u8, local.name, parameter)) break slot;
    } else return false;
    const keeper = if (judged.form == .result)
        try selka_core.keepingCallerOf(a, program, source, callee, &.{position})
    else
        try selka_core.keepingArgumentCallerOf(a, program, source, callee, position);
    return keeper != null;
}

fn ownershipCheck(init: Context, parsed: Parsed, program: language.typed.Program, source: language.source.Source) !bool {
    if (!checksOwnership(parsed.command)) return true;
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    var messages: std.ArrayList(u8) = .empty;
    // A program the refused check recovered (its failed bodies stood in) is validated without the proof store: nothing it
    // proves may be recorded.
    if (selka_core.recovered_ownership.recovered(program)) {
        const valid = try selka_core.recovered_ownership.validate(scratch.allocator(), init.gpa, program, source, init.diagnostics, &messages);
        try std.Io.File.stderr().writeStreamingAll(init.io, messages.items);
        return valid;
    }
    const local = if (parsed.ownership_cache == null) try openOwnershipCache(init, parsed) else null;
    defer closeOwnershipCache(parsed, local);
    const cache = parsed.ownership_cache orelse local;
    const valid = if (cache) |owned|
        try owned.validate(scratch.allocator(), program, source, init.diagnostics, &messages)
    else
        try selka_core.validateOwnership(scratch.allocator(), init.gpa, program, source, init.diagnostics, &messages);
    try std.Io.File.stderr().writeStreamingAll(init.io, messages.items);
    return valid;
}
