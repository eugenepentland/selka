//! The `selka` commands that build, run or test code, on the new core (S5-A,
//! NEW-CORE-S5-CLI-1): `build` (and `build --run`), `run`, `run-project`, `test`,
//! and the developer commands `dump-ir`, `dump-typed` and `coverage` (S5-D8). The
//! old back end's commands and flags are refused by name with what replaces them
//! (NEW-CORE-S5-RETIRED-1). `src/main.zig` asks `dispatch` first; null hands the
//! command to the front-end commands it still owns.
const std = @import("std");
const process_exit = @import("selka").process_exit;
const allocation_contract = @import("allocation_contract.zig");
const core_main = @import("main.zig");
/// The command-line parser of `build` and `run`, which `selka packages` asks which word of the line a command refuses.
pub const cli_args = @import("cli_args.zig");
const cli_run = @import("cli_run.zig");
const pipeline = @import("pipeline.zig");
const cost_command = @import("cost_command.zig");
const juice_command = @import("juice/command.zig");
const engine_command = @import("engine/command.zig");
/// Refuse retired ownership selectors before either command dispatcher runs.
pub const prepareArguments = @import("cli_ownership.zig").prepare;

/// The front end's session: one command's project graph, source files and reuse caches (`selka check` of a project runs on it).
pub const frontend = @import("frontend.zig");
/// An entry's project settings (its root, module name and `selka.json`), resolved before its graph loads (`selka rename`).
pub const project_entry = @import("project_entry.zig");
/// The command-scoped compiler-store policy: resolves the per-user default store into the command's environment, or disables sharing.
pub const compilerSharing = @import("compiler_sharing.zig").prepare;
/// Source ownership validation shared with the full front-end check command.
pub const validateOwnership = @import("single_owner.zig").validate;
/// The caller that keeps a function's result, which a `from` result would be lent to (F-8): `check` drops a
/// `W_COPY_MOVE` hint for a function that has one.
pub const keepingCallerOf = @import("single_owner.zig").keepingCallerOf;
/// The first caller that still needs the argument it passes to a parameter (F-27; `single_owner.keepingArgumentCallerOf`).
pub const keepingArgumentCallerOf = @import("single_owner.zig").keepingArgumentCallerOf;
/// Every caller's answer for each of several hints at once (`single_owner.callerFacts`): the cold check judges the
/// `W_COPY_FOR_STORE` warnings with it in one pass over the program.
pub const callerFacts = @import("single_owner.zig").callerFacts;
/// The ownership validation of a refused check's recovered program (failed bodies stood in), and the test for one.
pub const recovered_ownership = @import("recovered_ownership.zig");
/// Core's refusals of one interface-oracle check, located in module sources (`selka interfaces oracle`, W9).
pub const interface_ownership = @import("interface_ownership.zig");
/// Environment marker a directory `selka test` sets on the child compilers it
/// starts, so the front end can tell an internal child from the user's command.
pub const internal_child_hint = @import("tool_ticket.zig").hint;
/// The directory a test build reads the system libraries below ("" in every ordinary compiler), for `selka --version`.
pub const builtSystemRoot = @import("tool_identity.zig").builtSystemRoot;

/// Apply the `stores` of the project of an entry or directory to the command's environment (FR8); true after
/// printing a refusal. The front end's commands call it before they open a store, as `build`, `run` and `test` do.
pub const applyStores = cli_run.applyStores;
/// Starting a child process without copying this one; `selka packages` starts its project command through it.
pub const process_spawn = @import("process_spawn.zig");
/// Per-function checked ownership proofs for frontend command hosts.
pub const OwnershipCache = @import("ownership_cache.zig").Cache;
/// The scope an entry's ownership proofs are kept under (`ownership_cache.scopeOf`).
pub const ownershipScope = @import("ownership_cache.zig").scopeOf;
/// Where the engines find the compiler's shared tier (`engine_sharing.zig`).
pub const engine_sharing = @import("engine_sharing.zig");

/// The shared stage store, for `selka cache gc|configure --kind stages` (`src/cache_command.zig`).
pub const stage_store = @import("stage_store.zig");
/// Mode identity shared by frontend verdicts and ownership proofs.
pub const ownershipMode = @import("ownership_cache.zig").modeName;

/// What stops a command before it has a status: memory, an unwritable stream, or a
/// test the runner cannot encode.
pub const Error = core_main.Error || cost_command.Error || juice_command.Error || engine_command.Error;

/// A retired command or flag and the one-line reason the CLI gives.
const Retirement = struct { name: []const u8, message: []const u8 };

const qbe_emission = "QBE IL emission was retired with the old back end (S5); the compiler emits LLVM: use `selka build FILE.selka -o OUT --emit-llvm PATH`";
const host_retired = "host functions, libraries and providers were retired (S5-D5); use `extern` with `--link FILE.c` for C interop";
const runtime_retired = "runtime selection was retired (S5-D4): reference counting was removed; checked ownership is the only memory model; drop the flag";
const module_build_retired = "per-module QBE builds were retired (S5); `selka build` compiles and caches one unit per module";

/// Commands the new core does not have, with what replaces them.
const retired_commands = [_]Retirement{
    .{ .name = "invoke", .message = "`selka invoke` was retired with host functions (S5-D5); call the function from a `main` or a test" },
    .{ .name = "emit-qbe", .message = qbe_emission },
    .{ .name = "emit-project-qbe", .message = qbe_emission },
    .{ .name = "emit-runtime", .message = "the prebuilt QBE runtime archive was retired (S5); a build compiles the new core's runtime once per machine" },
    .{ .name = "dump-bytecode", .message = "the bytecode IR was retired (S5); `selka dump-ir FILE.selka` prints the Core IR" },
    .{ .name = "compile-module", .message = module_build_retired },
    .{ .name = "link-modules", .message = module_build_retired },
    .{ .name = "native-test-graph", .message = "the old test runner's internal commands were retired (S5); `selka test` runs tests on the new core" },
    .{ .name = "native-test-compile", .message = "the old test runner's internal commands were retired (S5); `selka test` runs tests on the new core" },
    .{ .name = "bench-promote", .message = "benchmark promotion was dropped (S5-D6)" },
};

/// Flags any command refuses, before `--`.
const retired_flags = [_]Retirement{
    .{ .name = "--gc-runtime", .message = runtime_retired },
    .{ .name = "--gc-stress", .message = "the tracing collector and its stress mode were retired (S5-D4); drop the flag" },
    .{ .name = "--rc-runtime", .message = runtime_retired },
    .{ .name = "--legacy-sharing", .message = "legacy sharing was retired (S5-D4): value semantics is the only mode; drop the flag" },
    .{ .name = "--value-semantics", .message = "--value-semantics was retired (S5-D4): value semantics is always on; drop the flag" },
    .{ .name = "--library", .message = host_retired },
    .{ .name = "--provider", .message = host_retired },
    .{ .name = "--link-library", .message = host_retired },
    .{ .name = "--library-path", .message = host_retired },
    .{ .name = "--unchecked", .message = "--unchecked was removed: every build keeps overflow, cast and bounds checks so optimization never changes a program's result" },
    .{ .name = "--explain-ownership", .message = "--explain-ownership read the old back end's ownership lowering (retired, S5); `selka build --stats` reports the new core's" },
};

/// Flags `selka test` refuses that its new runner dropped (S5-D6).
const dropped_test_flags = [_][]const u8{
    "--pure-skip",        "--diagnostics",  "--max-calls",     "--bench",        "--bench-only",    "--bench-output",
    "--bench-baseline",   "--bench-policy", "--bench-profile", "--bench-warmup", "--bench-batches", "--bench-batch-ms",
    "--bench-timeout-ms",
};

/// `build` and `run` flags `selka test` has no use for, with the reason (S5-B2).
const test_only_retired = [_]Retirement{
    .{ .name = "--report", .message = "`selka test --report` printed the old runner's work report (retired, S5-B2); `--json` reports each test, `cached` for a replayed receipt" },
    .{ .name = "--timings", .message = "`selka test --timings` was retired with the old runner (S5-B2); `selka run FILE.selka --timings` times one program" },
    .{ .name = "--explain-invalidation", .message = "--explain-invalidation compared the old back end's nine stage fingerprints (retired, S5-B2); `--json` reports each test, `cached` for a replayed receipt" },
};

/// Why `selka test` refuses the flag `name` (its `--flag` part): a flag `build` and
/// `run` retire with a pointer `test` cannot follow says what `test` offers instead.
fn testRefusal(arg: []const u8) ?[]const u8 {
    const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
    for (test_only_retired) |retired| if (std.mem.eql(u8, name, retired.name)) return retired.message;
    return cli_args.unported(arg);
}

// spec-case: NEW-CORE-S5-RETIRED-1
test "test refusals point at what test offers, not at flags test also refuses" {
    try std.testing.expect(std.mem.indexOf(u8, testRefusal("--explain-invalidation").?, "`--json`") != null);
    try std.testing.expect(std.mem.indexOf(u8, testRefusal("--explain-invalidation").?, "`--report`") == null);
    try std.testing.expect(std.mem.indexOf(u8, testRefusal("--report").?, "`--json`") != null);
    try std.testing.expect(testRefusal("--json") == null);
    try std.testing.expect(std.mem.indexOf(u8, cli_args.unported("--explain-invalidation").?, "`--report`") != null);
}

/// Run `args` (argv, the program name first) when it names a command of the new
/// core or a retired one, returning its exit status; null leaves it to the caller.
pub fn dispatch(init: std.process.Init, args: []const []const u8) Error!?u8 {
    if (args.len < 2) return null;
    const command = args[1];
    if (std.mem.eql(u8, command, "juice")) {
        const status = try juice_command.run(init, args[2..]);
        return status;
    }
    if (std.mem.eql(u8, command, "engine")) {
        const status = try engine_command.run(init, args[2..]);
        return status;
    }
    if (std.mem.eql(u8, command, "native")) return @import("native_command.zig").run(init, args[2..]);
    const rest = args[2..];
    if (std.mem.eql(u8, command, "check")) {
        // `--examples` checks the docstring examples the way `selka test` compiles them.
        for (rest) |arg| if (std.mem.eql(u8, arg, "--examples")) {
            const result = try @import("example_check.zig").run(init, rest);
            return result;
        };
        // Developer profiling keeps its dedicated output; ordinary checks retain
        // the full front-end parser, library support and diagnostic options.
        for (rest) |arg| if (std.mem.eql(u8, arg, "--ownership-audit") or std.mem.eql(u8, arg, "--typed") or std.mem.eql(u8, arg, "--stats") or std.mem.eql(u8, arg, "--local-stdlib")) {
            const result = try @import("check_command.zig").run(init, rest);
            return result;
        };
    }
    const status = status: {
        for (retired_commands) |retired| if (std.mem.eql(u8, command, retired.name)) break :status try refuse(init, command, retired.message);
        if (retiredFlag(rest)) |retired| break :status try refuse(init, command, retired.message);
        if (std.mem.eql(u8, command, "build")) break :status if (developerBuild(rest)) try core_main.buildCommand(init, rest) else try buildCommand(init, rest);
        if (std.mem.eql(u8, command, "run") or std.mem.eql(u8, command, "run-project")) break :status try cli_run.runCommand(init, command, rest);
        if (std.mem.eql(u8, command, "cost")) break :status try cost_command.run(init, rest);
        if (std.mem.eql(u8, command, "do")) break :status try @import("cli_do.zig").run(init, rest);
        if (std.mem.eql(u8, command, "test")) break :status try testCommand(init, rest);
        for ([_][]const u8{
            "dump-ir",
            "dump-typed",
            "coverage",
            "validate-certificates",
            "mutate-certificates",
            "link-certificates",
            "validate-fact-certificates",
            "mutate-fact-certificates",
            "verify-ir",
            "template-stand-ins",
        }) |name| if (std.mem.eql(u8, command, name)) break :status try core_main.developer(init, args);
        return null;
    };
    return status;
}

/// The same default release cost output appended by the interface CLI.
pub fn interfaceCost(init: std.process.Init, path: []const u8) Error!cost_command.Output {
    return cost_command.output(init, .{ .path = path });
}

/// One `cost --sites` row, read by the lint rule that names loop-depth sites.
pub const CostSite = @import("cost.zig").Site;

/// The one-line repair hint of a `cost --sites` row's kind, for the lint rule's rows.
pub fn costSiteHint(kind: @import("cost.zig").SiteKind) []const u8 {
    return @import("cost.zig").hint(kind);
}

/// What one cost-sites analysis gave a lint run: its rows, or the first error code of why it gave none.
pub const SitesAnalysis = struct {
    sites: []const CostSite = &.{},
    /// Set when the analysis could not be made: the first `error[CODE]` of its diagnostics, `none` when they name no code,
    /// or the name of the Zig error when it ended without diagnostics. Null when the analysis ran, with rows or without.
    failed: ?[]const u8 = null,
};

/// The cost-site rows of one entry, for a lint run's `L_ALLOC_IN_LOOP` and `L_COPY_IN_LOOP` rules: the same analysis as
/// `cost --sites`, with LLVM left out and nothing rendered, and the reason when there are no rows because it failed (a
/// program with no `main` fails with `E_MAIN`, which the caller knows from the checked program).
pub fn analyzeCostSites(init: std.process.Init, path: []const u8, cache: []const u8) SitesAnalysis {
    const output = cost_command.outputWithQuery(init, .{ .path = path, .json = true }, .{ .section = .sites, .reader = true, .cache = cache }) catch |err| return .{ .failed = @errorName(err) };
    if (output.status != 0) return .{ .failed = firstErrorCode(output.diagnostics) orelse "none" };
    return .{ .sites = output.sites };
}

/// The code of the first `error[CODE]` in rendered diagnostics, or null when there is none.
pub fn firstErrorCode(diagnostics: []const u8) ?[]const u8 {
    const marker = "error[";
    const start = (std.mem.indexOf(u8, diagnostics, marker) orelse return null) + marker.len;
    const length = std.mem.indexOfScalar(u8, diagnostics[start..], ']') orelse return null;
    return if (length == 0) null else diagnostics[start..][0..length];
}

test "firstErrorCode names the first coded error of rendered diagnostics" {
    try std.testing.expectEqualStrings("E_MAIN", firstErrorCode("a.selka:1:1: error[E_MAIN]: no entry\n  note: error[E_OTHER]\n").?);
    try std.testing.expect(firstErrorCode("error: cannot read a.selka: FileNotFound\n") == null);
    try std.testing.expect(firstErrorCode("") == null);
    try std.testing.expect(firstErrorCode("error[] x") == null);
}

/// The cost-site rows of the functions a program's discovered tests reach, for a lint run whose entry has no `main`
/// (a test file): `analyzeCostSites` follows only what `main` reaches. A caller that cannot use the rows reads a failure
/// as "no sites".
pub fn collectRootSites(a: std.mem.Allocator, program: @import("selka").typed.Program, src: @import("selka").source.Source, roots: []const @import("selka").typed.FunctionId, path: []const u8) Error![]const CostSite {
    return cost_command.rootSites(a, .{ .program = program, .src = src }, roots, path);
}

/// Whether a `build` names one of the core's developer-only switches, which the
/// core's own build command answers (S5-D8: `selka-core` merged into `selka`).
fn developerBuild(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--sabotage-facts") or std.mem.eql(u8, arg, "--generic-vectors") or std.mem.startsWith(u8, arg, "--trap-frames=")) return true;
    }
    return false;
}

/// The retirement a flag before `--` names, or null.
fn retiredFlag(args: []const []const u8) ?Retirement {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--")) return null;
        const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
        for (retired_flags) |retired| if (std.mem.eql(u8, name, retired.name)) return retired;
    }
    return null;
}

fn refuse(init: std.process.Init, command: []const u8, message: []const u8) Error!u8 {
    try write(init, try std.fmt.allocPrint(init.arena.allocator(), "selka {s}: {s}\n", .{ command, message }));
    return 2;
}

fn write(init: std.process.Init, text: []const u8) Error!void {
    // The build's report carries the check's warnings, some of which are counted rather than printed (`warning_display.zig`).
    @import("selka").warning_display.write(init.io, text) catch return error.WriteFailed;
}

const build_usage =
    \\usage: selka build <file.selka> (-o <output> | --run [run options] [-- ARGS...]) [--release | --unoptimized | --optimize-debug | --debug-o0] [--link FILE.c]... [--emit-llvm PATH] [--emit-certificates DIR]
    \\Default: lean debug (Core's facts passes, LLVM code generation at -O2 minus its costly passes); --mode Debug is the default.
    \\--debug-o0 selects LLVM -O0 (the cheapest cold build); --optimize-debug selects LLVM -O2; --unoptimized disables Core and LLVM optimization; --release optimizes the whole program.
    \\       [--cache-dir DIR] [--no-cache] [--local-stdlib] [--zig PATH] [--report] [--cache-report] [--verify-cache] [--stats] [--diagnostics=text|json]
    \\       [--cpu native|x86-64-v3] [--target NAME] [--device NAME] [--linker-script FILE.ld] [--include DIR]... (a device build: selka.json's target, device and devices give them; -o X.bin or X.uf2 writes an image)
    \\Checked ownership is the default: assignments move, parameters borrow, and copy(value) duplicates storage.
    \\
;

/// `selka build FILE.selka -o OUT` and `build --run`.
fn buildCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = try cli_run.parseRequest(init, .build, args, build_usage) orelse return 2;
    if (request.run != null) return cli_run.run(init, request, "build");
    // CLI-INPUT-REFUSED-1: an entry that cannot be read is refused by name, as `run` refuses it.
    if (try cli_run.unreadable(init, "build", request.path)) |message| {
        try write(init, message);
        return 2;
    }
    // The project's `target` and chosen device (MCU-C1), under the command line's flags.
    var device_request = request;
    if (try @import("device_build.zig").apply(init, &device_request)) |line| {
        try cli_run.writeStderr(init, line);
        return 2;
    }
    var options = device_request.build;
    if (request.no_cache) options.cache = try cli_run.privateCache(init, options.cache);
    defer if (request.no_cache) cli_run.discard(init.io, options.cache);
    var report: std.ArrayList(u8) = .empty;
    const compilation_init = try @import("compiler_sharing.zig").prepare(init, request.no_cache or options.show.verify_cache);
    // `selka build` returns to process exit after writing its report: the build may leave its last frees to the kernel (`process_exit.zig`).
    process_exit.declareLast();
    defer process_exit.withdraw();
    const status = pipeline.build(compilation_init, request.path, options, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError, error.Unsupported => 1,
        error.PolicyDenied => 3,
        error.ConfigurationFailed, error.ToolFailed, error.WriteFailed, error.InvalidIr, error.CacheMiss => failed: {
            try @import("build_failure.zig").note(init.arena.allocator(), &report, err, options.cache);
            break :failed 2;
        },
    };
    // A device's image (`.bin`, `.uf2`) is made from the ELF the build linked.
    const imaged = if (status == 0) try @import("device_build.zig").writeImage(compilation_init, options) else null;
    if (imaged) |line| try report.appendSlice(init.arena.allocator(), line);
    try write(init, report.items);
    return if (imaged != null) 2 else status;
}

/// `selka test`: the new core's runner (`test_runner.zig`), with the old CLI's
/// `--flag=VALUE` spellings, `--qbe` ignored and `--whole-program` accepted (S5-D6).
fn testCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const a = init.arena.allocator();
    var normalized: std.ArrayList([]const u8) = .empty;
    // A later `--zig` wins over the environment's.
    try normalized.appendSlice(a, &.{ "--zig", cli_run.zigPath(init) });
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const name = arg[0..split];
        for (dropped_test_flags) |dropped| if (std.mem.eql(u8, name, dropped)) {
            return refuse(init, "test", try std.fmt.allocPrint(a, "{s} was dropped with the old test runner (S5-D6)", .{name}));
        };
        if (testRefusal(arg)) |message| return refuse(init, "test", message);
        // Tests run, so only the host target takes them; it is the default, so naming it changes nothing.
        if (std.mem.eql(u8, name, "--target")) {
            const value = if (split < arg.len) arg[split + 1 ..] else if (index + 1 < args.len) args[index + 1] else "";
            if (split == arg.len) index += 1;
            const chosen = @import("target.zig").byName(value) orelse return refuse(init, "test", try cli_args.unknownTarget(a, value));
            if (!chosen.runsHere()) return refuse(init, "test", try cli_args.onlyBuilds(a, chosen.name));
            continue;
        }
        if (std.mem.eql(u8, arg, "--whole-program")) continue;
        if (std.mem.eql(u8, arg, "--engine-report")) {
            @import("selka").engine_session.requestReport();
            continue;
        }
        if (std.mem.eql(u8, name, "--qbe")) {
            if (split == arg.len) index += 1;
            continue;
        }
        // The core reads `--jobs=N` and `--max-steps=N` itself; any other `--flag=VALUE`
        // is split into the `--flag VALUE` it reads.
        const joined = std.mem.eql(u8, name, "--jobs") or std.mem.eql(u8, name, "--max-steps");
        if (split < arg.len and std.mem.startsWith(u8, arg, "--") and !joined) {
            try normalized.appendSlice(a, &.{ name, arg[split + 1 ..] });
            continue;
        }
        try normalized.append(a, arg);
    }
    // The compiler keeps its own address-space ceiling for the whole run: checking,
    // lowering, the `zig cc` builds and the in-process roots of a directory run are
    // all bounded by it. Only the test processes get the caller's address space back,
    // as each is spawned (`process_spawn.Options.address_space`); each lowers it to
    // its byte ceiling (NEW-CORE-S4-MEMORY-1).
    const status = try core_main.testCommand(init, normalized.items);
    return status;
}

/// Append Core allocation errors for lint; validation-only commands do not call this.
pub fn checkAllocationContracts(
    a: std.mem.Allocator,
    program: @import("selka").typed.Program,
    source: @import("selka").source.Source,
    sink: *@import("selka").diagnostic.Sink,
) std.mem.Allocator.Error!void {
    for (try allocation_contract.collectProgram(a, program, source)) |failure| {
        try sink.items.append(sink.allocator, try allocation_contract.diagnostic(a, failure));
    }
}
