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
    const exe = b.addExecutable(.{ .name = "qbe", .root_module = module });
    b.installArtifact(exe);
    return exe;
}

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.0-dev.1683+5ceec001b"))
        @panic("mylang requires Guardian's Zig 0.17.0-dev.1683+5ceec001b toolchain (see .zigversion)");
    const target = b.resolveTargetQuery(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dtest-filter=SUBSTRING` narrows the unit and CLI suites to one area in seconds.
    const test_filters: []const []const u8 = if (b.option([]const u8, "test-filter", "Run only Zig tests whose name contains this substring")) |needle|
        b.dupeStrings(&.{needle})
    else
        &.{};
    const core = b.addModule("mylang", .{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "mylang",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "mylang", .module = core }},
        }),
    });
    const build_assets = @import("build_qbe_assets.zig").module(b, target, optimize);
    exe.root_module.addImport("qbe_build_assets", build_assets);
    b.installArtifact(exe);
    // Installed beside `mylang`, where the native build driver looks for it before `PATH`.
    const qbe_exe = vendoredQbe(b, target);
    const guardian_dep = b.dependency("guardian", .{ .target = target, .optimize = optimize });
    const guardian_exe = guardian_dep.artifact("guardian-check");
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
        .root_source_file = b.path("src/root_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    unit.root_module.addImport("qbe_build_assets", build_assets);
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
        .imports = &.{.{ .name = "mylang", .module = core }},
    });
    const board_runner = b.addExecutable(.{ .name = "board-trial", .root_module = board_module });
    b.installArtifact(board_runner);
    const schematic_runner = b.addExecutable(.{ .name = "schematic-svg", .root_module = b.createModule(.{
        .root_source_file = b.path("src/schematic/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    b.installArtifact(schematic_runner);
    const byte_io_runner = b.addExecutable(.{ .name = "mylang-io", .root_module = b.createModule(.{
        .root_source_file = b.path("src/byte_io/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    b.installArtifact(byte_io_runner);
    const byte_io_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/byte_io/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    guardian.enableTestDiagnostics(byte_io_unit.root_module);
    guardian.addAllChecks(b, guardian_exe, b.getInstallStep(), .{});
    const board_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/board_trial/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    guardian.enableTestDiagnostics(board_unit.root_module);
    const schematic_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/schematic/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    guardian.enableTestDiagnostics(schematic_unit.root_module);
    const options = b.addOptions();
    options.addOptionPath("compiler_path", exe.getEmittedBin());
    options.addOptionPath("arena_example_path", b.path("examples/arena-managed/main.my"));
    // `run` builds natively, so the CLI fixtures name the tools this build made.
    options.addOptionPath("qbe_path", qbe_exe.getEmittedBin());
    options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    const integration = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .filters = test_filters, .root_module = b.createModule(.{
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
    const run_integration = b.addRunArtifact(integration);
    const test_step = b.step("test", "Run interpreter, checker, CLI, and tooling regression tests");
    b.step("test-interpreter", "Run the default interpreter acceptance suite").dependOn(test_step);
    guardian.addAllChecks(b, guardian_exe, test_step, .{});
    const run_unit = b.addRunArtifact(unit);
    test_step.dependOn(&run_unit.step);
    // The fast inner loops: no Python drivers and no Guardian, so `-Dtest-filter` returns in seconds.
    b.step("test-units", "Run only src/root_test.zig, honouring -Dtest-filter").dependOn(&run_unit.step);
    b.step("test-cli", "Run only test/integration.zig, honouring -Dtest-filter").dependOn(&run_integration.step);
    const byte_io_step = b.step("test-byte-io", "Verify raw guest stdin/stdout and host bounds");
    const run_byte_io_unit = b.addRunArtifact(byte_io_unit);
    byte_io_step.dependOn(&run_byte_io_unit.step);
    test_step.dependOn(&run_byte_io_unit.step);
    const byte_io_cli = b.addSystemCommand(&.{ "python3", "tests/byte_io.py", "--runner" });
    byte_io_cli.addFileArg(byte_io_runner.getEmittedBin());
    byte_io_cli.setCwd(b.path("."));
    byte_io_step.dependOn(&byte_io_cli.step);
    test_step.dependOn(&byte_io_cli.step);
    guardian.addAllChecks(b, guardian_exe, byte_io_step, .{});
    test_step.dependOn(&run_integration.step);
    const run_board_unit = b.addRunArtifact(board_unit);
    test_step.dependOn(&run_board_unit.step);
    const schematic_runtime = b.addSystemCommand(&.{ "python3", "tests/schematic_svg.py", "--runner" });
    schematic_runtime.addFileArg(schematic_runner.getEmittedBin());
    schematic_runtime.setCwd(b.path("."));
    test_step.dependOn(&schematic_runtime.step);
    const schematic_step = b.step("test-schematic", "Verify guest SVG generation against Netlisp connectivity and source mutations");
    schematic_step.dependOn(&schematic_runtime.step);
    const run_schematic_unit = b.addRunArtifact(schematic_unit);
    const audit_runtime = b.step("test-runtime-audit", "Run every Zig test root for isolated runtime probes");
    guardian.addAllChecks(b, guardian_exe, audit_runtime, .{});
    audit_runtime.dependOn(&run_unit.step);
    audit_runtime.dependOn(&run_integration.step);
    audit_runtime.dependOn(&run_board_unit.step);
    audit_runtime.dependOn(&run_byte_io_unit.step);
    audit_runtime.dependOn(&run_schematic_unit.step);
    schematic_step.dependOn(&run_schematic_unit.step);
    test_step.dependOn(&run_schematic_unit.step);
    guardian.addAllChecks(b, guardian_exe, schematic_step, .{});
    const board_runtime = b.addSystemCommand(&.{ "python3", "tests/board_trial.py", "--runner" });
    board_runtime.addFileArg(board_runner.getEmittedBin());
    board_runtime.addArg("--compiler");
    board_runtime.addFileArg(exe.getEmittedBin());
    board_runtime.setCwd(b.path("."));
    test_step.dependOn(&board_runtime.step);
    const disk_runtime = b.addSystemCommand(&.{ "python3", "tests/disk_projects.py", "--schematic-runner" });
    disk_runtime.addFileArg(schematic_runner.getEmittedBin());
    disk_runtime.addArg("--board-runner");
    disk_runtime.addFileArg(board_runner.getEmittedBin());
    disk_runtime.setCwd(b.path("."));
    test_step.dependOn(&disk_runtime.step);
    const disk_step = b.step("test-disk-projects", "Verify guest edits using unchanged host binaries and no build tools on PATH");
    disk_step.dependOn(&disk_runtime.step);
    disk_step.dependOn(&run_schematic_unit.step);
    disk_step.dependOn(&run_board_unit.step);
    guardian.addAllChecks(b, guardian_exe, disk_step, .{});
    const dependency_runtime = b.addSystemCommand(&.{ "python3", "tests/project_dependencies.py", "--compiler" });
    dependency_runtime.addFileArg(exe.getEmittedBin());
    dependency_runtime.setCwd(b.path("."));
    test_step.dependOn(&dependency_runtime.step);
    const dev_runtime = b.addSystemCommand(&.{ "python3", "tests/dev_reload.py", "--runner" });
    dev_runtime.addFileArg(schematic_runner.getEmittedBin());
    dev_runtime.setCwd(b.path("."));
    test_step.dependOn(&dev_runtime.step);
    const dev_step = b.step("test-dev-reload", "Verify persistent VM generations and snapshot preview reloads");
    dev_step.dependOn(&dev_runtime.step);
    dev_step.dependOn(&run_schematic_unit.step);
    guardian.addAllChecks(b, guardian_exe, dev_step, .{});
    const intent_tests = b.addSystemCommand(&.{ "python3", "tests/intent_trace.py", "--compiler" });
    intent_tests.addFileArg(exe.getEmittedBin());
    intent_tests.setCwd(b.path("."));
    test_step.dependOn(&intent_tests.step);
    const intent_step = b.step("test-intent", "Verify requirement links, revisions and source-pinned evidence");
    intent_step.dependOn(&intent_tests.step);
    guardian.addAllChecks(b, guardian_exe, intent_step, .{});
    const driver_tests = b.addSystemCommand(&.{ "python3", "tests/verification/run_tests.py", "--compiler" });
    driver_tests.addFileArg(exe.getEmittedBin());
    driver_tests.setCwd(b.path("."));
    test_step.dependOn(&driver_tests.step);
    const verification_step = b.step("test-verification", "Verify dependency selection, cache, scheduler and merge certificates");
    verification_step.dependOn(&driver_tests.step);
    verification_step.dependOn(&dependency_runtime.step);
    guardian.addAllChecks(b, guardian_exe, verification_step, .{});
    const board_contract = b.addSystemCommand(&.{ "python3", "-m", "unittest", "discover", "-s", "experiments/board_trial", "-p", "test_oracle.py" });
    board_contract.setCwd(b.path("."));
    test_step.dependOn(&board_contract.step);
    const repair_study = b.addSystemCommand(&.{ "python3", "experiments/board_trial/repair/selftest.py", "--compiler" });
    repair_study.addFileArg(exe.getEmittedBin());
    repair_study.addArgs(&.{ "--zig", b.graph.zig_exe });
    repair_study.setCwd(b.path("."));
    test_step.dependOn(&repair_study.step);
    const repair_step = b.step("test-repair-study", "Verify repair-study fixtures and retained evidence");
    repair_step.dependOn(&repair_study.step);
    guardian.addAllChecks(b, guardian_exe, repair_step, .{});
    const qbe_step = b.step("test-qbe", "Run QBE native compilation, runtime, and object-cache acceptance");
    const qbe_tool: std.Build.LazyPath = if (b.option([]const u8, "qbe", "QBE executable for optional acceptance (default: the vendored QBE this project builds)")) |path|
        .{ .cwd_relative = path }
    else
        qbe_exe.getEmittedBin();
    const native_test_step = b.step("test-native-tests", "Verify native guest test discovery, execution, fixtures, and affected-test reuse");
    const native_test_cli = b.addSystemCommand(&.{ "python3", "tests/native_test_cli.py", "--compiler" });
    native_test_cli.addFileArg(exe.getEmittedBin());
    native_test_cli.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    native_test_cli.addFileArg(qbe_tool);
    native_test_cli.setCwd(b.path("."));
    native_test_step.dependOn(&native_test_cli.step);
    const native_test_execution = b.addSystemCommand(&.{ "python3", "tests/native_test_execution.py", "--compiler" });
    native_test_execution.addFileArg(exe.getEmittedBin());
    native_test_execution.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    native_test_execution.addFileArg(qbe_tool);
    native_test_execution.setCwd(b.path("."));
    native_test_step.dependOn(&native_test_execution.step);
    const native_test_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/native_test_cli_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    native_test_unit.root_module.addImport("qbe_build_assets", build_assets);
    guardian.enableTestDiagnostics(native_test_unit.root_module);
    native_test_step.dependOn(&b.addRunArtifact(native_test_unit).step);
    compile_tests.dependOn(&native_test_unit.step);
    guardian.addAllChecks(b, guardian_exe, native_test_step, .{});
    qbe_step.dependOn(native_test_step);
    const ffi_step = b.step("test-c-ffi", "Verify direct C scalar imports and native library linking");
    const ffi_cli = b.addSystemCommand(&.{ "python3", "tests/qbe_c_ffi.py", "--compiler" });
    ffi_cli.addFileArg(exe.getEmittedBin());
    ffi_cli.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    ffi_cli.addFileArg(qbe_tool);
    ffi_cli.setCwd(b.path("."));
    ffi_step.dependOn(&ffi_cli.step);
    const ffi_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/c_abi_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    guardian.enableTestDiagnostics(ffi_unit.root_module);
    ffi_step.dependOn(&b.addRunArtifact(ffi_unit).step);
    compile_tests.dependOn(&ffi_unit.step);
    guardian.addAllChecks(b, guardian_exe, ffi_step, .{});
    qbe_step.dependOn(ffi_step);
    const qbe_build_step = b.step("test-qbe-build", "Verify native builds without Python and native adapter generation");
    const qbe_build_cli = b.addSystemCommand(&.{ "python3", "tests/qbe_build_cli.py", "--compiler" });
    qbe_build_cli.addFileArg(exe.getEmittedBin());
    qbe_build_cli.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_build_cli.addFileArg(qbe_tool);
    qbe_build_cli.setCwd(b.path("."));
    qbe_build_step.dependOn(&qbe_build_cli.step);
    qbe_step.dependOn(qbe_build_step);
    const qbe_build_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/qbe_build_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    qbe_build_unit.root_module.addImport("qbe_build_assets", build_assets);
    guardian.enableTestDiagnostics(qbe_build_unit.root_module);
    qbe_build_step.dependOn(&b.addRunArtifact(qbe_build_unit).step);
    compile_tests.dependOn(&qbe_build_unit.step);
    guardian.addAllChecks(b, guardian_exe, qbe_build_step, .{});
    const qbe_tests = b.addSystemCommand(&.{ "python3", "tests/qbe_builder.py", "--compiler" });
    qbe_tests.addFileArg(exe.getEmittedBin());
    qbe_tests.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_tests.addFileArg(qbe_tool);
    qbe_tests.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_tests.step);
    const qbe_parity = b.addSystemCommand(&.{ "python3", "tests/qbe_parity.py", "--compiler" });
    qbe_parity.addFileArg(exe.getEmittedBin());
    qbe_parity.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_parity.addFileArg(qbe_tool);
    qbe_parity.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_parity.step);
    const qbe_corpus = b.addSystemCommand(&.{ "python3", "tests/qbe_native_cases.py", "--compiler" });
    qbe_corpus.addFileArg(exe.getEmittedBin());
    qbe_corpus.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_corpus.addFileArg(qbe_tool);
    qbe_corpus.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_corpus.step);
    const qbe_runtime = b.addSystemCommand(&.{ "python3", "tests/qbe_runtime.py", "--zig", b.graph.zig_exe });
    qbe_runtime.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_runtime.step);
    const qbe_embed = b.addSystemCommand(&.{ "python3", "tests/qbe_embed.py", "--zig", b.graph.zig_exe });
    qbe_embed.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_embed.step);
    const qbe_wire = b.addSystemCommand(&.{ "python3", "tests/qbe_wire.py", "--zig", b.graph.zig_exe });
    qbe_wire.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_wire.step);
    const qbe_calls = b.addSystemCommand(&.{ "python3", "tests/qbe_native_calls.py", "--compiler" });
    qbe_calls.addFileArg(exe.getEmittedBin());
    qbe_calls.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_calls.addFileArg(qbe_tool);
    qbe_calls.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_calls.step);
    const qbe_managed = b.addSystemCommand(&.{ "python3", "tests/qbe_managed.py", "--compiler" });
    qbe_managed.addFileArg(exe.getEmittedBin());
    qbe_managed.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_managed.addFileArg(qbe_tool);
    qbe_managed.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_managed.step);
    const qbe_files = b.addSystemCommand(&.{ "python3", "tests/qbe_files.py", "--compiler" });
    qbe_files.addFileArg(exe.getEmittedBin());
    qbe_files.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_files.addFileArg(qbe_tool);
    qbe_files.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_files.step);
    const qbe_documents = b.addSystemCommand(&.{ "python3", "tests/qbe_docs.py", "--compiler" });
    qbe_documents.addFileArg(exe.getEmittedBin());
    qbe_documents.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_documents.addFileArg(qbe_tool);
    qbe_documents.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_documents.step);
    const qbe_output = b.addSystemCommand(&.{ "python3", "tests/qbe_io.py", "--compiler" });
    qbe_output.addFileArg(exe.getEmittedBin());
    qbe_output.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_output.addFileArg(qbe_tool);
    qbe_output.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_output.step);
    const qbe_arena = b.addSystemCommand(&.{ "python3", "tests/qbe_arena.py", "--compiler" });
    qbe_arena.addFileArg(exe.getEmittedBin());
    qbe_arena.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_arena.addFileArg(qbe_tool);
    qbe_arena.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_arena.step);
    const qbe_bytes = b.addSystemCommand(&.{ "python3", "tests/qbe_bytes.py", "--compiler" });
    qbe_bytes.addFileArg(exe.getEmittedBin());
    qbe_bytes.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_bytes.addFileArg(qbe_tool);
    qbe_bytes.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_bytes.step);
    const qbe_text = b.addSystemCommand(&.{ "python3", "tests/qbe_text.py", "--compiler" });
    qbe_text.addFileArg(exe.getEmittedBin());
    qbe_text.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_text.addFileArg(qbe_tool);
    qbe_text.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_text.step);
    const qbe_providers = b.addSystemCommand(&.{ "python3", "tests/qbe_provider_parity.py", "--compiler" });
    qbe_providers.addFileArg(exe.getEmittedBin());
    qbe_providers.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_providers.addFileArg(qbe_tool);
    qbe_providers.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_providers.step);
    const qbe_resources = b.addSystemCommand(&.{ "python3", "tests/qbe_resource_parity.py", "--compiler" });
    qbe_resources.addFileArg(exe.getEmittedBin());
    qbe_resources.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_resources.addFileArg(qbe_tool);
    qbe_resources.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_resources.step);
    const qbe_host = b.addSystemCommand(&.{ "python3", "tests/qbe_host.py", "--compiler" });
    qbe_host.addFileArg(exe.getEmittedBin());
    qbe_host.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_host.addFileArg(qbe_tool);
    qbe_host.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_host.step);
    const qbe_host_runtime = b.addSystemCommand(&.{ "python3", "tests/qbe_host_runtime.py" });
    qbe_host_runtime.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_host_runtime.step);
    const qbe_codecs = b.addSystemCommand(&.{ "python3", "tests/qbe_codecs.py", "--compiler" });
    qbe_codecs.addFileArg(exe.getEmittedBin());
    qbe_codecs.addArgs(&.{ "--zig", b.graph.zig_exe, "--qbe" });
    qbe_codecs.addFileArg(qbe_tool);
    qbe_codecs.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_codecs.step);
    const qbe_memory = b.addSystemCommand(&.{ "python3", "scripts/test_native_memory.py" });
    qbe_memory.setCwd(b.path("."));
    qbe_step.dependOn(&qbe_memory.step);
    guardian.addAllChecks(b, guardian_exe, qbe_step, .{});
    const duplicate_scaling = b.addSystemCommand(&.{ "python3", "tests/duplicate_scaling.py", "--compiler" });
    duplicate_scaling.addFileArg(exe.getEmittedBin());
    duplicate_scaling.setCwd(b.path("."));
    test_step.dependOn(&duplicate_scaling.step);
    const module_scaling = b.addSystemCommand(&.{ "python3", "tests/module_scaling.py", "--compiler" });
    module_scaling.addFileArg(exe.getEmittedBin());
    module_scaling.setCwd(b.path("."));
    test_step.dependOn(&module_scaling.step);
    const evaluation_reports = b.addSystemCommand(&.{ "python3", "tests/evaluation_reports.py", "--compiler" });
    evaluation_reports.addFileArg(exe.getEmittedBin());
    evaluation_reports.setCwd(b.path("."));
    test_step.dependOn(&evaluation_reports.step);
    const evaluation_cache = b.addSystemCommand(&.{ "python3", "tests/evaluation_cache.py", "--compiler" });
    evaluation_cache.addFileArg(exe.getEmittedBin());
    evaluation_cache.setCwd(b.path("."));
    test_step.dependOn(&evaluation_cache.step);
    const input_manifests = b.addSystemCommand(&.{ "python3", "tests/input_manifests.py", "--compiler" });
    input_manifests.addFileArg(exe.getEmittedBin());
    input_manifests.setCwd(b.path("."));
    test_step.dependOn(&input_manifests.step);
    const law_tests = b.addSystemCommand(&.{ "python3", "tests/laws.py", "--compiler" });
    law_tests.addFileArg(exe.getEmittedBin());
    law_tests.setCwd(b.path("."));
    test_step.dependOn(&law_tests.step);
    const package_tests = b.addSystemCommand(&.{ "python3", "tests/packages.py", "--compiler" });
    package_tests.addFileArg(exe.getEmittedBin());
    package_tests.setCwd(b.path("."));
    test_step.dependOn(&package_tests.step);
    const guest_tests = b.addSystemCommand(&.{ "python3", "tests/guest_tests.py", "--compiler" });
    guest_tests.addFileArg(exe.getEmittedBin());
    guest_tests.setCwd(b.path("."));
    test_step.dependOn(&guest_tests.step);
    const navigation_tests = b.addSystemCommand(&.{ "python3", "tests/navigation_client.py", "--compiler" });
    navigation_tests.addFileArg(exe.getEmittedBin());
    navigation_tests.setCwd(b.path("."));
    test_step.dependOn(&navigation_tests.step);
    const declaration_listing = b.addSystemCommand(&.{ "python3", "tests/list_declarations.py", "--compiler" });
    declaration_listing.addFileArg(exe.getEmittedBin());
    declaration_listing.setCwd(b.path("."));
    test_step.dependOn(&declaration_listing.step);
    const project_workflow = b.addSystemCommand(&.{ "python3", "tests/project_workflow.py", "--compiler" });
    project_workflow.addFileArg(exe.getEmittedBin());
    project_workflow.setCwd(b.path("."));
    test_step.dependOn(&project_workflow.step);
    const contract_tests = b.addSystemCommand(&.{ "python3", "tests/contract_runner.py", "--runner" });
    contract_tests.addFileArg(byte_io_runner.getEmittedBin());
    contract_tests.setCwd(b.path("."));
    test_step.dependOn(&contract_tests.step);
    const reference_tests = b.addSystemCommand(&.{ "python3", "tests/reference_tool.py", "--compiler" });
    reference_tests.addFileArg(exe.getEmittedBin());
    reference_tests.setCwd(b.path("."));
    test_step.dependOn(&reference_tests.step);
    const agent_tools = b.step("test-agent-tools", "Verify compact feedback, byte-contract fixtures, and compiler-pinned references");
    agent_tools.dependOn(&project_workflow.step);
    agent_tools.dependOn(&contract_tests.step);
    agent_tools.dependOn(&reference_tests.step);
    const agent_tools_integration = b.addSystemCommand(&.{ "python3", "tests/agent_tools_integration.py", "--compiler" });
    agent_tools_integration.addFileArg(exe.getEmittedBin());
    agent_tools_integration.addArg("--runner");
    agent_tools_integration.addFileArg(byte_io_runner.getEmittedBin());
    agent_tools_integration.setCwd(b.path("."));
    agent_tools.dependOn(&agent_tools_integration.step);
    test_step.dependOn(&agent_tools_integration.step);
    guardian.addAllChecks(b, guardian_exe, agent_tools, .{});
    const schemas = b.addSystemCommand(&.{ "python3", "tests/schemas.py", "--compiler" });
    schemas.addFileArg(exe.getEmittedBin());
    schemas.setCwd(b.path("."));
    test_step.dependOn(&schemas.step);
    const typed_json = b.addSystemCommand(&.{ "python3", "tests/typed_json.py", "--compiler" });
    typed_json.addFileArg(exe.getEmittedBin());
    typed_json.setCwd(b.path("."));
    test_step.dependOn(&typed_json.step);
    const python_bindings = b.addSystemCommand(&.{ "python3", "tests/python_bindings.py", "--compiler" });
    python_bindings.addFileArg(exe.getEmittedBin());
    python_bindings.setCwd(b.path("."));
    test_step.dependOn(&python_bindings.step);
    const python_calls = b.addSystemCommand(&.{ "python3", "tests/python_calls.py", "--compiler" });
    python_calls.addFileArg(exe.getEmittedBin());
    python_calls.setCwd(b.path("."));
    test_step.dependOn(&python_calls.step);
    const call_inputs = b.addSystemCommand(&.{ "python3", "tests/call_inputs.py", "--compiler" });
    call_inputs.addFileArg(exe.getEmittedBin());
    call_inputs.setCwd(b.path("."));
    test_step.dependOn(&call_inputs.step);
    const diagnostic_output = b.addSystemCommand(&.{ "python3", "tests/diagnostic_output.py", "--compiler" });
    diagnostic_output.addFileArg(exe.getEmittedBin());
    diagnostic_output.setCwd(b.path("."));
    test_step.dependOn(&diagnostic_output.step);
    const check_session = b.addSystemCommand(&.{ "python3", "tests/check_session.py", "--compiler" });
    check_session.addFileArg(exe.getEmittedBin());
    check_session.setCwd(b.path("."));
    test_step.dependOn(&check_session.step);
    const watch = b.addSystemCommand(&.{ "python3", "tests/watch.py", "--compiler" });
    watch.addFileArg(exe.getEmittedBin());
    watch.setCwd(b.path("."));
    test_step.dependOn(&watch.step);
    const binding_cache = b.addSystemCommand(&.{ "python3", "tests/binding_cache.py", "--compiler" });
    binding_cache.addFileArg(exe.getEmittedBin());
    binding_cache.setCwd(b.path("."));
    test_step.dependOn(&binding_cache.step);
    const corpus_review = b.addSystemCommand(&.{ "python3", "tests/corpus_review.py", "--compiler" });
    corpus_review.addFileArg(exe.getEmittedBin());
    corpus_review.setCwd(b.path("."));
    test_step.dependOn(&corpus_review.step);
    const schema_reports = b.addSystemCommand(&.{ "python3", "tests/schema_reports.py", "--compiler" });
    schema_reports.addFileArg(exe.getEmittedBin());
    schema_reports.setCwd(b.path("."));
    test_step.dependOn(&schema_reports.step);
    const calls = b.addSystemCommand(&.{ "python3", "tests/call_json.py", "--compiler" });
    calls.addFileArg(exe.getEmittedBin());
    calls.setCwd(b.path("."));
    test_step.dependOn(&calls.step);
    const docs_examples = b.addSystemCommand(&.{ "python3", "tests/docs_examples.py", "--compiler" });
    docs_examples.addFileArg(exe.getEmittedBin());
    docs_examples.setCwd(b.path("."));
    b.step("test-docs", "Execute every fenced documentation example").dependOn(&docs_examples.step);
    test_step.dependOn(&docs_examples.step);
    const doc_coverage = b.addRunArtifact(exe);
    doc_coverage.addArgs(&.{ "doc-coverage", "." });
    doc_coverage.setCwd(b.path("."));
    doc_coverage.has_side_effects = true;
    b.step("test-doc-coverage", "Require a documented example for every feature and standard export").dependOn(&doc_coverage.step);
    test_step.dependOn(&doc_coverage.step);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests"), b.path("test") }, .check = true });
    b.step("fmt-check", "Check canonical Zig formatting").dependOn(&fmt.step);
}
