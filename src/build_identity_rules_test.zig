//! The build-time identities' source selection and digest (`build_identity_rules.zig`),
//! exercised on synthetic in-memory sources.
const std = @import("std");
const rules = @import("build_identity_rules.zig");

const toolchain: rules.Toolchain = .{ .zig_version = "0.0.0-test", .optimize = "Debug" };

/// Both identities of one synthetic tree.
const Digests = struct { compiler: [64]u8, runner: [64]u8 };

/// Both identities over a synthetic tree of a front-end file, an emitter file and
/// two runner files, the front-end file holding `parser` and the trial executor
/// holding `runner`.
fn digests(a: std.mem.Allocator, parser: []const u8, runner: []const u8) !Digests {
    var sources: rules.Sources = .empty;
    try sources.put(a, "parser.zig", parser);
    try sources.put(a, "core/emit_llvm.zig", "pub const emit = 1;\n");
    try sources.put(a, "core/test_runner_execute.zig", runner);
    try sources.put(a, "memory_budget.zig", "pub const limit = 4;\n");
    const all = try rules.sortedPaths(a, sources, null);
    const covered = try rules.sortedPaths(a, sources, &rules.isRunnerSource);
    return .{
        .compiler = try rules.digest(a, rules.compiler_domain, toolchain, sources, all),
        .runner = try rules.digest(a, rules.runner_domain, toolchain, sources, covered),
    };
}

const parser_text = "pub const parsed = true;\n";
const runner_text = "pub const trials = 1;\n";

// spec: RUNNER-IDENTITY-1
test "build_identity: front-end and emitter sources are not runner sources" {
    try std.testing.expect(!rules.isRunnerSource("parser.zig"));
    try std.testing.expect(!rules.isRunnerSource("sema.zig"));
    try std.testing.expect(!rules.isRunnerSource("core/emit_llvm.zig"));
    try std.testing.expect(!rules.isRunnerSource("core/frontend.zig"));
    try std.testing.expect(!rules.isRunnerSource("build_identity_rules.zig"));
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: test runner, property, driver and pipeline sources are runner sources" {
    try std.testing.expect(rules.isRunnerSource("core/test_runner_execute.zig"));
    try std.testing.expect(rules.isRunnerSource("core/test_runner.zig"));
    try std.testing.expect(rules.isRunnerSource("core/property_execute.zig"));
    try std.testing.expect(rules.isRunnerSource("core/driver.zig"));
    try std.testing.expect(rules.isRunnerSource("core/pipeline.zig"));
    try std.testing.expect(rules.isRunnerSource("memory_budget.zig"));
    try std.testing.expect(rules.isRunnerSource("core/test_builder.zig"));
    try std.testing.expect(rules.isRunnerSource("core/unit_cache.zig"));
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: test-only sources are in neither identity" {
    try std.testing.expect(rules.isTestOnly("core/test_runner_test.zig"));
    try std.testing.expect(rules.isTestOnly("core/test_support.zig"));
    try std.testing.expect(rules.isTestOnly("stdlib_fixture.zig"));
    try std.testing.expect(!rules.isRunnerSource("core/test_runner_test.zig"));
    try std.testing.expect(!rules.isRunnerSource("core/test_support.zig"));
    try std.testing.expect(!rules.isRunnerSource("core/property_campaign_receipt_test.zig"));
    try std.testing.expect(!rules.isTestOnly("core/test_runner.zig"));
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: runner inputs are the sorted runner subset" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sources: rules.Sources = .empty;
    try sources.put(a, "parser.zig", parser_text);
    try sources.put(a, "memory_budget.zig", "");
    try sources.put(a, "core/test_runner.zig", "");
    try sources.put(a, "core/driver.zig", "");
    const covered = try rules.sortedPaths(a, sources, &rules.isRunnerSource);
    try std.testing.expectEqual(@as(usize, 3), covered.len);
    try std.testing.expectEqualStrings("core/driver.zig", covered[0]);
    try std.testing.expectEqualStrings("core/test_runner.zig", covered[1]);
    try std.testing.expectEqualStrings("memory_budget.zig", covered[2]);
    try std.testing.expectEqual(@as(usize, 4), (try rules.sortedPaths(a, sources, null)).len);
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: a front-end edit moves the compiler identity and leaves the runner identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try digests(arena.allocator(), parser_text, runner_text);
    const edited = try digests(arena.allocator(), parser_text ++ "// edited\n", runner_text);
    try std.testing.expect(!std.mem.eql(u8, &base.compiler, &edited.compiler));
    try std.testing.expectEqualStrings(&base.runner, &edited.runner);
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: a runner edit moves both identities" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try digests(arena.allocator(), parser_text, runner_text);
    const edited = try digests(arena.allocator(), parser_text, runner_text ++ "// edited\n");
    try std.testing.expect(!std.mem.eql(u8, &base.compiler, &edited.compiler));
    try std.testing.expect(!std.mem.eql(u8, &base.runner, &edited.runner));
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: digests are deterministic and the two identities differ" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const first = try digests(arena.allocator(), parser_text, runner_text);
    const second = try digests(arena.allocator(), parser_text, runner_text);
    try std.testing.expectEqualStrings(&first.compiler, &second.compiler);
    try std.testing.expectEqualStrings(&first.runner, &second.runner);
    try std.testing.expect(!std.mem.eql(u8, &first.compiler, &first.runner));
}

// spec-case: RUNNER-IDENTITY-1
test "build_identity: the compiler identity keeps the value the pre-runner tool computed" {
    // The pre-runner `build_identity.zig` (main 4892aaba4), run on a directory
    // holding these four files with ZIG_VERSION `0.0.0-test` and OPTIMIZE `Debug`,
    // wrote this `compiler_identity`. Every cache on the machine is keyed by it,
    // so moving the digest here must not change it.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try digests(arena.allocator(), parser_text, runner_text);
    try std.testing.expectEqualStrings("15ee04c920eddf62539001a1477fb433f4a30e7f14b548ff10026788214d1322", &base.compiler);
}
