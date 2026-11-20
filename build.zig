const std = @import("std");
const builtin = @import("builtin");
const product = @import("src/product.zig");
/// The test runner every custom test root links: Guardian's runner, kept as two files of this repository
/// (`tools/test_runner/`) when Guardian was turned off (GH-2, 18 November 2026). It prints the selected-test
/// count and fails a run that selected none, runs one shard (`--test-shard=K/N`, `--test-shard-plan`) and
/// selects tests by name at run time (`--test-filter=`, `--test-list=`), so test binaries are
/// compiled whole and never with `.filters`.
fn testRunner(b: *std.Build) std.Build.Step.Compile.TestRunner {
    return .{ .path = b.path("tools/test_runner/test_runner.zig"), .mode = .server };
}
/// Keep source locations in assertion failures in every optimize mode (`-ferror-tracing`): without them a failing
/// `expect` reports only `TestUnexpectedResult`.
fn enableTestDiagnostics(module: *std.Build.Module) void {
    module.error_tracing = true;
}
/// Give `run` shard `index` of `count` of its root's named tests.
fn announceShard(run: *std.Build.Step.Run, index: usize, count: usize) void {
    run.addArg(run.step.owner.fmt("--test-shard={d}/{d}", .{ index, count }));
}
/// The repository files each cached test step reads while it runs.
const test_inputs = @import("build_test_inputs.zig");
const verification = @import("build_verification.zig");
var verification_registry: ?verification.Registry = null;
var verification_core_binary: ?*std.Build.Step.Compile = null;
/// The core shards `zig build test` runs: the cached copies unfiltered, `test-core` itself under a filter.
var core_gate_step: ?*std.Build.Step = null;
/// The ReleaseFast SHA-256 object (`src/fast_sha256.zig`), which every binary that compiles the
/// front end's component verification must link.
var optimized_digest_object: ?*std.Build.Step.Compile = null;
/// The `build-env` host tool (`build_env.zig`): it writes the environment
/// manifest every cached test verdict is keyed on and projects the environment
/// every command `withTools` wraps runs in, from one definition.
var build_env: ?*std.Build.Step.Compile = null;
/// Where the test roots find the compiler and their fixtures
/// (`src/core/test_paths.zig`, TEST-PATHS-1): imported as `core_test_options` by
/// the core root and as `test_paths` by the unit, CLI and golden roots.
var test_paths: ?*std.Build.Module = null;
/// The component builder the CLI root runs, named at run time through
/// `SELKA_TEST_COMPONENT_BUILDER`.
var component_builder_bin: ?std.Build.LazyPath = null;
/// One mebibyte, the unit the resident-memory ceilings below are written in.
const mib: u64 = 1 << 20;
/// Resident-memory ceilings declared on the steps this build runs. The build
/// runner uses these with `--maxrss` and fails a step whose measured peak
/// exceeds its declaration. The pinned runner's blocked-step accounting can
/// exceed the aggregate reservation; see docs/tooling/runtime-budgets.md.
/// Only Zig compilations and Zig test binaries report a peak back, so only
/// those can trip a ceiling; for
/// a driver process it is purely a concurrency budget, and it covers the
/// children one driver runs at once rather than the largest single process
/// `/usr/bin/time -v` sees. Observed figures are recorded beside each ceiling.
const rss = struct {
    /// Zig test binaries, which also spawn the compiler. Observed: the CLI root
    /// 31M. The unit root additionally builds and runs every guest program its
    /// suites execute; the whole root peaked near 2.2G while it still linked libc
    /// for the retired `invoke` tests.
    const suite: u64 = 2560 * mib;
    /// One unit shard's scheduling reservation. C0 C3 sample 1 observed a
    /// 169.6 MiB process-tree RSS sum at 2-second sampling intervals (2026-10-13);
    /// 2026-10-18 sampled a shard's tree four times a second at a peak of 59 MiB.
    /// Sampling misses short peaks and shared pages are counted once per process,
    /// so 384 MiB is a concurrency budget with room above the observations (it
    /// was 1 GiB, which let the coordinator's 8 GiB `--maxrss` run eight shards
    /// at a time). Retired backend measurements no longer justify the old 2.5 GiB.
    const shard_unit: u64 = 384 * mib;
    /// One shard of the CLI root, which builds far fewer guests. Observed on a
    /// clean cache: 103M-141M for the test process, up to 1.22G for a moment
    /// across its tree; the ceiling is a concurrency budget.
    const shard_cli: u64 = 768 * mib;
    /// One shard of the core root, a single lane of builds and `zig cc`. Observed
    /// 2026-10-18, all ten shards at once, four samples a second: peak process-tree
    /// RSS 274 to 361 MiB (shared pages counted per process). It was the 1 GiB
    /// `driver` reservation, which with the 8 GiB `--maxrss` ran at most eight at a time.
    const shard_core: u64 = 512 * mib;
    /// The one core shard that holds `frontend_test`'s out-of-memory check, which checks a 5 MiB source twice with the Debug
    /// compiler. The runner measured its peak at 1.02 GB (9 November 2026, three lanes' first complete gates failed with
    /// "memory usage peaked at 1.02GB, exceeding the declared upper bound of 0.54GB"; the process tree sampled at 1044 MiB).
    /// 1.5 GiB leaves half again over that peak; the other nine shards peak under 420 MiB and keep `shard_core`.
    const shard_core_memory_check: u64 = 1536 * mib;
    /// One shard of the golden corpus replay, which runs `selka run` on each case. Observed
    /// 2026-10-28 in four gate members at 62-63 MiB (the test binary's peak). The former 2.5 GiB
    /// suite ceiling held 10 GiB of the 8 GiB budget for the whole golden phase.
    const shard_golden: u64 = 512 * mib;
    /// One test-support object compiled with ReleaseFast (juice_bytes_hash, fast_blake3,
    /// core_number_text). Observed uncached peaks 112, 136 and 138 MiB (gate log of 2026-10-20).
    /// A cached object still needs its whole ceiling free before it can run, and the core test
    /// binary depends on all three, so the former 4.5 GiB ceiling held every core shard behind
    /// the unit shards.
    const object: u64 = 512 * mib;
    /// The directory run of `tests/guest`. Observed on a clean cache
    /// (2026-09-23): `tests/guest` 1.33G.
    const guest_suite: u64 = 1536 * mib;
    /// Drivers that run the compiler a few programs at a time. Observed on a
    /// clean cache: the idiom probes 0.69G, parser hints 0.47G.
    const driver: u64 = 1024 * mib;
    /// `selka doctest`, which fans its examples out to a worker pool. Observed 2026-10-28: a 925 MiB
    /// process-tree peak (lane N's peaks.jsonl, isolated caches) under the 1 GiB driver ceiling, which
    /// leaves no room for a busier pool. 1.5 GiB keeps about 66% headroom over that peak.
    const doctest: u64 = 1536 * mib;
    /// `tests/mode_differential.py`, which builds up to six generated programs at once, each in up to four modes at a
    /// time, and runs their binaries and test children. Observed 12 November 2026: a 963 MiB process-tree peak (sampled
    /// five times a second, the gate's 14 programs, cold runtime store), 1264 MiB for programs twice as long.
    const mode_differential: u64 = 2048 * mib;
    /// Drivers that compile and link many native programs at once: the parity
    /// benchmark. Observed (the retired boundary matrix): 1.29G-1.45G.
    const parity: u64 = 2048 * mib;
    /// Checks that run Python but no compiler: the
    /// self-tests, the friction harvest, the SPEC merge driver, the inner-loop
    /// checks. Observed: under 60M each. Declaring a driver's 1G for each of
    /// them only kept the build runner from starting test shards it had room for.
    const script: u64 = 256 * mib;
    /// `zig build release`: `cp` of about 400 MiB and `xz -T4 -6` (four 94 MiB encoders).
    const release_bundle: u64 = 1024 * mib;
    /// Zig compilations. Only these and the test binaries report a peak to the
    /// build runner, so only they can trip a ceiling; the margin over the debug
    /// peak leaves room for a ReleaseFast build of the same tree.
    /// Observed (debug): src/root_test.zig 335M, the selka executable 270M, the
    /// other test roots 166-232M, the small runner executables 42M.
    /// Observed (ReleaseFast, C3/C4 tree): a test-root compile peaked at 2.55G,
    /// so the old 2.15G bound blocked the documented gate; 3G keeps a bounded
    /// ceiling with headroom for the same tree.
    /// Observed (ReleaseFast `-Dcompiler-only`, 2026-09-24, after the incremental
    /// build frontend landed): the selka executable compile peaked at 3.26-3.32G,
    /// over the 3G bound, so the install graph failed after writing the binary.
    /// Observed again (ReleaseFast, 2026-09-24, with per-module tests): 4.26G.
    const compile: u64 = 4608 * mib;
    /// Debug core/unit test compiles peaked at 583 MiB in the retained batch-2
    /// edit gates. Two GiB leaves over three times that observation while
    /// avoiding a ReleaseFast-sized reservation for each cached compile check.
    /// Optimized builds retain the larger ceiling above.
    const compile_debug_test: u64 = 2048 * mib;
    /// The B2 ReleaseFast compiler peaked at 5,226,618,880 bytes (2026-09-30), and
    /// main at 37285fb97f at 5,906,018,304 bytes (2026-10-21), over the old 5.5 GiB.
    /// Reserve 6.5 GiB, retaining about 18% headroom over the newer peak.
    const compiler_fast: u64 = 6656 * mib;
    /// The ReleaseFast compile of the `selka` executable itself. It peaked at 8,315,748,352 bytes (7.74 GiB) on 8 November 2026
    /// (main 4890f0e1b with two small changes; Zig printed `memory usage peaked at 8.32GB ... exceeding the declared upper bound of
    /// 6.98GB` for the 6.5 GiB above). Reserve 9.25 GiB, about 19% over that peak. A `--maxrss` below it refuses the install
    /// (`zig build -Doptimize=ReleaseFast` takes the machine's memory when none is given); `compiler_fast` stays for the component
    /// tool's steps, which a debug gate under `--maxrss 8589934592` also runs.
    const compiler_release: u64 = 9472 * mib;
    /// `zig build run`, which executes whatever program the caller names.
    /// Matches the 4 GiB ceiling `selka run` gives a guest.
    const guest: u64 = 4096 * mib;
};
/// Ceiling for a Zig compilation of a test root or the compiler executable. A debug compile
/// keeps the debug ceiling (observed 169-740 MiB per uncached debug test-root compile on
/// 2026-10-28); optimized compilations retain the larger ceiling.
fn compileCeiling(optimize: std.builtin.OptimizeMode) u64 {
    return if (optimize == .debug) rss.compile_debug_test else rss.compile;
}
/// The pinned Zig a guest build drives (`zig cc`), and the install step every
/// bounded driver waits on, filled in once at the top of `build`. A driver
/// invokes an uninstalled compiler, so it names the toolchain through
/// `SELKA_ZIG`, which the compiler reads when `--zig` does not name one (it outranks the bundled Zig and `ZIG`).
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
/// `-Dtest-release=true`: run the release-mode halves too, the language suites' `--release` pass and every Zig test's
/// release build. Off by default: the gate tests debug builds only (the user's decision of 28 October 2026).
var test_release = false;
/// `-Dproofs=true`: run the four Lean proof actions (`ownership-proof`, `verify-ir-proof`, `arith-proof`, `cache-proof`), which
/// need the Lean build tool `lake`. Off by default: without it each of them prints that it was skipped (never that it passed)
/// and exits 0, and nothing looks for `lake`, so a checkout with only git and Zig runs `zig build test` (the owner's decision
/// GH-D10 of 19 November 2026). The maintainer's coordinator, `scripts/verify_cache.py`, always passes it.
var proofs = false;
/// The `test_release_options` module every test root imports: `enabled` is `test_release`.
var release_switch: ?*std.Build.Module = null;
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
    verification_registry.?.register("input-discovery", &run.step, &.{}, false, "validated preparation discovery v1");
    inline for (comptime std.meta.declarations(test_inputs)) |name| {
        run.addArgs(&.{ "--list", name });
        run.addArgs(&@field(test_inputs, name));
    }
}
/// The make-time environment manifest `addEnvironmentManifest` writes on every
/// build that runs a cached test step.
var environment_manifest: ?std.Build.LazyPath = null;
/// The tools the environment manifest identifies by content: this build's Zig,
/// and the shell, `env`, Python and git found on the live `PATH` at make time. With
/// `-Dproofs=true` also the Lean build tool of the proof actions (`SELKA_LAKE`, else
/// `$HOME/.elan/bin/lake`; recorded as absent when there is none, which those actions refuse):
/// without the flag no step looks for `lake`, so its presence keys nothing.
const manifest_tools = [_][]const u8{ "sh", "env", "python3", "git" };
/// Add the step that records the make-time environment a cached test verdict
/// depends on, once per build (ENV-PROJECTION-2). A step's own environment
/// cannot key its verdict: every Run step inherits `zig build`'s live
/// environment (see `withTools`), which the build runner leaves out of a step's
/// cache key. `build-env digest` writes the host-scope environment identity
/// instead: the keyed and host variables of `src/environment_identity.zon` and
/// the digests of the tools above, so a changed `SELKA_*`, locale or Python
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
    if (proofs) run.addArg("lake");
    verification_registry.?.register("environment-discovery", &run.step, &.{}, false, "validated preparation discovery v1");
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
    // The manifest includes the verified artifact digest and the build key.
    // Source inputs alone cannot see a changed native input or toolchain library.
    if (install_components) |components| {
        run.step.dependOn(components);
        run.addFileInput(.{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir ++ "/test-index.json" } });
        run.addFileInput(.{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir ++ "/cache-plan.json" } });
    }
    for (tool_inputs) |tool| if (tool) |path| run.addFileInput(path);
    if (list.len != 0) verification_registry.?.declared(&run.step, list);
}
/// Prefix a command so that it runs in `zig build`'s live environment plus the
/// native tools a guest build needs. `Step.Run.setEnvironmentVariable` would
/// instead copy the whole configure-time environment into the step, and a
/// cached configuration keeps that copy: after one `zig build` under another
/// `PATH`, `TMPDIR` or `SELKA_*`, every later build with the same `-D` options
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
/// manifest does not key. `env` then adds `SELKA_ZIG`, which depends only on
/// this build's configuration, and the variables `withVariable` and
/// `withTestPaths` give the command.
fn withTools(step: *std.Build.Step.Run) void {
    const b = step.step.owner;
    var prefix: std.ArrayList([]const u8) = .empty;
    prefix.appendSlice(b.allocator, &.{ "sh", "-c", tools_script, "with-tools" }) catch @panic("out of memory");
    prefix.append(b.allocator, b.fmt("SELKA_ZIG={s}", .{tool_zig})) catch @panic("out of memory");
    const arena = b.graph.arena;
    const args = arena.alloc(std.Build.Step.Run.Arg, prefix.items.len) catch @panic("out of memory");
    for (args, prefix.items) |*arg, word| arg.* = .{ .bytes = b.graph.dupeString(word) };
    step.argv.insertSlice(arena, 0, args) catch @panic("out of memory");
    // The tool travels as an argument, so its content is part of the step's key.
    insertFile(step, 4, "", build_env.?.getEmittedBin());
    step.argv.insert(arena, args.len + 1, .{ .decorated_directory = .{
        .prefix = "SELKA_COMPONENT_DIR=",
        .suffix = "",
        .make_absolute = true,
        .lazy_path = .{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir } },
    } }) catch @panic("out of memory");
}
/// Where `withVariable` and `withTestPaths` insert a variable: after
/// `sh -c SCRIPT with-tools BUILD-ENV SELKA_ZIG=PATH`, before the command itself.
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
/// Name the executables a Zig test root runs (TEST-PATHS-1): `selka` through
/// `SELKA_TEST_COMPILER` and, for the CLI root, the component builder through
/// `SELKA_TEST_COMPONENT_BUILDER`. The test binaries embed no path of this
/// tree; the step keys each executable by content, so a changed compiler still
/// re-runs a cached verdict without rebuilding the test binary. The command
/// runs in the build root, where the roots' relative fixture paths resolve.
fn withTestPaths(step: *std.Build.Step.Run, component_builder: bool) void {
    const b = step.step.owner;
    step.setCwd(b.path("."));
    insertFile(step, variable_index, "SELKA_TEST_COMPILER=", tool_inputs[0].?);
    if (component_builder) {
        insertFile(step, variable_index, "SELKA_TEST_COMPONENT_BUILDER=", component_builder_bin.?);
    }
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
    \\ZIG_LOCAL_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/selka-zig-local.XXXXXX") || exit 2
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
/// bounded, and checked for exit status 0. The pinned build runner prints a
/// `failed command:` block for any step that writes to standard error, green or
/// not, so `scripts/quiet-driver.sh` captures the driver's output and re-emits it
/// only when the driver fails. `name` labels the step in the build summary,
/// where every such step would otherwise read `run sh`.
fn driver(b: *std.Build, name: []const u8, bytes: u64, list: []const u8) *std.Build.Step.Run {
    const run = bounded(b.addSystemCommand(&.{ "sh", "scripts/quiet-driver.sh" }), bytes);
    run.addFileInput(b.path("scripts/quiet-driver.sh"));
    run.setName(name);
    run.setCwd(b.path("."));
    run.expectExitCode(0);
    cached(run, list);
    return run;
}
/// Declare a step's resident-memory ceiling, give it the toolchain a guest build
/// needs (harmless on steps that build no guest), and prepare the components.
fn bounded(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    step.step.max_rss = bytes;
    withTools(step);
    if (install_components) |components| step.step.dependOn(components);
    return step;
}
/// What a proof action is without `-Dproofs=true` (GH-D10): a step that prints one line saying `name` was skipped and why,
/// on standard output (the pinned build runner reports a step that writes to standard error as a failed command), exits 0,
/// starts no driver and looks for no `lake`. The build summary still calls such a step a success (a Run step has no
/// skipped state), so the printed line is the report. Callers still register it under the action's id, so the inventory
/// lists the same actions; the coordinator passes the flag and refuses an inventory exported without it, so no receipt
/// records a skipped proof as a pass.
fn proofSkipped(b: *std.Build, name: []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{ "echo", b.fmt("{s}: SKIPPED, not run: the Lean proofs run only with -Dproofs=true (they need lake)", .{name}) });
    run.setName(b.fmt("{s} (skipped: -Dproofs=true runs it)", .{name}));
    run.has_side_effects = true;
    run.step.max_rss = rss.script;
    return run;
}
/// A focused test step: bound it and name the toolchain, without the install
/// graph. The test binary names the compiler it runs through a build option, so
/// a focused test waits only on that compile, never on the install.
fn focused(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    if (install_components) |components| step.step.dependOn(components);
    step.step.max_rss = bytes;
    withTools(step);
    // A test command must execute and report its selection; otherwise a warm
    // cache reuses the previous verdict and hides the selected-test count.
    step.has_side_effects = true;
    return step;
}
/// Forward filters to the runner, which selects by name at run time and fails a filter that names nothing.
fn forwardFilters(b: *std.Build, step: *std.Build.Step.Run, filters: []const []const u8) void {
    for (filters) |filter| step.addArg(b.fmt("--test-filter={s}", .{filter}));
}
/// The shard-plan file a sharded root's runs read, or null for the runner's modulo split.
fn shardPlanOption(b: *std.Build, name: []const u8, count: usize, default_count: usize, default_path: []const u8) ?[]const u8 {
    const path = b.option([]const u8, name, "Test runner shard-plan JSON; defaults to median weights at the default count") orelse {
        return if (count == default_count) default_path else null;
    };
    if (path.len == 0) {
        std.debug.print("error: -D{s}= requires a non-empty file path\n", .{name});
        std.process.exit(2);
    }
    return path;
}
/// File arguments bind plan bytes in Zig's run key; the coordinator separately
/// watches the same logical path before preparation and through publication.
fn forwardShardPlan(b: *std.Build, run: *std.Build.Step.Run, plan: ?[]const u8) void {
    if (plan) |path| {
        run.addArg("--test-shard-plan");
        run.addFileArg(if (std.fs.path.isAbsolute(path)) b.graph.cwdRelativePath(path) else b.path(path));
    }
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
    plan: ?[]const u8 = null,
    /// Whether the root runs the component builder (`withTestPaths`).
    component_builder: bool = false,
};
/// A gate root consumes one admitted CPU lane, including its guest compiler.
/// Focused whole-root unit/CLI commands keep their bounded batch parallelism.
fn boundNativeRoot(run: *std.Build.Step.Run) void {
    withVariable(run, "SELKA_UNIT_JOBS=1");
    withVariable(run, "SELKA_JOBS=1");
}
/// The index of the core shard (of the default ten) that `tests/shard-plans/core.json` gives `frontend_test`'s out-of-memory check, the
/// one test that needs `rss.shard_core_memory_check`; `scripts/verification_shard_plan_test.py` fails when a rebuilt plan moves it.
const core_memory_check_shard: usize = 0;
/// Historical median intervals choose modulo-shard registration order only.
/// Pinned Maker shuffles dependency traversal: launch order is not guaranteed.
/// Unknown shard counts retain natural order, preserving every shard identity.
fn shardRegistrationOrder(root: []const u8, count: usize) []const usize {
    if (std.mem.eql(u8, root, "cli") and count == 6) return &.{ 0, 3, 5, 2, 1, 4 };
    if (std.mem.eql(u8, root, "core") and count == 8) return &.{ 2, 3, 6, 5, 1, 7, 4, 0 };
    if (std.mem.eql(u8, root, "core") and count == 10) return &.{ 9, 2, 6, 7, 3, 8, 4, 5, 1, 0 };
    if (std.mem.eql(u8, root, "unit") and count == 12) return &.{ 11, 5, 1, 3, 0, 2, 6, 10, 7, 8, 4, 9 };
    return &.{};
}
/// The runs that cover one test root: `count` shards of the same test binary,
/// each executing the slice of the root's named tests that `--test-shard=`
/// assigns it, or the caller's single whole-root run when `count` is 1. The
/// shards partition the root — the test runner gives the unnamed `test { }`
/// blocks to shard 0 alone — so together they run every test exactly once, and
/// the build runner schedules them concurrently against its `--maxrss` budget.
/// A shard's verdict is cached on the test binary, the tools and the declared
/// inputs, so an unchanged rerun of the gate does not execute it again; the
/// whole-root run stays uncached because `test-units`/`test-cli` report its
/// selected count every time.
fn shardRuns(b: *std.Build, compile: *std.Build.Step.Compile, shards: Shards) []const *std.Build.Step {
    if (shards.count <= 1) return b.allocator.dupe(*std.Build.Step, &.{&shards.whole.step}) catch @panic("out of memory");
    const steps = b.allocator.alloc(*std.Build.Step, shards.count) catch @panic("out of memory");
    const order = shardRegistrationOrder(shards.inputs, shards.count);
    for (steps, 0..) |*step, position| {
        const index = if (order.len == shards.count) order[position] else position;
        const run = focused(b.addRunArtifact(compile), shards.bytes);
        boundNativeRoot(run);
        withTestPaths(run, shards.component_builder);
        announceShard(run, index, shards.count);
        forwardShardPlan(b, run, shards.plan);
        // The shards run at once, so each runs a test's batch of guest programs on
        // its share of the CPUs (`src/wiring/core_runner.zig`).
        withVariable(run, b.fmt("SELKA_UNIT_SHARDS={d}", .{shards.count}));
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

/// Give `module` the user guides `selka docs` prints: one anonymous import per
/// topic in `src/user_docs.zig`, named as `src/docs_command.zig` embeds it, so
/// the guides ship inside the compiler and an edited page rebuilds it.
fn addUserDocs(b: *std.Build, module: *std.Build.Module) void {
    const user_docs = @import("src/user_docs.zig");
    for (user_docs.topics) |topic| {
        module.addAnonymousImport(b.fmt("{s}{s}", .{ user_docs.import_prefix, topic.name }), .{ .root_source_file = b.path(topic.path) });
    }
}

/// `zig build bench-parity`: the standing selka/Zig/Rust parity benchmark under
/// `bench/parity`. It builds every arm with the compiler this build installs (or
/// `-Dbench-selka=PATH`), requires byte-identical output, times pinned
/// interleaved rounds and checks each program's ratio to Zig ReleaseFast against
/// `bench/parity/thresholds.json`. Opt-in: nothing else depends on it, so
/// `zig build test` never builds or times it. Arguments after `--` reach the
/// harness (`--json PATH`, `--arms ...`, `--write-thresholds`).
fn addParityBench(b: *std.Build) void {
    const cpu = b.option(u32, "bench-cpu", "bench-parity: the one CPU every timed process is pinned to (default: first of SELKA_TIMING_CPUS, else 2)");
    const rounds = b.option(u32, "bench-rounds", "bench-parity: timed rounds per program (default 7)") orelse 7;
    const filter = b.option([]const u8, "bench-filter", "bench-parity: comma-separated substrings of GROUP/NAME, e.g. sieve or micro/");
    const compiler = b.option([]const u8, "bench-selka", "bench-parity: time this compiler instead of the one this build installs");
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
        bench.addArgs(&.{ "--selka", path });
    } else {
        bench.addArg("--selka");
        bench.addFileArg(.{ .relative = .{ .base = .install_bin, .sub_path = product.command } });
        bench.step.dependOn(b.getInstallStep());
    }
    bench.addPassthruArgs();
    bench.has_side_effects = true;
    bench.step.max_rss = rss.parity;
    b.step("bench-parity", "Time selka against Zig and Rust on the parity suite and check ratio thresholds (opt-in)").dependOn(&bench.step);
}

/// The name the compiler code imports the number-text object by (`src/core/number_runtime.zig`), and the key of its
/// bytes in `build_identity_rules.named_files`.
const number_text_import = "core_number_text_object";

/// The Zig number-text runtime (`src/core/runtime/core_number_text.zig`) compiled once, for x86_64-linux-gnu.2.31 and the
/// skylake CPU model (`-mcpu skylake`: the AVX2 floor of the one supported target, scheduled like the machines it runs
/// on, which also gives the BLAKE3 digest of `bytes.blake3()` eight lanes; the generic `baseline` is four lanes and
/// `x86_64_v3` is eight lanes with a slower single-chunk path), so that it is embedded rather than built by
/// `zig build-obj` on a guest machine's first build that prints a number (NEW-CORE-S3-NUMBER-1). It is embedded as
/// bytes, so its debug information would carry this tree's path into the compiler, the core test binary and every guest
/// program that links it (TEST-PATHS-1); the object is built without it.
///
/// Every setting here shapes bytes that reach guest programs, and the compiler identity digests those bytes
/// (`build_identity.module`), so editing a setting moves the identity exactly when it changes the object.
var watch_links: ?bool = null;
/// Whether a watch build installs links (`-Dwatch-links`, default true); false copies as an ordinary build does.
fn watchLinks(b: *std.Build) bool {
    if (watch_links == null) watch_links = b.option(bool, "watch-links", "Under -Dwatch-identity, install the compiler and test binaries as links to the incremental artifacts (default true)") orelse true;
    return watch_links.?;
}
/// Install a large binary (the compiler or a test binary): a copy, except under the admitted incremental watch
/// (`-Dwatch-identity=true`), where a relative symbolic link to the artifact the incremental linker updates in place
/// installs nothing heavy (copying about 460 MB was 4.5 s of a 5 s watch rebuild, DL-3 part 2), always under the
/// default prefix `zig-out`. A later ordinary build's install replaces the link with a file, so a gate or the edit
/// check never runs through one.
fn installBinary(b: *std.Build, source: std.Build.LazyPath, dir: std.Build.InstallDir, name: []const u8) *std.Build.Step {
    if (!@import("build_identity.zig").watchMode(b) or !watchLinks(b)) return &b.addInstallFileWithDir(source, dir, name).step;
    const link = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && ln -sfnr \"$1\" \"$2\"", "install-link" });
    link.addFileArg(source);
    // The configure phase cannot name the install prefix; `scripts/dev_loop.py` builds with the default one, which the
    // step (run from the build root) names relative to it.
    const sub_dir = switch (dir) {
        .bin => "bin",
        .custom => |custom| custom,
        else => @panic("installBinary links only into bin or a custom directory"),
    };
    link.addArg(b.fmt("zig-out/{s}/{s}", .{ sub_dir, name }));
    link.has_side_effects = true;
    return &link.step;
}
fn numberTextObject(b: *std.Build) *std.Build.Step.Compile {
    return b.addObject(.{ .name = "core_number_text", .max_rss = rss.object, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/runtime/core_number_text.zig"),
        .target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux-gnu.2.31", .cpu_features = "skylake" }) catch @panic("number-text target")),
        .optimize = .ReleaseFast,
        .strip = true,
        .pic = true,
        .stack_check = false,
        .stack_protector = false,
        .link_libc = true,
    }) });
}

/// What the new core's steps build on: the shared front end module and the
/// `selka` executable whose commands the core provides.
const CoreInputs = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    front_end: *std.Build.Module,
    compiler: *std.Build.Step.Compile,
    filters: []const []const u8,
    /// The repository's test runner (`testRunner`), which can run one shard of the root (`--test-shard`).
    test_runner: std.Build.Step.Compile.TestRunner,
    /// Generated identity over every production compiler and runtime source and the bytes of `number_text`.
    identity: *std.Build.Module,
    /// The Zig number-text runtime object (`numberTextObject`), embedded in the compiler and every guest program that links it.
    number_text: *std.Build.Step.Compile,
    /// Link libc into the core test root (`-Dtest-libc=true`): the libc thread path, where a thread
    /// stack smaller than the binary's static thread-local block is refused (see `tool_identity.zig`).
    link_libc: bool = false,
};

/// Run native component tools in the live projected environment without a shell.
fn projectComponents(run: *std.Build.Step.Run) void {
    run.argv.insertSlice(run.step.owner.graph.arena, 0, &.{ .{ .bytes = "project" }, .{ .bytes = "--" } }) catch @panic("out of memory");
    insertFile(run, 0, "", build_env.?.getEmittedBin());
}

/// Common native component discovery/build inputs: the tree, the toolchain and the compiler that compiles the components
/// (the `selka` this build has just built; GH-D5).
fn componentArguments(b: *std.Build, run: *std.Build.Step.Run, compiler: std.Build.LazyPath) void {
    run.addArg("--root");
    run.addDirectoryArg2(b.path("."), .{ .make_absolute = true });
    run.addArgs(&.{ "--zig", b.graph.zig_exe, "--compiler" });
    run.addFileArg(compiler);
    run.setCwd(b.path("."));
}

/// The release bundle's assembly (`zig build release`), run from the repository with the install prefix, the release folder,
/// the bundle's name and the unpacked Zig distribution as its four arguments. POSIX `sh`, `cp`, `tar`, `xz` and `sha256sum`,
/// no Python. The last check runs the bundle's own compiler with no Zig on its `PATH`: it must find the bundled one and
/// accept it (`reuse: on`, which `tool_identity.zig` gives only the official distribution, `lib/` whole), so a release made
/// from another Zig does not get as far as a tarball.
const release_script =
    \\set -eu
    \\prefix=$1; release=$2; name=$3; zig_dir=$4
    \\out=$release/$name
    \\fail() { echo "release: $*" >&2; exit 1; }
    \\[ -x "$zig_dir/zig" ] && [ -f "$zig_dir/lib/std/std.zig" ] && [ -f "$zig_dir/LICENSE" ] || fail "$zig_dir is not an unpacked Zig distribution (it holds zig, lib/std/std.zig and LICENSE)"
    \\[ -f "$prefix/bin/selka" ] && [ -d "$prefix/libexec/selka/components" ] || fail "no installed compiler with its components under $prefix"
    \\rm -rf "$out" "$out.tar.xz" "$out.tar.xz.sha256"
    \\mkdir -p "$out/bin" "$out/libexec/selka" "$out/lib/selka/zig"
    \\cp -a "$prefix/bin/selka" "$out/bin/selka"
    \\if [ -f "$prefix/bin/selka.commit" ]; then cp -a "$prefix/bin/selka.commit" "$out/bin/selka.commit"; fi
    \\cp -a "$prefix/libexec/selka/components" "$out/libexec/selka/components"
    \\cp -a "$zig_dir/zig" "$out/lib/selka/zig/zig"
    \\cp -a "$zig_dir/lib" "$out/lib/selka/zig/lib"
    \\cp -a "$zig_dir/LICENSE" "$out/lib/selka/zig/LICENSE"
    \\cp LICENSE THIRD-PARTY-NOTICES.md install.sh "$out/"
    \\chmod 755 "$out/install.sh"
    \\printf '%s\n' \
    \\  "Selka: a language that checks who owns each value, and the compiler for it, with the Zig it drives inside (Linux x86-64)." \
    \\  "Install it with ./install.sh (into \$HOME/.local, or PREFIX=DIR ./install.sh), then try: selka run hello.selka" \
    \\  "Source, documentation and issues: https://github.com/eugenepentland/selka" > "$out/README"
    \\scratch=$release/.check-$$
    \\trap 'rm -rf "$scratch"' EXIT
    \\mkdir -p "$scratch/home"
    \\shown=$(cd "$scratch" && env -i HOME="$scratch/home" PATH=/usr/bin:/bin XDG_CACHE_HOME="$scratch/home/cache" "$out/bin/selka" native show) || { rm -rf "$out"; fail "the bundled compiler's native show failed: $shown"; }
    \\if ! printf '%s\n' "$shown" | grep -qx 'reuse: on'; then
    \\  rm -rf "$out"
    \\  fail "the bundled compiler does not accept the bundled Zig (is $zig_dir the official distribution?): $(printf '%s\n' "$shown" | grep '^reuse:')"
    \\fi
    \\XZ_OPT='-T4 -6' tar --sort=name --owner=0 --group=0 --numeric-owner -C "$release" -cJf "$out.tar.xz" "$name"
    \\(cd "$release" && sha256sum "$name.tar.xz" > "$name.tar.xz.sha256")
    \\echo "release: $out.tar.xz ($(du -h "$out.tar.xz" | cut -f1), folder $(du -sh "$out" | cut -f1))"
;

/// `zig build release -Doptimize=ReleaseFast -Dbundle-zig=DIR`: the release bundle `selka-VERSION-x86_64-linux/` and its
/// `.tar.xz` and `.sha256` under `zig-out/release`, VERSION from `build.zig.zon`. DIR is an unpacked official Zig
/// distribution; it goes under `lib/selka/zig` whole, because the toolchain identity reviews `lib/` as a tree and turns
/// cache reuse off for a trimmed one. The step is opt-in: without it a plain `zig build` needs no Zig distribution, and a
/// request that cannot make a bundle fails with the reason before anything is built.
fn addRelease(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, components: ComponentsChoice) void {
    const step = b.step("release", "Assemble zig-out/release/selka-VERSION-x86_64-linux and its .tar.xz (needs -Doptimize=ReleaseFast and -Dbundle-zig=DIR, an unpacked official Zig distribution)");
    const bundle_zig = b.option([]const u8, "bundle-zig", "release: the unpacked official Zig distribution (a folder holding zig, lib and LICENSE) to put under lib/selka/zig");
    const refusal: ?[]const u8 = if (target.result.os.tag != .linux or target.result.cpu.arch != .x86_64)
        "zig build release makes the Linux x86-64 bundle only"
    else if (optimize != .fast)
        "zig build release needs -Doptimize=ReleaseFast: a bundle of another build is several times larger"
    else if (components != .built)
        "zig build release needs the components built (leave -Dcomponents out): the bundle's compiler has to find them"
    else if (bundle_zig == null)
        "zig build release needs -Dbundle-zig=DIR: DIR is an unpacked official Zig 0.17.1 distribution (ziglang.org/download)"
    else
        null;
    if (refusal) |message| {
        step.dependOn(&b.addFail(message).step);
        return;
    }
    const assemble = b.addSystemCommand(&.{ "sh", "-c", release_script, "release" });
    assemble.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = "" } }, .{ .make_absolute = true });
    assemble.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = "release" } }, .{ .make_absolute = true });
    assemble.addArg(b.fmt("selka-{s}-x86_64-linux", .{@import("build.zig.zon").version}));
    // A relative DIR is relative to the repository; the script runs from there.
    const zig_dir: std.Build.LazyPath = if (std.fs.path.isAbsolute(bundle_zig.?)) .{ .cwd_relative = bundle_zig.? } else b.path(bundle_zig.?);
    assemble.addDirectoryArg2(zig_dir, .{ .make_absolute = true });
    assemble.setCwd(b.path("."));
    assemble.has_side_effects = true;
    assemble.step.max_rss = rss.release_bundle;
    assemble.step.dependOn(b.getInstallStep());
    step.dependOn(&assemble.step);
}

/// What `zig build` installs in `libexec/selka/components` (`-Dcomponents`).
const ComponentsChoice = enum {
    /// The components, compiled from `selfhost/components/` by the compiler this build has just built.
    built,
    /// No component: the installed compiler uses its built-in test index and cache plan, with one line of notice.
    reference,
};

/// The new compiler core (docs/design/new-core-ir.md), which `selka` runs for
/// every command that builds, runs or tests code (S5-D8: one binary):
/// - `src/core/cli.zig` becomes the `selka_core` module of the `selka`
///   executable;
/// - `zig build test-core` runs the core's unit tests and its end-to-end slice,
///   which drive that `selka`, split into `-Dcore-shards=N` concurrent shards of
///   one test binary (default 8; a `-Dtest-filter` run is one process); it returns
///   that step, which `zig build test` depends on.
fn addCore(b: *std.Build, inputs: CoreInputs) *std.Build.Step {
    const reviewed_platform = b.createModule(.{ .root_source_file = b.path("src/config_core_tool_platform.zig") });
    // A compiler that reads the system closure below DIR instead of `/` (GH-3b), to show that a machine whose libraries
    // differ gets keys of its own without touching the system. Test-only: an ordinary build never sets it.
    const system_root = b.option([]const u8, "test-system-root", "Build a compiler that reads the system libraries' closure below this directory (tests only)");
    const platform = if (system_root) |root| rooted: {
        const rooted_options = b.addOptions();
        rooted_options.addOption([]const u8, "system_root", root);
        break :rooted b.createModule(.{
            .root_source_file = b.path("test/fixtures/native-closure/rooted_platform.zig"),
            .imports = &.{ .{ .name = "reviewed_platform", .module = reviewed_platform }, .{ .name = "rooted_options", .module = rooted_options.createModule() } },
        });
    } else reviewed_platform;
    // A separate object also optimizes the standard-library SHA rounds, which
    // otherwise inherit the root's Debug mode even through an optimized module.
    const juice_bytes_hash = b.addObject(.{ .name = "juice_bytes_hash", .max_rss = rss.object, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/juice/bytes_hash_impl.zig"),
        .target = inputs.target,
        .optimize = .ReleaseFast,
        .pic = true,
    }) });
    // BLAKE3 over objects, programs and stage packs, optimized for the same reason
    // (`src/core/fast_blake3_impl.zig`): the Debug compiler's own rounds are 30 MB/s.
    const fast_blake3_object = b.addObject(.{ .name = "fast_blake3", .max_rss = rss.object, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/fast_blake3_impl.zig"),
        .target = inputs.target,
        .optimize = .ReleaseFast,
        .pic = true,
    }) });
    // The test runner's frame and byte ceilings share the run budget rules.
    const budget = b.modules.get("memory_budget") orelse @panic("memory_budget module");
    const unit = b.addTest(.{ .max_rss = if (inputs.optimize == .debug) rss.compile_debug_test else rss.compile, .test_runner = inputs.test_runner, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root_test.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{.{ .name = "selka", .module = inputs.front_end }},
        .link_libc = inputs.link_libc,
    }) });
    verification_core_binary = unit;
    optimized_digest_object = juice_bytes_hash;
    unit.root_module.addImport("core_tool_platform", platform);
    unit.root_module.addImport("build_identity", inputs.identity);
    unit.root_module.addImport("memory_budget", budget);
    unit.root_module.addImport("test_release_options", release_switch.?);
    // The compiler and fixture paths arrive at run time (TEST-PATHS-1).
    unit.root_module.addImport("core_test_options", test_paths.?);
    // `selka` runs the new core for every command that builds, runs or tests
    // code. Its commands live in `src/core/cli.zig`, a module of its own; the core
    // reaches the front end only as `selka`.
    const cli = b.createModule(.{
        .root_source_file = b.path("src/core/cli.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{ .{ .name = "selka", .module = inputs.front_end }, .{ .name = "core_tool_platform", .module = platform }, .{ .name = "build_identity", .module = inputs.identity }, .{ .name = "memory_budget", .module = budget } },
    });
    inputs.compiler.root_module.addImport("selka_core", cli);
    for ([_]*std.Build.Module{ unit.root_module, cli }) |module| {
        module.addObject(juice_bytes_hash);
        module.addObject(fast_blake3_object);
        module.addAnonymousImport(number_text_import, .{ .root_source_file = inputs.number_text.getEmittedBin() });
    }
    const step = b.step("test-core", "Run the new core's unit tests and its end-to-end slice");
    const test_binary = installBinary(b, unit.getEmittedBin(), .{ .custom = "focus" }, "core-tests");
    b.step("core-test-binary", "Compile the registered Core tests without provisioning components").dependOn(test_binary);
    // Most of the root's time is end-to-end builds of guest programs, so shards
    // of the one binary run concurrently; each test uses its own temporary tree.
    const requested = b.option(usize, "core-shards", "test-core: concurrent shards of the core test root (default 10)") orelse 10;
    const plan = shardPlanOption(b, "core-shard-plan", requested, 10, "tests/shard-plans/core.json");
    const suite_cache = b.option([]const u8, "core-test-cache", "test-core: content-addressed suite build cache (outputs and cache assertions stay private)") orelse product.work_dir ++ "/core-tests";
    const shards = if (inputs.filters.len == 0) @max(1, requested) else 1;
    const order = shardRegistrationOrder("core", shards);
    // `test-core` always runs, so it reports what it selected. The shards `zig build test`
    // and `test-core-gate` run are the same processes with their verdicts cached on the test
    // binary, the compiler, the environment and the declared inputs, like the other roots' shards.
    const gate = b.step("test-core-gate", "Run the core shards the gate runs, reusing the verdict of an unchanged shard");
    core_gate_step = if (inputs.filters.len == 0) gate else step;
    for (0..shards) |position| {
        const index = if (order.len == shards) order[position] else position;
        const reserved = if (shards > 1) (if (shards == 10 and index == core_memory_check_shard) rss.shard_core_memory_check else rss.shard_core) else rss.driver;
        const run = focused(b.addRunArtifact(unit), reserved);
        if (inputs.filters.len == 0) boundNativeRoot(run);
        withTestPaths(run, false);
        withVariable(run, b.fmt("SELKA_CORE_TEST_CACHE={s}", .{suite_cache}));
        // A filtered run is the only one the gate sees of these; an unfiltered one is covered below.
        if (inputs.filters.len != 0) verification_registry.?.declared(&run.step, "core");
        forwardFilters(b, run, inputs.filters);
        if (shards > 1) {
            announceShard(run, index, shards);
            forwardShardPlan(b, run, plan);
        }
        step.dependOn(&run.step);
        if (inputs.filters.len != 0) continue;
        const kept = focused(b.addRunArtifact(unit), reserved);
        boundNativeRoot(kept);
        withTestPaths(kept, false);
        withVariable(kept, b.fmt("SELKA_CORE_TEST_CACHE={s}", .{suite_cache}));
        cached(kept, "core");
        if (shards > 1) {
            announceShard(kept, index, shards);
            forwardShardPlan(b, kept, plan);
        }
        gate.dependOn(&kept.step);
    }
    return step;
}

pub fn build(b: *std.Build) void {
    // Building the compiler takes any 0.17 release from 0.17.1 on and no development snapshot. `.zigversion` names the
    // release the gate, CI and the published builds use (`scripts/verification_native_telemetry.py` holds the gate to it).
    const zig = builtin.zig_version;
    if (zig.major != 0 or zig.minor != 17 or zig.patch < 1 or zig.pre != null)
        @panic("selka requires Zig 0.17.1 or a later 0.17 release (see .zigversion)");
    // `-Dcpu=MODEL` (`x86_64_v3`) builds the compiler for that CPU model instead of this machine's, for a binary that other
    // machines run; the release workflow passes it. Without it the compiler is built for the machine it is built on.
    const cpu_model = b.option([]const u8, "cpu", "Build the compiler for this CPU model (for example x86_64_v3) instead of the machine's own");
    const target = b.resolveTargetQuery(if (cpu_model) |model|
        std.Target.Query.parse(.{ .arch_os_abi = "native", .cpu_features = model }) catch @panic("-Dcpu: not a CPU model Zig knows (see `zig targets`)")
    else
        .{});
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
    // root, which is what the gate did before sharding existed. Filters use
    // single whole-root runs: the test runner selects names at run time from the
    // complete binary.
    // Explicit sharded focus steps below retain their requested partition.
    const requested_shards = b.option(
        usize,
        "test-shards",
        "Split the unit and CLI test roots across this many parallel processes (default 12; 1 disables sharding)",
    ) orelse 12;
    const unit_plan = shardPlanOption(b, "unit-shard-plan", requested_shards, 12, "tests/shard-plans/unit.json");
    const cli_plan = shardPlanOption(b, "cli-shard-plan", @max(1, requested_shards / 2), 6, "tests/shard-plans/cli.json");
    if (requested_shards == 0) {
        std.debug.print("error: -Dtest-shards= needs a positive count; -Dtest-shards=1 runs each root in one process\n", .{});
        std.process.exit(2);
    }
    test_rerun = b.option(bool, "test-rerun", "Run every cached test step even when none of its declared inputs changed") orelse false;
    test_release = b.option(bool, "test-release", "Run the release-mode halves of the tests too: the language suites' --release pass and each Zig test's release build (default false: the gate tests debug builds only)") orelse false;
    proofs = b.option(bool, "proofs", "Run the four Lean proof actions too (ownership-proof, verify-ir-proof, arith-proof, cache-proof; they need the Lean build tool lake: SELKA_LAKE, else $HOME/.elan/bin/lake) (default false: each prints that it was skipped, never that it passed, and exits 0)") orelse false;
    const release_switch_options = b.addOptions();
    release_switch_options.addOption(bool, "enabled", test_release);
    release_switch = release_switch_options.createModule();
    build_env = @import("build_env.zig").tool(b, rss.compile);
    test_paths = b.createModule(.{ .root_source_file = b.path("src/core/test_paths.zig"), .target = target, .optimize = optimize });
    verification_registry = .{ .build = b, .controls = .{ .filtered = test_filters.len != 0, .rerun = test_rerun, .optimize = @tagName(optimize), .proofs = proofs } };
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
    const core = b.addModule("selka", .{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addImport("memory_budget", budget);
    const exe = b.addExecutable(.{
        .max_rss = if (optimize == .fast) rss.compiler_release else compileCeiling(optimize),
        .name = product.command,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "selka", .module = core }, .{ .name = "memory_budget", .module = budget } },
        }),
    });
    // A command file that the unit root also compiles reaches the front end
    // through its root's `compiler_language`, never by a second module path.
    exe.root_module.addImport("compiler_root", exe.root_module);
    addUserDocs(b, exe.root_module);
    const number_text = numberTextObject(b);
    const identity = @import("build_identity.zig").module(b, target, optimize, .{ .compile = rss.compile, .run = rss.driver }, &.{.{ .name = number_text_import, .file = number_text.getEmittedBin() }});
    exe.root_module.addImport("build_identity", identity);
    const install_exe = if (@import("build_identity.zig").watchMode(b)) installBinary(b, exe.getEmittedBin(), .bin, product.command) else &b.addInstallArtifact(exe, .{}).step;
    b.getInstallStep().dependOn(install_exe);
    // The pin's LLVM ReleaseSafe code avoids accelerated SHA-256's AVX/SSE
    // transition regression. Require LLVM: native-backend ReleaseSafe still
    // reproduces it. The components' own build settings are independent of it.
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
    b.step("component-builder", "Build the native component coordinator without building the components").dependOn(&install_component_tool.step);
    // `selka --version` names the commit the install ran at from a file beside the executable, which is deliberately not
    // part of the compiler: the identity digests the sources and embedded products, and a hash among them would move it at
    // every commit and empty every cache (D-FR22-4). It always runs and rewrites the file only when its text changes.
    const commit_file = b.addSystemCommand(&.{ "sh", "scripts/write-commit-file.sh" });
    commit_file.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = "bin" } }, .{ .make_absolute = true });
    // The script's private copy of the repository's index belongs to the build, so it lives in this tree's cache, not in the
    // installation (FR25); a fresh cache makes it again.
    commit_file.addDirectoryArg2(.{ .relative = .{ .base = .local_cache, .sub_path = "commit-file" } }, .{ .make_absolute = true });
    commit_file.setCwd(b.path("."));
    commit_file.has_side_effects = true;
    commit_file.step.max_rss = rss.script;
    b.getInstallStep().dependOn(&commit_file.step);
    const components_choice = b.option(ComponentsChoice, "components", "built (default): compile and install the Selka components with the compiler just built; reference: install none (the compiler uses its built-in implementations)") orelse .built;
    // Discovery is native so the ordinary installation remains Python-free.
    const component_discovery = b.addRunArtifact(component_tool);
    componentArguments(b, component_discovery, exe.getEmittedBin());
    component_discovery.addArg("--inputs-stamp");
    const component_stamp = component_discovery.addOutputFileArg("component-inputs.json");
    component_discovery.has_side_effects = true;
    // Discovery may build the native-input probe.
    component_discovery.step.max_rss = rss.compiler_fast;
    const component_build = b.addRunArtifact(component_tool);
    componentArguments(b, component_build, exe.getEmittedBin());
    component_build.addArg("--install-dir");
    const component_outputs = component_build.addOutputDirectoryArg("components");
    component_build.addArg("--output-stamp");
    const component_completion = component_build.addOutputFileArg("component-outputs.json");
    component_build.addArg("--verify-inputs-stamp");
    component_build.addFileArg(component_stamp);
    // The build is keyed by Zig's own cache on what it reads (the discovery stamp, the tool, the compiler, the environment
    // manifest); a `src/` edit changes the compiler, so the components are compiled again. `-Dtest-rerun` repeats the cached test steps
    // to rule out a stale verdict; this is no test step, and it re-ran in every gate for 4 to 5 s on the startup path that every
    // step waits behind. The install step below still runs on every build and checks the outputs' bytes, so a corrupt cached
    // output fails there.
    component_build.has_side_effects = false;
    component_build.step.max_rss = rss.compiler_fast;
    // Validate generated manifests and binary bytes on every installation. Missing
    // or corrupt cache outputs fail; missing/corrupt installed copies are repaired.
    const component_install = b.addRunArtifact(component_tool);
    component_install.addArgs(&.{ "--zig", b.graph.zig_exe, "--install-from" });
    component_install.addDirectoryArg(component_outputs);
    component_install.addArg("--install-stamp");
    component_install.addFileArg(component_completion);
    component_install.addArg("--install-dir");
    component_install.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir } }, .{ .make_absolute = true });
    component_install.setCwd(b.path("."));
    component_install.has_side_effects = true;
    component_install.step.max_rss = rss.script;
    verification_registry.?.register("component-preparation", &component_discovery.step, &test_inputs.component_inputs, false, "validated preparation discovery v1");
    verification_registry.?.register("component-preparation", &component_build.step, &test_inputs.component_inputs, false, "validated preparation discovery v1");
    verification_registry.?.register("component-preparation", &component_install.step, &test_inputs.component_inputs, false, "validated preparation discovery v1");
    const components_step = b.step("components", "Build and install the Selka components with the compiler this build builds");
    if (components_choice == .built) {
        install_components = &component_install.step;
        b.getInstallStep().dependOn(&component_install.step);
        components_step.dependOn(&component_install.step);
    }
    components_step.dependOn(&install_component_tool.step);
    tool_inputs = .{exe.getEmittedBin()};
    component_builder_bin = component_tool.getEmittedBin();
    addInputManifests(b);
    addEnvironmentManifest(b);
    // Guest-running drivers invoke an uninstalled compiler with no toolchain
    // beside it; name this build's Zig for them through the environment.
    tool_zig = b.graph.zig_exe;
    // These native commands use the live projected environment and the cached
    // build binds its content identity without a configure-time environment map.
    projectComponents(component_discovery);
    projectComponents(component_build);
    projectComponents(component_install);
    component_build.addFileInput(environment_manifest.?);
    // The compiler `scripts/affected_tests.py` runs guest tests and doctests with:
    // an unattached copy, so the inner loop never waits on the install. It is a file
    // copy, not a second artifact install: a run step names an artifact by the
    // path its install left, so two installs of one artifact would make that
    // path (and every cache key holding it) depend on which install ran last.
    const focus_exe_step = b.addInstallFileWithDir(exe.getEmittedBin(), .{ .custom = "focus" }, product.command);
    const affected_compiler = b.step("affected-compiler", "Install only selka to zig-out/focus, for scripts/affected_tests.py");
    affected_compiler.dependOn(&focus_exe_step.step);
    affected_compiler.dependOn(&component_install.step);
    install_all = b.getInstallStep();
    addRelease(b, target, optimize, components_choice);
    const run = bounded(b.addRunArtifact(exe), rss.guest);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const tooling_unit = b.addTest(.{
        .name = "tooling-unit-tests",
        .max_rss = compileCeiling(optimize),
        .test_runner = testRunner(b),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tooling_root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tooling_unit.root_module.addImport("compiler_root", tooling_unit.root_module);
    enableTestDiagnostics(tooling_unit.root_module);
    const text_scalar_unit = b.addTest(.{
        .name = "text-scalar-unit-tests",
        .max_rss = compileCeiling(optimize),
        .test_runner = testRunner(b),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/text_scalar_root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    enableTestDiagnostics(text_scalar_unit.root_module);
    const unit = b.addTest(.{
        .max_rss = if (optimize == .debug) rss.compile_debug_test else rss.compile,
        .test_runner = testRunner(b),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit.root_module.addImport("build_identity", identity);
    unit.root_module.addImport("memory_budget", budget);
    unit.root_module.addImport("test_release_options", release_switch.?);
    unit.root_module.addImport("compiler_root", unit.root_module);
    addUserDocs(b, unit.root_module);
    // The environment identity golden fixture (ENV-IDENTITY-2) is embedded, so it
    // is a compile input of the unit binary rather than a path read at run time.
    for ([_][]const u8{ "environment", "classification", "tools", "digest-guest", "digest-host" }) |name| {
        unit.root_module.addAnonymousImport(b.fmt("environment-identity/{s}.txt", .{name}), .{ .root_source_file = b.path(b.fmt("test/fixtures/environment-identity/{s}.txt", .{name})) });
    }
    // Unit tests build and run guest programs with `selka`, which the root cannot
    // import (NEW-CORE-S5-UNITS-1), through one shared cache.
    const native_test_options = b.addOptions();
    native_test_options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    native_test_options.addOption([]const u8, "cache_directory", product.work_dir ++ "/unit-tests");
    unit.root_module.addOptions("native_test_options", native_test_options);
    unit.root_module.addImport("test_paths", test_paths.?);
    const test_libc = b.option(bool, "test-libc", "Link libc into the new core's test root (the libc thread path; see tool_identity.zig)") orelse false;
    _ = addCore(b, .{ .target = target, .optimize = optimize, .front_end = core, .compiler = exe, .filters = test_filters, .test_runner = testRunner(b), .identity = identity, .number_text = number_text, .link_libc = test_libc });
    unit.root_module.addObject(optimized_digest_object.?);
    _ = b.option(bool, "compiler-only", "Accepted for older scripts: install selka and its required components");
    _ = b.option(bool, "gate-install", "Accepted for older scripts: Guardian, which it ran before the install, is off since GH-2");
    // The compiler and the component builder arrive at run time (`withTestPaths`).
    const options = b.addOptions();
    options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    options.addOption([]const u8, "semantic_cache_version", @import("src/semantic_cache_format.zig").version);
    const integration = b.addTest(.{ .max_rss = compileCeiling(optimize), .test_runner = testRunner(b), .root_module = b.createModule(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    integration.root_module.addOptions("test_options", options);
    integration.root_module.addImport("test_paths", test_paths.?);
    integration.root_module.addImport("test_release_options", release_switch.?);
    enableTestDiagnostics(unit.root_module);
    enableTestDiagnostics(integration.root_module);
    const compile_tests = b.step("test-compile", "Compile every Zig test without running the suite");
    compile_tests.dependOn(&unit.step);
    compile_tests.dependOn(&integration.step);
    const unit_binary = installBinary(b, unit.getEmittedBin(), .{ .custom = "focus" }, "unit-tests");
    b.step("unit-test-binary", "Compile compiler units without provisioning components").dependOn(unit_binary);
    const cli_binary = installBinary(b, integration.getEmittedBin(), .{ .custom = "focus" }, "cli-tests");
    b.step("cli-test-binary", "Compile CLI tests without provisioning components").dependOn(cli_binary);
    const run_integration = focused(b.addRunArtifact(integration), rss.suite);
    withTestPaths(run_integration, true);
    if (test_filters.len == 0 and cli_shards == 1) boundNativeRoot(run_integration);
    forwardFilters(b, run_integration, test_filters);
    const test_step = b.step("test", "Run the compiler, new-core, CLI, guest-language and tooling regression tests");
    b.step("test-interpreter", "Alias of test, kept for older scripts").dependOn(test_step);
    // Named modules' inline tests are excluded from importing roots by Zig.
    // Give the byte ceilings their own runner so MEMORY-CEILING-* is gated.
    const budget_unit = b.addTest(.{
        .max_rss = compileCeiling(optimize),
        .test_runner = testRunner(b),
        .root_module = budget,
    });
    enableTestDiagnostics(budget_unit.root_module);
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
    // The test runner's own tests (`tools/test_runner/`), on Zig's default runner: a custom runner is a root's
    // `main`, so its `test` blocks run only when it is compiled as an ordinary test root (they import test_timing.zig's).
    const runner_unit = b.addTest(.{
        .name = "test-runner-tests",
        .max_rss = compileCeiling(optimize),
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/test_runner/test_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_runner_unit = b.addRunArtifact(runner_unit);
    run_runner_unit.step.max_rss = rss.script;
    verification_registry.?.register("test-runner", &run_runner_unit.step, &.{"tools/test_runner/"}, false, "a small native root without a prepared artifact identity runs every time");
    b.step("test-test-runner", "Run the test runner's own tests (tools/test_runner/)").dependOn(&run_runner_unit.step);
    test_step.dependOn(&run_runner_unit.step);
    compile_tests.dependOn(&runner_unit.step);
    const run_unit = focused(b.addRunArtifact(unit), rss.suite);
    withTestPaths(run_unit, false);
    if (test_filters.len == 0 and unit_shards == 1) boundNativeRoot(run_unit);
    forwardFilters(b, run_unit, test_filters);
    verification_registry.?.declared(&run_unit.step, "unit");
    verification_registry.?.declared(&run_integration.step, "cli");
    // The gate runs each slow root as several concurrent shards; `test-units`
    // and `test-cli` keep the single whole-root run, so `-Dtest-filter` behaves
    // exactly as documented and its selected-test count means what it says.
    const unit_runs = shardRuns(b, unit, .{ .count = unit_shards, .bytes = rss.shard_unit, .inputs = "unit", .whole = run_unit, .plan = unit_plan });
    const cli_runs = shardRuns(b, integration, .{ .count = cli_shards, .bytes = rss.shard_cli, .inputs = "cli", .whole = run_integration, .plan = cli_plan, .component_builder = true });
    dependOnAll(test_step, unit_runs);
    // The fast inner loops: no Python drivers and no full install graph,
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
    dependOnAll(units_sharded, shardRuns(b, unit, .{ .count = requested_shards, .bytes = rss.shard_unit, .inputs = "", .whole = run_unit, .plan = unit_plan, .filters = test_filters, .cache = false }));
    dependOnAll(cli_sharded, shardRuns(b, integration, .{ .count = @max(1, requested_shards / 2), .bytes = rss.shard_cli, .inputs = "", .whole = run_integration, .plan = cli_plan, .filters = test_filters, .cache = false, .component_builder = true }));
    dependOnAll(test_step, cli_runs);
    // What `zig build test` runs of the compiler's own suites, without the rest of the gate: the
    // sharded roots whose shard verdicts are cached, so an unchanged shard is not run again.
    const units_gate = b.step("test-units-gate", "Run the unit shards the gate runs, reusing the verdict of an unchanged shard");
    dependOnAll(units_gate, unit_runs);
    units_gate.dependOn(&run_tooling_unit.step);
    units_gate.dependOn(&run_text_scalar_unit.step);
    dependOnAll(b.step("test-cli-gate", "Run the CLI shards the gate runs, reusing the verdict of an unchanged shard"), cli_runs);
    const audit_runtime = b.step("test-runtime-audit", "Run every Zig test root for isolated runtime probes");
    audit_runtime.dependOn(&focused_tooling.step);
    audit_runtime.dependOn(&focused_text_scalar.step);
    dependOnAll(audit_runtime, unit_runs);
    dependOnAll(audit_runtime, cli_runs);
    // The checked-in golden corpora `tests/goldens/qbe_*.json` hold the old core's
    // answers (expected stdout, exit status and trap per case), frozen when the old
    // back end was retired; the replay runs each case through this `selka run`.
    const golden_step = b.step("test-golden", "Replay the checked-in golden corpora through selka run with no Python oracle");
    const golden_unit = b.addTest(.{ .max_rss = compileCeiling(optimize), .test_runner = testRunner(b), .root_module = b.createModule(.{
        .root_source_file = b.path("test/golden_parity.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    golden_unit.root_module.addOptions("test_options", options);
    golden_unit.root_module.addImport("test_paths", test_paths.?);
    enableTestDiagnostics(golden_unit.root_module);
    compile_tests.dependOn(&golden_unit.step);
    const run_golden = bounded(b.addRunArtifact(golden_unit), rss.suite);
    withTestPaths(run_golden, false);
    boundNativeRoot(run_golden);
    cached(run_golden, "golden");
    forwardFilters(b, run_golden, test_filters);
    run_golden.setCwd(b.path("."));
    const golden_shards = b.option(usize, "golden-shards", "Concurrent golden case groups (default 4)") orelse 4;
    if (golden_shards < 1 or golden_shards > 4) @panic("golden-shards must be in 1..4");
    const golden_runs = shardRuns(b, golden_unit, .{
        .count = if (test_filters.len == 0) golden_shards else 1,
        .bytes = rss.shard_golden,
        .inputs = "golden",
        .whole = run_golden,
        .filters = test_filters,
    });
    dependOnAll(golden_step, golden_runs);
    test_step.dependOn(golden_step);
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
    // `selka.json`.
    const incremental_projects = driver(b, "python3 tests/incremental_diff.py --project tests/fixtures/module_projects", rss.driver, "incremental");
    incremental_projects.addArgs(&.{ "python3", "tests/incremental_diff.py", "--steps", "60", "--project", "tests/fixtures/module_projects" });
    incremental_projects.addArtifactArg(exe);
    incremental_step.dependOn(&incremental_projects.step);
    test_step.dependOn(incremental_step);
    // MODULE-INTERFACE-2/3: a seeded mutation walk asserts which edits keep a
    // module's interface hash and which change it, and every module of
    // `tests/lang` and the interface fixtures, checked against its imports'
    // interfaces alone, must equal the whole-program check, Core's ownership
    // and allocation-contract refusals included (W9, goal G7;
    // `tests/fixtures/interfaces_ownership` holds refused callers).
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
    oracle_run.addArgs(&.{ "tests/lang", "tests/fixtures/interfaces/main.selka", "tests/fixtures/interfaces_generic/main.selka", "tests/fixtures/incremental/main.selka", "tests/fixtures/interfaces_ownership" });
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
    const ownership_command_step = b.step("test-ownership-commands", "Verify default ownership and allocation contracts at public commands");
    const ownership_commands = driver(b, "checked ownership public commands", rss.driver, "ownership_commands");
    ownership_commands.addArgs(&.{ "python3", "scripts/test_ownership_default_cli.py", "--compiler" });
    ownership_commands.addArtifactArg(exe);
    ownership_commands.addArgs(&.{ "--stage", "retirement" });
    ownership_command_step.dependOn(&ownership_commands.step);
    test_step.dependOn(&ownership_commands.step);
    const component_tests = driver(b, "python3 selfhost/test_components.py", rss.script, "component_builder");
    component_tests.addArgs(&.{ "python3", "selfhost/test_components.py", "--zig", b.graph.zig_exe, "--builder" });
    component_tests.addArtifactArg(component_tool);
    const native_component_tests = driver(b, "pure Selka and native component qualification", rss.driver, "component_native");
    native_component_tests.addArgs(&.{ "python3", "selfhost/test_component_native.py", "--compiler" });
    native_component_tests.addArtifactArg(exe);
    native_component_tests.addArgs(&.{ "--zig", b.graph.zig_exe, "--component-dir" });
    native_component_tests.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir } }, .{ .make_absolute = true });
    const component_test_step = b.step("test-components", "Test pure Selka, native protocol, cache and failure boundaries");
    const component_support_tests = b.addTest(.{
        .max_rss = compileCeiling(optimize),
        .test_runner = testRunner(b),
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
    b.step("test-component-support", "Test native streaming hashes, canonical identity and the builder's environment").dependOn(&run_component_support.step);
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
    const selfhost_syntax_step = b.step("test-selfhost-syntax", "Check the syntax parity harness, and the Zig front end against itself over the in-tree corpus");
    const selfhost_syntax_run = driver(b, "python3 selfhost/tests/test_syntax_parity.py --compiler", rss.driver, "selfhost_syntax");
    selfhost_syntax_run.addArgs(&.{ "python3", "selfhost/tests/test_syntax_parity.py", "--compiler" });
    selfhost_syntax_run.addArtifactArg(exe);
    selfhost_syntax_step.dependOn(&selfhost_syntax_run.step);
    test_step.dependOn(selfhost_syntax_step);
    // The throughput harness builds a Zig twin and a release Selka program, so its smoke test stays out of the gate: it
    // is neither a dependency of `test` nor a verification action. Run it with `zig build test-selfhost-bench`.
    const selfhost_bench_run = bounded(b.addSystemCommand(&.{ "python3", "selfhost/tests/test_lexer_bench.py", "--compiler" }), rss.driver);
    selfhost_bench_run.addArtifactArg(exe);
    selfhost_bench_run.setCwd(b.path("."));
    selfhost_bench_run.has_side_effects = true;
    b.step("test-selfhost-bench", "Smoke-test the lexer throughput harness (builds the Zig twin and the release Selka benchmark; not part of the gate)").dependOn(&selfhost_bench_run.step);
    // The SPEC.md merge driver (`scripts/merge_spec.py`): synthetic three-way
    // cases, a throwaway repository end to end, and a replay of real merges.
    const spec_merge_step = b.step("test-spec-merge", "Verify the SPEC.md merge driver, including replayed history");
    const spec_merge_run = bounded(b.addSystemCommand(&.{ "python3", "tests/test_spec_merge.py" }), rss.script);
    spec_merge_run.setCwd(b.path("."));
    verification_registry.?.register("spec-history", &spec_merge_run.step, &.{ "tests/test_spec_merge.py", "scripts/merge_spec.py", "scripts/setup-git.sh", ".gitattributes" }, false, "replays repository history; its reuse borrowed Guardian's Git authority, gone since GH-2");
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
    identity_run.addFileInput(b.path("test/fixtures/build-identity/expected.json"));
    // The driver also checks the real `src` (facts against bytes) and names every source it read here, so an edit under
    // `src` reruns it.
    _ = identity_run.addPrefixedDepFileOutputArg("--depfile=", "identity-qualification.d");
    identity_run.addFileInput(environment_manifest.?);
    identity_run.expectExitCode(0);
    verification_registry.?.register("identity-qualification", &identity_run.step, &.{ "tests/compiler_identity_cache.py", "build_identity.zig", "src/build_identity_rules.zig", "test/fixtures/build-identity/expected.json", "src/" }, true, "identity probe implementation and exact toolchain");
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
    const edit_check_tests = driver(b, "python3 tests/test_edit_check.py", rss.script, "affected");
    edit_check_tests.addArgs(&.{ "python3", "tests/test_edit_check.py" });
    affected_step.dependOn(&edit_check_tests.step);
    test_step.dependOn(affected_step);
    // The Selka tools beside the Python scripts they port: both run on the same inputs and must print the same bytes
    // (T3 of docs/audits/real-work-shadow-plan-2026-10-30.md). Not a dependency of `test`: the tools are built by main's
    // compiler and stay out of the gate until a new stage-0 pin (decision U2).
    const selka_step = b.step("test-selka-tools", "Run each Selka tool and its Python original on the same inputs");
    const selka_run = driver(b, "python3 tests/test_selka_tools.py", rss.driver, "selka_tools");
    selka_run.addArgs(&.{ "python3", "tests/test_selka_tools.py", "--compiler" });
    selka_run.addArtifactArg(exe);
    selka_step.dependOn(&selka_run.step);
    const coverage_step = b.step("test-inputs-coverage", "Require every repository file a cached test names to be a declared input");
    const coverage_self = driver(b, "python3 tests/test_inputs_coverage.py --self-test", rss.script, "coverage_self");
    coverage_self.addArgs(&.{ "python3", "tests/test_inputs_coverage.py", "--self-test" });
    coverage_step.dependOn(&coverage_self.step);
    const coverage_run = driver(b, "python3 tests/test_inputs_coverage.py", rss.script, "coverage");
    verification_registry.?.register("coverage", &coverage_run.step, &test_inputs.coverage, true, "declared sources and guarded named-path existence");
    const manifest_self = driver(b, "python3 tests/input_manifest.py --self-test", rss.script, "manifest_self");
    manifest_self.addArgs(&.{ "python3", "tests/input_manifest.py", "--self-test" });
    coverage_step.dependOn(&manifest_self.step);
    coverage_run.addArgs(&.{ "python3", "tests/test_inputs_coverage.py" });
    coverage_step.dependOn(&coverage_run.step);
    test_step.dependOn(coverage_step);
    const verification_tests = b.step("test-verification-cache", "Verify action receipt admission and immutable input snapshots");
    const verification_test_scripts = [_][]const u8{ "scripts/verification_watch_pool_test.py", "scripts/watch_pool_review_test.py", "scripts/object_diagnostics_review_test.py", "scripts/verify_cache_test.py", "scripts/verification_snapshot_test.py", "scripts/verification_process_test.py", "scripts/verification_ownership_watch_test.py", "scripts/verification_report_test.py", "scripts/verification_budgets_test.py", "scripts/build_slot_test.py", "scripts/build_slot_watch_test.py", "scripts/dev_loop_test.py", "scripts/verification_telemetry_test.py", "scripts/verification_producers_test.py", "scripts/verification_policy_test.py", "scripts/verification_profiles_test.py", "scripts/verification_qualification_test.py", "scripts/development_loop_workloads_test.py", "scripts/verification_native_telemetry_test.py", "scripts/gate_summary_test.py", "scripts/application_cache_patience_test.py", "scripts/edit_check_test.py", "scripts/build_env_death_test.py", "scripts/verification_guest_telemetry_test.py", "scripts/verification_measurement_test.py", "scripts/verification_code_identity_test.py", "scripts/verification_environment_test.py", "scripts/verification_shard_plan_test.py", "scripts/verification_warm_test.py", "scripts/verification_git_tree_test.py", "scripts/verification_publication_test.py", "scripts/verification_digest_request_test.py", "scripts/ownership_proof_test.py", "scripts/fact_proof_test.py", "scripts/arith_proof_test.py", "scripts/cache_proof_test.py", "scripts/ownership_corpus_test.py", "scripts/ownership_verdict_store_test.py", "scripts/reuse_review_test.py", "scripts/corpus_exact_test.py", "tests/goals_register_test.py", "tests/compiler_map_test.py" };
    for (verification_test_scripts, 0..) |script, member| {
        const verification_run = driver(b, b.fmt("python3 {s}", .{script}), rss.script, "verification_cache");
        const module = std.fs.path.stem(script);
        const module_directory = std.fs.path.dirname(script) orelse ".";
        const telemetry_launcher = b.fmt("import sys; sys.path[:0] = ['scripts', '{s}']; import verification_telemetry; raise SystemExit(verification_telemetry.main())", .{module_directory});
        verification_run.addArgs(&.{ "python3", "-c", telemetry_launcher, "--action-id", "verification_cache", "--member", b.fmt("{d}", .{member}), "--output-directory-env", "SELKA_VERIFICATION_TELEMETRY_DIR", module });
        verification_tests.dependOn(&verification_run.step);
    }
    const scheduler_tests = driver(b, "python3 tests/verification/test_scheduler.py", rss.script, "verification_cache");
    scheduler_tests.addArgs(&.{ "python3", "-c", "import sys; sys.path[:0] = ['scripts', 'tests/verification']; import verification_telemetry; raise SystemExit(verification_telemetry.main())", "--action-id", "verification_cache", "--member", b.fmt("{d}", .{verification_test_scripts.len}), "--output-directory-env", "SELKA_VERIFICATION_TELEMETRY_DIR", "test_scheduler" });
    verification_tests.dependOn(&scheduler_tests.step);
    test_step.dependOn(verification_tests);
    const session_tests = driver(b, "python3 scripts/cache_session_test.py", rss.script, "verification_session");
    session_tests.addArgs(&.{ "python3", "scripts/cache_session_test.py" });
    verification_tests.dependOn(&session_tests.step);
    const fuzz_tests = b.step("test-fuzz-campaign", "Verify independent fuzz shards, retained corpus replay and qualified completion");
    for ([_][]const u8{
        "scripts/fuzz_campaign_store_test.py", "scripts/fuzz_campaign_test.py",
        "scripts/fuzz_coverage_test.py",       "tests/test_differential_corpus.py",
        "scripts/cache_retention_test.py",     "scripts/core_store_gc_test.py",
        "scripts/audit_cache_reads_test.py",   "scripts/service_worktree_test.py",
        "scripts/maintenance_review_test.py",
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
    // E1c: the task-group and parallel.map drivers under ThreadSanitizer at 8 threads, and their output at 1, 2 and 8 threads
    // (tests/test_concurrency.py). Its own step, outside `zig build test`: whether the complete gate runs it is the coordinator's call.
    const concurrency_step = b.step("test-concurrency", "Run the task-group and parallel.map drivers under ThreadSanitizer at 8 threads, and check their output across thread counts");
    const concurrency_run = bounded(b.addSystemCommand(&.{ "python3", "-I", "tests/test_concurrency.py" }), rss.script);
    concurrency_run.setCwd(b.path("."));
    concurrency_run.addArtifactArg(exe);
    concurrency_run.expectExitCode(0);
    concurrency_run.has_side_effects = true;
    concurrency_step.dependOn(&concurrency_run.step);
    const guest_step = b.step("test-guest", "Run the guest-behavior tests written in the language");
    const guest_tests = bounded(b.addRunArtifact(exe), rss.guest_suite);
    guest_tests.addArgs(&.{ "test", "tests/guest", "--cache-dir", product.work_dir ++ "/guest-tests" });
    guest_tests.setCwd(b.path("."));
    guest_tests.has_side_effects = true;
    verification_registry.?.register("guest", &guest_tests.step, &.{ "tests/", "test/", "examples/", "src/", "selfhost/" }, true, "compiler, source closure and projected environment");
    guest_step.dependOn(&guest_tests.step);
    test_step.dependOn(&guest_tests.step);
    const lang_step = b.step("test-lang", "Run tests/lang, tests/value_semantics and tests/ported through selka test, at optimized debug with the leak and fact checks (-Dtest-release=true adds the release pass)");
    const lang_guard = driver(b, "python3 tests/test_test_lang.py", rss.script, "language_guard");
    lang_guard.addArgs(&.{ "python3", "tests/test_test_lang.py" });
    b.step("test-lang-guard", "Verify the language gate's unsupported-verdict policy").dependOn(&lang_guard.step);
    lang_step.dependOn(&lang_guard.step);
    test_step.dependOn(&lang_guard.step);
    // The language-level guest tests run in default optimized debug, with the runtime's leak check on
    // (`SELKA_CORE_LEAKCHECK=1`: a test that ends with blocks still live fails) and the optimizer's facts verified at run
    // time (`--verify-facts`: the facts are checked on the inputs a test runs, and the ownership and fact certificates are
    // validated). The retired runtime switches went with their steps (S5-D4): `test-lang-gc` (`--gc-runtime --gc-stress`),
    // `test-value-semantics` and `test-legacy-sharing`. Value semantics is the default, so `tests/value_semantics` runs
    // here without its switch.
    // Release builds are not part of the gate (the user's decision of 28 October 2026). `-Dtest-release=true` adds each
    // suite's release pass: `--release --verify-facts` under `SELKA_CORE_LEAKCHECK=1`, in its own cache directory. The variable
    // reaches the test children through `env`, since a Run step may not carry an environment map of its own
    // (`requireLiveEnvironment`).
    const LangSuite = struct { dir: []const u8, cache: []const u8 };
    var lang_runs: std.ArrayList(*std.Build.Step) = .empty;
    for ([_]LangSuite{
        .{ .dir = "tests/lang", .cache = product.work_dir ++ "/lang-tests" },
        .{ .dir = "tests/value_semantics", .cache = product.work_dir ++ "/value-semantics-tests" },
        // Tests ported from the retired back end's Zig tests (S5-D1); outside
        // tests/lang, whose files the S5 conformance sweep compares with the
        // frozen old-core references.
        .{ .dir = "tests/ported", .cache = product.work_dir ++ "/ported-tests" },
    }) |suite| {
        const debug = bounded(b.addSystemCommand(&.{ "env", "SELKA_CORE_LEAKCHECK=1", "SELKA_ENGINE_VERIFY=16", "SELKA_ENGINE_SHADOW_LOG=@user", "python3", "scripts/test_lang.py", "--compiler" }), rss.driver);
        debug.addArtifactArg(exe);
        debug.setName(b.fmt("selka test {s} --verify-facts (leak check)", .{suite.dir}));
        debug.addArgs(&.{ "--allowlist", "tests/unsupported.json", suite.dir, "--verify-facts", "--cache-dir", suite.cache });
        // C4: the build the tests run writes the ownership certificates of each program it builds, for `ownership-proof`.
        debug.addArgs(&.{ "--emit-certificates", b.fmt(product.work_dir ++ "/ownership-certificates/{s}/debug", .{suite.dir}) });
        debug.setCwd(b.path("."));
        debug.has_side_effects = true;
        verification_registry.?.register("language", &debug.step, &test_inputs.language, true, "compiler, source closure, unsupported policy and projected environment");
        lang_step.dependOn(&debug.step);
        test_step.dependOn(&debug.step);
        lang_runs.append(b.allocator, &debug.step) catch @panic("out of memory");
        if (test_release) {
            const release = bounded(b.addSystemCommand(&.{ "env", "SELKA_CORE_LEAKCHECK=1", "SELKA_ENGINE_VERIFY=16", "SELKA_ENGINE_SHADOW_LOG=@user", "python3", "scripts/test_lang.py", "--compiler" }), rss.driver);
            release.addArtifactArg(exe);
            release.setName(b.fmt("selka test {s} --release --verify-facts (leak check)", .{suite.dir}));
            release.addArgs(&.{ "--allowlist", "tests/unsupported.json", suite.dir, "--release", "--verify-facts", "--cache-dir", b.fmt("{s}-release", .{suite.cache}) });
            release.addArgs(&.{ "--emit-certificates", b.fmt(product.work_dir ++ "/ownership-certificates/{s}/release", .{suite.dir}) });
            release.setCwd(b.path("."));
            release.has_side_effects = true;
            verification_registry.?.register("language", &release.step, &test_inputs.language, true, "compiler, source closure, unsupported policy and projected environment");
            lang_step.dependOn(&release.step);
            test_step.dependOn(&release.step);
            lang_runs.append(b.allocator, &release.step) catch @panic("out of memory");
        }
    }
    // FX10: the language suites twice in one fresh work directory, the second run forced, failing on a test whose verdict
    // differs or that is unsupported. A stored record served to a program it does not fit shows only on such a second run;
    // the complete gate does not run this step (about 93 s for tests/lang on 14 November), the user decides whether it joins.
    const rerun_step = b.step("test-lang-rerun", "Run each language suite twice in one fresh work directory (the second with --force) and fail on a changed or unsupported verdict");
    const rerun = bounded(b.addSystemCommand(&.{ "python3", "scripts/test_lang_rerun.py", "--compiler" }), rss.driver);
    rerun.addArtifactArg(exe);
    rerun.setName("selka test (each language suite twice, the second forced)");
    rerun.setCwd(b.path("."));
    rerun.has_side_effects = true;
    rerun_step.dependOn(&rerun.step);
    // C4: the gate action `ownership-proof` (package C4 of docs/audits/ownership-certificates-plan-2026-10-26.md). It runs
    // `lake build` in proofs/ownership, checks every function of the certificates the language runs above wrote with both the
    // Zig validator and `certcheck` (the verdicts must agree), and runs the fault-injection mutants through both. It waits for
    // the language runs, whose build writes the certificates; `scripts/ownership_proof.py` keeps the verdicts per function.
    // Without `-Dproofs=true` (GH-D10) it, `verify-ir-proof`, `arith-proof` and `cache-proof` are `proofSkipped` steps: one line, exit 0,
    // no driver, no `lake`, and no wait for the language runs. The whole of each waits for the flag: the Zig validator half of
    // `ownership-proof` is the same corpus check the language runs make under `--verify-facts`, and its Lean half is what the
    // action compares it with, so there is no half that runs usefully alone.
    const proof_step = b.step("test-ownership-proof", "Check the ownership certificates the language gate writes with the Zig validator and the Lean checker, and the fault-injection mutants with both (-Dproofs=true runs it; without, it is skipped)");
    const proof_run = if (proofs) bounded(b.addSystemCommand(&.{ "python3", "scripts/ownership_proof.py", "--compiler" }), rss.driver) else proofSkipped(b, "ownership-proof");
    if (proofs) {
        proof_run.addArtifactArg(exe);
        proof_run.setName("ownership-proof");
        proof_run.addArgs(&.{ "--certificates", product.work_dir ++ "/ownership-certificates" });
        if (test_release) proof_run.addArg("--with-release-certificates");
        proof_run.setCwd(b.path("."));
        proof_run.has_side_effects = true;
        for (lang_runs.items) |lang_run| proof_run.step.dependOn(lang_run);
    }
    verification_registry.?.register("ownership-proof", &proof_run.step, &test_inputs.ownership_proof, true, "compiler, source closure, the Lean model and toolchain, and the certificates the language gate writes");
    proof_step.dependOn(&proof_run.step);
    test_step.dependOn(&proof_run.step);
    // VL: the gate action `verify-ir-proof` (lane VL, proofs/verify_ir). It runs `lake build` in proofs/verify_ir (the Lean copy of
    // the IR verifier and the proofs that a module it accepts meets H2 of proofs/facts and A17 of proofs/ownership; the build's
    // `#assert_axioms` fails on a `sorry` or a changed axiom set), compares `selka verify-ir` with `lake exe irverify` on the IR
    // the language runs above wrote with their certificates and on single-rule mutants, checks that every fact certificate is its
    // IR's translation (and that a changed one is caught), and builds the C interop programs to check them the same way. It
    // waits for the language runs, whose builds write the IR, and for `ownership-proof`, which also builds proofs/facts (a path
    // dependency of proofs/verify_ir): two Lake builds never work in proofs/facts at once.
    const verify_ir_step = b.step("test-verify-ir-proof", "Compare the Zig IR verifier with its Lean copy on the IR the language gate writes and on mutants, and check the fact certificates are its translation (-Dproofs=true runs it; without, it is skipped)");
    const verify_ir_run = if (proofs) bounded(b.addSystemCommand(&.{ "python3", "scripts/verify_ir_proof.py", "--compiler" }), rss.driver) else proofSkipped(b, "verify-ir-proof");
    if (proofs) {
        verify_ir_run.addArtifactArg(exe);
        verify_ir_run.setName("verify-ir-proof");
        verify_ir_run.addArgs(&.{ "--certificates", product.work_dir ++ "/ownership-certificates", "--work", product.work_dir ++ "/verify-ir-proof", "--gate" });
        verify_ir_run.setCwd(b.path("."));
        verify_ir_run.has_side_effects = true;
        for (lang_runs.items) |lang_run| verify_ir_run.step.dependOn(lang_run);
        verify_ir_run.step.dependOn(&proof_run.step);
    }
    verification_registry.?.register("verify-ir-proof", &verify_ir_run.step, &test_inputs.verify_ir_proof, true, "compiler, source closure, the Lean copy of the IR verifier and toolchain, the IR the language gate writes, and the C interop fixtures");
    verify_ir_step.dependOn(&verify_ir_run.step);
    test_step.dependOn(&verify_ir_run.step);
    // C8: the gate action `arith-proof` (package C8 of docs/audits/ownership-certificates-plan-2026-10-26.md). It runs `lake build`
    // in proofs/arith (the proofs that the emitter's lowering of floor division, shifts, conversions and saturating addition
    // computes what the language says, and the axiom audit) and checks that the committed templates the emitter is compared
    // with (`src/core/arith_lowering_test.zig`, a test of `test-core`) are what the Lean formulas render. It runs no compiler.
    const arith_step = b.step("test-arith-proof", "Build the arithmetic lowering proofs in proofs/arith and check the templates the emitter is pinned to are what they render (-Dproofs=true runs it; without, it is skipped)");
    const arith_run = if (proofs) bounded(b.addSystemCommand(&.{ "python3", "scripts/arith_proof.py" }), rss.script) else proofSkipped(b, "arith-proof");
    if (proofs) {
        arith_run.setName("arith-proof");
        arith_run.setCwd(b.path("."));
        arith_run.has_side_effects = true;
    }
    verification_registry.?.register("arith-proof", &arith_run.step, &test_inputs.arith_proof, true, "the Lean arithmetic proofs, their rendered templates and toolchain");
    arith_step.dependOn(&arith_run.step);
    test_step.dependOn(&arith_run.step);
    // K4: the gate action `cache-proof` (package K4 of docs/audits/provable-cache-plan-2026-10-26.md). It runs `lake build` in
    // proofs/cache (the model of the build cache, the theorem that a warm build equals the clean build, and the axiom audit),
    // the fixtures of `cacheplan`, and compares the Lean test planner with the Zig cache-plan component on requests recorded from
    // `selka test` over a sample of tests/lang and on random graphs. It needs the compiler and its components, not the
    // language runs, and runs beside the other actions.
    const cache_proof_step = b.step("test-cache-proof", "Build the Lean model of the build cache and compare its test planner with the Zig component on recorded and random requests (-Dproofs=true runs it; without, it is skipped)");
    const cache_proof_run = if (proofs) bounded(b.addSystemCommand(&.{ "python3", "scripts/cache_proof.py", "--compiler" }), rss.driver) else proofSkipped(b, "cache-proof");
    if (proofs) {
        cache_proof_run.addArtifactArg(exe);
        cache_proof_run.setName("cache-proof");
        cache_proof_run.setCwd(b.path("."));
        cache_proof_run.has_side_effects = true;
    }
    verification_registry.?.register("cache-proof", &cache_proof_run.step, &test_inputs.cache_proof, true, "compiler, the cache-plan component, the Lean model of the build cache and toolchain");
    cache_proof_step.dependOn(&cache_proof_run.step);
    test_step.dependOn(&cache_proof_run.step);
    // C7.3: the facts half of `ownership-proof` runs `lake build` in proofs/facts, which depends on proofs/arith; it waits for the
    // arithmetic action so that two builds never work in proofs/arith at once. (Skipped steps run no build, so they wait for nothing.)
    if (proofs) proof_run.step.dependOn(&arith_run.step);
    // S5-C: the new core's own unit tests and end-to-end slice join the gate.
    test_step.dependOn(core_gate_step.?);
    const doctest_step = b.step("test-docs", "Execute every fenced documentation example");
    // The doctest fans its units out across a worker pool, so it is bounded like a suite.
    const doctest_run = driver(b, "selka doctest .", rss.doctest, "doctest");
    doctest_run.addArtifactArg(exe);
    doctest_run.addArgs(&.{ "doctest", "." });
    doctest_step.dependOn(&doctest_run.step);
    test_step.dependOn(&doctest_run.step);
    // W24: the gate action `goals_register`. The goals register (`docs/goals.md`) names Lean theorems, gate actions, files and pinned
    // examples (`test/fixtures/goals`); this fails when a named path or theorem does not exist, a named action is not registered, an
    // example id or an exception count disagrees with its page, or a pinned example fails (it runs `selka doctest` on the pins).
    // It runs no Lean: `ownership-proof`, `arith-proof`, `cache-proof` and `verify-ir-proof` do. The action's id is its input list.
    // DL-7: `--map` makes the same run check the compiler map (`docs/tooling/compiler-map.md`, `tests/compiler_map.py`): every file
    // and function the map names must exist, so the map cannot go stale; it needs no new action.
    const goals_step = b.step("test-goals", "Check that the goals register's and the compiler map's evidence exists and its pinned examples pass");
    const goals_run = driver(b, "python3 tests/goals_register.py", rss.driver, "goals_register");
    goals_run.addArgs(&.{ "python3", "tests/goals_register.py", "--compiler" });
    goals_run.addArtifactArg(exe);
    goals_run.addArgs(&.{ "--map", "docs/tooling/compiler-map.md" });
    goals_step.dependOn(&goals_run.step);
    test_step.dependOn(&goals_run.step);
    // GEN: the gate action `mode_differential`. It generates small valid programs from fixed seeds, builds each with the plain
    // build, `--release` and `selka test` (one program in four also with `--debug-o0`, `--unoptimized` and `selka test
    // --unoptimized`), and fails when the modes disagree on a function's printed value, trap or test verdict, or when any
    // mode stops with an internal compiler error. It is the one place release builds run in the default gate.
    const mode_differential_step = b.step("test-mode-differential", "Build generated programs in several modes and require them to agree");
    const mode_differential_run = driver(b, "python3 tests/mode_differential.py", rss.mode_differential, "mode_differential");
    mode_differential_run.addArgs(&.{ "python3", "tests/mode_differential.py", "--compiler" });
    mode_differential_run.addArtifactArg(exe);
    mode_differential_step.dependOn(&mode_differential_run.step);
    test_step.dependOn(&mode_differential_run.step);
    addParityBench(b);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("build_env.zig"), b.path("build_identity.zig"), b.path("build_test_inputs.zig"), b.path("build_verification.zig"), b.path("src"), b.path("tests"), b.path("test"), b.path("selfhost") }, .check = true });
    const fmt_step = b.step("fmt-check", "Check canonical Zig and live .selka corpus formatting");
    fmt_step.dependOn(&fmt.step);
    verification_registry.?.register("zig-format", &fmt.step, &test_inputs.zig_format, true, "exact formatter and complete source-format scope");
    const my_fmt = driver(b, "check live .selka corpus formatting", rss.script, "my_format");
    my_fmt.addArgs(&.{ "python3", "scripts/check_my_format.py", "--compiler" });
    my_fmt.addArtifactArg(exe);
    fmt_step.dependOn(&my_fmt.step);
    const fmt_tests = driver(b, "verify .selka formatting gate", rss.script, "my_format_self");
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
    // The one live piece of the finished ownership and removed-syntax migration
    // tooling: `selka fix` migrations reuse `migrate_embedded.py`, so its own
    // tests stay in the gate. The audits that checked the migration's output
    // (removed forms, ownership corpora, cleanup rewriters) are retired; the
    // compiler's `E_*_REMOVED` rejections and `selka fix` are tested directly.
    const migrate_step = b.step("test-migrate-embedded", "Verify embedded source extraction and guarded compiler-driven migration");
    for ([_][]const u8{ "tests/test_migrate_embedded.py", "scripts/ownership_applications_test.py" }) |test_path| {
        const migrate_tests = driver(b, b.fmt("python3 {s}", .{test_path}), rss.script, "migrate_embedded");
        migrate_tests.addArgs(&.{ "python3", test_path });
        migrate_step.dependOn(&migrate_tests.step);
        test_step.dependOn(&migrate_tests.step);
    }
    // No test group builds the parity suite, the runtime benchmarks, the
    // examples, the embedded standard library or the Selka components, so this
    // sweep keeps them checking (about six seconds, no exclusions).
    const program_check_step = b.step("test-program-check", "Run selka check over every bench, benchmark, example, stdlib and component program");
    const program_check = driver(b, "selka check standalone programs", rss.script, "program_check");
    program_check.addArgs(&.{ "python3", "scripts/check_programs.py", "--compiler" });
    program_check.addArtifactArg(exe);
    program_check_step.dependOn(&program_check.step);
    test_step.dependOn(&program_check.step);
    const verification_preparation = verification.prepare(b, &.{
        .{ .label = "selka", .binary = exe },
        .{ .label = "units", .binary = unit },
        .{ .label = "tooling-units", .binary = tooling_unit },
        .{ .label = "text-scalar-units", .binary = text_scalar_unit },
        .{ .label = "cli", .binary = integration },
        .{ .label = "core", .binary = verification_core_binary.? },
        .{ .label = "golden", .binary = golden_unit },
        .{ .label = "memory-budget", .binary = budget_unit },
        .{ .label = "test-runner", .binary = runner_unit },
        .{ .label = "component-support", .binary = component_support_tests },
        .{ .label = "component-builder", .binary = component_tool },
    }, if (install_components) |components| .{ .step = components, .manifest = .{ .relative = .{ .base = .install_prefix, .sub_path = product.components_subdir ++ "/test-index.json" } } } else null, &.{ install_exe, &install_component_tool.step });
    verification_registry.?.artifactDependencies("guest", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("language", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("ownership-proof", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("cache-proof", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("goals_register", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("mode_differential", &.{ "selka", "components" });
    verification_registry.?.artifactDependencies("ownership_commands", &.{ "selka", "components" });
    requireLiveEnvironment(b);
    // These scripts use declared source fixtures and isolated stand-ins, and
    // never execute a prepared native compiler or test binary. Unknown/new
    // cohorts retain the complete artifact identity until explicitly reviewed.
    for ([_][]const u8{ "idioms_self", "friction", "affected", "coverage_self", "manifest_self", "verification_cache", "fuzz_campaign", "juice_cache", "juice_pure", "migrate_embedded", "language_guard" }) |id| {
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
    @import("build_coverage.zig").configure(b, .{ .compiler = exe, .units = unit, .cli = integration, .core = verification_core_binary.? });
}
