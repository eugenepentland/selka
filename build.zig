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
    guardian.addAllChecks(b, guardian_exe, b.getInstallStep(), .{});
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Check, run, or inspect a source program").dependOn(&run.step);

    const unit = b.addTest(.{ .test_runner = guardian.testRunner(guardian_dep), .root_module = b.createModule(.{
        .root_source_file = b.path("src/root_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
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
    compile_tests.dependOn(&integration.step);
    const run_integration = b.addRunArtifact(integration);
    const test_step = b.step("test", "Run semantic and actual-CLI regression tests");
    guardian.addAllChecks(b, guardian_exe, test_step, .{});
    test_step.dependOn(&b.addRunArtifact(unit).step);
    test_step.dependOn(&run_integration.step);
    const driver_tests = b.addSystemCommand(&.{ "python3", "-m", "unittest", "discover", "-s", "tests/verification", "-p", "test_driver.py" });
    driver_tests.setCwd(b.path("."));
    test_step.dependOn(&driver_tests.step);
    const native_tests = b.addSystemCommand(&.{ "python3", "tests/native_cases.py", "--compiler" });
    native_tests.addFileArg(exe.getEmittedBin());
    native_tests.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_tests.setCwd(b.path("."));
    test_step.dependOn(&native_tests.step);
    const native_memory = b.addSystemCommand(&.{ "python3", "tests/native_memory.py", "--compiler" });
    native_memory.addFileArg(exe.getEmittedBin());
    native_memory.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_memory.setCwd(b.path("."));
    test_step.dependOn(&native_memory.step);
    const native_providers = b.addSystemCommand(&.{ "python3", "tests/native_providers.py", "--compiler" });
    native_providers.addFileArg(exe.getEmittedBin());
    native_providers.addArgs(&.{ "--zig", b.graph.zig_exe });
    native_providers.setCwd(b.path("."));
    test_step.dependOn(&native_providers.step);
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
    const check_session = b.addSystemCommand(&.{ "python3", "tests/check_session.py", "--compiler" });
    check_session.addFileArg(exe.getEmittedBin());
    check_session.setCwd(b.path("."));
    test_step.dependOn(&check_session.step);
    const binding_cache = b.addSystemCommand(&.{ "python3", "tests/binding_cache.py", "--compiler" });
    binding_cache.addFileArg(exe.getEmittedBin());
    binding_cache.setCwd(b.path("."));
    test_step.dependOn(&binding_cache.step);
    const corpus_review = b.addSystemCommand(&.{ "python3", "tests/corpus_review.py", "--compiler" });
    corpus_review.addFileArg(exe.getEmittedBin());
    corpus_review.addArgs(&.{ "--zig", b.graph.zig_exe });
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
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("src"), b.path("tests"), b.path("test") }, .check = true });
    b.step("fmt-check", "Check canonical Zig formatting").dependOn(&fmt.step);
}
