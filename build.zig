const std = @import("std");
const builtin = @import("builtin");
const guardian = @import("guardian");
/// The repository files each cached test step reads while it runs.
const test_inputs = @import("build_test_inputs.zig");
const verification = @import("build_verification.zig");
var verification_registry: ?verification.Registry = null;
var verification_core_binary: ?*std.Build.Step.Compile = null;
/// The `build-env` host tool (`build_env.zig`): it writes the environment
/// manifest every cached test verdict is keyed on and projects the environment
/// every command `withTools` wraps runs in, from one definition.
var build_env: ?*std.Build.Step.Compile = null;
/// Where the test roots find the compiler and their fixtures
/// (`src/core/test_paths.zig`, TEST-PATHS-1): imported as `core_test_options` by
/// the core root and as `test_paths` by the unit, CLI and golden roots.
var test_paths: ?*std.Build.Module = null;
/// The component builder the CLI root runs, named at run time through
/// `MYLANG_TEST_COMPONENT_BUILDER`.
var component_builder_bin: ?std.Build.LazyPath = null;
/// One mebibyte, the unit the resident-memory ceilings below are written in.
const mib: u64 = 1 << 20;
/// Resident-memory ceilings declared on the steps this build runs. The build
/// runner schedules concurrent steps against `--maxrss` using them and fails a
/// step whose measured peak exceeds its declaration. Only Zig compilations and
/// Zig test binaries report a peak back, so only those can trip a ceiling; for
/// a driver process it is purely a concurrency budget, and it covers the
/// children one driver runs at once rather than the largest single process
/// `/usr/bin/time -v` sees. Observed figures are recorded beside each ceiling.
const rss = struct {
    /// Zig test binaries, which also spawn the compiler. Observed: the CLI root
    /// 31M. The unit root additionally builds and runs every guest program its
    /// suites execute; the whole root peaked near 2.2G while it still linked libc
    /// for the retired `invoke` tests.
    const suite: u64 = 2560 * mib;
    /// One shard of the unit root. A shard builds and runs only its slice of
    /// the guest programs, so its peak sits well under the whole root's 2.2G.
    /// Observed on a clean cache (2026-09-23): the test process itself peaked
    /// at 216M-570M across the twelve shards, and a shard's whole process tree
    /// (its guest compiles included) at 275M-1.24G for a moment. The whole
    /// `zig build test` never held more than 5.8G at once, but at 1.5G per
    /// shard the declarations alone passed a 30G machine's budget, so the build
    /// runner held the last shards back for most of a minute. The module-era
    /// semantic-cache shard later passed 199 tests with a 1.31G process peak
    /// (2026-09-30); 2G admitted that work. After S2 Wave A's tests the
    /// shard holding `semantic_cache_test` and the old back end's RC tests
    /// peaked at 2.18G running alone (2,281,596 kB, 2026-10-05, 218 tests), so
    /// 2.5G keeps a measured ceiling with headroom.
    const shard_unit: u64 = 2560 * mib;
    /// One shard of the CLI root, which builds far fewer guests. Observed on a
    /// clean cache: 103M-141M for the test process, up to 1.22G for a moment
    /// across its tree; the ceiling is a concurrency budget.
    const shard_cli: u64 = 768 * mib;
    /// The directory run of `tests/guest`. Observed on a clean cache
    /// (2026-09-23): `tests/guest` 1.33G.
    const guest_suite: u64 = 1536 * mib;
    /// Drivers that run the compiler a few programs at a time. Observed on a
    /// clean cache: the idiom probes 0.69G, parser hints 0.47G.
    const driver: u64 = 1024 * mib;
    /// Drivers that compile and link many native programs at once: the parity
    /// benchmark. Observed (the retired boundary matrix): 1.29G-1.45G.
    const parity: u64 = 2048 * mib;
    /// Checks that run Python but no compiler: the
    /// self-tests, the friction harvest, the SPEC merge driver, the inner-loop
    /// checks. Observed: under 60M each. Declaring a driver's 1G for each of
    /// them only kept the build runner from starting test shards it had room for.
    const script: u64 = 256 * mib;
    /// Guardian's whole-tree gate. Observed: the whole-tree run's tree 273M.
    const gate: u64 = 512 * mib;
    /// Zig compilations. Only these and the test binaries report a peak to the
    /// build runner, so only they can trip a ceiling; the margin over the debug
    /// peak leaves room for a ReleaseFast build of the same tree.
    /// Observed (debug): src/root_test.zig 335M, the mylang executable 270M, the
    /// other test roots 166-232M, the small runner executables 42M.
    /// Observed (ReleaseFast, C3/C4 tree): a test-root compile peaked at 2.55G,
    /// so the old 2.15G bound blocked the documented gate; 3G keeps a bounded
    /// ceiling with headroom for the same tree.
    /// Observed (ReleaseFast `-Dcompiler-only`, 2026-09-24, after the incremental
    /// build frontend landed): the mylang executable compile peaked at 3.26-3.32G,
    /// over the 3G bound, so the install graph failed after writing the binary.
    /// Observed again (ReleaseFast, 2026-09-24, with per-module tests): 4.26G.
    const compile: u64 = 4608 * mib;
    /// The B2 ReleaseFast compiler peaked at 5,226,618,880 bytes (2026-09-30).
    /// Reserve 5.5 GiB for that artifact, retaining about 13% measured headroom.
    const compiler_fast: u64 = 5632 * mib;
    /// `zig build run`, which executes whatever program the caller names.
    /// Matches the 4 GiB ceiling `mylang run` gives a guest.
    const guest: u64 = 4096 * mib;
};
/// The pinned Zig a guest build drives (`zig cc`), and the install step every
/// bounded driver waits on, filled in once at the top of `build`. A driver
/// invokes an uninstalled compiler, so it names the toolchain through
/// `MYLANG_ZIG`, which the compiler reads when neither `--zig` nor `ZIG` names one.
var tool_zig: []const u8 = "";
var install_all: ?*std.Build.Step = null;
/// Independent components required by command-running focused tests.
var install_components: ?*std.Build.Step = null;
/// The emitted compiler binary. The cached steps that run it name it through an
/// installed path whose bytes the cache key cannot see, so each declares its
/// contents as an input.
var tool_inputs: [1]?std.Build.LazyPath = .{null};
/// `-Dtest-rerun`: run every cached test step even when none of its inputs
/// changed, to see full selected-test counts or to rule out a stale verdict.
var test_rerun = false;
/// The directory of per-list content manifests `tests/input_manifest.py` writes
/// on every build, one `NAME.txt` per list in `build_test_inputs.zig`.
var input_manifests: ?std.Build.LazyPath = null;
/// Add the step that hashes every declared test input, once per build. It runs on
/// every invocation because only a make-phase walk sees a file added to a
/// declared directory: this Zig version records `dependOnDirectory` but never
/// re-runs the configure phase for it. An unchanged tree yields byte-identical
/// manifests, so the cached steps that read them stay cached.
fn addInputManifests(b: *std.Build) void {
    const run = b.addSystemCommand(&.{ "python3", "tests/input_manifest.py" });
    run.setName("hash declared test inputs");
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    run.step.max_rss = rss.script;
    input_manifests = run.addOutputDirectoryArg("test-inputs");
    verification_registry.?.register("input-discovery", &run.step, &.{}, false, "directory membership must be discovered at execution time");
    inline for (comptime std.meta.declarations(test_inputs)) |name| {
        run.addArgs(&.{ "--list", name });
        run.addArgs(&@field(test_inputs, name));
    }
}
/// The make-time environment manifest `addEnvironmentManifest` writes on every
/// build that runs a cached test step.
var environment_manifest: ?std.Build.LazyPath = null;
/// The tools the environment manifest identifies by content: this build's Zig,
/// and the shell, `env`, Python and git found on the live `PATH` at make time.
const manifest_tools = [_][]const u8{ "sh", "env", "python3", "git" };
/// Add the step that records the make-time environment a cached test verdict
/// depends on, once per build (ENV-PROJECTION-2). A step's own environment
/// cannot key its verdict: every Run step inherits `zig build`'s live
/// environment (see `withTools`), which the build runner leaves out of a step's
/// cache key. `build-env digest` writes the host-scope environment identity
/// instead: the keyed and host variables of `src/environment_identity.zon` and
/// the digests of the tools above, so a changed `MYLANG_*`, locale or Python
/// setting, or a different `zig`, `sh`, `env`, `python3` or `git`, re-runs the
/// cached verdicts, while a placement or dropped variable (`PATH`, `TMPDIR`,
/// `PWD`, `TERM`, `CODEX_*`) leaves them cached.
fn addEnvironmentManifest(b: *std.Build) void {
    const run = b.addRunArtifact(build_env.?);
    run.setName("record the test environment");
    run.has_side_effects = true;
    run.step.max_rss = rss.script;
    run.addArg("digest");
    environment_manifest = run.addOutputFileArg("environment.txt");
    run.addArg(b.fmt("zig={s}", .{b.graph.zig_exe}));
    run.addArgs(&manifest_tools);
    verification_registry.?.register("environment-discovery", &run.step, &.{}, false, "live inherited environment must be discovered at execution time");
}
/// Let a test step's verdict be cached: it re-runs only when its command, the
/// environment `addEnvironmentManifest` records, an artifact it names,
/// the tools the environment names, or one of the repository files the `list`
/// in `build_test_inputs.zig` declares changes (or under `-Dtest-rerun`). An
/// empty `list` declares no repository files.
fn cached(run: *std.Build.Step.Run, list: []const u8) void {
    run.has_side_effects = test_rerun;
    const b = run.step.owner;
    if (list.len != 0) run.addFileInput(input_manifests.?.path(b, b.fmt("{s}.txt", .{list})));
    run.addFileInput(environment_manifest.?);
    // The manifest includes the verified artifact digest and qualified build
    // key. Source inputs alone cannot see a changed seed or toolchain library.
    if (install_components) |components| {
        run.step.dependOn(components);
        run.addFileInput(.{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components/test-index.json" } });
        run.addFileInput(.{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components/cache-plan.json" } });
    }
    for (tool_inputs) |tool| if (tool) |path| run.addFileInput(path);
    if (list.len != 0) verification_registry.?.declared(&run.step, list);
}
/// Prefix a command so that it runs in `zig build`'s live environment plus the
/// native tools a guest build needs. `Step.Run.setEnvironmentVariable` would
/// instead copy the whole configure-time environment into the step, and a
/// cached configuration keeps that copy: after one `zig build` under another
/// `PATH`, `TMPDIR` or `MYLANG_*`, every later build with the same `-D` options
/// ran its tests in that stale environment. The shell resolves Zig's global
/// cache the way `std.zig.resolveGlobalCacheDir` does, at make time, and names
/// it explicitly: a test that redirects `HOME` for a child compiler would
/// otherwise send its `zig cc` invocations to an empty cache. The command also
/// gets a Zig local cache of its own for as long as it runs (see
/// `tools_script`). The command runs through `build-env project`, so it sees
/// only the variables `src/environment_identity.zon` passes to children: the
/// keyed and host ones the environment manifest records, and placement ones
/// such as `PATH`, `HOME` and `TMPDIR` (ENV-PROJECTION-1). A dropped variable
/// (`PWD`, `TERM`, `CODEX_*`, ...) can therefore never change a verdict the
/// manifest does not key. `env` then adds `MYLANG_ZIG`, which depends only on
/// this build's configuration, and the variables `withVariable` and
/// `withTestPaths` give the command.
fn withTools(step: *std.Build.Step.Run) void {
    const b = step.step.owner;
    var prefix: std.ArrayList([]const u8) = .empty;
    prefix.appendSlice(b.allocator, &.{ "sh", "-c", tools_script, "with-tools" }) catch @panic("out of memory");
    prefix.append(b.allocator, b.fmt("MYLANG_ZIG={s}", .{tool_zig})) catch @panic("out of memory");
    const arena = b.graph.arena;
    const args = arena.alloc(std.Build.Step.Run.Arg, prefix.items.len) catch @panic("out of memory");
    for (args, prefix.items) |*arg, word| arg.* = .{ .bytes = b.graph.dupeString(word) };
    step.argv.insertSlice(arena, 0, args) catch @panic("out of memory");
    // The tool travels as an argument, so its content is part of the step's key.
    insertFile(step, 4, "", build_env.?.getEmittedBin());
    step.argv.insert(arena, args.len + 1, .{ .decorated_directory = .{
        .prefix = "MYLANG_COMPONENT_DIR=",
        .suffix = "",
        .make_absolute = true,
        .lazy_path = .{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components" } },
    } }) catch @panic("out of memory");
}
/// Where `withVariable` and `withTestPaths` insert a variable: after
/// `sh -c SCRIPT with-tools BUILD-ENV MYLANG_ZIG=PATH`, before the command itself.
const variable_index = 6;
/// Give the command `withTools` wraps the variable `assignment` (`NAME=VALUE`).
fn withVariable(step: *std.Build.Step.Run, assignment: []const u8) void {
    const b = step.step.owner;
    step.argv.insert(b.graph.arena, variable_index, .{ .bytes = b.graph.dupeString(assignment) }) catch @panic("out of memory");
}
/// Insert at `index` of the command an absolute path to `file`, after
/// `prefix`. The step's cache key holds the file's content, not its path, and
/// the step waits for whatever produces it.
fn insertFile(step: *std.Build.Step.Run, index: usize, prefix: []const u8, file: std.Build.LazyPath) void {
    const b = step.step.owner;
    step.argv.insert(b.graph.arena, index, .{ .lazy_path = .{
        .prefix = b.graph.dupeString(prefix),
        .lazy_path = file.dupe(b.graph),
        .suffix = "",
        .make_absolute = true,
    } }) catch @panic("out of memory");
    file.addStepDependencies(&step.step);
}
/// Name the executables a Zig test root runs (TEST-PATHS-1): `mylang` through
/// `MYLANG_TEST_COMPILER` and, for the CLI root, the component builder through
/// `MYLANG_TEST_COMPONENT_BUILDER`. The test binaries embed no path of this
/// tree; the step keys each executable by content, so a changed compiler still
/// re-runs a cached verdict without rebuilding the test binary. The command
/// runs in the build root, where the roots' relative fixture paths resolve.
fn withTestPaths(step: *std.Build.Step.Run, component_builder: bool) void {
    const b = step.step.owner;
    step.setCwd(b.path("."));
    insertFile(step, variable_index, "MYLANG_TEST_COMPILER=", tool_inputs[0].?);
    if (component_builder) insertFile(step, variable_index, "MYLANG_TEST_COMPONENT_BUILDER=", component_builder_bin.?);
}
/// The shell half of `withTools`: export Zig's global cache directory as the
/// Zig toolchain would resolve it here and now, point `ZIG_LOCAL_CACHE_DIR` at
/// a fresh directory under `$TMPDIR`, then run `env TOOL=PATH… CMD…`
/// (NATIVE-ZIG-CACHE-4). A test or driver that runs `zig cc` itself works in a
/// scratch directory inside the checkout (`.zig-cache/tmp`, or a `$TMPDIR`
/// there), so Zig would find this project's `build.zig` above it and keep the
/// object in its `.zig-cache` under a key naming that scratch path, which no
/// later run can reuse. The command replaces this shell with `exec`, so it
/// stays the build runner's own child, keeping its pid, exit status and
/// resource accounting; a detached watcher that ignores interrupts removes
/// the directory once that pid has gone, however the command ended. The first
/// argument is the `build-env` tool, which execs `env` and the command in turn
/// with the projected environment (ENV-PROJECTION-1), keeping that pid.
const tools_script =
    \\build_env=$1
    \\shift
    \\if [ -z "${ZIG_GLOBAL_CACHE_DIR+set}" ]; then
    \\  if [ -n "${XDG_CACHE_HOME:-}" ]; then ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/zig"
    \\  elif [ -n "${HOME:-}" ]; then ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/zig"; fi
    \\fi
    \\if [ -n "${ZIG_GLOBAL_CACHE_DIR+set}" ]; then export ZIG_GLOBAL_CACHE_DIR; fi
    \\ZIG_LOCAL_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mylang-zig-local.XXXXXX") || exit 2
    \\export ZIG_LOCAL_CACHE_DIR
    \\(trap '' HUP INT TERM; while kill -0 $$ 2>/dev/null; do sleep 1; done; rm -rf "$ZIG_LOCAL_CACHE_DIR") </dev/null >/dev/null 2>&1 &
    \\exec "$build_env" project -- env "$@"
;
/// Refuse a configuration in which any Run step carries its own environment
/// map. The build runner stores that map, a copy of the configure-time
/// environment, in the cached configuration and never refreshes it, so such a
/// step would test whatever environment first configured this cache (see
/// `withTools`). Walks every step reachable from a top-level step.
fn requireLiveEnvironment(b: *std.Build) void {
    var seen: std.AutoHashMapUnmanaged(*std.Build.Step, void) = .empty;
    var pending: std.ArrayList(*std.Build.Step) = .empty;
    for (b.top_level_steps.values()) |top| pending.append(b.allocator, &top.step) catch @panic("out of memory");
    while (pending.pop()) |step| {
        if ((seen.getOrPut(b.allocator, step) catch @panic("out of memory")).found_existing) continue;
        if (step.cast(std.Build.Step.Run)) |run| if (run.environ_map != null) {
            std.debug.print("error: build step '{s}' sets its own environment, which a cached configuration freezes; pass variables through withTools instead\n", .{step.name});
            std.process.exit(2);
        };
        pending.appendSlice(b.allocator, step.dependencies.items) catch @panic("out of memory");
    }
}
/// A test driver outside Zig (Python, or the compiler on a whole tree) whose
/// verdict is a pure function of `entries`, its command and the tools: cached,
/// bounded, and checked for exit status 0. The build runner discards a checked
/// step's standard output, so the command's standard output is sent to standard
/// error, which it keeps and prints when the step fails. `name` labels the step
/// in the build summary, where every such step would otherwise read `run sh`.
fn driver(b: *std.Build, name: []const u8, bytes: u64, list: []const u8) *std.Build.Step.Run {
    const run = bounded(b.addSystemCommand(&.{ "sh", "-c", "exec \"$@\" 1>&2", "driver" }), bytes);
    run.setName(name);
    run.setCwd(b.path("."));
    run.expectExitCode(0);
    cached(run, list);
    return run;
}
/// Declare a step's resident-memory ceiling, give it the toolchain a guest build
/// needs (harmless on steps that build no guest), and run it after the install.
fn bounded(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    step.step.max_rss = bytes;
    withTools(step);
    if (install_all) |install| step.step.dependOn(install);
    return step;
}
/// A focused test step: bound it and name the toolchain, without the install
/// graph. The test binary names the compiler it runs through a build option, so
/// a focused test waits only on that compile, never on Guardian.
fn focused(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    if (install_components) |components| step.step.dependOn(components);
    step.step.max_rss = bytes;
    withTools(step);
    // A test command must execute and report its selection; otherwise a warm
    // cache reuses the previous verdict and hides the selected-test count.
    step.has_side_effects = true;
    return step;
}
/// Forward the compiler-applied `-Dtest-filter` values to the Guardian runner.
/// Zig already excludes non-matching named tests at compile time; telling the
/// runner the filter lets it refuse a filter that named nothing instead of
/// silently passing with only the unnamed `test { }` blocks it cannot filter.
fn forwardFilters(b: *std.Build, step: *std.Build.Step.Run, filters: []const []const u8) void {
    for (filters) |filter| step.addArg(b.fmt("--guardian-filter={s}", .{filter}));
}
/// How to split one test root: its shard count, each shard's resident-memory
/// ceiling, the list naming the repository files its tests read
/// (`build_test_inputs.zig`), the
/// whole-root run a count of 1 uses instead, and — for the focused sharded
/// steps — the `-Dtest-filter` values to forward and whether to cache verdicts.
const Shards = struct {
    count: usize,
    bytes: u64,
    inputs: []const u8,
    whole: *std.Build.Step.Run,
    filters: []const []const u8 = &.{},
    cache: bool = true,
    /// Whether the root runs the component builder (`withTestPaths`).
    component_builder: bool = false,
};
/// The runs that cover one test root: `count` shards of the same test binary,
/// each executing the slice of the root's named tests that `--guardian-shard=`
/// assigns it, or the caller's single whole-root run when `count` is 1. The
/// shards partition the root — Guardian's runner gives the unnamed `test { }`
/// blocks to shard 0 alone — so together they run every test exactly once, and
/// the build runner schedules them concurrently against its `--maxrss` budget.
/// A shard's verdict is cached on the test binary, the tools and the declared
/// inputs, so an unchanged rerun of the gate does not execute it again; the
/// whole-root run stays uncached because `test-units`/`test-cli` report its
/// selected count every time.
fn shardRuns(b: *std.Build, compile: *std.Build.Step.Compile, shards: Shards) []const *std.Build.Step {
    if (shards.count <= 1) return b.allocator.dupe(*std.Build.Step, &.{&shards.whole.step}) catch @panic("out of memory");
    const steps = b.allocator.alloc(*std.Build.Step, shards.count) catch @panic("out of memory");
    for (steps, 0..) |*step, index| {
        const run = focused(b.addRunArtifact(compile), shards.bytes);
        withTestPaths(run, shards.component_builder);
        guardian.announceShard(run, index, shards.count);
        // The shards run at once, so each runs a test's batch of guest programs on
        // its share of the CPUs (`src/wiring/core_runner.zig`).
        withVariable(run, b.fmt("MYLANG_UNIT_SHARDS={d}", .{shards.count}));
        forwardFilters(b, run, shards.filters);
        if (shards.cache) cached(run, shards.inputs);
        step.* = &run.step;
    }
    return steps;
}
/// Make `step` wait on every run that covers a test root.
fn dependOnAll(step: *std.Build.Step, runs: []const *std.Build.Step) void {
    for (runs) |run| step.dependOn(run);
}
/// Guardian's `addAllChecks` returns nothing, so bound the check steps it has
/// just appended to `step`, which are the run steps naming its executable.
fn boundedChecks(step: *std.Build.Step) void {
    for (step.dependencies.items) |dependency| {
        if (std.mem.indexOf(u8, dependency.name, "guardian-check") != null) dependency.max_rss = rss.gate;
    }
}

/// Give `module` the user guides `mylang docs` prints: one anonymous import per
/// topic in `src/user_docs.zig`, named as `src/docs_command.zig` embeds it, so
/// the guides ship inside the compiler and an edited page rebuilds it.
fn addUserDocs(b: *std.Build, module: *std.Build.Module) void {
    const user_docs = @import("src/user_docs.zig");
    for (user_docs.topics) |topic| {
        module.addAnonymousImport(b.fmt("{s}{s}", .{ user_docs.import_prefix, topic.name }), .{ .root_source_file = b.path(topic.path) });
    }
}

/// `zig build bench-parity`: the standing mylang/Zig/Rust parity benchmark under
/// `bench/parity`. It builds every arm with the compiler this build installs (or
/// `-Dbench-mylang=PATH`), requires byte-identical output, times pinned
/// interleaved rounds and checks each program's ratio to Zig ReleaseFast against
/// `bench/parity/thresholds.json`. Opt-in: nothing else depends on it, so
/// `zig build test` never builds or times it. Arguments after `--` reach the
/// harness (`--json PATH`, `--arms ...`, `--write-thresholds`).
fn addParityBench(b: *std.Build) void {
    const cpu = b.option(u32, "bench-cpu", "bench-parity: the one CPU every timed process is pinned to (default: first of MYLANG_TIMING_CPUS, else 2)");
    const rounds = b.option(u32, "bench-rounds", "bench-parity: timed rounds per program (default 7)") orelse 7;
    const filter = b.option([]const u8, "bench-filter", "bench-parity: comma-separated substrings of GROUP/NAME, e.g. sieve or micro/");
    const compiler = b.option([]const u8, "bench-mylang", "bench-parity: time this compiler instead of the one this build installs");
    const bench = b.addSystemCommand(&.{ "python3", "bench/parity/bench_parity.py", "run", "--zig", b.graph.zig_exe });
    bench.setCwd(b.path("."));
    // Without -Dbench-cpu the harness picks the first preferred timing CPU itself.
    if (cpu) |index| bench.addArgs(&.{ "--cpu", b.fmt("{d}", .{index}) });
    bench.addArgs(&.{ "--rounds", b.fmt("{d}", .{rounds}) });
    if (filter) |needle| {
        if (std.mem.trim(u8, needle, " \t\r\n,").len == 0) {
            std.debug.print("error: -Dbench-filter= needs a non-empty substring; omit it to run every program\n", .{});
            std.process.exit(2);
        }
        bench.addArgs(&.{ "--filter", needle });
    }
    if (compiler) |path| {
        bench.addArgs(&.{ "--mylang", path });
    } else {
        bench.addArg("--mylang");
        bench.addFileArg(.{ .relative = .{ .base = .install_bin, .sub_path = "mylang" } });
        bench.step.dependOn(b.getInstallStep());
    }
    bench.addPassthruArgs();
    bench.has_side_effects = true;
    bench.step.max_rss = rss.parity;
    b.step("bench-parity", "Time mylang against Zig and Rust on the parity suite and check ratio thresholds (opt-in)").dependOn(&bench.step);
}

/// What the new core's steps build on: the shared front end module and the
/// `mylang` executable whose commands the core provides.
const CoreInputs = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    front_end: *std.Build.Module,
    compiler: *std.Build.Step.Compile,
    filters: []const []const u8,
    /// Guardian's test runner, which can run one shard of the root (`--guardian-shard`).
    test_runner: std.Build.Step.Compile.TestRunner,
    /// Generated identity over every production compiler and runtime source.
    identity: *std.Build.Module,
};

/// The new compiler core (docs/design/new-core-ir.md), which `mylang` runs for
/// every command that builds, runs or tests code (S5-D8: one binary):
/// - `src/core/cli.zig` becomes the `mylang_core` module of the `mylang`
///   executable;
/// - `zig build test-core` runs the core's unit tests and its end-to-end slice,
///   which drive that `mylang`, split into `-Dcore-shards=N` concurrent shards of
///   one test binary (default 8; a `-Dtest-filter` run is one process); it returns
///   that step, which `zig build test` depends on.
fn addCore(b: *std.Build, inputs: CoreInputs) *std.Build.Step {
    const platform = b.createModule(.{ .root_source_file = b.path("src/config_core_tool_platform.zig") });
    // A separate object also optimizes the standard-library SHA rounds, which
    // otherwise inherit the root's Debug mode even through an optimized module.
    const juice_bytes_hash = b.addObject(.{ .name = "juice_bytes_hash", .max_rss = rss.compile, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/juice/bytes_hash_impl.zig"),
        .target = inputs.target,
        .optimize = .ReleaseFast,
        .pic = true,
    }) });
    // The test runner's frame and byte ceilings share the run budget rules.
    const budget = b.modules.get("memory_budget") orelse @panic("memory_budget module");
    const unit = b.addTest(.{ .max_rss = rss.compile, .filters = inputs.filters, .test_runner = inputs.test_runner, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root_test.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{.{ .name = "mylang", .module = inputs.front_end }},
    }) });
    verification_core_binary = unit;
    unit.root_module.addImport("core_tool_platform", platform);
    unit.root_module.addImport("build_identity", inputs.identity);
    unit.root_module.addImport("memory_budget", budget);
    // The compiler and fixture paths arrive at run time (TEST-PATHS-1).
    unit.root_module.addImport("core_test_options", test_paths.?);
    // The number-text helper's target and CPU are fixed (`-mcpu baseline`), so it is
    // compiled once here and embedded, rather than by `zig build-obj` on a guest
    // machine's first build that prints a number (NEW-CORE-S3-NUMBER-1). It is
    // embedded as bytes, so its debug information would carry this tree's path
    // into the compiler, the core test binary and every guest program that links
    // it (TEST-PATHS-1); the object is built without it.
    const number_text = b.addObject(.{ .name = "core_number_text", .max_rss = rss.compile, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/runtime/core_number_text.zig"),
        .target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux-gnu.2.31", .cpu_features = "baseline" }) catch @panic("number-text target")),
        .optimize = .ReleaseFast,
        .strip = true,
        .pic = true,
        .stack_check = false,
        .stack_protector = false,
        .link_libc = true,
    }) });
    // `mylang` runs the new core for every command that builds, runs or tests
    // code. Its commands live in `src/core/cli.zig`, a module of its own; the core
    // reaches the front end only as `mylang`.
    const cli = b.createModule(.{
        .root_source_file = b.path("src/core/cli.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{ .{ .name = "mylang", .module = inputs.front_end }, .{ .name = "core_tool_platform", .module = platform }, .{ .name = "build_identity", .module = inputs.identity }, .{ .name = "memory_budget", .module = budget } },
    });
    inputs.compiler.root_module.addImport("mylang_core", cli);
    for ([_]*std.Build.Module{ unit.root_module, cli }) |module| {
        module.addObject(juice_bytes_hash);
        module.addAnonymousImport("core_number_text_object", .{ .root_source_file = number_text.getEmittedBin() });
    }
    const step = b.step("test-core", "Run the new core's unit tests and its end-to-end slice");
    const test_binary = b.addInstallFileWithDir(unit.getEmittedBin(), .{ .custom = "focus" }, "core-tests");
    b.step("core-test-binary", "Compile the registered Core tests without provisioning components").dependOn(&test_binary.step);
    // Most of the root's time is end-to-end builds of guest programs, so shards
    // of the one binary run concurrently; each test uses its own temporary tree.
    const requested = b.option(usize, "core-shards", "test-core: concurrent shards of the core test root (default 8)") orelse 8;
    const shards = if (inputs.filters.len == 0) @max(1, requested) else 1;
    for (0..shards) |index| {
        const run = focused(b.addRunArtifact(unit), rss.driver);
        withTestPaths(run, false);
        verification_registry.?.declared(&run.step, "core");
        forwardFilters(b, run, inputs.filters);
        if (shards > 1) guardian.announceShard(run, index, shards);
        step.dependOn(&run.step);
    }
    return step;
}

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.0-dev.1683+5ceec001b"))
        @panic("mylang requires Guardian's Zig 0.17.0-dev.1683+5ceec001b toolchain (see .zigversion)");
    const target = b.resolveTargetQuery(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dtest-filter=SUBSTRING` narrows the unit and CLI suites to one area in seconds.
    // It may be repeated; a test runs when its name contains any of the substrings,
    // which is how `scripts/affected_tests.py` selects several areas in one build.
    // An absent flag runs every test; an explicitly empty one is a footgun that
    // silently selects the whole suite, so reject it before it reaches a test root.
    const test_filters: []const []const u8 = if (b.option([]const []const u8, "test-filter", "Run only Zig tests whose name contains this substring (repeatable)")) |needles| blk: {
        for (needles) |needle| if (std.mem.trim(u8, needle, " \t\r\n").len == 0) {
            std.debug.print("error: -Dtest-filter= needs a non-empty substring; run `zig build test` for the full suite\n", .{});
            std.process.exit(2);
        };
        break :blk b.dupeStrings(needles);
    } else &.{};
    // `-Dtest-shards=N` splits the two slow test roots across N processes the
    // build runner schedules in parallel; `-Dtest-shards=1` is one process per
    // root, which is what the gate did before sharding existed. A filter is
    // incompatible with it by construction: the compiler has already dropped
    // every non-matching test, so splitting the handful that remain eight ways
    // yields empty shards and counts nobody can read. A filtered run therefore
    // falls back to the single whole-root runs `test-units`/`test-cli` use.
    const requested_shards = b.option(
        usize,
        "test-shards",
        "Split the unit and CLI test roots across this many parallel processes (default 12; 1 disables sharding)",
    ) orelse 12;
    if (requested_shards == 0) {
        std.debug.print("error: -Dtest-shards= needs a positive count; -Dtest-shards=1 runs each root in one process\n", .{});
        std.process.exit(2);
    }
    test_rerun = b.option(bool, "test-rerun", "Run every cached test step even when none of its declared inputs changed") orelse false;
    build_env = @import("build_env.zig").tool(b, rss.compile);
    test_paths = b.createModule(.{ .root_source_file = b.path("src/core/test_paths.zig"), .target = target, .optimize = optimize });
    verification_registry = .{ .build = b, .controls = .{ .filtered = test_filters.len != 0, .rerun = test_rerun, .optimize = @tagName(optimize) } };
    const unit_shards = if (test_filters.len == 0) requested_shards else 1;
    // The CLI root is both smaller and coarser than the unit root, so it takes
    // half the shards; a wider fan-out oversubscribes the core budget and made
    // the whole gate slower even though it shortened the slowest CLI shard.
    const cli_shards = if (test_filters.len == 0) @max(1, requested_shards / 2) else 1;
    // The compiler and the new core's test runner import the byte ceilings as a
    // module, so the file has one owner and its own test root.
    const budget = b.addModule("memory_budget", .{
        .root_source_file = b.path("src/memory_budget.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core = b.addModule("mylang", .{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addImport("memory_budget", budget);
    const exe = b.addExecutable(.{
        .max_rss = if (optimize == .fast) rss.compiler_fast else rss.compile,
        .name = "mylang",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "mylang", .module = core }, .{ .name = "memory_budget", .module = budget } },
        }),
    });
    // A command file that the unit root also compiles reaches the front end
    // through its root's `compiler_language`, never by a second module path.
    exe.root_module.addImport("compiler_root", exe.root_module);
    addUserDocs(b, exe.root_module);
    const identity = @import("build_identity.zig").module(b, target, optimize, .{ .compile = rss.compile, .run = rss.driver });
    exe.root_module.addImport("build_identity", identity);
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    // The pin's LLVM ReleaseSafe code avoids accelerated SHA-256's AVX/SSE
    // transition regression. Require LLVM: native-backend ReleaseSafe still
    // reproduces it. Seed and component build settings remain independent.
    const component_tool = b.addExecutable(.{
        .max_rss = rss.compile,
        .name = "selka-components",
        .use_llvm = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("selfhost/components.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = .ReleaseSafe,
        }),
    });
    const install_component_tool = b.addInstallFileWithDir(component_tool.getEmittedBin(), .{ .custom = "tools" }, "selka-components");
    b.getInstallStep().dependOn(&install_component_tool.step);
    b.step("component-builder", "Build the native bootstrap coordinator without provisioning a seed").dependOn(&install_component_tool.step);
    const component_owned_pin = b.option([]const u8, "component-owned-compiler-pin", "Independent checked-owned component compiler source pin (optional qualification route)");
    const component_seed_source = b.option([]const u8, "component-seed-source", "Verified source archive for provisioning the selected component compiler pin");
    const component_build = b.addRunArtifact(component_tool);
    component_build.addArg("--root");
    component_build.addDirectoryArg2(b.path("."), .{ .make_absolute = true });
    component_build.addArgs(&.{ "--zig", b.graph.zig_exe, "--install-dir" });
    component_build.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components" } }, .{ .make_absolute = true });
    if (component_owned_pin) |pin| {
        component_build.addArg("--owned-compiler-pin");
        component_build.addFileArg(if (std.fs.path.isAbsolute(pin)) b.graph.cwdRelativePath(pin) else b.path(pin));
    }
    if (component_seed_source) |archive| {
        component_build.addArg("--seed-source");
        component_build.addFileArg(if (std.fs.path.isAbsolute(archive)) b.graph.cwdRelativePath(archive) else b.path(archive));
    }
    component_build.setCwd(b.path("."));
    component_build.has_side_effects = true;
    component_build.step.max_rss = rss.compiler_fast;
    verification_registry.?.register("component-preparation", &component_build.step, &test_inputs.component_inputs, false, "component manifests and installed outputs require validation");
    install_components = &component_build.step;
    b.getInstallStep().dependOn(&component_build.step);
    const components_step = b.step("components", "Build and install pinned-seed Selka components without rebuilding the host");
    components_step.dependOn(&component_build.step);
    components_step.dependOn(&install_component_tool.step);
    tool_inputs = .{exe.getEmittedBin()};
    component_builder_bin = component_tool.getEmittedBin();
    addInputManifests(b);
    addEnvironmentManifest(b);
    // Guest-running drivers invoke an uninstalled compiler with no toolchain
    // beside it; name this build's Zig for them through the environment.
    tool_zig = b.graph.zig_exe;
    // The compiler `scripts/affected_tests.py` runs guest tests and doctests with:
    // an unattached copy, so the inner loop never waits on Guardian. It is a file
    // copy, not a second artifact install: a run step names an artifact by the
    // path its install left, so two installs of one artifact would make that
    // path (and every cache key holding it) depend on which install ran last.
    const focus_exe_step = b.addInstallFileWithDir(exe.getEmittedBin(), .{ .custom = "focus" }, "mylang");
    const affected_compiler = b.step("affected-compiler", "Install only mylang to zig-out/focus, for scripts/affected_tests.py");
    affected_compiler.dependOn(&focus_exe_step.step);
    affected_compiler.dependOn(&component_build.step);
    const seed_compiler = b.step("seed-compiler", "Install only mylang to zig-out/focus without provisioning components");
    seed_compiler.dependOn(&focus_exe_step.step);
    install_all = b.getInstallStep();
    const guardian_dep = b.dependency("guardian", .{ .target = target, .optimize = optimize });
    const guardian_exe = guardian_dep.artifact("guardian-check");
    const run = bounded(b.addRunArtifact(exe), rss.guest);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const tooling_unit = b.addTest(.{
        .name = "tooling-unit-tests",
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tooling_root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    guardian.enableTestDiagnostics(tooling_unit.root_module);
    const text_scalar_unit = b.addTest(.{
        .name = "text-scalar-unit-tests",
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/text_scalar_root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    guardian.enableTestDiagnostics(text_scalar_unit.root_module);
    const unit = b.addTest(.{
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit.root_module.addImport("build_identity", identity);
    unit.root_module.addImport("memory_budget", budget);
    unit.root_module.addImport("compiler_root", unit.root_module);
    addUserDocs(b, unit.root_module);
    // The environment identity golden fixture (ENV-IDENTITY-2) is embedded, so it
    // is a compile input of the unit binary rather than a path read at run time.
    for ([_][]const u8{ "environment", "classification", "tools", "digest-guest", "digest-host" }) |name| {
        unit.root_module.addAnonymousImport(b.fmt("environment-identity/{s}.txt", .{name}), .{ .root_source_file = b.path(b.fmt("test/fixtures/environment-identity/{s}.txt", .{name})) });
    }
    // Unit tests build and run guest programs with `mylang`, which the root cannot
    // import (NEW-CORE-S5-UNITS-1), through one shared cache.
    const native_test_options = b.addOptions();
    native_test_options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    native_test_options.addOption([]const u8, "cache_directory", ".mylang-cache/unit-tests");
    unit.root_module.addOptions("native_test_options", native_test_options);
    unit.root_module.addImport("test_paths", test_paths.?);
    const core_tests = addCore(b, .{ .target = target, .optimize = optimize, .front_end = core, .compiler = exe, .filters = test_filters, .test_runner = guardian.testRunner(guardian_dep), .identity = identity });
    _ = b.option(bool, "compiler-only", "Accepted for older scripts: install mylang and its required components");
    guardian.addAllChecks(b, guardian_exe, b.getInstallStep(), .{});
    boundedChecks(b.getInstallStep());
    // The compiler and component builder arrive at run time (`withTestPaths`).
    const options = b.addOptions();
    // The optional component pins reach the bootstrap test as given, never as a
    // path this build resolves: a relative one names a file under the build
    // root, the test's working directory (TEST-PATHS-1).
    options.addOption([]const u8, "component_owned_compiler_pin", component_owned_pin orelse "");
    options.addOption([]const u8, "component_seed_source", component_seed_source orelse "");
    options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    options.addOption([]const u8, "semantic_cache_version", @import("src/semantic_store.zig").format_version);
    const integration = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    integration.root_module.addOptions("test_options", options);
    integration.root_module.addImport("test_paths", test_paths.?);
    guardian.enableTestDiagnostics(unit.root_module);
    guardian.enableTestDiagnostics(integration.root_module);
    const compile_tests = b.step("test-compile", "Compile every Zig test without running the suite");
    compile_tests.dependOn(&unit.step);
    compile_tests.dependOn(&integration.step);
    const run_integration = focused(b.addRunArtifact(integration), rss.suite);
    withTestPaths(run_integration, true);
    forwardFilters(b, run_integration, test_filters);
    const test_step = b.step("test", "Run the compiler, new-core, CLI, guest-language and tooling regression tests");
    b.step("test-interpreter", "Alias of test, kept for older scripts").dependOn(test_step);
    guardian.addAllChecks(b, guardian_exe, test_step, .{});
    boundedChecks(test_step);
    // Named modules' inline tests are excluded from importing roots by Zig.
    // Give the byte ceilings their own runner so MEMORY-CEILING-* is gated.
    const budget_unit = b.addTest(.{
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .root_module = budget,
    });
    guardian.enableTestDiagnostics(budget_unit.root_module);
    // Pure native tooling consumes its own executable and declared closure.
    // Do not use cached()/bounded(): those bind compiler/component artifacts.
    const run_tooling_unit = b.addRunArtifact(tooling_unit);
    run_tooling_unit.step.max_rss = rss.script;
    run_tooling_unit.setCwd(b.path("."));
    run_tooling_unit.has_side_effects = test_rerun;
    run_tooling_unit.addFileInput(input_manifests.?.path(b, "tooling_unit.txt"));
    run_tooling_unit.addFileInput(environment_manifest.?);
    forwardFilters(b, run_tooling_unit, test_filters);
    verification_registry.?.declared(&run_tooling_unit.step, "tooling_unit");
    test_step.dependOn(&run_tooling_unit.step);
    compile_tests.dependOn(&tooling_unit.step);
    const focused_tooling = b.addRunArtifact(tooling_unit);
    focused_tooling.step.max_rss = rss.script;
    focused_tooling.setCwd(b.path("."));
    focused_tooling.has_side_effects = true;
    forwardFilters(b, focused_tooling, test_filters);
    b.step("test-tooling-units", "Run independent pure tooling tests, honouring -Dtest-filter").dependOn(&focused_tooling.step);
    const run_text_scalar_unit = b.addRunArtifact(text_scalar_unit);
    run_text_scalar_unit.step.max_rss = rss.script;
    run_text_scalar_unit.setCwd(b.path("."));
    run_text_scalar_unit.has_side_effects = test_rerun;
    run_text_scalar_unit.addFileInput(input_manifests.?.path(b, "text_scalar_unit.txt"));
    run_text_scalar_unit.addFileInput(environment_manifest.?);
    forwardFilters(b, run_text_scalar_unit, test_filters);
    verification_registry.?.declared(&run_text_scalar_unit.step, "text_scalar_unit");
    test_step.dependOn(&run_text_scalar_unit.step);
    compile_tests.dependOn(&text_scalar_unit.step);
    const focused_text_scalar = b.addRunArtifact(text_scalar_unit);
    focused_text_scalar.step.max_rss = rss.script;
    focused_text_scalar.setCwd(b.path("."));
    focused_text_scalar.has_side_effects = true;
    forwardFilters(b, focused_text_scalar, test_filters);
    b.step("test-text-scalar-units", "Run independent scalar text tests, honouring -Dtest-filter").dependOn(&focused_text_scalar.step);
    const run_budget_unit = bounded(b.addRunArtifact(budget_unit), rss.driver);
    cached(run_budget_unit, "memory_budget");
    const budget_step = b.step("test-memory-budget", "Verify guest byte ceilings, kernel guards and fan-out bounds");
    budget_step.dependOn(&run_budget_unit.step);
    test_step.dependOn(&run_budget_unit.step);
    compile_tests.dependOn(&budget_unit.step);
    const run_unit = focused(b.addRunArtifact(unit), rss.suite);
    withTestPaths(run_unit, false);
    forwardFilters(b, run_unit, test_filters);
    verification_registry.?.declared(&run_unit.step, "unit");
    verification_registry.?.declared(&run_integration.step, "cli");
    // The gate runs each slow root as several concurrent shards; `test-units`
    // and `test-cli` keep the single whole-root run, so `-Dtest-filter` behaves
    // exactly as documented and its selected-test count means what it says.
    const unit_runs = shardRuns(b, unit, .{ .count = unit_shards, .bytes = rss.shard_unit, .inputs = "unit", .whole = run_unit });
    const cli_runs = shardRuns(b, integration, .{ .count = cli_shards, .bytes = rss.shard_cli, .inputs = "cli", .whole = run_integration, .component_builder = true });
    dependOnAll(test_step, unit_runs);
    // The fast inner loops: no Python drivers, no Guardian and no full install graph,
    // so `-Dtest-filter` returns in seconds.
    const units_step = b.step("test-units", "Run compiler and pure tooling units; filters select the compiler root");
    units_step.dependOn(&run_unit.step);
    if (test_filters.len == 0) units_step.dependOn(&focused_tooling.step);
    if (test_filters.len == 0) units_step.dependOn(&focused_text_scalar.step);
    b.step("test-cli", "Run only test/integration.zig, honouring -Dtest-filter").dependOn(&run_integration.step);
    // The same focused runs split into `-Dtest-shards` concurrent processes even
    // under a filter, for `scripts/affected_tests.py`: its selections can name a
    // hundred slow tests, and it sums the shards' counts itself. They are never
    // cached, so every run reports what it selected.
    const units_sharded = b.step("test-units-sharded", "Run src/root_test.zig split into -Dtest-shards processes, honouring -Dtest-filter");
    if (test_filters.len == 0) units_sharded.dependOn(&focused_tooling.step);
    if (test_filters.len == 0) units_sharded.dependOn(&focused_text_scalar.step);
    const cli_sharded = b.step("test-cli-sharded", "Run test/integration.zig split into -Dtest-shards/2 processes, honouring -Dtest-filter");
    dependOnAll(units_sharded, shardRuns(b, unit, .{ .count = requested_shards, .bytes = rss.shard_unit, .inputs = "", .whole = run_unit, .filters = test_filters, .cache = false }));
    dependOnAll(cli_sharded, shardRuns(b, integration, .{ .count = @max(1, requested_shards / 2), .bytes = rss.shard_cli, .inputs = "", .whole = run_integration, .filters = test_filters, .cache = false, .component_builder = true }));
    dependOnAll(test_step, cli_runs);
    const audit_runtime = b.step("test-runtime-audit", "Run every Zig test root for isolated runtime probes");
    guardian.addAllChecks(b, guardian_exe, audit_runtime, .{});
    boundedChecks(audit_runtime);
    audit_runtime.dependOn(&focused_tooling.step);
    audit_runtime.dependOn(&focused_text_scalar.step);
    dependOnAll(audit_runtime, unit_runs);
    dependOnAll(audit_runtime, cli_runs);
    const intent_step = b.step("test-intent", "Verify requirement links, revisions and source-pinned evidence");
    guardian.addAllChecks(b, guardian_exe, intent_step, .{});
    boundedChecks(intent_step);
    const verification_step = b.step("test-verification", "Verify dependency selection, cache, scheduler and merge certificates");
    guardian.addAllChecks(b, guardian_exe, verification_step, .{});
    boundedChecks(verification_step);
    const repair_step = b.step("test-repair-study", "Verify repair-study fixtures and retained evidence");
    guardian.addAllChecks(b, guardian_exe, repair_step, .{});
    boundedChecks(repair_step);
    // The checked-in golden corpora `tests/goldens/qbe_*.json` hold the old core's
    // answers (expected stdout, exit status and trap per case), frozen when the old
    // back end was retired; the replay runs each case through this `mylang run`.
    const golden_step = b.step("test-golden", "Replay the checked-in golden corpora through mylang run with no Python oracle");
    const golden_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
        .root_source_file = b.path("test/golden_parity.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    golden_unit.root_module.addOptions("test_options", options);
    golden_unit.root_module.addImport("test_paths", test_paths.?);
    guardian.enableTestDiagnostics(golden_unit.root_module);
    compile_tests.dependOn(&golden_unit.step);
    const run_golden = bounded(b.addRunArtifact(golden_unit), rss.suite);
    withTestPaths(run_golden, false);
    cached(run_golden, "golden");
    forwardFilters(b, run_golden, test_filters);
    run_golden.setCwd(b.path("."));
    golden_step.dependOn(&run_golden.step);
    test_step.dependOn(golden_step);
    const agent_tools = b.step("test-agent-tools", "Verify compact feedback, byte-contract fixtures, and compiler-pinned references");
    guardian.addAllChecks(b, guardian_exe, agent_tools, .{});
    boundedChecks(agent_tools);
    const idiom_step = b.step("test-idioms", "Measure Python-shaped idioms and reject regressions");
    const idiom_self_test = driver(b, "python3 tests/idiom_probes.py --self-test", rss.script, "idioms_self");
    idiom_self_test.addArgs(&.{ "python3", "tests/idiom_probes.py", "--self-test" });
    idiom_step.dependOn(&idiom_self_test.step);
    const idiom_run = driver(b, "python3 tests/idiom_probes.py --compiler", rss.driver, "idioms");
    idiom_run.addArgs(&.{ "python3", "tests/idiom_probes.py", "--compiler" });
    idiom_run.addArtifactArg(exe);
    idiom_step.dependOn(&idiom_run.step);
    test_step.dependOn(idiom_step);
    // Incremental `check` must answer exactly what a cold check answers: a
    // seeded mutation walk over a small project compares the two byte for byte.
    const incremental_step = b.step("test-incremental", "Compare cached and cold check over seeded source mutations");
    const incremental_run = driver(b, "python3 tests/incremental_diff.py", rss.driver, "incremental");
    incremental_run.addArgs(&.{ "python3", "tests/incremental_diff.py", "--steps", "120" });
    incremental_run.addArtifactArg(exe);
    incremental_step.dependOn(&incremental_run.step);
    // The same walk over a project whose modules sit in subdirectories under a
    // `mylang.json`.
    const incremental_projects = driver(b, "python3 tests/incremental_diff.py --project tests/fixtures/module_projects", rss.driver, "incremental");
    incremental_projects.addArgs(&.{ "python3", "tests/incremental_diff.py", "--steps", "60", "--project", "tests/fixtures/module_projects" });
    incremental_projects.addArtifactArg(exe);
    incremental_step.dependOn(&incremental_projects.step);
    test_step.dependOn(incremental_step);
    // MODULE-INTERFACE-2/3: a seeded mutation walk asserts which edits keep a
    // module's interface hash and which change it, and every module of
    // `tests/lang` and the interface fixtures, checked against its imports'
    // interfaces alone, must equal the whole-program check.
    const interfaces_step = b.step("test-interfaces", "Module interface hashes over seeded mutations, and the per-module check oracle");
    const interfaces_run = driver(b, "python3 tests/interface_diff.py", rss.driver, "interfaces");
    interfaces_run.addArgs(&.{ "python3", "tests/interface_diff.py", "--steps", "120" });
    interfaces_run.addArtifactArg(exe);
    interfaces_step.dependOn(&interfaces_run.step);
    const generic_run = driver(b, "python3 tests/interface_diff.py --project tests/fixtures/interfaces_generic", rss.driver, "interfaces");
    generic_run.addArgs(&.{ "python3", "tests/interface_diff.py", "--steps", "40", "--project", "tests/fixtures/interfaces_generic" });
    generic_run.addArtifactArg(exe);
    interfaces_step.dependOn(&generic_run.step);
    const oracle_run = driver(b, "python3 tests/interface_oracle.py", rss.driver, "interface_oracle");
    oracle_run.addArgs(&.{ "python3", "tests/interface_oracle.py" });
    oracle_run.addArtifactArg(exe);
    oracle_run.addArgs(&.{ "tests/lang", "tests/fixtures/interfaces/main.my", "tests/fixtures/interfaces_generic/main.my", "tests/fixtures/incremental/main.my" });
    interfaces_step.dependOn(&oracle_run.step);
    test_step.dependOn(interfaces_step);
    // The repair-round packages ship two Python drivers beside their Zig tests:
    // the parser-hint/classifier agreement (static, then end to end against this
    // compiler) and the friction harvest over its replay fixture. Registering
    // them here keeps them from rotting outside the gate.
    const usefulness_step = b.step("test-agent-usefulness", "Verify parser hints, headerless imports, and the friction harvest");
    const hints_static = driver(b, "python3 tests/parser_hints.py", rss.script, "parser_hints");
    hints_static.addArgs(&.{ "python3", "tests/parser_hints.py" });
    usefulness_step.dependOn(&hints_static.step);
    const hints_run = driver(b, "python3 tests/parser_hints.py --compiler", rss.driver, "parser_hints");
    hints_run.addArgs(&.{ "python3", "tests/parser_hints.py", "--compiler" });
    hints_run.addArtifactArg(exe);
    usefulness_step.dependOn(&hints_run.step);
    const harvest_run = driver(b, "python3 tests/test_friction_harvest.py", rss.script, "friction");
    harvest_run.addArgs(&.{ "python3", "tests/test_friction_harvest.py" });
    usefulness_step.dependOn(&harvest_run.step);
    test_step.dependOn(usefulness_step);
    const isolation_step = b.step("test-cache-isolation", "Verify no-cache and doctest scratch isolation, frame advice and guest ceilings");
    const isolation_run = driver(b, "python3 tests/tooling_cache_isolation.py --compiler", rss.driver, "tooling_isolation");
    isolation_run.addArgs(&.{ "python3", "tests/tooling_cache_isolation.py", "--compiler" });
    isolation_run.addArtifactArg(exe);
    isolation_step.dependOn(&isolation_run.step);
    test_step.dependOn(isolation_step);
    const application_cache_step = b.step("test-application-cache", "Verify native persistent values and interrupted application recovery");
    const application_cache_run = driver(b, "python3 tests/application_cache.py --smoke --compiler", rss.driver, "application_cache");
    application_cache_run.addArgs(&.{ "python3", "tests/application_cache.py", "--smoke", "--compiler" });
    application_cache_run.addArtifactArg(exe);
    application_cache_step.dependOn(&application_cache_run.step);
    test_step.dependOn(application_cache_step);
    const component_tests = driver(b, "python3 selfhost/test_components.py", rss.script, "component_builder");
    component_tests.addArgs(&.{ "python3", "selfhost/test_components.py", "--zig", b.graph.zig_exe, "--builder" });
    component_tests.addArtifactArg(component_tool);
    const native_component_tests = driver(b, "pure Selka and native component qualification", rss.driver, "component_native");
    native_component_tests.addArgs(&.{ "python3", "selfhost/test_component_native.py", "--builder" });
    native_component_tests.addArtifactArg(component_tool);
    native_component_tests.addArgs(&.{ "--zig", b.graph.zig_exe, "--component-dir" });
    native_component_tests.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components" } }, .{ .make_absolute = true });
    if (component_owned_pin) |pin| {
        native_component_tests.addArg("--owned-compiler-pin");
        native_component_tests.addFileArg(if (std.fs.path.isAbsolute(pin)) b.graph.cwdRelativePath(pin) else b.path(pin));
    }
    if (component_seed_source) |archive| {
        native_component_tests.addArg("--seed-source");
        native_component_tests.addFileArg(if (std.fs.path.isAbsolute(archive)) b.graph.cwdRelativePath(archive) else b.path(archive));
    }
    const component_test_step = b.step("test-components", "Test pure Selka, native protocol, cache and failure boundaries");
    const component_support_tests = b.addTest(.{
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .root_module = b.createModule(.{
            .root_source_file = b.path("selfhost/component_support_test.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const run_component_support = b.addRunArtifact(component_support_tests);
    run_component_support.step.max_rss = rss.driver;
    run_component_support.has_side_effects = true;
    verification_registry.?.register("component-support", &run_component_support.step, &test_inputs.component_builder, true, "exact native support executable and declared inputs");
    b.step("test-component-support", "Test native streaming hashes, canonical identity and archive extraction").dependOn(&run_component_support.step);
    component_test_step.dependOn(&run_component_support.step);
    compile_tests.dependOn(&component_support_tests.step);
    component_test_step.dependOn(&component_tests.step);
    component_test_step.dependOn(&native_component_tests.step);
    test_step.dependOn(&run_component_support.step);
    test_step.dependOn(&native_component_tests.step);
    test_step.dependOn(&component_tests.step);
    const selfhost_numeric_step = b.step("test-selfhost-numeric", "Compare bootstrap and live numeric token extents");
    const selfhost_numeric_run = driver(b, "python3 selfhost/tests/run_lexer_diff.py --compiler", rss.driver, "selfhost_numeric");
    selfhost_numeric_run.addArgs(&.{ "python3", "selfhost/tests/run_lexer_diff.py", "--compiler" });
    selfhost_numeric_run.addArtifactArg(exe);
    selfhost_numeric_step.dependOn(&selfhost_numeric_run.step);
    test_step.dependOn(selfhost_numeric_step);
    // The SPEC.md merge driver (`scripts/merge_spec.py`): synthetic three-way
    // cases, a throwaway repository end to end, and a replay of real merges.
    const spec_merge_step = b.step("test-spec-merge", "Verify the SPEC.md merge driver, including replayed history");
    const spec_merge_run = bounded(b.addSystemCommand(&.{ "python3", "tests/test_spec_merge.py" }), rss.script);
    spec_merge_run.setCwd(b.path("."));
    verification_registry.?.register("spec-history", &spec_merge_run.step, &.{}, false, "SPEC replay reads git history and creates repositories");
    spec_merge_step.dependOn(&spec_merge_run.step);
    test_step.dependOn(spec_merge_step);
    // Work-based performance comparisons have no PMU/Valgrind dependency in
    // the gate; real collector qualification is an explicit developer run.
    const juice_step = b.step("test-juice", "Verify performance proxy contracts, collectors and comparison integrity");
    // These classes exercise synthetic records and private temporary fixtures.
    // Runner also compiles/executes C and observes host tools: keep it fresh.
    const juice_pure_run = driver(b, "Juice synthetic contracts and reports", rss.script, "juice_pure");
    juice_pure_run.addArgs(&.{ "python3", "tests/test_juice.py", "--pure" });
    juice_step.dependOn(&juice_pure_run.step);
    const juice_run = driver(b, "Juice native runner integration", rss.script, "juice");
    juice_run.addArgs(&.{ "python3", "tests/test_juice.py", "--native" });
    juice_step.dependOn(&juice_run.step);
    const juice_native_run = driver(b, "python3 tests/test_juice_native.py", rss.script, "juice");
    juice_native_run.addArgs(&.{ "python3", "tests/test_juice_native.py" });
    juice_native_run.addArtifactArg(exe);
    verification_registry.?.register("juice", &juice_native_run.step, &test_inputs.juice, false, "native performance collectors and host state require fresh execution");
    juice_step.dependOn(&juice_native_run.step);
    const juice_runtime_run = bounded(b.addSystemCommand(&.{ "python3", "tests/test_juice_runtime_bench.py" }), rss.script);
    juice_runtime_run.setCwd(b.path("."));
    verification_registry.?.register("juice-runtime", &juice_runtime_run.step, &test_inputs.juice_runtime, false, "runtime collectors observe CPU, scheduler and current host state");
    juice_step.dependOn(&juice_runtime_run.step);
    test_step.dependOn(juice_step);
    // The compiler's `compiler_identity` comes from a make-phase run of
    // `build_identity.zig`. This driver runs that file on throwaway trees that
    // share one Zig cache, the way a stale digest once reached an installed compiler.
    const identity_step = b.step("test-compiler-identity", "Verify the compiler identity follows its sources across trees and edits");
    const identity_run = bounded(b.addSystemCommand(&.{"python3"}), rss.driver);
    identity_run.addFileArg(b.path("tests/compiler_identity_cache.py"));
    identity_run.addArgs(&.{ "--zig", b.graph.zig_exe });
    identity_run.addFileInput(b.path("build_identity.zig"));
    identity_run.addFileInput(b.path("src/build_identity_rules.zig"));
    identity_run.addFileInput(environment_manifest.?);
    identity_run.expectExitCode(0);
    verification_registry.?.register("identity-qualification", &identity_run.step, &.{}, false, "compiler identity qualification produces temporary compiler artifacts");
    identity_step.dependOn(&identity_run.step);
    test_step.dependOn(identity_step);
    // The inner loop's own machinery: the change-to-test mapping behind
    // `scripts/affected_tests.py`, and the check that every repository file a
    // cached test root names is one of its declared inputs.
    const affected_step = b.step("test-affected-selection", "Pin scripts/affected_tests.py's change-to-test mapping");
    const affected_run = driver(b, "python3 tests/test_affected_tests.py", rss.script, "affected");
    affected_run.addArgs(&.{ "python3", "tests/test_affected_tests.py" });
    affected_step.dependOn(&affected_run.step);
    const focused_wrapper_tests = driver(b, "python3 tests/test_focused_test.py", rss.script, "affected");
    focused_wrapper_tests.addArgs(&.{ "python3", "tests/test_focused_test.py" });
    affected_step.dependOn(&focused_wrapper_tests.step);
    test_step.dependOn(affected_step);
    const coverage_step = b.step("test-inputs-coverage", "Require every repository file a cached test names to be a declared input");
    const coverage_self = driver(b, "python3 tests/test_inputs_coverage.py --self-test", rss.script, "coverage_self");
    coverage_self.addArgs(&.{ "python3", "tests/test_inputs_coverage.py", "--self-test" });
    coverage_step.dependOn(&coverage_self.step);
    const coverage_run = driver(b, "python3 tests/test_inputs_coverage.py", rss.script, "coverage");
    verification_registry.?.register("coverage", &coverage_run.step, &test_inputs.coverage, false, "fixture membership and negative path lookups outside source recipes require freshness");
    const manifest_self = driver(b, "python3 tests/input_manifest.py --self-test", rss.script, "manifest_self");
    manifest_self.addArgs(&.{ "python3", "tests/input_manifest.py", "--self-test" });
    coverage_step.dependOn(&manifest_self.step);
    coverage_run.addArgs(&.{ "python3", "tests/test_inputs_coverage.py" });
    coverage_step.dependOn(&coverage_run.step);
    test_step.dependOn(coverage_step);
    const verification_tests = b.step("test-verification-cache", "Verify action receipt admission and immutable input snapshots");
    for ([_][]const u8{ "scripts/verify_cache_test.py", "scripts/verification_snapshot_test.py", "scripts/verification_process_test.py", "scripts/verification_report_test.py", "scripts/verification_budgets_test.py", "scripts/build_slot_test.py", "scripts/verification_telemetry_test.py", "scripts/verification_producers_test.py", "scripts/verification_policy_test.py", "scripts/verification_profiles_test.py", "scripts/verification_qualification_test.py", "scripts/development_loop_workloads_test.py", "scripts/verification_native_telemetry_test.py", "scripts/verification_guest_telemetry_test.py", "scripts/verification_measurement_test.py", "scripts/verification_code_identity_test.py", "scripts/verification_environment_test.py" }, 0..) |script, member| {
        const verification_run = driver(b, b.fmt("python3 {s}", .{script}), rss.script, "verification_cache");
        const module = std.fs.path.stem(script);
        verification_run.addArgs(&.{ "python3", "scripts/verification_telemetry.py", "--action-id", "verification_cache", "--member", b.fmt("{d}", .{member}), "--output-directory-env", "SELKA_VERIFICATION_TELEMETRY_DIR", module });
        verification_tests.dependOn(&verification_run.step);
    }
    test_step.dependOn(verification_tests);
    const session_tests = driver(b, "python3 scripts/cache_session_test.py", rss.script, "verification_session");
    session_tests.addArgs(&.{ "python3", "scripts/cache_session_test.py" });
    verification_tests.dependOn(&session_tests.step);
    const fuzz_tests = b.step("test-fuzz-campaign", "Verify independent fuzz shards, retained corpus replay and qualified completion");
    for ([_][]const u8{
        "scripts/fuzz_campaign_store_test.py", "scripts/fuzz_campaign_test.py",
        "scripts/fuzz_coverage_test.py",       "tests/test_differential_corpus.py",
        "scripts/cache_retention_test.py",
    }) |script| {
        const fuzz_run = driver(b, b.fmt("python3 {s}", .{script}), rss.script, "fuzz_campaign");
        fuzz_run.addArgs(&.{ "python3", script });
        fuzz_tests.dependOn(&fuzz_run.step);
    }
    test_step.dependOn(fuzz_tests);
    const juice_cache_tests = b.step("test-juice-cache", "Verify qualified measurement reuse, evidence integrity and comparison-only decisions");
    for ([_][]const u8{ "scripts/juice_cache_test.py", "tests/test_juice_evidence.py", "scripts/juice_provider_test.py", "scripts/juice_worker_test.py" }) |script| {
        const cache_run = driver(b, b.fmt("python3 {s}", .{script}), rss.script, "juice_cache");
        cache_run.addArgs(&.{ "python3", script });
        juice_cache_tests.dependOn(&cache_run.step);
    }
    test_step.dependOn(juice_cache_tests);
    const doc_coverage = bounded(b.addRunArtifact(exe), rss.driver);
    doc_coverage.addArgs(&.{ "doc-coverage", "." });
    doc_coverage.setCwd(b.path("."));
    doc_coverage.has_side_effects = true;
    verification_registry.?.register("doc-coverage", &doc_coverage.step, &test_inputs.doc_coverage, true, "complete document and feature-contract scope");
    b.step("test-doc-coverage", "Require a documented example for every feature and standard export").dependOn(&doc_coverage.step);
    test_step.dependOn(&doc_coverage.step);
    const guest_step = b.step("test-guest", "Run the guest-behavior tests written in the language");
    const guest_tests = bounded(b.addRunArtifact(exe), rss.guest_suite);
    guest_tests.addArgs(&.{ "test", "tests/guest", "--cache-dir", ".mylang-cache/guest-tests" });
    guest_tests.setCwd(b.path("."));
    guest_tests.has_side_effects = true;
    verification_registry.?.register("guest", &guest_tests.step, &.{}, false, "guest Host and external-effect eligibility remains compiler-authoritative");
    guest_step.dependOn(&guest_tests.step);
    test_step.dependOn(&guest_tests.step);
    guardian.addAllChecks(b, guardian_exe, guest_step, .{});
    boundedChecks(guest_step);
    const lang_step = b.step("test-lang", "Run tests/lang, tests/value_semantics and tests/ported through mylang test, at optimized debug, unoptimized and release with the leak and fact checks");
    // The language-level guest tests run in default optimized debug, explicit
    // unoptimized mode, and release with its facts asserted
    // (`--verify-facts`) and the runtime's leak check on (`MYL_CORE_LEAKCHECK=1`:
    // a test that ends with blocks live fails). The retired runtime switches went
    // with their steps (S5-D4): `test-lang-gc` (`--gc-runtime --gc-stress`),
    // `test-value-semantics` and `test-legacy-sharing`. Value semantics is the
    // default, so `tests/value_semantics` runs here without its switch.
    const LangSuite = struct { dir: []const u8, cache: []const u8 };
    for ([_]LangSuite{
        .{ .dir = "tests/lang", .cache = ".mylang-cache/lang-tests" },
        .{ .dir = "tests/value_semantics", .cache = ".mylang-cache/value-semantics-tests" },
        // Tests ported from the retired back end's Zig tests (S5-D1); outside
        // tests/lang, whose files the S5 conformance sweep compares with the
        // frozen old-core references.
        .{ .dir = "tests/ported", .cache = ".mylang-cache/ported-tests" },
    }) |suite| {
        const debug = bounded(b.addRunArtifact(exe), rss.suite);
        debug.setName(b.fmt("mylang test {s}", .{suite.dir}));
        debug.addArgs(&.{ "test", suite.dir, "--cache-dir", suite.cache });
        debug.setCwd(b.path("."));
        debug.has_side_effects = true;
        verification_registry.?.register("language", &debug.step, &.{}, false, "guest Host and external-effect eligibility requires execution-time admission");
        lang_step.dependOn(&debug.step);
        test_step.dependOn(&debug.step);
        const unoptimized = bounded(b.addRunArtifact(exe), rss.suite);
        unoptimized.setName(b.fmt("mylang test {s} --unoptimized", .{suite.dir}));
        unoptimized.addArgs(&.{ "test", suite.dir, "--unoptimized", "--cache-dir", b.fmt("{s}-unoptimized", .{suite.cache}) });
        unoptimized.setCwd(b.path("."));
        unoptimized.has_side_effects = true;
        verification_registry.?.register("language", &unoptimized.step, &.{}, false, "guest Host and external-effect eligibility requires execution-time admission");
        lang_step.dependOn(&unoptimized.step);
        test_step.dependOn(&unoptimized.step);
        // The variable reaches the test children through `env`, since a Run step
        // may not carry an environment map of its own (`requireLiveEnvironment`).
        const release = bounded(b.addSystemCommand(&.{ "env", "MYL_CORE_LEAKCHECK=1" }), rss.suite);
        release.setName(b.fmt("mylang test {s} --release --verify-facts (leak check)", .{suite.dir}));
        release.addArtifactArg(exe);
        release.addArgs(&.{ "test", suite.dir, "--release", "--verify-facts", "--cache-dir", b.fmt("{s}-release", .{suite.cache}) });
        release.setCwd(b.path("."));
        release.has_side_effects = true;
        verification_registry.?.register("language", &release.step, &.{}, false, "guest Host and external-effect eligibility requires execution-time admission");
        lang_step.dependOn(&release.step);
        test_step.dependOn(&release.step);
    }
    guardian.addAllChecks(b, guardian_exe, lang_step, .{});
    boundedChecks(lang_step);
    // S5-C: the new core's own unit tests and end-to-end slice join the gate.
    test_step.dependOn(core_tests);
    const doctest_step = b.step("test-docs", "Execute every fenced documentation example");
    // The doctest fans its units out across a worker pool, so it is bounded like a suite.
    const doctest_run = driver(b, "mylang doctest .", rss.suite, "doctest");
    doctest_run.addArtifactArg(exe);
    doctest_run.addArgs(&.{ "doctest", "." });
    doctest_step.dependOn(&doctest_run.step);
    test_step.dependOn(&doctest_run.step);
    guardian.addAllChecks(b, guardian_exe, doctest_step, .{});
    boundedChecks(doctest_step);
    addParityBench(b);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("build_env.zig"), b.path("build_identity.zig"), b.path("build_test_inputs.zig"), b.path("build_verification.zig"), b.path("src"), b.path("tests"), b.path("test"), b.path("selfhost") }, .check = true });
    const fmt_step = b.step("fmt-check", "Check canonical Zig and live .my corpus formatting");
    fmt_step.dependOn(&fmt.step);
    verification_registry.?.register("zig-format", &fmt.step, &test_inputs.zig_format, true, "exact formatter and complete source-format scope");
    const my_fmt = driver(b, "check live .my corpus formatting", rss.script, "my_format");
    my_fmt.addArgs(&.{ "python3", "scripts/check_my_format.py", "--compiler" });
    my_fmt.addArtifactArg(exe);
    fmt_step.dependOn(&my_fmt.step);
    const fmt_tests = driver(b, "verify .my formatting gate", rss.script, "my_format_self");
    fmt_tests.addArgs(&.{ "python3", "tests/test_my_format.py", "--compiler" });
    fmt_tests.addArtifactArg(exe);
    fmt_step.dependOn(&fmt_tests.step);
    test_step.dependOn(&my_fmt.step);
    test_step.dependOn(&fmt_tests.step);
    const noalloc_step = b.step("test-noalloc-lint", "Lint every live allocation-contract source");
    const noalloc_lint = driver(b, "lint live noalloc contracts", rss.script, "noalloc_lint");
    noalloc_lint.addArgs(&.{ "python3", "scripts/check_noalloc.py", "--compiler" });
    noalloc_lint.addArtifactArg(exe);
    noalloc_step.dependOn(&noalloc_lint.step);
    test_step.dependOn(&noalloc_lint.step);
    const embedded_step = b.step("test-embedded-migration", "Verify embedded source extraction and guarded compiler-driven migration");
    const embedded_tests = driver(b, "verify embedded migration staging", rss.script, "embedded_migration");
    embedded_tests.addArgs(&.{ "python3", "tests/test_migrate_embedded.py" });
    embedded_step.dependOn(&embedded_tests.step);
    test_step.dependOn(&embedded_tests.step);
    const verification_preparation = verification.prepare(b, &.{
        .{ .label = "mylang", .binary = exe },
        .{ .label = "units", .binary = unit },
        .{ .label = "tooling-units", .binary = tooling_unit },
        .{ .label = "text-scalar-units", .binary = text_scalar_unit },
        .{ .label = "cli", .binary = integration },
        .{ .label = "core", .binary = verification_core_binary.? },
        .{ .label = "golden", .binary = golden_unit },
        .{ .label = "memory-budget", .binary = budget_unit },
        .{ .label = "component-support", .binary = component_support_tests },
        .{ .label = "component-builder", .binary = component_tool },
    }, .{ .step = install_components.?, .manifest = .{ .relative = .{ .base = .install_prefix, .sub_path = "libexec/mylang/components/test-index.json" } } }, &.{ &install_exe.step, &install_component_tool.step });
    requireLiveEnvironment(b);
    // These scripts use declared source fixtures and isolated stand-ins, and
    // never execute a prepared native compiler or test binary. Unknown/new
    // cohorts retain the complete artifact identity until explicitly reviewed.
    for ([_][]const u8{ "idioms_self", "friction", "affected", "coverage_self", "manifest_self", "verification_cache", "fuzz_campaign", "juice_cache", "juice_pure", "embedded_migration" }) |id| {
        verification_registry.?.artifactDependencies(id, &.{});
    }
    verification_registry.?.artifactDependencies("tooling_unit", &.{"tooling-units"});
    verification_registry.?.artifactDependencies("text_scalar_unit", &.{"text-scalar-units"});
    verification_registry.?.artifactDependencies("memory_budget", &.{ "memory-budget", "components" });
    verification_registry.?.artifactDependencies("component-support", &.{"component-support"});
    verification_registry.?.artifactDependencies("component_builder", &.{ "component-builder", "components" });
    verification_registry.?.artifactDependencies("component_native", &.{ "component-builder", "components" });
    verification.registerInfrastructure(&verification_registry.?, &.{ test_step, fmt_step });
    verification_registry.?.exportPlan(&.{ test_step, fmt_step }, verification_preparation);
}
