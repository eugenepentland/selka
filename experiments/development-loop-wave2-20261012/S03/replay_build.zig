//! Minimal artifact replay of existing test recipes; never builds a compiler.
const std = @import("std");
const guardian = @import("guardian");

/// Replay the existing native test recipe with frozen compiler options.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const kind = b.option([]const u8, "kind", "scalar, units-root, all-units or golden") orelse "scalar";
    const compiler = b.option([]const u8, "compiler", "Authenticated frozen compiler") orelse @panic("compiler required");
    const baseline = b.option(bool, "baseline", "Broad C0 root") orelse false;
    const golden = std.mem.eql(u8, kind, "golden");
    const all_units = std.mem.eql(u8, kind, "all-units");
    const units_root = all_units or std.mem.eql(u8, kind, "units-root");
    const filters: []const []const u8 = if (units_root) &.{} else if (golden) &[_][]const u8{"checked-in golden corpora replay natively with explicit skip counts"} else &[_][]const u8{
        "every shared vector answers the pinned grammar's value",
        "the grammar keeps the rounding horizon, the signed bound and the exponent bound",
        "every shared vector answers the same through the UTF-8 octet entry points",
        "float format specifications render every CPython oracle row exactly",
        "integer and text format specifications render every CPython oracle row exactly",
        "round to n digits rounds the exact binary value with ties away from zero",
        "a specification the value family cannot take is rejected with CPython's reason",
        "a packed specification survives the runtime word unchanged",
    };
    const module = b.createModule(.{
        .root_source_file = b.path(if (golden) "test/golden_parity.zig" else if (baseline or units_root) "src/root_test.zig" else "src/text_scalar_root_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dependency = b.dependency("guardian", .{ .target = target, .optimize = optimize });
    const tests = b.addTest(.{ .name = "s03-replayed-tests", .root_module = module, .filters = filters, .test_runner = guardian.testRunner(dependency) });
    guardian.enableTestDiagnostics(module);
    const options = b.addOptions();
    options.addOption([]const u8, "compiler_path", compiler);
    options.addOption([]const u8, "zig_path", b.graph.zig_exe);
    if (golden) {
        module.addOptions("test_options", options);
    } else if (baseline or units_root) {
        options.addOption([]const u8, "cache_directory", ".mylang-cache/unit-tests");
        module.addOptions("native_test_options", options);
        module.addImport("compiler_root", module);
        module.addImport("memory_budget", b.createModule(.{ .root_source_file = b.path("src/memory_budget.zig"), .target = target, .optimize = optimize }));
        module.addImport("build_identity", @import("build_identity.zig").module(b, target, optimize, .{ .compile = 1 << 30, .run = 1 << 30 }));
        const docs = @import("src/user_docs.zig");
        for (docs.topics) |topic| module.addAnonymousImport(b.fmt("{s}{s}", .{ docs.import_prefix, topic.name }), .{ .root_source_file = b.path(topic.path) });
    }
    const install = b.addInstallArtifact(tests, .{});
    const preparation = b.step("prepare", "Compile and link exactly selected existing tests");
    preparation.dependOn(&install.step);
    if (all_units and !baseline) {
        const scalar_module = b.createModule(.{ .root_source_file = b.path("src/text_scalar_root_test.zig"), .target = target, .optimize = optimize });
        const scalar_tests = b.addTest(.{ .name = "s03-replayed-scalar", .root_module = scalar_module, .test_runner = guardian.testRunner(dependency) });
        guardian.enableTestDiagnostics(scalar_module);
        preparation.dependOn(&b.addInstallArtifact(scalar_tests, .{}).step);
    }
    const run = b.addRunArtifact(tests);
    for (filters) |filter| run.addArg(b.fmt("--guardian-filter={s}", .{filter}));
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    b.step("check", "Execute exactly selected tests").dependOn(&run.step);
}
