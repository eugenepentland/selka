//! The `mylang` commands that build, run or test code, on the new core (S5-A,
//! NEW-CORE-S5-CLI-1): `build` (and `build --run`), `run`, `run-project`, `test`,
//! and the developer commands `dump-ir`, `dump-typed` and `coverage` (S5-D8). The
//! old back end's commands and flags are refused by name with what replaces them
//! (NEW-CORE-S5-RETIRED-1). `src/main.zig` asks `dispatch` first; null hands the
//! command to the front-end commands it still owns.
const std = @import("std");
const core_main = @import("main.zig");
const cli_args = @import("cli_args.zig");
const cli_run = @import("cli_run.zig");
const pipeline = @import("pipeline.zig");
const cost_command = @import("cost_command.zig");
const juice_command = @import("juice/command.zig");

/// What stops a command before it has a status: memory, an unwritable stream, or a
/// test the runner cannot encode.
pub const Error = core_main.Error || cost_command.Error || juice_command.Error;

/// A retired command or flag and the one-line reason the CLI gives.
const Retirement = struct { name: []const u8, message: []const u8 };

const qbe_emission = "QBE IL emission was retired with the old back end (S5); the compiler emits LLVM: use `mylang build FILE.my -o OUT --emit-llvm PATH`";
const host_retired = "host functions, libraries and providers were retired (S5-D5); use `extern` with `--link FILE.c` for C interop";
const runtime_retired = "runtime selection was retired (S5-D4): one-count reference counting is the only memory model; drop the flag";
const module_build_retired = "per-module QBE builds were retired (S5); `mylang build` compiles and caches one unit per module";

/// Commands the new core does not have, with what replaces them.
const retired_commands = [_]Retirement{
    .{ .name = "invoke", .message = "`mylang invoke` was retired with host functions (S5-D5); call the function from a `main` or a test" },
    .{ .name = "emit-qbe", .message = qbe_emission },
    .{ .name = "emit-project-qbe", .message = qbe_emission },
    .{ .name = "emit-runtime", .message = "the prebuilt QBE runtime archive was retired (S5); a build compiles the new core's runtime once per machine" },
    .{ .name = "dump-bytecode", .message = "the bytecode IR was retired (S5); `mylang dump-ir FILE.my` prints the Core IR" },
    .{ .name = "compile-module", .message = module_build_retired },
    .{ .name = "link-modules", .message = module_build_retired },
    .{ .name = "native-test-graph", .message = "the old test runner's internal commands were retired (S5); `mylang test` runs tests on the new core" },
    .{ .name = "native-test-compile", .message = "the old test runner's internal commands were retired (S5); `mylang test` runs tests on the new core" },
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
    .{ .name = "--explain-ownership", .message = "--explain-ownership read the old back end's ownership lowering (retired, S5); `mylang build --stats` reports the new core's" },
};

/// Flags `mylang test` refuses that its new runner dropped (S5-D6).
const dropped_test_flags = [_][]const u8{
    "--pure-skip",        "--diagnostics",  "--max-calls",     "--bench",        "--bench-only",    "--bench-output",
    "--bench-baseline",   "--bench-policy", "--bench-profile", "--bench-warmup", "--bench-batches", "--bench-batch-ms",
    "--bench-timeout-ms",
};

/// `build` and `run` flags `mylang test` has no use for, with the reason (S5-B2).
const test_only_retired = [_]Retirement{
    .{ .name = "--report", .message = "`mylang test --report` printed the old runner's work report (retired, S5-B2); `--json` reports each test, `cached` for a replayed receipt" },
    .{ .name = "--timings", .message = "`mylang test --timings` was retired with the old runner (S5-B2); `mylang run FILE.my --timings` times one program" },
    .{ .name = "--explain-invalidation", .message = "--explain-invalidation compared the old back end's nine stage fingerprints (retired, S5-B2); `--json` reports each test, `cached` for a replayed receipt" },
};

/// Why `mylang test` refuses the flag `name` (its `--flag` part): a flag `build` and
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
    try std.testing.expect(std.mem.indexOf(u8, testRefusal("--friction-log=x").?, "mylang check") != null);
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
    const rest = args[2..];
    const status = status: {
        for (retired_commands) |retired| if (std.mem.eql(u8, command, retired.name)) break :status try refuse(init, command, retired.message);
        if (retiredFlag(rest)) |retired| break :status try refuse(init, command, retired.message);
        if (std.mem.eql(u8, command, "build")) break :status if (developerBuild(rest)) try core_main.buildCommand(init, rest) else try buildCommand(init, rest);
        if (std.mem.eql(u8, command, "run") or std.mem.eql(u8, command, "run-project")) break :status try cli_run.runCommand(init, command, rest);
        if (std.mem.eql(u8, command, "cost")) break :status try cost_command.run(init, rest);
        if (std.mem.eql(u8, command, "test")) break :status try testCommand(init, rest);
        for ([_][]const u8{ "dump-ir", "dump-typed", "coverage" }) |name| if (std.mem.eql(u8, command, name)) break :status try core_main.developer(init, args);
        return null;
    };
    return status;
}

/// The same default release cost output appended by the interface CLI.
pub fn interfaceCost(init: std.process.Init, path: []const u8) Error!cost_command.Output {
    return cost_command.output(init, .{ .path = path });
}

/// Whether a `build` names one of the core's developer-only switches, which the
/// core's own build command answers (S5-D8: `mylang-core` merged into `mylang`).
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
    try write(init, try std.fmt.allocPrint(init.arena.allocator(), "mylang {s}: {s}\n", .{ command, message }));
    return 2;
}

fn write(init: std.process.Init, text: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(init.io, text) catch return error.WriteFailed;
}

const build_usage =
    \\usage: mylang build <file.my> (-o <output> | --run [run options] [-- ARGS...]) [--release] [--link FILE.c]... [--emit-llvm PATH]
    \\       [--cache-dir DIR] [--no-cache] [--zig PATH] [--report] [--cache-report] [--verify-cache] [--stats] [--diagnostics=text|json]
    \\
;

/// `mylang build FILE.my -o OUT` and `build --run`.
fn buildCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = try cli_run.parseRequest(init, .build, args, build_usage) orelse return 2;
    if (request.run != null) return cli_run.run(init, request, "build");
    // CLI-INPUT-REFUSED-1: an entry that cannot be read is refused by name, as `run` refuses it.
    if (try cli_run.unreadable(init, "build", request.path)) |message| {
        try write(init, message);
        return 2;
    }
    var options = request.build;
    if (request.no_cache) options.cache = try cli_run.privateCache(init, options.cache);
    defer if (request.no_cache) cli_run.discard(init.io, options.cache);
    var report: std.ArrayList(u8) = .empty;
    const status = pipeline.build(init, request.path, options, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError, error.Unsupported => 1,
        error.PolicyDenied => 3,
        error.ConfigurationFailed => 2,
        error.ToolFailed, error.WriteFailed, error.InvalidIr => 2,
    };
    try write(init, report.items);
    return status;
}

/// `mylang test`: the new core's runner (`test_runner.zig`), with the old CLI's
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
        if (std.mem.eql(u8, arg, "--whole-program")) continue;
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
    // Test processes inherit the caller's address space, not the compiler's own
    // ceiling; each lowers it to its byte ceiling (NEW-CORE-S4-MEMORY-1).
    cli_run.restoreAddressSpace(init.environ_map);
    const status = try core_main.testCommand(init, normalized.items);
    return status;
}

/// Verify backend allocation contracts after a host's existing frontend check.
pub fn checkAllocationContracts(a: std.mem.Allocator, program: @import("mylang").typed.Program, source: @import("mylang").source.Source, sink: *@import("mylang").diagnostic.Sink) @import("mylang").diagnostic.Error!void {
    if (try @import("allocation_contract.zig").checkProgram(a, program, source)) |failure| {
        const item = try @import("allocation_contract.zig").diagnostic(a, failure);
        return sink.fail(item.code, item.span, item.message);
    }
}
