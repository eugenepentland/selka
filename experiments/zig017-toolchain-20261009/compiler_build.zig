//! Isolated compiler-only comparison: mirrors the production module graph.
//! No seed provisioning, installed package, Guardian or project version-pin changes.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{});
    const optimize = b.standardOptimizeOption(.{});
    const llvm = b.option(bool, "llvm", "Force the LLVM or self-hosted backend") orelse false;
    const budget = b.createModule(.{ .root_source_file = b.path("src/memory_budget.zig"), .target = target, .optimize = optimize });
    const language = b.createModule(.{ .root_source_file = b.path("src/compiler.zig"), .target = target, .optimize = optimize });
    language.addImport("memory_budget", budget);
    const exe = b.addExecutable(.{ .name = "mylang", .use_llvm = llvm, .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize,
        .imports = &.{ .{ .name = "mylang", .module = language }, .{ .name = "memory_budget", .module = budget } },
    }) });
    exe.root_module.addImport("compiler_root", exe.root_module);
    const docs = @import("src/user_docs.zig");
    for (docs.topics) |topic| exe.root_module.addAnonymousImport(b.fmt("{s}{s}", .{ docs.import_prefix, topic.name }), .{ .root_source_file = b.path(topic.path) });
    const identity = @import("build_identity.zig").module(b, target, optimize, .{ .compile = 2 << 30, .run = 1 << 30 });
    exe.root_module.addImport("build_identity", identity);
    const platform = b.createModule(.{ .root_source_file = b.path("src/config_core_tool_platform.zig") });
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/cli.zig"), .target = target, .optimize = optimize,
        .imports = &.{ .{ .name = "mylang", .module = language }, .{ .name = "core_tool_platform", .module = platform }, .{ .name = "build_identity", .module = identity }, .{ .name = "memory_budget", .module = budget } },
    });
    const number_text = b.addObject(.{ .name = "core_number_text", .use_llvm = false, .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/runtime/core_number_text.zig"),
        .target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux-gnu.2.31", .cpu_features = "baseline" }) catch @panic("number-text target")),
        .optimize = .ReleaseFast, .pic = true, .stack_check = false, .stack_protector = false, .link_libc = true,
    }) });
    core.addAnonymousImport("core_number_text_object", .{ .root_source_file = number_text.getEmittedBin() });
    exe.root_module.addImport("mylang_core", core);
    b.installArtifact(exe);
}
