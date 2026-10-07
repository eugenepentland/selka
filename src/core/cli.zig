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

/// What stops a command before it has a status: memory, an unwritable stream, or a
/// test the runner cannot encode.
pub const Error = core_main.Error;

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
    .{ .name = "--explain-ownership", .message = "--explain-ownership read the old back end's ownership lowering (retired, S5); `mylang build --stats` reports the new core's" },
};

/// Flags `mylang test` refuses that its new runner dropped (S5-D6).
const dropped_test_flags = [_][]const u8{
    "--pure-skip",        "--diagnostics",  "--max-calls",     "--bench",        "--bench-only",    "--bench-output",
    "--bench-baseline",   "--bench-policy", "--bench-profile", "--bench-warmup", "--bench-batches", "--bench-batch-ms",
    "--bench-timeout-ms",
};

/// Run `args` (argv, the program name first) when it names a command of the new
/// core or a retired one, returning its exit status; null leaves it to the caller.
pub fn dispatch(init: std.process.Init, args: []const []const u8) Error!?u8 {
    if (args.len < 2) return null;
    const command = args[1];
    const rest = args[2..];
    const status = status: {
        for (retired_commands) |retired| if (std.mem.eql(u8, command, retired.name)) break :status try refuse(init, command, retired.message);
        if (retiredFlag(rest)) |retired| break :status try refuse(init, command, retired.message);
        if (std.mem.eql(u8, command, "build")) break :status try buildCommand(init, rest);
        if (std.mem.eql(u8, command, "run") or std.mem.eql(u8, command, "run-project")) break :status try runCommand(init, command, rest);
        if (std.mem.eql(u8, command, "test")) break :status try testCommand(init, rest);
        for ([_][]const u8{ "dump-ir", "dump-typed", "coverage" }) |name| if (std.mem.eql(u8, command, name)) break :status try core_main.developer(init, args);
        return null;
    };
    return status;
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
    \\usage: mylang build FILE.my (-o OUT | --run [RUN OPTIONS] [-- ARGS...]) [--release] [--link FILE.c]... [--emit-llvm PATH]
    \\       [--cache-dir DIR] [--zig PATH] [--cache-report] [--verify-cache] [--stats] [--diagnostics=text|json]
    \\
;

const run_usage =
    \\usage: mylang run FILE.my [options] [-- ARGS...]
    \\       mylang run-project ENTRY.my [options] [-- ARGS...]
    \\  builds the program with the new core and runs it; every value after -- is a program argument
    \\  budgets (each takes --flag N or --flag=N; N is a positive integer):
    \\    --max-steps N      instruction ceiling (default: unbounded)
    \\    --max-frames N     call-depth ceiling (default: unbounded); each frame reserves 32 KiB of --max-memory
    \\    --timeout N        elapsed-time cap in seconds
    \\    --max-memory SIZE  byte ceiling, K/M/G suffixes (default 4G; MYLANG_MEMORY_LIMIT names the same)
    \\  output: --print-result --diagnostics=text|json
    \\  build: --release --zig=PATH --cache-dir=DIR
    \\  authority: --restrict --allow-read=DIR --allow-write=DIR --allow-endpoint=IP:PORT --allow-clock
    \\             --allow-random[=SEED] --allow-env[=NAME,...] --allow-host --allow-all
    \\  `mylang --help` lists every command
    \\
;

fn zigPath(init: std.process.Init) []const u8 {
    return init.environ_map.get("ZIG") orelse init.environ_map.get("MYLANG_ZIG") orelse "zig";
}

fn parseRequest(init: std.process.Init, command: cli_args.Command, args: []const []const u8, usage: []const u8) Error!?cli_args.Request {
    var failure: cli_args.Failure = .usage;
    const request = cli_args.parse(init.arena.allocator(), command, args, zigPath(init), &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Usage => {
            switch (failure) {
                .usage => try write(init, usage),
                .retired => |message| try write(init, try std.fmt.allocPrint(init.arena.allocator(), "mylang: {s}\n", .{message})),
            }
            return null;
        },
    };
    return request;
}

/// `mylang build FILE.my -o OUT` and `build --run`.
fn buildCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = try parseRequest(init, .build, args, build_usage) orelse return 2;
    if (request.run != null) return cli_run.run(init, request, "build");
    var report: std.ArrayList(u8) = .empty;
    const status = pipeline.build(init, request.path, request.build, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError, error.Unsupported => 1,
        error.ToolFailed, error.WriteFailed, error.InvalidIr => 2,
    };
    try write(init, report.items);
    return status;
}

/// `mylang run` and `run-project`: the same command; a project entry is found from the file.
fn runCommand(init: std.process.Init, command: []const u8, args: []const []const u8) Error!u8 {
    const request = try parseRequest(init, .run, args, run_usage) orelse return 2;
    return cli_run.run(init, request, command);
}

/// `mylang test`: the new core's runner (`test_runner.zig`), with the old CLI's
/// `--flag=VALUE` spellings, `--qbe` ignored and `--whole-program` accepted (S5-D6).
fn testCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const a = init.arena.allocator();
    var normalized: std.ArrayList([]const u8) = .empty;
    // A later `--zig` wins over the environment's.
    try normalized.appendSlice(a, &.{ "--zig", zigPath(init) });
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const name = arg[0..split];
        for (dropped_test_flags) |dropped| if (std.mem.eql(u8, name, dropped)) {
            return refuse(init, "test", try std.fmt.allocPrint(a, "{s} was dropped with the old test runner (S5-D6)", .{name}));
        };
        if (cli_args.unported(arg)) |message| return refuse(init, "test", message);
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
    const status = try core_main.testCommand(init, normalized.items);
    return status;
}
