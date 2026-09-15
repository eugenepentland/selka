//! Unit coverage for the Wave-3 invalidation report: synthetic receipts keep
//! the comparison independent of the real compiler and cache layout.
const std = @import("std");
const t = std.testing;
const invalidation = @import("invalidation.zig");

const declaration_function_kind = "function";

const Import = struct { module: []const u8, alias: []const u8 };
const Input = struct { module: []const u8, path: []const u8, sha256: []const u8, bytes: usize = 10, imports: []const Import = &.{} };
const Declaration = struct { name: []const u8, kind: []const u8, identity: []const u8, body_sha256: ?[]const u8 = null };
const Module = struct { name: []const u8, identity: []const u8, declarations: []const Declaration };
const Implementation = struct {
    compiler_sha256: []const u8,
    zig_version: []const u8,
    architecture: []const u8,
    os: []const u8,
    abi: []const u8,
    optimize: []const u8,
};
const Incremental = struct {
    version: []const u8 = "incremental-identities-v1",
    project_interface_sha256: []const u8,
    modules: []const Module,
    specializations: ?[]const []const u8 = null,
    fragments: ?[]const []const u8 = null,
};
const Document = struct {
    version: []const u8 = "project-dependencies-v1",
    complete: bool = true,
    entry: []const u8 = "main",
    implementation: Implementation,
    inputs: []const Input,
    manifests: []const []const u8 = &.{},
    incremental: Incremental,
    runtime_abi: ?[]const u8 = null,
    target: ?[]const u8 = null,
};

const Options = struct {
    compiler_sha: []const u8 = "compiler-a",
    zig_version: []const u8 = "0.17.0-dev",
    architecture: []const u8 = "x86_64",
    os: []const u8 = "linux",
    abi: []const u8 = "gnu",
    optimize: []const u8 = "Debug",
    main_sha: []const u8 = "sha-main",
    data_sha: []const u8 = "sha-data",
    main_path: []const u8 = "main.my",
    data_path: []const u8 = "data.my",
    main_identity: []const u8 = "id-main",
    data_identity: []const u8 = "id-data",
    interface_sha: []const u8 = "interface-a",
    main_body: []const u8 = "body-main-main",
    value_body: []const u8 = "body-data-value",
    helper_body: []const u8 = "body-data-helper",
    value_identity: []const u8 = "decl-data-value",
    helper_identity: []const u8 = "decl-data-helper",
    specialization_a: []const u8 = "data::value@i64",
    specialization_b: []const u8 = "data::helper@i64",
    fragment_a: []const u8 = "data::value",
    fragment_b: []const u8 = "data::helper",
    runtime_abi: []const u8 = "abi-v1",
    target: []const u8 = "x86_64-linux",
    include_runtime_abi: bool = true,
    include_target: bool = true,
    include_specializations: bool = true,
    include_fragments: bool = true,
};

fn buildDoc(arena: std.mem.Allocator, options: Options) ![]u8 {
    const main_declarations = try arena.alloc(Declaration, 1);
    main_declarations[0] = .{ .name = "main", .kind = declaration_function_kind, .identity = "decl-main-main", .body_sha256 = options.main_body };

    const data_declarations = try arena.alloc(Declaration, 2);
    data_declarations[0] = .{ .name = "value", .kind = declaration_function_kind, .identity = options.value_identity, .body_sha256 = options.value_body };
    data_declarations[1] = .{ .name = "helper", .kind = declaration_function_kind, .identity = options.helper_identity, .body_sha256 = options.helper_body };

    const modules = try arena.alloc(Module, 2);
    modules[0] = .{ .name = "main", .identity = options.main_identity, .declarations = main_declarations };
    modules[1] = .{ .name = "data", .identity = options.data_identity, .declarations = data_declarations };

    const inputs = try arena.alloc(Input, 2);
    inputs[0] = .{ .module = "main", .path = options.main_path, .sha256 = options.main_sha };
    inputs[1] = .{ .module = "data", .path = options.data_path, .sha256 = options.data_sha };

    var specializations: ?[]const []const u8 = null;
    if (options.include_specializations) {
        const values = try arena.alloc([]const u8, 2);
        values[0] = options.specialization_a;
        values[1] = options.specialization_b;
        specializations = values;
    }

    var fragments: ?[]const []const u8 = null;
    if (options.include_fragments) {
        const values = try arena.alloc([]const u8, 2);
        values[0] = options.fragment_a;
        values[1] = options.fragment_b;
        fragments = values;
    }

    const document: Document = .{
        .implementation = .{
            .compiler_sha256 = options.compiler_sha,
            .zig_version = options.zig_version,
            .architecture = options.architecture,
            .os = options.os,
            .abi = options.abi,
            .optimize = options.optimize,
        },
        .inputs = inputs,
        .incremental = .{
            .project_interface_sha256 = options.interface_sha,
            .modules = modules,
            .specializations = specializations,
            .fragments = fragments,
        },
        .runtime_abi = if (options.include_runtime_abi) options.runtime_abi else null,
        .target = if (options.include_target) options.target else null,
    };

    return std.json.Stringify.valueAlloc(arena, document, .{ .emit_null_optional_fields = false });
}

const all_executed: [std.meta.tags(invalidation.Stage).len]bool = @splat(true);

fn explain(allocator: std.mem.Allocator, previous: ?[]const u8, current: []const u8) !invalidation.Explanation {
    return invalidation.explain(allocator, previous, current, &all_executed);
}

fn queryFor(explanation: invalidation.Explanation, stage: invalidation.Stage) invalidation.Query {
    for (explanation.queries) |query| if (query.stage == stage) return query;
    unreachable;
}

fn expectHit(explanation: invalidation.Explanation, stage: invalidation.Stage) !void {
    try t.expectEqual(invalidation.Status.hit, queryFor(explanation, stage).status);
}

fn expectMiss(explanation: invalidation.Explanation, stage: invalidation.Stage, first_changed: []const u8) !void {
    const query = queryFor(explanation, stage);
    try t.expectEqual(invalidation.Status.miss, query.status);
    try t.expectEqualStrings(first_changed, query.first_changed.?);
}

fn expectAllMiss(explanation: invalidation.Explanation, first_changed: []const u8) !void {
    try t.expectEqual(@as(usize, 0), explanation.hits);
    for (std.meta.tags(invalidation.Stage)) |stage| try expectMiss(explanation, stage, first_changed);
}

// spec: INVALIDATION-REPORT-1
test "invalidation identical receipts hit every stage" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{});
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try t.expectEqual(@as(usize, 9), explanation.hits);
    try t.expectEqual(@as(usize, 0), explanation.misses);
    for (std.meta.tags(invalidation.Stage)) |stage| try expectHit(explanation, stage);
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation source hash misses load and lex but not interface or body" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .data_sha = "sha-data-b" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try expectMiss(explanation, .load_source, "module:data");
    try expectMiss(explanation, .lex_parse, "module:data");
    try expectHit(explanation, .resolve_interface);
    try expectHit(explanation, .check_body);
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation interface hash misses resolve while module and body stay hit" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .interface_sha = "interface-b" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try expectHit(explanation, .load_source);
    try expectHit(explanation, .lex_parse);
    try expectHit(explanation, .collect_declarations);
    try expectMiss(explanation, .resolve_interface, "interface");
    try expectHit(explanation, .check_body);
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation private body misses check_body and lowering for that declaration" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .helper_body = "body-data-helper-b" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try expectMiss(explanation, .check_body, "module:data::helper");
    try expectHit(explanation, .resolve_interface);
    // Lowering consumes the checked body, so a body edit must invalidate it.
    try expectMiss(explanation, .lower_function, "helper");
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation compiler identity misses load and link" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .compiler_sha = "compiler-b" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try expectMiss(explanation, .load_source, "compiler");
    try expectMiss(explanation, .link, "compiler");
    try expectHit(explanation, .lex_parse);
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation runtime ABI change misses link only" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .runtime_abi = "abi-v2" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    try expectMiss(explanation, .link, "runtime-abi");
    try expectHit(explanation, .load_source);
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation missing and corrupt baselines miss every stage without error" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const current = try buildDoc(arena, .{});

    var no_baseline = try explain(t.allocator, null, current);
    defer no_baseline.deinit(t.allocator);
    try expectAllMiss(no_baseline, "no-baseline");

    var corrupt = try explain(t.allocator, "{not json", current);
    defer corrupt.deinit(t.allocator);
    try expectAllMiss(corrupt, "corrupt-baseline");
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation covers declaration, specialization, function, fragment and toolchain stages" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});

    {
        const current = try buildDoc(arena, .{ .data_identity = "id-data-b" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .collect_declarations, "module:data");
    }
    {
        const current = try buildDoc(arena, .{ .specialization_a = "data::value@i32" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .instantiate_specialization, "data::value@i32");
    }
    {
        const current = try buildDoc(arena, .{ .value_identity = "decl-data-value-b" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .lower_function, "value");
    }
    {
        const current = try buildDoc(arena, .{ .fragment_a = "data::value-v2" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .emit_fragment, "data::value");
    }
    {
        const current = try buildDoc(arena, .{ .target = "aarch64-linux" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .link, "target");
    }
    {
        const current = try buildDoc(arena, .{ .zig_version = "0.18.0-dev" });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .link, "toolchain");
    }
    {
        const current = try buildDoc(arena, .{ .include_specializations = false });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .instantiate_specialization, "absent");
    }
    {
        const current = try buildDoc(arena, .{ .include_fragments = false });
        var explanation = try explain(t.allocator, previous, current);
        defer explanation.deinit(t.allocator);
        try expectMiss(explanation, .emit_fragment, "absent");
    }
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation explain rejects InvalidCurrent and allMiss baseline is covered" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const current = try buildDoc(arena, .{});
    try t.expectError(error.InvalidCurrent, invalidation.explain(t.allocator, null, "{not json", &all_executed));
    var explanation = try explain(t.allocator, null, current);
    explanation.deinit(t.allocator);
}

// spec-case: INVALIDATION-REPORT-1
// spec: INVALIDATION-BASELINE-1
// spec-case: INVALIDATION-EXECUTION-1
test "skipped stages are never reported as reuse and a structurally empty baseline is corrupt" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .data_sha = "sha-data-b" });
    var executed: [std.meta.tags(invalidation.Stage).len]bool = @splat(true);
    executed[@backingInt(invalidation.Stage.lower_function)] = false;
    executed[@backingInt(invalidation.Stage.emit_fragment)] = false;
    executed[@backingInt(invalidation.Stage.link)] = false;
    var explanation = try invalidation.explain(t.allocator, previous, current, &executed);
    defer explanation.deinit(t.allocator);
    try t.expectEqual(@as(usize, 3), explanation.skipped);
    try t.expectEqual(invalidation.Status.skipped, queryFor(explanation, .lower_function).status);
    try t.expectEqual(invalidation.Status.skipped, queryFor(explanation, .emit_fragment).status);
    try t.expectEqual(invalidation.Status.skipped, queryFor(explanation, .link).status);
    try t.expect(queryFor(explanation, .load_source).status == .miss);

    // `{}` parses as JSON but is not a receipt: it must be treated as corrupt, not
    // silently compared into hits.
    var corrupt = try invalidation.explain(t.allocator, "{}", current, &all_executed);
    defer corrupt.deinit(t.allocator);
    try t.expectEqual(@as(usize, 0), corrupt.hits);
    try t.expectEqual(@as(usize, 9), corrupt.misses);
    for (std.meta.tags(invalidation.Stage)) |stage| try expectMiss(corrupt, stage, "corrupt-baseline");

    // A changed body hash invalidates lowering, since lowering consumes the body.
    const body_changed = try buildDoc(arena, .{ .value_body = "body-data-value-2" });
    var changed = try invalidation.explain(t.allocator, previous, body_changed, &all_executed);
    defer changed.deinit(t.allocator);
    try expectMiss(changed, .check_body, "module:data::value");
    try expectMiss(changed, .lower_function, "value");
}

// spec-case: INVALIDATION-REPORT-1
test "invalidation render emits all stages in order with the version" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const previous = try buildDoc(arena, .{});
    const current = try buildDoc(arena, .{ .data_sha = "sha-data-b" });
    var explanation = try explain(t.allocator, previous, current);
    defer explanation.deinit(t.allocator);
    const rendered = try invalidation.render(t.allocator, explanation);
    defer t.allocator.free(rendered);

    try t.expect(std.mem.indexOf(u8, rendered, "\"version\":\"invalidation-report-v1\"") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, rendered, .{});
    defer parsed.deinit();
    const queries = parsed.value.object.get("queries").?.array.items;
    try t.expectEqual(@as(usize, 9), queries.len);
    const expected = std.meta.tags(invalidation.Stage);
    for (queries, 0..) |query, index| {
        try t.expectEqualStrings(@tagName(expected[index]), query.object.get("stage").?.string);
    }
}
