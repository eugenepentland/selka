//! The edit check's coverage variant (EC1): the compiler and the three Zig test roots
//! built with the pinned Zig's `-ffuzz` edge counters and the coverage runtime
//! (`tools/edit_check/coverage_rt.zig`), installed under `zig-out/coverage/`.
//!
//! Nothing here changes the normal build. A plain configuration only gains the
//! `coverage` step, which runs a second `zig build` with
//! `-Dcoverage-instrument=true` into its own prefix; the instrumented
//! configuration is the same graph with every module's `fuzz` switched on. Neither
//! step is part of the install graph or the gate.
const std = @import("std");

/// Resident-memory reservation for an instrumented compile: the LLVM backend peaks near 4 GiB.
const compile_reservation: usize = 6 * 1024 * 1024 * 1024;

/// The artifacts the coverage variant instruments, as `build()` made them.
pub const Artifacts = struct {
    /// The `selka` executable.
    compiler: *std.Build.Step.Compile,
    /// The compiler unit root (`src/root_test.zig`).
    units: *std.Build.Step.Compile,
    /// The CLI root (`test/integration.zig`).
    cli: *std.Build.Step.Compile,
    /// The new core's root (`src/core/root_test.zig`).
    core: *std.Build.Step.Compile,
};

/// The edit check's developer tool and its tests, built only when their steps are requested.
fn addTools(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const tool = b.addExecutable(.{ .name = "edit-check-tool", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/edit_check/edit_check_tool.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    }) });
    const install = b.addInstallArtifact(tool, .{ .dest_dir = .{ .override = .{ .custom = "tools" } } });
    b.step("edit-check-tool", "Build the edit check's map and impact tool into <prefix>/tools").dependOn(&install.step);
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/edit_check/root_test.zig"),
        .target = target,
        .optimize = .Debug,
    }) });
    tests.root_module.addOptions("test_options", test_options);
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(b.path("."));
    // The impact step (EC2) is its own tool; its root sits in `tools/` so it can import `edit_check/`.
    const impact = b.addExecutable(.{ .name = "edit-check-impact", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/impact.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    }) });
    const install_impact = b.addInstallArtifact(impact, .{ .dest_dir = .{ .override = .{ .custom = "tools" } } });
    b.step("edit-check-impact", "Build the edit check's impact tool into <prefix>/tools").dependOn(&install_impact.step);
    const impact_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tools/impact.zig"),
        .target = target,
        .optimize = .Debug,
    }) });
    const run_impact_tests = b.addRunArtifact(impact_tests);
    run_impact_tests.setCwd(b.path("."));
    // The map refresh's scheduling (scripts/edit_check_refresh.py): batching, cancellation, refusal, locking, merging.
    const refresh_tests = b.addSystemCommand(&.{ "python3", "-B", "scripts/edit_check_refresh_test.py" });
    refresh_tests.setCwd(b.path("."));
    const test_step = b.step("test-edit-check", "Run the edit check tools' tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_impact_tests.step);
    test_step.dependOn(&refresh_tests.step);
}

/// Declare the `edit-check-binaries` step: the three Zig test binaries, uninstrumented, under
/// `<prefix>/edit-check`, and the marker that their test runner (`tools/test_runner/`) has `--test-list`.
/// The step is not part of the install graph.
fn addEditCheckBinaries(b: *std.Build, artifacts: Artifacts) void {
    const step = b.step("edit-check-binaries", "Install the Zig test binaries the edit check runs under <prefix>/edit-check");
    const dir: std.Build.InstallDir = .{ .custom = "edit-check" };
    const named = [_]struct { []const u8, *std.Build.Step.Compile }{
        .{ "unit-tests", artifacts.units },
        .{ "cli-tests", artifacts.cli },
        .{ "core-tests", artifacts.core },
    };
    for (named) |entry| {
        step.dependOn(&b.addInstallArtifact(entry[1], .{ .dest_dir = .{ .override = dir }, .dest_sub_path = entry[0] }).step);
    }
    const marker = b.addWriteFiles();
    const file = marker.add("test-list-supported", "guardian runtime_test_list\n");
    step.dependOn(&b.addInstallFileWithDir(file, dir, "test-list-supported").step);
}

/// Declare the `coverage` step, and under `-Dcoverage-instrument=true` instrument
/// `artifacts` and declare `coverage-binaries`, which installs them.
pub fn configure(b: *std.Build, artifacts: Artifacts) void {
    addTools(b);
    addEditCheckBinaries(b, artifacts);
    const map_run = b.addSystemCommand(&.{ "python3", "scripts/edit_check_map.py" });
    map_run.setCwd(b.path("."));
    b.step("coverage-map", "Collect per-test coverage and write the map to the edit check store (run it directly; it takes build slots itself)").dependOn(&map_run.step);
    const instrument = b.option(bool, "coverage-instrument", "Instrument the compiler and Zig test roots with edge counters (use with the coverage-binaries step)") orelse false;
    if (!instrument) {
        const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "coverage-binaries", "-Dcoverage-instrument=true", "--prefix" });
        run.argv.append(b.graph.arena, .{ .decorated_directory = .{
            .prefix = "",
            .suffix = "",
            .make_absolute = true,
            .lazy_path = .{ .relative = .{ .base = .install_prefix, .sub_path = "coverage" } },
        } }) catch @panic("out of memory");
        b.step("coverage", "Build the instrumented compiler and Zig test roots into <prefix>/coverage (edit check)").dependOn(&run.step);
        return;
    }
    const runtime = b.addObject(.{ .name = "coverage_rt", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/edit_check/coverage_rt.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .ReleaseSafe,
        .link_libc = true,
        .fuzz = false,
    }) });
    const hooks = b.addObject(.{ .name = "coverage_hooks", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/edit_check/coverage_hooks.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .ReleaseSafe,
        .link_libc = true,
        .fuzz = false,
    }) });
    const installs = b.step("coverage-binaries", "Install the instrumented compiler and Zig test roots under <prefix>/bin");
    const named = [_]struct { []const u8, *std.Build.Step.Compile }{
        .{ "selka", artifacts.compiler },
        .{ "unit-tests", artifacts.units },
        .{ "cli-tests", artifacts.cli },
        .{ "core-tests", artifacts.core },
    };
    for (named) |entry| {
        const compile = entry[1];
        // The native self-hosted backend emits no coverage counters.
        compile.use_llvm = true;
        // LLVM's Debug backend peaks above the self-hosted backend's declared reservation.
        compile.step.max_rss = compile_reservation;
        // `exit` must run `atexit`, which the runtime uses to write the hit set.
        compile.root_module.link_libc = true;
        // A build id names the binary's code: a copy of the binary keeps it, and the map finds the binary a
        // process ran from by it when a test has deleted that copy (the coverage runtime writes it into each `.cov`).
        compile.build_id = .fast;
        for (compile.root_module.getGraph().modules) |module| module.fuzz = true;
        compile.root_module.addObject(runtime);
        // Test binaries link the fuzzer runtime through the test runner, which already defines the hooks.
        if (compile.kind != .@"test") compile.root_module.addObject(hooks);
        installs.dependOn(&b.addInstallArtifact(compile, .{ .dest_sub_path = entry[0] }).step);
    }
}
