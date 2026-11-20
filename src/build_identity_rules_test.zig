//! The build-time identities' source selection and digest (`build_identity_rules.zig`),
//! exercised on synthetic in-memory sources.
const std = @import("std");
const rules = @import("build_identity_rules.zig");

const toolchain: rules.Toolchain = .{ .zig_version = "0.0.0-test", .optimize = "Debug" };

/// The identity of one synthetic tree.
const Digests = struct { compiler: [64]u8 };

/// The compiler identity over a synthetic tree of a front-end file, an emitter file and
/// two runner files, the front-end file holding `parser` and the trial executor
/// holding `runner`.
fn digests(a: std.mem.Allocator, parser: []const u8, runner: []const u8) !Digests {
    var sources: rules.Sources = .empty;
    try sources.put(a, "parser.zig", parser);
    try sources.put(a, "core/emit_llvm.zig", "pub const emit = 1;\n");
    try sources.put(a, "core/test_runner_execute.zig", runner);
    try sources.put(a, "memory_budget.zig", "pub const limit = 4;\n");
    const all = try rules.sortedPaths(a, sources, null);
    return .{ .compiler = try rules.digest(a, rules.compiler_domain, toolchain, sources, all) };
}

const parser_text = "pub const parsed = true;\n";
const runner_text = "pub const trials = 1;\n";

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: test-only sources are not production sources" {
    try std.testing.expect(rules.isTestOnly("core/test_runner_test.zig"));
    try std.testing.expect(rules.isTestOnly("core/test_support.zig"));
    try std.testing.expect(rules.isTestOnly("stdlib_fixture.zig"));
    try std.testing.expect(rules.isTestOnly("core/property_campaign_receipt_test.zig"));
    try std.testing.expect(!rules.isTestOnly("core/test_runner.zig"));
}

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: digests are deterministic, and an edit of any production source moves the identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const first = try digests(arena.allocator(), parser_text, runner_text);
    const second = try digests(arena.allocator(), parser_text, runner_text);
    try std.testing.expectEqualStrings(&first.compiler, &second.compiler);
    const front = try digests(arena.allocator(), parser_text ++ "pub const edited = true;\n", runner_text);
    const runner = try digests(arena.allocator(), parser_text, runner_text ++ "pub const edited = true;\n");
    try std.testing.expect(!std.mem.eql(u8, &first.compiler, &front.compiler));
    try std.testing.expect(!std.mem.eql(u8, &first.compiler, &runner.compiler));
}

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: the compiler identity of four fixed files keeps its pinned value" {
    // Pins the token-based definition of COMPILER-IDENTITY-TOKENS-1 (domain v3): the
    // identity of these four files with ZIG_VERSION `0.0.0-test` and OPTIMIZE `Debug`.
    // Every cache keyed by `compiler_identity` goes cold when this value moves, so
    // moving it must be deliberate and come with a new domain tag. (The rename to `selka` moved it: every domain tag changed.)
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const base = try digests(arena.allocator(), parser_text, runner_text);
    try std.testing.expectEqualStrings("fac7931af7ca050cae52187956466624822f961546d76728f003f27bb3457f38", &base.compiler);
}

/// The identity of a synthetic tree whose front-end file is `parser` and whose
/// runtime C file is `runtime`.
fn digestsWithRuntime(a: std.mem.Allocator, parser: []const u8, runtime: []const u8) !Digests {
    var sources: rules.Sources = .empty;
    try sources.put(a, "parser.zig", parser);
    try sources.put(a, "core/runtime/rt.c", runtime);
    try sources.put(a, "core/test_runner_execute.zig", runner_text);
    const all = try rules.sortedPaths(a, sources, null);
    return .{ .compiler = try rules.digest(a, rules.compiler_domain, toolchain, sources, all) };
}

fn expectSameIdentity(a: std.mem.Allocator, left: []const u8, right: []const u8) !void {
    const first = try digests(a, left, runner_text);
    const second = try digests(a, right, runner_text);
    try std.testing.expectEqualStrings(&first.compiler, &second.compiler);
}

fn expectDifferentIdentity(a: std.mem.Allocator, left: []const u8, right: []const u8) !void {
    const first = try digests(a, left, runner_text);
    const second = try digests(a, right, runner_text);
    try std.testing.expect(!std.mem.eql(u8, &first.compiler, &second.compiler));
}

// spec: COMPILER-IDENTITY-TOKENS-1
test "build_identity: comments, doc comments and layout of a Zig source leave the identity unchanged" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectSameIdentity(a, parser_text, "// leading comment\n" ++ parser_text ++ "// trailing comment, no newline");
    try expectSameIdentity(a, parser_text, "//! module doc\n/// doc comment\npub const parsed = true; // why\n");
    try expectSameIdentity(a, parser_text, "pub   const parsed\n    =\n  true\n;\n\n\n");
    try expectSameIdentity(a, parser_text, "pub const parsed = true;\r\n");
    try expectSameIdentity(a, "const s = \"a\"; //x", "const s = \"a\"; ////y\n");
}

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: any change of a token moves the identity, including inside literals that look like comments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectDifferentIdentity(a, parser_text, "pub const parsed = false;\n");
    try expectDifferentIdentity(a, parser_text, "pub const parse = true;\n");
    try expectDifferentIdentity(a, "pub const s = \"a // b\";\n", "pub const s = \"a // c\";\n");
    try expectDifferentIdentity(a, "pub const s = \"a\";\n", "pub const s = \"a \";\n");
    try expectDifferentIdentity(a, "pub const s =\n    \\\\one\n;\n", "pub const s =\n    \\\\two\n;\n");
    try expectDifferentIdentity(a, "pub const s =\n    \\\\one\n;\n", "pub const s =\n    \\\\one \n;\n");
    try expectDifferentIdentity(a, "pub const c = 'a';\n", "pub const c = 'b';\n");
    try expectDifferentIdentity(a, "pub const n = 1;\n", "pub const n = 2;\n");
    try expectDifferentIdentity(a, "pub const n = 1 + 2;\n", "pub const n = 1 - 2;\n");
}

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: a file that is not Zig is digested as its bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try digestsWithRuntime(a, parser_text, "int rt(void) { return 1; }\n");
    const commented = try digestsWithRuntime(a, parser_text, "int rt(void) { return 1; } /* why */\n");
    const spaced = try digestsWithRuntime(a, parser_text, "int rt(void) {  return 1; }\n");
    try std.testing.expect(!std.mem.eql(u8, &base.compiler, &commented.compiler));
    try std.testing.expect(!std.mem.eql(u8, &base.compiler, &spaced.compiler));
    const again = try digestsWithRuntime(a, parser_text, "int rt(void) { return 1; }\n");
    try std.testing.expectEqualStrings(&base.compiler, &again.compiler);
}

/// Sources of a synthetic tree: each entry is a path relative to `src` and its bytes.
fn treeOf(a: std.mem.Allocator, entries: []const [2][]const u8) !rules.Sources {
    var sources: rules.Sources = .empty;
    for (entries) |entry| try sources.put(a, entry[0], entry[1]);
    return sources;
}

test "stage closure: follows file-scope and function-body imports transitively and skips an unreferenced file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\nfn f() void { _ = @import(\"d.zig\"); }\n" },
        .{ "core/b.zig", "const c = @import(\"c.zig\");\n" },
        .{ "core/c.zig", "pub const v = 1;\n" },
        .{ "d.zig", "pub const d = 1;\n" },
        .{ "unused.zig", "pub const u = 1;\n" },
    });
    const paths = try rules.closure(a, sources, &.{"compiler.zig"});
    try std.testing.expectEqual(@as(usize, 4), paths.len);
    try std.testing.expectEqualStrings("compiler.zig", paths[0]);
    try std.testing.expectEqualStrings("core/b.zig", paths[1]);
    try std.testing.expectEqualStrings("core/c.zig", paths[2]);
    try std.testing.expectEqualStrings("d.zig", paths[3]);
}

test "stage closure: an import inside a test declaration is not followed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{
        .{ "compiler.zig", "pub const x = 1;\ntest \"only a test\" {\n    _ = @import(\"helper.zig\");\n}\n" },
        .{ "helper.zig", "pub const h = 1;\n" },
    });
    const paths = try rules.closure(a, sources, &.{"compiler.zig"});
    try std.testing.expectEqual(@as(usize, 1), paths.len);
    try std.testing.expectEqualStrings("compiler.zig", paths[0]);
}

test "stage closure: named modules and embedded files resolve; a comment spelling an import is not an edge" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{
        .{ "core/driver.zig", "// const g = @import(\"ghost.zig\");\nconst m = @import(\"selka\");\nconst n = @embedFile(\"core_number_text_object\");\nconst d = @embedFile(\"data.selka\");\n" },
        .{ "compiler.zig", "pub const c = 1;\n" },
        .{ "core/runtime/core_number_text.zig", "pub const t = 1;\n" },
        .{ "core/data.selka", "fn main() {}\n" },
    });
    const paths = try rules.closure(a, sources, &.{"core/driver.zig"});
    try std.testing.expectEqual(@as(usize, 4), paths.len);
    try std.testing.expectEqualStrings("compiler.zig", paths[0]);
    try std.testing.expectEqualStrings("core/data.selka", paths[1]);
    try std.testing.expectEqualStrings("core/driver.zig", paths[2]);
    try std.testing.expectEqualStrings("core/runtime/core_number_text.zig", paths[3]);
}

test "stage closure refuses a non-literal import, an unknown module, a test-only import, and a missing path" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const computed = try treeOf(a, &.{.{ "compiler.zig", "const name = \"b.zig\";\nconst b = @import(name);\n" }});
    try std.testing.expectError(error.NonLiteralImport, rules.closure(a, computed, &.{"compiler.zig"}));
    const unknown = try treeOf(a, &.{.{ "compiler.zig", "const x = @import(\"nosuch\");\n" }});
    try std.testing.expectError(error.UnknownModule, rules.closure(a, unknown, &.{"compiler.zig"}));
    const testonly = try treeOf(a, &.{
        .{ "compiler.zig", "const t = @import(\"test_support.zig\");\n" },
        .{ "test_support.zig", "pub const s = 1;\n" },
    });
    try std.testing.expectError(error.TestOnlyImport, rules.closure(a, testonly, &.{"compiler.zig"}));
    const missing = try treeOf(a, &.{.{ "compiler.zig", "const g = @import(\"gone.zig\");\n" }});
    try std.testing.expectError(error.MissingSource, rules.closure(a, missing, &.{"compiler.zig"}));
}

test "stage identity: a file in the closure moves it, a comment does not, a file outside does not, and the chain carries the upstream" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\n" },
        .{ "core/b.zig", "pub const v = 1;\n" },
        .{ "core/other.zig", "pub const o = 1;\n" },
    });
    const edited = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\n" },
        .{ "core/b.zig", "pub const v = 2;\n" },
        .{ "core/other.zig", "pub const o = 1;\n" },
    });
    const commented = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\n" },
        .{ "core/b.zig", "// why\npub const v = 1;\n" },
        .{ "core/other.zig", "pub const o = 1;\n" },
    });
    const outside = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\n" },
        .{ "core/b.zig", "pub const v = 1;\n" },
        .{ "core/other.zig", "pub const o = 2;\n" },
    });
    const roots = [_][]const u8{"compiler.zig"};
    const before = try rules.digestChained(a, rules.stage_domain, toolchain, "", base, try rules.closure(a, base, &roots));
    const moved = try rules.digestChained(a, rules.stage_domain, toolchain, "", edited, try rules.closure(a, edited, &roots));
    const same = try rules.digestChained(a, rules.stage_domain, toolchain, "", commented, try rules.closure(a, commented, &roots));
    const unrelated = try rules.digestChained(a, rules.stage_domain, toolchain, "", outside, try rules.closure(a, outside, &roots));
    try std.testing.expect(!std.mem.eql(u8, &before, &moved));
    try std.testing.expectEqualStrings(&before, &same);
    try std.testing.expectEqualStrings(&before, &unrelated);
    const chained = try rules.digestChained(a, rules.stage_domain, toolchain, &before, base, try rules.closure(a, base, &roots));
    try std.testing.expect(!std.mem.eql(u8, &before, &chained));
}

test "stage closure refuses a file that does not parse" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const broken = try treeOf(a, &.{.{ "compiler.zig", "pub const = ;\n" }});
    try std.testing.expectError(error.ParseFailed, rules.closure(a, broken, &.{"compiler.zig"}));
}

test "stage names and stage roots line up, in pipeline order" {
    try std.testing.expectEqual(rules.stage_names.len, rules.stage_roots.len);
    try std.testing.expectEqualStrings("front", rules.stage_names[0]);
    try std.testing.expectEqualStrings("emit", rules.stage_names[3]);
    try std.testing.expectEqualStrings("test-runner", rules.stage_names[rules.stage_names.len - 1]);
}

test "the test-runner stage chains from lower, and the other stages chain from the stage before them" {
    try std.testing.expectEqual(@as(?usize, null), rules.stage_upstream[0]);
    try std.testing.expectEqual(@as(?usize, 0), rules.stage_upstream[1]);
    try std.testing.expectEqual(@as(?usize, 1), rules.stage_upstream[2]);
    try std.testing.expectEqual(@as(?usize, 2), rules.stage_upstream[3]);
    try std.testing.expectEqual(@as(?usize, 1), rules.stage_upstream[4]);
}

test "a test-runner stage moves with lower and with its own files, and an emitter edit leaves it as it was" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const runner_roots = &.{"core/test_runner_facts.zig"};
    const lower_roots = &.{"core/lowering_cache.zig"};
    const base = try treeOf(a, &.{
        .{ "core/test_runner_facts.zig", "const l = @import(\"lowering_cache.zig\");\npub const f = 1;\n" },
        .{ "core/lowering_cache.zig", "pub const lower = 1;\n" },
        .{ "core/emit_llvm.zig", "pub const emit = 1;\n" },
    });
    const emitted = try treeOf(a, &.{
        .{ "core/test_runner_facts.zig", "const l = @import(\"lowering_cache.zig\");\npub const f = 1;\n" },
        .{ "core/lowering_cache.zig", "pub const lower = 1;\n" },
        .{ "core/emit_llvm.zig", "pub const emit = 2;\n" },
    });
    const facts = try treeOf(a, &.{
        .{ "core/test_runner_facts.zig", "const l = @import(\"lowering_cache.zig\");\npub const f = 2;\n" },
        .{ "core/lowering_cache.zig", "pub const lower = 1;\n" },
        .{ "core/emit_llvm.zig", "pub const emit = 1;\n" },
    });
    const lowered = try treeOf(a, &.{
        .{ "core/test_runner_facts.zig", "const l = @import(\"lowering_cache.zig\");\npub const f = 1;\n" },
        .{ "core/lowering_cache.zig", "pub const lower = 2;\n" },
        .{ "core/emit_llvm.zig", "pub const emit = 1;\n" },
    });
    const lower_digest = try rules.digestChained(a, rules.stage_domain, toolchain, "", base, try rules.closure(a, base, lower_roots));
    const identity = try testRunnerIdentity(a, lower_digest, base, runner_roots);
    try std.testing.expectEqualStrings(&identity, &try testRunnerIdentity(a, lower_digest, emitted, runner_roots));
    try std.testing.expect(!std.mem.eql(u8, &identity, &try testRunnerIdentity(a, lower_digest, facts, runner_roots)));
    const lowered_digest = try rules.digestChained(a, rules.stage_domain, toolchain, "", lowered, try rules.closure(a, lowered, lower_roots));
    try std.testing.expect(!std.mem.eql(u8, &lower_digest, &lowered_digest));
    try std.testing.expect(!std.mem.eql(u8, &identity, &try testRunnerIdentity(a, lowered_digest, lowered, runner_roots)));
}

/// The test-runner stage identity of `sources` chained from `upstream` (the lower stage's digest of `lower_sources`).
fn testRunnerIdentity(a: std.mem.Allocator, upstream: [64]u8, sources: rules.Sources, roots: []const []const u8) ![64]u8 {
    return rules.digestChained(a, rules.stage_domain, toolchain, &upstream, sources, try rules.closure(a, sources, roots));
}

test "the real test-runner closure is free of the emitter: its roots reach no emit_llvm.zig" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer directory.close(io);
    var sources: rules.Sources = .empty;
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or rules.isTestOnly(entry.path)) continue;
        try sources.put(a, try a.dupe(u8, entry.path), try directory.readFileAlloc(io, entry.path, a, .unlimited));
    }
    const closure = try rules.closure(a, sources, rules.stage_roots[rules.stage_roots.len - 1]);
    try std.testing.expect(!contains(closure, "core/emit_llvm.zig"));
    try std.testing.expect(contains(closure, "core/test_runner_graph.zig"));
    try std.testing.expect(contains(closure, "core/lowering_cache.zig"));
}

test "the optimizer stage's identity covers both checks a final record's validated bit stands for" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var directory = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer directory.close(io);
    var sources: rules.Sources = .empty;
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or rules.isTestOnly(entry.path)) continue;
        try sources.put(a, try a.dupe(u8, entry.path), try directory.readFileAlloc(io, entry.path, a, .unlimited));
    }
    // A final record's key binds the `opt` stage identity: a compiler whose ownership validator or IR verifier differs keys its
    // records apart, so a record one of them validated is never served to the other as validated (`passes.validatedFinal`).
    try std.testing.expectEqualStrings("opt", rules.stage_names[2]);
    const closure = try rules.closure(a, sources, rules.stage_roots[2]);
    try std.testing.expect(contains(closure, "core/passes.zig"));
    try std.testing.expect(contains(closure, "core/validate_ownership.zig"));
    try std.testing.expect(contains(closure, "core/ownership_export.zig"));
    try std.testing.expect(contains(closure, "core/verify_ir.zig"));
}

/// Whether `paths` holds `needle`.
fn contains(paths: []const []const u8, needle: []const u8) bool {
    for (paths) |path| if (std.mem.eql(u8, path, needle)) return true;
    return false;
}

/// An embedded number-text object digested from `bytes`, standing for one build of it.
fn objectBuiltAs(bytes: []const u8) rules.Embedded {
    return .{ .name = "core_number_text_object", .digest = rules.productDigest(bytes) };
}

/// `toolchain` with `products` embedded.
fn embedding(products: []const rules.Embedded) rules.Toolchain {
    return .{ .zig_version = toolchain.zig_version, .optimize = toolchain.optimize, .products = products };
}

// spec-case: COMPILER-IDENTITY-TOKENS-1
test "build_identity: the bytes of an embedded product move the compiler identity and the same bytes do not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{.{ "parser.zig", parser_text }});
    const paths = try rules.sortedPaths(a, sources, null);
    const baseline = [_]rules.Embedded{objectBuiltAs("object built for the baseline cpu")};
    const skylake = [_]rules.Embedded{objectBuiltAs("object built for the skylake cpu")};
    const bare = try rules.digest(a, rules.compiler_domain, toolchain, sources, paths);
    const before = try rules.digest(a, rules.compiler_domain, embedding(&baseline), sources, paths);
    const again = try rules.digest(a, rules.compiler_domain, embedding(&.{objectBuiltAs("object built for the baseline cpu")}), sources, paths);
    const after = try rules.digest(a, rules.compiler_domain, embedding(&skylake), sources, paths);
    // A build of the product with other settings is a different compiler; a rebuild with the same bytes is not.
    try std.testing.expectEqualStrings(&before, &again);
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
    try std.testing.expect(!std.mem.eql(u8, &before, &bare));
    // A comment in a Zig source still moves nothing, with a product in the digest.
    const commented = try treeOf(a, &.{.{ "parser.zig", "// why\n" ++ parser_text }});
    try std.testing.expectEqualStrings(&before, &try rules.digest(a, rules.compiler_domain, embedding(&baseline), commented, try rules.sortedPaths(a, commented, null)));
    // With no products the digested text is what it was before products existed (the pinned value above stays).
    try std.testing.expectEqualStrings(&bare, &try rules.digest(a, rules.compiler_domain, embedding(&.{}), sources, paths));
}

test "build_identity: a stage carries an embedded product exactly when its closure reaches the embed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{
        .{ "compiler.zig", "const b = @import(\"core/b.zig\");\n" },
        .{ "core/b.zig", "pub const v = 1;\n" },
        .{ "core/emit_units.zig", "pub const object = @embedFile(\"core_number_text_object\");\n" },
        .{ "core/runtime/core_number_text.zig", "pub const n = 1;\n" },
    });
    const front = try rules.closure(a, sources, &.{"compiler.zig"});
    const emit = try rules.closure(a, sources, &.{"core/emit_units.zig"});
    const baseline = [_]rules.Embedded{objectBuiltAs("baseline")};
    const skylake = [_]rules.Embedded{objectBuiltAs("skylake")};
    try std.testing.expectEqual(@as(usize, 0), (try rules.reachedProducts(a, &baseline, front)).len);
    try std.testing.expectEqual(@as(usize, 1), (try rules.reachedProducts(a, &baseline, emit)).len);
    const front_before = try rules.digestChained(a, rules.stage_domain, embedding(try rules.reachedProducts(a, &baseline, front)), "", sources, front);
    const front_after = try rules.digestChained(a, rules.stage_domain, embedding(try rules.reachedProducts(a, &skylake, front)), "", sources, front);
    const emit_before = try rules.digestChained(a, rules.stage_domain, embedding(try rules.reachedProducts(a, &baseline, emit)), "", sources, emit);
    const emit_after = try rules.digestChained(a, rules.stage_domain, embedding(try rules.reachedProducts(a, &skylake, emit)), "", sources, emit);
    try std.testing.expectEqualStrings(&front_before, &front_after);
    try std.testing.expect(!std.mem.eql(u8, &emit_before, &emit_after));
}

test "build_identity: the products a build supplies must be exactly the ones named_files marks" {
    const object = objectBuiltAs("object");
    try rules.checkProducts(&.{object});
    try std.testing.expectError(error.MissingProduct, rules.checkProducts(&.{}));
    try std.testing.expectError(error.UnknownProduct, rules.checkProducts(&.{ object, .{ .name = "selka", .digest = rules.productDigest("x") } }));
    try std.testing.expectError(error.UnknownProduct, rules.checkProducts(&.{ object, .{ .name = "no_such_module", .digest = rules.productDigest("x") } }));
}

/// Every production source of the real `src`, relative to it.
fn realSources(a: std.mem.Allocator, io: std.Io) !rules.Sources {
    var directory = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer directory.close(io);
    var sources: rules.Sources = .empty;
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or rules.isTestOnly(entry.path)) continue;
        try sources.put(a, try a.dupe(u8, entry.path), try directory.readFileAlloc(io, entry.path, a, .unlimited));
    }
    return sources;
}

/// The engine kinds' identities over `sources`, each chained from the kinds before it.
fn engineIdentities(a: std.mem.Allocator, sources: rules.Sources) ![rules.engine_kinds.len][64]u8 {
    var out: [rules.engine_kinds.len][64]u8 = undefined;
    var earlier: [rules.engine_kinds.len][]const u8 = undefined;
    for (rules.engine_kinds, 0..) |_, index| {
        out[index] = try rules.engineKindIdentity(a, toolchain, sources, index, earlier[0..index]);
        earlier[index] = &out[index];
    }
    return out;
}

/// Sources for the engine kinds: each kind's root imports the engine's context, and the probe imports the digest module.
fn engineSources(a: std.mem.Allocator, context_text: []const u8, probe_text: []const u8) !rules.Sources {
    var sources: rules.Sources = .empty;
    try sources.put(a, "core/engine/context.zig", context_text);
    try sources.put(a, "core/engine/digest.zig", "pub const hash = 1;\n");
    try sources.put(a, "core/engine/kinds/probe.zig", probe_text);
    try sources.put(a, "core/engine/kinds/probe_size.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/probe_class.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/test_exec.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/module_tokens.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/test_report.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/module_syntax.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/project_graph.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/module_interface.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/module_check.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/noalloc_closure.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/module_passes.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/program_diagnostics.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/unit_lower.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/program_facts.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/unit_optimize.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/unit_emit.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/ownership_proof.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/test_facts.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "core/engine/kinds/test_graph.zig", "const c = @import(\"../context.zig\");\n");
    try sources.put(a, "unrelated.zig", "pub const x = 1;\n");
    // The files a kind covers and its boundary are leaves; a test replaces one to give it imports.
    for (rules.engine_kinds) |kind| {
        for ([_][]const []const u8{ kind.covers, kind.boundary }) |files| {
            for (files) |path| if (!sources.contains(path)) try sources.put(a, path, "pub const leaf = 1;\n");
        }
    }
    return sources;
}

const base_probe = "const c = @import(\"../context.zig\");\nconst d = @import(\"../digest.zig\");\n";

test "an engine kind's identity ignores comments and layout, and moves with a token of its closure" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try engineIdentities(a, try engineSources(a, "pub const x = 1;\n", base_probe));
    const commented = try engineIdentities(a, try engineSources(a, "// a note\npub  const x   =  1;\n", base_probe));
    const edited = try engineIdentities(a, try engineSources(a, "pub const x = 2;\n", base_probe));
    for (base, commented, edited) |was, same, moved| {
        try std.testing.expectEqualStrings(&was, &same);
        try std.testing.expect(!std.mem.eql(u8, &was, &moved));
    }
    try std.testing.expect(!std.mem.eql(u8, &base[0], &base[1]));
    try std.testing.expect(!std.mem.eql(u8, &base[1], &base[2]));
}

/// The engine kinds' identities over the base sources with `changes` (a path and its new text) applied.
fn identitiesAfter(a: std.mem.Allocator, changes: []const [2][]const u8) ![rules.engine_kinds.len][64]u8 {
    var sources = try engineSources(a, "pub const x = 1;\n", base_probe);
    for (changes) |change| try sources.put(a, change[0], change[1]);
    return engineIdentities(a, sources);
}

const test_exec_index = kindIndex("test-exec");
const test_report_index = kindIndex("test-report");

/// The position of the engine kind called `name` in `rules.engine_kinds`.
fn kindIndex(comptime name: []const u8) usize {
    inline for (rules.engine_kinds, 0..) |kind, index| if (comptime std.mem.eql(u8, kind.name, name)) return index;
    @compileError("no engine kind " ++ name);
}

/// Whether exactly the kind at `index` has another identity in `after` than in `base`.
fn onlyMoved(base: [rules.engine_kinds.len][64]u8, after: [rules.engine_kinds.len][64]u8, index: usize) bool {
    for (base, after, 0..) |was, now, at| if (std.mem.eql(u8, &was, &now) == (at == index)) return false;
    return true;
}

test "an engine kind's identity moves with a file it covers, and the kinds that do not cover it stay put" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try identitiesAfter(a, &.{});
    const spawn = try identitiesAfter(a, &.{.{ "core/process_spawn.zig", "pub const leaf = 2;\n" }});
    const compiler = try identitiesAfter(a, &.{.{ "compiler.zig", "pub const leaf = 2;\n" }});
    try std.testing.expect(onlyMoved(base, spawn, test_exec_index));
    try std.testing.expect(onlyMoved(base, compiler, test_report_index));
    const commented = try identitiesAfter(a, &.{.{ "core/process_spawn.zig", "// a note\npub  const leaf   =  1;\n" }});
    try std.testing.expectEqualStrings(&base[test_exec_index], &commented[test_exec_index]);
}

const front_setup = [_][2][]const u8{
    .{ "core/test_runner_execute.zig", "const typed = @import(\"selka\").typed;\nconst early = @import(\"selka\");\nconst sema_alias = early.sema;\n" },
    .{ "compiler.zig", "pub const typed = @import(\"typed.zig\");\npub const sema = @import(\"sema.zig\");\npub const lexer = @import(\"lexer.zig\");\n" },
    .{ "typed.zig", "pub const t = 1;\n" },
    .{ "sema.zig", "pub const s = 1;\n" },
    .{ "lexer.zig", "pub const l = 1;\n" },
};

/// The test-exec and test-report identities after `member` of the front end module (or none) gains a token.
fn afterMemberEdit(a: std.mem.Allocator, member: []const u8) ![2][64]u8 {
    const edited = try identitiesAfter(a, &(front_setup ++ [_][2][]const u8{.{ member, "pub const t = 2;\n" }}));
    return .{ edited[test_exec_index], edited[test_report_index] };
}

test "a kind that covers the runner follows the front end module by the members it names" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try identitiesAfter(a, &front_setup);
    const typed = try afterMemberEdit(a, "typed.zig");
    const sema = try afterMemberEdit(a, "sema.zig");
    // A member the runner does not name is not in its closure; the plan, which covers the whole module, does follow it.
    const lexer = try afterMemberEdit(a, "lexer.zig");
    try std.testing.expect(!std.mem.eql(u8, &base[test_exec_index], &typed[0]));
    try std.testing.expect(!std.mem.eql(u8, &base[test_exec_index], &sema[0]));
    try std.testing.expectEqualStrings(&base[test_exec_index], &lexer[0]);
    try std.testing.expect(!std.mem.eql(u8, &base[test_report_index], &lexer[1]));
}

test "an engine kind's code is the closure of its roots alone, which is what the access scan reads" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try engineSources(a, "pub const x = 1;\n", base_probe);
    const code = try rules.engineKindCode(a, sources, rules.engine_kinds[test_exec_index]);
    const covered = try rules.engineKindClosure(a, sources, rules.engine_kinds[test_exec_index]);
    try std.testing.expect(contains(code, "core/engine/kinds/test_exec.zig"));
    try std.testing.expect(!contains(code, "core/process_spawn.zig"));
    try std.testing.expect(contains(covered, "core/process_spawn.zig"));
}

test "a boundary file joins a kind's identity by its own tokens and its imports are not followed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const setup = [_][2][]const u8{
        .{ "core/test_runner_execute.zig", "const options = @import(\"test_runner_options.zig\");\n" },
        .{ "core/test_runner_options.zig", "const deep = @import(\"deep.zig\");\n" },
        .{ "deep.zig", "pub const d = 1;\n" },
    };
    const base = try identitiesAfter(a, &setup);
    const deeper = try identitiesAfter(a, &(setup ++ [_][2][]const u8{.{ "deep.zig", "pub const d = 2;\n" }}));
    const edited = try identitiesAfter(a, &(setup ++ [_][2][]const u8{.{ "core/test_runner_options.zig", "const deep = @import(\"deep.zig\");\nconst e = 1;\n" }}));
    try std.testing.expectEqualStrings(&base[test_exec_index], &deeper[test_exec_index]);
    try std.testing.expect(!std.mem.eql(u8, &base[test_exec_index], &edited[test_exec_index]));
}

test "an engine kind chains from the kinds upstream of it, so an edit to the probe moves the kinds built on it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try engineIdentities(a, try engineSources(a, "pub const x = 1;\n", base_probe));
    const probe_edited = try engineIdentities(a, try engineSources(a, "pub const x = 1;\n", base_probe ++ "const e = 1;\n"));
    // Neither later probe kind imports the probe's file, but both chain from it; the test kinds chain from no probe.
    for (base, probe_edited, 0..) |was, moved, index| try std.testing.expectEqual(index < test_exec_index, !std.mem.eql(u8, &was, &moved));
}

test "an engine kind's closure refuses a non-literal import, as a stage's does" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try engineSources(a, "pub const x = 1;\n", "const name = \"x.zig\";\nconst c = @import(name);\n");
    try std.testing.expectError(error.NonLiteralImport, rules.engineKindIdentity(a, toolchain, sources, 0, &.{}));
}

/// Every production source under `src`, read from the working directory.
fn productionSources(a: std.mem.Allocator) !rules.Sources {
    const io = std.testing.io;
    var directory = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer directory.close(io);
    var sources: rules.Sources = .empty;
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or rules.isTestOnly(entry.path)) continue;
        try sources.put(a, try a.dupe(u8, entry.path), try directory.readFileAlloc(io, entry.path, a, .unlimited));
    }
    return sources;
}

/// How many of `products` the real stage called `stage` embeds.
fn embeddedBy(a: std.mem.Allocator, sources: rules.Sources, stage: usize, products: []const rules.Embedded) !usize {
    return (try rules.reachedProducts(a, products, try rules.closure(a, sources, rules.stage_roots[stage]))).len;
}

test "the real tree: the emit stage embeds the number-text object and the front end does not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try realSources(a, std.testing.io);
    const object = [_]rules.Embedded{objectBuiltAs("object")};
    try std.testing.expectEqualStrings("front", rules.stage_names[0]);
    try std.testing.expectEqualStrings("emit", rules.stage_names[3]);
    try std.testing.expectEqual(@as(usize, 0), try embeddedBy(a, sources, 0, &object));
    try std.testing.expectEqual(@as(usize, 1), try embeddedBy(a, sources, 3, &object));
}

test "an engine kind carries no embedded product its closure does not reach" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try engineSources(a, "pub const x = 1;\n", base_probe);
    const bare = try rules.engineKindIdentity(a, toolchain, sources, 0, &.{});
    const baseline = try rules.engineKindIdentity(a, embedding(&.{objectBuiltAs("baseline")}), sources, 0, &.{});
    const skylake = try rules.engineKindIdentity(a, embedding(&.{objectBuiltAs("skylake")}), sources, 0, &.{});
    // The probe's closure never reaches the number-text embed, so a rebuilt object leaves its records valid.
    try std.testing.expectEqualStrings(&bare, &baseline);
    try std.testing.expectEqualStrings(&baseline, &skylake);
}

test "the engine kinds' real closures stay clear of the compiler and name the context" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try productionSources(a);
    for (rules.engine_kinds) |kind| {
        const closure = try rules.closure(a, sources, kind.roots);
        try std.testing.expect(contains(closure, "core/engine/context.zig"));
        try std.testing.expect(!contains(closure, "compiler.zig"));
        try std.testing.expect(!contains(closure, "core/engine/engine.zig"));
    }
}

/// Every source of `sources` analyzed once (`rules.analyze`), in the same order.
fn factsOf(a: std.mem.Allocator, gpa: std.mem.Allocator, sources: rules.Sources) !rules.Facts {
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var facts: rules.Facts = .empty;
    for (sources.keys(), sources.values()) |path, bytes| try facts.put(a, path, try rules.analyze(a, &scratch, path, bytes));
    return facts;
}

/// The closure of `roots` under `options` over one form of a tree, or the error that refused it, as text.
fn closureText(a: std.mem.Allocator, corpus: rules.Corpus, roots: []const []const u8, options: rules.ClosureOptions) ![]const u8 {
    const paths = rules.closureIn(a, corpus, roots, options) catch |err| return @errorName(err);
    return std.mem.join(a, "\n", paths);
}

/// Every identity and closure the tool writes, over one form of a tree, as one text: the compiler identity, each stage's
/// closure and identity, and each engine kind's closures and identity (or the error that refused each).
fn identitiesText(a: std.mem.Allocator, corpus: rules.Corpus) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    const all = try corpus.sortedPaths(a);
    const compiler = rules.digestChainedIn(a, rules.compiler_domain, toolchain, "", corpus, all) catch |err| {
        try w.print("compiler {s}\n", .{@errorName(err)});
        return text.written();
    };
    try w.print("compiler {s}\n", .{&compiler});
    for (rules.stage_roots) |roots| {
        try w.print("stage {s}\n", .{try closureText(a, corpus, roots, .{})});
        const closure = rules.closureIn(a, corpus, roots, .{}) catch continue;
        try w.print("digest {s}\n", .{&try rules.digestChainedIn(a, rules.stage_domain, toolchain, "", corpus, closure)});
    }
    var earlier: [rules.engine_kinds.len][]const u8 = undefined;
    for (rules.engine_kinds, 0..) |kind, index| {
        const options: rules.ClosureOptions = .{ .walk = .members, .boundary = kind.boundary };
        const covered = try closureText(a, corpus, try std.mem.concat(a, []const u8, &.{ kind.roots, kind.covers }), options);
        try w.print("kind {s}\n{s}\n", .{ covered, try closureText(a, corpus, kind.roots, options) });
        const identity = rules.engineKindIdentityIn(a, toolchain, corpus, index, earlier[0..index]) catch |err| {
            earlier[index] = @errorName(err);
            try w.print("identity {s}\n", .{earlier[index]});
            continue;
        };
        earlier[index] = try a.dupe(u8, &identity);
        try w.print("identity {s}\n", .{earlier[index]});
    }
    return text.written();
}

/// The identities of `sources` read from bytes, from bytes parsed in freed scratch memory and from facts analyzed once:
/// the three must be the same text. (The real `src` is compared by `tests/compiler_identity_cache.py --only real`, whose
/// tool needs 4 s and 31 MB for it; the bytes form in a Debug test binary with an arena needed 25 s and 1.5 GB.)
fn expectSameIdentities(a: std.mem.Allocator, gpa: std.mem.Allocator, sources: rules.Sources) !void {
    const facts = try factsOf(a, gpa, sources);
    const from_bytes = try identitiesText(a, .{ .bytes = &sources });
    try std.testing.expectEqualStrings(from_bytes, try identitiesText(a, .{ .parsed = .{ .sources = &sources, .scratch = gpa } }));
    try std.testing.expectEqualStrings(from_bytes, try identitiesText(a, .{ .facts = &facts }));
}

test "build identity facts: refusals and front end member uses come out of facts as they come out of bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const member_root = "pub const typed = @import(\"typed.zig\");\npub const sema = @import(\"sema.zig\");\npub const typed = @import(\"typed2.zig\");\n";
    const trees = [_][]const [2][]const u8{
        &.{ .{ "compiler.zig", member_root }, .{ "typed.zig", "x" }, .{ "typed2.zig", "y" }, .{ "sema.zig", "const m = @import(\"selka\");\nconst t = m.typed;\n" } },
        &.{
            .{ "compiler.zig", member_root },
            .{ "typed2.zig", "y" },
            .{ "a.zig", "const m = @import(\"selka\");\nfn f() void { g(m); }\n" },
            .{ "core/engine/kinds/probe.zig", "const x = @import(\"selka\").typed;\nconst y = @import(\"selka\").nothing;\n" },
        },
        &.{ .{ "compiler.zig", "pub const = ;" }, .{ "core/engine/kinds/probe.zig", "const x = @import(\"selka\").typed;\n" } },
        &.{ .{ "compiler.zig", "const x = @import(name);\n" }, .{ "core/engine/kinds/probe.zig", "const x = @import(\"selka\");\n" } },
        &.{ .{ "compiler.zig", "const x = @import(\"no_such_module\");\n" }, .{ "core/engine/kinds/probe.zig", "const x = @embedFile(\"../../runtime/rt.c\");\n" }, .{ "core/runtime/rt.c", "int f;" } },
        &.{ .{ "compiler.zig", "const x = @import(\"sema_test.zig\");\ntest { _ = @import(\"gone.zig\"); }\n" }, .{ "sema_test.zig", "" } },
        &.{.{ "compiler.zig", "const x = @import(\"missing.zig\");\nconst y = @import(\"std\");\nconst z = @embedFile(\"core_number_text_object\");\n" }},
        &.{ .{ "core/engine/kinds/probe.zig", "const p = @import(\"../../../outside.zig\");\nconst q = @import(\"./same.zon\");\n" }, .{ "outside.zig", "" }, .{ "core/engine/kinds/same.zon", ".{}" } },
    };
    for (trees) |entries| try expectSameIdentities(a, std.testing.allocator, try treeOf(a, entries));
}

/// A record's entries holding one file's facts, as the tool would write them.
fn oneEntry(a: std.mem.Allocator) !rules.RecordEntries {
    var entries: rules.RecordEntries = .empty;
    try entries.put(a, "compiler.zig", .{
        .content = rules.contentKey("pub const typed = @import(\"typed.zig\");\n"),
        .facts = .{ .digest = @splat(7), .edges = &.{"a.zig"}, .member_edges = &.{}, .member_names = &.{"typed"}, .member_use = .whole, .member_table = &.{.{ "typed", "typed.zig" }} },
    });
    try entries.put(a, "core/runtime/rt.c", .{
        .content = rules.contentKey("int f;\n"),
        .facts = .{ .digest = @splat(9), .refusal = .unknown_module },
    });
    return entries;
}

const record_header: rules.RecordHeader = .{ .tool = @splat(1), .root = "/tree/src" };

/// `header` with one field changed by `edit`.
fn headerWith(edit: enum { tool, root }) rules.RecordHeader {
    var header = record_header;
    switch (edit) {
        .tool => header.tool[31] = 2,
        .root => header.root = "/other/src",
    }
    return header;
}

/// `bytes` with the byte at `index` changed.
fn flipped(a: std.mem.Allocator, bytes: []const u8, index: usize) ![]const u8 {
    const out = try a.dupe(u8, bytes);
    out[index] ^= 0x40;
    return out;
}

test "build identity record: a whole record for this tool and tree decodes to the entries written" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = try oneEntry(a);
    const bytes = try rules.encodeRecord(a, record_header, &entries);
    const decoded = (try rules.decodeRecord(a, bytes, record_header)).?;
    try std.testing.expectEqual(@as(usize, 2), decoded.count());
    const first = decoded.get("compiler.zig").?;
    try std.testing.expectEqualSlices(u8, &entries.get("compiler.zig").?.content, &first.content);
    try std.testing.expectEqualSlices(u8, &entries.get("compiler.zig").?.facts.digest, &first.facts.digest);
    try std.testing.expectEqualStrings("typed.zig", first.facts.member_table[0][1]);
    try std.testing.expectEqual(rules.MemberUse.whole, first.facts.member_use);
    try std.testing.expectEqual(rules.Refusal.unknown_module, decoded.get("core/runtime/rt.c").?.facts.refusal.?);
}

test "build identity record: a record of another tool or tree, or a truncated or damaged one, decodes to nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = try oneEntry(a);
    const bytes = try rules.encodeRecord(a, record_header, &entries);
    try std.testing.expect((try rules.decodeRecord(a, bytes, headerWith(.tool))) == null);
    try std.testing.expect((try rules.decodeRecord(a, bytes, headerWith(.root))) == null);
    try std.testing.expect((try rules.decodeRecord(a, bytes[0 .. bytes.len - 1], record_header)) == null);
    try std.testing.expect((try rules.decodeRecord(a, bytes[0 .. bytes.len / 2], record_header)) == null);
    try std.testing.expect((try rules.decodeRecord(a, "", record_header)) == null);
    try std.testing.expect((try rules.decodeRecord(a, try flipped(a, bytes, bytes.len / 2), record_header)) == null);
    try std.testing.expect((try rules.decodeRecord(a, try flipped(a, bytes, bytes.len - 1), record_header)) == null);
}

test "build identity record: an entry stands only for the bytes it was computed from" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const entry = (try oneEntry(arena.allocator())).get("compiler.zig").?;
    try std.testing.expect(rules.recordServes(entry, rules.contentKey("pub const typed = @import(\"typed.zig\");\n")));
    // One byte changed in place, as a write through a shared mapping does without moving the file's times.
    try std.testing.expect(!rules.recordServes(entry, rules.contentKey("pub const typed = @import(\"typeD.zig\");\n")));
    try std.testing.expect(!rules.recordServes(entry, rules.contentKey("pub const typed = @import(\"typed.zig\");\n ")));
    try std.testing.expect(!rules.recordServes(entry, rules.contentKey("")));
}

test "build identity record: the tool key moves with the tool's sources and its Zig, and a record has a size bound" {
    const key = rules.recordToolKey("0.0.0-test", &.{ "tool", "rules" });
    try std.testing.expectEqualSlices(u8, &key, &rules.recordToolKey("0.0.0-test", &.{ "tool", "rules" }));
    try std.testing.expect(!std.mem.eql(u8, &key, &rules.recordToolKey("0.0.1-test", &.{ "tool", "rules" })));
    try std.testing.expect(!std.mem.eql(u8, &key, &rules.recordToolKey("0.0.0-test", &.{ "tool", "rules " })));
    try std.testing.expect(!std.mem.eql(u8, &key, &rules.recordToolKey("0.0.0-test", &.{ "toolr", "ules" })));
    try std.testing.expect(rules.max_record_bytes >= 64 << 20);
}

test "build identity facts: a refused compiler.zig still resolves member uses as its bytes do" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // compiler.zig parses but refuses its own edges (an unknown module); its member table is still the one `memberFiles`
    // builds, so the probe's member use is an edge to typed.zig, not to the whole module.
    const sources = try treeOf(a, &.{
        .{ "compiler.zig", "pub const typed = @import(\"typed.zig\");\nconst x = @import(\"no_such_module\");\n" },
        .{ "typed.zig", "pub const t = 1;\n" },
        .{ "core/engine/kinds/probe.zig", "const t = @import(\"selka\").typed;\n" },
    });
    const facts = try factsOf(a, std.testing.allocator, sources);
    const roots = [_][]const u8{"core/engine/kinds/probe.zig"};
    const from_bytes = try closureText(a, .{ .bytes = &sources }, &roots, .{ .walk = .members });
    try std.testing.expectEqualStrings("core/engine/kinds/probe.zig\ntyped.zig", from_bytes);
    try std.testing.expectEqualStrings(from_bytes, try closureText(a, .{ .facts = &facts }, &roots, .{ .walk = .members }));
}

test "build identity facts: the parsed form frees each file's parse and gives the identities of the bytes form" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = try treeOf(a, &.{
        .{ "compiler.zig", "pub const typed = @import(\"typed.zig\");\nconst b = @import(\"core/b.zig\");\n" },
        .{ "typed.zig", "pub const t = @embedFile(\"core/runtime/rt.c\");\n" },
        .{ "core/b.zig", "fn f() void {\n    _ = @import(\"../typed.zig\");\n}\n" },
        .{ "core/runtime/rt.c", "int f;\n" },
        .{ "core/engine/kinds/probe.zig", "const t = @import(\"selka\").typed;\nconst m = @import(\"selka\");\nconst s = m.nothing;\n" },
    });
    // The testing allocator fails the test on any parse the parsed form leaves behind.
    const parsed: rules.Corpus = .{ .parsed = .{ .sources = &sources, .scratch = std.testing.allocator } };
    const roots = [_][]const u8{ "compiler.zig", "core/engine/kinds/probe.zig" };
    try std.testing.expectEqualStrings(try closureText(a, .{ .bytes = &sources }, &roots, .{ .walk = .members }), try closureText(a, parsed, &roots, .{ .walk = .members }));
    try std.testing.expectEqualStrings(try closureText(a, .{ .bytes = &sources }, &roots, .{}), try closureText(a, parsed, &roots, .{}));
    try std.testing.expectEqualStrings(try identitiesText(a, .{ .bytes = &sources }), try identitiesText(a, parsed));
}
