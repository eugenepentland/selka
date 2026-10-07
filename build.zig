const std = @import("std");
const builtin = @import("builtin");
const guardian = @import("guardian");
/// The repository files each cached test step reads while it runs.
const test_inputs = @import("build_test_inputs.zig");
/// QBE release vendored under `vendor/qbe`; `.qbeversion` must agree with it.
const vendored_qbe = "1.3";
/// Translation units of the vendored QBE release, matching its own `Makefile`.
const qbe_sources = [_][]const u8{
    "main.c",       "util.c",       "parse.c",      "abi.c",          "cfg.c",
    "mem.c",        "ssa.c",        "alias.c",      "load.c",         "copy.c",
    "fold.c",       "gvn.c",        "gcm.c",        "simpl.c",        "ifopt.c",
    "live.c",       "spill.c",      "rega.c",       "emit.c",         "amd64/targ.c",
    "amd64/sysv.c", "amd64/isel.c", "amd64/emit.c", "amd64/winabi.c", "arm64/targ.c",
    "arm64/abi.c",  "arm64/isel.c", "arm64/emit.c", "rv64/targ.c",    "rv64/abi.c",
    "rv64/isel.c",  "rv64/emit.c",
};
/// Compile the vendored QBE release with the pinned Zig C compiler so a native
/// build needs no separately installed assembler and no Python installer.
fn vendoredQbe(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    if (!std.mem.eql(u8, std.mem.trim(u8, @embedFile(".qbeversion"), " \t\r\n"), vendored_qbe))
        @panic("re-vendor vendor/qbe (see vendor/README.md) when changing .qbeversion");
    const module = b.createModule(.{ .target = target, .optimize = .ReleaseFast, .link_libc = true });
    module.addIncludePath(b.path("vendor/qbe"));
    module.addCSourceFiles(.{ .root = b.path("vendor/qbe"), .files = &qbe_sources, .flags = &.{ "-std=c99", "-fno-sanitize=undefined" } });
    return b.addExecutable(.{ .max_rss = rss.compile, .name = "qbe", .root_module = module });
}

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
    /// Zig test binaries, which also spawn the compiler. Observed: the schematic root 48M, the CLI root 31M, byte I/O 11M,
    /// the focused native-test root 13M. The unit root additionally builds and
    /// runs every guest program its suites execute. It links libc dynamically so
    /// the invoke tests can `dlopen` a shared object built against it, which
    /// costs real memory over the statically linked allocator: the whole root now
    /// peaks near 2.2G where it used to peak near 1.1G.
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
    /// shard holding `semantic_cache_test` and `qbe_rc_index_update_test`
    /// peaked at 2.18G running alone (2,281,596 kB, 2026-10-05, 218 tests), so
    /// 2.5G keeps a measured ceiling with headroom.
    const shard_unit: u64 = 2560 * mib;
    /// One shard of the CLI root, which builds far fewer guests. Observed on a
    /// clean cache: 103M-141M for the test process, up to 1.22G for a moment
    /// across its tree; the ceiling is a concurrency budget.
    const shard_cli: u64 = 768 * mib;
    /// The host applications' test roots (board, byte I/O, schematic) and the
    /// directory run of `tests/guest`. Observed on a clean cache (2026-09-23):
    /// the schematic root's process tree 1.24G, `tests/guest` 1.33G, the board
    /// and byte I/O roots under 50M.
    const host_suite: u64 = 1536 * mib;
    /// Drivers that run the compiler a few programs at a time. Observed on a
    /// clean cache: the idiom probes 0.69G, parser hints 0.47G, the C runtime
    /// suites (every suite compiling at once) 0.55G.
    const driver: u64 = 1024 * mib;
    /// Drivers that compile and link many native programs at once, the QBE
    /// parity and boundary drivers. Observed: the boundary matrix 1.29G-1.45G.
    const parity: u64 = 2048 * mib;
    /// Checks that run Python or a small C harness but no compiler: the
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
/// The native tools every guest-running driver needs, and the install step that
/// produces them, filled in once at the top of `build`. A driver invokes an
/// uninstalled compiler whose directory holds no tools, so it names them through
/// the environment the compiler reads.
var tool_qbe: []const u8 = "";
var tool_zig: []const u8 = "";
var install_all: ?*std.Build.Step = null;
/// The tools a focused test needs on disk (`MYLANG_QBE`, and the compiler the
/// unit root resolves beside it), installed to a private prefix. These installs
/// are deliberately not attached to the default install step: Guardian reorders
/// every artifact install attached there to run after its gate, which would drag
/// Guardian back into the focused graph.
var tool_qbe_focus: []const u8 = "";
var install_qbe_focus: ?*std.Build.Step = null;
/// The focused prefix pairs the compiler with `qbe`, because tests in the unit
/// root resolve `mylang` from the directory `MYLANG_QBE` names.
var install_exe_focus: ?*std.Build.Step = null;
/// The emitted `qbe` and compiler binaries. The environment names the tools by
/// an installed path whose bytes the cache key cannot see, so every cached
/// step that runs them declares their contents as inputs.
var tool_inputs: [2]?std.Build.LazyPath = .{ null, null };
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
    inline for (comptime std.meta.declarations(test_inputs)) |name| {
        run.addArgs(&.{ "--list", name });
        run.addArgs(&@field(test_inputs, name));
    }
}
/// The make-time environment manifest `addEnvironmentManifest` writes on every
/// build that runs a cached test step.
var environment_manifest: ?std.Build.LazyPath = null;
/// The environment variables a cached verdict depends on, printed sorted, one
/// `NAME=value` per line, from the environment `zig build` itself runs in.
const environment_script =
    \\env | grep -E '^(PATH|HOME|TMPDIR|XDG_CACHE_HOME|ZIG_GLOBAL_CACHE_DIR|ZIG_LOCAL_CACHE_DIR|MYLANG_[A-Za-z0-9_]*)=' | LC_ALL=C sort > "$1"
;
/// Add the step that records the make-time environment a cached test verdict
/// depends on, once per build. A step's own environment cannot key its verdict:
/// every Run step now inherits `zig build`'s live environment (see
/// `withTools`), which the build runner leaves out of a step's cache key. This
/// file carries it in instead, so a changed `PATH`, `TMPDIR` or `MYLANG_*`
/// re-runs the cached verdicts and an unchanged one keeps them.
fn addEnvironmentManifest(b: *std.Build) void {
    const run = b.addSystemCommand(&.{ "sh", "-c", environment_script, "record-environment" });
    run.setName("record the test environment");
    run.has_side_effects = true;
    run.step.max_rss = rss.script;
    environment_manifest = run.addOutputFileArg("environment.txt");
}
/// Let a test step's verdict be cached: it re-runs only when its command, the
/// environment variables `environment_script` records, an artifact it names,
/// the tools the environment names, or one of the repository files the `list`
/// in `build_test_inputs.zig` declares changes (or under `-Dtest-rerun`). An
/// empty `list` declares no repository files.
fn cached(run: *std.Build.Step.Run, list: []const u8) void {
    run.has_side_effects = test_rerun;
    const b = run.step.owner;
    if (list.len != 0) run.addFileInput(input_manifests.?.path(b, b.fmt("{s}.txt", .{list})));
    run.addFileInput(environment_manifest.?);
    for (tool_inputs) |tool| if (tool) |path| run.addFileInput(path);
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
/// `tools_script`). `env` then adds the tool paths, which depend only on this
/// build's configuration.
fn withTools(step: *std.Build.Step.Run, qbe: []const u8) void {
    const b = step.step.owner;
    var prefix: std.ArrayList([]const u8) = .empty;
    prefix.appendSlice(b.allocator, &.{ "sh", "-c", tools_script, "with-tools" }) catch @panic("out of memory");
    if (qbe.len != 0) {
        prefix.append(b.allocator, b.fmt("MYLANG_QBE={s}", .{qbe})) catch @panic("out of memory");
        prefix.append(b.allocator, b.fmt("MYLANG_ZIG={s}", .{tool_zig})) catch @panic("out of memory");
    }
    const arena = b.graph.arena;
    const args = arena.alloc(std.Build.Step.Run.Arg, prefix.items.len) catch @panic("out of memory");
    for (args, prefix.items) |*arg, word| arg.* = .{ .bytes = b.graph.dupeString(word) };
    step.argv.insertSlice(arena, 0, args) catch @panic("out of memory");
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
/// the directory once that pid has gone, however the command ended.
const tools_script =
    \\if [ -z "${ZIG_GLOBAL_CACHE_DIR+set}" ]; then
    \\  if [ -n "${XDG_CACHE_HOME:-}" ]; then ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/zig"
    \\  elif [ -n "${HOME:-}" ]; then ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/zig"; fi
    \\fi
    \\if [ -n "${ZIG_GLOBAL_CACHE_DIR+set}" ]; then export ZIG_GLOBAL_CACHE_DIR; fi
    \\ZIG_LOCAL_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mylang-zig-local.XXXXXX") || exit 2
    \\export ZIG_LOCAL_CACHE_DIR
    \\(trap '' HUP INT TERM; while kill -0 $$ 2>/dev/null; do sleep 1; done; rm -rf "$ZIG_LOCAL_CACHE_DIR") </dev/null >/dev/null 2>&1 &
    \\exec env "$@"
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
/// Declare a step's resident-memory ceiling, and give it the native tools a guest
/// build needs; harmless on steps that build no guest.
fn bounded(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    step.step.max_rss = bytes;
    withTools(step, tool_qbe);
    if (tool_qbe.len != 0) {
        if (install_all) |install| step.step.dependOn(install);
    }
    return step;
}
/// A focused test step: bound it, name the native tools, and depend only on the
/// unattached `qbe` and compiler copies, not on the whole installation. The
/// compiler under test builds guests from its embedded runtime assets, so a
/// focused test needs neither the runtime archive, the host applications nor
/// Guardian.
fn focused(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    step.step.max_rss = bytes;
    withTools(step, tool_qbe_focus);
    // A test command must execute and report its selection; otherwise a warm
    // cache reuses the previous verdict and hides the selected-test count.
    step.has_side_effects = true;
    if (tool_qbe_focus.len != 0) {
        if (install_qbe_focus) |qbe| step.step.dependOn(qbe);
        if (install_exe_focus) |compiler| step.step.dependOn(compiler);
    }
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
        guardian.announceShard(run, index, shards.count);
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
    // Without -Dbench-cpu the harness picks the first reserved timing CPU itself.
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

/// `zig build test-rc-fuzz [-Dfuzz-seeds=N] [-Dfuzz-start=N]` runs the
/// differential fuzzer in `experiments/rc-fuzz` with the installed compiler: one
/// generated program per seed, under the default reference-counting runtime and
/// its counted and `--release` modes against `--gc-runtime`, failing on any RC
/// divergence (`--gc-stress` findings are reported only). Opt-in like
/// `bench-parity`: `zig build test` never runs it (RC-DEFAULT-1). Arguments after
/// `--` reach the harness (`--jobs N`, `--gen gen2.py`, `--no-stress`).
fn addRcFuzz(b: *std.Build) void {
    const seeds = b.option(u32, "fuzz-seeds", "test-rc-fuzz: how many seeds to generate and compare (default 200)") orelse 200;
    const start = b.option(u32, "fuzz-start", "test-rc-fuzz: the first seed (default 1)") orelse 1;
    const fuzz = b.addSystemCommand(&.{ "python3", "experiments/rc-fuzz/run.py", "--compiler" });
    fuzz.setCwd(b.path("."));
    fuzz.addFileArg(.{ .relative = .{ .base = .install_bin, .sub_path = "mylang" } });
    fuzz.addArgs(&.{ "--start", b.fmt("{d}", .{start}), "--count", b.fmt("{d}", .{seeds}) });
    fuzz.addPassthruArgs();
    fuzz.has_side_effects = true;
    fuzz.step.max_rss = rss.suite;
    fuzz.step.dependOn(b.getInstallStep());
    withTools(fuzz, tool_qbe);
    b.step("test-rc-fuzz", "Differential-fuzz the default RC runtime against --gc-runtime (opt-in, not part of test)").dependOn(&fuzz.step);
}

/// What the new core's steps build on: the shared front end module and the
/// old compiler that serves as its oracle.
const CoreInputs = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    front_end: *std.Build.Module,
    old_compiler: *std.Build.Step.Compile,
    filters: []const []const u8,
    /// Guardian's test runner, which can run one shard of the root (`--guardian-shard`).
    test_runner: std.Build.Step.Compile.TestRunner,
    /// Generated identity over every production compiler/runtime source.
    build_assets: *std.Build.Module,
};

/// The new compiler core (docs/design/new-core-ir.md), kept off the default
/// install graph (decision N2):
/// - `zig build core` installs `zig-out/bin/mylang-core`;
/// - `zig build test-core` runs its unit tests and the end-to-end slice, split into
///   `-Dcore-shards=N` concurrent shards of one test binary (default 8; a
///   `-Dtest-filter` run is one process);
/// - `-Dcore-diff=true` also builds each slice program with the old compiler
///   and requires the same stdout and exit status (it builds the old compiler).
fn addCore(b: *std.Build, inputs: CoreInputs) void {
    const platform = b.createModule(.{ .root_source_file = b.path("src/config_core_tool_platform.zig") });
    const exe = b.addExecutable(.{ .max_rss = rss.compile, .name = "mylang-core", .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/main.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{.{ .name = "mylang", .module = inputs.front_end }},
    }) });
    exe.root_module.addImport("core_tool_platform", platform);
    exe.root_module.addImport("qbe_build_assets", inputs.build_assets);
    b.step("core", "Build and install the new compiler core, zig-out/bin/mylang-core").dependOn(&b.addInstallArtifact(exe, .{}).step);
    const differential = b.option(bool, "core-diff", "test-core: also compare each slice program with the old compiler's build of it") orelse false;
    const options = b.addOptions();
    options.addOptionPath("core_path", exe.getEmittedBin());
    options.addOption(bool, "differential", differential);
    if (differential) options.addOptionPath("old_path", inputs.old_compiler.getEmittedBin()) else options.addOption([]const u8, "old_path", "");
    options.addOptionPath("clock_path", b.path("benchmarks/runtime/ports/native_clock.c"));
    const root = std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, ".", b.allocator) catch @panic("build root");
    options.addOption([]const u8, "fixtures", b.pathJoin(&.{ root, "test", "core" }));
    options.addOption([]const u8, "lang_tests", b.pathJoin(&.{ root, "tests", "lang" }));
    const unit = b.addTest(.{ .max_rss = rss.compile, .filters = inputs.filters, .test_runner = inputs.test_runner, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root_test.zig"),
        .target = inputs.target,
        .optimize = inputs.optimize,
        .imports = &.{.{ .name = "mylang", .module = inputs.front_end }},
    }) });
    unit.root_module.addImport("core_tool_platform", platform);
    unit.root_module.addImport("qbe_build_assets", inputs.build_assets);
    unit.root_module.addOptions("core_test_options", options);
    const step = b.step("test-core", "Run the new core's unit tests and its end-to-end slice (not part of test)");
    // Most of the root's time is end-to-end builds of guest programs, so shards
    // of the one binary run concurrently; each test uses its own temporary tree.
    const requested = b.option(usize, "core-shards", "test-core: concurrent shards of the core test root (default 8)") orelse 8;
    const shards = if (inputs.filters.len == 0) @max(1, requested) else 1;
    for (0..shards) |index| {
        const run = b.addRunArtifact(unit);
        run.step.max_rss = rss.driver;
        run.has_side_effects = true;
        if (shards > 1) guardian.announceShard(run, index, shards);
        step.dependOn(&run.step);
    }
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
    const unit_shards = if (test_filters.len == 0) requested_shards else 1;
    // The CLI root is both smaller and coarser than the unit root, so it takes
    // half the shards; a wider fan-out oversubscribes the core budget and made
    // the whole gate slower even though it shortened the slowest CLI shard.
    const cli_shards = if (test_filters.len == 0) @max(1, requested_shards / 2) else 1;
    // The guest-running hosts live under src/<host>/, so they cannot reach
    // src/memory_budget.zig by path; they import it as a module instead. The
    // compiler itself reaches the same file directly from its own root module.
    const budget = b.addModule("memory_budget", .{
        .root_source_file = b.path("src/memory_budget.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_contract = b.addModule("runtime_contract", .{
        .root_source_file = b.path("src/runtime_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core = b.addModule("mylang", .{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    core.addImport("runtime_contract", runtime_contract);
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
    // Snapshot identity needs the actual application/test root rather than the
    // generated Zig or Guardian test-runner root exposed by `@import("root")`.
    exe.root_module.addImport("runtime_contract", runtime_contract);
    exe.root_module.addImport("native_test_root", exe.root_module);
    addUserDocs(b, exe.root_module);
    const build_assets = @import("build_qbe_assets.zig").module(b, target, optimize, .{ .compile = rss.compile, .run = rss.driver });
    exe.root_module.addImport("qbe_build_assets", build_assets);
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    // Installed beside `mylang`, where the native build driver looks for it before `PATH`.
    const qbe_exe = vendoredQbe(b, target);
    tool_inputs = .{ qbe_exe.getEmittedBin(), exe.getEmittedBin() };
    addInputManifests(b);
    addEnvironmentManifest(b);
    const install_qbe_step = b.addInstallArtifact(qbe_exe, .{});
    b.getInstallStep().dependOn(&install_qbe_step.step);
    // Guest-running drivers invoke an uninstalled compiler with no tools beside it
    // and none on `PATH`; name the vendored tools for them through the environment.
    // The build runs with the project root as its working directory, and the
    // install step (an added dependency) puts `qbe` at this path before any driver.
    const root = std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, ".", b.allocator) catch @panic("build root");
    tool_qbe = b.pathJoin(&.{ root, "zig-out", "bin", "qbe" });
    tool_zig = b.graph.zig_exe;
    // Focused tests need `qbe` on disk but must stay off the gated install graph.
    // A separate, unattached copy of the same binaries gives them a stable path
    // without pulling in Guardian or the other installed artifacts. It is a file
    // copy, not a second artifact install: a run step names an artifact by the
    // path its install left, so two installs of one artifact would make that
    // path (and every cache key holding it) depend on which install ran last.
    const focus_qbe_step = b.addInstallFileWithDir(qbe_exe.getEmittedBin(), .{ .custom = "focus" }, "qbe");
    const focus_exe_step = b.addInstallFileWithDir(exe.getEmittedBin(), .{ .custom = "focus" }, "mylang");
    tool_qbe_focus = b.pathJoin(&.{ root, "zig-out", "focus", "qbe" });
    install_qbe_focus = &focus_qbe_step.step;
    install_exe_focus = &focus_exe_step.step;
    // The compiler `scripts/affected_tests.py` runs guest tests and doctests with:
    // the same unattached copies, so the inner loop never waits on Guardian or
    // on the host applications `zig build` installs.
    const affected_compiler = b.step("affected-compiler", "Install only mylang and qbe to zig-out/focus, for scripts/affected_tests.py");
    affected_compiler.dependOn(&focus_exe_step.step);
    affected_compiler.dependOn(&focus_qbe_step.step);
    // Prebuild the runtime archive (and text-formatter object) for each optimize
    // mode with the freshly built compiler and install them beside it under
    // `lib/mylang-runtime`, so a cold `mylang build` links a matching prebuilt
    // archive instead of compiling the runtime from source on its first run.
    const prebuild = b.addRunArtifact(exe);
    // Name the compiler by its installed path every time, rather than by
    // whichever path exists when this step happens to start, so an unchanged
    // rerun reuses the prebuilt runtime instead of re-emitting it.
    prebuild.step.dependOn(&install_exe.step);
    prebuild.step.max_rss = rss.parity;
    prebuild.addArgs(&.{ "emit-runtime", "--zig", b.graph.zig_exe, "--qbe" });
    prebuild.addFileArg(qbe_exe.getEmittedBin());
    prebuild.addArg("--out");
    const runtime_out = prebuild.addOutputDirectoryArg("mylang-runtime");
    prebuild.addArg("--work");
    _ = prebuild.addOutputDirectoryArg("work");
    const install_runtime = b.addInstallDirectory(.{ .source_dir = runtime_out, .install_dir = .lib, .install_subdir = "mylang-runtime" });
    b.getInstallStep().dependOn(&install_runtime.step);
    install_all = b.getInstallStep();
    // Host applications build their own guests natively, so they carry the same
    // native build driver the compiler does rather than shelling out to it.
    const native_build = b.createModule(.{ .root_source_file = b.path("src/qbe_build.zig"), .target = target, .optimize = optimize });
    native_build.addImport("runtime_contract", runtime_contract);
    native_build.addImport("qbe_build_assets", build_assets);
    native_build.addImport("memory_budget", budget);
    // A host application links guest executables, so it falls back to the tools
    // this build produced when neither a flag, the environment, nor `PATH` names one.
    const host_tools = b.addOptions();
    host_tools.addOptionPath("qbe", qbe_exe.getEmittedBin());
    host_tools.addOption([]const u8, "zig", b.graph.zig_exe);
    const host_native = b.createModule(.{ .root_source_file = b.path("src/host_native.zig"), .target = target, .optimize = optimize });
    host_native.addImport("qbe_build", native_build);
    host_native.addImport("memory_budget", budget);
    host_native.addImport("host_tools", host_tools.createModule());
    const host_imports: []const std.Build.Module.Import = &.{
        .{ .name = "mylang", .module = core },
        .{ .name = "host_native", .module = host_native },
        .{ .name = "memory_budget", .module = budget },
    };
    const guardian_dep = b.dependency("guardian", .{ .target = target, .optimize = optimize });
    const guardian_exe = guardian_dep.artifact("guardian-check");
    const run = bounded(b.addRunArtifact(exe), rss.guest);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const unit = b.addTest(.{
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root_test.zig"),
            .target = target,
            .optimize = optimize,
            // The invoke tests `dlopen` a shared object that `mylang build --library`
            // linked against the system libc. Without this the test binary is
            // statically linked and carries no libc of its own, so the loaded object
            // brings up a second, independent glibc whose global state disagrees with
            // the process it was loaded into: the first call through the loaded codec
            // entry then faults inside glibc at a varying address. Linking the tests
            // the way the loaded object expects turns that boundary into an ordinary
            // dynamic call.
            .link_libc = true,
        }),
    });
    unit.link_gc_sections = true;
    unit.root_module.addIncludePath(b.path("src"));
    unit.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{ "src/native_regions.c", "tests/native_rc_arena_test.c", "tests/native_rc_hold_test.c", "tests/native_rc_fast_test.c", "tests/native_rc_image_test.c", "tests/native_rc_loan_test.c", "tests/native_rc_history_test.c", "tests/native_rc_stats_test.c", "tests/native_rc_contract_test.c", "tests/native_rc_collections_test.c", "tests/native_rc_registered_release_test.c", "tests/native_rc_codecs_test.c", "tests/native_rc_host_test.c", "src/native_print.c", "src/qbe_runtime.c", "src/native_cow.c", "src/native_rc.c", "src/native_rc_stats.c", "src/native_rc_shapes.c", "src/native_rc_walk.c", "src/native_rc_scope.c", "src/native_rc_transfer.c", "src/native_rc_alloc.c", "src/native_rc_values.c", "src/native_heap.c", "src/native_arena.c", "src/native_collections.c", "src/native_text.c", "src/native_search.c", "src/native_trim.c", "src/native_repr.c", "src/native_text_methods.c", "src/native_dictionary.c", "src/native_equal.c", "src/native_bytes.c" },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG", "-DMYL_RC_CONTRACT_LIBRARY", "-DMYL_NATIVE_RC_COUNTING=1", "-DMYL_RC_STATS_LIBRARY", "-DMYL_RC_COLLECTIONS_LIBRARY", "-DMYL_RC_CODECS_LIBRARY", "-DMYL_RC_HOST_LIBRARY", "-ffunction-sections", "-fdata-sections" },
    });
    unit.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{ "tests/native_file_cleanup_test.c", "src/qbe_files.c", "src/qbe_resources.c", "src/qbe_stand_ins.c" },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG", "-DMYL_FILE_CLEANUP_LIBRARY", "-ffunction-sections", "-fdata-sections" },
    });
    unit.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{ "tests/qbe_runtime_rc_test.c", "tests/native_argv_test.c", "src/qbe_runtime_rc.c" },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG", "-DMYL_NATIVE_RC=1", "-DMYL_NATIVE_ARGV_LIBRARY", "-DMYL_RC_CONTRACT_LIBRARY", "-DMYL_NATIVE_RC_COUNTING=1", "-DMYL_RC_STATS_LIBRARY", "-ffunction-sections", "-fdata-sections" },
    });
    unit.root_module.addImport("runtime_contract", runtime_contract);
    unit.root_module.addImport("native_test_root", unit.root_module);
    unit.root_module.addImport("qbe_build_assets", build_assets);
    unit.root_module.addImport("memory_budget", budget);
    addUserDocs(b, unit.root_module);
    // Unit tests execute guest programs natively, so they need the same tools and
    // one shared object cache that `mylang build` uses.
    const native_test_options = b.addOptions();
    native_test_options.addOptionPath("qbe_path", qbe_exe.getEmittedBin());
    native_test_options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    native_test_options.addOption([]const u8, "cache_directory", ".mylang-cache/unit-tests");
    unit.root_module.addOptions("native_test_options", native_test_options);
    const board_module = b.createModule(.{
        .root_source_file = b.path("src/board_trial/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    });
    // `-Dcompiler-only` installs the compiler, QBE and the prebuilt runtime but
    // not the three application runners. Each runner links its own copy of the
    // whole compiler, so a ReleaseFast install otherwise optimizes that code four
    // times; a compiler built only to measure guest programs needs none of them.
    // The application tests under `tests/application_comparison` and
    // `tests/development_velocity` read the runners from `zig-out/bin`, so they
    // need the default install.
    addCore(b, .{ .target = target, .optimize = optimize, .front_end = core, .old_compiler = exe, .filters = test_filters, .test_runner = guardian.testRunner(guardian_dep), .build_assets = build_assets });
    const compiler_only = b.option(bool, "compiler-only", "Install only mylang, qbe and the runtime, not board-trial, schematic-svg or mylang-io (for measurement installs)") orelse false;
    const board_runner = b.addExecutable(.{ .max_rss = rss.compile, .name = "board-trial", .root_module = board_module });
    if (!compiler_only) b.installArtifact(board_runner);
    const schematic_runner = b.addExecutable(.{ .max_rss = rss.compile, .name = "schematic-svg", .root_module = b.createModule(.{
        .root_source_file = b.path("src/schematic/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    }) });
    if (!compiler_only) b.installArtifact(schematic_runner);
    const byte_io_runner = b.addExecutable(.{ .max_rss = rss.compile, .name = "mylang-io", .root_module = b.createModule(.{
        .root_source_file = b.path("src/byte_io/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    }) });
    if (!compiler_only) b.installArtifact(byte_io_runner);
    const byte_io_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/byte_io/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    }) });
    guardian.enableTestDiagnostics(byte_io_unit.root_module);
    guardian.addAllChecks(b, guardian_exe, b.getInstallStep(), .{});
    boundedChecks(b.getInstallStep());
    const board_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/board_trial/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    }) });
    guardian.enableTestDiagnostics(board_unit.root_module);
    const schematic_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/schematic/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = host_imports,
    }) });
    // The schematic tests drive the host application, which builds its guest with
    // a real frontend; a Zig test binary is not one, so it names the installed
    // compiler explicitly rather than recursing into itself.
    const schematic_options = b.addOptions();
    schematic_options.addOptionPath("compiler_path", exe.getEmittedBin());
    schematic_unit.root_module.addOptions("schematic_test_options", schematic_options);
    guardian.enableTestDiagnostics(schematic_unit.root_module);
    const options = b.addOptions();
    options.addOptionPath("compiler_path", exe.getEmittedBin());
    options.addOptionPath("arena_example_path", b.path("examples/arena-managed/main.my"));
    // `run` builds natively, so the CLI fixtures name the tools this build made.
    options.addOptionPath("qbe_path", qbe_exe.getEmittedBin());
    options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    const integration = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
        .root_source_file = b.path("test/integration.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    integration.root_module.addOptions("test_options", options);
    integration.root_module.addImport("runtime_contract", runtime_contract);
    guardian.enableTestDiagnostics(unit.root_module);
    guardian.enableTestDiagnostics(integration.root_module);
    const compile_tests = b.step("test-compile", "Compile every Zig test without running the suite");
    compile_tests.dependOn(&unit.step);
    compile_tests.dependOn(&board_unit.step);
    compile_tests.dependOn(&schematic_unit.step);
    compile_tests.dependOn(&byte_io_unit.step);
    compile_tests.dependOn(&integration.step);
    const run_integration = focused(b.addRunArtifact(integration), rss.suite);
    forwardFilters(b, run_integration, test_filters);
    const test_step = b.step("test", "Run interpreter, checker, CLI, and tooling regression tests");
    b.step("test-interpreter", "Run the default interpreter acceptance suite").dependOn(test_step);
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
    const run_budget_unit = bounded(b.addRunArtifact(budget_unit), rss.driver);
    cached(run_budget_unit, "memory_budget");
    const budget_step = b.step("test-memory-budget", "Verify guest byte ceilings, kernel guards and fan-out bounds");
    budget_step.dependOn(&run_budget_unit.step);
    test_step.dependOn(&run_budget_unit.step);
    compile_tests.dependOn(&budget_unit.step);
    const run_unit = focused(b.addRunArtifact(unit), rss.suite);
    forwardFilters(b, run_unit, test_filters);
    // The gate runs each slow root as several concurrent shards; `test-units`
    // and `test-cli` keep the single whole-root run, so `-Dtest-filter` behaves
    // exactly as documented and its selected-test count means what it says.
    const unit_runs = shardRuns(b, unit, .{ .count = unit_shards, .bytes = rss.shard_unit, .inputs = "unit", .whole = run_unit });
    const cli_runs = shardRuns(b, integration, .{ .count = cli_shards, .bytes = rss.shard_cli, .inputs = "cli", .whole = run_integration });
    dependOnAll(test_step, unit_runs);
    // The fast inner loops: no Python drivers, no Guardian and no full install graph,
    // so `-Dtest-filter` returns in seconds.
    b.step("test-units", "Run only src/root_test.zig, honouring -Dtest-filter").dependOn(&run_unit.step);
    b.step("test-cli", "Run only test/integration.zig, honouring -Dtest-filter").dependOn(&run_integration.step);
    // The same focused runs split into `-Dtest-shards` concurrent processes even
    // under a filter, for `scripts/affected_tests.py`: its selections can name a
    // hundred slow tests, and it sums the shards' counts itself. They are never
    // cached, so every run reports what it selected.
    const units_sharded = b.step("test-units-sharded", "Run src/root_test.zig split into -Dtest-shards processes, honouring -Dtest-filter");
    const cli_sharded = b.step("test-cli-sharded", "Run test/integration.zig split into -Dtest-shards/2 processes, honouring -Dtest-filter");
    dependOnAll(units_sharded, shardRuns(b, unit, .{ .count = requested_shards, .bytes = rss.shard_unit, .inputs = "", .whole = run_unit, .filters = test_filters, .cache = false }));
    dependOnAll(cli_sharded, shardRuns(b, integration, .{ .count = @max(1, requested_shards / 2), .bytes = rss.shard_cli, .inputs = "", .whole = run_integration, .filters = test_filters, .cache = false }));
    const byte_io_step = b.step("test-byte-io", "Verify raw guest stdin/stdout and host bounds");
    const run_byte_io_unit = bounded(b.addRunArtifact(byte_io_unit), rss.host_suite);
    cached(run_byte_io_unit, "byte_io");
    byte_io_step.dependOn(&run_byte_io_unit.step);
    test_step.dependOn(&run_byte_io_unit.step);
    guardian.addAllChecks(b, guardian_exe, byte_io_step, .{});
    boundedChecks(byte_io_step);
    dependOnAll(test_step, cli_runs);
    const run_board_unit = bounded(b.addRunArtifact(board_unit), rss.host_suite);
    cached(run_board_unit, "board");
    test_step.dependOn(&run_board_unit.step);
    const schematic_step = b.step("test-schematic", "Verify guest SVG generation against Netlisp connectivity and source mutations");
    const run_schematic_unit = bounded(b.addRunArtifact(schematic_unit), rss.host_suite);
    cached(run_schematic_unit, "schematic");
    const audit_runtime = b.step("test-runtime-audit", "Run every Zig test root for isolated runtime probes");
    guardian.addAllChecks(b, guardian_exe, audit_runtime, .{});
    boundedChecks(audit_runtime);
    dependOnAll(audit_runtime, unit_runs);
    dependOnAll(audit_runtime, cli_runs);
    audit_runtime.dependOn(&run_board_unit.step);
    audit_runtime.dependOn(&run_byte_io_unit.step);
    audit_runtime.dependOn(&run_schematic_unit.step);
    schematic_step.dependOn(&run_schematic_unit.step);
    test_step.dependOn(&run_schematic_unit.step);
    guardian.addAllChecks(b, guardian_exe, schematic_step, .{});
    boundedChecks(schematic_step);
    const board_step = b.step("test-board-trial", "Verify the bounded board-validation trial against its independent oracle");
    board_step.dependOn(&run_board_unit.step);
    const disk_step = b.step("test-disk-projects", "Verify guest edits using unchanged host binaries and no build tools on PATH");
    disk_step.dependOn(&run_schematic_unit.step);
    disk_step.dependOn(&run_board_unit.step);
    guardian.addAllChecks(b, guardian_exe, disk_step, .{});
    boundedChecks(disk_step);
    const dev_step = b.step("test-dev-reload", "Verify persistent VM generations and snapshot preview reloads");
    dev_step.dependOn(&run_schematic_unit.step);
    guardian.addAllChecks(b, guardian_exe, dev_step, .{});
    boundedChecks(dev_step);
    const intent_step = b.step("test-intent", "Verify requirement links, revisions and source-pinned evidence");
    guardian.addAllChecks(b, guardian_exe, intent_step, .{});
    boundedChecks(intent_step);
    const verification_step = b.step("test-verification", "Verify dependency selection, cache, scheduler and merge certificates");
    guardian.addAllChecks(b, guardian_exe, verification_step, .{});
    boundedChecks(verification_step);
    const repair_step = b.step("test-repair-study", "Verify repair-study fixtures and retained evidence");
    guardian.addAllChecks(b, guardian_exe, repair_step, .{});
    boundedChecks(repair_step);
    const qbe_step = b.step("test-qbe", "Run QBE native compilation, runtime, and object-cache acceptance");
    const native_heap_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native_heap_module.addIncludePath(b.path("src"));
    native_heap_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{
            "tests/native_heap_test.c",
            "src/native_heap.c",
            "src/native_rc.c",
            "src/native_rc_stats.c",
            "src/native_rc_shapes.c",
            "src/native_rc_walk.c",
            "src/native_rc_scope.c",
            "src/native_rc_transfer.c",
            "src/native_rc_alloc.c",
            "src/native_rc_values.c",

            "src/native_arena.c",
            // Structural equality looks dictionary keys up through the table.
            "src/native_dictionary.c",
            "src/native_equal.c",
            "src/native_text.c",
            "src/native_search.c",
            "src/native_trim.c",
            "src/native_repr.c",
            "src/native_collections.c",
            "src/native_bytes.c",
        },
        // Keep the harness's C assertions active under every optimize mode.
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const native_heap_test = b.addExecutable(.{
        .max_rss = rss.compile,
        .name = "native-heap-test",
        .root_module = native_heap_module,
    });
    const run_native_heap_test = b.addRunArtifact(native_heap_test);
    run_native_heap_test.step.max_rss = rss.script;
    // The harness binary is its only input, so a checked run is cached on it.
    run_native_heap_test.expectExitCode(0);
    const native_heap_step = b.step("test-native-heap", "Verify native collector trace, cycle, budget, and equality paths");
    const native_arena_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native_arena_module.addIncludePath(b.path("src"));
    native_arena_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{
            "tests/native_arena_chunks_test.c",
            "src/native_heap.c",
            "src/native_rc.c",
            "src/native_rc_stats.c",
            "src/native_rc_shapes.c",
            "src/native_rc_walk.c",
            "src/native_rc_scope.c",
            "src/native_rc_transfer.c",
            "src/native_rc_alloc.c",
            "src/native_rc_values.c",

            "src/native_arena.c",
            "src/native_collections.c",
            "src/native_text.c",
            "src/native_search.c",
            "src/native_trim.c",
            "src/native_repr.c",
            "src/native_dictionary.c",
            "src/native_equal.c",
            "src/native_bytes.c",
            "src/native_regions.c",
        },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const native_arena_test = b.addExecutable(.{
        .max_rss = rss.compile,
        .name = "native-arena-chunks-test",
        .root_module = native_arena_module,
    });
    const run_native_arena_test = b.addRunArtifact(native_arena_test);
    run_native_arena_test.step.max_rss = rss.script;
    run_native_arena_test.expectExitCode(0);
    // COW-UNIQUE-1: copy on write over the collector, under collection stress.
    const native_cow_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native_cow_module.addIncludePath(b.path("src"));
    native_cow_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{
            "tests/native_cow_test.c",
            "src/native_cow.c",
            "src/native_heap.c",
            "src/native_rc.c",
            "src/native_rc_stats.c",
            "src/native_rc_shapes.c",
            "src/native_rc_walk.c",
            "src/native_rc_scope.c",
            "src/native_rc_transfer.c",
            "src/native_rc_alloc.c",
            "src/native_rc_values.c",

            "src/native_arena.c",
            "src/native_collections.c",
            "src/native_text.c",
            "src/native_search.c",
            "src/native_trim.c",
            "src/native_repr.c",
            "src/native_dictionary.c",
            "src/native_equal.c",
            "src/native_bytes.c",
            "src/native_regions.c",
        },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const native_cow_test = b.addExecutable(.{
        .max_rss = rss.compile,
        .name = "native-cow-test",
        .root_module = native_cow_module,
    });
    const run_native_cow_test = b.addRunArtifact(native_cow_test);
    run_native_cow_test.step.max_rss = rss.script;
    run_native_cow_test.expectExitCode(0);
    native_heap_step.dependOn(&run_native_cow_test.step);
    compile_tests.dependOn(&native_cow_test.step);
    test_step.dependOn(&run_native_cow_test.step);
    qbe_step.dependOn(&run_native_cow_test.step);
    native_heap_step.dependOn(&run_native_arena_test.step);
    native_heap_step.dependOn(&run_native_heap_test.step);
    guardian.addAllChecks(b, guardian_exe, native_heap_step, .{});
    boundedChecks(native_heap_step);
    compile_tests.dependOn(&native_heap_test.step);
    compile_tests.dependOn(&native_arena_test.step);
    test_step.dependOn(&run_native_heap_test.step);
    test_step.dependOn(&run_native_arena_test.step);
    qbe_step.dependOn(&run_native_heap_test.step);
    qbe_step.dependOn(&run_native_arena_test.step);
    // ERROR-TRACE-6: the trace recorders keep the registers their convention promises.
    const error_trace_abi_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    error_trace_abi_module.addIncludePath(b.path("src"));
    error_trace_abi_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &.{
            "tests/error_trace_abi_test.c",
            "src/qbe_runtime.c",
            "src/qbe_stack.c",
            "src/native_cow.c",
            "src/native_heap.c",
            "src/native_rc.c",
            "src/native_rc_stats.c",
            "src/native_rc_shapes.c",
            "src/native_rc_walk.c",
            "src/native_rc_scope.c",
            "src/native_rc_transfer.c",
            "src/native_rc_alloc.c",
            "src/native_rc_values.c",

            "src/native_arena.c",
            "src/native_collections.c",
            "src/native_text.c",
            "src/native_search.c",
            "src/native_trim.c",
            "src/native_repr.c",
            "src/native_dictionary.c",
            "src/native_equal.c",
            "src/native_bytes.c",
            "src/native_regions.c",
        },
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const error_trace_abi_test = b.addExecutable(.{
        .max_rss = rss.compile,
        .name = "error-trace-abi-test",
        .root_module = error_trace_abi_module,
    });
    const run_error_trace_abi_test = b.addRunArtifact(error_trace_abi_test);
    run_error_trace_abi_test.step.max_rss = rss.script;
    run_error_trace_abi_test.expectExitCode(0);
    const error_trace_abi_step = b.step("test-error-trace-abi", "Verify the error trace recorders keep the registers their calling conventions promise");
    error_trace_abi_step.dependOn(&run_error_trace_abi_test.step);
    compile_tests.dependOn(&error_trace_abi_test.step);
    test_step.dependOn(&run_error_trace_abi_test.step);
    qbe_step.dependOn(&run_error_trace_abi_test.step);
    const native_test_step = b.step("test-native-tests", "Verify native guest test discovery, execution, fixtures, and affected-test reuse");
    const native_test_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/native_test_cli_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    native_test_unit.root_module.addImport("runtime_contract", runtime_contract);
    native_test_unit.root_module.addImport("native_test_root", native_test_unit.root_module);
    native_test_unit.root_module.addImport("qbe_build_assets", build_assets);
    native_test_unit.root_module.addImport("memory_budget", budget);
    guardian.enableTestDiagnostics(native_test_unit.root_module);
    const run_native_test_unit = bounded(b.addRunArtifact(native_test_unit), rss.suite);
    cached(run_native_test_unit, "native_roots");
    native_test_step.dependOn(&run_native_test_unit.step);
    compile_tests.dependOn(&native_test_unit.step);
    guardian.addAllChecks(b, guardian_exe, native_test_step, .{});
    boundedChecks(native_test_step);
    qbe_step.dependOn(native_test_step);
    const ffi_step = b.step("test-c-ffi", "Verify direct C scalar imports and native library linking");
    const ffi_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/c_abi_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    ffi_unit.root_module.addImport("runtime_contract", runtime_contract);
    guardian.enableTestDiagnostics(ffi_unit.root_module);
    const run_ffi_unit = bounded(b.addRunArtifact(ffi_unit), rss.suite);
    cached(run_ffi_unit, "native_roots");
    ffi_step.dependOn(&run_ffi_unit.step);
    compile_tests.dependOn(&ffi_unit.step);
    guardian.addAllChecks(b, guardian_exe, ffi_step, .{});
    boundedChecks(ffi_step);
    qbe_step.dependOn(ffi_step);
    const qbe_build_step = b.step("test-qbe-build", "Verify native builds without Python and native adapter generation");
    qbe_step.dependOn(qbe_build_step);
    const host_native_unit = b.addTest(.{
        .max_rss = rss.compile,
        .test_runner = guardian.testRunner(guardian_dep),
        .root_module = host_native,
    });
    guardian.enableTestDiagnostics(host_native_unit.root_module);
    const run_host_native_unit = bounded(b.addRunArtifact(host_native_unit), rss.suite);
    cached(run_host_native_unit, "native_roots");
    qbe_build_step.dependOn(&run_host_native_unit.step);
    compile_tests.dependOn(&host_native_unit.step);
    const qbe_build_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/qbe_build_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    qbe_build_unit.root_module.addImport("runtime_contract", runtime_contract);
    qbe_build_unit.root_module.addImport("qbe_build_assets", build_assets);
    qbe_build_unit.root_module.addImport("memory_budget", budget);
    guardian.enableTestDiagnostics(qbe_build_unit.root_module);
    const run_qbe_build_unit = bounded(b.addRunArtifact(qbe_build_unit), rss.suite);
    cached(run_qbe_build_unit, "native_roots");
    qbe_build_step.dependOn(&run_qbe_build_unit.step);
    compile_tests.dependOn(&qbe_build_unit.step);
    const host_bridge_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    host_bridge_module.addIncludePath(b.path("src"));
    host_bridge_module.addCSourceFile(.{
        .file = b.path("tests/qbe_host_bridge.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const host_bridge_test = b.addExecutable(.{ .name = "host-bridge-test", .root_module = host_bridge_module, .max_rss = rss.compile });
    const run_host_bridge_test = bounded(b.addRunArtifact(host_bridge_test), rss.suite);
    // The bridge harness binary is its only input, so a checked run is cached on it.
    run_host_bridge_test.expectExitCode(0);
    qbe_build_step.dependOn(&run_host_bridge_test.step);
    compile_tests.dependOn(&host_bridge_test.step);
    guardian.addAllChecks(b, guardian_exe, qbe_build_step, .{});
    boundedChecks(qbe_build_step);
    const golden_step = b.step("test-golden", "Replay the checked-in native golden corpora with no Python oracle");
    const golden_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
        .root_source_file = b.path("test/golden_parity.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    golden_unit.root_module.addOptions("test_options", options);
    guardian.enableTestDiagnostics(golden_unit.root_module);
    compile_tests.dependOn(&golden_unit.step);
    const run_golden = bounded(b.addRunArtifact(golden_unit), rss.suite);
    cached(run_golden, "golden");
    forwardFilters(b, run_golden, test_filters);
    run_golden.setCwd(b.path("."));
    golden_step.dependOn(&run_golden.step);
    qbe_step.dependOn(golden_step);
    guardian.addAllChecks(b, guardian_exe, qbe_step, .{});
    boundedChecks(qbe_step);
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
    // MODULE-CHECK-1: the same walk over a project whose modules sit in
    // subdirectories under a `mylang.json`, where `check` is per module.
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
    // MODULE-COMPILE-1..3: every module of `tests/lang` and the fixtures,
    // compiled on its own from its imports' interfaces, emits the whole
    // program's units key for key (Debug, and ReleaseFast switches) and links
    // into the whole program's executable; the default build of each program
    // (module by module, MODULE-SCHEDULE-1..4) makes the `--whole-program`
    // build's executable and an unchanged rebuild compiles nothing; and an
    // incremental default build after seeded edits builds what a clean
    // whole-program build builds.
    const module_compile_step = b.step("test-module-compile", "Per-module compilation and the default per-module build against the whole-program build, and its build differential");
    const module_programs = [_][]const u8{ "tests/fixtures/interfaces/main.my", "tests/fixtures/interfaces_generic/main.my", "tests/fixtures/incremental/main.my", "tests/fixtures/module_compile/main.my", "tests/fixtures/module_projects/main.my" };
    const module_oracle = driver(b, "python3 tests/module_compile_oracle.py", rss.driver, "module_compile");
    module_oracle.addArgs(&.{ "python3", "tests/module_compile_oracle.py" });
    module_oracle.addArtifactArg(exe);
    module_oracle.addArg("tests/lang");
    module_oracle.addArgs(&module_programs);
    module_compile_step.dependOn(&module_oracle.step);
    const module_release = driver(b, "python3 tests/module_compile_oracle.py --release", rss.driver, "module_compile");
    module_release.addArgs(&.{ "python3", "tests/module_compile_oracle.py", "--release" });
    module_release.addArtifactArg(exe);
    module_release.addArgs(&module_programs);
    module_compile_step.dependOn(&module_release.step);
    const module_build = driver(b, "python3 tests/module_build_oracle.py", rss.driver, "module_compile");
    module_build.addArgs(&.{ "python3", "tests/module_build_oracle.py" });
    module_build.addArtifactArg(exe);
    module_build.addArg("tests/lang");
    module_build.addArgs(&module_programs);
    module_compile_step.dependOn(&module_build.step);
    // MODULE-CHECK-1: the default `check` (module by module) of the same
    // programs against the whole-program check.
    const module_check = driver(b, "python3 tests/module_check_oracle.py", rss.driver, "module_compile");
    module_check.addArgs(&.{ "python3", "tests/module_check_oracle.py" });
    module_check.addArtifactArg(exe);
    module_check.addArg("tests/lang");
    module_check.addArgs(&module_programs);
    module_compile_step.dependOn(&module_check.step);
    // MODULE-TEST-1: the default `test` (module by module) of the same
    // programs against `test --whole-program`.
    const module_tests = driver(b, "python3 tests/module_test_oracle.py", rss.driver, "module_compile");
    module_tests.addArgs(&.{ "python3", "tests/module_test_oracle.py" });
    module_tests.addArtifactArg(exe);
    module_tests.addArg("tests/lang");
    module_tests.addArgs(&module_programs);
    module_compile_step.dependOn(&module_tests.step);
    const module_diff = driver(b, "python3 tests/module_build_diff.py", rss.driver, "module_compile");
    module_diff.addArgs(&.{ "python3", "tests/module_build_diff.py", "--steps", "20" });
    module_diff.addArtifactArg(exe);
    module_compile_step.dependOn(&module_diff.step);
    // MODULE-PROJECT-1: the same differential over a project with a `mylang.json`.
    const project_diff = driver(b, "python3 tests/module_build_diff.py --project tests/fixtures/module_projects", rss.driver, "module_compile");
    project_diff.addArgs(&.{ "python3", "tests/module_build_diff.py", "--project", "tests/fixtures/module_projects", "--steps", "12" });
    project_diff.addArtifactArg(exe);
    module_compile_step.dependOn(&project_diff.step);
    test_step.dependOn(module_compile_step);
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
    spec_merge_step.dependOn(&spec_merge_run.step);
    test_step.dependOn(spec_merge_step);
    // The bundled runtime's `content_hash` comes from a make-phase run of
    // `build_qbe_assets.zig`. This driver runs that file on throwaway trees that
    // share one Zig cache, the way a stale hash once reached an installed compiler.
    const identity_step = b.step("test-runtime-identity", "Verify the bundled runtime's identity follows its bytes across trees and edits");
    const identity_run = bounded(b.addSystemCommand(&.{"python3"}), rss.driver);
    identity_run.addFileArg(b.path("tests/runtime_identity_cache.py"));
    identity_run.addArgs(&.{ "--zig", b.graph.zig_exe });
    identity_run.addFileInput(b.path("build_qbe_assets.zig"));
    identity_run.addFileInput(environment_manifest.?);
    identity_run.expectExitCode(0);
    identity_step.dependOn(&identity_run.step);
    test_step.dependOn(identity_step);
    // The boundary matrix runs every carried shape through both native backends
    // and requires one answer, so a shape that satisfies its contract on QBE and
    // not on LLVM fails here instead of on whichever backend nobody ran.
    const boundary_step = b.step("test-native-boundary", "Verify every carried boundary shape agrees across the QBE and LLVM backends");
    const boundary_self = driver(b, "python3 tests/native_boundary_matrix.py --self-test", rss.script, "boundary_self");
    boundary_self.addArgs(&.{ "python3", "tests/native_boundary_matrix.py", "--self-test" });
    boundary_step.dependOn(&boundary_self.step);
    const boundary_run = driver(b, "python3 tests/native_boundary_matrix.py --compiler", rss.parity, "boundary");
    boundary_run.addArgs(&.{ "python3", "tests/native_boundary_matrix.py", "--compiler" });
    boundary_run.addArtifactArg(exe);
    boundary_step.dependOn(&boundary_run.step);
    test_step.dependOn(boundary_step);
    // The LLVM adapter's unit tests pin its IL parsing, overflow-intrinsic
    // rewrites, frame map and declaration attributes. Nothing else fails if the
    // adapter silently stops matching a shape, so they run in the gate.
    const adapter_step = b.step("test-llvm-adapter", "Run the LLVM adapter's unit tests");
    const adapter_run = driver(b, "python3 -m unittest test_adapter", rss.driver, "adapter");
    adapter_run.addArgs(&.{ "python3", "-m", "unittest", "test_adapter" });
    adapter_run.setCwd(b.path("experiments/llvm-backend"));
    adapter_step.dependOn(&adapter_run.step);
    test_step.dependOn(adapter_step);
    // The C runtime's own suites (heap, collections, text, dictionary, regions,
    // print, text views) under UBSan. Two of them broke silently in merges when
    // only lanes ran them by hand, so they run in the gate.
    const native_memory_step = b.step("test-native-memory", "Run the C runtime suites under UBSan");
    const native_memory_run = driver(b, "python3 scripts/test_native_memory.py", rss.driver, "native_memory");
    native_memory_run.addArgs(&.{ "python3", "scripts/test_native_memory.py" });
    native_memory_step.dependOn(&native_memory_run.step);
    test_step.dependOn(native_memory_step);
    // The inner loop's own machinery: the change-to-test mapping behind
    // `scripts/affected_tests.py`, and the check that every repository file a
    // cached test root names is one of its declared inputs.
    const affected_step = b.step("test-affected-selection", "Pin scripts/affected_tests.py's change-to-test mapping");
    const affected_run = driver(b, "python3 tests/test_affected_tests.py", rss.script, "affected");
    affected_run.addArgs(&.{ "python3", "tests/test_affected_tests.py" });
    affected_step.dependOn(&affected_run.step);
    test_step.dependOn(affected_step);
    const coverage_step = b.step("test-inputs-coverage", "Require every repository file a cached test names to be a declared input");
    const coverage_self = driver(b, "python3 tests/test_inputs_coverage.py --self-test", rss.script, "coverage_self");
    coverage_self.addArgs(&.{ "python3", "tests/test_inputs_coverage.py", "--self-test" });
    coverage_step.dependOn(&coverage_self.step);
    const coverage_run = driver(b, "python3 tests/test_inputs_coverage.py", rss.script, "coverage");
    const manifest_self = driver(b, "python3 tests/input_manifest.py --self-test", rss.script, "manifest_self");
    manifest_self.addArgs(&.{ "python3", "tests/input_manifest.py", "--self-test" });
    coverage_step.dependOn(&manifest_self.step);
    coverage_run.addArgs(&.{ "python3", "tests/test_inputs_coverage.py" });
    coverage_step.dependOn(&coverage_run.step);
    test_step.dependOn(coverage_step);
    const doc_coverage = bounded(b.addRunArtifact(exe), rss.driver);
    doc_coverage.addArgs(&.{ "doc-coverage", "." });
    doc_coverage.setCwd(b.path("."));
    doc_coverage.has_side_effects = true;
    b.step("test-doc-coverage", "Require a documented example for every feature and standard export").dependOn(&doc_coverage.step);
    test_step.dependOn(&doc_coverage.step);
    const guest_step = b.step("test-guest", "Run the guest-behavior tests written in the language");
    const guest_tests = bounded(b.addRunArtifact(exe), rss.host_suite);
    guest_tests.addArgs(&.{ "test", "tests/guest", "--cache-dir", ".mylang-cache/guest-tests" });
    guest_tests.setCwd(b.path("."));
    guest_tests.has_side_effects = true;
    guest_step.dependOn(&guest_tests.step);
    test_step.dependOn(&guest_tests.step);
    guardian.addAllChecks(b, guardian_exe, guest_step, .{});
    boundedChecks(guest_step);
    const lang_step = b.step("test-lang", "Run the unit root's migrated language-level guest tests under RC and under stressed GC");
    // RC-DEFAULT-1: the suite runs once under the default reference-counting
    // runtime and once under the `--gc-runtime` opt-out, where the collector
    // stress the Zig root's `native_execute` tests ask for is a run-wide flag,
    // so every migrated program keeps that coverage too.
    const lang_tests = bounded(b.addRunArtifact(exe), rss.suite);
    lang_tests.addArgs(&.{ "test", "tests/lang", "--cache-dir", ".mylang-cache/lang-tests" });
    lang_tests.setCwd(b.path("."));
    lang_tests.has_side_effects = true;
    lang_step.dependOn(&lang_tests.step);
    test_step.dependOn(&lang_tests.step);
    const lang_gc_step = b.step("test-lang-gc", "Run the language-level guest tests under the tracing collector with --gc-stress");
    const lang_gc_tests = bounded(b.addRunArtifact(exe), rss.suite);
    lang_gc_tests.addArgs(&.{ "test", "tests/lang", "--gc-runtime", "--cache-dir", ".mylang-cache/lang-tests-gc", "--gc-stress" });
    lang_gc_tests.setCwd(b.path("."));
    lang_gc_tests.has_side_effects = true;
    lang_gc_step.dependOn(&lang_gc_tests.step);
    lang_step.dependOn(&lang_gc_tests.step);
    test_step.dependOn(&lang_gc_tests.step);
    guardian.addAllChecks(b, guardian_exe, lang_step, .{});
    boundedChecks(lang_step);
    guardian.addAllChecks(b, guardian_exe, lang_gc_step, .{});
    boundedChecks(lang_gc_step);
    const legacy_step = b.step("test-legacy-sharing", "Run migration-window sharing tests under --legacy-sharing");
    const legacy_tests = bounded(b.addRunArtifact(exe), rss.suite);
    legacy_tests.addArgs(&.{ "test", "tests/legacy", "--legacy-sharing", "--cache-dir", ".mylang-cache/legacy-tests", "--gc-stress" });
    legacy_tests.setCwd(b.path("."));
    legacy_tests.has_side_effects = true;
    legacy_step.dependOn(&legacy_tests.step);
    test_step.dependOn(&legacy_tests.step);
    guardian.addAllChecks(b, guardian_exe, legacy_step, .{});
    boundedChecks(legacy_step);
    // VALUE-SEMANTICS-1: the guest tests that assert value semantics run
    // with the switch on, under the default RC runtime and, like `test-lang`,
    // under the stressed collector (RC-DEFAULT-1).
    const values_step = b.step("test-value-semantics", "Run the value-semantics guest tests under --value-semantics");
    const value_tests = bounded(b.addRunArtifact(exe), rss.suite);
    value_tests.addArgs(&.{ "test", "tests/value_semantics", "--value-semantics", "--cache-dir", ".mylang-cache/value-semantics-tests" });
    value_tests.setCwd(b.path("."));
    value_tests.has_side_effects = true;
    values_step.dependOn(&value_tests.step);
    test_step.dependOn(&value_tests.step);
    const value_gc_tests = bounded(b.addRunArtifact(exe), rss.suite);
    value_gc_tests.addArgs(&.{ "test", "tests/value_semantics", "--value-semantics", "--gc-runtime", "--cache-dir", ".mylang-cache/value-semantics-tests-gc", "--gc-stress" });
    value_gc_tests.setCwd(b.path("."));
    value_gc_tests.has_side_effects = true;
    values_step.dependOn(&value_gc_tests.step);
    test_step.dependOn(&value_gc_tests.step);
    guardian.addAllChecks(b, guardian_exe, values_step, .{});
    boundedChecks(values_step);
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
    addRcFuzz(b);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests"), b.path("test") }, .check = true });
    b.step("fmt-check", "Check canonical Zig formatting").dependOn(&fmt.step);
    requireLiveEnvironment(b);
}
