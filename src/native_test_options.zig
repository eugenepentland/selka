//! Command-line controls for native application tests and benchmarks.
const std = @import("std");
const execute = @import("native_test_execute.zig");
const budget = @import("memory_budget");
const build_options = @import("qbe_build_options.zig");
/// Invalid native test command arguments.
pub const Error = error{InvalidTestArguments};
/// Boolean mode switches, grouped to keep the options surface bounded.
pub const Flags = struct {
    force: bool = false,
    /// `--no-cache` reads and writes no durable result, graph or query entry.
    no_cache: bool = false,
    /// `--pure-skip` opts into replaying a recorded pass-or-fail outcome for an
    /// unchanged signature-pure test; off by default so recorded failures do not
    /// change the default result.
    pure_skip: bool = false,
    /// Opt-in D3 experiment forwarded to every compiler child the test spawns.
    /// `--affected` selects only tests that reach a declaration changed since
    /// `--against REF`; the reference itself lives on `Options.against`.
    affected: bool = false,
    /// `--gc-stress` runs every collected test with the runtime's stress
    /// collector, the same coverage `native_execute` gets from its own flag.
    gc_stress: bool = false,
    /// Output-channel switches, grouped apart from the execution switches.
    output: Output = .{},
    /// Output channel selection: the work report and the JSON report.
    pub const Output = struct {
        /// `--report` emits a work-report-v1 line for this test invocation.
        report: bool = false,
        json: bool = false,
    };
};
/// Sampling and whole-run bounds for one benchmark invocation.
pub const Tuning = struct {
    sampling: execute.Sampling = .{},
    timeout_ms: u32 = 120000,
};
/// Benchmark discovery, artifacts and runner identity. A benchmark run always
/// executes freshly; these controls never select a cached performance result.
pub const BenchOptions = struct {
    /// `--bench PATTERN` selects exported `bench_` functions and enables bench mode.
    pattern: ?[]const u8 = null,
    /// `--bench-only` skips correctness tests for local iteration.
    only: bool = false,
    /// Atomic candidate report path for inspection or a proposed baseline.
    output: ?[]const u8 = null,
    /// Approved baseline compared against, never replaced while checking.
    baseline: ?[]const u8 = null,
    /// Approved policy supplying limits, required suite and noise budget.
    policy: ?[]const u8 = null,
    /// Runner profile identity that must match the baseline provenance.
    profile: []const u8 = "default",
    tuning: Tuning = .{},
};
/// Discovery, execution and cache policy.
pub const Options = struct {
    link_arguments: []const []const u8 = &.{},
    source: []const u8 = "",
    filter: []const u8 = "*",
    cases: ?[]const u8 = null,
    cache: []const u8 = ".mylang-cache/tests",
    toolchain: Toolchain = .{},
    mode: []const u8 = "Debug",
    flags: Flags = .{},
    jobs: ?usize = null,
    limits: execute.Limits = .{},
    bench: BenchOptions = .{},
    /// `--against REF` reference revision for `--affected`; null without it.
    against: ?[]const u8 = null,
};
/// The executables one native session drives, grouped so the option record
/// stays a bag of independent choices rather than a list of tool paths.
pub const Toolchain = struct {
    qbe: []const u8 = "",
    zig: []const u8 = "zig",
    /// The mylang executable this session spawns for its compiler children.
    /// Null means this process (`/proc/self/exe`), which is what the CLI wants
    /// and what a session must not assume: a session built by anything other
    /// than the CLI that leaves this null spawns *itself* as the compiler, and
    /// a test binary handed `native-test-graph` runs its tests instead of
    /// emitting facts, so the two recurse without bound. An embedder or a test
    /// names the compiler it means.
    compiler: ?[]const u8 = null,
};
/// Native tests require no Python interpreter.
pub const usage = "usage: mylang test <entry.my|directory> [--filter SUBSTRING|GLOB] [--cases FILE]\n" ++
    "  --affected --against REF  run only tests reaching a declaration changed since REF\n" ++
    "  --link FILE --link-library NAME --library-path DIR (repeatable)\n" ++
    "  --cache-dir DIR --force --no-cache --report --json --pure-skip --qbe PATH --zig PATH\n" ++
    "  a test build uses QBE in either mode; --release builds the LLVM release path\n" ++
    "    (ReleaseFast, --llvm-opt 3 --lto) and refuses --mode and --qbe\n" ++
    "  --gc-stress  run every collected test under the runtime's stress collector\n" ++
    "  --mode Debug|ReleaseFast\n" ++
    "  --max-steps N --max-frames N --max-calls N --timeout-ms N\n" ++
    "  --max-memory BYTES  per-test byte ceiling (K/M/G suffixes; default 512M)\n" ++
    "  --jobs N  directory fan-out width (default: cores, capped by free memory)\n" ++
    "  bench: --bench PATTERN [--bench-only] [--bench-output FILE]\n" ++
    "         [--bench-baseline FILE] [--bench-policy FILE] [--bench-profile ID]\n" ++
    "         [--bench-warmup N] [--bench-batches N] [--bench-batch-ms N]\n" ++
    "         [--bench-timeout-ms N]\n";
/// Parse options, rejecting malformed budgets, sampling bounds and unknown flags.
pub fn parse(args: []const []const u8) Error!Options {
    var result: Options = .{ .link_arguments = args };
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!std.mem.startsWith(u8, arg, "-")) {
            if (result.source.len != 0) return error.InvalidTestArguments;
            result.source = arg;
            continue;
        }
        if (std.mem.eql(u8, arg, "--force")) {
            result.flags.force = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-cache")) {
            result.flags.no_cache = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--report")) {
            result.flags.output.report = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            result.flags.output.json = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--pure-skip")) {
            result.flags.pure_skip = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--mutation-markers")) {
            continue;
        }
        if (std.mem.eql(u8, arg, "--bench-only")) {
            result.bench.only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--affected")) {
            result.flags.affected = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--gc-stress")) {
            result.flags.gc_stress = true;
            continue;
        }
        // `--release` rides in `link_arguments`, where the session finds it and
        // hands it to the child build, so the frozen Options field set does not
        // grow. It is a ReleaseFast build, and the mode keys every receipt.
        if (std.mem.eql(u8, arg, build_options.release_flag)) {
            result.mode = "ReleaseFast";
            continue;
        }
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const flag = std.meta.stringToEnum(Flag, arg[0..split]) orelse return error.InvalidTestArguments;
        const value = if (split < arg.len) arg[split + 1 ..] else value: {
            i += 1;
            if (i == args.len) return error.InvalidTestArguments;
            break :value args[i];
        };
        if (value.len == 0) return error.InvalidTestArguments;
        if (@import("native_link.zig").isFlag(@tagName(flag)) and !@import("native_link.zig").valid(@tagName(flag), value)) return error.InvalidTestArguments;
        try assign(&result, flag, value);
    }
    if (result.source.len == 0) return error.InvalidTestArguments;
    if (build_options.release(args) and build_options.restatesRelease(args)) return error.InvalidTestArguments;
    if (!std.mem.eql(u8, result.mode, "Debug") and !std.mem.eql(u8, result.mode, "ReleaseFast")) return error.InvalidTestArguments;
    const wanted = result.bench.only or result.bench.output != null or result.bench.baseline != null or result.bench.policy != null;
    if (wanted and result.bench.pattern == null) return error.InvalidTestArguments;
    // `--affected` and `--against REF` only make sense together: one selects the
    // derivation, the other names the revision it compares against.
    if (result.flags.affected != (result.against != null)) return error.InvalidTestArguments;
    return result;
}
const Flag = enum {
    @"--link",
    @"--link-library",
    @"--library-path",
    @"--filter",
    @"--cases",
    @"--against",
    @"--cache-dir",
    @"--qbe",
    @"--zig",
    @"--mode",
    @"--max-steps",
    @"--max-frames",
    @"--max-calls",
    @"--timeout-ms",
    @"--max-memory",
    @"--jobs",
    @"--bench",
    @"--bench-output",
    @"--bench-baseline",
    @"--bench-policy",
    @"--bench-profile",
    @"--bench-warmup",
    @"--bench-batches",
    @"--bench-batch-ms",
    @"--bench-timeout-ms",
};
fn assign(result: *Options, flag: Flag, value: []const u8) Error!void {
    switch (flag) {
        .@"--link", .@"--link-library", .@"--library-path" => {},
        .@"--filter" => result.filter = value,
        .@"--cases" => result.cases = value,
        .@"--against" => result.against = value,
        .@"--cache-dir" => result.cache = value,
        .@"--qbe" => result.toolchain.qbe = value,
        .@"--zig" => result.toolchain.zig = value,
        .@"--mode" => result.mode = value,
        .@"--max-steps" => result.limits.max_steps = try number(value),
        .@"--max-frames" => result.limits.max_frames = try number(value),
        .@"--max-calls" => result.limits.max_calls = try number(value),
        .@"--timeout-ms" => result.limits.timeout_ms = @intCast(try number(value)),
        .@"--max-memory" => result.limits.max_memory = budget.parse(value) catch return error.InvalidTestArguments,
        .@"--jobs" => result.jobs = budget.jobs(value) catch return error.InvalidTestArguments,
        .@"--bench" => result.bench.pattern = value,
        .@"--bench-output" => result.bench.output = value,
        .@"--bench-baseline" => result.bench.baseline = value,
        .@"--bench-policy" => result.bench.policy = value,
        .@"--bench-profile" => result.bench.profile = value,
        .@"--bench-warmup" => result.bench.tuning.sampling.warmup_iterations = try bounded(value, 0, 1000),
        .@"--bench-batches" => result.bench.tuning.sampling.batch_count = try bounded(value, 1, 64),
        .@"--bench-batch-ms" => result.bench.tuning.sampling.target_batch_ns = (try bounded(value, 1, 86_400_000)) * 1_000_000,
        .@"--bench-timeout-ms" => result.bench.tuning.timeout_ms = @intCast(try bounded(value, 1, std.math.maxInt(u32))),
    }
}
fn number(value: []const u8) Error!u64 {
    const n = std.fmt.parseInt(u64, value, 10) catch return error.InvalidTestArguments;
    if (n == 0 or n > std.math.maxInt(u32)) return error.InvalidTestArguments;
    return n;
}
fn bounded(value: []const u8, minimum: u64, maximum: u64) Error!u64 {
    const n = std.fmt.parseInt(u64, value, 10) catch return error.InvalidTestArguments;
    if (n < minimum or n > maximum) return error.InvalidTestArguments;
    return n;
}
test "native test options validate budgets and discovery controls" {
    const opts = try parse(&.{ "main.my", "--filter=*ok", "--force", "--json", "--max-steps", "100" });
    try std.testing.expect(opts.flags.force and opts.flags.output.json);
    const fresh = try parse(&.{ "main.my", "--no-cache", "--report" });
    try std.testing.expect(fresh.flags.no_cache and fresh.flags.output.report);
    try std.testing.expectEqual(@as(u64, 100), opts.limits.max_steps);
    for ([_][]const []const u8{ &.{}, &.{ "x", "--wat" }, &.{ "x", "--max-steps=0" }, &.{ "x", "--mode=Fast" }, &.{ "x", "--cases" } }) |args| {
        try std.testing.expectError(error.InvalidTestArguments, parse(args));
    }
}

// spec-case: NATIVE-BENCH-1
test "benchmark options select a pattern, artifacts, identity and sampling bounds" {
    const opts = try parse(&.{
        "main.my",          "--bench",        "bench_*",            "--bench-output",  "out.json",
        "--bench-baseline", "base.json",      "--bench-policy",     "policy.json",     "--bench-profile",
        "linux-release",    "--bench-warmup", "0",                  "--bench-batches", "3",
        "--bench-batch-ms", "50",             "--bench-timeout-ms", "9000",
    });
    try std.testing.expectEqualStrings("bench_*", opts.bench.pattern.?);
    try std.testing.expectEqualStrings("linux-release", opts.bench.profile);
    try std.testing.expectEqual(@as(u64, 0), opts.bench.tuning.sampling.warmup_iterations);
    try std.testing.expectEqual(@as(u64, 3), opts.bench.tuning.sampling.batch_count);
    try std.testing.expectEqual(@as(u64, 50_000_000), opts.bench.tuning.sampling.target_batch_ns);
    try std.testing.expectEqual(@as(u32, 9000), opts.bench.tuning.timeout_ms);
    const only = try parse(&.{ "main.my", "--bench", "*", "--bench-only" });
    try std.testing.expect(only.bench.only);
    // Artifact and benchmark-only switches need an explicit selection.
    for ([_][]const []const u8{
        &.{ "x", "--bench-only" },
        &.{ "x", "--bench-output", "o.json" },
        &.{ "x", "--bench-batches", "0" },
        &.{ "x", "--bench-batches", "65" },
        &.{ "x", "--bench-warmup", "1001" },
        &.{ "x", "--bench-batch-ms", "0" },
    }) |args| {
        try std.testing.expectError(error.InvalidTestArguments, parse(args));
    }
}

// spec-case: MEMORY-CEILING-1
test "a test run accepts a suffixed byte ceiling and an explicit fan-out width" {
    const opts = try parse(&.{ "main.my", "--max-memory=64M", "--jobs", "3" });
    try std.testing.expectEqual(@as(?u64, 64 << 20), opts.limits.max_memory);
    try std.testing.expectEqual(@as(?usize, 3), opts.jobs);
    // Unresolved by default, so the environment and the built-in default still apply.
    try std.testing.expectEqual(@as(?u64, null), (try parse(&.{"main.my"})).limits.max_memory);
    try std.testing.expectEqual(@as(?usize, null), (try parse(&.{"main.my"})).jobs);
    for ([_][]const []const u8{ &.{ "x", "--max-memory=12x" }, &.{ "x", "--max-memory" }, &.{ "x", "--jobs=0" }, &.{ "x", "--jobs=all" } }) |args| {
        try std.testing.expectError(error.InvalidTestArguments, parse(args));
    }
}

// spec-case: PURE-SKIP-1
test "pure-skip is an explicit opt-in switch" {
    const enabled = try parse(&.{ "main.my", "--pure-skip" });
    try std.testing.expect(enabled.flags.pure_skip);
    try std.testing.expect(!(try parse(&.{"main.my"})).flags.pure_skip);
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--pure-skipp" }));
}

// spec-case: AFFECTED-TEST-1
test "affected selection needs both switches and a reference" {
    const selected = try parse(&.{ "main.my", "--affected", "--against", "HEAD" });
    try std.testing.expect(selected.flags.affected);
    try std.testing.expectEqualStrings("HEAD", selected.against.?);
    const joined = try parse(&.{ "main.my", "--affected", "--against=origin/main" });
    try std.testing.expectEqualStrings("origin/main", joined.against.?);
    try std.testing.expect(!(try parse(&.{"main.my"})).flags.affected);
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--against", "HEAD" }));
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--affected" }));
}

// spec-case: BUILD-RELEASE-1
test "a test run's --release is a ReleaseFast build that refuses --mode and --qbe" {
    const asked = try parse(&.{ "main.my", "--release" });
    try std.testing.expectEqualStrings("ReleaseFast", asked.mode);
    try std.testing.expect(build_options.release(asked.link_arguments));
    try std.testing.expectEqualStrings("Debug", (try parse(&.{"main.my"})).mode);
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--release", "--mode", "Debug" }));
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--mode=ReleaseFast", "--release" }));
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--qbe", "/opt/qbe", "--release" }));
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--release=yes" }));
    try std.testing.expect(std.mem.indexOf(u8, usage, "--release builds the LLVM release path") != null);
}

// spec: GUEST-TEST-GC-STRESS-1
test "gc stress is an explicit opt-in switch" {
    const enabled = try parse(&.{ "main.my", "--gc-stress" });
    try std.testing.expect(enabled.flags.gc_stress);
    try std.testing.expect(!(try parse(&.{"main.my"})).flags.gc_stress);
    try std.testing.expectError(error.InvalidTestArguments, parse(&.{ "main.my", "--gc-stress=1" }));
}
