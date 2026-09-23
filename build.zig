const std = @import("std");
const builtin = @import("builtin");
const guardian = @import("guardian");
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
    /// the guest programs, so its peak sits well under the whole root's 1.1G:
    /// observed 77M-336M across eight warm shards. The ceiling keeps the cold
    /// margin the whole root needs while letting eight shards share a
    /// `--maxrss` budget the whole root's 2G ceiling would not stretch to.
    const shard_unit: u64 = 1536 * mib;
    /// One shard of the CLI root, which builds far fewer guests. Observed
    /// 91M-139M across four warm shards; the ceiling is a concurrency budget.
    const shard_cli: u64 = 1024 * mib;
    /// Python drivers that drive the compiler but build no native programs.
    const driver: u64 = 1024 * mib;
    /// Drivers that compile and link native programs, the QBE parity and
    const parity: u64 = 2048 * mib;
    /// Guardian's whole-tree gate. Observed: the whole-tree run stays well under 100M.
    const gate: u64 = 1024 * mib;
    /// Zig compilations. Only these and the test binaries report a peak to the
    /// build runner, so only they can trip a ceiling; the margin over the debug
    /// peak leaves room for a ReleaseFast build of the same tree.
    /// Observed (debug): src/root_test.zig 335M, the mylang executable 270M, the
    /// other test roots 166-232M, the small runner executables 42M.
    /// Observed (ReleaseFast, C3/C4 tree): a test-root compile peaked at 2.55G,
    /// so the old 2.15G bound blocked the documented gate; 3G keeps a bounded
    /// ceiling with headroom for the same tree.
    const compile: u64 = 3072 * mib;
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
/// The qualified LLVM adapter source a test driver names through
/// `MYLANG_LLVM_ADAPTER`: a test binary runs the compiler from a cache directory
/// that has no `lib/mylang-llvm` beside it, and a ReleaseFast build defaults to
/// the LLVM arm, so the adapter must be found the way `qbe` is.
var tool_llvm_adapter: []const u8 = "";
/// Declare a step's resident-memory ceiling, and give it the native tools a guest
/// build needs; harmless on steps that build no guest.
fn bounded(step: *std.Build.Step.Run, bytes: u64) *std.Build.Step.Run {
    step.step.max_rss = bytes;
    // Name Zig's global cache explicitly: a test that redirects `HOME` for a child
    // compiler would otherwise send its `zig cc` invocations to an empty cache.
    if (std.zig.resolveGlobalCacheDir(step.step.owner.allocator, &step.step.owner.graph.environ_map)) |zig_cache| {
        step.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", zig_cache);
    } else |_| {}
    if (tool_qbe.len != 0) {
        step.setEnvironmentVariable("MYLANG_QBE", tool_qbe);
        step.setEnvironmentVariable("MYLANG_ZIG", tool_zig);
        if (tool_llvm_adapter.len != 0) step.setEnvironmentVariable("MYLANG_LLVM_ADAPTER", tool_llvm_adapter);
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
    // Name Zig's global cache explicitly: a test that redirects `HOME` for a child
    // compiler would otherwise send its `zig cc` invocations to an empty cache.
    if (std.zig.resolveGlobalCacheDir(step.step.owner.allocator, &step.step.owner.graph.environ_map)) |zig_cache| {
        step.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", zig_cache);
    } else |_| {}
    // A test command must execute and report its selection; otherwise a warm
    // cache reuses the previous verdict and hides the selected-test count.
    step.has_side_effects = true;
    if (tool_qbe_focus.len != 0) {
        step.setEnvironmentVariable("MYLANG_QBE", tool_qbe_focus);
        step.setEnvironmentVariable("MYLANG_ZIG", tool_zig);
        if (tool_llvm_adapter.len != 0) step.setEnvironmentVariable("MYLANG_LLVM_ADAPTER", tool_llvm_adapter);
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
/// The runs that cover one test root: `count` shards of the same test binary,
/// each executing the slice of the root's named tests that `--guardian-shard=`
/// assigns it, or the caller's single whole-root run when `count` is 1. The
/// shards partition the root — Guardian's runner gives the unnamed `test { }`
/// blocks to shard 0 alone — so together they run every test exactly once, and
/// the build runner schedules them concurrently against its `--maxrss` budget.
fn shardRuns(
    b: *std.Build,
    compile: *std.Build.Step.Compile,
    bytes: u64,
    count: usize,
    whole: *std.Build.Step.Run,
) []const *std.Build.Step {
    if (count <= 1) return b.allocator.dupe(*std.Build.Step, &.{&whole.step}) catch @panic("out of memory");
    const steps = b.allocator.alloc(*std.Build.Step, count) catch @panic("out of memory");
    for (steps, 0..) |*step, index| {
        const run = focused(b.addRunArtifact(compile), bytes);
        guardian.announceShard(run, index, count);
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

/// `zig build bench-parity`: the standing mylang/Zig/Rust parity benchmark under
/// `bench/parity`. It builds every arm with the compiler this build installs (or
/// `-Dbench-mylang=PATH`), requires byte-identical output, times pinned
/// interleaved rounds and checks each program's ratio to Zig ReleaseFast against
/// `bench/parity/thresholds.json`. Opt-in: nothing else depends on it, so
/// `zig build test` never builds or times it. Arguments after `--` reach the
/// harness (`--json PATH`, `--arms ...`, `--write-thresholds`).
fn addParityBench(b: *std.Build) void {
    const cpu = b.option(u32, "bench-cpu", "bench-parity: the one CPU every timed process is pinned to (default 2)") orelse 2;
    const rounds = b.option(u32, "bench-rounds", "bench-parity: timed rounds per program (default 7)") orelse 7;
    const filter = b.option([]const u8, "bench-filter", "bench-parity: comma-separated substrings of GROUP/NAME, e.g. sieve or micro/");
    const compiler = b.option([]const u8, "bench-mylang", "bench-parity: time this compiler instead of the one this build installs");
    const bench = b.addSystemCommand(&.{ "python3", "bench/parity/bench_parity.py", "run", "--zig", b.graph.zig_exe });
    bench.setCwd(b.path("."));
    bench.addArgs(&.{ "--cpu", b.fmt("{d}", .{cpu}), "--rounds", b.fmt("{d}", .{rounds}) });
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

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.0-dev.1683+5ceec001b"))
        @panic("mylang requires Guardian's Zig 0.17.0-dev.1683+5ceec001b toolchain (see .zigversion)");
    const target = b.resolveTargetQuery(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dtest-filter=SUBSTRING` narrows the unit and CLI suites to one area in seconds.
    // An absent flag runs every test; an explicitly empty one is a footgun that
    // silently selects the whole suite, so reject it before it reaches a test root.
    const test_filters: []const []const u8 = if (b.option([]const u8, "test-filter", "Run only Zig tests whose name contains this substring")) |needle| blk: {
        if (std.mem.trim(u8, needle, " \t\r\n").len == 0) {
            std.debug.print("error: -Dtest-filter= needs a non-empty substring; run `zig build test` for the full suite\n", .{});
            std.process.exit(2);
        }
        break :blk b.dupeStrings(&.{needle});
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
    const core = b.addModule("mylang", .{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .max_rss = rss.compile,
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
    exe.root_module.addImport("native_test_root", exe.root_module);
    const build_assets = @import("build_qbe_assets.zig").module(b, target, optimize, .{ .compile = rss.compile, .run = rss.driver });
    exe.root_module.addImport("qbe_build_assets", build_assets);
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);
    // Installed beside `mylang`, where the native build driver looks for it before `PATH`.
    const qbe_exe = vendoredQbe(b, target);
    const install_qbe_step = b.addInstallArtifact(qbe_exe, .{});
    b.getInstallStep().dependOn(&install_qbe_step.step);
    // LLVM's adapter is optional at run time; keep its imported modules beside
    // its entry point so an installed compiler needs no source checkout.
    for ([_][]const u8{ "qbe_llvm.py", "llvm_emit.py", "runtime_signatures.py", "amd64_sysv.py" }) |file| {
        const source = b.path(b.pathJoin(&.{ "experiments", "llvm-backend", file }));
        const install = b.addInstallFileWithDir(source, .lib, b.pathJoin(&.{ "mylang-llvm", file }));
        b.getInstallStep().dependOn(&install.step);
    }
    // Guest-running drivers invoke an uninstalled compiler with no tools beside it
    // and none on `PATH`; name the vendored tools for them through the environment.
    // The build runs with the project root as its working directory, and the
    // install step (an added dependency) puts `qbe` at this path before any driver.
    const root = std.Io.Dir.cwd().realPathFileAlloc(b.graph.io, ".", b.allocator) catch @panic("build root");
    tool_qbe = b.pathJoin(&.{ root, "zig-out", "bin", "qbe" });
    tool_zig = b.graph.zig_exe;
    // A test binary runs the compiler from a cache directory with no
    // `lib/mylang-llvm` beside it, and a ReleaseFast build now defaults to the
    // LLVM arm, so name the adapter source the same way `qbe` is named.
    tool_llvm_adapter = b.pathJoin(&.{ root, "experiments", "llvm-backend", "qbe_llvm.py" });
    // Focused tests need `qbe` on disk but must stay off the gated install graph.
    // A separate, unattached install of the same compile step gives them a stable
    // path without pulling in Guardian or the other installed artifacts.
    const focus_qbe_step = b.addInstallArtifact(qbe_exe, .{ .dest_dir = .{ .override = .{ .custom = "focus" } } });
    const focus_exe_step = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "focus" } } });
    tool_qbe_focus = b.pathJoin(&.{ root, "zig-out", "focus", "qbe" });
    install_qbe_focus = &focus_qbe_step.step;
    install_exe_focus = &focus_exe_step.step;
    // Prebuild the runtime archive (and text-formatter object) for each optimize
    // mode with the freshly built compiler and install them beside it under
    // `lib/mylang-runtime`, so a cold `mylang build` links a matching prebuilt
    // archive instead of compiling the runtime from source on its first run.
    const prebuild = b.addRunArtifact(exe);
    prebuild.step.max_rss = rss.parity;
    prebuild.addArgs(&.{ "emit-runtime", "--zig", b.graph.zig_exe, "--qbe" });
    prebuild.addFileArg(qbe_exe.getEmittedBin());
    // The release path links an LLVM/bitcode runtime archive, so the prebuild
    // needs the qualified adapter; it lives in the source tree until installed.
    prebuild.addArg("--llvm-adapter");
    prebuild.addArg(b.pathJoin(&.{ root, "experiments", "llvm-backend", "qbe_llvm.py" }));
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
    native_build.addImport("qbe_build_assets", build_assets);
    native_build.addImport("memory_budget", budget);
    // A host application links guest executables, so it falls back to the tools
    // this build produced when neither a flag, the environment, nor `PATH` names one.
    const host_tools = b.addOptions();
    host_tools.addOptionPath("qbe", qbe_exe.getEmittedBin());
    host_tools.addOption([]const u8, "zig", b.graph.zig_exe);
    host_tools.addOption([]const u8, "llvm_adapter", b.pathJoin(&.{ root, "experiments", "llvm-backend", "qbe_llvm.py" }));
    const host_native = b.createModule(.{ .root_source_file = b.path("src/host_native.zig"), .target = target, .optimize = optimize });
    host_native.addImport("qbe_build", native_build);
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
    unit.root_module.addImport("native_test_root", unit.root_module);
    unit.root_module.addImport("qbe_build_assets", build_assets);
    unit.root_module.addImport("memory_budget", budget);
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
    const run_unit = focused(b.addRunArtifact(unit), rss.suite);
    forwardFilters(b, run_unit, test_filters);
    // The gate runs each slow root as several concurrent shards; `test-units`
    // and `test-cli` keep the single whole-root run, so `-Dtest-filter` behaves
    // exactly as documented and its selected-test count means what it says.
    const unit_runs = shardRuns(b, unit, rss.shard_unit, unit_shards, run_unit);
    const cli_runs = shardRuns(b, integration, rss.shard_cli, cli_shards, run_integration);
    dependOnAll(test_step, unit_runs);
    // The fast inner loops: no Python drivers, no Guardian and no full install graph,
    // so `-Dtest-filter` returns in seconds.
    b.step("test-units", "Run only src/root_test.zig, honouring -Dtest-filter").dependOn(&run_unit.step);
    b.step("test-cli", "Run only test/integration.zig, honouring -Dtest-filter").dependOn(&run_integration.step);
    const byte_io_step = b.step("test-byte-io", "Verify raw guest stdin/stdout and host bounds");
    const run_byte_io_unit = bounded(b.addRunArtifact(byte_io_unit), rss.suite);
    byte_io_step.dependOn(&run_byte_io_unit.step);
    test_step.dependOn(&run_byte_io_unit.step);
    guardian.addAllChecks(b, guardian_exe, byte_io_step, .{});
    boundedChecks(byte_io_step);
    dependOnAll(test_step, cli_runs);
    const run_board_unit = bounded(b.addRunArtifact(board_unit), rss.suite);
    test_step.dependOn(&run_board_unit.step);
    const schematic_step = b.step("test-schematic", "Verify guest SVG generation against Netlisp connectivity and source mutations");
    const run_schematic_unit = bounded(b.addRunArtifact(schematic_unit), rss.suite);
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
            "src/native_arena.c",
            "src/native_equal.c",
            "src/native_text.c",
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
    run_native_heap_test.step.max_rss = rss.driver;
    run_native_heap_test.has_side_effects = true;
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
            "src/native_arena.c",
            "src/native_collections.c",
            "src/native_text.c",
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
    run_native_arena_test.step.max_rss = rss.driver;
    run_native_arena_test.has_side_effects = true;
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
    const native_test_step = b.step("test-native-tests", "Verify native guest test discovery, execution, fixtures, and affected-test reuse");
    const native_test_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/native_test_cli_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    native_test_unit.root_module.addImport("native_test_root", native_test_unit.root_module);
    native_test_unit.root_module.addImport("qbe_build_assets", build_assets);
    native_test_unit.root_module.addImport("memory_budget", budget);
    guardian.enableTestDiagnostics(native_test_unit.root_module);
    native_test_step.dependOn(&bounded(b.addRunArtifact(native_test_unit), rss.suite).step);
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
    guardian.enableTestDiagnostics(ffi_unit.root_module);
    ffi_step.dependOn(&bounded(b.addRunArtifact(ffi_unit), rss.suite).step);
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
    qbe_build_step.dependOn(&bounded(b.addRunArtifact(host_native_unit), rss.suite).step);
    compile_tests.dependOn(&host_native_unit.step);
    const qbe_build_unit = b.addTest(.{ .max_rss = rss.compile, .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/qbe_build_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    qbe_build_unit.root_module.addImport("qbe_build_assets", build_assets);
    qbe_build_unit.root_module.addImport("memory_budget", budget);
    guardian.enableTestDiagnostics(qbe_build_unit.root_module);
    qbe_build_step.dependOn(&bounded(b.addRunArtifact(qbe_build_unit), rss.suite).step);
    compile_tests.dependOn(&qbe_build_unit.step);
    const host_bridge_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    host_bridge_module.addIncludePath(b.path("src"));
    host_bridge_module.addCSourceFile(.{
        .file = b.path("tests/qbe_host_bridge.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-UNDEBUG" },
    });
    const host_bridge_test = b.addExecutable(.{ .name = "host-bridge-test", .root_module = host_bridge_module, .max_rss = rss.compile });
    qbe_build_step.dependOn(&bounded(b.addRunArtifact(host_bridge_test), rss.suite).step);
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
    const idiom_self_test = bounded(b.addSystemCommand(&.{ "python3", "tests/idiom_probes.py", "--self-test" }), rss.driver);
    idiom_self_test.setCwd(b.path("."));
    idiom_step.dependOn(&idiom_self_test.step);
    const idiom_run = bounded(b.addSystemCommand(&.{ "python3", "tests/idiom_probes.py", "--compiler" }), rss.parity);
    idiom_run.addArtifactArg(exe);
    idiom_run.setCwd(b.path("."));
    idiom_run.has_side_effects = true;
    idiom_step.dependOn(&idiom_run.step);
    test_step.dependOn(idiom_step);
    // The repair-round packages ship two Python drivers beside their Zig tests:
    // the parser-hint/classifier agreement (static, then end to end against this
    // compiler) and the friction harvest over its replay fixture. Registering
    // them here keeps them from rotting outside the gate.
    const usefulness_step = b.step("test-agent-usefulness", "Verify parser hints, headerless imports, and the friction harvest");
    const hints_static = bounded(b.addSystemCommand(&.{ "python3", "tests/parser_hints.py" }), rss.driver);
    hints_static.setCwd(b.path("."));
    usefulness_step.dependOn(&hints_static.step);
    const hints_run = bounded(b.addSystemCommand(&.{ "python3", "tests/parser_hints.py", "--compiler" }), rss.parity);
    hints_run.addArtifactArg(exe);
    hints_run.setCwd(b.path("."));
    hints_run.has_side_effects = true;
    usefulness_step.dependOn(&hints_run.step);
    const harvest_run = bounded(b.addSystemCommand(&.{ "python3", "tests/test_friction_harvest.py" }), rss.driver);
    harvest_run.setCwd(b.path("."));
    usefulness_step.dependOn(&harvest_run.step);
    test_step.dependOn(usefulness_step);
    // The bundled runtime's `content_hash` comes from a make-phase run of
    // `build_qbe_assets.zig`. This driver runs that file on throwaway trees that
    // share one Zig cache, the way a stale hash once reached an installed compiler.
    const identity_step = b.step("test-runtime-identity", "Verify the bundled runtime's identity follows its bytes across trees and edits");
    const identity_run = bounded(b.addSystemCommand(&.{"python3"}), rss.driver);
    identity_run.addFileArg(b.path("tests/runtime_identity_cache.py"));
    identity_run.addArgs(&.{ "--zig", b.graph.zig_exe });
    identity_run.addFileInput(b.path("build_qbe_assets.zig"));
    identity_run.expectExitCode(0);
    identity_step.dependOn(&identity_run.step);
    test_step.dependOn(identity_step);
    // The boundary matrix runs every carried shape through both native backends
    // and requires one answer, so a shape that satisfies its contract on QBE and
    // not on LLVM fails here instead of on whichever backend nobody ran.
    const boundary_step = b.step("test-native-boundary", "Verify every carried boundary shape agrees across the QBE and LLVM backends");
    const boundary_self = bounded(b.addSystemCommand(&.{ "python3", "tests/native_boundary_matrix.py", "--self-test" }), rss.driver);
    boundary_self.setCwd(b.path("."));
    boundary_step.dependOn(&boundary_self.step);
    const boundary_run = bounded(b.addSystemCommand(&.{ "python3", "tests/native_boundary_matrix.py", "--compiler" }), rss.parity);
    boundary_run.addArtifactArg(exe);
    boundary_run.setCwd(b.path("."));
    boundary_run.has_side_effects = true;
    boundary_step.dependOn(&boundary_run.step);
    test_step.dependOn(boundary_step);
    // The LLVM adapter's unit tests pin its IL parsing, overflow-intrinsic
    // rewrites, frame map and declaration attributes. Nothing else fails if the
    // adapter silently stops matching a shape, so they run in the gate.
    const adapter_step = b.step("test-llvm-adapter", "Run the LLVM adapter's unit tests");
    const adapter_run = bounded(b.addSystemCommand(&.{ "python3", "-m", "unittest", "test_adapter" }), rss.driver);
    adapter_run.setCwd(b.path("experiments/llvm-backend"));
    adapter_run.has_side_effects = true;
    adapter_step.dependOn(&adapter_run.step);
    test_step.dependOn(adapter_step);
    // The C runtime's own suites (heap, collections, text, dictionary, regions,
    // print, text views) under UBSan. Two of them broke silently in merges when
    // only lanes ran them by hand, so they run in the gate.
    const native_memory_step = b.step("test-native-memory", "Run the C runtime suites under UBSan");
    const native_memory_run = bounded(b.addSystemCommand(&.{ "python3", "scripts/test_native_memory.py" }), rss.driver);
    native_memory_run.setCwd(b.path("."));
    native_memory_run.has_side_effects = true;
    native_memory_step.dependOn(&native_memory_run.step);
    test_step.dependOn(native_memory_step);
    const doc_coverage = bounded(b.addRunArtifact(exe), rss.driver);
    doc_coverage.addArgs(&.{ "doc-coverage", "." });
    doc_coverage.setCwd(b.path("."));
    doc_coverage.has_side_effects = true;
    b.step("test-doc-coverage", "Require a documented example for every feature and standard export").dependOn(&doc_coverage.step);
    test_step.dependOn(&doc_coverage.step);
    const guest_step = b.step("test-guest", "Run the guest-behavior tests written in the language");
    const guest_tests = bounded(b.addRunArtifact(exe), rss.suite);
    guest_tests.addArgs(&.{ "test", "tests/guest", "--cache-dir", ".mylang-cache/guest-tests" });
    guest_tests.setCwd(b.path("."));
    guest_tests.has_side_effects = true;
    guest_step.dependOn(&guest_tests.step);
    test_step.dependOn(&guest_tests.step);
    guardian.addAllChecks(b, guardian_exe, guest_step, .{});
    boundedChecks(guest_step);
    const lang_step = b.step("test-lang", "Run the unit root's migrated language-level guest tests");
    const lang_tests = bounded(b.addRunArtifact(exe), rss.suite);
    // The collector stress the Zig root's `native_execute` tests ask for is a
    // run-wide flag here, so every migrated program gets the same coverage.
    lang_tests.addArgs(&.{ "test", "tests/lang", "--cache-dir", ".mylang-cache/lang-tests", "--gc-stress" });
    lang_tests.setCwd(b.path("."));
    lang_tests.has_side_effects = true;
    lang_step.dependOn(&lang_tests.step);
    test_step.dependOn(&lang_tests.step);
    guardian.addAllChecks(b, guardian_exe, lang_step, .{});
    boundedChecks(lang_step);
    const doctest_step = b.step("test-docs", "Execute every fenced documentation example");
    // The doctest fans its units out across a worker pool, so it is bounded like a suite.
    const doctest_run = bounded(b.addRunArtifact(exe), rss.suite);
    doctest_run.addArgs(&.{ "doctest", "." });
    doctest_run.setCwd(b.path("."));
    doctest_run.has_side_effects = true;
    doctest_step.dependOn(&doctest_run.step);
    test_step.dependOn(&doctest_run.step);
    guardian.addAllChecks(b, guardian_exe, doctest_step, .{});
    boundedChecks(doctest_step);
    addParityBench(b);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests"), b.path("test") }, .check = true });
    b.step("fmt-check", "Check canonical Zig formatting").dependOn(&fmt.step);
}
