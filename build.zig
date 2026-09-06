const std = @import("std");
const builtin = @import("builtin");
const guardian = @import("guardian");

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.0-dev.1683+5ceec001b"))
        @panic("mylang requires Guardian's Zig 0.17.0-dev.1683+5ceec001b toolchain (see .zigversion)");
    const target = b.resolveTargetQuery(.{});
    const optimize = b.standardOptimizeOption(.{});
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
    b.installArtifact(exe);
    const guardian_dep = b.dependency("guardian", .{ .target = target, .optimize = optimize });
    const guardian_exe = guardian_dep.artifact("guardian-check");
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/root_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const board_module = b.createModule(.{
        .root_source_file = b.path("src/board_trial/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    });
    const board_runner = b.addExecutable(.{ .name = "board-trial", .root_module = board_module });
    b.installArtifact(board_runner);
    guardian.addAllChecks(b, guardian_exe, b.getInstallStep(), .{});
    const board_unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/board_trial/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "mylang", .module = core }},
    }) });
    guardian.enableTestDiagnostics(board_unit.root_module);
    const options = b.addOptions();
    options.addOptionPath("compiler_path", exe.getEmittedBin());
    const integration = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
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
    compile_tests.dependOn(&integration.step);
    const run_integration = b.addRunArtifact(integration);
    const test_step = b.step("test", "Run interpreter, checker, CLI, and tooling regression tests");
    b.step("test-interpreter", "Run the default interpreter acceptance suite").dependOn(test_step);
    const native_step = b.step("test-native", "Run optional native compilation and parity integration tests");
    guardian.addAllChecks(b, guardian_exe, native_step, .{});
    const all_tests = b.step("test-all", "Run interpreter and native acceptance suites");
    all_tests.dependOn(test_step);
    all_tests.dependOn(native_step);
    guardian.addAllChecks(b, guardian_exe, test_step, .{});
    test_step.dependOn(&b.addRunArtifact(unit).step);
    test_step.dependOn(&run_integration.step);
    test_step.dependOn(&b.addRunArtifact(board_unit).step);
    const board_runtime = b.addSystemCommand(&.{ "python3", "tests/board_trial.py", "--runner" });
    board_runtime.addFileArg(board_runner.getEmittedBin());
    board_runtime.addArg("--compiler");
    board_runtime.addFileArg(exe.getEmittedBin());
    board_runtime.setCwd(b.path("."));
    test_step.dependOn(&board_runtime.step);
    const driver_tests = b.addSystemCommand(&.{ "python3", "-m", "unittest", "discover", "-s", "tests/verification", "-p", "test_driver.py" });
    driver_tests.setCwd(b.path("."));
    test_step.dependOn(&driver_tests.step);
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
    const python_native = b.addSystemCommand(&.{ "python3", "tests/python_native_calls.py", "--compiler" });
    python_native.addFileArg(exe.getEmittedBin());
    python_native.addArgs(&.{ "--zig", b.graph.zig_exe });
    python_native.setCwd(b.path("."));
    native_step.dependOn(&python_native.step);
    const native_codec = b.addSystemCommand(&.{ "python3", "tests/native_codec_dispatch.py", "--compiler" });
    native_codec.addFileArg(exe.getEmittedBin());
    native_codec.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_codec.setCwd(b.path("."));
    native_step.dependOn(&native_codec.step);
    const codec_wire = b.addSystemCommand(&.{ "python3", "tests/native_codec_wire.py", "--compiler" });
    codec_wire.addFileArg(exe.getEmittedBin());
    codec_wire.addArgs(&.{ "--zig", b.graph.zig_exe });
    codec_wire.setCwd(b.path("."));
    native_step.dependOn(&codec_wire.step);
    const native_schema = b.addSystemCommand(&.{ "python3", "tests/native_schema.py", "--compiler" });
    native_schema.addFileArg(exe.getEmittedBin());
    native_schema.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_schema.setCwd(b.path("."));
    native_step.dependOn(&native_schema.step);
    const native_wire = b.addSystemCommand(&.{ "python3", "tests/native_wire.py", "--compiler" });
    native_wire.addFileArg(exe.getEmittedBin());
    native_wire.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_wire.setCwd(b.path("."));
    native_step.dependOn(&native_wire.step);
    const native_calls = b.addSystemCommand(&.{ "python3", "tests/native_calls.py", "--compiler" });
    native_calls.addFileArg(exe.getEmittedBin());
    native_calls.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_calls.setCwd(b.path("."));
    native_step.dependOn(&native_calls.step);
    const embedding_tests = b.addSystemCommand(&.{ "python3", "tests/native_embedding.py", "--compiler" });
    embedding_tests.addFileArg(exe.getEmittedBin());
    embedding_tests.addArgs(&.{ "--zig", b.graph.zig_exe });
    embedding_tests.setCwd(b.path("."));
    native_step.dependOn(&embedding_tests.step);
    const native_tests = b.addSystemCommand(&.{ "python3", "tests/native_cases.py", "--compiler" });
    native_tests.addFileArg(exe.getEmittedBin());
    native_tests.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_tests.setCwd(b.path("."));
    native_step.dependOn(&native_tests.step);
    const native_memory = b.addSystemCommand(&.{ "python3", "tests/native_memory.py", "--compiler" });
    native_memory.addFileArg(exe.getEmittedBin());
    native_memory.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_memory.setCwd(b.path("."));
    native_step.dependOn(&native_memory.step);
    const native_providers = b.addSystemCommand(&.{ "python3", "tests/native_providers.py", "--compiler" });
    native_providers.addFileArg(exe.getEmittedBin());
    native_providers.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_providers.setCwd(b.path("."));
    native_step.dependOn(&native_providers.step);
    const native_environment = b.addSystemCommand(&.{ "python3", "tests/native_environment.py", "--compiler" });
    native_environment.addFileArg(exe.getEmittedBin());
    native_environment.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_environment.setCwd(b.path("."));
    native_step.dependOn(&native_environment.step);
    const native_resources = b.addSystemCommand(&.{ "python3", "tests/native_resources.py", "--compiler" });
    native_resources.addFileArg(exe.getEmittedBin());
    native_resources.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_resources.setCwd(b.path("."));
    native_step.dependOn(&native_resources.step);
    const native_builder = b.addSystemCommand(&.{ "python3", "tests/native_builder.py", "--compiler" });
    native_builder.addFileArg(exe.getEmittedBin());
    native_builder.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_builder.setCwd(b.path("."));
    native_step.dependOn(&native_builder.step);
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
    const native_corpus = b.addSystemCommand(&.{ "python3", "tests/corpus_review.py", "--compiler" });
    native_corpus.addFileArg(exe.getEmittedBin());
    native_corpus.addArgs(&.{ "--native", "--zig", b.graph.zig_exe });
    native_corpus.setCwd(b.path("."));
    native_step.dependOn(&native_corpus.step);
    const schema_reports = b.addSystemCommand(&.{ "python3", "tests/schema_reports.py", "--compiler" });
    schema_reports.addFileArg(exe.getEmittedBin());
    schema_reports.setCwd(b.path("."));
    test_step.dependOn(&schema_reports.step);
    const calls = b.addSystemCommand(&.{ "python3", "tests/call_json.py", "--compiler" });
    calls.addFileArg(exe.getEmittedBin());
    calls.setCwd(b.path("."));
    test_step.dependOn(&calls.step);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests"), b.path("test") }, .check = true });
    b.step("fmt-check", "Check canonical Zig formatting").dependOn(&fmt.step);
}
