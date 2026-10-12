//! Bounded live native cohort using the production inventory and producer writer.
const std = @import("std");
const verification = @import("build_verification.zig");
const inputs = @import("build_test_inputs.zig");
const support = @import("support.zig");

/// Register real scalar/tooling tests and live fixture-membership assertions.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const rerun = b.option(bool, "test-rerun", "Execute selected actions freshly") orelse false;
    var registry: verification.Registry = .{ .build = b, .controls = .{ .rerun = rerun, .optimize = @tagName(optimize) } };
    const scalar = unit(b, "scalar-live-tests", "src/text_scalar_root_test.zig", target, optimize);
    const tooling = unit(b, "tooling-live-tests", "src/tooling_root_test.zig", target, optimize);
    const scalar_run = b.addRunArtifact(scalar);
    scalar_run.has_side_effects = rerun;
    registry.declared(&scalar_run.step, "text_scalar_unit");
    registry.artifactDependencies("text_scalar_unit", &.{"text-scalar-units"});
    const tooling_run = b.addRunArtifact(tooling);
    tooling_run.has_side_effects = rerun;
    registry.declared(&tooling_run.step, "tooling_unit");
    registry.artifactDependencies("tooling_unit", &.{"tooling-units"});
    const members = b.addSystemCommand(&.{"python3"});
    members.addFileArg(b.path("scripts/verification_telemetry.py"));
    members.addArgs(&.{ "--action-id", "fixtures", "--member", "0", "--output-directory-env", "MYLANG_TEST_TELEMETRY_DIR", "membership_cases" });
    members.addFileInput(b.path("scripts/membership_cases.py"));
    members.setCwd(b.path("scripts"));
    members.has_side_effects = true;
    registry.declared(&members.step, "fixtures");
    registry.artifactDependencies("fixtures", &.{});
    const test_step = b.step("test", "Complete this bounded native/fixture cohort");
    test_step.dependOn(&scalar_run.step);
    test_step.dependOn(&tooling_run.step);
    test_step.dependOn(&members.step);
    const fmt = b.addFmt(.{ .paths = &.{ b.path("src"), b.path("build.zig"), b.path("build_verification.zig"), b.path("build_test_inputs.zig"), b.path("support.zig") }, .check = true });
    registry.register("format", &fmt.step, &inputs.format, true, "exact source formatting inputs");
    registry.artifactDependencies("format", &.{});
    const fmt_step = b.step("fmt-check", "Check the bounded cohort's Zig sources");
    fmt_step.dependOn(&fmt.step);

    const prepare = b.step("verification-prepare", "Prepare real native providers and immutable support artifacts");
    const writer = b.addSystemCommand(&.{"python3"});
    writer.addFileArg(b.path("scripts/verification_artifacts.py"));
    writer.setCwd(b.path("."));
    writer.addFileInput(b.path("scripts/verification_producers.py"));
    writer.addFileInput(b.path("scripts/verification_snapshot.py"));
    const manifest = writer.addOutputFileArg("artifacts.json");
    writer.addArgs(&.{ "--qualify", "text-scalar-units", @tagName(optimize), "--qualify", "tooling-units", @tagName(optimize) });
    for (inputs.text_scalar_unit) |path| writer.addFileInput(b.path(path));
    for (inputs.tooling_unit) |path| writer.addFileInput(b.path(path));
    writer.addArg("text-scalar-units");
    writer.addFileArg(scalar.getEmittedBin());
    writer.addArg("tooling-units");
    writer.addFileArg(tooling.getEmittedBin());
    inline for (.{ "mylang", "units", "cli", "core" }) |label| {
        writer.addArg(label);
        writer.addFileArg(.{ .cwd_relative = @field(support, label) });
    }
    const installed = b.addInstallFileWithDir(manifest, .{ .custom = "verification" }, "artifacts.json");
    prepare.dependOn(&installed.step);
    const compiler = b.addInstallFileWithDir(.{ .cwd_relative = support.mylang }, .bin, "mylang");
    prepare.dependOn(&compiler.step);
    inline for (support.components) |component| {
        const file = b.addInstallFileWithDir(.{ .cwd_relative = component.source }, .{ .custom = "libexec/mylang/components" }, component.name);
        prepare.dependOn(&file.step);
    }
    registry.exportPlan(&.{ test_step, fmt_step }, &.{ &scalar.step, &tooling.step });
}

fn unit(b: *std.Build, name: []const u8, root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const compiled = b.addTest(.{
        .name = name,
        .max_rss = 2147483648,
        .test_runner = .{ .path = .{ .cwd_relative = "../guardian-zig/src/test_runner.zig" }, .mode = .server },
        .root_module = b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize, .error_tracing = true }),
    });
    return compiled;
}
